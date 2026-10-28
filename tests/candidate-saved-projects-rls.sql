-- Transaction-only fixtures. Nothing from this test remains in the database.
begin;
insert into auth.users(id,email,role,aud,raw_app_meta_data,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000701','benchpro-demo+saved-a@example.com','authenticated','authenticated','{}','{}'),
('00000000-0000-4000-8000-000000000702','benchpro-demo+saved-b@example.com','authenticated','authenticated','{}','{}');
insert into public.project_listings(id,title,category,summary,description,requirements,skills,work_mode,location,duration,experience,status,is_demo,expires_at)
select ('00000000-0000-4000-8000-00000000080'||n)::uuid,'Transaction-only security fixture','Engineering','Uncommitted test only. Not a genuine project.','This listing exists only in this rolled-back test transaction.',array['SQL'],array['SQL'],'Remote','India','6 months','5+ years',case n when 2 then 'draft' when 3 then 'closed' else 'published' end,n=5,case when n=4 then now()-interval '1 day' else null end from generate_series(1,5)n;
set local role anon;
do $$ begin
  begin perform 1 from public.candidate_saved_projects;raise exception 'Anonymous bookmark access';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000701","role":"authenticated"}',true);
set local role authenticated;
insert into public.candidate_saved_projects(user_id,project_id) values('00000000-0000-4000-8000-000000000701','00000000-0000-4000-8000-000000000801');
do $$ declare n int;begin
  if (select count(*) from public.candidate_saved_projects)<>1 then raise exception 'Own bookmark unreadable';end if;
  begin insert into public.candidate_saved_projects(user_id,project_id) values('00000000-0000-4000-8000-000000000702','00000000-0000-4000-8000-000000000801');raise exception 'Other user bookmark insert allowed';exception when insufficient_privilege then null;end;
  for n in 2..5 loop
    begin insert into public.candidate_saved_projects(user_id,project_id) values('00000000-0000-4000-8000-000000000701',('00000000-0000-4000-8000-00000000080'||n)::uuid);raise exception 'Non-open project saved';exception when insufficient_privilege then null;end;
  end loop;
  begin update public.candidate_saved_projects set user_id='00000000-0000-4000-8000-000000000702';raise exception 'Bookmark ownership changed';exception when insufficient_privilege then null;end;
  begin insert into public.candidate_saved_projects(user_id,project_id) values('00000000-0000-4000-8000-000000000701','00000000-0000-4000-8000-000000000801');raise exception 'Duplicate bookmark';exception when unique_violation then null;end;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000702","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  if exists(select 1 from public.candidate_saved_projects) then raise exception 'Other user bookmark visible';end if;
  delete from public.candidate_saved_projects; if found then raise exception 'Other user bookmark deleted';end if;
end $$;
reset role;
update public.project_listings set status='closed' where id='00000000-0000-4000-8000-000000000801';
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000701","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  if exists(select 1 from public.project_listings where id='00000000-0000-4000-8000-000000000801') then raise exception 'Bookmark exposes closed project';end if;
  delete from public.candidate_saved_projects where project_id='00000000-0000-4000-8000-000000000801';
  if not found then raise exception 'Own closed bookmark cannot be removed';end if;
end $$;
reset role;
rollback;
