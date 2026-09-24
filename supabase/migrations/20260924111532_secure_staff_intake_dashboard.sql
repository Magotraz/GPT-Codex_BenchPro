create schema if not exists private;

create table private.benchpro_staff_access (
  email text primary key check (
    email = lower(trim(email))
    and email ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$'
  ),
  created_at timestamptz not null default now()
);

alter table private.benchpro_staff_access enable row level security;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;
revoke all on table private.benchpro_staff_access from public, anon, authenticated;

create or replace function private.is_benchpro_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from private.benchpro_staff_access as staff
      where staff.email = lower(coalesce((select auth.jwt() ->> 'email'), ''))
    );
$function$;

revoke all on function private.is_benchpro_staff() from public, anon, authenticated;
grant execute on function private.is_benchpro_staff() to authenticated;

insert into private.benchpro_staff_access (email)
values ('admin@benchpro.in')
on conflict (email) do nothing;

alter table public.staffing_requests
  add column assigned_to text check (
    assigned_to is null or assigned_to ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$'
  );

grant select on public.staffing_requests to authenticated;
grant update (status, assigned_to) on public.staffing_requests to authenticated;

create policy "Approved staff can read staffing requests"
  on public.staffing_requests
  for select
  to authenticated
  using ((select private.is_benchpro_staff()));

create policy "Approved staff can update intake workflow"
  on public.staffing_requests
  for update
  to authenticated
  using ((select private.is_benchpro_staff()))
  with check ((select private.is_benchpro_staff()));

