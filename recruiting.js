(async function(){
  'use strict';
  const testDataset=new URLSearchParams(location.search).get('data')==='test';
  const S=window.Shortlist,E=S.esc,$=id=>document.getElementById(id),A=window.ProjectsAPI,dialog=$('slDialog');
  const api=async(path,options={})=>{const session=await A.session(true);if(!session)throw new Error('Sign in with your BenchPro staff account.');return fetch('https://ttmkcmeqiawrzbvymhal.supabase.co/rest/v1/'+path,{...options,headers:{apikey:'sb_publishable_kYY2o5gsLpUww-bgH0az4A_nQhdMiaN',Authorization:'Bearer '+session.access_token,'Content-Type':'application/json',...(options.headers||{})}})};
  const T=S.transport(api);let data={roles:[],clients:[],candidates:[],applications:[],listings:[],sources:[],reviews:[],submissions:[]},queue='reviews',busy=false,ticket=0;
  const role=id=>data.roles.find(r=>r.id===id),candidate=id=>data.candidates.find(c=>c.id===id),company=r=>data.clients.find(c=>c.id===r?.client_id)?.company_name||r?.company_name||'Client unavailable';
  function error(message='',inside=false){const node=$(inside?'slActionError':'slError');if(node){node.textContent=message;node.hidden=!message}}
  function mount(title,body,footer=''){ticket++;$('slDialogTitle').textContent=title;$('slDialogBody').innerHTML=body+'<div id="slActionError" class="sl-error" role="alert" hidden></div>';$('slDialogFooter').innerHTML=footer;if(!dialog.open)dialog.showModal()}
  function render(){
    const counts=[['In screening',data.reviews.filter(r=>r.state==='draft').length],['With clients',data.submissions.filter(s=>!s.revoked_at).length],['Withdrawn profiles',data.submissions.filter(s=>s.revoked_at).length],['Client action due',data.submissions.filter(s=>!s.revoked_at&&s.needs_client_response&&s.status!=='declined').length]];
    $('slMetrics').innerHTML=counts.map(([label,value])=>`<div class="sl-metric"><span>${label}</span><strong>${value}</strong></div>`).join('');
    document.querySelectorAll('[data-queue]').forEach(b=>b.setAttribute('aria-selected',String(b.dataset.queue===queue)));$('slState').hidden=queue!=='reviews';
    const q=$('slSearch').value.trim().toLowerCase(),state=$('slState').value;
    if(queue==='reviews'){
      const rows=data.reviews.filter(r=>(!state||r.state===state)&&[r.profile.full_name,role(r.staffing_request_id)?.role_or_skills,company(role(r.staffing_request_id))].join(' ').toLowerCase().includes(q));
      $('slRows').innerHTML=rows.length?rows.map(r=>{const j=role(r.staffing_request_id),s=data.submissions.find(s=>s.review_id===r.id&&!s.revoked_at),overdue=r.next_action_at&&r.next_action_at<new Date().toISOString().slice(0,10)&&r.state!=='closed';return `<article class="sl-row"><div><h3>${E(r.profile.full_name)}</h3><p>${E(j?.role_or_skills)} · ${E(company(j))}</p><div class="sl-row-meta">${S.pill(r.state)}${s?S.pill(s.status):''}<span class="sl-caption ${overdue?'sl-overdue':''}">${r.next_action_at?`${overdue?'Overdue · ':'Next action · '}${S.date(r.next_action_at)}`:'Set a next action date'}</span></div></div><div class="sl-actions"><button class="sl-button" data-review="${E(r.id)}">Open submission →</button>${testDataset&&j?.client_id?`<a class="sl-link" href="client.html?manage=${E(j.client_id)}">Client view ↗</a>`:''}</div></article>`}).join(''):S.empty('A focused shortlist starts here','Review incoming applications or start an submission for a registered candidate.');
    }else{
      const rows=data.applications.filter(a=>[candidate(a.candidate_id)?.full_name,data.listings.find(p=>p.id===a.project_id)?.title].join(' ').toLowerCase().includes(q));
      $('slRows').innerHTML=rows.length?rows.map(a=>{const c=candidate(a.candidate_id),p=data.listings.find(p=>p.id===a.project_id),source=data.sources.find(s=>s.project_id===a.project_id),existing=data.reviews.find(r=>r.application_id===a.id||r.candidate_id===a.candidate_id&&r.staffing_request_id===source?.staffing_request_id),active=!['withdrawn','rejected','closed','placed'].includes(a.status);return `<article class="sl-row"><div><h3>${E(c?.full_name||'Candidate')}</h3><p>${E(p?.title)} · ${E(c?.primary_role)}</p><p>${E((c?.skills||[]).join(' · '))}</p><div class="sl-row-meta">${S.pill(a.status)}<span class="sl-caption">Applied ${S.date(a.created_at)}</span></div></div>${existing?`<button class="sl-button" data-review="${E(existing.id)}">Open submission →</button>`:active&&source?.staffing_request_id?`<button class="sl-button" data-start-application="${E(a.id)}">Start screening →</button>`:active?'<a class="sl-link" href="publishing.html">Link listing to a client role first ↗</a>':'<span class="sl-caption">Application closed</span>'}</article>`}).join(''):S.empty('No applications in this view','Applications to your published projects appear here.');
    }
  }
  async function load(){
    error('');$('slRefresh').disabled=true;
    try{
      await T.action('capabilities');
      const tables=[['roles','staffing_requests',{select:'id,client_id,company_name,role_or_skills,status,is_demo,assigned_to',is_demo:'eq.'+testDataset,order:'created_at.desc,id.asc'}],['clients','clients',{select:'id,company_name',is_demo:'eq.'+testDataset,order:'id.asc'}],['candidates','candidate_accounts',{select:'id,full_name,primary_role,skills,years_experience,country_or_timezone,availability,available_from,profile_summary,resume_file_path,resume_file_name,is_demo',is_demo:'eq.'+testDataset,order:'full_name.asc,id.asc'}],['applications','project_applications',{select:'id,candidate_id,project_id,status,created_at',order:'created_at.desc,id.asc'}],['listings','project_listings',{select:'id,title,is_demo',is_demo:'eq.'+testDataset,order:'id.asc'}],['sources','project_listing_sources',{select:'project_id,staffing_request_id',order:'project_id.asc'}],['reviews','shortlist_reviews',{select:'*',order:'updated_at.desc,id.asc'}],['submissions','client_submissions',{select:'*',order:'published_at.desc,id.asc'}]];
      const results=await Promise.all(tables.map(async([key,table,params])=>[key,await T.all(table,params)]));data=Object.fromEntries(results);
      const live=new Set(data.roles.map(r=>r.id)),listings=new Set(data.listings.map(p=>p.id));data.reviews=data.reviews.filter(r=>live.has(r.staffing_request_id));data.submissions=data.submissions.filter(s=>live.has(s.staffing_request_id));data.applications=data.applications.filter(a=>listings.has(a.project_id));
      $('slAccess').hidden=true;$('slWorkspace').hidden=false;
      if(!$('slDataset')){const mode=document.createElement('div');mode.id='slDataset';mode.className='sl-notice';mode.innerHTML=testDataset?'Test dataset · fictional records. Changes are saved. <a href="recruiting.html">Return to live data</a>':'Working with real records. <a href="recruiting.html?data=test">Open test dataset</a>';$('slWorkspace').prepend(mode);if(testDataset)document.querySelectorAll('a[href="admin.html"],a[href="publishing.html"]').forEach(a=>a.href+='?data=test');}
      $('slNew').hidden=false;render();return true;
    }catch(e){error(e.message);$('slWorkspace').hidden=true;$('slNew').hidden=true;dialog.close();$('slAccess').hidden=false;$('slAccess').innerHTML='The recruiting desk requires approved BenchPro staff access. <a href="login.html">Sign in</a>.';return false}finally{$('slRefresh').disabled=false}
  }
  function newSubmission(application,selectedCandidate){
    const source=application&&data.sources.find(s=>s.project_id===application.project_id),roles=data.roles.filter(r=>r.client_id&&r.status!=='closed');
    mount('Start a client submission',`<p class="sl-muted">Start a private screening record. Nothing is shared with the client at this step.</p><form id="slCreateForm" class="sl-form-grid" style="margin-top:22px"><label class="sl-field wide">Client role<select name="staffing_request_id" required><option value="">Choose a role</option>${roles.map(r=>`<option value="${E(r.id)}" ${source?.staffing_request_id===r.id?'selected':''}>${E(company(r)+' · '+r.role_or_skills)}</option>`).join('')}</select></label><label class="sl-field wide">Registered candidate<select name="candidate_id" required><option value="">Choose a candidate</option>${data.candidates.map(c=>`<option value="${E(c.id)}" ${(application?.candidate_id||selectedCandidate)===c.id?'selected':''}>${E(c.full_name+' · '+c.primary_role)}</option>`).join('')}</select></label></form><p class="sl-note">Sourced consideration is recorded separately from an application. An existing application is linked automatically when it matches this role.</p>`,`<button class="sl-button" data-close>Cancel</button><button class="sl-button primary" type="submit" form="slCreateForm">Start screening</button>`);
    $('slCreateForm').onsubmit=async e=>{e.preventDefault();await run(async()=>{const f=new FormData(e.currentTarget),result=await T.action('create',{...Object.fromEntries(f),...(application?{application_id:application.id}:{})});await load();await openReview(result.id)})};
  }
  async function run(fn){if(busy)return;busy=true;error('',true);dialog.querySelectorAll('button').forEach(b=>b.disabled=true);try{await fn()}catch(e){error(e.message,true)}finally{busy=false;dialog.querySelectorAll('button').forEach(b=>b.disabled=false)}}
  async function openReview(id) {
    const current=++ticket;
    try {
      const [reviews,permissions,submissions,activity]=await Promise.all([
        T.all('shortlist_reviews',{id:'eq.'+id,select:'*'}),
        T.all('shortlist_permissions',{review_id:'eq.'+id,select:'*',order:'requested_at.desc,id.desc'}),
        T.all('client_submissions',{review_id:'eq.'+id,select:'*',order:'published_at.desc,id.desc'}),
        T.all('shortlist_activity',{review_id:'eq.'+id,select:'*',order:'occurred_at.asc,id.asc'})
      ]);
      if(current!==ticket)return;
      const r=reviews[0];if(!r)throw new Error('Submission unavailable.');
      const job=role(r.staffing_request_id),c=candidate(r.candidate_id),submission=submissions.find(s=>!s.revoked_at),editing=r.state==='draft';
      const form=editing?`<form id="slReviewForm">
        <div class="sl-rating-editor"><label class="sl-field">BenchPro fit rating<input name="fit_rating" type="number" inputmode="decimal" min="1" max="5" step="0.1" placeholder="4.8" value="${E(r.fit_rating??'')}" aria-describedby="slRatingHelp"></label><span id="slRatingHelp" class="sl-caption">1–5 · Fit for this role</span></div>
        <div class="sl-form-grid">${S.fields.map(([key,label])=>`<label class="sl-field ${['summary','project_evidence','requirements_evidence'].includes(key)?'wide':''}">${E(label)}${['summary','project_evidence','requirements_evidence'].includes(key)?`<textarea name="${key}" maxlength="2500" required minlength="20">${E(r.profile[key])}</textarea>`:`<input name="${key}" value="${E(r.profile[key])}" maxlength="300" ${['full_name','title','skills','availability'].includes(key)?'required':''}>`}</label>`).join('')}</div>
        <p class="sl-note">These professional details and the fit rating will be shared. Remove contact details and confidential information. Original resumes and internal notes remain private.</p>
        <h3 class="sl-section-heading">Private screening</h3><label class="sl-field">Internal notes<textarea name="screening_notes" maxlength="6000">${E(r.screening_notes)}</textarea></label>
        <label class="sl-check"><input name="screening_confirmed" type="checkbox" ${r.screening_confirmed?'checked':''}>I screened this candidate against the role and recorded supporting evidence.</label>
        <label class="sl-check"><input name="candidate_discussed" type="checkbox">I have discussed this role with the candidate and confirmed their interest and availability.</label>
        <label class="sl-field">Next action date<input type="date" name="next_action_at" value="${E(r.next_action_at||'')}"></label>
        <div class="sl-actions" id="slFormActions" style="margin-top:20px"><button class="sl-button" type="submit" name="save">Save draft</button><button class="sl-button primary" type="submit" name="send">Review & send to client</button></div>
        <div id="slSendConfirm" class="sl-approval" hidden><h3>Send this profile to ${E(company(job))}?</h3><p class="sl-caption">The client superuser and the teammate assigned to this role can review this profile.</p><div id="slSendPreview"></div><div class="sl-actions"><button class="sl-button" type="button" id="slKeepEditing">Keep editing</button><button class="sl-button primary" type="button" id="slSend">Send to client</button></div></div>
      </form>`:S.profile(r.profile,submission?.fit_rating??r.fit_rating)+`<details class="sl-no-print"><summary>Private screening notes</summary><p class="sl-prose">${E(r.screening_notes||'No internal notes.')}</p></details>`;
      const history=permissions.length?`<details class="sl-note"><summary>Previous candidate decisions</summary>${permissions.map(p=>`<p>${E(p.decision)} · ${S.date(p.decided_at||p.requested_at)}</p>`).join('')}<p>Historical decisions are retained. Discuss the role again before preparing another submission.</p></details>`:'';
      mount(`${company(job)} · ${job?.role_or_skills||'Candidate submission'}`,
        `<div class="sl-actions" style="margin-bottom:20px">${S.pill(r.state)}${submission?S.pill(submission.status):''}${c?.resume_file_path?'<button class="sl-button" id="slOriginalResume">Original resume · staff only</button>':''}</div>${form}${history}
        ${submission?`<form id="slRatingForm" class="sl-rating-update"><label class="sl-field">Update BenchPro fit rating<input name="fit_rating" type="number" inputmode="decimal" min="1" max="5" step="0.1" required value="${E(submission.fit_rating??'')}"></label><button class="sl-button">Save rating</button></form>`:''}
        <h3 class="sl-section-heading">Activity & client feedback</h3>${S.history(activity)}
        ${submission&&submission.status!=='declined'?'<form id="slReplyForm"><label class="sl-field">Reply to the client<textarea name="message" required minlength="5" maxlength="3000" placeholder="Visible to the client team with access to this role."></textarea></label><button class="sl-button primary" style="margin-top:10px">Send response</button></form>':''}`,
        `<button class="sl-button" data-close>Close</button>${submission?'<button class="sl-button danger" id="slWithdraw">Withdraw profile</button>':''}${!editing?'<button class="sl-button" id="slRevision">'+(submission?'Withdraw & revise':'Prepare new revision')+'</button>':''}`);
      if(editing) {
        let pending;
        $('slReviewForm').onsubmit=async e=>{
          e.preventDefault();error('',true);
          const f=new FormData(e.currentTarget),profile=Object.fromEntries(S.fields.map(([k])=>[k,String(f.get(k)||'').trim()]));
          pending={id:r.id,revision:r.revision,profile,fit_rating:f.get('fit_rating'),screening_notes:f.get('screening_notes'),screening_confirmed:f.has('screening_confirmed'),candidate_discussed:f.has('candidate_discussed'),next_action_at:f.get('next_action_at')};
          if(e.submitter?.name!=='send')return run(async()=>{await T.action('save',pending);await load();await openReview(r.id)});
          if(!pending.fit_rating||!pending.screening_confirmed||!pending.candidate_discussed){error('Add a fit rating and confirm screening and the candidate conversation before sending.',true);return}
          $('slSendPreview').innerHTML=S.profile(profile,Number(pending.fit_rating));$('slSendConfirm').hidden=false;$('slFormActions').hidden=true;
          $('slReviewForm').querySelectorAll('input,textarea').forEach(x=>x.disabled=true);$('slSend').focus();
        };
        $('slKeepEditing').onclick=()=>{$('slSendConfirm').hidden=true;$('slFormActions').hidden=false;$('slReviewForm').querySelectorAll('input,textarea').forEach(x=>x.disabled=false)};
        $('slSend').onclick=()=>run(async()=>{await T.action('submit',pending);await load();await openReview(r.id)});
      }
      if($('slRatingForm'))$('slRatingForm').onsubmit=e=>{e.preventDefault();const rating=new FormData(e.currentTarget).get('fit_rating');run(async()=>{await T.action('rate',{id:submission.id,revision:submission.revision,fit_rating:rating});await load();await openReview(r.id)})};
      if($('slReplyForm'))$('slReplyForm').onsubmit=e=>{e.preventDefault();const message=new FormData(e.currentTarget).get('message');run(async()=>{await T.action('reply',{id:submission.id,revision:submission.revision,message});await load();await openReview(r.id)})};
      function withdraw(revise) {
        mount(revise?'Prepare a new revision':'Withdraw candidate profile',
          `<p class="sl-muted">${submission?'This profile will disappear from the client pipeline and further client actions will be blocked. ':''}${revise?'You can edit the draft and confirm a fresh candidate conversation before sending again. ':''}The candidate’s application will not be marked withdrawn. Previous copies saved by the client cannot be recalled.</p><form id="slWithdrawForm" style="margin-top:20px"><label class="sl-field">Internal reason<textarea name="message" required minlength="5" maxlength="3000"></textarea></label></form>`,
          `<button class="sl-button" id="slCancelWithdrawal">Cancel</button><button class="sl-button danger" form="slWithdrawForm">${revise?'Confirm revision':'Withdraw profile'}</button>`);
        $('slCancelWithdrawal').onclick=()=>openReview(r.id);
        $('slWithdrawForm').onsubmit=e=>{e.preventDefault();const message=new FormData(e.currentTarget).get('message');run(async()=>{await T.action(revise?'reset':'withdraw',{id:r.id,revision:r.revision,message});await load();await openReview(r.id)})};
      }
      if($('slWithdraw'))$('slWithdraw').onclick=()=>withdraw(false);
      if($('slRevision'))$('slRevision').onclick=()=>withdraw(true);
      if($('slOriginalResume'))$('slOriginalResume').onclick=async()=>{
        const popup=window.open('about:blank','_blank');if(!popup){error('Allow pop-ups to view the private resume.',true);return}popup.opener=null;
        try{const session=await A.session(true),res=await fetch('https://ttmkcmeqiawrzbvymhal.supabase.co/storage/v1/object/sign/candidate-resumes/'+c.resume_file_path.split('/').map(encodeURIComponent).join('/'),{method:'POST',headers:{apikey:'sb_publishable_kYY2o5gsLpUww-bgH0az4A_nQhdMiaN',Authorization:'Bearer '+session.access_token,'Content-Type':'application/json'},body:JSON.stringify({expiresIn:60})}),result=await res.json();if(!res.ok||!result.signedURL)throw new Error('Resume unavailable.');popup.location.href=/^https:\/\//.test(result.signedURL)?result.signedURL:'https://ttmkcmeqiawrzbvymhal.supabase.co/storage/v1'+result.signedURL}catch(e){popup.close();error(e.message,true)}
      };
    }catch(e){error(e.message,dialog.open)}
  }

  document.addEventListener('click',e=>{const close=e.target.closest('[data-close]');if(close){dialog.close();return}const b=e.target.closest('[data-review]');if(b){openReview(b.dataset.review);return}const a=e.target.closest('[data-start-application]');if(a){newSubmission(data.applications.find(r=>r.id===a.dataset.startApplication));return}const q=e.target.closest('[data-queue]');if(q){queue=q.dataset.queue;render()}});
  dialog.addEventListener('close',()=>{ticket++});$('slSearch').oninput=render;$('slState').onchange=render;$('slRefresh').onclick=load;$('slNew').onclick=()=>newSubmission();
  await load();const candidateId=new URLSearchParams(location.search).get('candidate');if(candidateId&&data.candidates.some(c=>c.id===candidateId))newSubmission(null,candidateId);const initial=new URLSearchParams(location.search).get('review');if(initial)await openReview(initial);const applicationId=new URLSearchParams(location.search).get('application');if(applicationId){const a=data.applications.find(a=>a.id===applicationId);const review=data.reviews.find(r=>r.application_id===applicationId);if(review)await openReview(review.id);else if(a)newSubmission(a);}
})();
