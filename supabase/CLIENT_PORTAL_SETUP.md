# Client portal deployment prerequisites

The client portal depends on the database migration and the `client-access` Edge Function in this folder. The front end intentionally contains no Supabase service-role key.

## Apply the database migration

Run `supabase/migrations/20261013120000_client_dashboard_access.sql` once in the SQL Editor for project `ttmkcmeqiawrzbvymhal`. It creates client-scoped memberships/domains, RLS policies for client-owned roles and documents, the client-side role assignment field, and an assignment audit trail. It does not insert sample data or alter existing client records.

## Deploy the invitation and membership function

Deploy `supabase/functions/client-access/index.ts` as the `client-access` Edge Function. Supabase supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` to hosted functions. Set the additional secret `APP_SITE_URL` to the production origin, currently `https://benchpro.in`.

The function is configured to require a signed-in user. It only lets BenchPro staff approve/remove domains, load the staff recovery workspace, or invite/restore client superusers; a client superuser can invite same-domain team members and remove their client membership. Removing a member never deletes their Auth account. If they have assigned roles, removal requires transferring those roles to an active teammate. Staff recovery reads use the function's service role only after checking the signed-in account against the BenchPro staff allowlist, so the staff recovery view does not depend on browser-side client-table RLS access.

## Allow invite redirects

In Supabase Authentication URL Configuration, allow `https://benchpro.in/client.html` as a redirect URL. Configure any preview origin separately if preview invitations are needed. Invite email template links should continue to use Supabase's `{{ .ConfirmationURL }}` value.

After the migration and function are deployed, deploy the web source to Vercel. BenchPro staff can open **Manage portal access** from a client's details in the Admin Dashboard, approve the client's domain, then send the initial superuser invitation.
