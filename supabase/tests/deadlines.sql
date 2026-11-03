\set ON_ERROR_STOP on
begin;
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
select public.memo_sync_v4('[
 {"id":"30000000-0000-4000-8000-000000000001","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"create","value":{"title":"Due task","done":false,"priority":1,"position":0,"deadline":{"at":"2026-07-15T21:00:00.000Z","zone":"America/Toronto"}}},
 {"id":"30000000-0000-4000-8000-000000000002","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"attempt","value":{"id":"ffffffff-ffff-4fff-8fff-ffffffffffff","at":"2026-07-14T10:00:00Z"}}
]') is not null as created;
-- Existing clients can edit other fields without erasing the deadline.
select public.memo_sync_v3('[
 {"id":"30000000-0000-4000-8000-000000000003","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"title","value":"Older client edit"},
 {"id":"30000000-0000-4000-8000-000000000004","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"done","value":true}
]') is not null;
do $$ declare t jsonb; begin
 select value into t from jsonb_array_elements(public.memo_sync_v4()) where value->>'id' = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
 assert (t->'deadline'->>'at')::timestamptz = '2026-07-15T21:00:00Z'::timestamptz;
 assert t->'deadline'->>'zone' = 'America/Toronto';
 assert t->>'title' = 'Older client edit' and (t->>'done')::boolean;
 assert t->>'priority' = '1' and jsonb_array_length(t->'attempts') = 1;
end $$;
select public.memo_sync_v4('[
 {"id":"30000000-0000-4000-8000-000000000005","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"deadline","value":{"at":"2026-11-01T06:30:00.000Z","zone":"America/Toronto"}},
 {"id":"30000000-0000-4000-8000-000000000006","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"deadline","value":null},
 {"id":"30000000-0000-4000-8000-000000000005","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"deadline","value":{"at":"2026-11-01T06:30:00.000Z","zone":"America/Toronto"}}
]') is not null as clear_and_retry;
do $$ declare t jsonb; invalid jsonb; begin
 select value into t from jsonb_array_elements(public.memo_sync_v4()) where value->>'id' = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
 assert t->'deadline' = 'null'::jsonb, 'Retry restored a removed deadline';
 for invalid in select value from jsonb_array_elements('[
  {"at":"2026-11-01T06:30:00Z","zone":"Unknown"},
  {"at":"2026-11-01T06:30:00","zone":"UTC"},
  {"at":"infinity","zone":"UTC"},
  {"at":"2026-11-01T06:30:00Z"},
  {"zone":"UTC"},
  false
 ]'::jsonb) loop
  begin
   perform public.memo_sync_v4(jsonb_build_array(jsonb_build_object('id','30000000-0000-4000-8000-000000000007','task_id','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','kind','deadline','value',invalid)));
   raise exception 'Invalid deadline accepted';
  exception when raise_exception then
   if SQLERRM = 'Invalid deadline accepted' then raise; end if;
  end;
 end loop;
end $$;
-- Account isolation applies to new writes and snapshots as well.
set request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';
select public.memo_sync_v4('[{"id":"30000000-0000-4000-8000-000000000008","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"deadline","value":{"at":"2026-11-01T06:30:00Z","zone":"UTC"}}]') is not null;
do $$ begin
 assert not exists (select 1 from jsonb_array_elements(public.memo_sync_v4()) t where t->>'id' = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
end $$;
set request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
do $$ begin
 assert (select due_at is null from public.memo_tasks where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
end $$;
-- Deletion wins over a later deadline change.
select public.memo_sync_v4('[
 {"id":"30000000-0000-4000-8000-000000000009","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"delete"},
 {"id":"30000000-0000-4000-8000-000000000010","task_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","kind":"deadline","value":{"at":"2026-11-01T06:30:00Z","zone":"UTC"}}
]') is not null;
do $$ begin
 assert not exists (select 1 from jsonb_array_elements(public.memo_sync_v4()) t where t->>'id' = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
end $$;
reset role;
set role anon;
do $$ begin
 begin
  perform public.memo_sync_v4();
  raise exception 'Anonymous sync accepted';
 exception when insufficient_privilege then null;
 end;
end $$;
reset role;
rollback;
