alter table public.staffing_requests
  add column jd_file_path text,
  add column jd_file_name text,
  add column jd_file_size bigint,
  add column jd_file_type text,
  add constraint staffing_requests_jd_file_metadata_check check (
    (jd_file_path is null and jd_file_name is null and jd_file_size is null and jd_file_type is null)
    or
    (
      jd_file_path ~ '^requests/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[A-Za-z0-9][A-Za-z0-9._-]{0,119}[.](pdf|doc|docx)$'
      and jd_file_name is not null and char_length(jd_file_name) between 1 and 180
      and jd_file_size between 1 and 10485760
      and jd_file_type in ('application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
    )
  );

comment on column public.staffing_requests.jd_file_path is 'Private Supabase Storage object path for a client-provided role description.';
comment on column public.staffing_requests.jd_file_name is 'Original display name of the client-provided role description.';
comment on column public.staffing_requests.jd_file_size is 'Role description file size in bytes; capped at 10 MiB.';
comment on column public.staffing_requests.jd_file_type is 'Validated MIME type of the client-provided role description.';

grant insert (id, jd_file_path, jd_file_name, jd_file_size, jd_file_type)
  on public.staffing_requests to anon;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'client-role-jds',
  'client-role-jds',
  false,
  10485760,
  array['application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document']
)
on conflict (id) do update
set name = excluded.name,
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Public can upload role JDs"
  on storage.objects
  for insert
  to anon
  with check (
    bucket_id = 'client-role-jds'
    and array_length(storage.foldername(name), 1) = 2
    and (storage.foldername(name))[1] = 'requests'
    and (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and storage.filename(name) ~* '^[A-Za-z0-9][A-Za-z0-9._-]{0,119}[.](pdf|doc|docx)$'
  );

create policy "Approved staff can read role JDs"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'client-role-jds'
    and (select private.is_benchpro_staff())
  );

