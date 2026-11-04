-- Registered-candidate pilot. Raw profiles/applications remain private.
alter table private.benchpro_staff_access add column can_publish_shortlists boolean not null default false;
update private.benchpro_staff_access set can_publish_shortlists=true where email='admin@benchpro.in';

create table public.shortlist_reviews (
  id uuid primary key default gen_random_uuid(),
  staffing_request_id uuid not null references public.staffing_requests(id) on delete restrict,
  candidate_id uuid not null references public.candidate_accounts(id) on delete restrict,
  application_id uuid references public.project_applications(id) on delete restrict,
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  state text not null default 'draft' check(state in ('draft','permission_pending','ready','published','closed')),
  revision integer not null default 1,
  profile jsonb not null default '{}',
  screening_notes text not null default '' check(char_length(screening_notes)<=6000),
  screening_confirmed boolean not null default false,
  availability_confirmed_at timestamptz,
  next_action_at date,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(staffing_request_id,candidate_id), unique(application_id)
);
create index shortlist_reviews_candidate_idx on public.shortlist_reviews(candidate_id);
create index shortlist_reviews_owner_idx on public.shortlist_reviews(owner_user_id,state,next_action_at);

create table public.shortlist_permissions (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references public.shortlist_reviews(id) on delete restrict,
  revision integer not null,
  candidate_id uuid not null references public.candidate_accounts(id) on delete restrict,
  client_id uuid not null references public.clients(id) on delete restrict,
  client_name text not null, role_title text not null,
  profile jsonb not null,
  notice_version text not null default 'client-introduction-v1',
  notice text not null,
  decision text not null default 'pending' check(decision in ('pending','granted','declined','withdrawn','cancelled')),
  requested_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '30 days',
  decided_at timestamptz, unique(review_id,revision)
);
create index shortlist_permissions_candidate_idx on public.shortlist_permissions(candidate_id,requested_at);
create index shortlist_permissions_client_idx on public.shortlist_permissions(client_id);

create table public.client_submissions (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references public.shortlist_reviews(id) on delete restrict,
  permission_id uuid not null unique references public.shortlist_permissions(id) on delete restrict,
  staffing_request_id uuid not null references public.staffing_requests(id) on delete restrict,
  client_id uuid not null references public.clients(id) on delete restrict,
  role_title text not null, profile jsonb not null,
  status text not null default 'awaiting_review' check(status in ('awaiting_review','interview_requested','on_hold','declined')),
  revision integer not null default 1,
  needs_client_response boolean not null default true,
  follow_up_on date,
  published_by uuid not null references auth.users(id) on delete restrict,
  published_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  revoked_at timestamptz
);
create unique index client_submissions_active_review_idx on public.client_submissions(review_id) where revoked_at is null;
create index client_submissions_role_idx on public.client_submissions(staffing_request_id);
create index client_submissions_client_idx on public.client_submissions(client_id,published_at);
create index client_submissions_publisher_idx on public.client_submissions(published_by);

create table public.shortlist_activity (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references public.shortlist_reviews(id) on delete restrict,
  submission_id uuid references public.client_submissions(id) on delete restrict,
  audience text not null check(audience in ('staff','client')),
  kind text not null,
  message text not null check(char_length(message)<=3000),
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  actor_label text not null,
  occurred_at timestamptz not null default now()
);
create index shortlist_activity_review_idx on public.shortlist_activity(review_id,occurred_at);
create index shortlist_activity_submission_idx on public.shortlist_activity(submission_id,occurred_at);
create index shortlist_activity_actor_idx on public.shortlist_activity(actor_user_id);
create unique index shortlist_activity_seen_idx on public.shortlist_activity(submission_id,actor_user_id) where kind='viewed';

create table public.candidate_shortlist_updates (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.candidate_accounts(id) on delete restrict,
  permission_id uuid not null references public.shortlist_permissions(id) on delete restrict,
  title text not null, message text not null,
  occurred_at timestamptz not null default now(), read_at timestamptz
);
create index candidate_shortlist_updates_owner_idx on public.candidate_shortlist_updates(candidate_id,occurred_at);
create index candidate_shortlist_updates_permission_idx on public.candidate_shortlist_updates(permission_id);

create function private.can_publish_shortlists() returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and exists(select 1 from auth.users u join private.benchpro_staff_access s on s.email=lower(u.email) where u.id=auth.uid() and s.can_publish_shortlists);
$$;
create function private.can_review_client_role(target uuid) returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and exists(
    select 1 from public.staffing_requests r join public.client_memberships m on m.client_id=r.client_id
    where r.id=target and m.user_id=auth.uid() and m.status='active'
    and (m.role='superuser' or m.id=r.client_assignee_membership_id)
  );
