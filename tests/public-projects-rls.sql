-- Integration test: every fixture is uncommitted and rolled back, including auth users.
-- Never use these fixtures as public content or seed data.
begin;
insert into auth.users(id,email,role,aud,raw_app_meta_data,raw_user_meta_data)
values ('00000000-0000-4000-8000-000000000101','benchpro-demo+rls-candidate-a@example.com','authenticated','authenticated','{}','{}'),
       ('00000000-0000-4000-8000-000000000102','benchpro-demo+rls-candidate-b@example.com','authenticated','authenticated','{}','{}');
insert into public.candidate_accounts(id,user_id,full_name,primary_role,skills,country_or_timezone,resume_file_path,resume_file_name,resume_file_size,resume_file_type)
select ('00000000-0000-4000-8000-00000000020'||n)::uuid,('00000000-0000-4000-8000-00000000010'||n)::uuid,
  'RLS Test Candidate','Test Engineer',array['SQL'],'India',
  'candidates/00000000-0000-4000-8000-00000000020'||n||'/00000000-0000-4000-8000-000000000301_resume.pdf','resume.pdf',1,'application/pdf'
from generate_series(1,2) n;
insert into public.project_listings(id,title,category,summary,description,requirements,skills,work_mode,location,duration,experience,status,is_demo,expires_at)
select ('00000000-0000-4000-8000-00000000040'||n)::uuid,'RLS test project','Engineering',
 'Uncommitted security test project only.','This project exists only within a rolled-back security test transaction.',
 array['Test requirement'],array['SQL'],'Remote','India','6 months','5+ years',
 case n when 2 then 'draft' when 3 then 'closed' else 'published' end,n=5,
 case when n=4 then now()-interval '1 day' else null end
from generate_series(1,5) n;

set local role anon;
do $$ begin
  if (select count(*) from public.project_listings where id::text like '00000000-0000-4000-8000-00000000040%')<>1 then raise exception 'Public listing isolation failed'; end if;
  begin perform 1 from public.project_listing_sources;raise exception 'Private sources exposed';exception when insufficient_privilege then null;end;
  begin perform 1 from public.project_applications;raise exception 'Applications exposed to anon';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000101","email":"benchpro-demo+rls-candidate-a@example.com","role":"authenticated"}',true);
set local role authenticated;
insert into public.project_applications(project_id,candidate_id,availability,consent)
values('00000000-0000-4000-8000-000000000401','00000000-0000-4000-8000-000000000201','available',true);
do $$ begin
  begin insert into public.project_applications(project_id,candidate_id,availability,consent) values('00000000-0000-4000-8000-000000000401','00000000-0000-4000-8000-000000000202','available',true);raise exception 'Candidate impersonation allowed';exception when insufficient_privilege then null;end;
  begin insert into public.project_applications(project_id,candidate_id,availability,consent) values('00000000-0000-4000-8000-000000000402','00000000-0000-4000-8000-000000000201','available',true);raise exception 'Draft application allowed';exception when insufficient_privilege then null;end;
  begin insert into public.project_applications(project_id,candidate_id,availability,consent) values('00000000-0000-4000-8000-000000000403','00000000-0000-4000-8000-000000000201','available',true);raise exception 'Closed application allowed';exception when insufficient_privilege then null;end;
  begin insert into public.project_applications(project_id,candidate_id,availability,consent) values('00000000-0000-4000-8000-000000000404','00000000-0000-4000-8000-000000000201','available',true);raise exception 'Expired application allowed';exception when insufficient_privilege then null;end;
  begin insert into public.project_applications(project_id,candidate_id,availability,consent) values('00000000-0000-4000-8000-000000000405','00000000-0000-4000-8000-000000000201','available',true);raise exception 'Demo application allowed';exception when insufficient_privilege then null;end;
  begin insert into public.project_applications(project_id,candidate_id,availability,consent) values('00000000-0000-4000-8000-000000000401','00000000-0000-4000-8000-000000000201','available',true);raise exception 'Duplicate application allowed';exception when unique_violation then null;end;
  begin update public.project_applications set status='placed' where candidate_id='00000000-0000-4000-8000-000000000201';raise exception 'Candidate changed own review stage';exception when insufficient_privilege then null;end;
  begin update public.project_applications set candidate_id='00000000-0000-4000-8000-000000000202';raise exception 'Application ownership mutable';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000102","email":"benchpro-demo+rls-candidate-b@example.com","role":"authenticated"}',true);
set local role authenticated;
do $$ begin if exists(select 1 from public.project_applications where candidate_id='00000000-0000-4000-8000-000000000201') then raise exception 'Other candidate application visible';end if;end $$;
insert into public.project_applications(project_id,candidate_id,availability,consent)
values('00000000-0000-4000-8000-000000000401','00000000-0000-4000-8000-000000000202','available',true);
reset role;
-- A client-only identity has no publishing or application access.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000103","email":"benchpro-demo+rls-client@example.com","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  if exists(select 1 from public.project_applications) then raise exception 'Client can read candidate applications';end if;
  if exists(select 1 from public.project_listing_sources) then raise exception 'Client can read source links';end if;
  update public.project_listings set title='Tampered title' where id='00000000-0000-4000-8000-000000000401';
  if found then raise exception 'Nonstaff can edit public roles';end if;
end $$;
reset role;
-- Use an existing approved staff identity; no staff permission is created by this test.
select set_config('request.jwt.claims',jsonb_build_object('sub',u.id,'email',u.email,'role','authenticated')::text,true)
from auth.users u join private.benchpro_staff_access s on s.email=lower(u.email) limit 1;
set local role authenticated;
do $$ begin
  if not public.is_benchpro_staff_account() then raise exception 'Approved staff fixture unavailable';end if;
  if (select count(*) from public.project_applications where project_id='00000000-0000-4000-8000-000000000401')<>2 then raise exception 'Staff application visibility failed';end if;
  update public.project_applications set status='reviewing' where project_id='00000000-0000-4000-8000-000000000401';
  if not found then raise exception 'Staff cannot update application stages';end if;
  update public.project_listings set status='closed' where id='00000000-0000-4000-8000-000000000401';
  if not found then raise exception 'Staff cannot close listings';end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000101","email":"benchpro-demo+rls-candidate-a@example.com","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  if (select count(*) from public.project_applications where project_id='00000000-0000-4000-8000-000000000401')<>1 then raise exception 'Own application isolation failed';end if;
  if not exists(select 1 from public.project_listings where id='00000000-0000-4000-8000-000000000401') then raise exception 'Closed project history lost';end if;
  update public.project_applications set status='withdrawn' where candidate_id='00000000-0000-4000-8000-000000000201';
  if not found then raise exception 'Candidate withdrawal failed';end if;
  update public.project_applications set status='submitted' where candidate_id='00000000-0000-4000-8000-000000000201';
  if found then raise exception 'Withdrawn application reactivated by candidate';end if;
end $$;
reset role;
set local role anon;
do $$ begin if exists(select 1 from public.project_listings where id='00000000-0000-4000-8000-000000000401') then raise exception 'Closed listing visible to public';end if;end $$;
reset role;
rollback;
select 'PASS: public visibility, staff publishing, own applications, ownership, duplicate prevention, closed/expired/demo protection, stage restrictions, withdrawal and retained history; all fixtures rolled back' as result;
