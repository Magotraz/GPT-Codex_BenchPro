# Controlled client shortlists

This release connects private recruiting work, candidate permission and authenticated client feedback. Applications and registered profiles are never automatically shared with clients.

## Operating flow

1. Open **Admin → Recruiting desk** (`recruiting.html`). Select an incoming application, or create an introduction for an existing registered candidate and an open, client-linked role.
2. Complete the professional profile, screening evidence and availability checks. Internal notes and original resumes stay with BenchPro. Profile fields are free text: staff must remove contact details, private pay information and other confidential material before requesting permission.
3. Choose **Save & request candidate permission**. The candidate receives an in-app update and reviews the exact profile in **Client introductions**. They can approve or decline; approved introductions can also be withdrawn.
4. Refresh the recruiting desk. An authorised publisher reviews the approved snapshot and chooses **Publish to client**. The initial publisher is `admin@benchpro.in`; being ordinary BenchPro staff does not confer publishing authority.
5. Clients use **Shortlists** or **Roles → View shortlist**. They can request an interview, ask a question, hold with a revisit date or decline. Responses require confirmation. BenchPro replies from the recruiting desk.

The superuser sees all published profiles for their client. A teammate sees only profiles for roles currently assigned to them. Reassignment, revoked membership or removal of the user's approved email domain removes subsequent access. Existing downloaded/printed copies cannot be recalled.

## Data boundaries and lifecycle

- `shortlist_reviews`: staff-only screening and operational notes.
- `shortlist_permissions`: candidate-specific notice, exact snapshot and decision. Requests expire after 30 days; permission must still be current when publishing.
- `client_submissions`: published snapshot, review stage and follow-up date. Original resumes are not client-accessible through this feature. Clients can print the approved profile.
- `shortlist_activity`: immutable internal or client-visible activity. Candidate updates never repeat raw client comments.
- `candidate_shortlist_updates`: private candidate notifications and persisted read state.

All writes use the authenticated `shortlist_action` RPC. Database checks enforce actor, client, current assignment, publisher permission, candidate approval and expected revision. Direct client/staff writes to workflow records are denied. The RPC locks related records to coordinate with withdrawal and assignment changes.

A matching application progresses to reviewing when screening starts, shortlisted when permission is requested, and client review only when publication succeeds. Client decline marks it rejected. Candidate decline or withdrawal also withdraws the matching application. An application withdrawal revokes the introduction. Candidate profile edits do not change an approved snapshot. Staff must start a revision and obtain permission again to change shared content.

## First-release limits

- Registered candidates only; no external prospect records or public share links.
- Notifications are in-app. No automatic emails or scheduled reminder delivery.
- Interview requests begin coordination; they do not create calendar bookings.
- Offers, acceptance, contracts and onboarding are separate future work. Managed application stages cannot be manually bypassed in Public projects.
- Follow-up dates and review ownership are recorded; advanced assignment/reporting and retention automation are not included.
- Synthetic data is confined to isolated browser fixtures and rolled-back SQL transactions. No sample introductions are published to real clients.

## Verification and release

- `tests/shortlists-rls.sql`: transactional integration checks with staff, candidate, superuser, assigned teammate and unrelated client identities. All fixtures are rolled back.
- `tests/shortlists.browser.cjs`: browser flow using an isolated HTTP server and mocked API responses; tests screening retries, candidate permission, client feedback, notification read state, withdrawal, private-field exclusion and mobile fit.
- Existing candidate workspace, updates and model/API tests cover regressions.

Apply the three `20261103*shortlist*` migrations before deploying the matching frontend. These were applied to project `ttmkcmeqiawrzbvymhal`. The final RPC function body was checked against the repository. Rolling back frontend code does not remove the workflow tables or their access controls; preserve these records and assess compatibility before any database rollback.
