-- Executed after bootstrap.sql and the migration in an isolated PostgreSQL DB.
\set ON_ERROR_STOP on
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
select public.memo_sync('[
 {"id":"00000000-0000-4000-8000-000000000001","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"create","value":{"title":"Read","done":false}},
 {"id":"00000000-0000-4000-8000-000000000002","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"attempt","value":{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","at":"2026-10-07T10:00:00.000Z"}}
]');
do $$ begin
  assert jsonb_array_length(public.memo_sync()) = 1, 'missing task';
  assert jsonb_array_length(public.memo_sync()->0->'attempts') = 1, 'missing attempt';
  begin
    insert into public.memo_tasks(owner,id,title) values (auth.uid(), gen_random_uuid(), 'Bypass');
    raise exception 'Direct writes were allowed';
  exception when insufficient_privilege then null;
  end;
end $$;
-- Two device edits affect different fields and add distinct attempts.
select public.memo_sync('[
 {"id":"00000000-0000-4000-8000-000000000003","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"title","value":"Read more"},
 {"id":"00000000-0000-4000-8000-000000000004","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"done","value":true},
 {"id":"00000000-0000-4000-8000-000000000005","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"attempt","value":{"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","at":"2026-10-07T11:00:00.000Z"}}
]');
-- Lost response: replaying an old operation cannot revert the newer title.
select public.memo_sync('[
 {"id":"00000000-0000-4000-8000-000000000003","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"title","value":"Unexpected retry"},
 {"id":"00000000-0000-4000-8000-000000000002","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"attempt","value":{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","at":"2026-10-07T10:00:00.000Z"}}
]');
do $$ declare data jsonb := public.memo_sync(); begin
  assert data->0->>'title' = 'Read more', 'retry reverted title';
  assert (data->0->>'done')::boolean, 'field edit lost completion';
  assert jsonb_array_length(data->0->'attempts') = 2, 'attempts not merged/deduplicated';
end $$;
-- Removed attempts stay removed even if another device imports an old copy.
select public.memo_sync('[
 {"id":"00000000-0000-4000-8000-000000000006","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"remove_attempt","value":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"},
 {"id":"00000000-0000-4000-8000-000000000007","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"attempt","value":{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","at":"2026-10-07T10:00:00.000Z"}}
]');
do $$ begin assert jsonb_array_length(public.memo_sync()->0->'attempts') = 1; end $$;
-- Another account cannot see, edit, or delete A's data, even using its task IDs.
set request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';
do $$ begin
  assert public.memo_sync() = '[]'::jsonb;
  assert (select count(*) from public.memo_tasks) = 0, 'RLS exposed another account';
  assert (select count(*) from public.memo_attempts) = 0, 'RLS exposed attempts';
end $$;
select public.memo_sync('[
 {"id":"00000000-0000-4000-8000-000000000001","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"title","value":"Account B"},
 {"id":"00000000-0000-4000-8000-000000000002","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"delete","value":null}
]');
set request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
do $$ begin assert public.memo_sync()->0->>'title' = 'Read more'; end $$;
-- Whole batch rolls back on an invalid command, including the deduplication IDs.
do $$ begin
  begin
    perform public.memo_sync('[
      {"id":"00000000-0000-4000-8000-000000000008","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"title","value":"Should roll back"},
      {"id":"00000000-0000-4000-8000-000000000009","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"bogus","value":null}
    ]');
    raise exception 'Invalid command unexpectedly succeeded';
  exception when raise_exception then
    if sqlerrm <> 'Unknown operation' then raise; end if;
  end;
  assert public.memo_sync()->0->>'title' = 'Read more', 'partial batch committed';
end $$;
-- Deletion wins over subsequent stale edits, attempts, and creation/import.
select public.memo_sync('[
 {"id":"00000000-0000-4000-8000-000000000008","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"delete","value":null},
 {"id":"00000000-0000-4000-8000-000000000010","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"create","value":{"title":"Resurrected","done":false}},
 {"id":"00000000-0000-4000-8000-000000000011","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"title","value":"Resurrected"},
 {"id":"00000000-0000-4000-8000-000000000012","task_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","kind":"attempt","value":{"id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","at":"2026-10-07T12:00:00.000Z"}}
]');
do $$ begin assert public.memo_sync() = '[]'::jsonb, 'deleted task resurrected'; end $$;
-- Both missing auth and anonymous execution are denied.
set request.jwt.claim.sub = '';
do $$ begin
  begin perform public.memo_sync(); raise exception 'Unauthenticated call succeeded';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
set role anon;
do $$ begin
  begin perform public.memo_sync(); raise exception 'Anonymous call succeeded';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'All sync SQL assertions passed' as result;
-- Aggregated snapshots are not truncated by a REST table's default 1,000-row cap.
insert into public.memo_tasks(owner, id, title)
select '11111111-1111-4111-8111-111111111111', gen_random_uuid(), 'Task ' || n
from generate_series(1, 1001) n;
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
do $$ begin assert jsonb_array_length(public.memo_sync()) = 1001, 'snapshot truncated'; end $$;
reset role;
