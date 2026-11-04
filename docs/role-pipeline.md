# Role Kanban pipeline — release 1

## Where to use it

- Staff: Admin → Recruiting desk (`recruiting.html`). Select a client and role, then Screening, Client pipeline or Archived. Existing `?candidate=`, `?application=` and `?review=` links remain supported.
- Client: Workspace → Talent pipeline. Existing `?tab=shortlists` URLs remain compatible. Superusers see company roles; teammates only assigned roles. Staff management previews are read-only for client actions.
- `recruiting.html?data=test` uses the existing persisted sample dataset. Test/real identities cannot be mixed.

## One handoff, shared progress

Unprocessed applications appear in New. Starting screening creates or reuses a role-specific review. Registered candidates and private sourced talent can also be selected from Add candidate. Upload a sourced profile creates a talent record without an Auth account or registration email; duplicate email checks direct the recruiter to the existing talent record.

The existing recruiter submission checks still require a role conversation, screening confirmation, role-specific evidence and a 1–5 fit rating with one decimal. Send to client publishes the approved snapshot. No candidate or separate admin approval is requested.

Client review → Interview → Offer → Onboarding → Started is stored on the client submission shared by both views. Dragging and Move… use the same confirmation and revision-checked database operation. Interview requested is not scheduled. Preparing offer is not an issued offer. Only staff records a confirmed schedule, sent/accepted offer, onboarding and start. Onboarding requires a recorded accepted offer; Started requires onboarding and explicit confirmation. Started cannot be casually dragged back.

Client feedback remains available in the profile panel: request interview, ask a question, hold with a revisit date, or decline. Hold is a flag; declined submissions appear under Archived. Withdrawal revokes client profile, discussion and document access on new requests; history remains private. Previously downloaded files and already-issued signed URLs cannot be recalled (document links expire in 60 seconds).

## Data and documents

- Registered considerations reference candidate_accounts; sourced considerations reference talent_profiles. Exactly one identity is required. Mirrored registered talent is normalised to its candidate account to prevent duplicate role cards.
- Existing drafts stay private; known interview requests map to Interview, with no invented scheduling milestones. Existing histories are retained.
- New application updates use the existing candidate event system. Only actual sent offers map to `offer`, and only confirmed starts map to `placed`.
- Original resumes stay in the private candidate-resumes bucket. A separate client-profile-documents bucket holds immutable, explicitly approved versions. Staff must save draft edits before adding/removing attachments. Published snapshots keep the document version they were sent with.
- All stage mutations authenticate and check the current role assignment, membership, lifecycle and revision in the database. Direct table writes remain denied. Activity records capture stage, actor and decision; private screening information is never returned to clients.
- Sourced people are not automatically merged with a future registration. Identity linking requires separate verified reconciliation; name-only matching is not performed.

## Limits

This release tracks interview, offer and onboarding progress manually. It does not send emails, book calendars, generate contracts, parse resumes or calculate revenue. No new synthetic milestones are inserted into real records. Role-level stage tracking is not an invoice or revenue record.

## Verification and deployment

Run `tests/pipeline-database.cjs` with PGlite available via NODE_PATH. It reconstructs the repository migrations in an isolated database, then runs existing shortlist tests and pipeline-rls.sql, including real row-level policies. Supabase Auth/Storage primitives are represented by a local schema; hosted token issuance and file transport require deployment checks.

Run `tests/shortlists.browser.cjs` with Playwright available via NODE_PATH. It exercises both desktop/mobile UIs with isolated HTTP fixtures, including source upload, screening, sharing, client feedback, stage changes, ratings, archival and withdrawal. `tests/pipeline-model.test.cjs` checks presentation and permission choices.

Apply `20261104153109_role_kanban_pipeline.sql` before deploying matching frontend files. The migration is additive and preserves the existing shortlist RPC interface. Verify production migration, function grants, storage policies and Vercel commit after deployment.

For an emergency frontend rollback, retain the database migration and history. Old screens do not fully represent advanced Kanban milestones; pause pipeline mutations before using them operationally. Never drop new source references or stage history as a rollback shortcut.
