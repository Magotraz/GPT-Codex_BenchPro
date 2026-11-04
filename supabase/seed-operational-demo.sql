-- Explicit, opt-in sample dataset. Not part of automatic db reset/deployment.
-- Apply after operational_demo_dataset migration. Re-running preserves workflow edits.
-- Auth rows are locked fixture identities, NOT usable sign-ins: no password/identity,
-- banned indefinitely, reserved example.com addresses. No invites or emails are sent.
begin;
do $seed$
declare
  company jsonb; person jsonb; job jsonb; i integer; j integer; k integer;
  staff uuid; client uuid; member uuid; usr uuid; cand uuid; role_id uuid; listing uuid;
  application uuid; review uuid; submission uuid; existing uuid; address text; v_company_name text;
  stage text; decision text; packet jsonb; score numeric; created timestamptz;
  client_ids uuid[]='{}'; role_ids uuid[]='{}'; listing_ids uuid[]='{}'; candidate_ids uuid[]='{}';
  companies jsonb='[
    ["Northstar Health Systems","Healthcare & Life Sciences","1001-5000","active","Maya Kapoor"],
    ["Meridian Cloud Services","IT Services & Consulting","201-500","active","Alex Morgan"],
    ["ArborPay","Financial Services & Fintech","51-200","active","Leah Bennett"],
    ["BluePeak Logistics","Transportation & Logistics","1001-5000","active","Samir Das"],
    ["LumenArc Energy","Energy & Utilities","501-1000","prospect","Eva Collins"],
    ["Crestfield Retail","Retail & Consumer","501-1000","prospect","Jonah Reed"]
  ]';
  jobs jsonb='[
    [1,"Senior Salesforce Solution Architect","Enterprise platforms","Salesforce, Apex, Health Cloud","6 months","Remote","India / US overlap","shortlist_sent","Modernize patient engagement with Health Cloud and integrate the platform with appointment and service systems."],
    [2,"Senior Data Engineer","Data & AI","Snowflake, Python, dbt, SQL","6 months","Remote","India / UK overlap","shortlist_sent","Build governed ingestion pipelines and analytics models for a multi-tenant cloud reporting platform."],
    [3,"Salesforce CPQ Consultant","Enterprise platforms","Salesforce CPQ, Apex, Revenue Cloud","4 months","Hybrid","Bengaluru, India","shortlist_sent","Redesign subscription pricing and quote-to-cash workflows, including approvals, renewals and billing integration."],
    [4,"AWS Cloud Infrastructure Engineer","Cloud & platform","AWS, Terraform, Kubernetes, CI/CD","9 months","Remote","India / Gulf overlap","qualified","Build secure cloud foundations, automate infrastructure delivery and improve resilience for logistics operations."],
    [5,"ERP Integration Architect","Enterprise platforms","Oracle Cloud, OIC, REST, SQL","6 months","Hybrid","Dubai, UAE","qualified","Connect Oracle ERP with procurement and finance systems and lead integration architecture through rollout."],
    [3,"Senior Backend Engineer","Engineering","Java, Spring Boot, PostgreSQL, APIs","6 months","Remote","India / Europe overlap","shortlist_sent","Deliver reliable transaction services with strong API contracts, observability and automated integration tests."],
    [4,"React Frontend Engineer","Engineering","React, TypeScript, Next.js, Accessibility","3 months","Remote","India","qualified","Build an accessible shipment operations console with reusable components and responsive data-rich screens."],
    [2,"Machine Learning Engineer","Data & AI","Python, PyTorch, MLflow, Azure","6 months","Remote","UK / Europe overlap","shortlist_sent","Productionize forecasting models with reproducible training, model monitoring and measurable evaluation criteria."],
    [1,"QA Automation Engineer","Engineering","Playwright, Selenium, Java, API testing","4 months","Hybrid","Pune, India","qualified","Establish automated regression coverage for patient-service workflows and improve release confidence."],
    [6,"ServiceNow Implementation Consultant","Enterprise platforms","ServiceNow, ITSM, JavaScript, Flow Designer","5 months","Remote","India / US overlap","qualified","Implement ITSM service workflows, integrate operational systems and support business adoption through launch."]
  ]';
  people jsonb='[
    ["Aditi Rao","Salesforce Solution Architect",11,"Salesforce, Apex, Health Cloud, Integration","Bengaluru, India","within_2_weeks","Led Health Cloud delivery and integrated patient-support workflows across three service teams."],
    ["Rohan Mehta","Senior Salesforce Developer",7,"Salesforce, Apex, LWC, SOQL","Pune, India","available","Built accessible Lightning components and automated case routing for a national service organization."],
    ["Neha Iyer","Senior Data Engineer",9,"Snowflake, Python, dbt, SQL","Hyderabad, India","available","Designed incremental pipelines and governed dbt models for finance and operations analytics."],
    ["Kabir Shah","Analytics Engineer",6,"dbt, BigQuery, SQL, Looker","Mumbai, India","within_4_weeks","Delivered tested semantic models, standardized business metrics and optimized warehouse costs."],
    ["Priya Nair","Salesforce CPQ Consultant",8,"Salesforce CPQ, Apex, Revenue Cloud, Billing","Kochi, India","within_2_weeks","Configured complex subscription bundles, approval chains and renewal flows for enterprise sales teams."],
    ["Omar Farooq","Salesforce Revenue Consultant",5,"Salesforce CPQ, Sales Cloud, Integration","Dubai, UAE","available","Implemented quote-to-cash automation and migrated product and pricing data across sales systems."],
    ["Arjun Sethi","AWS Cloud Architect",12,"AWS, Terraform, Kubernetes, Networking","Delhi, India","within_2_weeks","Designed resilient landing zones and deployment automation for distributed logistics applications."],
    ["Meera Kapoor","DevOps Engineer",6,"AWS, Docker, Kubernetes, GitHub Actions","Bengaluru, India","available","Built infrastructure pipelines, improved monitoring coverage and automated incident recovery tasks."],
    ["Vikram Desai","Oracle ERP Integration Architect",14,"Oracle Cloud, OIC, REST, SQL","Ahmedabad, India","within_4_weeks","Led finance and procurement integration programs with clear migration and reconciliation controls."],
    ["Sana Qureshi","Integration Consultant",8,"MuleSoft, Oracle Cloud, REST, Java","Dubai, UAE","engaged","Delivered reusable API integrations connecting ERP, CRM and procurement platforms."],
    ["Elena Novak","Senior Java Engineer",10,"Java, Spring Boot, PostgreSQL, Kafka","Warsaw, Poland","within_2_weeks","Delivered event-driven transaction services with reliable API contracts and production observability."],
    ["Daniel Brooks","Senior .NET Engineer",9,"C#, .NET, Azure, SQL Server","Manchester, UK","engaged","Modernized service APIs and introduced automated deployment and operational dashboards."],
    ["Kiran Patel","React Frontend Engineer",6,"React, TypeScript, Next.js, Accessibility","Pune, India","available","Built accessible enterprise interfaces and reusable components for complex operational workflows."],
    ["Ananya Sen","Full Stack Engineer",5,"React, Node.js, TypeScript, PostgreSQL","Kolkata, India","within_2_weeks","Delivered customer-facing web applications from data models through responsive user interfaces."],
    ["Liam Carter","Machine Learning Engineer",8,"Python, PyTorch, MLflow, Azure","London, UK","within_2_weeks","Productionized demand forecasting with reproducible training, monitoring and offline evaluation."],
    ["Fatima Khan","Data Scientist",7,"Python, scikit-learn, SQL, Statistics","Hyderabad, India","paused","Built forecasting experiments and interpretable models with clear business evaluation criteria."],
    ["Ishaan Malhotra","QA Automation Engineer",6,"Playwright, Selenium, Java, API testing","Chandigarh, India","available","Established end-to-end test suites and stable release gates for service-oriented applications."],
    ["Sofia Martins","Senior SDET",9,"Playwright, TypeScript, Cypress, Performance testing","Lisbon, Portugal","within_4_weeks","Designed automated quality checks and load-testing programs for high-volume digital platforms."],
    ["Nikhil Menon","ServiceNow Consultant",10,"ServiceNow, ITSM, JavaScript, Flow Designer","Chennai, India","within_2_weeks","Led ITSM implementations, workflow integrations and service-management adoption programs."],
    ["Grace Chen","ServiceNow Developer",5,"ServiceNow, JavaScript, REST, Service Portal","Singapore","available","Built service catalog workflows, operational integrations and self-service portal experiences."]
  ]';
