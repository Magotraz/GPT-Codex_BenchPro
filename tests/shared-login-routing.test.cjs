const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// Exercise the routing used by the static login page without real credentials.
const html = fs.readFileSync(path.join(__dirname, '..', 'login.html'), 'utf8');
const start = html.indexOf('    const SUPABASE_URL=');
const end = html.indexOf("    $('loginForm').addEventListener");
assert.ok(start >= 0 && end > start, 'Login routing source is present');
const routingSource = html.slice(start, end);
const account = {access_token:'test-token',refresh_token:'test-refresh',user:{id:'test-user'}};

function harness({staff=false,candidates=[],memberships=[],clients=[],staffOk=true}={}) {
  const storage = new Map([['benchpro_staff_session','stale-session']]);
  const calls = [], redirects = [];
  const context = vm.createContext({
    URLSearchParams,
    document:{getElementById:()=>({hidden:false,classList:{toggle(){}}})},
    sessionStorage:{getItem:key=>storage.get(key)||null,setItem:(key,value)=>storage.set(key,value),removeItem:key=>storage.delete(key)},
    location:{replace:url=>redirects.push(url)},
    fetch:async(url,options)=>{
      calls.push({url,options});
      let data;
      if(url.endsWith('/rpc/is_benchpro_staff_account'))return {ok:staffOk,json:async()=>staff};
      if(url.includes('/candidate_accounts?'))data=candidates;
      else if(url.includes('/client_memberships?'))data=memberships;
      else if(url.includes('/clients?'))data=clients;
      else throw new Error('Unexpected request: '+url);
      return {ok:true,json:async()=>data};
    }
  });
  vm.runInContext(routingSource,context);
  vm.runInContext('showDestinations=options=>{globalThis.choices=options.map(({title,detail})=>({title,detail}))}',context);
  return {context,storage,calls,redirects,route:()=>context.routeAccount(account)};
}

test('approved staff reach admin with a usable staff session',async()=>{
  const h=harness({staff:true});
  await h.route();
  assert.deepEqual(h.redirects,['admin.html']);
  assert.deepEqual(JSON.parse(h.storage.get('benchpro_staff_session')),account);
  assert.equal(h.calls.length,1,'staff do not depend on candidate or client queries');
  assert.equal(h.calls[0].options.headers.Authorization,'Bearer test-token');
});

test('candidate routing is retained and stale staff access is cleared',async()=>{
  const h=harness({candidates:[{id:'candidate-1'}]});
  await h.route();
  assert.deepEqual(h.redirects,['candidate.html']);
  assert.equal(h.storage.has('benchpro_staff_session'),false);
});

test('client-only accounts reach their own workspace',async()=>{
  const h=harness({memberships:[{client_id:'client-1',role:'recruiter'}],clients:[{id:'client-1',company_name:'Client'}]});
  await h.route();
  assert.deepEqual(h.redirects,['client.html?client_id=client-1']);
  assert.equal(h.storage.has('benchpro_staff_session'),false);
});

test('candidate and client accounts retain the workspace chooser',async()=>{
  const h=harness({candidates:[{id:'candidate-1'}],memberships:[{client_id:'client-1',role:'superuser'}],clients:[{id:'client-1',company_name:'Client'}]});
  await h.route();
  assert.deepEqual(h.redirects,[]);
  assert.deepEqual(Array.from(h.context.choices,x=>x.title),['Candidate dashboard','Client']);
});

test('failed staff verification cannot create an admin session',async()=>{
  const h=harness({staffOk:false});
  await assert.rejects(h.route(),/Could not verify your BenchPro access/);
  assert.deepEqual(h.redirects,[]);
  assert.equal(h.storage.has('benchpro_staff_session'),false);
});

test('staff verification requires an actual boolean response',async()=>{
  const h=harness({staff:'true'});
  await assert.rejects(h.route(),/Could not verify your BenchPro access/);
  assert.deepEqual(h.redirects,[]);
  assert.equal(h.storage.has('benchpro_staff_session'),false);
});

test('clearing shared login removes both session keys',async()=>{
  const h=harness({staff:true});
  await h.route();
  h.context.clearSession();
  assert.equal(h.storage.size,0);
});
