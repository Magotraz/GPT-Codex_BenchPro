-- Client portal access is organization membership, separate from BenchPro Auth accounts.
-- Removing a member revokes only the membership and retains their auth account/history.

create table public.client_email_domains (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  domain text not null check (domain = lower(trim(domain)) and domain ~ '^[a-z0-9.-]+\.[a-z]{2,}$'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (client_id, domain)
);

create table public.client_memberships (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  user_id uuid references auth.users(id) on delete restrict,
  email text not null check (email = lower(trim(email)) and email ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$'),
  role text not null check (role in ('superuser', 'recruiter')),
  status text not null default 'invited' check (status in ('invited', 'active', 'removed')),
  invited_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  activated_at timestamptz,
  removed_at timestamptz
);

create unique index client_memberships_active_user_idx
  on public.client_memberships (client_id, user_id) where user_id is not null and status = 'active';
create unique index client_memberships_pending_email_idx
  on public.client_memberships (client_id, email) where status = 'invited';
create index client_memberships_user_client_idx on public.client_memberships (user_id, client_id) where status = 'active';

alter table public.staffing_requests
  add column client_assignee_membership_id uuid references public.client_memberships(id) on delete set null;

create table public.client_assignment_events (
  id bigint generated always as identity primary key,
  staffing_request_id uuid not null references public.staffing_requests(id) on delete restrict,
  client_id uuid not null references public.clients(id) on delete restrict,
  previous_membership_id uuid references public.client_memberships(id) on delete set null,
  new_membership_id uuid references public.client_memberships(id) on delete set null,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now()
);

alter table public.client_email_domains enable row level security;
alter table public.client_memberships enable row level security;
alter table public.client_assignment_events enable row level security;

create or replace function private.is_client_member(target_client_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select (select auth.uid()) is not null and exists (
    select 1 from public.client_memberships m
    where m.client_id = target_client_id and m.user_id = (select auth.uid()) and m.status = 'active'
      and lower(split_part(coalesce((select auth.jwt() ->> 'email'), ''), '@', 2)) =
        any (select d.domain from public.client_email_domains d where d.client_id = m.client_id)
  );
$$;

create or replace function private.is_client_superuser(target_client_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select (select auth.uid()) is not null and exists (
    select 1 from public.client_memberships m
    where m.client_id = target_client_id and m.user_id = (select auth.uid())
      and m.status = 'active' and m.role = 'superuser'
      and lower(split_part(coalesce((select auth.jwt() ->> 'email'), ''), '@', 2)) =
        any (select d.domain from public.client_email_domains d where d.client_id = m.client_id)
  );
$$;

revoke all on function private.is_client_member(uuid) from public, anon, authenticated;
revoke all on function private.is_client_superuser(uuid) from public, anon, authenticated;
grant execute on function private.is_client_member(uuid), private.is_client_superuser(uuid) to authenticated;
create or replace function public.is_benchpro_staff_account()
returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_benchpro_staff();
$$;
revoke all on function public.is_benchpro_staff_account() from public, anon;
grant execute on function public.is_benchpro_staff_account() to authenticated;

revoke all on table public.client_email_domains, public.client_memberships, public.client_assignment_events from public, anon, authenticated;
grant select on public.client_email_domains, public.client_memberships, public.client_assignment_events to authenticated;
grant all on public.client_email_domains, public.client_memberships, public.client_assignment_events to service_role;
grant insert (id, contact_name, designation, company_name, work_email, phone_number, role_or_skills, project_duration, target_start_date, work_location_timezone, project_details, status, client_id, company_size, business_type)
  on public.staffing_requests to authenticated;
grant update (jd_file_path, jd_file_name, jd_file_size, jd_file_type) on public.staffing_requests to authenticated;

create policy "BenchPro staff manage approved client domains"
  on public.client_email_domains for all to authenticated
  using ((select private.is_benchpro_staff())) with check ((select private.is_benchpro_staff()));
create policy "Client members can view their allowed domains"
  on public.client_email_domains for select to authenticated
  using ((select private.is_client_member(client_id)));

create policy "Members can view own client membership"
  on public.client_memberships for select to authenticated
  using (user_id = (select auth.uid()) and status = 'active');
create policy "Client superusers can view their team"
  on public.client_memberships for select to authenticated
  using ((select private.is_client_superuser(client_id)));
create policy "BenchPro staff can view client memberships"
  on public.client_memberships for select to authenticated
  using ((select private.is_benchpro_staff()));

create policy "Client members can read their assigned client roles"
  on public.staffing_requests for select to authenticated
  using (client_id is not null and (select private.is_client_member(client_id)));
create policy "Client members can post roles for their own organization"
  on public.staffing_requests for insert to authenticated
  with check (
    client_id is not null and status = 'new'
    and (select private.is_client_member(client_id))
    and company_name = (select c.company_name from public.clients c where c.id = client_id)
    and company_size is not distinct from (select c.company_size from public.clients c where c.id = client_id)
    and business_type is not distinct from (select c.business_type from public.clients c where c.id = client_id)
  );
create or replace function public.assign_client_role(target_request_id uuid, target_membership_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  request_client_id uuid;
begin
  select r.client_id into request_client_id from public.staffing_requests r where r.id = target_request_id;
  if request_client_id is null or not private.is_client_superuser(request_client_id) then
    raise exception 'Only this client superuser can assign a client role.' using errcode = '42501';
  end if;
  if target_membership_id is not null and not exists (
    select 1 from public.client_memberships m
    where m.id = target_membership_id and m.client_id = request_client_id and m.status = 'active'
  ) then
    raise exception 'Choose an active teammate from this client.' using errcode = '23514';
  end if;
  update public.staffing_requests set client_assignee_membership_id = target_membership_id where id = target_request_id;
end;
$$;

create or replace function public.release_client_member_roles(target_client_id uuid, departing_membership_id uuid, replacement_membership_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_benchpro_staff() and not private.is_client_superuser(target_client_id) then
    raise exception 'Only BenchPro Admin or the client superuser can reassign roles.' using errcode = '42501';
  end if;
  if replacement_membership_id is not null and not exists (
    select 1 from public.client_memberships m
    where m.id = replacement_membership_id and m.client_id = target_client_id and m.status = 'active'
  ) then
    raise exception 'Choose an active teammate from this client.' using errcode = '23514';
  end if;
  update public.staffing_requests
  set client_assignee_membership_id = replacement_membership_id
  where client_id = target_client_id and client_assignee_membership_id = departing_membership_id;
end;
$$;
revoke all on function public.assign_client_role(uuid, uuid), public.release_client_member_roles(uuid, uuid, uuid) from public, anon;
grant execute on function public.assign_client_role(uuid, uuid), public.release_client_member_roles(uuid, uuid, uuid) to authenticated;

create policy "Client members can view assignment history"
  on public.client_assignment_events for select to authenticated
  using ((select private.is_client_member(client_id)));

create or replace function public.audit_client_role_assignment()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.client_assignee_membership_id is distinct from new.client_assignee_membership_id then
    insert into public.client_assignment_events (
      staffing_request_id, client_id, previous_membership_id, new_membership_id, changed_by
    ) values (
      new.id, new.client_id, old.client_assignee_membership_id,
      new.client_assignee_membership_id, (select auth.uid())
    );
  end if;
  return new;
end;
$$;
revoke all on function public.audit_client_role_assignment() from public, anon, authenticated;
create trigger audit_client_role_assignment
  after update of client_assignee_membership_id on public.staffing_requests
  for each row execute function public.audit_client_role_assignment();

create or replace function public.activate_client_membership_for_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.email_confirmed_at is null or new.email is null then return new; end if;
  update public.client_memberships
  set email = lower(new.email)
  where user_id = new.id and status = 'active';
  update public.client_memberships
  set user_id = new.id, email = lower(new.email), status = 'active', activated_at = coalesce(activated_at, now())
  where lower(email) = lower(new.email) and status = 'invited';
  return new;
end;
$$;
revoke all on function public.activate_client_membership_for_auth_user() from public, anon, authenticated;
create trigger activate_client_membership_for_auth_user
  after insert or update of email, email_confirmed_at on auth.users
  for each row execute function public.activate_client_membership_for_auth_user();

-- Clients see organization details and only roles linked to their own client record.
create policy "Client members can read their client record"
  on public.clients for select to authenticated
  using ((select private.is_client_member(id)));

-- Role documents remain private and accessible only to BenchPro staff or members of the role's client.
create policy "Client members can read their own role JDs"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'client-role-jds'
    and (storage.foldername(name))[1] = 'requests'
    and exists (
      select 1 from public.staffing_requests r
      where r.id::text = (storage.foldername(name))[2]
        and r.client_id is not null and (select private.is_client_member(r.client_id))
    )
  );
create policy "Client members can upload JDs to their own roles"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'client-role-jds'
    and (storage.foldername(name))[1] = 'requests'
    and exists (
      select 1 from public.staffing_requests r
      where r.id::text = (storage.foldername(name))[2]
        and r.client_id is not null and (select private.is_client_member(r.client_id))
    )
  );

comment on table public.client_memberships is 'Client-scoped portal access; removing a membership retains the auth user and historic work.';
comment on table public.client_email_domains is 'Email domains approved by BenchPro staff for client portal access.';
comment on column public.staffing_requests.client_assignee_membership_id is 'Client-side owner for the role. Separate from BenchPro internal assigned_to.';

notify pgrst, 'reload schema';
