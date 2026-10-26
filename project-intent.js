/* Only a project UUID can be carried through authentication; never a redirect URL. */
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.ProjectIntent=api})(typeof globalThis!=='undefined'?globalThis:this,function(){
  const KEY='benchpro_project_intent',TTL=24*60*60*1000;
  const valid=id=>typeof id==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id);
  function read(storage,now=Date.now()){try{const value=JSON.parse(storage.getItem(KEY));return valid(value?.id)&&Number.isFinite(value.created_at)&&now>=value.created_at&&now-value.created_at<TTL?value.id:null}catch{return null}}
  function capture(search,storage,now=Date.now(),backup){const requested=new URLSearchParams(search).get('apply_to'),current=read(storage,now),id=valid(requested)?requested:current||(backup?read(backup,now):null);if(id){const value=valid(requested)?JSON.stringify({id,created_at:now}):current?storage.getItem(KEY):backup?.getItem(KEY);try{storage.setItem(KEY,value);if(backup)backup.setItem(KEY,value)}catch{}}return id}
  const target=id=>valid(id)?'project.html?id='+encodeURIComponent(id)+'&apply=1':null;
  const clear=(storage,backup)=>{storage.removeItem(KEY);if(backup)backup.removeItem(KEY)};
  return {valid,read,capture,target,clear};
});
