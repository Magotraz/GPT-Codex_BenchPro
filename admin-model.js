(function(root){
  'use strict';
  const DAY=86400000;
  const activeStages=['submitted','reviewing','shortlisted','client_review','offer'];
  const age=(date,now=Date.now())=>Math.max(0,Math.floor((now-new Date(date).getTime())/DAY))||0;
  function operating(data){
    const clients=(data.clients||[]).filter(x=>!x.is_demo), ids=new Set(clients.map(x=>x.id));
    const roles=(data.roles||[]).filter(x=>!x.is_demo&&(!x.client_id||ids.has(x.client_id)));
    const listings=(data.listings||[]).filter(x=>!x.is_demo), listingIds=new Set(listings.map(x=>x.id));
    return {...data,clients,roles,listings,applications:(data.applications||[]).filter(x=>listingIds.has(x.project_id)),members:(data.members||[]).filter(x=>ids.has(x.client_id)),candidates:data.candidates||[]};
  }
  function metrics(data){return {clients:data.clients.length,activeClients:data.clients.filter(x=>x.lifecycle_status==='active').length,openRoles:data.roles.filter(x=>x.status!=='closed').length,unowned:data.roles.filter(x=>x.status!=='closed'&&!x.assigned_to).length,applications:data.applications.filter(x=>activeStages.includes(x.status)).length,offers:data.applications.filter(x=>x.status==='offer').length,placed:data.applications.filter(x=>x.status==='placed').length,rejected:data.applications.filter(x=>x.status==='rejected').length};}
  function actions(data,now=Date.now()){
    const tasks=[];
    data.roles.filter(x=>x.status!=='closed').forEach(r=>{
      if(!r.client_id)tasks.push({kind:'Link client',title:r.role_or_skills,detail:r.company_name,priority:'High',target:'inquiries',id:r.id});
      else if(!r.assigned_to)tasks.push({kind:'Assign owner',title:r.role_or_skills,detail:r.company_name,priority:'High',target:'roles',id:r.id});
      else if(age(r.created_at,now)>14)tasks.push({kind:'Review aging role',title:r.role_or_skills,detail:age(r.created_at,now)+' days since request · '+r.assigned_to,priority:'Medium',target:'roles',id:r.id});
    });
    data.members.filter(m=>m.status==='invited').forEach(m=>tasks.push({kind:'Pending invitation',title:m.email,detail:data.clients.find(c=>c.id===m.client_id)?.company_name||'Client team',priority:'Medium',target:'contacts',id:m.client_id}));
    const pending=data.applications.filter(a=>a.status==='submitted');
    if(pending.length)tasks.push({kind:'Review applications',title:pending.length+' applications awaiting review',detail:'Open the publishing workspace to review and update stages.',priority:'High',target:'publishing'});
    return tasks;
  }
  function forecast(rows,currency){
    const eligible=rows.filter(r=>r.currency===currency);
    const total={billings:0,cost:0,potential:0,weighted:0};
    eligible.forEach(r=>{const amount=r.hours*r.billRate,cost=r.hours*r.costRate;if(r.status==='Confirmed'){total.billings+=amount;total.cost+=cost;}else{total.potential+=amount;total.weighted+=amount*r.probability/100;}});
    return {...total,gp:total.billings-total.cost,margin:total.billings?(total.billings-total.cost)/total.billings*100:0};
  }
  const api={age,operating,metrics,actions,forecast,activeStages};
  if(typeof module==='object'&&module.exports)module.exports=api;else root.BenchProAdminModel=api;
})(typeof window!=='undefined'?window:globalThis);