$$;
revoke all on function private.can_publish_shortlists(),private.can_review_client_role(uuid) from public,anon,authenticated;
grant execute on function private.can_publish_shortlists(),private.can_review_client_role(uuid) to authenticated;

alter table public.shortlist_reviews enable row level security;
alter table public.shortlist_permissions enable row level security;
alter table public.client_submissions enable row level security;
alter table public.shortlist_activity enable row level security;
alter table public.candidate_shortlist_updates enable row level security;
revoke all on public.shortlist_reviews,public.shortlist_permissions,public.client_submissions,public.shortlist_activity,public.candidate_shortlist_updates from public,anon,authenticated;
grant select on public.shortlist_reviews,public.shortlist_permissions,public.client_submissions,public.shortlist_activity,public.candidate_shortlist_updates to authenticated;
grant update(read_at) on public.candidate_shortlist_updates to authenticated;
grant all on public.shortlist_reviews,public.shortlist_permissions,public.client_submissions,public.shortlist_activity,public.candidate_shortlist_updates to service_role;
create policy "Staff read private screening" on public.shortlist_reviews for select to authenticated using((select private.is_benchpro_staff()));
create policy "Staff read introduction permissions" on public.shortlist_permissions for select to authenticated using((select private.is_benchpro_staff()));
create policy "Candidates read their introduction permissions" on public.shortlist_permissions for select to authenticated using(exists(select 1 from public.candidate_accounts c where c.id=candidate_id and c.user_id=(select auth.uid())));
create policy "Staff read submissions" on public.client_submissions for select to authenticated using((select private.is_benchpro_staff()));
create policy "Clients read published submissions for accessible roles" on public.client_submissions for select to authenticated using(revoked_at is null and private.can_review_client_role(staffing_request_id));
create policy "Staff read shortlist history" on public.shortlist_activity for select to authenticated using((select private.is_benchpro_staff()));
create policy "Clients read shared discussions" on public.shortlist_activity for select to authenticated using(audience='client' and exists(select 1 from public.client_submissions s where s.id=submission_id and s.revoked_at is null and private.can_review_client_role(s.staffing_request_id)));
create policy "Candidates read own shortlist updates" on public.candidate_shortlist_updates for select to authenticated using(exists(select 1 from public.candidate_accounts c where c.id=candidate_id and c.user_id=(select auth.uid())));
create policy "Candidates mark own shortlist updates read" on public.candidate_shortlist_updates for update to authenticated using(exists(select 1 from public.candidate_accounts c where c.id=candidate_id and c.user_id=(select auth.uid()))) with check(exists(select 1 from public.candidate_accounts c where c.id=candidate_id and c.user_id=(select auth.uid())));

