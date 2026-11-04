-- Run as a transaction on the connected database. Every fixture is rolled back.
begin;
create temporary table shortlist_test_ids(name text primary key,id uuid not null);
insert into shortlist_test_ids values
('staff',gen_random_uuid()),('staff_reader',gen_random_uuid()),('candidate_user',gen_random_uuid()),('candidate',gen_random_uuid()),
('superuser',gen_random_uuid()),('member',gen_random_uuid()),('other',gen_random_uuid()),
('client',gen_random_uuid()),('other_client',gen_random_uuid()),('role',gen_random_uuid()),('other_role',gen_random_uuid()),
('membership',gen_random_uuid()),('listing',gen_random_uuid()),('application',gen_random_uuid());
grant select,insert,update on shortlist_test_ids to authenticated;
create function pg_temp.tid(n text) returns uuid language sql as $$ select id from shortlist_test_ids where name=n $$;
create function pg_temp.claim(n text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.tid(n),'role','authenticated','email','benchpro-demo+'||n||'@example.com')::text,true); end $$;
-- SQL permits direct fixture setup only before switching to the user role.
insert into auth.users(id,email) select id,'benchpro-demo+'||name||'@example.com' from shortlist_test_ids where name in ('staff','staff_reader','candidate_user','superuser','member','other');
insert into private.benchpro_staff_access(email,can_publish_shortlists) values('benchpro-demo+staff@example.com',true);
insert into private.benchpro_staff_access(email,can_publish_shortlists) values('benchpro-demo+staff_reader@example.com',false);
insert into public.clients(id,company_name,is_demo) values(pg_temp.tid('client'),'DEMO | Shortlist QA',true),(pg_temp.tid('other_client'),'DEMO | Other Client QA',true);
insert into public.client_email_domains(client_id,domain,created_by) values(pg_temp.tid('client'),'example.com',pg_temp.tid('staff')),(pg_temp.tid('other_client'),'example.com',pg_temp.tid('staff'));
insert into public.client_memberships(id,client_id,user_id,email,role,status) values
(gen_random_uuid(),pg_temp.tid('client'),pg_temp.tid('superuser'),'benchpro-demo+superuser@example.com','superuser','active'),
(pg_temp.tid('membership'),pg_temp.tid('client'),pg_temp.tid('member'),'benchpro-demo+member@example.com','recruiter','active'),
(gen_random_uuid(),pg_temp.tid('other_client'),pg_temp.tid('other'),'benchpro-demo+other@example.com','superuser','active');
insert into public.staffing_requests(id,client_id,company_name,contact_name,work_email,role_or_skills,status,is_demo) values
(pg_temp.tid('role'),pg_temp.tid('client'),'DEMO | Shortlist QA','QA Owner','benchpro-demo+role@example.com','QA Data Engineer','qualified',true),
(pg_temp.tid('other_role'),pg_temp.tid('other_client'),'DEMO | Other Client QA','QA Owner','benchpro-demo+other-role@example.com','QA Other Engineer','qualified',true);
insert into public.candidate_accounts(id,user_id,full_name,primary_role,skills,profile_summary) values(pg_temp.tid('candidate'),pg_temp.tid('candidate_user'),'QA Alex Morgan','Data Engineer',array['SQL','Python'],'INTERNAL RAW PROFILE MUST NOT LEAK');
insert into public.project_listings(id,title,category,summary,description,requirements,skills,work_mode,location,duration,experience,is_demo) values(pg_temp.tid('listing'),'QA Data Engineer','Data & AI','Transaction-only shortlist QA project','Transaction-only shortlist QA project description',array['SQL'],array['SQL'],'Remote','India','6 months','5 years',true);
insert into public.project_listing_sources(project_id,staffing_request_id,created_by) values(pg_temp.tid('listing'),pg_temp.tid('role'),pg_temp.tid('staff'));
insert into public.project_applications(id,project_id,candidate_id,availability,consent) values(pg_temp.tid('application'),pg_temp.tid('listing'),pg_temp.tid('candidate'),'available',true);

set local role authenticated;
select pg_temp.claim('staff');
insert into shortlist_test_ids values('review',(public.shortlist_action('create',jsonb_build_object('staffing_request_id',pg_temp.tid('role'),'candidate_id',pg_temp.tid('candidate'),'application_id',pg_temp.tid('application')))->>'id')::uuid);
do $$ declare result jsonb; begin
result=public.shortlist_action('create',jsonb_build_object('staffing_request_id',pg_temp.tid('role'),'candidate_id',pg_temp.tid('candidate')));
if (result->>'id')::uuid<>pg_temp.tid('review') then raise exception 'FAIL: duplicate candidate-role review'; end if;
begin perform public.shortlist_action('publish',jsonb_build_object('id',pg_temp.tid('review'),'revision',1,'approved',true));raise exception 'FAIL: published without permission';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise; end if;end;
end $$;
select public.shortlist_action('save',jsonb_build_object('id',pg_temp.tid('review'),'revision',1,'screening_confirmed',true,'availability_confirmed',true,'screening_notes','PRIVATE COST AND RECRUITER NOTES','profile',jsonb_build_object('full_name','QA Alex Morgan','title','Data Engineer','skills','SQL, Python','availability','Available in two weeks','summary','Approved recommendation for a data migration role.','project_evidence','Delivered a cloud migration across multiple data sources.','requirements_evidence','SQL evidence confirmed during a recruiter screen.','work_email','SHOULD NOT APPEAR','resume_file_path','SHOULD NOT APPEAR')));
select public.shortlist_action('request_permission',jsonb_build_object('id',pg_temp.tid('review'),'revision',2));
insert into shortlist_test_ids select 'permission',id from public.shortlist_permissions where review_id=pg_temp.tid('review');

