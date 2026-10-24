\set ON_ERROR_STOP on
-- Run after sync.sql and the priority migration in a disposable database.
begin;
do $$ begin
  assert (select count(distinct position) from public.memo_tasks where owner = '11111111-1111-4111-8111-111111111111') =
    (select count(*) from public.memo_tasks where owner = '11111111-1111-4111-8111-111111111111'), 'migration lost old ordering';
end $$;
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
select public.memo_sync_v2('[
 {"id":"10000000-0000-4000-8000-000000000001","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"create","value":{"title":"Priority task","done":false,"priority":2,"position":0}},
 {"id":"10000000-0000-4000-8000-000000000002","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"attempt","value":{"id":"ffffffff-ffff-4fff-8fff-ffffffffffff","at":"2026-10-24T10:00:00Z"}},
 {"id":"10000000-0000-4000-8000-000000000003","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"placement","value":{"priority":1,"position":4}}
]') is not null as created;
-- Other fields edited by old clients must preserve priority and ordering.
select public.memo_sync('[
 {"id":"10000000-0000-4000-8000-000000000004","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"title","value":"Legacy title edit"},
 {"id":"10000000-0000-4000-8000-000000000005","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"done","value":true}
]') is not null as legacy_edit;
do $$ declare t jsonb; begin
  select value into t from jsonb_array_elements(public.memo_sync_v2()) where value->>'id' = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  assert t->>'priority' = '1' and t->>'position' = '4';
  assert t->>'title' = 'Legacy title edit' and (t->>'done')::boolean;
  assert jsonb_array_length(t->'attempts') = 1;
end $$;
-- Clearing classification also supplies its destination position, atomically.
select public.memo_sync_v2('[
 {"id":"10000000-0000-4000-8000-000000000006","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"placement","value":{"priority":null,"position":0}},
 {"id":"10000000-0000-4000-8000-000000000003","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"placement","value":{"priority":1,"position":4}}
]') is not null as retried;
do $$ declare t jsonb; begin
  select value into t from jsonb_array_elements(public.memo_sync_v2()) where value->>'id' = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  assert t->'priority' = 'null'::jsonb and t->>'position' = '0', 'retry overwrote the newer placement';
  begin
    perform public.memo_sync_v2('[{"id":"10000000-0000-4000-8000-000000000007","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"placement","value":{"priority":0,"position":0}}]');
    raise exception 'Invalid priority succeeded';
  exception when raise_exception then
    if sqlerrm <> 'Invalid placement' then raise; end if;
  end;
end $$;
-- A different account's placement commands cannot modify this task.
set request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';
select public.memo_sync_v2('[{"id":"10000000-0000-4000-8000-000000000008","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"placement","value":{"priority":99,"position":99}}]') is not null as other_account;
set request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
do $$ begin
 assert (select priority is null and position = 0 from public.memo_tasks where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
end $$;
select public.memo_sync_v2('[
 {"id":"10000000-0000-4000-8000-000000000009","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"delete","value":null},
 {"id":"10000000-0000-4000-8000-000000000010","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"placement","value":{"priority":1,"position":0}}
]') is not null as deletion;
do $$ begin
 assert not exists(select 1 from jsonb_array_elements(public.memo_sync_v2()) where value->>'id' = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
end $$;
reset role;
set role anon;
do $$ begin
 begin perform public.memo_sync_v2(); raise exception 'Anonymous v2 access succeeded';
 exception when insufficient_privilege then null; end;
end $$;
rollback;
select 'Priority migration and sync assertions passed' as result;
