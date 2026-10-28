-- Private bookmarks do not create applications or expose private project copy.
create table public.candidate_saved_projects (
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid not null references public.project_listings(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, project_id)
);
create index candidate_saved_projects_project_idx on public.candidate_saved_projects(project_id);
alter table public.candidate_saved_projects enable row level security;
revoke all on public.candidate_saved_projects from public, anon, authenticated;
grant select, delete on public.candidate_saved_projects to authenticated;
grant insert (user_id,project_id) on public.candidate_saved_projects to authenticated;
create policy "Candidates read their own saved projects" on public.candidate_saved_projects
  for select to authenticated using (user_id=(select auth.uid()));
create policy "Candidates save only open published projects" on public.candidate_saved_projects
  for insert to authenticated with check (
    user_id=(select auth.uid()) and exists (
      select 1 from public.project_listings p where p.id=project_id
        and p.status='published' and not p.is_demo
        and (p.expires_at is null or p.expires_at>now())
    )
  );
create policy "Candidates remove their own saved projects" on public.candidate_saved_projects
  for delete to authenticated using (user_id=(select auth.uid()));
comment on table public.candidate_saved_projects is 'Private account bookmarks. Closed or unpublished listing details remain governed by existing listing policies.';