select pg_temp.claim('superuser');
do $$ begin
if exists(select 1 from public.client_submissions where staffing_request_id=pg_temp.tid('role')) then raise exception 'FAIL: draft visible to client';end if;
if exists(select 1 from public.shortlist_reviews where id=pg_temp.tid('review')) then raise exception 'FAIL: screening leaked';end if;
if exists(select 1 from public.candidate_accounts where id=pg_temp.tid('candidate')) then raise exception 'FAIL: raw candidate leaked';end if;
begin perform public.shortlist_action('grant',jsonb_build_object('id',pg_temp.tid('permission')));raise exception 'FAIL: client granted consent';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
end $$;

select pg_temp.claim('candidate_user');
savepoint expired_request;
reset role;
update public.shortlist_permissions set expires_at=now()-interval '1 day' where id=pg_temp.tid('permission');
set local role authenticated;
select pg_temp.claim('candidate_user');
do $$ begin
begin perform public.shortlist_action('grant',jsonb_build_object('id',pg_temp.tid('permission')));raise exception 'FAIL: expired permission accepted';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
end $$;
rollback to savepoint expired_request;
do $$ begin
if (select count(*) from public.shortlist_permissions where id=pg_temp.tid('permission'))<>1 then raise exception 'FAIL: candidate cannot review packet';end if;
if (select profile from public.shortlist_permissions where id=pg_temp.tid('permission')) ?| array['work_email','resume_file_path','screening_notes'] then raise exception 'FAIL: unapproved JSON fields leaked';end if;
begin update public.shortlist_permissions set decision='granted' where id=pg_temp.tid('permission');raise exception 'FAIL: direct permission mutation';exception when insufficient_privilege then null;end;
end $$;
select public.shortlist_action('grant',jsonb_build_object('id',pg_temp.tid('permission')));
select public.shortlist_action('grant',jsonb_build_object('id',pg_temp.tid('permission')));

select pg_temp.claim('staff_reader');
do $$ begin
begin perform public.shortlist_action('publish',jsonb_build_object('id',pg_temp.tid('review'),'revision',4,'approved',true));raise exception 'FAIL: non-publisher published';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
end $$;

select pg_temp.claim('staff');
select public.shortlist_action('publish',jsonb_build_object('id',pg_temp.tid('review'),'revision',4,'approved',true));
select public.shortlist_action('publish',jsonb_build_object('id',pg_temp.tid('review'),'revision',5,'approved',true));
insert into shortlist_test_ids select 'submission',id from public.client_submissions where review_id=pg_temp.tid('review');
do $$ begin
if (select count(*) from public.client_submissions where review_id=pg_temp.tid('review'))<>1 then raise exception 'FAIL: duplicate publication';end if;
if (select status from public.project_applications where id=pg_temp.tid('application'))<>'client_review' then raise exception 'FAIL: application not progressed';end if;
begin update public.project_applications set status='placed' where id=pg_temp.tid('application');raise exception 'FAIL: managed status bypass';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
end $$;

select pg_temp.claim('other');
do $$ begin
if exists(select 1 from public.client_submissions where id=pg_temp.tid('submission')) then raise exception 'FAIL: cross-client read';end if;
if exists(select 1 from public.candidate_shortlist_updates where candidate_id=pg_temp.tid('candidate')) then raise exception 'FAIL: other candidate updates leaked';end if;
begin perform public.shortlist_action('feedback',jsonb_build_object('id',pg_temp.tid('submission'),'revision',1,'decision','interview_requested','message','Cross client request'));raise exception 'FAIL: cross-client action';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
end $$;
select pg_temp.claim('member');
do $$ begin if exists(select 1 from public.client_submissions where id=pg_temp.tid('submission')) then raise exception 'FAIL: unassigned member read';end if;end $$;

