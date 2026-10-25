// Run with: node --test tests/client-model.test.cjs
const test = require('node:test');
const assert = require('node:assert/strict');
const M = require('../client-model.js');
const roles = [
  {id:'1',role_or_skills:'Data Engineer',status:'new',client_assignee_membership_id:'super',created_at:'2026-10-24',target_start_date:'2026-11-01'},
  {id:'2',role_or_skills:'Cloud Architect',status:'qualified',client_assignee_membership_id:'team',created_at:'2026-10-23',target_start_date:'2026-12-01'},
  {id:'3',role_or_skills:'QA Engineer',status:'new',client_assignee_membership_id:null,created_at:'2026-10-22'},
  {id:'4',role_or_skills:'DevOps',status:'closed',client_assignee_membership_id:'team',created_at:'2026-09-20',target_start_date:'2026-10-29'}
];
test('member overview and search never include another owner or unassigned roles',()=>{
  const visible=M.visibleRoles(roles,{id:'team',role:'recruiter',status:'active'});
  assert.deepEqual(visible.map(r=>r.id),['2','4']);
  assert.deepEqual(M.counts(visible),{total:2,open:1,review:0,unassigned:0,closed:1});
  assert.deepEqual(M.filterRoles(visible,[],{search:'Data Engineer'}),[]);
  assert.deepEqual(M.visibleRoles(roles,null),[]);
  assert.deepEqual(M.visibleRoles(roles,{id:'team',role:'recruiter',status:'removed'}),[]);
  assert.deepEqual(M.visibleRoles(roles,{id:'super',role:'superuser',status:'removed'}),[]);
});
test('superuser and staff retain company-wide visibility',()=>{
  assert.equal(M.visibleRoles(roles,{id:'super',role:'superuser',status:'active'}).length,4);
  assert.equal(M.visibleRoles(roles,null,true).length,4);
});
test('search, owner, and status filters combine; sort puts missing dates last',()=>{
  const members=[{id:'team',email:'priya@example.com'}];
  assert.deepEqual(M.filterRoles(roles,members,{filter:'current',owner:'team',search:'PRIYA',sort:'newest'}).map(r=>r.id),['2']);
  assert.deepEqual(M.filterRoles(roles,members,{filter:'current',owner:'unassigned'}).map(r=>r.id),['3']);
  assert.deepEqual(M.filterRoles(roles,members,{sort:'start'}).map(r=>r.id),['4','1','2','3']);
  assert.deepEqual(M.filterRoles(roles,members,{sort:'title'}).map(r=>r.id),['2','1','4','3']);
});
test('target-date reminders exclude closed and past roles; include fourteen-day boundary',()=>{
  assert.deepEqual(M.upcoming(roles,new Date('2026-10-25T12:00:00')).map(r=>r.id),['1']);
  assert.equal(M.upcoming([{status:'new',target_start_date:'2026-11-08'}],new Date('2026-10-25T12:00:00')).length,1);
  assert.equal(M.upcoming([{status:'new',target_start_date:'2026-10-24'}],new Date('2026-10-25T12:00:00')).length,0);
});
