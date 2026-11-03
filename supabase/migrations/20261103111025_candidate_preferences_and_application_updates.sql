-- Optional preferences inherit the existing owner/staff profile policies.
alter table public.candidate_accounts
  add column preferred_work_mode text check (preferred_work_mode in ('Remote','Hybrid','On-site','Flexible')),
  add column preferred_location text check (char_length(preferred_location)<=160),
  add column weekly_hours smallint check (weekly_hours between 1 and 60),
  add column portfolio_url text check (char_length(portfolio_url)<=500);

create table public.candidate_application_events (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.project_applications(id) on delete cascade,
  status text not null check (status in ('submitted','reviewing','shortlisted','client_review','offer','placed','rejected','closed','withdrawn')),
  occurred_at timestamptz not null default now()
);
create index candidate_application_events_application_idx on public.candidate_application_events(application_id,occurred_at);
alter table public.candidate_application_events enable row level security;
revoke all on public.candidate_application_events from public,anon,authenticated;
grant select on public.candidate_application_events to authenticated;
grant all on public.candidate_application_events to service_role;
create policy "Read events for accessible applications" on public.candidate_application_events
for select to authenticated using (
  exists(select 1 from public.project_applications a where a.id=application_id)
);
-- The parent application RLS authorizes the write. Only this trigger writes history;
-- direct candidate/staff history writes are intentionally not granted.
create function private.record_candidate_application_event() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null and coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'An authenticated application update is required';
  end if;
  if auth.uid() is not null and not private.is_benchpro_staff() and not exists(
    select 1 from public.candidate_accounts c where c.id=new.candidate_id and c.user_id=auth.uid()
  ) then raise exception 'Application access denied'; end if;
  if tg_op='INSERT' then
    insert into public.candidate_application_events(application_id,status) values(new.id,new.status);
  elsif new.status is distinct from old.status then
    insert into public.candidate_application_events(application_id,status) values(new.id,new.status);
  end if;
  return new;
end;
$$;
revoke all on function private.record_candidate_application_event() from public,anon,authenticated;
create trigger candidate_application_event after insert or update of status on public.project_applications
for each row execute function private.record_candidate_application_event();
comment on table public.candidate_application_events is 'Candidate-visible status changes recorded from Phase 2 onward. No internal notes or inferred historical stages.';
