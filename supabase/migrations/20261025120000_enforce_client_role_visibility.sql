-- Limit client role visibility to client superusers and the member assigned to each role.

drop policy if exists "Client members can read their assigned client roles" on public.staffing_requests;

create policy "Client superusers can read all client roles"
  on public.staffing_requests for select to authenticated
  using (
    client_id is not null
    and (select private.is_client_superuser(client_id))
  );

create policy "Client members can read roles assigned to them"
  on public.staffing_requests for select to authenticated
  using (
    client_id is not null
    and client_assignee_membership_id is not null
    and (select private.is_client_member(client_id))
    and exists (
      select 1
      from public.client_memberships m
      where m.id = staffing_requests.client_assignee_membership_id
        and m.client_id = staffing_requests.client_id
        and m.user_id = (select auth.uid())
        and m.role = 'recruiter'
        and m.status = 'active'
    )
  );

-- Assignment history is limited to superusers and members involved in that assignment.
drop policy if exists "Client members can view assignment history" on public.client_assignment_events;

create policy "Client superusers can view assignment history"
  on public.client_assignment_events for select to authenticated
  using ((select private.is_client_superuser(client_id)));

create policy "Assigned members can view their assignment history"
  on public.client_assignment_events for select to authenticated
  using (
    (select private.is_client_member(client_id))
    and exists (
      select 1
      from public.client_memberships m
      where m.client_id = client_assignment_events.client_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'
        and m.role = 'recruiter'
        and m.id in (
          client_assignment_events.previous_membership_id,
          client_assignment_events.new_membership_id
        )
    )
  );

-- Role documents follow the same visibility as their associated role.
drop policy if exists "Client members can read their own role JDs" on storage.objects;

create policy "Client superusers can read client role JDs"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'client-role-jds'
    and (storage.foldername(name))[1] = 'requests'
    and exists (
      select 1 from public.staffing_requests r
      where r.id::text = (storage.foldername(name))[2]
        and r.client_id is not null
        and (select private.is_client_superuser(r.client_id))
    )
  );

create policy "Assigned members can read assigned role JDs"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'client-role-jds'
    and (storage.foldername(name))[1] = 'requests'
    and exists (
      select 1 from public.staffing_requests r
      join public.client_memberships m
        on m.id = r.client_assignee_membership_id
       and m.client_id = r.client_id
      where r.id::text = (storage.foldername(name))[2]
        and r.client_id is not null
        and m.user_id = (select auth.uid())
        and m.role = 'recruiter'
        and m.status = 'active'
        and (select private.is_client_member(r.client_id))
    )
  );

notify pgrst, 'reload schema';
