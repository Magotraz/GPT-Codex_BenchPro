/* Shared presentation and authenticated transport. Permissions are enforced by SQL. */
(function(root){
  'use strict';
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const labels={draft:'Screening',permission_pending:'Legacy review',ready:'Legacy ready',published:'With client',closed:'Closed',awaiting_review:'Awaiting review',interview_requested:'Interview requested',on_hold:'On hold',declined:'Not proceeding',pending:'Awaiting your permission',granted:'Approved',withdrawn:'Withdrawn',cancelled:'Superseded'};
  const fields=[['full_name','Candidate name'],['title','Professional title'],['experience','Relevant experience'],['skills','Core skills'],['location','Location / time-zone overlap'],['availability','Confirmed availability'],['summary','Why this person fits'],['project_evidence','Relevant project experience'],['requirements_evidence','Evidence against role requirements'],['client_rate','Approved client rate (optional)']];
  const date=v=>v?new Date(/^\d{4}-\d{2}-\d{2}$/.test(v)?v+'T12:00:00':v).toLocaleDateString(undefined,{day:'numeric',month:'short',year:'numeric'}):'—';
  const pill=s=>`<span class="sl-pill sl-${esc(s)}">${esc(labels[s]||s)}</span>`;
  const rating=value=>value==null?'':`<div class="sl-fit-rating"><span>BenchPro fit rating</span><strong>${esc(Number(value).toFixed(1))}<small> / 5</small></strong></div>`;
  function profile(p={},fitRating=null){return `<article class="sl-profile"><div class="sl-profile-heading"><div class="sl-avatar" aria-hidden="true">${esc((p.full_name||'?').split(/\s+/).slice(0,2).map(s=>s[0]).join(''))}</div><div><h2>${esc(p.full_name)}</h2><p>${esc(p.title)}</p></div>${rating(fitRating)}</div><div class="sl-tags">${(p.skills||'').split(',').map(s=>s.trim()).filter(Boolean).map(s=>`<span>${esc(s)}</span>`).join('')}</div><dl class="sl-facts">${['experience','location','availability','client_rate'].filter(k=>p[k]).map(k=>`<div><dt>${esc(fields.find(f=>f[0]===k)[1])}</dt><dd>${esc(p[k])}</dd></div>`).join('')}</dl>${['summary','project_evidence','requirements_evidence'].filter(k=>p[k]).map(k=>`<section><h3>${esc(fields.find(f=>f[0]===k)[1])}</h3><p class="sl-prose">${esc(p[k])}</p></section>`).join('')}</article>`}
  function history(rows){return rows.length?`<ol class="sl-history">${rows.map(e=>`<li><div><strong>${esc(e.actor_label)}</strong><time>${date(e.occurred_at)}</time></div><span class="sl-caption">${esc((e.kind||'').replaceAll('_',' '))}${e.audience==='staff'?' · Internal':''}</span><p class="sl-prose">${esc(e.message)}</p></li>`).join('')}</ol>`:'<p class="sl-empty">No discussion yet.</p>'}
  const empty=(title,message)=>`<div class="sl-empty"><span aria-hidden="true">☷</span><h3>${esc(title)}</h3><p>${esc(message)}</p></div>`;
  function transport(api){
    async function request(path,options={}){const res=await api(path,options);const data=res.status===204?null:await res.json().catch(()=>null);if(!res.ok){const e=new Error(data?.code==='P0001'?data.message:res.status===401?'Your session expired. Please sign in again.':res.status===403?'You no longer have access to this action.':'Could not complete this request. Refresh and try again.');e.code=data?.code;throw e}return data}
    const all=async(table,params={})=>{let rows=[],offset=0;while(true){const batch=await request(table+'?'+new URLSearchParams({...params,limit:'200',offset:String(offset)}));if(!Array.isArray(batch))throw new Error('Could not load this workspace.');rows.push(...batch);if(batch.length<200)return rows;offset+=batch.length}};
    return {request,all,action:(action,payload={})=>request('rpc/shortlist_action',{method:'POST',body:JSON.stringify({action,payload})})};
  }
  root.Shortlist={esc,labels,fields,date,pill,rating,profile,history,empty,transport};
  if(typeof module!=='undefined')module.exports=root.Shortlist;
})(typeof window!=='undefined'?window:globalThis);
