create table public.clients (
  id uuid primary key default gen_random_uuid(),
  company_name text not null check (char_length(trim(company_name)) between 2 and 160),
  company_size text check (company_size is null or company_size in ('1-10','11-50','51-200','201-500','501-1000','1001-5000','5001-10000','10001+','prefer_not_to_say')),
  business_type text check (business_type is null or business_type in ('IT Services & Consulting','Software / SaaS','Financial Services & Fintech','Healthcare & Life Sciences','Manufacturing & Industrial','Retail & Consumer','Transportation & Logistics','Telecom & Media','Energy & Utilities','Government & Education','Other')),
  lifecycle_status text not null default 'prospect' check (lifecycle_status in ('prospect','active','past')),
  is_demo boolean not null default false,
  created_at timestamptz not null default now()
);

comment on table public.clients is 'Canonical BenchPro client organizations; staffing requests are linked by client_id.';
comment on column public.clients.is_demo is 'True only for synthetic demo client data.';
alter table public.clients enable row level security;
grant select, insert, update on public.clients to authenticated;
create policy "Approved staff can read clients" on public.clients for select to authenticated using ((select private.is_benchpro_staff()));
create policy "Approved staff can create clients" on public.clients for insert to authenticated with check ((select private.is_benchpro_staff()));
create policy "Approved staff can update clients" on public.clients for update to authenticated using ((select private.is_benchpro_staff())) with check ((select private.is_benchpro_staff()));

alter table public.staffing_requests
  add column client_id uuid references public.clients(id) on delete set null;
create index staffing_requests_client_id_idx on public.staffing_requests(client_id);
grant select (client_id) on public.staffing_requests to authenticated;
grant update (client_id) on public.staffing_requests to authenticated;

with grouped as (
  select
    lower(regexp_replace(trim(company_name), '\s+', ' ', 'g')) as normalized_name,
    min(company_name) as company_name,
    (array_agg(company_size) filter (where company_size is not null))[1] as company_size,
    (array_agg(business_type) filter (where business_type is not null))[1] as business_type,
    bool_or(is_demo) as is_demo
  from public.staffing_requests
  group by lower(regexp_replace(trim(company_name), '\s+', ' ', 'g'))
), inserted as (
  insert into public.clients (company_name, company_size, business_type, lifecycle_status, is_demo)
  select company_name, company_size, business_type, 'prospect', is_demo
  from grouped
  returning id, company_name
)
update public.staffing_requests as request
set client_id = client.id
from inserted as client
where lower(regexp_replace(trim(request.company_name), '\s+', ' ', 'g'))
    = lower(regexp_replace(trim(client.company_name), '\s+', ' ', 'g'));

