const test=require('node:test');
const assert=require('node:assert/strict');
const M=require('../admin-model.js');
const {readAll}=require('../admin-data.js');

test('persisted test data has separate totals including candidates, roles and applications',()=>{
 const raw={clients:[{id:'real'},{id:'demo',is_demo:true}],roles:[{id:'r',client_id:'real'},{id:'d',client_id:'demo',is_demo:true}],candidates:[{id:'r'},{id:'d',is_demo:true}],listings:[{id:'r'},{id:'d',is_demo:true}],applications:[{project_id:'r'},{project_id:'d'}],members:[{client_id:'real'},{client_id:'demo'}]};
 const real=M.operating(raw),demo=M.operating(raw,true);
 for(const key of ['clients','roles','candidates','listings','applications','members'])assert.equal(demo[key].length,1);
 assert.equal(demo.clients[0].id,'demo');assert.equal(demo.candidates[0].id,'d');assert.equal(real.candidates[0].id,'r');
 assert.equal(raw.candidates.length,2);assert.equal(raw.clients[1].is_demo,true);
});
test('live operational totals exclude demo clients, roles and applications on demo listings',()=>{
 const d=M.operating({clients:[{id:'c'},{id:'demo',is_demo:true}],roles:[{id:'a',client_id:'c'},{id:'b',client_id:'demo'},{id:'c',is_demo:true},{id:'d',client_id:null}],listings:[{id:'p'},{id:'pd',is_demo:true}],applications:[{project_id:'p'},{project_id:'pd'}],members:[{client_id:'c'},{client_id:'demo'}]});
 assert.deepEqual(d.roles.map(r=>r.id),['a','d']);assert.equal(d.applications.length,1);assert.equal(d.members.length,1);
});
test('forecast separates currencies, confirmed gross profit and potential work',()=>{
 const rows=[{currency:'USD',status:'Confirmed',hours:100,billRate:80,costRate:55,probability:100},{currency:'USD',status:'Potential',hours:100,billRate:90,costRate:60,probability:60},{currency:'INR',status:'Confirmed',hours:160,billRate:2000,costRate:1200,probability:100}];
 assert.deepEqual(M.forecast(rows,'USD'),{billings:8000,cost:5500,potential:9000,weighted:5400,gp:2500,margin:31.25});assert.equal(M.forecast([],'USD').margin,0);
});
test('active application counts do not include placed, rejected or withdrawn records',()=>{
 const d={clients:[],roles:[],applications:['submitted','offer','placed','rejected','withdrawn'].map(status=>({status}))};assert.equal(M.metrics(d).applications,2);assert.equal(M.metrics(d).placed,1);
});
test('action queue prioritizes linking and ownership without duplicating aging items',()=>{
 const now=Date.parse('2026-10-27'),old='2026-09-01';const d={roles:[{id:'1',status:'new',created_at:old},{id:'2',client_id:'c',status:'qualified',created_at:old},{id:'3',client_id:'c',status:'qualified',assigned_to:'owner@example.com',created_at:old},{id:'4',status:'closed',created_at:old}],members:[],clients:[],applications:[]};
 assert.deepEqual(M.actions(d,now).map(t=>t.kind),['Link client','Assign owner','Review aging role']);
});
test('readAll honors smaller server row caps and does not silently truncate',async()=>{
 const seen=[];const rows=await readAll(async path=>{const o=Number(new URL('https://example.com/'+path).searchParams.get('offset'));seen.push(o);return {ok:true,json:async()=>o<4?[o,o+1]:[o],headers:{get:()=>o+'-'+Math.min(o+1,4)+'/5'}};},'roles?order=id');assert.deepEqual(rows,[0,1,2,3,4]);assert.deepEqual(seen,[0,2,4]);
});
test('failed reads and incomplete pagination cannot become valid zero totals',async()=>{
 await assert.rejects(readAll(async()=>({ok:false}),'roles'),/Could not load/);
 await assert.rejects(readAll(async()=>({ok:true,json:async()=>[],headers:{get:()=>'*\/5'}}),'roles'),/Data changed/);
});
