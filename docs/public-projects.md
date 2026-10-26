# Public project listings and applications

This release connects public project discovery to existing candidate profiles. It does not make private client requests or uploaded JDs public.

## Staff workflow

1. Sign in with an approved BenchPro staff account. Open **Public projects** from the admin client-directory toolbar (or `publishing.html`).
2. Create a project and optionally link its private source request. Client users cannot publish listings. Client-posted roles continue through the existing private intake process.
3. Write the public copy. Use **Confidential client** unless the client has approved use of their name. Do not copy personal contact details or confidential JDs into public fields.
4. Save as a draft, or confirm that the copy and advertising permission have been reviewed and publish. Published, unexpired, non-demo listings appear on the public board. Featured roles are prioritized on the homepage.
5. Open a listing in the publishing workspace to review applications, open private resumes and update application stages. These stages are visible to the applicant. This release does not send application or stage-change emails.
6. Close a role to stop new applications. Existing applicants retain its details and application history. Listings and applications cannot be deleted through this interface.

## Candidate workflow

Visitors browse `projects.html` and review `project.html?id=<uuid>`. Login returns them to their chosen project. Existing client users can also create a private candidate profile under the same identity.

An application requires a saved name, specialty, country, skills and resume metadata on the existing candidate account, plus explicit review consent. Missing information sends the person to their existing profile editor. Applications use the current private profile rather than an immutable resume snapshot; this is stated in the application form and staff workspace. Availability at application time is recorded separately.

The pending application destination is a validated UUID stored for 24 hours in session storage, with a local-storage backup so same-browser email activation in another tab can return to the role. It contains no credentials or profile data. OAuth/email callback URLs remain unchanged, avoiding new wildcard authentication redirects. Successful application, an existing application, or cancellation clears the pending destination. Application review never submits automatically after authentication.

Candidates see only their own applications and can withdraw active ones. A database uniqueness constraint prevents duplicate submissions. This first release retains a withdrawn application rather than allowing self-service reapplication; BenchPro can discuss renewed interest with the candidate.

## Security and validation

Public copy is in `project_listings`. Private source associations are in `project_listing_sources`; candidate submissions are in `project_applications`. All three tables have RLS and explicit grants. Public visitors have no access to applications or source links. Client membership confers no publishing or applicant access. Staff access uses the existing server-managed staff allowlist, never editable user metadata.

Closed-project history uses a narrowly scoped private security-definer boolean helper to avoid a cycle between listing SELECT and application INSERT policies. It returns only whether the caller owns an application for a project.

Run `node --test tests/*.test.cjs` for model, account routing and API session tests. Run `tests/public-projects-rls.sql` through a privileged SQL connection for the transactional integration test. It tests public visibility; candidate isolation, ownership and review stages; duplicates; draft/closed/expired/demo rejection; staff access; withdrawal; and retained project history. All test fixtures are uncommitted and rolled back, including test auth users. No synthetic staffing requests are inserted.

## Rollback

The pre-release source baseline is `a0c4fadbc9028f08988590a07571921a54e80064`. Revert the public-projects release commit and push to restore the previous frontend. Keep the additive database tables and policies if real applications have been received; do not drop or delete applicant data as a visual rollback.

## Follow-up work

This is the first functional slice. Next improvements include client-approved structured public job fields for search-engine JobPosting markup, application notifications, saved searches, and founder-level reporting sourced from these application records. Current browse pages paginate 24 listings at a time; staff publishing lists paginate 50 and applicant lists paginate 30. The source-request picker shows the newest 1,000 genuine requests.
