const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(require('node:path').join(__dirname,'../login.html'),'utf8');
const source = html.match(/<script>\s*([\s\S]*?)<\/script>/)[1];
function page({hash='',pending=null,protocol='https:',staff=false,memberships=[],candidates=[],userOk=true}={}) {
  const nodes = new Map(), store = new Map(), redirects=[], history=[];
  const node = id => {if(!nodes.has(id))nodes.set(id,{hidden:false,textContent:'',disabled:false,handlers:{},classList:{toggle(){}},addEventListener(event,fn){this.handlers[event]=fn},querySelector(){return node(id+'-label')}});return nodes.get(id)};
  const context=vm.createContext({URL,URLSearchParams,Date,
    document:{getElementById:node,querySelector:()=>({href:''})},
    ProjectIntent:{capture(){},read:()=>pending,target:id=>'project.html?id='+id+'&apply=1'},
    sessionStorage:{getItem:k=>store.get(k)||null,setItem:(k,v)=>store.set(k,v),removeItem:k=>store.delete(k)},localStorage:{},
    window:{addEventListener(event,fn){node('window').handlers[event]=fn}},
    location:{protocol,origin:'https://www.benchpro.in',pathname:'/login.html',search:'',hash,assign:url=>redirects.push(url),replace:url=>redirects.push(url)},
    history:{replaceState:(_,__,url)=>history.push(url)},
    fetch:async url=>({ok:url.endsWith('/auth/v1/user')?userOk:true,json:async()=>url.endsWith('/auth/v1/user')?{id:'user-1'}:url.includes('is_benchpro_staff_account')?staff:url.includes('candidate_accounts')?candidates:url.includes('client_memberships')?memberships:url.includes('/clients?')?[{id:'client-1',company_name:'Client'}]:{}})
  });
  vm.runInContext(source,context);
  return {node,store,redirects,history,context};
}
const callback='#access_token=fake-access&refresh_token=fake-refresh&expires_in=3600';
const settle=()=>new Promise(resolve=>setImmediate(resolve));
test('Google opens account chooser and returns only to the common login URL',()=>{
  const h=page();h.node('googleLoginButton').handlers.click();const url=new URL(h.redirects[0]);
  assert.equal(url.origin,'https://ttmkcmeqiawrzbvymhal.supabase.co');assert.equal(url.pathname,'/auth/v1/authorize');
  assert.equal(url.searchParams.get('provider'),'google');assert.equal(url.searchParams.get('prompt'),'select_account');
  assert.equal(url.searchParams.get('redirect_to'),'https://www.benchpro.in/login.html');assert.equal(h.node('googleLoginButton').disabled,true);
  h.node('window').handlers.pageshow();assert.equal(h.node('googleLoginButton').disabled,false);
});
test('Google callback carries pending application context',()=>{
  const h=page({pending:'fcb54afe-b709-4dad-a9b3-51700ec6ac56'});h.node('googleLoginButton').handlers.click();
  assert.equal(new URL(new URL(h.redirects[0]).searchParams.get('redirect_to')).searchParams.get('apply_to'),'fcb54afe-b709-4dad-a9b3-51700ec6ac56');
});
test('local file preview does not attempt an invalid OAuth redirect',()=>{const h=page({protocol:'file:'});h.node('googleLoginButton').handlers.click();assert.equal(h.redirects.length,0);assert.match(h.node('feedback').textContent,/website/)});
for(const [name,options,target] of [
 ['candidate',{},'candidate.html'],['staff',{staff:true},'admin.html'],
 ['client',{memberships:[{client_id:'client-1',role:'recruiter'}]},'client.html?client_id=client-1'],
 ['pending application',{pending:'project-1'},'project.html?id=project-1&apply=1']
])test('OAuth callback verifies user and routes '+name,async()=>{const h=page({hash:callback,...options});await settle();assert.deepEqual(h.redirects,[target]);assert.equal(JSON.parse(h.store.get('benchpro_candidate_session')).user.id,'user-1');assert.deepEqual(h.history,['/login.html'])});
test('unverified OAuth callback cannot enter a workspace',async()=>{const h=page({hash:callback,userOk:false});await settle();assert.equal(h.redirects.length,0);assert.equal(h.store.has('benchpro_candidate_session'),false);assert.match(h.node('feedback').textContent,/Could not verify/)});
test('cancelled Google consent displays retry feedback and no session',async()=>{const h=page({hash:'#error=access_denied&error_description=untrusted'});await settle();assert.match(h.node('feedback').textContent,/Sign-in could not be completed/);assert.equal(h.redirects.length,0);assert.equal(h.store.size,0)});
test('password recovery callback still shows recovery form',async()=>{const h=page({hash:callback+'&type=recovery'});await settle();assert.equal(h.node('recoveryView').hidden,false);assert.equal(h.node('loginLayout').hidden,true);assert.equal(h.redirects.length,0)});
