# Candidate workspace — Phase 1

`candidate.html` retains signup, Google OAuth, confirmation, recovery, profile and private resume handlers. Authenticated candidates now see Overview, Explore projects, My applications, Saved projects and My profile. `?view=profile` and `?apply_to=<uuid>` preserve the profile/application return path. Shared login and client/staff permissions are unchanged.

## Data and behavior

- Profile: existing `candidate_accounts`, explicitly selected by authenticated user ID. Readiness checks the same five essentials as application submission. It is not a screening score.
- Discovery: published, non-demo, non-expired `project_listings`. Search combines role/summary/location/skills, specialty and work arrangement. Ordering uses exact shared skills, featured status and publication date. Overview excludes projects already applied to.
- Applications: existing `project_applications`, filtered to the candidate profile ID. All/active/past filters, stage explanations, submitted/updated timestamps and confirmation before withdrawal. This is not an event timeline. `placed` is labelled "Placement confirmed", not completed onboarding.
- Bookmarks: new `candidate_saved_projects` is private to `auth.uid()`, including for staff. No UPDATE grant; users can SELECT/INSERT/DELETE only their own rows. INSERT requires an open, non-demo listing. Saving does not apply. Closed/unpublished details gain no new visibility; a retained bookmark can still be removed.
- Failed reads display errors and unavailable totals rather than false zeros. Profile inputs remain while switching sections. Resume upload, secure view and removal retain existing storage behavior.
- Applications still reference current profiles/resumes. Immutable submissions, event history, notifications, interviews and onboarding are later phases.

## Verification and preview

Run `node --test tests/*.test.cjs` for model and shared-login tests. `tests/candidate-saved-projects-rls.sql` uses transaction-only fixtures and ROLLBACK: own-user access, cross-user and anonymous denial, immutable ownership, duplicate saves, invalid listing states and removal after closure.

`node tests/candidate-workspace.browser.cjs` requires Playwright on NODE_PATH and Chrome. It owns a localhost fixture server and verifies desktop/mobile rendering, search, saves across reload, removal, withdrawal cancel/confirm, profile save/create and error states.

For visual review run `node tests/candidate-preview-server.cjs`, then open `http://127.0.0.1:4180/candidate.html`. Fresh browser contexts with `?fixture=new`, `?fixture=empty` or `?fixture=error` cover other states. Sample data stays in the local browser session; production is never contacted. Resume storage is disabled in the preview. No synthetic candidate records, applications or public listings are seeded in production.

## Release

Apply `20261027181619_candidate_saved_projects.sql` before deploying the frontend. This additive table leaves existing client, staff, profile and application policies unchanged. Frontend rollback can revert the release commit; the unused bookmarks table can remain without affecting the previous UI.
