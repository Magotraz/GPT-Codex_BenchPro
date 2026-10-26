-- Avoid a policy cycle when application INSERT checks the target listing.
-- This exposes only whether the caller owns an application for the given listing.
create function private.has_own_project_application(target_project_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from public.project_applications a
    join public.candidate_accounts c on c.id=a.candidate_id
    where a.project_id=target_project_id and c.user_id=(select auth.uid())
  );
$$;
revoke all on function private.has_own_project_application(uuid) from public,anon,authenticated;
grant execute on function private.has_own_project_application(uuid) to authenticated;
drop policy "Applicants retain project history" on public.project_listings;
create policy "Applicants retain project history" on public.project_listings
  for select to authenticated using (private.has_own_project_application(id));
