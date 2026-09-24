alter table public.talent_profiles
  add column linkedin_url text check (
    linkedin_url is null or char_length(linkedin_url) <= 500
  );

create policy "Approved staff can remove candidate resumes"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'candidate-resumes'
    and (select private.is_benchpro_staff())
  );

