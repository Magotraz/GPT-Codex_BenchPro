-- Persisted test data stays separate from real operating records.
alter table public.candidate_accounts add column is_demo boolean not null default false;

-- Preserve the existing private talent mirror, including the demo classification.
create or replace function public.sync_candidate_account_to_talent_profile()
returns trigger language plpgsql security definer set search_path='' as $$
declare account_email text;
begin
  select email into account_email from auth.users where id=new.user_id;
  insert into public.talent_profiles (
    id,full_name,primary_role,years_experience,skills,country_or_timezone,
    availability,available_from,work_email,phone_number,linkedin_url,profile_summary,
    resume_file_path,resume_file_name,resume_file_size,resume_file_type,is_active,is_demo,created_by,updated_at
  ) values (
    new.id,new.full_name,new.primary_role,new.years_experience,new.skills,new.country_or_timezone,
    new.availability,new.available_from,account_email,new.phone_number,new.linkedin_url,new.profile_summary,
    new.resume_file_path,new.resume_file_name,new.resume_file_size,new.resume_file_type,true,new.is_demo,new.user_id,now()
  ) on conflict(id) do update set
    full_name=excluded.full_name,primary_role=excluded.primary_role,years_experience=excluded.years_experience,
    skills=excluded.skills,country_or_timezone=excluded.country_or_timezone,availability=excluded.availability,
    available_from=excluded.available_from,work_email=excluded.work_email,phone_number=excluded.phone_number,
    linkedin_url=excluded.linkedin_url,profile_summary=excluded.profile_summary,resume_file_path=excluded.resume_file_path,
    resume_file_name=excluded.resume_file_name,resume_file_size=excluded.resume_file_size,
    resume_file_type=excluded.resume_file_type,is_demo=excluded.is_demo,updated_at=now();
  return new;
end $$;
revoke all on function public.sync_candidate_account_to_talent_profile() from public,anon,authenticated;

-- These triggers run as the caller. Existing RLS still governs all reads/writes.
create function private.protect_demo_classification() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if tg_op='UPDATE' and new.is_demo is distinct from old.is_demo then
    raise exception 'Sample classification cannot be changed. Create a separate real record instead.';
  end if;
  if tg_table_name='candidate_accounts' and tg_op='INSERT' and new.is_demo
     and current_user in ('anon','authenticated') then
    raise exception 'Sample candidates must be provisioned through the controlled seed.';
  end if;
  return new;
end $$;
create trigger protect_demo_classification before insert or update of is_demo on public.candidate_accounts
for each row execute function private.protect_demo_classification();
create trigger protect_demo_classification before update of is_demo on public.clients
for each row execute function private.protect_demo_classification();
create trigger protect_demo_classification before update of is_demo on public.staffing_requests
for each row execute function private.protect_demo_classification();
create trigger protect_demo_classification before update of is_demo on public.project_listings
for each row execute function private.protect_demo_classification();

create function private.protect_demo_relationship() returns trigger
language plpgsql security invoker set search_path='' as $$
declare left_demo boolean; right_demo boolean;
begin
  if tg_table_name='shortlist_reviews' then
    select is_demo into left_demo from public.candidate_accounts where id=new.candidate_id;
    select is_demo into right_demo from public.staffing_requests where id=new.staffing_request_id;
  elsif tg_table_name='project_applications' then
    select is_demo into left_demo from public.candidate_accounts where id=new.candidate_id;
    select is_demo into right_demo from public.project_listings where id=new.project_id;
  elsif tg_table_name='project_listing_sources' then
    if new.staffing_request_id is null then return new; end if;
    select is_demo into left_demo from public.project_listings where id=new.project_id;
    select is_demo into right_demo from public.staffing_requests where id=new.staffing_request_id;
  elsif tg_table_name='staffing_requests' then
    if new.client_id is null then return new; end if;
    left_demo=new.is_demo;
    select is_demo into right_demo from public.clients where id=new.client_id;
  end if;
  if left_demo is null or right_demo is null or left_demo<>right_demo then
    raise exception 'Test and real records cannot be connected. Choose records from the same dataset.';
  end if;
  return new;
end $$;
create trigger protect_demo_relationship before insert or update of candidate_id,staffing_request_id on public.shortlist_reviews
for each row execute function private.protect_demo_relationship();
create trigger protect_demo_relationship before insert or update of candidate_id,project_id on public.project_applications
for each row execute function private.protect_demo_relationship();
create trigger protect_demo_relationship before insert or update of project_id,staffing_request_id on public.project_listing_sources
for each row execute function private.protect_demo_relationship();
create trigger protect_demo_relationship before insert or update of client_id on public.staffing_requests
for each row execute function private.protect_demo_relationship();
revoke all on function private.protect_demo_classification(),private.protect_demo_relationship() from public,anon,authenticated;
