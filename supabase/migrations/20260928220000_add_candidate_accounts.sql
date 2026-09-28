create table public.candidate_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete restrict,
  full_name text not null check (char_length(trim(full_name)) between 2 and 120),
  primary_role text not null check (char_length(trim(primary_role)) between 2 and 140),
  years_experience smallint check (years_experience is null or years_experience between 0 and 60),
  skills text[] not null default '{}',
  country_or_timezone text check (country_or_timezone is null or char_length(trim(country_or_timezone)) <= 160),
  availability text not null default 'available'
    check (availability in ('available','within_2_weeks','within_4_weeks','engaged','paused')),
  available_from date,
  phone_number text check (phone_number is null or char_length(trim(phone_number)) between 7 and 32),
  linkedin_url text check (linkedin_url is null or char_length(trim(linkedin_url)) <= 500),
  profile_summary text check (profile_summary is null or char_length(profile_summary) <= 3000),
  resume_file_path text,
  resume_file_name text,
  resume_file_size bigint,
  resume_file_type text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint candidate_accounts_skills_count_check check (cardinality(skills) <= 30),
  constraint candidate_accounts_resume_metadata_check check (
    (
      resume_file_path is null and resume_file_name is null
      and resume_file_size is null and resume_file_type is null
    )
    or
    (
      resume_file_path is not null
      and (storage.foldername(resume_file_path))[1] = 'candidates'
      and (storage.foldername(resume_file_path))[2] = id::text
      and storage.filename(resume_file_path) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}_[A-Za-z0-9][A-Za-z0-9._-]{0,119}[.](pdf|doc|docx)$'
      and resume_file_name is not null and char_length(resume_file_name) between 1 and 180
      and resume_file_size between 1 and 10485760
      and resume_file_type in ('application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
    )
  )
);

comment on table public.candidate_accounts is 'Candidate-owned account profile data. Internal BenchPro notes are stored separately on talent_profiles.';
alter table public.candidate_accounts enable row level security;
grant select, insert, update on public.candidate_accounts to authenticated;

create policy "Candidates can read their own account profile"
  on public.candidate_accounts for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Candidates can create their own account profile"
  on public.candidate_accounts for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Candidates can update their own account profile"
  on public.candidate_accounts for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create or replace function public.sync_candidate_account_to_talent_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  account_email text;
begin
  select u.email into account_email from auth.users as u where u.id = new.user_id;
  insert into public.talent_profiles (
    id, full_name, primary_role, years_experience, skills, country_or_timezone,
    availability, available_from, work_email, phone_number, linkedin_url,
    profile_summary, resume_file_path, resume_file_name, resume_file_size,
    resume_file_type, is_active, is_demo, created_by, updated_at
  ) values (
    new.id, new.full_name, new.primary_role, new.years_experience, new.skills,
    new.country_or_timezone, new.availability, new.available_from, account_email,
    new.phone_number, new.linkedin_url, new.profile_summary, new.resume_file_path,
    new.resume_file_name, new.resume_file_size, new.resume_file_type, true, false,
    new.user_id, now()
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    primary_role = excluded.primary_role,
    years_experience = excluded.years_experience,
    skills = excluded.skills,
    country_or_timezone = excluded.country_or_timezone,
    availability = excluded.availability,
    available_from = excluded.available_from,
    work_email = excluded.work_email,
    phone_number = excluded.phone_number,
    linkedin_url = excluded.linkedin_url,
    profile_summary = excluded.profile_summary,
    resume_file_path = excluded.resume_file_path,
    resume_file_name = excluded.resume_file_name,
    resume_file_size = excluded.resume_file_size,
    resume_file_type = excluded.resume_file_type,
    updated_at = now();
  return new;
end;
$$;

revoke all on function public.sync_candidate_account_to_talent_profile() from public, anon, authenticated;

create trigger sync_candidate_account_to_talent_profile
  after insert or update on public.candidate_accounts
  for each row execute function public.sync_candidate_account_to_talent_profile();

create policy "Candidates can upload their own resumes"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'candidate-resumes'
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[1] = 'candidates'
    and exists (
      select 1 from public.candidate_accounts as ca
      where ca.id::text = (storage.foldername(name))[2]
        and ca.user_id = (select auth.uid())
    )
    and storage.filename(name) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}_[A-Za-z0-9][A-Za-z0-9._-]{0,119}[.](pdf|doc|docx)$'
  );

create policy "Candidates can read their own resumes"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'candidate-resumes'
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[1] = 'candidates'
    and exists (
      select 1 from public.candidate_accounts as ca
      where ca.id::text = (storage.foldername(name))[2]
        and ca.user_id = (select auth.uid())
    )
  );

create policy "Candidates can remove their own resumes"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'candidate-resumes'
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[1] = 'candidates'
    and exists (
      select 1 from public.candidate_accounts as ca
      where ca.id::text = (storage.foldername(name))[2]
        and ca.user_id = (select auth.uid())
    )
  );
