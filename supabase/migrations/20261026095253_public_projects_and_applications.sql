-- Public copy is separate from private staffing requests and uploaded JDs.
create table public.project_listings (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(trim(title)) between 3 and 160),
  category text not null check (category in ('Data & AI','Enterprise platforms','Cloud & platform','Engineering','Other')),
  summary text not null check (char_length(trim(summary)) between 20 and 300),
  description text not null check (char_length(trim(description)) between 30 and 12000),
  responsibilities text[] not null default '{}' check (cardinality(responsibilities) <= 15),
  requirements text[] not null default '{}' check (cardinality(requirements) between 1 and 15),
  skills text[] not null check (cardinality(skills) between 1 and 20),
  work_mode text not null check (work_mode in ('Remote','Hybrid','On-site')),
  location text not null check (char_length(trim(location)) between 2 and 160),
  duration text not null check (char_length(trim(duration)) between 2 and 80),
  experience text not null check (char_length(trim(experience)) between 2 and 80),
  start_window text not null default 'To be discussed' check (char_length(trim(start_window)) between 2 and 120),
  client_display_name text not null default 'Confidential client' check (char_length(trim(client_display_name)) between 2 and 160),
  status text not null default 'draft' check (status in ('draft','published','closed')),
  featured boolean not null default false,
  is_demo boolean not null default false,
  published_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index project_listings_open_idx on public.project_listings (published_at desc)
  where status = 'published' and not is_demo;

create table public.project_listing_sources (
  project_id uuid primary key references public.project_listings(id) on delete restrict,
  staffing_request_id uuid unique references public.staffing_requests(id) on delete restrict,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.project_applications (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.project_listings(id) on delete restrict,
  candidate_id uuid not null references public.candidate_accounts(id) on delete restrict,
  availability text not null check (availability in ('available','within_2_weeks','within_4_weeks','engaged','paused')),
  available_from date,
  consent boolean not null check (consent),
  status text not null default 'submitted' check (status in ('submitted','reviewing','shortlisted','client_review','offer','placed','rejected','closed','withdrawn')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, candidate_id)
);
create index project_applications_candidate_idx on public.project_applications(candidate_id,created_at desc);
create index project_applications_project_idx on public.project_applications(project_id,created_at desc);

alter table public.project_listings enable row level security;
alter table public.project_listing_sources enable row level security;
alter table public.project_applications enable row level security;
revoke all on public.project_listings, public.project_listing_sources, public.project_applications from public, anon, authenticated;
grant select on public.project_listings to anon, authenticated;
grant insert, update on public.project_listings to authenticated;
grant select, insert, update on public.project_listing_sources to authenticated;
grant select on public.project_applications to authenticated;
grant insert (project_id,candidate_id,availability,available_from,consent) on public.project_applications to authenticated;
grant update (status) on public.project_applications to authenticated;
grant all on public.project_listings, public.project_listing_sources, public.project_applications to service_role;

create policy "Public can browse approved open projects" on public.project_listings
  for select to anon, authenticated
  using (status='published' and not is_demo and (expires_at is null or expires_at > now()));
create policy "Approved staff manage public project copy" on public.project_listings
  for all to authenticated
  using ((select private.is_benchpro_staff()))
  with check ((select private.is_benchpro_staff()));
create policy "Approved staff manage private project sources" on public.project_listing_sources
  for all to authenticated
  using ((select private.is_benchpro_staff()))
  with check ((select private.is_benchpro_staff()));
create policy "Candidates read own project applications" on public.project_applications
  for select to authenticated using (
    exists (select 1 from public.candidate_accounts c where c.id=candidate_id and c.user_id=(select auth.uid()))
  );
create policy "Approved staff review project applications" on public.project_applications
  for select to authenticated using ((select private.is_benchpro_staff()));
create policy "Candidates apply with their own complete profile" on public.project_applications
  for insert to authenticated with check (
    consent and status='submitted'
    and exists (
      select 1 from public.candidate_accounts c
      where c.id=candidate_id and c.user_id=(select auth.uid())
        and char_length(trim(c.full_name))>=2 and char_length(trim(c.primary_role))>=2
        and nullif(trim(c.country_or_timezone),'') is not null
        and cardinality(c.skills)>0 and c.resume_file_path is not null
    )
    and exists (
      select 1 from public.project_listings p
      where p.id=project_id and p.status='published' and not p.is_demo
        and (p.expires_at is null or p.expires_at>now())
    )
  );
create policy "Approved staff update application stages" on public.project_applications
  for update to authenticated using ((select private.is_benchpro_staff()))
  with check ((select private.is_benchpro_staff()));
create policy "Candidates withdraw their own active applications" on public.project_applications
  for update to authenticated using (
    status in ('submitted','reviewing','shortlisted','client_review','offer')
    and exists(select 1 from public.candidate_accounts c where c.id=candidate_id and c.user_id=(select auth.uid()))
  ) with check (
    status='withdrawn'
    and exists(select 1 from public.candidate_accounts c where c.id=candidate_id and c.user_id=(select auth.uid()))
  );
create policy "Applicants retain project history" on public.project_listings
  for select to authenticated using (
    exists (
      select 1 from public.project_applications a
      join public.candidate_accounts c on c.id=a.candidate_id
      where a.project_id=project_listings.id and c.user_id=(select auth.uid())
    )
  );

create function private.project_record_timestamps() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  new.updated_at=now();
  if tg_table_name='project_listings' and new.status='published' then
    new.published_at=coalesce(new.published_at,now());
  end if;
  return new;
end;
$$;
revoke all on function private.project_record_timestamps() from public,anon,authenticated;
create trigger project_listing_timestamps before insert or update on public.project_listings
  for each row execute function private.project_record_timestamps();
-- Separate trigger keeps application timestamps server-owned.
create function private.project_application_timestamps() returns trigger
language plpgsql security invoker set search_path='' as $$
begin new.updated_at=now(); return new; end;
$$;
revoke all on function private.project_application_timestamps() from public,anon,authenticated;
create trigger project_application_timestamps before update on public.project_applications
  for each row execute function private.project_application_timestamps();

comment on table public.project_listings is 'Staff-approved public copy only. Never store private client contacts, raw JDs or candidate data here.';
comment on table public.project_listing_sources is 'Staff-only association between a public listing and an internal staffing request.';
comment on table public.project_applications is 'Candidate-owned expressions of interest. Staff review the current private candidate profile; clients have no access through this table.';
