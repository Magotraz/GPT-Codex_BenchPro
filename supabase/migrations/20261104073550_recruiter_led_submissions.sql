-- Preserve historical decisions. New submissions are recruiter-led.
alter table public.shortlist_reviews
  add column fit_rating numeric check(fit_rating between 1 and 5 and fit_rating=round(fit_rating,1)),
  add column candidate_discussed_at timestamptz,
  add column candidate_discussed_by uuid references auth.users(id);
create index shortlist_reviews_discussed_by_idx on public.shortlist_reviews(candidate_discussed_by);
alter table public.client_submissions
  alter column permission_id drop not null,
  add column fit_rating numeric check(fit_rating between 1 and 5 and fit_rating=round(fit_rating,1));
alter table public.candidate_shortlist_updates alter column permission_id drop not null;
alter table public.candidate_shortlist_updates add column archived_at timestamptz;
-- Retire obsolete action prompts without deleting the candidate's recorded decisions.
update public.candidate_shortlist_updates set archived_at=now()
  where title in ('Approve a client introduction','Introduction paused for revision');

-- Keep actual application milestones consistent with controlled introductions.
create or replace function private.shortlist_action(action text, payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  who uuid=auth.uid(); staff boolean; r public.shortlist_reviews; p public.shortlist_permissions;
  s public.client_submissions; job public.staffing_requests; cand public.candidate_accounts;
  app public.project_applications; ident uuid; rid uuid; cid uuid; expected integer;
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
    select * into cand from public.candidate_accounts where id=cid;
    if not found then raise exception 'Choose a registered candidate'; end if;
    if nullif(payload->>'application_id','') is not null then
      select * into app from public.project_applications where id=(payload->>'application_id')::uuid for update;
      if not found or app.candidate_id<>cid or app.status in ('withdrawn','closed','rejected','placed') or not exists(select 1 from public.project_listing_sources x where x.project_id=app.project_id and x.staffing_request_id=rid) then raise exception 'Application must be active and linked to this role'; end if;
    else
      select a.* into app from public.project_applications a join public.project_listing_sources x on x.project_id=a.project_id where a.candidate_id=cid and x.staffing_request_id=rid for update of a;
      if found and app.status in ('withdrawn','closed','rejected','placed') then raise exception 'This application is no longer active'; end if;
    end if;
    safe=private.shortlist_profile(jsonb_build_object('full_name',cand.full_name,'title',cand.primary_role,'experience',case when cand.years_experience is null then '' else cand.years_experience||' years' end,'skills',array_to_string(cand.skills,', '),'location',coalesce(cand.preferred_location,cand.country_or_timezone),'availability',replace(cand.availability,'_',' '),'summary','','project_evidence','','requirements_evidence','','client_rate',''));
    insert into public.shortlist_reviews(staffing_request_id,candidate_id,application_id,owner_user_id,profile) values(rid,cid,app.id,who,safe) on conflict(staffing_request_id,candidate_id) do nothing returning id into ident;
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
    update public.shortlist_reviews set profile=safe,fit_rating=rating,candidate_discussed_at=case when coalesce((payload->>'candidate_discussed')::boolean,false) then now() end,candidate_discussed_by=case when coalesce((payload->>'candidate_discussed')::boolean,false) then who end,screening_notes=left(coalesce(payload->>'screening_notes',''),6000),screening_confirmed=coalesce((payload->>'screening_confirmed')::boolean,false),availability_confirmed_at=case when coalesce((payload->>'candidate_discussed')::boolean,false) then now() end,next_action_at=nullif(payload->>'next_action_at','')::date,revision=revision+1,updated_at=now() where id=r.id;
  elsif action='publish' then
    if r.state<>'draft' then raise exception 'Refresh or start a revision before sending this profile'; end if;
    if r.fit_rating is null then raise exception 'Add a BenchPro fit rating before sending'; end if;
    if not r.screening_confirmed or r.candidate_discussed_at is null or r.candidate_discussed_at<now()-interval '14 days' then raise exception 'Confirm screening and the candidate conversation before sending'; end if;
    if char_length(r.profile->>'summary')<20 or char_length(r.profile->>'project_evidence')<20 or char_length(r.profile->>'requirements_evidence')<20 then raise exception 'Add a recommendation, project evidence and requirement evidence (20 characters each)'; end if;
    insert into public.client_submissions(review_id,staffing_request_id,client_id,role_title,profile,fit_rating,published_by,follow_up_on)
      values(r.id,r.staffing_request_id,job.client_id,job.role_or_skills,r.profile,r.fit_rating,who,coalesce(r.next_action_at,current_date+2)) returning * into s;
    update public.shortlist_reviews set state='published',revision=revision+1,updated_at=now() where id=r.id;
    if app.id is not null then update public.project_applications set status='client_review' where id=app.id; end if;
    insert into public.shortlist_activity(review_id,submission_id,audience,kind,message,actor_user_id,actor_label)
      values(r.id,s.id,'client','published','BenchPro shared this profile. Fit rating: '||r.fit_rating||' / 5.',who,'BenchPro team');
    insert into public.shortlist_activity(review_id,submission_id,audience,kind,message,actor_user_id,actor_label)
      values(r.id,s.id,'staff','candidate_discussion','Recruiter confirmed the role discussion, interest and availability before sharing.',who,'BenchPro team');
    insert into public.candidate_shortlist_updates(candidate_id,title,message)
      values(r.candidate_id,'Your profile has been shared',client_name||' is reviewing your professional profile for '||job.role_or_skills||'.');
  elsif action in ('reset','withdraw') then
    msg=trim(coalesce(payload->>'message',''));
    if char_length(msg)<5 or char_length(msg)>3000 then raise exception 'Add a reason between 5 and 3000 characters'; end if;
    select * into s from public.client_submissions where review_id=r.id and revoked_at is null for update;
    if action='withdraw' and not found then raise exception 'There is no active client submission to withdraw'; end if;
    update public.client_submissions set revoked_at=now(),needs_client_response=false,revision=revision+1,updated_at=now() where review_id=r.id and revoked_at is null;
    update public.shortlist_permissions set decision='cancelled',decided_at=now() where review_id=r.id and decision in ('pending','granted');
    update public.shortlist_reviews set state=case when action='reset' then 'draft' else 'closed' end,screening_confirmed=false,availability_confirmed_at=null,candidate_discussed_at=null,candidate_discussed_by=null,revision=revision+1,updated_at=now() where id=r.id;
    -- A recruiter retracting a presentation is not a candidate withdrawing an application.
    if app.id is not null and app.status='client_review' then update public.project_applications set status='reviewing' where id=app.id; end if;
    insert into public.shortlist_activity(review_id,submission_id,audience,kind,message,actor_user_id,actor_label)
      values(r.id,s.id,'staff',case when action='reset' then 'revision' else 'staff_withdrawal' end,msg,who,'BenchPro team');
    if s.id is not null then
      insert into public.candidate_shortlist_updates(candidate_id,title,message)
        values(r.candidate_id,'Client submission withdrawn','BenchPro has withdrawn your profile from review for '||job.role_or_skills||' at '||client_name||'.'||case when app.id is not null then ' Your application has not been withdrawn.' else '' end);
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
      insert into public.candidate_shortlist_updates(candidate_id,permission_id,title,message) values(r.candidate_id,s.permission_id,case outcome when 'interview_requested' then 'Interview coordination requested' else 'Client review completed' end,case outcome when 'interview_requested' then client_name||' would like to discuss '||job.role_or_skills||'. BenchPro will coordinate next steps; an interview is not yet scheduled.' else client_name||' is not proceeding with this submission. This does not affect your other opportunities.' end);
      if outcome='declined' and app.id is not null then update public.project_applications set status='rejected' where id=app.id; end if;
    end if;
  else raise exception 'Unknown shortlist action'; end if;
  return jsonb_build_object('id',r.id,'submission_id',s.id);
end; $$;

revoke all on function private.shortlist_action(text,jsonb) from public,anon,authenticated;
grant execute on function private.shortlist_action(text,jsonb) to authenticated;
notify pgrst,'reload schema';
