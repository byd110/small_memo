\set ON_ERROR_STOP on
begin;
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
select public.memo_sync_v3('[
 {"id":"20000000-0000-4000-8000-000000000001","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"create","value":{"title":"Archived task","done":true,"completed_at":"2026-09-01T00:00:00Z","priority":1,"position":0}},
 {"id":"20000000-0000-4000-8000-000000000002","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"attempt","value":{"id":"ffffffff-ffff-4fff-8fff-ffffffffffff","at":"2026-08-24T10:00:00Z"}},
 {"id":"20000000-0000-4000-8000-000000000003","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"archive","value":{"completed_at":"2026-09-01T00:00:00Z","archived_at":"2026-10-01T00:00:00Z"}}
]') is not null as created;
do $$ declare t jsonb; begin
  select value into t from jsonb_array_elements(public.memo_sync_v3()) where value->>'id' = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  assert (t->>'done')::boolean and t->>'archived_at' is not null;
  assert (t->>'completed_at')::timestamptz = '2026-09-01T00:00:00Z'::timestamptz;
  assert t->>'priority' = '1' and jsonb_array_length(t->'attempts') = 1;
end $$;
-- Legacy reopen clears dates; a delayed archive and a retried old operation cannot undo it.
select public.memo_sync_v2('[{"id":"20000000-0000-4000-8000-000000000004","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"done","value":false}]') is not null;
select public.memo_sync_v3('[
 {"id":"20000000-0000-4000-8000-000000000005","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"archive","value":{"completed_at":"2026-09-01T00:00:00Z","archived_at":"2026-10-02T00:00:00Z"}},
 {"id":"20000000-0000-4000-8000-000000000003","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"archive","value":{"completed_at":"2026-09-01T00:00:00Z","archived_at":"2026-10-01T00:00:00Z"}}
]') is not null;
do $$ declare t jsonb; begin
  select value into t from jsonb_array_elements(public.memo_sync_v3()) where value->>'id' = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  assert not (t->>'done')::boolean and t->>'archived_at' is null and t->>'completed_at' is null;
  begin
    perform public.memo_sync_v3('[{"id":"20000000-0000-4000-8000-000000000006","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"lifecycle","value":{"done":false,"completed_at":null,"archived_at":"2026-10-01T00:00:00Z"}}]');
    raise exception 'Invalid lifecycle accepted';
  exception when raise_exception then
    if SQLERRM = 'Invalid lifecycle accepted' then raise; end if;
  end;
end $$;
-- Other accounts cannot change or see this task.
set request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';
select public.memo_sync_v3('[{"id":"20000000-0000-4000-8000-000000000007","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"lifecycle","value":{"done":true,"completed_at":"2026-10-01T00:00:00Z","archived_at":null}}]') is not null;
do $$ begin
 assert not exists (select 1 from jsonb_array_elements(public.memo_sync_v3()) t where t->>'id' = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
end $$;
reset role;
rollback;
