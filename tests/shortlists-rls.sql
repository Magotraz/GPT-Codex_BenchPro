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
select pg_temp.claim('staff_reader');
insert into shortlist_test_ids values('review',(public.shortlist_action('create',jsonb_build_object('staffing_request_id',pg_temp.tid('role'),'candidate_id',pg_temp.tid('candidate'),'application_id',pg_temp.tid('application')))->>'id')::uuid);
create function pg_temp.packet() returns jsonb language sql as $$
select jsonb_build_object('id',pg_temp.tid('review'),'revision',r.revision,'fit_rating',4.8,'screening_confirmed',true,'candidate_discussed',true,
 'screening_notes','PRIVATE STAFF NOTES','profile',jsonb_build_object('full_name','QA Alex Morgan','title','Data Engineer','skills','SQL, Python','availability','Two weeks','summary','Strong evidence of successful data platform delivery.','project_evidence','Delivered a complex data migration across cloud systems.','requirements_evidence','SQL and Python delivery experience confirmed in screening.','work_email','PRIVATE_EMAIL','resume_file_path','PRIVATE_PATH'))
from public.shortlist_reviews r where r.id=pg_temp.tid('review');
$$;
do $$ declare score numeric; before_revision integer; begin
select revision into before_revision from public.shortlist_reviews where id=pg_temp.tid('review');
foreach score in array array[0,5.1,4.88] loop
 begin perform public.shortlist_action('submit',pg_temp.packet()||jsonb_build_object('fit_rating',score));raise exception 'FAIL invalid rating';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
