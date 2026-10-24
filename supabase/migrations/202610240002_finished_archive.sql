-- Run after 202610240001_priority_order.sql. No task or attempt history is removed.
begin;
alter table public.memo_tasks
  add column completed_at timestamptz,
  add column archived_at timestamptz;
-- Existing completed tasks get a full 30-day grace period from this upgrade.
update public.memo_tasks set completed_at = now() where done;
alter table public.memo_tasks add constraint memo_task_lifecycle check (
  (done and completed_at is not null) or
  (not done and completed_at is null and archived_at is null)
);

-- Keep legacy completion writes coherent without changing their RPC contract.
create function public.memo_task_completion_dates() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not new.done then
    new.completed_at := null;
    new.archived_at := null;
  elsif new.completed_at is null then
    new.completed_at := now();
  end if;
  return new;
end;
$$;
revoke all on function public.memo_task_completion_dates() from public, anon, authenticated;
create trigger memo_task_completion_dates before insert or update on public.memo_tasks
for each row execute function public.memo_task_completion_dates();

create function public.memo_sync_v3(operations jsonb default '[]'::jsonb)
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
      when 'archive' then
        if jsonb_typeof(payload->'completed_at') is distinct from 'string' or
           jsonb_typeof(payload->'archived_at') is distinct from 'string' then
          raise exception 'Invalid archive';
        end if;
        -- A delayed archive must not finish a task reopened on another device.
        update public.memo_tasks set archived_at = (payload->>'archived_at')::timestamptz
          where owner = account and id = task and not deleted and done
            and completed_at = (payload->>'completed_at')::timestamptz;
      when 'lifecycle' then
        if jsonb_typeof(payload->'done') is distinct from 'boolean' or
           not (payload ? 'completed_at') or not (payload ? 'archived_at') or
           jsonb_typeof(payload->'completed_at') not in ('null', 'string') or
           jsonb_typeof(payload->'archived_at') not in ('null', 'string') then
          raise exception 'Invalid lifecycle';
        end if;
        if (not (payload->>'done')::boolean and
            (payload->>'completed_at' is not null or payload->>'archived_at' is not null)) or
           (payload->>'archived_at' is not null and payload->>'completed_at' is null) then
          raise exception 'Invalid lifecycle timestamps';
        end if;
        update public.memo_tasks set done = (payload->>'done')::boolean,
          completed_at = (payload->>'completed_at')::timestamptz,
          archived_at = (payload->>'archived_at')::timestamptz
          where owner = account and id = task and not deleted;
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
        insert into public.memo_tasks(owner, id, title, done, completed_at, archived_at, priority, position)
        values (account, task, payload->>'title', (payload->>'done')::boolean, (payload->>'completed_at')::timestamptz, (payload->>'archived_at')::timestamptz,
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
    'id', t.id, 'title', t.title, 'done', t.done, 'completed_at', t.completed_at, 'archived_at', t.archived_at, 'priority', t.priority, 'position', t.position,
    'attempts', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'at', a.at) order by a.at, a.id)
      from public.memo_attempts a where a.owner = account and a.task_id = t.id and not a.deleted), '[]'::jsonb)
  ) order by t.priority nulls first, t.position, t.id), '[]'::jsonb)
  into result from public.memo_tasks t where t.owner = account and not t.deleted;
  return result;
end;
$$;
revoke all on function public.memo_sync_v3(jsonb) from public, anon;
grant execute on function public.memo_sync_v3(jsonb) to authenticated;
commit;
