alter table public.talent_profiles
  drop constraint talent_profiles_work_email_check,
  add constraint talent_profiles_work_email_check check (
    work_email is null or (
      char_length(work_email) between 5 and 320
      and work_email ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+[.][A-Z]{2,}$'
    )
  );

