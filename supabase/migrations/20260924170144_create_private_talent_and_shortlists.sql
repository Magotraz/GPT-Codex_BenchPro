create table public.talent_profiles (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (char_length(trim(full_name)) between 2 and 120),
  primary_role text not null check (char_length(trim(primary_role)) between 2 and 140),
  years_experience smallint check (years_experience is null or years_experience between 0 and 60),
  skills text[] not null default '{}',
  country_or_timezone text check (country_or_timezone is null or char_length(trim(country_or_timezone)) <= 160),
  availability text not null default 'available'
    check (availability in ('available','within_2_weeks','within_4_weeks','engaged','paused')),
  available_from date,
  work_email text check (
    work_email is null or (
      char_length(work_email) between 5 and 320
      and work_email ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+[.][A-Z]{2,}$'
    )
  ),
  phone_number text check (phone_number is null or char_length(trim(phone_number)) between 7 and 32),
  profile_summary text check (profile_summary is null or char_length(profile_summary) <= 3000),
  internal_notes text check (internal_notes is null or char_length(internal_notes) <= 3000),
  is_active boolean not null default true,
  resume_file_path text,
  resume_file_name text,
  resume_file_size bigint,
  resume_file_type text,
  is_demo boolean not null default false,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint talent_profiles_skills_count_check check (cardinality(skills) <= 30),
  constraint talent_profiles_resume_metadata_check check (
    (
      resume_file_path is null and resume_file_name is null
      and resume_file_size is null and resume_file_type is null
    )
    or
    (
      resume_file_path is not null
      and resume_file_path ~ '^candidates/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}_[A-Za-z0-9][A-Za-z0-9._-]{0,119}[.](pdf|doc|docx)$'
      and resume_file_name is not null and char_length(resume_file_name) between 1 and 180
      and resume_file_size between 1 and 10485760
      and resume_file_type in ('application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
    )
  )
);

comment on table public.talent_profiles is 'Private BenchPro talent bench. Accessible only to approved BenchPro staff.';
comment on column public.talent_profiles.internal_notes is 'Staff-only candidate notes; never client-facing.';
comment on column public.talent_profiles.resume_file_path is 'Private object path in the candidate-resumes bucket.';

alter table public.talent_profiles enable row level security;
grant select, insert, update on public.talent_profiles to authenticated;

create policy "Approved staff can read talent profiles"
  on public.talent_profiles for select to authenticated
  using ((select private.is_benchpro_staff()));

create policy "Approved staff can create talent profiles"
  on public.talent_profiles for insert to authenticated
  with check ((select private.is_benchpro_staff()));

create policy "Approved staff can update talent profiles"
  on public.talent_profiles for update to authenticated
  using ((select private.is_benchpro_staff()))
  with check ((select private.is_benchpro_staff()));

create table public.role_talent_matches (
  id uuid primary key default gen_random_uuid(),
  staffing_request_id uuid not null references public.staffing_requests(id) on delete cascade,
  talent_profile_id uuid not null references public.talent_profiles(id) on delete restrict,
  stage text not null default 'considering'
    check (stage in ('considering','screening','shortlisted','shared','interviewing','selected','not_selected','withdrawn')),
  proposed_hourly_rate_usd numeric(10,2) check (
    proposed_hourly_rate_usd is null or proposed_hourly_rate_usd between 0.01 and 99999.99
  ),
  client_summary text check (client_summary is null or char_length(client_summary) <= 2000),
  internal_notes text check (internal_notes is null or char_length(internal_notes) <= 3000),
  shared_at timestamptz,
  added_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (staffing_request_id, talent_profile_id),
  constraint shared_candidates_have_shared_timestamp check (
    stage not in ('shared','interviewing','selected') or shared_at is not null
  )
);

comment on table public.role_talent_matches is 'Staff-only candidate-to-role pipeline and shortlist details. Shared means BenchPro has deliberately sent the profile outside the portal.';
comment on column public.role_talent_matches.client_summary is 'Approved, client-facing introduction text; visible only inside the staff dashboard until a client portal is introduced.';
comment on column public.role_talent_matches.internal_notes is 'Private BenchPro recruiting notes.';

alter table public.role_talent_matches enable row level security;
grant select, insert, update on public.role_talent_matches to authenticated;

create policy "Approved staff can read role talent matches"
  on public.role_talent_matches for select to authenticated
  using ((select private.is_benchpro_staff()));

create policy "Approved staff can create role talent matches"
  on public.role_talent_matches for insert to authenticated
  with check ((select private.is_benchpro_staff()));

create policy "Approved staff can update role talent matches"
  on public.role_talent_matches for update to authenticated
  using ((select private.is_benchpro_staff()))
  with check ((select private.is_benchpro_staff()));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'candidate-resumes',
  'candidate-resumes',
  false,
  10485760,
  array['application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document']
)
on conflict (id) do update
set name = excluded.name,
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Approved staff can upload candidate resumes"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'candidate-resumes'
    and (select private.is_benchpro_staff())
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[1] = 'candidates'
    and (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and storage.filename(name) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}_[A-Za-z0-9][A-Za-z0-9._-]{0,119}[.](pdf|doc|docx)$'
  );

create policy "Approved staff can read candidate resumes"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'candidate-resumes'
    and (select private.is_benchpro_staff())
  );

