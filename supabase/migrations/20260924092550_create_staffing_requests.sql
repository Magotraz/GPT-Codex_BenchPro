create table public.staffing_requests (
  id uuid primary key default gen_random_uuid(),
  contact_name text not null check (char_length(trim(contact_name)) between 2 and 120),
  company_name text not null check (char_length(trim(company_name)) between 2 and 160),
  work_email text not null check (
    char_length(work_email) between 5 and 320
    and work_email ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$'
  ),
  role_or_skills text not null check (char_length(trim(role_or_skills)) between 2 and 200),
  project_duration text check (project_duration is null or char_length(project_duration) <= 120),
  target_start_date date,
  work_location_timezone text check (work_location_timezone is null or char_length(work_location_timezone) <= 140),
  project_details text check (project_details is null or char_length(project_details) <= 2000),
  status text not null default 'new' check (status in ('new', 'contacted', 'qualified', 'shortlist_sent', 'closed')),
  created_at timestamptz not null default now()
);

alter table public.staffing_requests enable row level security;

revoke all on table public.staffing_requests from anon, authenticated;
grant usage on schema public to anon;
grant insert (
  contact_name,
  company_name,
  work_email,
  role_or_skills,
  project_duration,
  target_start_date,
  work_location_timezone,
  project_details
) on public.staffing_requests to anon;

create policy "Public can submit staffing requests"
  on public.staffing_requests
  for insert
  to anon
  with check (status = 'new');
