# Company workspace

The admin route remains `admin.html`, using the existing approved-staff session and RLS policies. No new database tables, access grants, production fixtures, or authentication shortcuts are introduced.

## Live capabilities

- Overview of client demand, open requests, applications, and an actionable exception queue.
- Client creation, website editing, inquiry linking, role status/internal ownership, private JD access, and links to existing client portal membership management.
- Contacts derived from role requests, plus client superusers, invited/active/removed members, and client assignment counts.
- Candidate profiles and application stages from their existing tables; publishing/application decisions remain in `publishing.html`.
- Current workload and client-demand reports, creation-period filters, and a CSV export.
- Paginated reads rather than the previous 500-record truncation. Failed reads are labelled unavailable.

## Preview data

Live mode is the default. **Explore sample data** replaces operating records with fictional, in-memory examples. It never inserts them into Supabase. Existing role/website/inquiry preview edits remain local; creating a client and sending invitations are unavailable in preview.

Delivery and financial modules currently use explicitly labelled sample data in both modes. Financial scenarios recalculate in memory and can be reset in Administration. Currencies are never summed together. Confirmed billings, direct cost, gross profit, and probability-weighted potential are distinct. Forecast hours cover an illustrative next-30-day planning window.

The fixtures are in `admin-samples.js` and the older `getPreviewClients`/`getPreviewRequests` functions in `admin.html`. Removing preview support requires removing those factories and their UI entry points; it does not require deleting database records. If database demo requests are cleaned later, use only `where is_demo = true` under the project instructions.

## Definitions and limitations

- A role is a staffing request, not a count of vacancies. No headcount is inferred.
- Applications count candidate/project pairs, while profiles count saved candidate accounts. Unconfirmed auth registrations are not available here.
- Pipeline totals are current-stage snapshots, not historical conversions. Placed applications are not automatically active contractors.
- Live headline data excludes demo-tagged clients, their roles, demo requests, and applications on demo listings.
- Role age starts at request creation. It does not indicate time since contact.
- Contacts currently come from requests; a separate editable contact CRM is not implemented.
- The action queue is derived, not a durable assigned-task system.
- Offers, onboarding checklists, signed engagements, rates, invoices, collections, renewals, and audit reporting still need structured live records and workflows. Add a dedicated finance/CEO permission before storing confidential commercial data; current staff authorization is shared.

## Verification

`node --test tests/*.test.cjs` includes finance isolation, demo exclusion, pipeline definitions, action prioritization, and pagination/error cases. An isolated local preview server outside the repository is used for UI checks; it intercepts API reads with fixtures and rejects writes. It is never deployed.

Database read-policy checks use a rolled-back transaction with the approved staff identity to verify table visibility. This is separate from browser session verification, which requires a signed-in production admin.
