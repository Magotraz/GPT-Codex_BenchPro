alter table public.staffing_requests
  add column phone_number text check (
    phone_number is null or char_length(trim(phone_number)) between 7 and 32
  ),
  add column designation text check (
    designation is null or char_length(trim(designation)) <= 120
  ),
  add column company_size text check (
    company_size is null or company_size in (
      '1-10', '11-50', '51-200', '201-500', '501-1000',
      '1001-5000', '5001-10000', '10001+', 'prefer_not_to_say'
    )
  ),
  add column business_type text check (
    business_type is null or business_type in (
      'IT Services & Consulting',
      'Software / SaaS',
      'Financial Services & Fintech',
      'Healthcare & Life Sciences',
      'Manufacturing & Industrial',
      'Retail & Consumer',
      'Transportation & Logistics',
      'Telecom & Media',
      'Energy & Utilities',
      'Government & Education',
      'Other'
    )
  );

comment on column public.staffing_requests.phone_number is
  'Optional international phone number provided by the client contact.';
comment on column public.staffing_requests.designation is
  'Optional job title/designation of the client contact.';
comment on column public.staffing_requests.company_size is
  'Optional employee-count range selected by the client.';
comment on column public.staffing_requests.business_type is
  'Optional industry/business type selected by the client.';

grant insert (phone_number, designation, company_size, business_type)
  on public.staffing_requests to anon;

update public.staffing_requests as request
set phone_number = demo.phone_number,
    designation = demo.designation,
    company_size = demo.company_size,
    business_type = demo.business_type
from (
  values
    ('benchpro-demo+001@example.com', '+1 202-555-0101', 'VP, Enterprise Applications', '5001-10000', 'Healthcare & Life Sciences'),
    ('benchpro-demo+002@example.com', '+1 202-555-0102', 'Chief Technology Officer', '51-200', 'IT Services & Consulting'),
    ('benchpro-demo+003@example.com', '+1 202-555-0103', 'Director of CRM', '201-500', 'Financial Services & Fintech'),
    ('benchpro-demo+004@example.com', '+1 202-555-0104', 'Head of Cloud Engineering', '10001+', 'Transportation & Logistics'),
    ('benchpro-demo+005@example.com', '+1 202-555-0105', 'Head of Enterprise Architecture', '1001-5000', 'Energy & Utilities')
) as demo(work_email, phone_number, designation, company_size, business_type)
where request.is_demo is true
  and request.work_email = demo.work_email;

