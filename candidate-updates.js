/* Private candidate updates, backed by application activity and account read receipts. */
(function(){
  'use strict';
  const $=id=>document.getElementById(id),E=window.ProjectsModel.esc,M=window.CandidateModel;
  const bell=$('cwUpdatesBell'),dialog=$('cwUpdatesDialog');
  let ctx=null,events=[],read=new Set(),ready=false,loading=false,saving=false,limit=20,version=0;
  const query=(table,params)=>table+'?'+new URLSearchParams(params);
  function error(text=''){$('cwUpdatesError').textContent=text;$('cwUpdatesError').hidden=!text}
  async function request(context,path,options={}){const r=await context.api(path,options);if(!r.ok)throw new Error('Request failed');return r.status===204?null:r.json().catch(()=>null)}
  async function all(context,table,params){let result=[],offset=0;while(true){const rows=await request(context,query(table,{...params,limit:'200',offset:String(offset)}));if(!Array.isArray(rows))throw new Error('Invalid updates response');result.push(...rows);if(!rows.length)return result;offset+=rows.length}}
  function render(){
    const unread=events.filter(e=>!read.has(e.id)).length;
    $('cwUpdatesDot').hidden=!ready||unread===0;
    bell.setAttribute('aria-label',ready&&unread?`Updates, ${unread} unread`:'Updates');
    $('cwUpdatesSummary').textContent=loading?'Checking your updates…':ready?(events.length?`${unread} unread · ${events.length} update${events.length===1?'':'s'}`:'Application updates for your account.'):'Updates are temporarily unavailable.';
    $('cwUpdatesReadAll').hidden=!ready||unread===0;$('cwUpdatesReadAll').disabled=loading||saving;
    $('cwUpdatesRetry').disabled=loading||saving;
    $('cwUpdatesMore').hidden=!ready||events.length<=limit;
    $('cwUpdatesList').setAttribute('aria-busy',String(loading));
    if(!ready){$('cwUpdatesList').innerHTML='<p class="cw-updates-empty">'+(loading?'Loading your updates…':'Use Refresh to try again.')+'</p>';return}
    if(!events.length){$('cwUpdatesList').innerHTML='<div class="cw-updates-empty"><strong>You’re all caught up.</strong><p>Updates about your applications will appear here as they happen.</p></div>';return}
    $('cwUpdatesList').innerHTML=events.slice(0,limit).map(e=>{
      const a=ctx.applications.find(a=>a.id===e.application_id),stage=(e.kind==='shortlist'?[e.title,e.message]:M.stages[e.status])||['Application updated','Open your application to view its progress.'],isRead=read.has(e.id),when=new Date(e.occurred_at).toLocaleString(undefined,{day:'numeric',month:'short',year:'numeric',hour:'numeric',minute:'2-digit'});
      return `<button type="button" class="cw-update-item ${isRead?'':'unread'}" data-update="${E(e.id)}" ${saving?'disabled':''}><span class="cw-update-indicator" aria-hidden="true"></span><span><strong>${E(stage[0])}${isRead?'':'<span class="cw-sr-only"> · Unread</span>'}</strong><b>${E(e.kind==='shortlist'?'Client submission':(a?.project_listings?.title||'Your application'))}</b><span class="cw-update-description">${E(stage[1])}</span><time datetime="${E(e.occurred_at)}">${E(when)}</time></span>${e.kind==='shortlist'?'':'<span aria-hidden="true">↗</span>'}</button>`;
    }).join('');
  }
  async function load(options){
    const ticket=++version;ctx=options;loading=true;error('');render();
    try{
      let next=[],receipts=[],submissions=[];
      if(options.profile?.id){
        if(!options.applications)throw new Error('Applications unavailable');
        // Explicit candidate filter also isolates staff accounts with candidate access.
        next=await all(options,'candidate_application_events',{select:'id,application_id,status,occurred_at,project_applications!inner(candidate_id)','project_applications.candidate_id':'eq.'+options.profile.id,order:'occurred_at.desc,id.desc'});
        submissions=(await all(options,'candidate_shortlist_updates',{select:'id,candidate_id,title,message,occurred_at,read_at',candidate_id:'eq.'+options.profile.id,archived_at:'is.null',order:'occurred_at.desc,id.desc'})).map(e=>({...e,kind:'shortlist'}));
        receipts=await all(options,'candidate_update_receipts',{select:'event_id',user_id:'eq.'+options.getSession().user.id,order:'event_id.asc'});
      }
      if(ticket!==version)return;
      const ownIds=new Set((options.applications||[]).map(a=>a.id));
      events=[...next.filter(e=>ownIds.has(e.application_id)),...submissions].sort((a,b)=>String(b.occurred_at).localeCompare(String(a.occurred_at))||String(b.id).localeCompare(String(a.id)));read=new Set([...receipts.map(r=>r.event_id),...submissions.filter(e=>e.read_at).map(e=>e.id)]);ready=true;
    }catch(e){if(ticket!==version)return;ready=false;events=[];read.clear();error('We couldn’t load your updates. Please try Refresh.')}
    finally{if(ticket===version){loading=false;render()}}
  }
  async function mark(ids){
    const context=ctx,ticket=version; saving=true;error('');render();
    try{
      const shortlistIds=ids.filter(id=>events.find(e=>e.id===id)?.kind==='shortlist'),applicationIds=ids.filter(id=>!shortlistIds.includes(id));
      if(shortlistIds.length)await request(context,'candidate_shortlist_updates?'+new URLSearchParams({id:'in.('+shortlistIds.join(',')+')',candidate_id:'eq.'+context.profile.id}),{method:'PATCH',body:JSON.stringify({read_at:new Date().toISOString()})});
      if(applicationIds.length)await request(context,'candidate_update_receipts?on_conflict=user_id,event_id',{method:'POST',headers:{Prefer:'resolution=ignore-duplicates,return=minimal'},body:JSON.stringify(applicationIds.map(id=>({user_id:context.getSession().user.id,event_id:id})))});
      if(ticket!==version)return false;
      ids.forEach(id=>read.add(id));return true;
    }catch(e){if(ticket===version)error('Couldn’t save the read status. Please try again.');return false}
    finally{saving=false;render()}
  }
  bell.onclick=()=>{if(!ctx)return;limit=20;dialog.showModal();render();if(!saving)ctx.onRefresh()};
  $('cwUpdatesClose').onclick=()=>dialog.close();
  dialog.addEventListener('click',e=>{if(e.target===dialog){const r=dialog.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)dialog.close()}});
  dialog.addEventListener('close',()=>bell.focus({preventScroll:true}));
  $('cwUpdatesRetry').onclick=()=>ctx?.onRefresh();
  $('cwUpdatesReadAll').onclick=async()=>{if(saving||loading||!ready)return;await mark(events.filter(e=>!read.has(e.id)).map(e=>e.id));if(dialog.open)$('cwUpdatesClose').focus()};
  $('cwUpdatesMore').onclick=()=>{limit+=20;render()};
  $('cwUpdatesList').onclick=async e=>{const button=e.target.closest('[data-update]');if(!button||saving||loading)return;const event=events.find(item=>item.id===button.dataset.update);if(!event)return;const context=ctx;if(await mark(read.has(event.id)?[]:[event.id])){if(event.kind!=='shortlist'){dialog.close();context.onOpen(event.application_id)}}};
  window.CandidateUpdates={load,reset(){version++;ctx=null;events=[];read.clear();ready=false;loading=false;saving=false;if(dialog.open)dialog.close();render()}};
})();