-- Profiles are generated from an explicit allowlist. No contact, resume storage path,
-- private notes or pay fields can be smuggled into a client packet via JSON.
create function private.shortlist_profile(data jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare out_data jsonb='{}'; k text; v text;
begin
  foreach k in array array['full_name','title','experience','skills','location','availability','summary','project_evidence','requirements_evidence','client_rate'] loop
    v=trim(coalesce(data->>k,''));
    if char_length(v)>(case when k in ('summary','project_evidence','requirements_evidence') then 2500 else 300 end) then raise exception 'A profile field is too long'; end if;
    out_data=out_data||jsonb_build_object(k,v);
  end loop;
  if char_length(out_data->>'full_name')<2 or char_length(out_data->>'title')<2 then raise exception 'Add a name and professional title'; end if;
  return out_data;
end; $$;
revoke all on function private.shortlist_profile(jsonb) from public,anon,authenticated;

-- All state changes are transactional; public tables have no client/staff write grants.
create function private.shortlist_action(action text, payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  who uuid=auth.uid(); staff boolean; r public.shortlist_reviews; p public.shortlist_permissions;
  s public.client_submissions; job public.staffing_requests; cand public.candidate_accounts;
  app public.project_applications; ident uuid; rid uuid; cid uuid; expected integer;
  msg text; label text; safe jsonb; client_name text; outcome text; due date;
begin
  if who is null then raise exception 'Sign in to continue'; end if;
  staff=private.is_benchpro_staff();
  if action='capabilities' then
    if not staff then raise exception 'Staff access required'; end if;
    return jsonb_build_object('can_publish',private.can_publish_shortlists());
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
    return jsonb_build_object('id',ident);
  end if;

  -- Always acquire locks in role -> application -> review -> permission/submission order.
  -- The application-first portion coordinates with candidate withdrawal's row lock.
  if action in ('grant','deny','withdraw_permission') then
    select review_id into rid from public.shortlist_permissions where id=(payload->>'id')::uuid;
  elsif action in ('feedback','viewed','reply') then
    select review_id into rid from public.client_submissions where id=(payload->>'id')::uuid;
  else rid=(payload->>'id')::uuid; end if;
  select * into r from public.shortlist_reviews where id=rid;
  if not found then raise exception 'This introduction is unavailable'; end if;
  -- Hold the role stable while checking its client, lifecycle and current assignee.
  select * into job from public.staffing_requests where id=r.staffing_request_id for share;
  if r.application_id is not null then select * into app from public.project_applications where id=r.application_id for update; end if;
  select * into r from public.shortlist_reviews where id=rid for update;
  select * into cand from public.candidate_accounts where id=r.candidate_id;
  if action in ('grant','deny','withdraw_permission') then
    if cand.user_id<>who then raise exception 'This introduction is unavailable'; end if;
  elsif action in ('feedback','viewed') then
    perform 1 from public.client_memberships where client_id=job.client_id and user_id=who and status='active' for share;
    if not private.can_review_client_role(r.staffing_request_id) then raise exception 'This introduction is unavailable'; end if;
  elsif not staff then raise exception 'Staff access required'; end if;
  select company_name into client_name from public.clients where id=job.client_id;
  if action in ('save','request_permission','publish','reset') then
    expected=(payload->>'revision')::integer;
    if expected is null or expected<>r.revision then raise exception 'This review changed. Refresh before continuing'; end if;
  end if;
  if action in ('save','request_permission','publish') and (job.client_id is null or job.status='closed' or (app.id is not null and app.status in ('withdrawn','closed','rejected','placed'))) then raise exception 'The role or application is no longer active'; end if;
  label=case when staff then 'BenchPro team' else coalesce((select email from public.client_memberships where user_id=who and client_id=job.client_id and status='active' limit 1),'Client team') end;

  if action='save' then
    if r.state<>'draft' then raise exception 'Start a revision before editing an introduction already sent for approval'; end if;
    safe=private.shortlist_profile(payload->'profile');
    update public.shortlist_reviews set profile=safe,screening_notes=left(coalesce(payload->>'screening_notes',''),6000),screening_confirmed=coalesce((payload->>'screening_confirmed')::boolean,false),availability_confirmed_at=case when coalesce((payload->>'availability_confirmed')::boolean,false) then now() end,next_action_at=nullif(payload->>'next_action_at','')::date,revision=revision+1,updated_at=now() where id=r.id;
  elsif action='request_permission' then
    if r.state<>'draft' or not r.screening_confirmed or r.availability_confirmed_at is null or r.availability_confirmed_at<now()-interval '14 days' then raise exception 'Complete screening and confirm current availability first'; end if;
    if char_length(r.profile->>'summary')<20 or char_length(r.profile->>'project_evidence')<20 or char_length(r.profile->>'requirements_evidence')<20 then raise exception 'Add a recommendation, project evidence and requirement evidence (20 characters each)'; end if;
    insert into public.shortlist_permissions(review_id,revision,candidate_id,client_id,client_name,role_title,profile,notice) values(r.id,r.revision,r.candidate_id,job.client_id,client_name,job.role_or_skills,r.profile,'I authorise BenchPro to share this approved professional profile with '||client_name||' for '||job.role_or_skills||'. The client may review it and provide feedback to BenchPro. This does not accept an offer. I can withdraw this introduction from my workspace. Copies already viewed or saved cannot be recalled.') returning * into p;
    update public.shortlist_reviews set state='permission_pending',revision=revision+1,updated_at=now() where id=r.id;
    insert into public.candidate_shortlist_updates(candidate_id,permission_id,title,message) values(r.candidate_id,p.id,'Approve a client introduction',client_name||' · '||job.role_or_skills||'. Review the exact profile before deciding.');
  elsif action in ('grant','deny','withdraw_permission') then
    select * into p from public.shortlist_permissions where id=(payload->>'id')::uuid and review_id=r.id for update;
    if not found then raise exception 'This introduction is unavailable'; end if;
    outcome=case action when 'grant' then 'granted' when 'deny' then 'declined' else 'withdrawn' end;
    if p.decision=outcome then return jsonb_build_object('id',r.id); end if;
    if action='withdraw_permission' then
      if p.decision not in ('pending','granted') then raise exception 'This introduction is no longer active'; end if;
    elsif p.decision<>'pending' or p.expires_at<=now() or r.state<>'permission_pending' or job.client_id<>p.client_id or job.status='closed' or (app.id is not null and app.status in ('withdrawn','closed','rejected','placed')) then raise exception 'This permission request is no longer active'; end if;
    update public.shortlist_permissions set decision=outcome,decided_at=now() where id=p.id;
    update public.shortlist_reviews set state=case when action='grant' then 'ready' else 'closed' end,revision=revision+1,updated_at=now() where id=r.id;
    if action='withdraw_permission' then update public.client_submissions set revoked_at=now(),updated_at=now() where review_id=r.id and revoked_at is null; end if;
    insert into public.shortlist_activity(review_id,audience,kind,message,actor_user_id,actor_label) values(r.id,'staff',outcome,'Candidate '||outcome||' this introduction.',who,'Candidate');
    insert into public.candidate_shortlist_updates(candidate_id,permission_id,title,message) values(r.candidate_id,p.id,case action when 'grant' then 'Introduction approved' when 'deny' then 'Introduction declined' else 'Introduction withdrawn' end,client_name||' · '||job.role_or_skills);
  elsif action='publish' then
    if not private.can_publish_shortlists() then raise exception 'Publisher approval is required'; end if;
    select * into s from public.client_submissions where review_id=r.id and revoked_at is null;
    if found and r.state='published' then return jsonb_build_object('id',r.id,'submission_id',s.id); end if;
    select * into p from public.shortlist_permissions where review_id=r.id and decision='granted' order by requested_at desc limit 1 for update;
    if r.state<>'ready' or not found or p.client_id<>job.client_id or p.profile<>r.profile or p.expires_at<=now() then raise exception 'Current candidate permission is required'; end if;
    if not coalesce((payload->>'approved')::boolean,false) then raise exception 'Review and approve the client profile before publishing'; end if;
    if r.availability_confirmed_at<now()-interval '14 days' then raise exception 'Availability is stale. Start a revision and reconfirm it'; end if;
    insert into public.client_submissions(review_id,permission_id,staffing_request_id,client_id,role_title,profile,published_by,follow_up_on) values(r.id,p.id,r.staffing_request_id,job.client_id,job.role_or_skills,p.profile,who,coalesce(r.next_action_at,current_date+2)) returning * into s;
    update public.shortlist_reviews set state='published',revision=revision+1,updated_at=now() where id=r.id;
    if app.id is not null then update public.project_applications set status='client_review' where id=app.id; end if;
    insert into public.shortlist_activity(review_id,submission_id,audience,kind,message,actor_user_id,actor_label) values(r.id,s.id,'client','published','BenchPro shared this approved profile for your review.',who,'BenchPro team');
    insert into public.candidate_shortlist_updates(candidate_id,permission_id,title,message) values(r.candidate_id,p.id,'Your profile has been shared',client_name||' is reviewing your approved profile for '||job.role_or_skills||'.');
  elsif action='reset' then
    if char_length(trim(coalesce(payload->>'message','')))<5 then raise exception 'Add a reason for the revision'; end if;
    update public.shortlist_permissions set decision='cancelled',decided_at=now() where review_id=r.id and decision in ('pending','granted');
    update public.client_submissions set revoked_at=now(),updated_at=now() where review_id=r.id and revoked_at is null;
    insert into public.candidate_shortlist_updates(candidate_id,permission_id,title,message) select r.candidate_id,p2.id,'Introduction paused for revision','BenchPro will request permission again before sharing a revised profile.' from public.shortlist_permissions p2 where p2.review_id=r.id order by p2.requested_at desc limit 1;
    update public.shortlist_reviews set state='draft',screening_confirmed=false,availability_confirmed_at=null,revision=revision+1,updated_at=now() where id=r.id;
    insert into public.shortlist_activity(review_id,audience,kind,message,actor_user_id,actor_label) values(r.id,'staff','revision',left(payload->>'message',3000),who,'BenchPro team');
  elsif action in ('feedback','viewed','reply') then
    select * into s from public.client_submissions where id=(payload->>'id')::uuid and review_id=r.id and revoked_at is null for update;
    if not found then raise exception 'This introduction is no longer available'; end if;
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
      insert into public.candidate_shortlist_updates(candidate_id,permission_id,title,message) values(r.candidate_id,s.permission_id,case outcome when 'interview_requested' then 'Interview coordination requested' else 'Client review completed' end,case outcome when 'interview_requested' then client_name||' would like to discuss '||job.role_or_skills||'. BenchPro will coordinate next steps; an interview is not yet scheduled.' else client_name||' is not proceeding with this introduction. This does not affect your other opportunities.' end);
      if outcome='declined' and app.id is not null then update public.project_applications set status='rejected' where id=app.id; end if;
    end if;
  else raise exception 'Unknown shortlist action'; end if;
  return jsonb_build_object('id',r.id,'submission_id',s.id);
end; $$;
revoke all on function private.shortlist_action(text,jsonb) from public,anon,authenticated;
grant execute on function private.shortlist_action(text,jsonb) to authenticated;
create function public.shortlist_action(action text,payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$ select private.shortlist_action(action,payload); $$;
revoke all on function public.shortlist_action(text,jsonb) from public,anon,authenticated;
grant execute on function public.shortlist_action(text,jsonb) to authenticated;

-- Candidate withdrawals also revoke client access, even from older application UIs.
create function private.withdraw_shortlist_application() returns trigger language plpgsql security definer set search_path='' as $$
declare r public.shortlist_reviews; p public.shortlist_permissions;
begin
  if new.status='withdrawn' and old.status is distinct from new.status then
    for r in select * from public.shortlist_reviews where application_id=new.id for update loop
      update public.client_submissions set revoked_at=now(),updated_at=now() where review_id=r.id and revoked_at is null;
      update public.shortlist_permissions set decision='withdrawn',decided_at=now() where review_id=r.id and decision in ('pending','granted');
      update public.shortlist_reviews set state='closed',revision=revision+1,updated_at=now() where id=r.id;
      insert into public.shortlist_activity(review_id,audience,kind,message,actor_user_id,actor_label) values(r.id,'staff','withdrawn','Candidate application withdrawn; client access revoked.',auth.uid(),'Candidate');
    end loop;
  end if;
  return new;
end; $$;
revoke all on function private.withdraw_shortlist_application() from public,anon,authenticated;
create trigger withdraw_shortlist_application after update of status on public.project_applications for each row execute function private.withdraw_shortlist_application();

-- A source-link edit must never move an existing client submission to another company.
create function private.protect_shortlist_role_link() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_table_name='staffing_requests' then
    if new.client_id is distinct from old.client_id and exists(select 1 from public.shortlist_reviews where staffing_request_id=old.id) then raise exception 'This role has introductions. Create a separate role for another client'; end if;
  else
    if new.staffing_request_id is distinct from old.staffing_request_id and exists(select 1 from public.shortlist_reviews r join public.project_applications a on a.id=r.application_id where a.project_id=old.project_id) then raise exception 'This listing has introductions. Its client role link is locked'; end if;
  end if;
  return new;
end; $$;
revoke all on function private.protect_shortlist_role_link() from public,anon,authenticated;
create trigger protect_shortlist_client_link before update of client_id on public.staffing_requests for each row execute function private.protect_shortlist_role_link();
create trigger protect_shortlist_listing_link before update of staffing_request_id on public.project_listing_sources for each row execute function private.protect_shortlist_role_link();

comment on table public.client_submissions is 'Approved snapshot only. Registered candidate pilot. Original resumes, recruiting notes and candidate pay remain private.';
comment on table public.shortlist_permissions is 'Candidate-approved, role-specific disclosure. Immutable packet; changes require a new request.';

-- The parent write is authorised by RLS or the explicit shortlist RPC. This trigger
-- records it without exposing a public event-insertion API (including client decisions).
create or replace function private.record_candidate_application_event() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='INSERT' then
    insert into public.candidate_application_events(application_id,status) values(new.id,new.status);
  elsif new.status is distinct from old.status then
    insert into public.candidate_application_events(application_id,status) values(new.id,new.status);
  end if;
  return new;
end; $$;
revoke all on function private.record_candidate_application_event() from public,anon,authenticated;
create function private.protect_managed_application_stage() returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if current_user='authenticated' and new.status is distinct from old.status and new.status<>'withdrawn'
    and (new.status='client_review' or exists(select 1 from public.shortlist_reviews where application_id=old.id)) then
    raise exception 'Use the recruiting desk to progress this introduction';
  end if;
  return new;
end; $$;
revoke all on function private.protect_managed_application_stage() from public,anon,authenticated;
create trigger protect_managed_application_stage before update of status on public.project_applications for each row execute function private.protect_managed_application_stage();
notify pgrst,'reload schema';
