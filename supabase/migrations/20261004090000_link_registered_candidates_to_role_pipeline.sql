-- Let the role pipeline reference either a self-registered candidate account or a staff-entered talent profile.
alter table public.role_talent_matches
  add column candidate_account_id uuid;

alter table public.role_talent_matches
  alter column talent_profile_id drop not null;

alter table public.role_talent_matches
  add constraint role_talent_matches_candidate_account_id_fkey
  foreign key (candidate_account_id)
  references public.candidate_accounts(id)
  on delete restrict;

alter table public.role_talent_matches
  add constraint role_talent_matches_exactly_one_candidate_check
  check (num_nonnulls(talent_profile_id, candidate_account_id) = 1);

create unique index role_talent_matches_request_candidate_account_key
  on public.role_talent_matches (staffing_request_id, candidate_account_id)
  where candidate_account_id is not null;

create index role_talent_matches_candidate_account_id_idx
  on public.role_talent_matches (candidate_account_id)
  where candidate_account_id is not null;

-- Candidate accounts remain private: this adds read access for the existing approved-staff
-- allowlist only. Candidate-owned select/update policies continue to apply as before.
create policy "Approved staff can read candidate accounts"
  on public.candidate_accounts for select to authenticated
  using ((select private.is_benchpro_staff()));

comment on column public.role_talent_matches.candidate_account_id is
  'Self-registered candidate linked to this role; access remains restricted to approved BenchPro staff until deliberately shared.';
