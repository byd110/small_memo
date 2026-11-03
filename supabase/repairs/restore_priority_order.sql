-- Repair a database that has the newer sync RPCs but missed the priority/order
-- columns. Safe to run again: existing priorities and positions are preserved.
-- Run in the Supabase SQL Editor. Requires the initial personal-sync tables.
begin;

alter table public.memo_tasks
  add column if not exists priority integer check (priority >= 1);

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'memo_tasks'
      and column_name = 'position'
  ) then
    alter table public.memo_tasks
      add column position integer not null default 0 check (position >= 0);
    -- Only initialize ordering when the column was missing; never reorder a
    -- database that already has user-selected positions.
    with ranked as (
      select owner, id,
        row_number() over (partition by owner order by created_at, id) - 1 as n
      from public.memo_tasks
    )
    update public.memo_tasks t set position = ranked.n
    from ranked where t.owner = ranked.owner and t.id = ranked.id;
  end if;
end;
$$;

notify pgrst, 'reload schema';
commit;
