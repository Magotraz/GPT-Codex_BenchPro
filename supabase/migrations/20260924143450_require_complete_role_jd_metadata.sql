alter table public.staffing_requests
  drop constraint staffing_requests_jd_file_metadata_check,
  add constraint staffing_requests_jd_file_metadata_check check (
    (jd_file_path is null and jd_file_name is null and jd_file_size is null and jd_file_type is null)
    or
    (
      jd_file_path is not null
      and jd_file_path ~ '^requests/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[A-Za-z0-9][A-Za-z0-9._-]{0,119}[.](pdf|doc|docx)$'
      and jd_file_name is not null and char_length(jd_file_name) between 1 and 180
      and jd_file_size between 1 and 10485760
      and jd_file_type in ('application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
    )
  );

