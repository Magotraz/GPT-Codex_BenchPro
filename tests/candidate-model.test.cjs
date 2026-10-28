const test=require('node:test'),assert=require('node:assert/strict'),M=require('../candidate-model');
test('readiness follows actual required application fields, not optional enrichment',()=>{
 assert.equal(M.readiness(null).filter(x=>x.done).length,0);
 const p={full_name:'Test Person',primary_role:'Engineer',country_or_timezone:'India',skills:['SQL'],resume_file_path:'private/path'};
 assert.equal(M.readiness(p).filter(x=>x.done).length,5);
 assert.equal(M.readiness({...p,resume_file_path:null}).find(x=>x.field==='resume_file').done,false);
});
test('ranking explains exact shared skills and does not invent semantic matches',()=>{
 const a={id:'a',skills:['Java'],featured:true},b={id:'b',skills:['sql'],featured:false};
 assert.deepEqual(M.rank([a,b],{skills:['SQL']}),[b,a]);
 assert.deepEqual(M.sharedSkills(a,{skills:['JavaScript']}),[]);
 assert.deepEqual(M.sharedSkills(b,{skills:[' SQL ']}),['sql']);
});
test('search includes skills and combines category and work mode',()=>{
 const p={title:'Data Engineer',skills:['Snowflake'],category:'Data & AI',work_mode:'Remote'};
 assert.equal(M.matches(p,{q:'snowflake',category:'Data & AI',mode:'Remote'}),true);
 assert.equal(M.matches(p,{q:'snowflake',mode:'Hybrid'}),false);
});
test('placement is not represented as completed onboarding; past stages are not active',()=>{
 assert.equal(M.stages.placed[0],'Placement confirmed');
 for(const status of ['placed','withdrawn','closed','rejected'])assert.equal(M.active.includes(status),false);
 for(const status of M.active)assert.ok(M.stages[status]);
});
