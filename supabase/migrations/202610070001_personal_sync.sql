-- Run once in your Supabase SQL Editor. No database password belongs in the app.
begin;

create table public.memo_tasks (
  owner uuid not null references auth.users(id) on delete cascade,
  id uuid not null,
  title text not null check (length(trim(title)) between 1 and 500),
  done boolean not null default false,
  deleted boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (owner, id)
);
create table public.memo_attempts (
  owner uuid not null,
  task_id uuid not null,
  id uuid not null,
  at timestamptz,
  deleted boolean not null default false,
  primary key (owner, task_id, id),
  foreign key (owner, task_id) references public.memo_tasks(owner, id) on delete cascade,
  check (deleted or at is not null)
);
create table public.memo_operations (
  owner uuid not null references auth.users(id) on delete cascade,
  id uuid not null,
  primary key (owner, id)
);

alter table public.memo_tasks enable row level security;
alter table public.memo_attempts enable row level security;
alter table public.memo_operations enable row level security;
create policy own_tasks on public.memo_tasks for select to authenticated using ((select auth.uid()) = owner);
create policy own_attempts on public.memo_attempts for select to authenticated using ((select auth.uid()) = owner);
-- Writes go through the function below; no client may bypass tombstones or deduplication.
revoke all on public.memo_tasks, public.memo_attempts, public.memo_operations from public, anon, authenticated;
grant select on public.memo_tasks, public.memo_attempts to authenticated;

create function public.memo_sync(operations jsonb default '[]'::jsonb)
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
      when 'create' then
        if jsonb_typeof(payload->'title') is distinct from 'string' or jsonb_typeof(payload->'done') is distinct from 'boolean' then
          raise exception 'Invalid task';
        end if;
        insert into public.memo_tasks(owner, id, title, done)
        values (account, task, payload->>'title', (payload->>'done')::boolean)
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
    'id', t.id, 'title', t.title, 'done', t.done,
    'attempts', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'at', a.at) order by a.at, a.id)
      from public.memo_attempts a where a.owner = account and a.task_id = t.id and not a.deleted), '[]'::jsonb)
  ) order by t.created_at, t.id), '[]'::jsonb)
  into result from public.memo_tasks t where t.owner = account and not t.deleted;
  return result;
end;
$$;
revoke all on function public.memo_sync(jsonb) from public, anon;
grant execute on function public.memo_sync(jsonb) to authenticated;
commit;
