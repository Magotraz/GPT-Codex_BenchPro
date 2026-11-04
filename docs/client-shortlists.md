# Recruiter-led candidate submissions

## Operating flow

1. Open Admin → Recruiting desk → New submission, or Talent & applications → Prepare for client. Choose a registered candidate and an open client-linked role.
2. Prepare the professional profile and a role-specific BenchPro fit rating from 1 to 5 (one decimal place supported). Internal notes, raw resumes and private account fields stay within BenchPro.
3. Confirm screening and that the role has been discussed with the candidate, including interest and availability. This confirmation is recorded with the recruiter identity and time.
4. Review the client-facing profile and choose Send to client. Saving and sending are atomic. Any approved BenchPro staff account can submit; no candidate or separate admin approval is required.
5. Clients review profiles under Shortlists, with the rating at the top right. They can request interview coordination, ask a question, hold or decline. BenchPro replies and can update ratings, with changes recorded in activity.
6. Withdraw profile asks for an internal reason. It revokes client access, removes the profile from client lists and counts, and preserves staff history. A matching application in client review returns to reviewing; it is never marked withdrawn by this staff action.

## Access and history

- Superusers see all active submissions for their client; teammates see only their currently assigned roles. Backend permissions apply to reads and actions.
- Visible client shortlist views refresh every 15 seconds and on returning to the window. Opening a profile always rechecks access. Revocation blocks new requests immediately. An open profile is cleared on revalidation; previously printed/saved copies cannot be recalled.
- The candidate approval screen has been retired. Candidates receive informational in-app updates. A candidate withdrawing their actual application still revokes related client submissions.
- Existing permission decisions remain in history. Obsolete approval prompts are archived. Legacy unsent reviews need a deliberate revision and fresh recruiter confirmation; nothing is automatically published.
- A revised or previously withdrawn profile requires an explicit new submission. Rating-only edits do not require withdrawing the profile; the actor, timestamp and old/new score are recorded.
- Original resumes are not published. Free-text professional fields must be reviewed by staff for contact details and confidential information before sending.

## Release limits

Registered candidates only. No automatic email delivery, calendar bookings, offer acceptance or onboarding workflow is included. A rating represents recruiter judgement about a particular role, not an automated percentage or permanent score for the candidate.

## Verification

- tests/shortlists-rls.sql: transaction-only fixture tests for staff submission, missing conversation, atomic failure, rating validation, client isolation, assigned-role access, private fields, stale updates, rating audit, staff withdrawal and candidate application withdrawal. Every fixture rolls back.
- tests/shortlists.browser.cjs: isolated browser fixtures cover the full UI flow, profile preview, decimal rating, client feedback, rating edits, withdrawal, desktop/mobile layout and the absence of candidate approval controls.
- Candidate workspace and notification browser regressions cover existing navigation and updates.

Apply the recruiter_led_submissions migration before the matching frontend. Do not roll back only the frontend to the older candidate-approval flow: those RPC actions are retired. Historical records and access rules must be retained in any rollback.
