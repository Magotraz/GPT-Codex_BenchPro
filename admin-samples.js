/* Presentation fixtures only. Never send these records to the database. Remove this file
   and the sample-mode entry point when the preview is retired. */
window.BenchProAdminSamples=function(clients,roles){
  const date=days=>new Date(Date.now()+days*86400000).toISOString();
  const names=['Aarav Mehta','Sofia Patel','Daniel Lee','Priya Rao','Nina Shah','Owen Clarke','Maya Singh','Alex Morgan'];
  const candidates=names.map((name,i)=>({id:'sample-person-'+i,full_name:name,primary_role:['Data Engineer','Cloud Architect','Salesforce Developer','Product Designer'][i%4],skills:[['Snowflake','Python'],['AWS','Terraform'],['Salesforce','Apex'],['Figma','Research']][i%4],availability:i===3?'engaged':i===2?'within_2_weeks':'available',country_or_timezone:['India','US Eastern','UK','India'][i%4],resume_file_name:i===5?null:'profile.pdf',profile_summary:i===5?'':'Experienced technology professional',created_at:date(-i*4),updated_at:date(-i)}));
  const listings=roles.slice(0,6).map((r,i)=>({id:'sample-listing-'+i,title:r.role_or_skills,status:i===5?'draft':'published',is_demo:false,created_at:r.created_at}));
  const applications=Array.from({length:18},(_,i)=>({id:'sample-application-'+i,project_id:listings[i%6].id,candidate_id:candidates[i%8].id,status:['submitted','reviewing','shortlisted','client_review','offer','placed','rejected','withdrawn','submitted'][i%9],created_at:date(-i),updated_at:date(-i/2)}));
  const members=clients.flatMap((c,i)=>[{id:'sample-member-'+i,client_id:c.id,email:'client.lead'+i+'@example.com',role:'superuser',status:'active',created_at:date(-20)},{id:'sample-teammate-'+i,client_id:c.id,email:'hiring.team'+i+'@example.com',role:'recruiter',status:i===2?'invited':'active',created_at:date(-4)}]);
  const engagements=[
    {name:'Aarav Mehta',role:'Senior Data Engineer',client:'Aureline Systems',stage:'Active',start:date(-35),end:date(25),next:'Confirm extension',owner:'Sarah',currency:'USD',hours:160,billRate:85,costRate:60,status:'Confirmed',probability:100},
    {name:'Sofia Patel',role:'Cloud Platform Architect',client:'Northwind Freight',stage:'Onboarding',start:date(6),end:date(186),next:'Client access pending',owner:'James',currency:'USD',hours:120,billRate:110,costRate:78,status:'Confirmed',probability:100},
    {name:'Daniel Lee',role:'Salesforce Developer',client:'Cedarline Payments',stage:'Offer',start:date(12),end:date(102),next:'Awaiting acceptance',owner:'Sarah',currency:'USD',hours:120,billRate:90,costRate:64,status:'Potential',probability:60},
    {name:'Priya Rao',role:'Product Designer',client:'Harborview Health',stage:'Active',start:date(-60),end:date(14),next:'Renewal decision due',owner:'Nisha',currency:'INR',hours:160,billRate:2400,costRate:1650,status:'Confirmed',probability:100},
    {name:'Nina Shah',role:'Platform Engineer',client:'LumenGrid Energy',stage:'Onboarding',start:date(9),end:date(189),next:'Contract signature pending',owner:'Nisha',currency:'INR',hours:120,billRate:2800,costRate:2000,status:'Potential',probability:80}
  ];
  return {candidates,listings,applications,members,engagements};
};
