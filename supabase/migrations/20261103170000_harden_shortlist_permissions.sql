-- Match existing company-domain rules using the current account email, not stale JWT metadata.
create or replace function private.can_review_client_role(target uuid) returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and exists(
    select 1 from public.staffing_requests r
    join public.client_memberships m on m.client_id=r.client_id
    join auth.users u on u.id=m.user_id
    join public.client_email_domains d on d.client_id=m.client_id and d.domain=lower(split_part(u.email,'@',2))
    where r.id=target and m.user_id=auth.uid() and m.status='active'
      and (m.role='superuser' or m.id=r.client_assignee_membership_id)
  );
$$;
revoke all on function private.can_review_client_role(uuid) from public,anon,authenticated;
grant execute on function private.can_review_client_role(uuid) to authenticated;
notify pgrst,'reload schema';
