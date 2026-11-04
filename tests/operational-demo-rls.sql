-- Append to seed inside a transaction, or run against the seeded dataset. Always roll back.
begin;
do $$
begin
  if (select count(*) from public.candidate_accounts where is_demo)<>20 then raise exception 'Expected 20 sample candidates';end if;
  if (select count(*) from public.staffing_requests where is_demo)<>10 then raise exception 'Expected 10 sample roles';end if;
  if (select count(*) from public.clients where is_demo)<>6 then raise exception 'Expected 6 sample clients';end if;
  if exists(select 1 from public.staffing_requests where is_demo and (company_name not like 'DEMO | %' or work_email not like 'benchpro-demo+%@example.com')) then raise exception 'Invalid sample markers';end if;
  if exists(select 1 from public.candidate_accounts c join public.talent_profiles t on t.id=c.id where c.is_demo and not t.is_demo) then raise exception 'Candidate mirror lost sample flag';end if;
  if exists(select 1 from auth.users where raw_app_meta_data->>'benchpro_demo_batch'='operations-2026-11' and (banned_until is null or banned_until<=now() or encrypted_password is not null)) then raise exception 'Sample identity may sign in';end if;
end $$;
-- Staff can use real workflows on demo records, but cannot mix them with real clients.
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from auth.users where email='admin@benchpro.in'),'email','admin@benchpro.in','role','authenticated')::text,true);
set local role authenticated;
do $$ declare cand uuid; real_role uuid; r public.shortlist_reviews; s public.client_submissions; published jsonb;
begin
  select id into cand from public.candidate_accounts where is_demo limit 1;
  select id into real_role from public.staffing_requests where not is_demo and client_id is not null and status<>'closed' limit 1;
  if real_role is not null then
    begin
      perform public.shortlist_action('create',jsonb_build_object('candidate_id',cand,'staffing_request_id',real_role));
      raise exception 'FAIL: sample candidate sent to real role';
    exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
  end if;
  select sr.* into r from public.shortlist_reviews sr join public.candidate_accounts c on c.id=sr.candidate_id where c.is_demo and sr.state='draft' limit 1;
  if r.id is null then raise exception 'Missing draft test submission'; end if;
  published=public.shortlist_action('submit',jsonb_build_object('id',r.id,'revision',r.revision,'profile',r.profile,
    'fit_rating',4.7,'screening_confirmed',true,'candidate_discussed',true,'screening_notes','Sample QA discussion'));
  select * into s from public.client_submissions where review_id=r.id and revoked_at is null;
  if s.id is null or s.fit_rating<>4.7 then raise exception 'Sample submission did not publish';end if;
  perform public.shortlist_action('rate',jsonb_build_object('id',s.id,'revision',s.revision,'fit_rating',4.9));
  select * into r from public.shortlist_reviews where id=r.id;
  perform public.shortlist_action('withdraw',jsonb_build_object('id',r.id,'revision',r.revision,'message','Sample QA availability change'));
  if (select revoked_at from public.client_submissions where id=s.id) is null then raise exception 'Withdrawal failed';end if;
  if (select status from public.project_applications where id=r.application_id)<>'reviewing' then raise exception 'Withdrawal damaged application';end if;
  begin update public.clients set is_demo=false where is_demo;raise exception 'FAIL: demo classification removed';
  exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
end $$;
reset role;
-- A client's own shortlist is visible; withdrawn samples remain absent.
select set_config('request.jwt.claims',jsonb_build_object('sub',(select user_id from public.client_memberships where email='benchpro-demo+showcase-client-2-1@example.com'),'email','benchpro-demo+showcase-client-2-1@example.com','role','authenticated')::text,true);
set local role authenticated;
do $$ begin
  if not exists(select 1 from public.client_submissions where status='interview_requested') then raise exception 'Sample client shortlist missing';end if;
  if exists(select 1 from public.client_submissions where revoked_at is not null) then raise exception 'Withdrawn profiles visible';end if;
end $$;
reset role;
-- Anonymous visitors never get sample profiles, projects or private client data.
select set_config('request.jwt.claims','{}',true);
set local role anon;
do $$ begin
  if exists(select 1 from public.project_listings where is_demo) then raise exception 'Sample jobs leaked publicly';end if;
end $$;
reset role;
select 'Operational sample isolation and staff workflow passed' as result;
rollback;
