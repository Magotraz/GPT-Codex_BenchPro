begin;
insert into auth.users(id,email) values
('00000000-0000-4000-8000-000000000a01','benchpro-demo+phase2-owner@example.com'),
('00000000-0000-4000-8000-000000000a02','benchpro-demo+phase2-other@example.com');
insert into public.candidate_accounts(id,user_id,full_name,primary_role) values
('00000000-0000-4000-8000-000000000a03','00000000-0000-4000-8000-000000000a01','QA Candidate','Data Engineer');
insert into public.project_listings(id,title,category,summary,description,requirements,skills,work_mode,location,duration,experience,is_demo,client_display_name)
values('00000000-0000-4000-8000-000000000a04','QA Phase Two Role','Data & AI','Temporary transaction-only QA project','Temporary project for transaction-only access policy checks',array['SQL experience'],array['SQL'],'Remote','India','6 months','5 years',true,'DEMO | Phase Two QA');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into public.project_applications(id,project_id,candidate_id,availability,consent)
values('00000000-0000-4000-8000-000000000a05','00000000-0000-4000-8000-000000000a04','00000000-0000-4000-8000-000000000a03','available',true);
update public.project_applications set status='reviewing' where id='00000000-0000-4000-8000-000000000a05';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000a02","role":"authenticated"}',true);
do $$ begin
if exists(select 1 from public.candidate_application_events where application_id='00000000-0000-4000-8000-000000000a05') then raise exception 'Other user can read activity'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000a01","role":"authenticated"}',true);
do $$ begin
if (select count(*) from public.candidate_application_events where application_id='00000000-0000-4000-8000-000000000a05') <> 2 then raise exception 'Owner history missing'; end if;
begin
insert into public.candidate_application_events(application_id,status) values('00000000-0000-4000-8000-000000000a05','offer');
raise exception 'Owner could forge activity';
exception when insufficient_privilege then null; end;
begin
update public.project_applications set status='offer' where id='00000000-0000-4000-8000-000000000a05';
raise exception 'Owner could promote application';
exception when insufficient_privilege then null; end;
update public.candidate_accounts set preferred_work_mode='Remote',weekly_hours=40 where id='00000000-0000-4000-8000-000000000a03';
update public.project_applications set status='withdrawn' where id='00000000-0000-4000-8000-000000000a05';
if (select count(*) from public.candidate_application_events where application_id='00000000-0000-4000-8000-000000000a05') <> 3 then raise exception 'Withdrawal history missing'; end if;
end $$;
reset role;
select 'PASS: event recording, owner read, other-user isolation, immutable events, stage protection, preference save and withdrawal' as result;
rollback;
