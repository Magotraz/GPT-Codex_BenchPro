create table public.candidate_update_receipts (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  event_id uuid not null references public.candidate_application_events(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key(user_id,event_id)
);
create index candidate_update_receipts_event_idx on public.candidate_update_receipts(event_id);
alter table public.candidate_update_receipts enable row level security;
revoke all on public.candidate_update_receipts from public,anon,authenticated;
grant select on public.candidate_update_receipts to authenticated;
grant insert(user_id,event_id) on public.candidate_update_receipts to authenticated;
grant all on public.candidate_update_receipts to service_role;
create policy "Read own update receipts" on public.candidate_update_receipts
for select to authenticated using(user_id=(select auth.uid()));
create policy "Mark own candidate events read" on public.candidate_update_receipts
for insert to authenticated with check (
  user_id=(select auth.uid()) and exists (
    select 1 from public.candidate_application_events e
    join public.project_applications a on a.id=e.application_id
    join public.candidate_accounts c on c.id=a.candidate_id
    where e.id=event_id and c.user_id=(select auth.uid())
  )
);
comment on table public.candidate_update_receipts is 'Private read receipts for candidate application updates. Only the owning candidate may mark an event as read.';
