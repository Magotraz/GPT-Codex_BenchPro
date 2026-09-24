alter table public.staffing_requests
  add column if not exists is_demo boolean not null default false;

comment on column public.staffing_requests.is_demo is
  'True for synthetic demo data; false for real client submissions.';

update public.staffing_requests
set is_demo = true
where work_email like 'benchpro-demo+%@example.com'
  and company_name like 'DEMO | %';

