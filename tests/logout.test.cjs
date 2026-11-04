const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const cases=[['admin.html',"document.getElementById('logoutButton').addEventListener"],['client.js',"$('signOut').addEventListener"],['candidate.html',"document.getElementById('signOutButton').addEventListener"],['login.html',"$('signOutButton').addEventListener"]];
for(const [file,marker] of cases)for(const offline of [false,true])for(const managementId of file==='client.js'?[null,'sample-client']:[null]){
 test(`${file} logout → homepage; ${offline?'offline':'online'}${managementId?' staff client view':''}`,async()=>{
  const source=fs.readFileSync(path.join(__dirname,'..',file),'utf8'),start=source.indexOf(marker);assert.ok(start>=0);
  const end=source.indexOf('});',start)+3,registration=source.slice(start,end);
  const storage=new Map([['benchpro_staff_session','staff'],['benchpro_candidate_session','account'],['unrelated','keep']]);
  let handler,redirect,logoutCalls=0,resetCalls=0;
  const element={disabled:false,addEventListener:(type,callback)=>{assert.equal(type,'click');handler=callback}};
  const auth=async(action)=>{assert.equal(action,'logout');logoutCalls++;if(offline)throw Error('Offline');return {ok:true}};
  const location={replace(target){assert.equal(storage.has('benchpro_staff_session'),false);assert.equal(storage.has('benchpro_candidate_session'),false);redirect=target}};
  const context={document:{getElementById:()=>element},$:()=>element,sessionStorage:{removeItem:key=>storage.delete(key)},
   window:{location,CandidateUpdates:{reset:()=>resetCalls++}},location,session:{access_token:'fixture'},getSession:()=>({access_token:'fixture'}),
   accessToken:async()=>'fixture',auth,authPost:auth,authRequest:auth,requests:[1],clients:[1],expandedClients:new Set([1]),profile:{},profileForm:{reset:()=>resetCalls++},
   managementId,STAFF_KEY:'benchpro_staff_session',CLIENT_KEY:'benchpro_candidate_session',SESSION_KEY:file==='admin.html'?'benchpro_staff_session':'benchpro_candidate_session',
   showLogin:()=>assert.fail('Legacy login must not appear'),showSignedOut:()=>assert.fail('Legacy signed-out form must not appear')};
  vm.createContext(context);
  // Execute each page's real clearSession helper, where it has one.
  if(file!=='client.js'){
   const match=source.match(/(?:const clearSession=\(\)=>[^\n]+|function clearSession\(\)\{[^\n]+\})/);assert.ok(match);vm.runInContext(match[0],context);
  }
  vm.runInContext(registration,context);await handler();assert.equal(redirect,'/');assert.equal(logoutCalls,1);assert.equal(storage.get('unrelated'),'keep');
  if(file==='candidate.html')assert.equal(resetCalls,2);
 });
}
