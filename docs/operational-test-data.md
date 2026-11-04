# Operational test dataset

This is persisted fictional data, separate from the browser-only Design preview.

## Where to review

- Sign in as approved BenchPro staff, open `admin.html`, then **Test dataset** (or `admin.html?data=test`).
- **Talent & applications** contains 20 saved profiles and 30 applications.
- **Clients** contains 6 demo clients; **Roles** contains 10 client requests.
- **Contacts & teams** contains 12 sample memberships, two per company.
- **Recruiting desk** (`recruiting.html?data=test`) contains 12 reviews: 10 profiles currently with clients, one draft, and one withdrawn profile retained in staff history.
- **Public projects** (`publishing.html?data=test`) contains the 10 private draft briefs and their applications. Publishing is disabled in this test view.
- Open a client and choose **Manage portal access**, then **Shortlists**, to inspect its client workspace as staff. The existing staff view is read-only for client feedback; sample feedback illustrates interview requests, holds and declines.
- Staff can create another submission, save screening details, send it, edit a rating, withdraw it and confirm its removal from the client view. These operations persist on the test records.

The first five existing demo companies and requests were reused. The old `DEMO | Test Client` placeholder was renamed `DEMO | Crestfield Retail`. Genuine records were not changed. A real client workspace will not show these unrelated demo clients or their candidates.

## Data boundaries

All fictional clients, staffing requests, project listings, candidate accounts and mirrored talent profiles have `is_demo=true`. Requests use `DEMO |` company names and reserved `benchpro-demo+…@example.com` addresses. Applications and submissions inherit classification through their foreign keys. Database triggers prevent mixing real and test relationships or changing an existing record's classification.

The 32 sample Auth identities (20 candidates and 12 client teammates) have no passwords or login identities, are indefinitely banned, and carry `raw_app_meta_data.benchpro_demo_batch = 'operations-2026-11'` and `fixture_only=true`. They satisfy profile ownership relationships only; they are not test credentials or usable registrations. No emails were sent. No fabricated resume file links were added. Candidate login, email delivery and resume upload must be tested with an actual controlled test account.

Public project browsing already excludes demo listings at database level. Live admin totals and recruiting/publishing selectors now exclude sample candidates as well as sample roles. The new Test dataset control is a view selector, not an authorization mechanism: existing staff checks and RLS still apply.

Financial and delivery panels retain their existing separately labelled illustrative data. The seed does not create invoices, contracts or payment records.

## Setup and verification

1. Apply `supabase/migrations/20261104104943_operational_demo_dataset.sql`.
2. Deliberately execute `supabase/seed-operational-demo.sql` using privileged database tooling. This file is not configured as an automatic startup/reset seed. Immediate repeat runs do not duplicate the dataset; existing applications/submissions are preserved.
3. Execute `tests/operational-demo-rls.sql`. Its actions roll back.
4. Unit checks: `node --test tests/admin-model.test.cjs tests/projects-model.test.cjs tests/projects-api.test.cjs`.
5. Browser check: `node tests/operational-demo.browser.cjs <demo-fixtures.json>` with Playwright available. Export only demo rows under table-name keys matching the test catalog. It routes every Supabase request to local fixtures, not production. Screenshots go outside source to `work/demo-qa`.

## Later removal

Do not run cleanup until explicitly requested. First export the affected demo rows and count their dependencies. Restrict targets by `is_demo=true`; staffing requests must also have `work_email like 'benchpro-demo+%@example.com'`. For the 32 fixture identities, additionally require the exact app-metadata batch marker and reserved email prefix.

Remove dependent activity and candidate notifications, submissions and legacy permissions, then reviews, application events/applications and saved-project links, listing sources/listings, role-assignment events and role matches, staffing requests, memberships/domains, and demo clients. Remove sample candidate/talent profiles before their locked Auth fixture identities. Preserve every genuine request/client/candidate, and abort cleanup if an unexpected cross-dataset reference exists. Never use company names alone as a deletion criterion. The classification migration can remain after cleanup.
