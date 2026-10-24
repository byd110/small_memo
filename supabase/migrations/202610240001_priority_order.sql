-- Upgrade an existing personal-sync database. Run after the first migration.
-- Old clients keep using memo_sync; they cannot overwrite these new fields.
begin;
alter table public.memo_tasks
  add column priority integer check (priority >= 1),
  add column position integer not null default 0 check (position >= 0);
with ranked as (
  select owner, id, row_number() over (partition by owner order by created_at, id) - 1 as n
  from public.memo_tasks
)
update public.memo_tasks t set position = ranked.n
from ranked where t.owner = ranked.owner and t.id = ranked.id;

create function public.memo_sync_v2(operations jsonb default '[]'::jsonb)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  account uuid := auth.uid();
  op jsonb;
  task uuid;
  op_id uuid;
  kind text;
  payload jsonb;
  result jsonb;
begin
  if account is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  if jsonb_typeof(operations) <> 'array' or jsonb_array_length(operations) > 100 then
    raise exception 'Expected at most 100 operations';
  end if;
  -- Serialize devices for this account, including empty pulls, for a consistent snapshot.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(account::text, 0));
  for op in select value from jsonb_array_elements(operations) loop
    op_id := (op->>'id')::uuid;
    task := (op->>'task_id')::uuid;
    kind := op->>'kind';
    payload := op->'value';
    if op_id is null or task is null or kind is null then raise exception 'Invalid operation'; end if;
    insert into public.memo_operations(owner, id) values (account, op_id) on conflict do nothing;
    if not found then continue; end if;
    case kind
      when 'placement' then
        if not (payload ? 'priority') or
           (jsonb_typeof(payload->'priority') <> 'null' and
            (jsonb_typeof(payload->'priority') <> 'number' or (payload->>'priority') !~ '^[1-9][0-9]*$')) or
           jsonb_typeof(payload->'position') is distinct from 'number' or
           (payload->>'position') !~ '^[0-9]+$' then
          raise exception 'Invalid placement';
        end if;
        update public.memo_tasks set priority = (payload->>'priority')::integer,
          position = (payload->>'position')::integer
          where owner = account and id = task and not deleted;
      when 'create' then
        if jsonb_typeof(payload->'title') is distinct from 'string' or jsonb_typeof(payload->'done') is distinct from 'boolean' then
          raise exception 'Invalid task';
        end if;
        insert into public.memo_tasks(owner, id, title, done, priority, position)
        values (account, task, payload->>'title', (payload->>'done')::boolean,
          (payload->>'priority')::integer, coalesce((payload->>'position')::integer,
            (select coalesce(max(position), -1) + 1 from public.memo_tasks where owner = account and priority is null and not deleted)))
        on conflict do nothing; -- Never resurrect a previously deleted task.
      when 'title' then
        if jsonb_typeof(payload) is distinct from 'string' then raise exception 'Invalid title'; end if;
        update public.memo_tasks set title = payload #>> '{}' where owner = account and id = task and not deleted;
      when 'done' then
        if jsonb_typeof(payload) is distinct from 'boolean' then raise exception 'Invalid completion'; end if;
        update public.memo_tasks set done = (payload #>> '{}')::boolean where owner = account and id = task and not deleted;
      when 'delete' then
        -- A tombstone also handles a deletion arriving before a retried import.
        insert into public.memo_tasks(owner, id, title, deleted) values (account, task, '(deleted)', true)
        on conflict (owner, id) do update set deleted = true;
      when 'attempt' then
        if exists (select 1 from public.memo_tasks where owner = account and id = task and not deleted) then
          insert into public.memo_attempts(owner, task_id, id, at)
          values (account, task, (payload->>'id')::uuid, (payload->>'at')::timestamptz)
          on conflict do nothing;
        end if;
      when 'remove_attempt' then
        if exists (select 1 from public.memo_tasks where owner = account and id = task and not deleted) then
          insert into public.memo_attempts(owner, task_id, id, deleted)
          values (account, task, (payload #>> '{}')::uuid, true)
          on conflict (owner, task_id, id) do update set deleted = true;
        end if;
      else raise exception 'Unknown operation';
    end case;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'title', t.title, 'done', t.done, 'priority', t.priority, 'position', t.position,
    'attempts', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'at', a.at) order by a.at, a.id)
      from public.memo_attempts a where a.owner = account and a.task_id = t.id and not a.deleted), '[]'::jsonb)
  ) order by t.priority nulls first, t.position, t.id), '[]'::jsonb)
  into result from public.memo_tasks t where t.owner = account and not t.deleted;
  return result;
end;
$$;
revoke all on function public.memo_sync_v2(jsonb) from public, anon;
grant execute on function public.memo_sync_v2(jsonb) to authenticated;
commit;