select pg_temp.claim('superuser');
select public.assign_client_role(pg_temp.tid('role'),pg_temp.tid('membership'));
select pg_temp.claim('member');
do $$ begin if (select count(*) from public.client_submissions where id=pg_temp.tid('submission'))<>1 then raise exception 'FAIL: assigned member cannot read';end if;end $$;
select public.shortlist_action('viewed',jsonb_build_object('id',pg_temp.tid('submission')));
select public.shortlist_action('viewed',jsonb_build_object('id',pg_temp.tid('submission')));
select public.shortlist_action('feedback',jsonb_build_object('id',pg_temp.tid('submission'),'revision',1,'decision','interview_requested','message','Please coordinate an interview next week.'));
do $$ begin
begin perform public.shortlist_action('feedback',jsonb_build_object('id',pg_temp.tid('submission'),'revision',1,'decision','declined','message','Stale browser response'));raise exception 'FAIL: stale update accepted';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
begin perform public.shortlist_action('feedback',jsonb_build_object('id',pg_temp.tid('submission'),'revision',2,'decision','on_hold','message','Waiting for budget'));raise exception 'FAIL: hold without date';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
end $$;
select pg_temp.claim('superuser');
select public.assign_client_role(pg_temp.tid('role'),null);
select pg_temp.claim('member');
do $$ begin
if exists(select 1 from public.client_submissions where id=pg_temp.tid('submission')) then raise exception 'FAIL: reassignment retained access';end if;
begin perform public.shortlist_action('feedback',jsonb_build_object('id',pg_temp.tid('submission'),'revision',2,'decision','question','message','Old tab question'));raise exception 'FAIL: revoked member action';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
end $$;

select pg_temp.claim('staff');
select public.shortlist_action('reply',jsonb_build_object('id',pg_temp.tid('submission'),'revision',2,'message','We are confirming availability and will follow up.'));
savepoint client_decline;
select pg_temp.claim('superuser');
select public.shortlist_action('feedback',jsonb_build_object('id',pg_temp.tid('submission'),'revision',3,'decision','declined','message','The role needs more experience in cloud data migration.'));
select pg_temp.claim('candidate_user');
do $$ begin
if (select status from public.project_applications where id=pg_temp.tid('application'))<>'rejected' then raise exception 'FAIL: client decline milestone missing';end if;
if exists(select 1 from public.shortlist_activity where submission_id=pg_temp.tid('submission')) then raise exception 'FAIL: raw decline feedback leaked';end if;
end $$;
rollback to savepoint client_decline;
do $$ begin
if (select count(*) from public.shortlist_activity where submission_id=pg_temp.tid('submission') and kind='viewed')<>1 then raise exception 'FAIL: duplicate viewed event';end if;
begin update public.staffing_requests set client_id=pg_temp.tid('other_client') where id=pg_temp.tid('role');raise exception 'FAIL: rehomed client role';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
begin update public.project_listing_sources set staffing_request_id=pg_temp.tid('other_role') where project_id=pg_temp.tid('listing');raise exception 'FAIL: rehomed public listing';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
end $$;

savepoint withdraw_permission;
select pg_temp.claim('candidate_user');
select public.shortlist_action('withdraw_permission',jsonb_build_object('id',pg_temp.tid('permission')));
do $$ begin if (select status from public.project_applications where id=pg_temp.tid('application'))<>'withdrawn' then raise exception 'FAIL: withdrawing introduction left application active';end if;end $$;
select pg_temp.claim('superuser');
do $$ begin if exists(select 1 from public.client_submissions where id=pg_temp.tid('submission')) then raise exception 'FAIL: permission withdrawal retained access';end if;end $$;
rollback to savepoint withdraw_permission;

select pg_temp.claim('candidate_user');
do $$ begin
update public.candidate_accounts set full_name='Changed Candidate Profile' where id=pg_temp.tid('candidate');
if (select profile->>'full_name' from public.shortlist_permissions where id=pg_temp.tid('permission'))<>'QA Alex Morgan' then raise exception 'FAIL: candidate edit changed approved snapshot';end if;
if exists(select 1 from public.shortlist_activity where review_id=pg_temp.tid('review')) then raise exception 'FAIL: raw feedback leaked to candidate';end if;
if not exists(select 1 from public.candidate_shortlist_updates where permission_id=pg_temp.tid('permission') and title='Interview coordination requested') then raise exception 'FAIL: candidate milestone missing';end if;
update public.candidate_shortlist_updates set read_at=now() where permission_id=pg_temp.tid('permission');
update public.project_applications set status='withdrawn' where id=pg_temp.tid('application');
end $$;
select pg_temp.claim('superuser');
do $$ begin
if exists(select 1 from public.client_submissions where id=pg_temp.tid('submission')) then raise exception 'FAIL: withdrawn profile remains visible';end if;
begin perform public.shortlist_action('feedback',jsonb_build_object('id',pg_temp.tid('submission'),'revision',3,'decision','question','message','Stale after withdrawal'));raise exception 'FAIL: feedback after withdrawal';exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
end $$;
reset role;
select 'PASS: consent, publishing, isolation, assignment, feedback, stale updates, private fields and withdrawal' as result;
rollback;
