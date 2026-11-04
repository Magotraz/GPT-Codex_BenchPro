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
insert into public.candidate_accounts(id,user_id,full_name,primary_role,skills,profile_summary,is_demo) values(pg_temp.tid('candidate'),pg_temp.tid('candidate_user'),'QA Alex Morgan','Data Engineer',array['SQL','Python'],'INTERNAL RAW PROFILE MUST NOT LEAK',true);
insert into public.project_listings(id,title,category,summary,description,requirements,skills,work_mode,location,duration,experience,is_demo) values(pg_temp.tid('listing'),'QA Data Engineer','Data & AI','Transaction-only shortlist QA project','Transaction-only shortlist QA project description',array['SQL'],array['SQL'],'Remote','India','6 months','5 years',true);
insert into public.project_listing_sources(project_id,staffing_request_id,created_by) values(pg_temp.tid('listing'),pg_temp.tid('role'),pg_temp.tid('staff'));
insert into public.project_applications(id,project_id,candidate_id,availability,consent) values(pg_temp.tid('application'),pg_temp.tid('listing'),pg_temp.tid('candidate'),'available',true);


set local role authenticated;
-- Helpers execute under the caller's actual role and claims.
create function pg_temp.expect_denied(statement text) returns void language plpgsql as $$ begin
  begin execute statement; exception when raise_exception or insufficient_privilege or check_violation then return; end;
  raise exception 'FAIL: operation should have been denied: %',statement;
end $$;
create function pg_temp.packet_for(review uuid) returns jsonb language sql as $$
 select jsonb_build_object('id',r.id,'revision',r.revision,'fit_rating',4.8,'screening_confirmed',true,'candidate_discussed',true,
 'screening_notes','PRIVATE EXPECTATIONS','profile',r.profile||jsonb_build_object('summary','Strong data platform delivery experience confirmed.','project_evidence','Delivered complex data projects with enterprise teams.','requirements_evidence','SQL, Python and cloud experience checked by recruiter.')) from public.shortlist_reviews r where id=review
$$;
create function pg_temp.move_to(sub uuid,target text,detail text) returns jsonb language sql as $$
 select public.pipeline_action('move',jsonb_build_object('id',s.id,'revision',s.revision,'stage',target,'detail',detail,'message','Confirmed next step with the relevant team.','confirmed',true)) from public.client_submissions s where id=sub
$$;
select pg_temp.claim('staff');
insert into shortlist_test_ids values('source_review',(public.pipeline_action('source',jsonb_build_object('staffing_request_id',pg_temp.tid('role'),'full_name','QA Sourced Person','primary_role','Cloud Engineer','work_email','benchpro-demo+sourced@example.com','skills',jsonb_build_array('AWS','Python'),'years_experience',7))->>'id')::uuid);
insert into shortlist_test_ids select 'source_talent',talent_profile_id from public.shortlist_reviews where id=pg_temp.tid('source_review');
reset role;
do $$ begin
 if exists(select 1 from auth.users where email='benchpro-demo+sourced@example.com') then raise exception 'FAIL sourced person got an auth account'; end if;
end $$;
set local role authenticated;
select pg_temp.expect_denied(format($q$select public.pipeline_action('source','{"staffing_request_id":"%s","full_name":"Duplicate Person","primary_role":"Engineer","work_email":"BENCHPRO-DEMO+SOURCED@EXAMPLE.COM"}')$q$,pg_temp.tid('role')));
select pg_temp.expect_denied(format($q$select public.pipeline_action('source','{"staffing_request_id":"%s","full_name":"Real Person","primary_role":"Engineer","work_email":"real@realcompany.in"}')$q$,pg_temp.tid('role')));
-- Real records cannot leak into a test role.
reset role;
insert into public.talent_profiles(full_name,primary_role,work_email,is_demo) values('QA Real Classification','Cloud Engineer','classification@example.com',false) returning id;
set local role authenticated;
select pg_temp.expect_denied(format($q$select public.shortlist_action('create','{"staffing_request_id":"%s","talent_profile_id":"%s"}')$q$,pg_temp.tid('role'),(select id from public.talent_profiles where work_email='classification@example.com')));
-- Private document plus a separate explicitly approved document.
insert into storage.objects(bucket_id,name) values('candidate-resumes','candidates/'||pg_temp.tid('source_talent')||'/'||gen_random_uuid()||'_private.pdf');
select public.pipeline_action('source_resume',jsonb_build_object('id',pg_temp.tid('source_review'),'revision',1,'path',(select name from storage.objects where bucket_id='candidate-resumes' and name like 'candidates/'||pg_temp.tid('source_talent')||'/%'),'name','private.pdf','size',100,'type','application/pdf'));
insert into storage.objects(bucket_id,name) values('client-profile-documents','reviews/'||pg_temp.tid('source_review')||'/approved.pdf');
select public.pipeline_action('document',jsonb_build_object('id',pg_temp.tid('source_review'),'revision',2,'path','reviews/'||pg_temp.tid('source_review')||'/approved.pdf','name','approved.pdf'));
select pg_temp.expect_denied(format($q$select public.pipeline_action('document','{"id":"%s","revision":3,"path":"reviews/other/secret.pdf"}')$q$,pg_temp.tid('source_review')));
select pg_temp.claim('superuser');
do $$ begin
 if exists(select 1 from public.shortlist_reviews) or exists(select 1 from public.talent_profiles) or exists(select 1 from storage.objects) then raise exception 'FAIL private information leaked'; end if;
