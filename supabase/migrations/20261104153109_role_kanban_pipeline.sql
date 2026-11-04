-- Extend the existing controlled submission system; no profiles are auto-published.
alter table public.shortlist_reviews
  alter column candidate_id drop not null,
  add column talent_profile_id uuid references public.talent_profiles(id) on delete restrict,
  add column screening_stage text not null default 'screening' check(screening_stage in ('new','screening')),
  add column source_kind text not null default 'network' check(source_kind in ('applicant','network','sourced')),
  add column client_document_path text,
  add column client_document_name text,
  add constraint shortlist_one_identity check(num_nonnulls(candidate_id,talent_profile_id)=1),
  add constraint shortlist_source_application check(application_id is null or candidate_id is not null);
create unique index shortlist_reviews_talent_role_idx on public.shortlist_reviews(staffing_request_id,talent_profile_id) where talent_profile_id is not null;
create index shortlist_reviews_talent_idx on public.shortlist_reviews(talent_profile_id);
update public.shortlist_reviews set source_kind='applicant' where application_id is not null;
alter table public.client_submissions
  add column pipeline_stage text not null default 'client_review' check(pipeline_stage in ('client_review','interview','offer','onboarding','started')),
  add column stage_detail text not null default 'Awaiting review' check(char_length(stage_detail)<=80),
  add column stage_entered_at timestamptz not null default now(),
  add column client_document_path text,
  add column client_document_name text;
update public.client_submissions set pipeline_stage=case when status='interview_requested' then 'interview' else 'client_review' end,
  stage_detail=case when status='interview_requested' then 'Interview requested' else 'Awaiting review' end,stage_entered_at=published_at;
create index client_submissions_pipeline_idx on public.client_submissions(client_id,pipeline_stage,stage_entered_at) where revoked_at is null;

-- Match sample classification for either a registered or a sourced person.
create or replace function private.protect_demo_relationship() returns trigger
language plpgsql security invoker set search_path='' as $$
declare left_demo boolean; right_demo boolean;
begin
  if tg_table_name='shortlist_reviews' then
    if new.candidate_id is not null then select is_demo into left_demo from public.candidate_accounts where id=new.candidate_id;
    else select is_demo into left_demo from public.talent_profiles where id=new.talent_profile_id; end if;
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
    left_demo=new.is_demo; select is_demo into right_demo from public.clients where id=new.client_id;
  end if;
  if left_demo is null or right_demo is null or left_demo<>right_demo then raise exception 'Test and real records cannot be connected. Choose records from the same dataset.'; end if;
  return new;
end $$;
drop trigger protect_demo_relationship on public.shortlist_reviews;
create trigger protect_demo_relationship before insert or update of candidate_id,talent_profile_id,staffing_request_id on public.shortlist_reviews for each row execute function private.protect_demo_relationship();
create trigger protect_demo_classification before update of is_demo on public.talent_profiles for each row execute function private.protect_demo_classification();

-- Compatibility with existing feedback clients: an interview request is not a booking.
create function private.sync_submission_stage() returns trigger language plpgsql set search_path='' as $$
begin
  if new.status='interview_requested' and old.status is distinct from new.status and new.pipeline_stage=old.pipeline_stage then
    new.pipeline_stage='interview'; new.stage_detail='Interview requested';
  end if;
  if new.pipeline_stage is distinct from old.pipeline_stage then new.stage_entered_at=now(); end if;
  return new;
end $$;
revoke all on function private.sync_submission_stage() from public,anon,authenticated;
create trigger sync_submission_stage before update on public.client_submissions for each row execute function private.sync_submission_stage();

-- Only deliberately prepared client documents belong here; original resumes stay private.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('client-profile-documents','client-profile-documents',false,10485760,array['application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document']) on conflict(id) do nothing;
create policy "Staff upload approved profile documents" on storage.objects for insert to authenticated with check(bucket_id='client-profile-documents' and (select private.is_benchpro_staff()) and (storage.foldername(name))[1]='reviews' and exists(select 1 from public.shortlist_reviews r where r.id::text=(storage.foldername(name))[2] and r.state='draft'));
create policy "Staff read approved profile documents" on storage.objects for select to authenticated using(bucket_id='client-profile-documents' and (select private.is_benchpro_staff()));
create policy "Clients read active approved profile documents" on storage.objects for select to authenticated using(bucket_id='client-profile-documents' and exists(select 1 from public.client_submissions s where s.client_document_path=name and s.revoked_at is null and private.can_review_client_role(s.staffing_request_id)));
-- Uploaded documents are immutable. Revisions use a new path, preserving what was shared.