begin
  select u.id into staff from auth.users u join private.benchpro_staff_access s on lower(u.email)=lower(s.email)
    where u.email='admin@benchpro.in';
  if staff is null then raise exception 'Approved admin account required for seed ownership'; end if;
  i=0;
  for company in select value from jsonb_array_elements(companies) loop
    i=i+1; v_company_name='DEMO | '||(company->>0);
    select c.id into client from public.clients c where c.is_demo and c.company_name=v_company_name order by c.created_at limit 1;
    -- Reuse the existing explicitly tagged placeholder instead of making a seventh client.
    if client is null and i=6 then
      select id into client from public.clients where is_demo and clients.company_name='DEMO | Test Client' limit 1;
      if client is not null then update public.clients set company_name='DEMO | Crestfield Retail' where id=client and is_demo; end if;
    end if;
    if client is null then
      insert into public.clients(company_name,company_size,business_type,lifecycle_status,is_demo,website,created_at)
      values(v_company_name,company->>2,company->>1,company->>3,true,'https://example.com',now()-(i*6)*interval '1 day') returning id into client;
    else
      update public.clients set lifecycle_status=company->>3,company_size=company->>2,business_type=company->>1 where id=client and is_demo;
    end if;
    client_ids=array_append(client_ids,client);
    insert into public.client_email_domains(client_id,domain,created_by) values(client,'example.com',staff) on conflict do nothing;
    for k in 1..2 loop
      address='benchpro-demo+showcase-client-'||i||'-'||k||'@example.com';
      select id into usr from auth.users where email=address;
      if usr is null then
        insert into auth.users(id,email,banned_until,raw_app_meta_data,created_at,updated_at)
        values(gen_random_uuid(),address,'infinity','{"benchpro_demo_batch":"operations-2026-11","fixture_only":true}',now(),now()) returning id into usr;
      elsif not exists(select 1 from auth.users where id=usr and raw_app_meta_data->>'benchpro_demo_batch'='operations-2026-11' and banned_until>now()) then
        raise exception 'Refusing to reuse a non-fixture identity';
      end if;
      insert into public.client_memberships(client_id,user_id,email,role,status,invited_by,activated_at)
      select client,usr,address,case when k=1 then 'superuser' else 'recruiter' end,'active',staff,now()-interval '7 days'
      where not exists(select 1 from public.client_memberships where client_id=client and email=address);
    end loop;
  end loop;
  i=0;
  for job in select value from jsonb_array_elements(jobs) loop
    i=i+1;j=(job->>0)::int;client=client_ids[j];company=companies->(j-1);
    select id into role_id from public.staffing_requests where client_id=client and is_demo and role_or_skills=job->>1 order by created_at limit 1;
    if role_id is null then
      select id into member from public.client_memberships where client_id=client and email='benchpro-demo+showcase-client-'||j||'-2@example.com' limit 1;
      insert into public.staffing_requests(client_id,company_name,contact_name,designation,work_email,company_size,business_type,
        role_or_skills,project_duration,target_start_date,work_location_timezone,project_details,status,is_demo,assigned_to,client_assignee_membership_id,created_at)
      values(client,'DEMO | '||(company->>0),company->>4,'Technology Delivery Lead','benchpro-demo+showcase-role-'||i||'@example.com',company->>2,company->>1,
        job->>1,job->>4,current_date+14,job->>6,job->>8,job->>7,true,case when i%3=0 then null else 'admin@benchpro.in' end,
        case when i%3=0 then null else member end,now()-(i*2)*interval '1 day') returning id into role_id;
    end if;
    role_ids=array_append(role_ids,role_id);
    select project_id into listing from public.project_listing_sources where staffing_request_id=role_id;
    if listing is null then
      insert into public.project_listings(title,category,summary,description,responsibilities,requirements,skills,work_mode,location,duration,experience,
        start_window,client_display_name,status,is_demo,created_at)
      values(job->>1,job->>2,job->>8,(job->>8)||' Work with a cross-functional delivery team, agree milestones with the project lead and provide maintainable documentation. This is a private test opportunity.',
        array['Deliver agreed project milestones','Collaborate with product and technical stakeholders','Document solutions and support handover'],
        array['Hands-on delivery experience in '||(job->>3),'Clear stakeholder communication and project delivery experience'],
        string_to_array(job->>3,', '),job->>5,job->>6,job->>4,'5+ years','Within 2–4 weeks','DEMO | '||(company->>0),'draft',true,now()-(i*2)*interval '1 day') returning id into listing;
      insert into public.project_listing_sources(project_id,staffing_request_id,created_by) values(listing,role_id,staff);
    elsif not exists(select 1 from public.project_listings where id=listing and is_demo) then raise exception 'Existing listing is not a demo';
    end if;
    listing_ids=array_append(listing_ids,listing);
  end loop;
  i=0;
  for person in select value from jsonb_array_elements(people) loop
    i=i+1;j=(i+1)/2;address='benchpro-demo+showcase-candidate-'||lpad(i::text,2,'0')||'@example.com';
    select id into usr from auth.users where email=address;
    if usr is null then
      insert into auth.users(id,email,banned_until,raw_app_meta_data,created_at,updated_at)
      values(gen_random_uuid(),address,'infinity','{"benchpro_demo_batch":"operations-2026-11","fixture_only":true}',now(),now()) returning id into usr;
    elsif not exists(select 1 from auth.users where id=usr and raw_app_meta_data->>'benchpro_demo_batch'='operations-2026-11' and banned_until>now()) then
      raise exception 'Refusing to reuse a non-fixture identity';
    end if;
    select id into cand from public.candidate_accounts where user_id=usr;
    if cand is null then
      insert into public.candidate_accounts(user_id,full_name,primary_role,years_experience,skills,country_or_timezone,availability,available_from,
        profile_summary,preferred_work_mode,preferred_location,weekly_hours,is_demo,created_at)
      values(usr,person->>0,person->>1,(person->>2)::smallint,string_to_array(person->>3,', '),person->>4,person->>5,
        case when person->>5='within_4_weeks' then current_date+28 else current_date+14 end,person->>6,
        case when i%4=0 then 'Hybrid' else 'Remote' end,person->>4,case when i%5=0 then 20 else 40 end,true,now()-(i+5)*interval '1 day') returning id into cand;
    elsif not exists(select 1 from public.candidate_accounts where id=cand and is_demo) then raise exception 'Existing candidate is not a demo';
    end if;
    candidate_ids=array_append(candidate_ids,cand);job=jobs->(j-1);client=client_ids[(job->>0)::int];
    stage=case when i%2=1 then case when j=4 then 'rejected' else 'client_review' end
      when i=2 or i=4 or i=14 then 'reviewing' when i=6 or i=16 then 'rejected' when i=10 then 'offer'
      when i=12 then 'placed' when i=18 then 'withdrawn' else 'submitted' end;
    select id into application from public.project_applications where project_id=listing_ids[j] and candidate_id=cand;
    if application is null then
      insert into public.project_applications(project_id,candidate_id,availability,consent,status,created_at)
      values(listing_ids[j],cand,person->>5,true,stage,now()-(i%7+2)*interval '1 day') returning id into application;
    end if;
    -- Ten client submissions, one draft, one withdrawn example. All other profiles remain available to try.
    if i%2=1 or i in (2,4) then
      select id into review from public.shortlist_reviews where staffing_request_id=role_ids[j] and candidate_id=cand;
      if review is null then
        score=case when i%3=0 then 4.8 when i%3=1 then 4.2 else 4.9 end;
        packet=jsonb_build_object('full_name',person->>0,'title',person->>1,'experience',(person->>2)||' years','skills',person->>3,
          'location',person->>4,'availability',replace(person->>5,'_',' '),'summary',person->>6,
          'project_evidence',person->>6,'requirements_evidence','Relevant delivery experience in '||(person->>3)||'. Example screening notes for testing.',
          'client_rate',case when i%3=0 then 'USD 75/hour · sample estimate' else 'USD 60/hour · sample estimate' end);
        created=now()-(i%5+1)*interval '1 day';
        insert into public.shortlist_reviews(staffing_request_id,candidate_id,application_id,owner_user_id,state,profile,screening_notes,screening_confirmed,
          availability_confirmed_at,candidate_discussed_at,candidate_discussed_by,next_action_at,fit_rating,created_at)
        values(role_ids[j],cand,application,staff,case when i=2 then 'draft' when i=4 then 'closed' else 'published' end,packet,
          'SAMPLE: fictional screening discussion for workflow testing.',i<>2,case when i<>2 then created end,
          case when i<>2 then created end,case when i<>2 then staff end,current_date+(i%5)-2,score,created) returning id into review;
        if i<>2 then
          decision=case when j in (2,6) then 'interview_requested' when j in (3,8) then 'on_hold' when j=4 then 'declined' else 'awaiting_review' end;
          insert into public.client_submissions(review_id,staffing_request_id,client_id,role_title,profile,status,needs_client_response,follow_up_on,
            published_by,published_at,fit_rating,revoked_at)
          values(review,role_ids[j],client,job->>1,packet,decision,decision='awaiting_review',case when decision='on_hold' then current_date+3 end,
            staff,created,score,case when i=4 then now()-interval '1 day' end) returning id into submission;
          insert into public.shortlist_activity(review_id,submission_id,audience,kind,message,actor_user_id,actor_label,occurred_at)
          values(review,submission,'client','published','Sample profile presented for workflow testing.',staff,'BenchPro sample setup',created);
          if decision<>'awaiting_review' and i<>4 then
            select user_id into member from public.client_memberships where client_id=client and role='superuser' and email like 'benchpro-demo+showcase-%' limit 1;
            insert into public.shortlist_activity(review_id,submission_id,audience,kind,message,actor_user_id,actor_label)
            values(review,submission,'client',decision,case decision when 'interview_requested' then 'Sample feedback: please arrange a technical discussion next week.'
              when 'on_hold' then 'Sample feedback: waiting for the delivery lead to confirm the project start.' else 'Sample feedback: this project requires a different depth of domain experience.' end,member,'Sample client feedback');
          end if;
          if i=4 then
            insert into public.shortlist_activity(review_id,submission_id,audience,kind,message,actor_user_id,actor_label)
            values(review,submission,'staff','staff_withdrawal','Sample withdrawal: availability changed. The candidate application stays in review.',staff,'BenchPro sample setup');
          end if;
        end if;
      end if;
    end if;
  end loop;
  -- A further ten applications demonstrate that a candidate can apply to more than one role.
  for i in 1..10 loop
    j=case when i<=2 then 3 when i<=4 then 8 when i<=6 then 1 when i<=8 then 7 else 10 end;
    insert into public.project_applications(project_id,candidate_id,availability,consent,status,created_at)
    select listing_ids[j],candidate_ids[i],'within_2_weeks',true,case when i%3=0 then 'reviewing' else 'submitted' end,now()-(i%4)*interval '1 day'
    where not exists(select 1 from public.project_applications where project_id=listing_ids[j] and candidate_id=candidate_ids[i]);
  end loop;
end $seed$;
commit;

