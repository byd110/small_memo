\set ON_ERROR_STOP on
-- TEST DATABASE ONLY. Run in a separate empty database. Intentionally omit the
-- priority migration to reproduce a newer RPC installed over an older schema.
\ir bootstrap.sql
\ir ../migrations/202610070001_personal_sync.sql
insert into public.memo_tasks(owner, id, title, done, created_at) values
 ('11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Original task', false, '2026-10-01T10:00:00Z'),
 ('11111111-1111-4111-8111-111111111111', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Finished task', true, '2026-10-02T10:00:00Z');
insert into public.memo_attempts(owner, task_id, id, at) values
 ('11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', '2026-10-01T11:00:00Z');
\ir ../migrations/202610240002_finished_archive.sql
\ir ../migrations/202611030001_deadlines.sql
update public.memo_tasks set due_at = '2026-12-01T22:00:00Z', due_zone = 'America/Toronto'
 where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
update public.memo_tasks set archived_at = now() where done;
create temp table original_tasks as select to_jsonb(t) as data from public.memo_tasks t;
create temp table original_attempts as select to_jsonb(a) as data from public.memo_attempts a;
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
do $$ begin
 begin
  perform public.memo_sync_v4('[{"id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"create","value":{"title":"New task","done":false,"priority":1,"position":2}}]');
  raise exception 'Missing priority did not reproduce';
 exception when undefined_column then
  assert SQLERRM like '%priority%', 'Unexpected missing column';
 end;
end $$;
reset role;
\ir ../repairs/restore_priority_order.sql

do $$ begin
 assert (select count(*) from public.memo_tasks) = 2;
 assert not exists (
  select 1 from original_tasks o where not exists (
   select 1 from public.memo_tasks t where to_jsonb(t) - 'priority' - 'position' = o.data
  )
 ), 'Repair changed existing task data';
 assert not exists (
  select 1 from original_attempts o where not exists (
   select 1 from public.memo_attempts a where to_jsonb(a) = o.data
  )
 ), 'Repair changed attempt history';
 assert (select position = 0 from public.memo_tasks where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
 assert (select position = 1 from public.memo_tasks where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
end $$;
set role authenticated;
select public.memo_sync_v4('[{"id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"create","value":{"title":"New task","done":false,"priority":1,"position":2}}]') is not null as same_operation_retry_succeeded;
select public.memo_sync_v4('[{"id":"ffffffff-ffff-4fff-8fff-ffffffffffff","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"placement","value":{"priority":2,"position":8}}]') is not null as ordering_works;
do $$ begin
 assert jsonb_array_length(public.memo_sync_v4()) = 3;
 assert (select priority = 1 from public.memo_tasks where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
end $$;
reset role;
create temp table repaired_tasks as select to_jsonb(t) as data from public.memo_tasks t;
\ir ../repairs/restore_priority_order.sql
do $$ begin
 assert not exists (
  select 1 from repaired_tasks r where not exists (
   select 1 from public.memo_tasks t where to_jsonb(t) = r.data
  )
 ), 'Repeated repair changed task data or ordering';
end $$;
-- A partial schema might already have positions. Preserve those as well.
alter table public.memo_tasks drop column priority;
\ir ../repairs/restore_priority_order.sql
do $$ begin
 assert (select position = 8 from public.memo_tasks where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'Existing order was overwritten';
 assert not exists (
  select 1 from repaired_tasks r where not exists (
   select 1 from public.memo_tasks t where to_jsonb(t) - 'priority' = r.data - 'priority'
  )
 ), 'Adding priority alone changed other task data';
end $$;
