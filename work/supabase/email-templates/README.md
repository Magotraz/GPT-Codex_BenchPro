# BenchPro Auth email template

## Confirm signup

- **From name:** BenchPro
- **From address:** `no-reply@benchpro.in`
- **Subject:** `Activate your BenchPro account`
- **Supabase template:** `confirm_signup.html`
- **Expiry wording:** none. Supabase confirmation links still have a configurable validity period; candidates can request a fresh activation email from the candidate sign-in page.

Paste the subject and HTML body into **Supabase Dashboard → Authentication → Email Templates → Confirm signup**. The HTML uses Supabase's `{{ .ConfirmationURL }}` and `{{ .SiteURL }}` template variables.

The sender name/address are configured separately under **Authentication → SMTP Settings**. Verify `benchpro.in` with the mail provider, configure its sending DNS records, then enter the SMTP host, port, username, and password in Supabase. Do not commit SMTP credentials to this repository.