end $$;
select pg_temp.expect_denied(format($q$select public.pipeline_action('source','{"staffing_request_id":"%s","full_name":"Intruder","primary_role":"Engineer","work_email":"benchpro-demo+intruder@example.com"}')$q$,pg_temp.tid('role')));
select pg_temp.claim('staff');
select public.shortlist_action('submit',pg_temp.packet_for(pg_temp.tid('source_review')));
insert into shortlist_test_ids select 'source_submission',id from public.client_submissions where review_id=pg_temp.tid('source_review');
do $$ begin
 if exists(select 1 from public.candidate_shortlist_updates where candidate_id=pg_temp.tid('candidate')) then raise exception 'FAIL sourced person created unrelated account updates'; end if;
 if (select count(*) from public.shortlist_reviews where talent_profile_id=pg_temp.tid('source_talent'))<>1 then raise exception 'FAIL duplicate role consideration'; end if;
end $$;
-- Re-adding existing talent returns the existing role card.
select public.shortlist_action('create',jsonb_build_object('staffing_request_id',pg_temp.tid('role'),'talent_profile_id',pg_temp.tid('source_talent')));
select pg_temp.claim('other');
do $$ begin if exists(select 1 from public.client_submissions) or exists(select 1 from storage.objects) then raise exception 'FAIL cross-client data exposed'; end if; end $$;
select pg_temp.expect_denied(format($q$select public.pipeline_action('move','{"id":"%s","revision":1,"stage":"interview","detail":"Interview requested","message":"Cross client attempt"}')$q$,pg_temp.tid('source_submission')));
select pg_temp.claim('member');
do $$ begin if exists(select 1 from public.client_submissions) then raise exception 'FAIL unassigned member'; end if;end $$;
reset role;update public.staffing_requests set client_assignee_membership_id=pg_temp.tid('membership') where id=pg_temp.tid('role');set local role authenticated;
do $$ begin
 if not exists(select 1 from public.client_submissions where id=pg_temp.tid('source_submission')) then raise exception 'FAIL assigned member cannot see pipeline'; end if;
 if (select count(*) from storage.objects)<>1 or exists(select 1 from storage.objects where bucket_id='candidate-resumes') then raise exception 'FAIL document isolation'; end if;
end $$;
select pg_temp.move_to(pg_temp.tid('source_submission'),'interview','Interview requested');
select pg_temp.expect_denied(format($q$select public.pipeline_action('move','{"id":"%s","revision":1,"stage":"offer","detail":"Preparing offer","message":"Stale revision attempt"}')$q$,pg_temp.tid('source_submission')));
select pg_temp.expect_denied(format($q$select pg_temp.move_to('%s','started','Start confirmed')$q$,pg_temp.tid('source_submission')));
select pg_temp.expect_denied(format($q$select pg_temp.move_to('%s','offer','Offer accepted')$q$,pg_temp.tid('source_submission')));
select pg_temp.move_to(pg_temp.tid('source_submission'),'offer','Preparing offer');
select pg_temp.claim('staff');
select pg_temp.expect_denied(format($q$select pg_temp.move_to('%s','onboarding','Joining in progress')$q$,pg_temp.tid('source_submission')));
select pg_temp.move_to(pg_temp.tid('source_submission'),'offer','Offer sent');
select pg_temp.move_to(pg_temp.tid('source_submission'),'offer','Offer accepted');
select pg_temp.move_to(pg_temp.tid('source_submission'),'onboarding','Joining in progress');
select pg_temp.move_to(pg_temp.tid('source_submission'),'started','Start confirmed');
do $$ begin
 if (select pipeline_stage from public.client_submissions where id=pg_temp.tid('source_submission'))<>'started' then raise exception 'FAIL start progression'; end if;
 if (select count(*) from public.shortlist_activity where submission_id=pg_temp.tid('source_submission') and kind='stage_changed')<>6 then raise exception 'FAIL stage audit history'; end if;
end $$;
select public.shortlist_action('withdraw',jsonb_build_object('id',pg_temp.tid('source_review'),'revision',(select revision from public.shortlist_reviews where id=pg_temp.tid('source_review')),'message','Review fixture withdrawal and access revocation.'));
select pg_temp.claim('member');
do $$ begin if exists(select 1 from public.client_submissions) or exists(select 1 from storage.objects) or exists(select 1 from public.shortlist_activity) then raise exception 'FAIL withdrawal visibility'; end if;end $$;
-- Registered applicants still share the same pipeline and coarse candidate milestones.
select pg_temp.claim('staff');
insert into shortlist_test_ids values('registered_review',(public.shortlist_action('create',jsonb_build_object('staffing_request_id',pg_temp.tid('role'),'candidate_id',pg_temp.tid('candidate')))->>'id')::uuid);
select public.shortlist_action('submit',pg_temp.packet_for(pg_temp.tid('registered_review')));
insert into shortlist_test_ids select 'registered_submission',id from public.client_submissions where review_id=pg_temp.tid('registered_review');
select pg_temp.move_to(pg_temp.tid('registered_submission'),'offer','Preparing offer');
do $$ begin if (select status from public.project_applications where id=pg_temp.tid('application'))<>'client_review' then raise exception 'FAIL preparing offer invented an offer';end if;end $$;
select pg_temp.move_to(pg_temp.tid('registered_submission'),'offer','Offer sent');
do $$ begin if (select status from public.project_applications where id=pg_temp.tid('application'))<>'offer' then raise exception 'FAIL sent offer milestone missing';end if;end $$;
select pg_temp.claim('candidate_user');
update public.project_applications set status='withdrawn' where id=pg_temp.tid('application');
select pg_temp.claim('superuser');
do $$ begin if exists(select 1 from public.client_submissions) then raise exception 'FAIL candidate withdrawal did not revoke access'; end if;end $$;
reset role;
select 'PASS: sourced identities, duplicate checks, private/approved documents, demo isolation, assigned roles, stage permissions, audit, real offer milestones, and withdrawal' as result;
rollback;