end loop;
begin perform public.shortlist_action('submit',pg_temp.packet()||'{"candidate_discussed":false}');raise exception 'FAIL missing conversation';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
begin perform public.shortlist_action('submit',pg_temp.packet()||'{"fit_rating":null}');raise exception 'FAIL missing rating';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
if (select revision from public.shortlist_reviews where id=pg_temp.tid('review'))<>before_revision then raise exception 'FAIL partial save after failed submit';end if;
end $$;
select public.shortlist_action('submit',pg_temp.packet());
insert into shortlist_test_ids select 'submission',id from public.client_submissions where review_id=pg_temp.tid('review');
do $$ begin
if exists(select 1 from public.shortlist_permissions where review_id=pg_temp.tid('review')) then raise exception 'FAIL candidate permission created';end if;
if (select fit_rating from public.client_submissions where id=pg_temp.tid('submission'))<>4.8 then raise exception 'FAIL decimal rating';end if;
if (select status from public.project_applications where id=pg_temp.tid('application'))<>'client_review' then raise exception 'FAIL client review milestone';end if;
begin perform public.shortlist_action('submit',pg_temp.packet());raise exception 'FAIL duplicate submission';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
begin perform public.shortlist_action('request_permission',pg_temp.packet());raise exception 'FAIL legacy permission request';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
end $$;
select pg_temp.claim('candidate_user');
do $$ begin
if exists(select 1 from public.client_submissions where id=pg_temp.tid('submission')) then raise exception 'FAIL candidate saw client packet';end if;
if not exists(select 1 from public.candidate_shortlist_updates where candidate_id=pg_temp.tid('candidate') and title='Your profile has been shared') then raise exception 'FAIL candidate informational update';end if;
begin perform public.shortlist_action('withdraw',jsonb_build_object('id',pg_temp.tid('review'),'revision',3,'message','Unauthorised withdrawal'));raise exception 'FAIL candidate staff action';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
end $$;
select pg_temp.claim('other');
do $$ begin
if exists(select 1 from public.client_submissions where id=pg_temp.tid('submission')) then raise exception 'FAIL cross client read';end if;
begin perform public.shortlist_action('feedback',jsonb_build_object('id',pg_temp.tid('submission'),'revision',1,'decision','question','message','Unauthorised comment'));raise exception 'FAIL cross client action';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
end $$;
select pg_temp.claim('member');
do $$ begin if exists(select 1 from public.client_submissions where id=pg_temp.tid('submission')) then raise exception 'FAIL unassigned member read';end if;end $$;
reset role;
update public.staffing_requests set client_assignee_membership_id=pg_temp.tid('membership') where id=pg_temp.tid('role');
set local role authenticated;
select pg_temp.claim('member');
do $$ begin
if not exists(select 1 from public.client_submissions where id=pg_temp.tid('submission')) then raise exception 'FAIL assigned member access';end if;
if exists(select 1 from public.shortlist_reviews where id=pg_temp.tid('review')) then raise exception 'FAIL private notes exposed';end if;
if exists(select 1 from public.client_submissions where id=pg_temp.tid('submission') and (profile ? 'work_email' or profile ? 'resume_file_path')) then raise exception 'FAIL private fields exposed';end if;
begin perform public.shortlist_action('rate',jsonb_build_object('id',pg_temp.tid('submission'),'revision',1,'fit_rating',5));raise exception 'FAIL client rating edit';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
begin update public.client_submissions set fit_rating=5 where id=pg_temp.tid('submission');raise exception 'FAIL direct update';exception when insufficient_privilege then null;end;
end $$;
select public.shortlist_action('feedback',jsonb_build_object('id',pg_temp.tid('submission'),'revision',1,'decision','interview_requested','message','Please coordinate an interview next week.'));
select pg_temp.claim('staff_reader');
select public.shortlist_action('rate',jsonb_build_object('id',pg_temp.tid('submission'),'revision',2,'fit_rating',4.9));
do $$ begin
if (select fit_rating from public.client_submissions where id=pg_temp.tid('submission'))<>4.9 then raise exception 'FAIL rating change';end if;
if not exists(select 1 from public.shortlist_activity where submission_id=pg_temp.tid('submission') and kind='rating_updated' and actor_user_id=pg_temp.tid('staff_reader')) then raise exception 'FAIL rating audit';end if;
begin perform public.shortlist_action('rate',jsonb_build_object('id',pg_temp.tid('submission'),'revision',2,'fit_rating',4.2));raise exception 'FAIL stale rating accepted';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
end $$;
-- Withdrawal does not withdraw the application and retains private history.
select public.shortlist_action('withdraw',jsonb_build_object('id',pg_temp.tid('review'),'revision',4,'message','Availability changed during follow-up.'));
do $$ begin
if (select status from public.project_applications where id=pg_temp.tid('application'))<>'reviewing' then raise exception 'FAIL staff withdrawal changed candidate application to withdrawn';end if;
if not exists(select 1 from public.shortlist_activity where review_id=pg_temp.tid('review') and kind='staff_withdrawal' and message='Availability changed during follow-up.') then raise exception 'FAIL missing withdrawal history';end if;
end $$;
select pg_temp.claim('superuser');
do $$ begin
if exists(select 1 from public.client_submissions where id=pg_temp.tid('submission')) then raise exception 'FAIL withdrawn submission visible';end if;
if exists(select 1 from public.shortlist_activity where submission_id=pg_temp.tid('submission')) then raise exception 'FAIL revoked discussion visible';end if;
begin perform public.shortlist_action('feedback',jsonb_build_object('id',pg_temp.tid('submission'),'revision',3,'decision','question','message','Stale browser action'));raise exception 'FAIL revoked action allowed';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
end $$;
-- Reissue is deliberate, with a new record and a new conversation confirmation.
select pg_temp.claim('staff_reader');
select public.shortlist_action('reset',jsonb_build_object('id',pg_temp.tid('review'),'revision',5,'message','Candidate availability discussed again.'));
select public.shortlist_action('submit',pg_temp.packet());
select pg_temp.claim('candidate_user');
update public.project_applications set status='withdrawn' where id=pg_temp.tid('application');
select pg_temp.claim('superuser');
do $$ begin if exists(select 1 from public.client_submissions where review_id=pg_temp.tid('review')) then raise exception 'FAIL candidate application withdrawal did not revoke access';end if;end $$;
reset role;
select 'PASS: recruiter submission, atomic validation, decimal ratings, actor isolation, assignment, audit and withdrawal' as result;
rollback;