create or replace function private.shortlist_action(action text, payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  who uuid=auth.uid(); staff boolean; r public.shortlist_reviews; p public.shortlist_permissions;
  s public.client_submissions; job public.staffing_requests; cand public.candidate_accounts;
  talent public.talent_profiles; tid uuid; app public.project_applications; ident uuid; rid uuid; cid uuid; expected integer;
  msg text; label text; safe jsonb; client_name text; outcome text; due date; rating numeric;
begin
  if who is null then raise exception 'Sign in to continue'; end if;
  staff=private.is_benchpro_staff();
  if action in ('request_permission','grant','deny','withdraw_permission') then
    raise exception 'Candidate approval requests have been replaced. Refresh your workspace';
  end if;
  if action='submit' then
    -- Saving and publishing are one transaction: failure cannot leave a partial submission.
    perform private.shortlist_action('save',payload);
    return private.shortlist_action('publish',payload||jsonb_build_object('revision',(payload->>'revision')::integer+1));
  end if;
  if action='capabilities' then
    if not staff then raise exception 'Staff access required'; end if;
    return jsonb_build_object('can_publish',true);
  end if;
  if action='create' then
    if not staff then raise exception 'Staff access required'; end if;
    rid=(payload->>'staffing_request_id')::uuid; cid=(payload->>'candidate_id')::uuid;
    select * into job from public.staffing_requests where id=rid for update;
    if not found or job.client_id is null or job.status='closed' then raise exception 'Choose an open role linked to a client'; end if;
    tid=nullif(payload->>'talent_profile_id','')::uuid;
    if cid is null and tid is not null then select id into cid from public.candidate_accounts where id=tid; if found then tid=null; end if; end if;
    if cid is null and tid is not null then
      select * into talent from public.talent_profiles where id=tid and is_active;
      if not found then raise exception 'Choose an active talent profile'; end if;
      if talent.is_demo is distinct from job.is_demo then raise exception 'Test and real records cannot be connected'; end if;
      safe=private.shortlist_profile(jsonb_build_object('full_name',talent.full_name,'title',talent.primary_role,'experience',coalesce(talent.years_experience::text,'')||' years','skills',array_to_string(talent.skills,', '),'location',talent.country_or_timezone,'availability',replace(talent.availability,'_',' '),'summary',coalesce(talent.profile_summary,'')));
      insert into public.shortlist_reviews(staffing_request_id,talent_profile_id,owner_user_id,profile,source_kind)
        values(rid,tid,who,safe,'sourced') on conflict(staffing_request_id,talent_profile_id) where talent_profile_id is not null do nothing returning id into ident;
      if ident is null then select id into ident from public.shortlist_reviews where staffing_request_id=rid and talent_profile_id=tid; end if;
      return jsonb_build_object('id',ident);
    end if;
    if tid is not null then raise exception 'Choose one candidate'; end if;
    select * into cand from public.candidate_accounts where id=cid;
    if not found then raise exception 'Choose a candidate'; end if;
    if nullif(payload->>'application_id','') is not null then
      select * into app from public.project_applications where id=(payload->>'application_id')::uuid for update;
      if not found or app.candidate_id<>cid or app.status in ('withdrawn','closed','rejected','placed') or not exists(select 1 from public.project_listing_sources x where x.project_id=app.project_id and x.staffing_request_id=rid) then raise exception 'Application must be active and linked to this role'; end if;
    else
      select a.* into app from public.project_applications a join public.project_listing_sources x on x.project_id=a.project_id where a.candidate_id=cid and x.staffing_request_id=rid for update of a;
      if found and app.status in ('withdrawn','closed','rejected','placed') then raise exception 'This application is no longer active'; end if;
    end if;
    safe=private.shortlist_profile(jsonb_build_object('full_name',cand.full_name,'title',cand.primary_role,'experience',case when cand.years_experience is null then '' else cand.years_experience||' years' end,'skills',array_to_string(cand.skills,', '),'location',coalesce(cand.preferred_location,cand.country_or_timezone),'availability',replace(cand.availability,'_',' '),'summary','','project_evidence','','requirements_evidence','','client_rate',''));
    insert into public.shortlist_reviews(staffing_request_id,candidate_id,application_id,owner_user_id,profile,source_kind) values(rid,cid,app.id,who,safe,case when app.id is null then 'network' else 'applicant' end) on conflict(staffing_request_id,candidate_id) do nothing returning id into ident;
    if ident is null then select id into ident from public.shortlist_reviews where staffing_request_id=rid and candidate_id=cid; end if;
    if app.id is not null then
      update public.shortlist_reviews set application_id=app.id where id=ident and application_id is null;
      if app.status='submitted' then update public.project_applications set status='reviewing' where id=app.id; end if;
    end if;
    return jsonb_build_object('id',ident);
  end if;

  -- Always acquire locks in role -> application -> review -> permission/submission order.
  -- The application-first portion coordinates with candidate withdrawal's row lock.
  if action in ('grant','deny','withdraw_permission') then
    select review_id into rid from public.shortlist_permissions where id=(payload->>'id')::uuid;
  elsif action in ('feedback','viewed','reply','rate') then
    select review_id into rid from public.client_submissions where id=(payload->>'id')::uuid;
  else rid=(payload->>'id')::uuid; end if;
  select * into r from public.shortlist_reviews where id=rid;
  if not found then raise exception 'This submission is unavailable'; end if;
  -- Hold the role stable while checking its client, lifecycle and current assignee.
  select * into job from public.staffing_requests where id=r.staffing_request_id for share;
  if r.application_id is not null then select * into app from public.project_applications where id=r.application_id for update; end if;
  select * into r from public.shortlist_reviews where id=rid for update;
  select * into cand from public.candidate_accounts where id=r.candidate_id;
  if action in ('grant','deny','withdraw_permission') then
    if cand.user_id<>who then raise exception 'This submission is unavailable'; end if;
  elsif action in ('feedback','viewed') then
    perform 1 from public.client_memberships where client_id=job.client_id and user_id=who and status='active' for share;
    if not private.can_review_client_role(r.staffing_request_id) then raise exception 'This submission is unavailable'; end if;
  elsif not staff then raise exception 'Staff access required'; end if;
  select company_name into client_name from public.clients where id=job.client_id;
  if action in ('save','publish','reset','withdraw') then
    expected=(payload->>'revision')::integer;
    if expected is null or expected<>r.revision then raise exception 'This review changed. Refresh before continuing'; end if;
  end if;
  if action in ('save','publish') and (job.client_id is null or job.status='closed' or (app.id is not null and app.status in ('withdrawn','closed','rejected','placed'))) then raise exception 'The role or application is no longer active'; end if;
  label=case when staff then 'BenchPro team' else coalesce((select email from public.client_memberships where user_id=who and client_id=job.client_id and status='active' limit 1),'Client team') end;

  if action='save' then
    if r.state<>'draft' then raise exception 'Start a revision before editing a shared or historical submission'; end if;
    safe=private.shortlist_profile(payload->'profile');
    rating=nullif(payload->>'fit_rating','')::numeric;
    if rating is not null and (rating<1 or rating>5 or rating<>round(rating,1)) then raise exception 'Enter a fit rating from 1 to 5, with at most one decimal place'; end if;
    update public.shortlist_reviews set screening_stage='screening',profile=safe,fit_rating=rating,candidate_discussed_at=case when coalesce((payload->>'candidate_discussed')::boolean,false) then now() end,candidate_discussed_by=case when coalesce((payload->>'candidate_discussed')::boolean,false) then who end,screening_notes=left(coalesce(payload->>'screening_notes',''),6000),screening_confirmed=coalesce((payload->>'screening_confirmed')::boolean,false),availability_confirmed_at=case when coalesce((payload->>'candidate_discussed')::boolean,false) then now() end,next_action_at=nullif(payload->>'next_action_at','')::date,revision=revision+1,updated_at=now() where id=r.id;
  elsif action='publish' then
    if r.state<>'draft' then raise exception 'Refresh or start a revision before sending this profile'; end if;
    if r.fit_rating is null then raise exception 'Add a BenchPro fit rating before sending'; end if;
    if not r.screening_confirmed or r.candidate_discussed_at is null or r.candidate_discussed_at<now()-interval '14 days' then raise exception 'Confirm screening and the candidate conversation before sending'; end if;
    if char_length(r.profile->>'summary')<20 or char_length(r.profile->>'project_evidence')<20 or char_length(r.profile->>'requirements_evidence')<20 then raise exception 'Add a recommendation, project evidence and requirement evidence (20 characters each)'; end if;
    insert into public.client_submissions(review_id,staffing_request_id,client_id,role_title,profile,fit_rating,published_by,follow_up_on,client_document_path,client_document_name)
      values(r.id,r.staffing_request_id,job.client_id,job.role_or_skills,r.profile,r.fit_rating,who,coalesce(r.next_action_at,current_date+2),r.client_document_path,r.client_document_name) returning * into s;
    update public.shortlist_reviews set state='published',revision=revision+1,updated_at=now() where id=r.id;
    if app.id is not null then update public.project_applications set status='client_review' where id=app.id; end if;
    insert into public.shortlist_activity(review_id,submission_id,audience,kind,message,actor_user_id,actor_label)
      values(r.id,s.id,'client','published','BenchPro shared this profile. Fit rating: '||r.fit_rating||' / 5.',who,'BenchPro team');
    insert into public.shortlist_activity(review_id,submission_id,audience,kind,message,actor_user_id,actor_label)
      values(r.id,s.id,'staff','candidate_discussion','Recruiter confirmed the role discussion, interest and availability before sharing.',who,'BenchPro team');
    if r.candidate_id is not null then insert into public.candidate_shortlist_updates(candidate_id,title,message)
      values(r.candidate_id,'Your profile has been shared',client_name||' is reviewing your professional profile for '||job.role_or_skills||'.'); end if;
  elsif action in ('reset','withdraw') then
    msg=trim(coalesce(payload->>'message',''));
    if char_length(msg)<5 or char_length(msg)>3000 then raise exception 'Add a reason between 5 and 3000 characters'; end if;
    select * into s from public.client_submissions where review_id=r.id and revoked_at is null for update;
    if action='withdraw' and not found then raise exception 'There is no active client submission to withdraw'; end if;
    update public.client_submissions set revoked_at=now(),needs_client_response=false,revision=revision+1,updated_at=now() where review_id=r.id and revoked_at is null;
    update public.shortlist_permissions set decision='cancelled',decided_at=now() where review_id=r.id and decision in ('pending','granted');
    update public.shortlist_reviews set state=case when action='reset' then 'draft' else 'closed' end,screening_confirmed=false,availability_confirmed_at=null,candidate_discussed_at=null,candidate_discussed_by=null,revision=revision+1,updated_at=now() where id=r.id;
    -- A recruiter retracting a presentation is not a candidate withdrawing an application.
    if app.id is not null and app.status in ('client_review','offer') then update public.project_applications set status='reviewing' where id=app.id; end if;
    insert into public.shortlist_activity(review_id,submission_id,audience,kind,message,actor_user_id,actor_label)
      values(r.id,s.id,'staff',case when action='reset' then 'revision' else 'staff_withdrawal' end,msg,who,'BenchPro team');
    if s.id is not null then
      if r.candidate_id is not null then insert into public.candidate_shortlist_updates(candidate_id,title,message)
        values(r.candidate_id,'Client submission withdrawn','BenchPro has withdrawn your profile from review for '||job.role_or_skills||' at '||client_name||'.'||case when app.id is not null then ' Your application has not been withdrawn.' else '' end); end if;
    end if;
  elsif action='rate' then
    select * into s from public.client_submissions where id=(payload->>'id')::uuid and review_id=r.id and revoked_at is null for update;
    if not found then raise exception 'This submission is no longer available'; end if;
    if (payload->>'revision')::integer is distinct from s.revision then raise exception 'Another update was made. Refresh before changing the rating'; end if;
    rating=nullif(payload->>'fit_rating','')::numeric;
    if rating is null or rating<1 or rating>5 or rating<>round(rating,1) then raise exception 'Enter a fit rating from 1 to 5, with at most one decimal place'; end if;
    update public.client_submissions set fit_rating=rating,revision=revision+1,updated_at=now() where id=s.id;
    update public.shortlist_reviews set fit_rating=rating,revision=revision+1,updated_at=now() where id=r.id;
    insert into public.shortlist_activity(review_id,submission_id,audience,kind,message,actor_user_id,actor_label)
      values(r.id,s.id,'client','rating_updated','BenchPro fit rating updated from '||coalesce(s.fit_rating::text,'unrated')||' to '||rating||' / 5.',who,'BenchPro team');
  elsif action in ('feedback','viewed','reply') then
    select * into s from public.client_submissions where id=(payload->>'id')::uuid and review_id=r.id and revoked_at is null for update;
    if not found then raise exception 'This submission is no longer available'; end if;
    if action='viewed' then
      insert into public.shortlist_activity(review_id,submission_id,audience,kind,message,actor_user_id,actor_label) values(r.id,s.id,'staff','viewed','Profile opened by an authorised client user.',who,label) on conflict do nothing;
      return jsonb_build_object('id',r.id);
    end if;
    if (payload->>'revision')::integer is distinct from s.revision then raise exception 'Another update was made. Refresh before responding'; end if;
    if job.status='closed' or s.status='declined' then raise exception 'This submission is closed for new decisions'; end if;
    msg=trim(coalesce(payload->>'message',''));
    if char_length(msg)<5 or char_length(msg)>3000 then raise exception 'Add a message between 5 and 3000 characters'; end if;
    outcome=case when action='reply' then 'reply' else payload->>'decision' end;
    if outcome is null or outcome not in ('question','interview_requested','on_hold','declined','reply') or (outcome='reply' and not staff) then raise exception 'Choose a valid response'; end if;
    due=nullif(payload->>'follow_up_on','')::date;
    if outcome='on_hold' and (due is null or due<current_date or due>current_date+90) then raise exception 'Choose a revisit date within the next 90 days'; end if;
    update public.client_submissions set status=case when outcome in ('question','reply') then status else outcome end,revision=revision+1,needs_client_response=(outcome='reply'),follow_up_on=case when outcome='on_hold' then due else follow_up_on end,updated_at=now() where id=s.id;
    update public.shortlist_reviews set next_action_at=coalesce(due,current_date),updated_at=now() where id=r.id;
    insert into public.shortlist_activity(review_id,submission_id,audience,kind,message,actor_user_id,actor_label) values(r.id,s.id,'client',outcome,msg,who,label);
    if outcome in ('interview_requested','declined') and outcome<>s.status then
      if r.candidate_id is not null then insert into public.candidate_shortlist_updates(candidate_id,permission_id,title,message) values(r.candidate_id,s.permission_id,case outcome when 'interview_requested' then 'Interview coordination requested' else 'Client review completed' end,case outcome when 'interview_requested' then client_name||' would like to discuss '||job.role_or_skills||'. BenchPro will coordinate next steps; an interview is not yet scheduled.' else client_name||' is not proceeding with this submission. This does not affect your other opportunities.' end); end if;
      if outcome='declined' and app.id is not null then update public.project_applications set status='rejected' where id=app.id; end if;
    end if;
  else raise exception 'Unknown shortlist action'; end if;
  return jsonb_build_object('id',r.id,'submission_id',s.id);
end; $$;

revoke all on function private.shortlist_action(text,jsonb) from public,anon,authenticated;
grant execute on function private.shortlist_action(text,jsonb) to authenticated;

create function private.pipeline_action(action text,payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare who uuid=auth.uid(); staff boolean; r public.shortlist_reviews; s public.client_submissions;
  job public.staffing_requests; app public.project_applications; t public.talent_profiles;
  rid uuid; ident uuid; result jsonb; target text; detail text; msg text; label text; source_email text; doc text; due date;
begin
  if who is null then raise exception 'Sign in to continue'; end if;
  staff=private.is_benchpro_staff();
  if action='source' then
    if not staff then raise exception 'Staff access required'; end if;
    select * into job from public.staffing_requests where id=(payload->>'staffing_request_id')::uuid for update;
    if not found or job.client_id is null or job.status='closed' then raise exception 'Choose an open role linked to a client'; end if;
    source_email=lower(trim(payload->>'work_email'));
    if source_email is null or source_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then raise exception 'Enter a valid candidate email'; end if;
    if job.is_demo and source_email !~ '^benchpro-demo[+][^@]+@example[.]com$' then raise exception 'Test candidates need a benchpro-demo+ address at example.com'; end if;
    -- Serialise duplicate checks for concurrent imports of the same address.
    perform pg_advisory_xact_lock(hashtextextended(source_email,0));
    if exists(select 1 from public.talent_profiles where lower(work_email)=source_email) then raise exception 'This email already exists. Choose the person from the talent database'; end if;
    insert into public.talent_profiles(full_name,primary_role,work_email,phone_number,skills,years_experience,country_or_timezone,availability,profile_summary,is_demo,created_by)
      values(trim(payload->>'full_name'),trim(payload->>'primary_role'),source_email,nullif(trim(payload->>'phone_number'),''),
      array(select trim(value) from jsonb_array_elements_text(coalesce(payload->'skills','[]')) where trim(value)<>''),
      nullif(payload->>'years_experience','')::smallint,nullif(payload->>'location',''),coalesce(nullif(payload->>'availability',''),'available'),left(coalesce(payload->>'summary',''),3000),job.is_demo,who) returning * into t;
    result=private.shortlist_action('create',jsonb_build_object('staffing_request_id',job.id,'talent_profile_id',t.id));
    return result||jsonb_build_object('talent_profile_id',t.id);
  end if;
  if action='move' then select review_id into rid from public.client_submissions where id=(payload->>'id')::uuid;
  else rid=(payload->>'id')::uuid; end if;
  select * into r from public.shortlist_reviews where id=rid;
  if not found then raise exception 'This candidate is unavailable'; end if;
  select * into job from public.staffing_requests where id=r.staffing_request_id for share;
  if r.application_id is not null then select * into app from public.project_applications where id=r.application_id for update; end if;
  select * into r from public.shortlist_reviews where id=rid for update;
  if not staff then
    perform 1 from public.client_memberships where client_id=job.client_id and user_id=who and status='active' for share;
    if action<>'move' or not private.can_review_client_role(job.id) then raise exception 'This candidate is unavailable'; end if;
  end if;
  if job.status='closed' or (app.id is not null and app.status in ('withdrawn','closed','rejected','placed')) then raise exception 'The role or application is no longer active'; end if;
  label=case when staff then 'BenchPro team' else coalesce((select email from public.client_memberships where client_id=job.client_id and user_id=who and status='active' limit 1),'Client team') end;
  if action='move' then
    select * into s from public.client_submissions where id=(payload->>'id')::uuid and review_id=r.id and revoked_at is null for update;
    if not found or s.status='declined' then raise exception 'This submission is no longer active'; end if;
    if (payload->>'revision')::integer is distinct from s.revision then raise exception 'Another update was made. Refresh before moving this candidate'; end if;
    target=payload->>'stage'; detail=payload->>'detail'; msg=trim(coalesce(payload->>'message',''));
    if target is null or target not in ('client_review','interview','offer','onboarding','started') then raise exception 'Choose a valid stage'; end if;
    if s.pipeline_stage='started' then raise exception 'A confirmed start is final. Contact BenchPro admin for a correction'; end if;
    if not staff and (s.pipeline_stage in ('onboarding','started') or target not in ('client_review','interview','offer')) then raise exception 'BenchPro confirms onboarding and project starts'; end if;
    if char_length(msg)<5 or char_length(msg)>2000 then raise exception 'Add a short update (5–2000 characters)'; end if;
    if detail is null or not (
      (target='client_review' and detail='Awaiting review') or
      (target='interview' and detail in ('Interview requested','Scheduled','Feedback due','Completed')) or
      (target='offer' and detail in ('Preparing offer','Offer sent','Offer accepted')) or
      (target='onboarding' and detail='Joining in progress') or
      (target='started' and detail='Start confirmed')) then raise exception 'Choose a valid stage detail'; end if;
    if not staff and ((target='interview' and detail='Scheduled') or (target='offer' and detail<>'Preparing offer')) then raise exception 'BenchPro records confirmed schedules and offers'; end if;
    if target='onboarding' and not(s.pipeline_stage='offer' and s.stage_detail='Offer accepted') then raise exception 'Record the accepted offer before onboarding'; end if;
    if target='started' and s.pipeline_stage<>'onboarding' then raise exception 'Complete onboarding before confirming the start'; end if;
    if target in ('onboarding','started') and not coalesce((payload->>'confirmed')::boolean,false) then raise exception 'Confirm this milestone before continuing'; end if;
    due=nullif(payload->>'follow_up_on','')::date;
    update public.client_submissions set pipeline_stage=target,stage_detail=detail,
      status=case when target='interview' then 'interview_requested' else 'awaiting_review' end,
      follow_up_on=due,needs_client_response=(staff and target in ('client_review','interview')),revision=revision+1,updated_at=now() where id=s.id;
    update public.shortlist_reviews set next_action_at=due,revision=revision+1,updated_at=now() where id=r.id;
    if app.id is not null then update public.project_applications set status=case when target='started' then 'placed' when target='onboarding' or (target='offer' and detail in ('Offer sent','Offer accepted')) then 'offer' else 'client_review' end where id=app.id; end if;
    insert into public.shortlist_activity(review_id,submission_id,audience,kind,message,actor_user_id,actor_label)
      values(r.id,s.id,'client','stage_changed',replace(s.pipeline_stage,'_',' ')||' → '||replace(target,'_',' ')||' · '||detail||E'\n'||msg,who,label);
    if r.candidate_id is not null and target in ('onboarding','started') and target<>s.pipeline_stage then
      insert into public.candidate_shortlist_updates(candidate_id,title,message) values(r.candidate_id,case when target='started' then 'Project start confirmed' else 'Onboarding in progress' end,'BenchPro recorded an update for '||job.role_or_skills||'.');
    end if;
    return jsonb_build_object('id',r.id,'submission_id',s.id);
  end if;
  if (payload->>'revision')::integer is distinct from r.revision then raise exception 'This review changed. Refresh before continuing'; end if;
  if r.state<>'draft' then raise exception 'Only a private draft can be changed here'; end if;
  if action='screen' then
    target=payload->>'stage'; if target is null or target not in ('new','screening') then raise exception 'Choose a screening stage'; end if;
    update public.shortlist_reviews set screening_stage=target,revision=revision+1,updated_at=now() where id=r.id;
  elsif action='archive' then
    msg=trim(coalesce(payload->>'message','')); if char_length(msg)<5 or char_length(msg)>2000 then raise exception 'Add a job-related reason'; end if;
    update public.shortlist_reviews set state='closed',revision=revision+1,updated_at=now() where id=r.id;
    if app.id is not null then update public.project_applications set status='rejected' where id=app.id; end if;
  elsif action in ('document','source_resume') then
    doc=nullif(payload->>'path','');
    if doc is not null then
      if action='document' and (doc not like 'reviews/'||r.id||'/%' or not exists(select 1 from storage.objects where bucket_id='client-profile-documents' and name=doc)) then raise exception 'Upload an approved document for this profile first'; end if;
      if action='source_resume' and (r.talent_profile_id is null or doc not like 'candidates/'||r.talent_profile_id||'/%' or not exists(select 1 from storage.objects where bucket_id='candidate-resumes' and name=doc)) then raise exception 'Upload this sourced candidate resume first'; end if;
    end if;
    if action='document' then
      update public.shortlist_reviews set client_document_path=doc,client_document_name=case when doc is null then null else left(payload->>'name',180) end,revision=revision+1,updated_at=now() where id=r.id;
    else
      if r.talent_profile_id is null then raise exception 'Choose a sourced candidate'; end if;
      update public.talent_profiles set resume_file_path=doc,resume_file_name=payload->>'name',resume_file_size=(payload->>'size')::bigint,resume_file_type=payload->>'type',updated_at=now() where id=r.talent_profile_id;
      update public.shortlist_reviews set revision=revision+1,updated_at=now() where id=r.id;
    end if;
  else raise exception 'Unknown pipeline action'; end if;
  insert into public.shortlist_activity(review_id,audience,kind,message,actor_user_id,actor_label) values(r.id,'staff',action,coalesce(msg,'Updated '||replace(action,'_',' ')||coalesce(': '||target,'')),who,label);
  return jsonb_build_object('id',r.id);
end $$;
revoke all on function private.pipeline_action(text,jsonb) from public,anon,authenticated;
grant execute on function private.pipeline_action(text,jsonb) to authenticated;
create function public.pipeline_action(action text,payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$ select private.pipeline_action(action,payload) $$;
revoke all on function public.pipeline_action(text,jsonb) from public,anon,authenticated;
grant execute on function public.pipeline_action(text,jsonb) to authenticated;
notify pgrst,'reload schema';
