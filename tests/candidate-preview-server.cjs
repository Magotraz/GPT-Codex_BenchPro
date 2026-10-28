// Isolated local preview. No credentials, production writes or synthetic database records.
const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
const fixture=`<script>
(()=>{
const mode=new URLSearchParams(location.search).get('fixture')||'populated';
sessionStorage.setItem('benchpro_candidate_session',JSON.stringify({access_token:'local-preview',refresh_token:'local-preview',expires_at:Date.now()/1000+3600,user:{id:'00000000-0000-4000-8000-000000000901',email:'benchpro-demo+preview@example.com',user_metadata:{full_name:'Alex Morgan'}}}));
const sampleProfile={id:'00000000-0000-4000-8000-000000000902',user_id:'00000000-0000-4000-8000-000000000901',full_name:'Alex Morgan',primary_role:'Senior Data Engineer',skills:['Python','SQL','Snowflake','AWS'],years_experience:8,country_or_timezone:'India',availability:'within_2_weeks',available_from:'2026-11-10',profile_summary:'Data engineer building reliable cloud platforms and analytics pipelines.',resume_file_path:'private/preview.pdf',resume_file_name:'Alex_Morgan_Resume.pdf'};
const listings=[['Senior Data Engineer','Data & AI',['Python','SQL','Snowflake'],'Remote','India · US overlap','6 months'],['Cloud Platform Engineer','Cloud & platform',['AWS','Terraform','Kubernetes'],'Remote','India','12 months'],['Salesforce Solution Architect','Enterprise platforms',['Salesforce','Apex'],'Hybrid','Bengaluru, India','6 months'],['Full Stack Engineer','Engineering',['React','Node.js'],'Remote','Europe overlap','3 months']].map((a,i)=>({id:'00000000-0000-4000-8000-00000000091'+i,title:a[0],category:a[1],skills:a[2],work_mode:a[3],location:a[4],duration:a[5],experience:'5–8 years',summary:'Help a growing technology team deliver reliable systems and meaningful project outcomes.',description:'Work with an experienced team on a clearly scoped technology project.',requirements:['Relevant project experience'],responsibilities:['Deliver project milestones'],client_display_name:['Northstar Analytics','Meridian Cloud','Summit Digital','Orbit Commerce'][i],status:'published',is_demo:false,featured:i===0,published_at:'2026-10-27T10:00:00Z'}));
let state=JSON.parse(sessionStorage.getItem('candidate-preview-state')||'null')||{profile:mode==='new'?null:sampleProfile,saved:[{project_id:listings[1].id,created_at:'2026-10-26T12:00:00Z'}],applications:[{id:'00000000-0000-4000-8000-000000000921',project_id:listings[0].id,candidate_id:sampleProfile.id,status:'reviewing',created_at:'2026-10-24T10:00:00Z',updated_at:'2026-10-26T12:00:00Z',project_listings:listings[0]},{id:'00000000-0000-4000-8000-000000000922',project_id:listings[2].id,candidate_id:sampleProfile.id,status:'submitted',created_at:'2026-10-25T10:00:00Z',updated_at:'2026-10-25T10:00:00Z',project_listings:listings[2]}]};
if(mode==='empty'||mode==='new'){state.saved=[];state.applications=[]}
const persist=()=>sessionStorage.setItem('candidate-preview-state',JSON.stringify(state));
window.fetch=async(url,options={})=>{
 const u=new URL(url,location.href),table=u.pathname.split('/').pop(),method=options.method||'GET',body=options.body&&typeof options.body==='string'?JSON.parse(options.body):{},id=(u.searchParams.get('id')||'').replace('eq.',''),pid=(u.searchParams.get('project_id')||'').replace('eq.','');
 if(!u.hostname.endsWith('supabase.co'))throw new Error('Network disabled in isolated preview');
 const response=(x,status=200)=>new Response(JSON.stringify(x),{status,headers:{'Content-Type':'application/json'}});
 if(mode==='error'&&table!=='candidate_accounts')return response({},503);
 if(u.pathname.includes('/storage/'))return response({},403);
 if(table==='candidate_accounts'&&method!=='GET'){state.profile={...state.profile,...body};persist();return response([state.profile])}
 if(table==='candidate_saved_projects'&&method==='POST'){state.saved.push({...body,created_at:new Date().toISOString()});persist();return response([state.saved.at(-1)])}
 if(table==='candidate_saved_projects'&&method==='DELETE'){state.saved=state.saved.filter(s=>s.project_id!==pid);persist();return response(null)}
 if(table==='project_applications'&&method==='PATCH'){const a=state.applications.find(a=>a.id===id);Object.assign(a,body,{updated_at:new Date().toISOString()});persist();return response([a])}
 if(table==='project_applications'&&method==='POST'){const a={...body,id:'00000000-0000-4000-8000-000000000923',status:'submitted',created_at:new Date().toISOString(),project_listings:listings.find(p=>p.id===body.project_id)};state.applications.push(a);persist();return response([a])}
 let rows=table==='candidate_accounts'?(state.profile?[state.profile]:[]):table==='project_listings'?(mode==='empty'||mode==='new'?[]:listings):table==='project_applications'?state.applications:table==='candidate_saved_projects'?state.saved:[];
 if(id)rows=rows.filter(r=>r.id===id);if(pid)rows=rows.filter(r=>r.project_id===pid);
 const offset=Number(u.searchParams.get('offset')||0),limit=Number(u.searchParams.get('limit')||200);return response(rows.slice(offset,offset+limit));
};
})();
</script>`;
const server=http.createServer((req,res)=>{
 const url=new URL(req.url,'http://127.0.0.1'),name=path.resolve(root,'.'+decodeURIComponent(url.pathname==='/'?'/candidate.html':url.pathname));
 if(!name.startsWith(root+path.sep)){res.writeHead(403);return res.end()}
 try{let content=fs.readFileSync(name);const ext=path.extname(name);if(ext==='.html'){content=content.toString().replace('<head>','<head>'+fixture).replace(/<script src="https:\/\/cdn.jsdelivr.net[^>]+><\/script>/g,'');content=content.replace('<body','<body');content=content.replace(/(<body[^>]*>)/,'$1<div style="background:#fff1c2;color:#5d512b;padding:8px;text-align:center;font:12px Arial">Isolated design preview · sample data · no production changes</div>')}
 res.writeHead(200,{'Cache-Control':'no-store','Content-Type':({'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.png':'image/png','.svg':'image/svg+xml'})[ext]||'application/octet-stream'});res.end(content)}catch{res.writeHead(404);res.end('Not found')}
});
if(require.main===module)server.listen(4180,'127.0.0.1',()=>console.log('Candidate preview: http://127.0.0.1:4180/candidate.html'));
module.exports=server;
