// Usage: node tests/operational-demo.browser.cjs <exported-demo-fixtures.json>
// Read-only fixtures must contain only demo rows; the browser makes no production requests.
const {chromium}=require('playwright'),fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const fixtures=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const root=path.resolve(__dirname,'..'),out=path.resolve(__dirname,'../../demo-qa');fs.mkdirSync(out,{recursive:true});
const errors=[],calls=[];
const server=http.createServer((req,res)=>{const file=path.resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://127.0.0.1').pathname));if(!file.startsWith(root+path.sep)){res.writeHead(403);return res.end()}
 try{let body=fs.readFileSync(file);if(file.endsWith('.html'))body=body.toString().replace(/<script src="https:\/\/cdn.jsdelivr.net[^>]+><\/script>/g,'');res.writeHead(200,{'Content-Type':file.endsWith('.html')?'text/html':file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':'application/octet-stream'});res.end(body)}catch{res.writeHead(404);res.end()}});
(async()=>{
 await new Promise(resolve=>server.listen(4188,'127.0.0.1',resolve));const browser=await chromium.launch({channel:'chrome',headless:true});
 const page=await browser.newPage({viewport:{width:1440,height:1000}});page.on('pageerror',e=>errors.push(e.message));
 await page.addInitScript(()=>{const s=JSON.stringify({access_token:'fixture-staff',refresh_token:'fixture-only',expires_at:Date.now()/1000+3600,user:{id:'00000000-0000-4000-8000-000000000001',email:'admin@benchpro.in',user_metadata:{full_name:'Test Admin'}}});sessionStorage.setItem('benchpro_staff_session',s);});
 await page.route('**/*',async route=>{const req=route.request(),u=new URL(req.url());if(u.hostname==='127.0.0.1')return route.continue();if(!u.hostname.endsWith('supabase.co'))return route.fulfill({status:200,body:''});
  const table=u.pathname.split('/').pop();calls.push(u.pathname+u.search);let rows;
  if(table==='is_benchpro_staff_account')return route.fulfill({json:true});
  if(table==='shortlist_action')return route.fulfill({json:{can_publish:true}});
  if(table==='client-access'){const cid=req.postDataJSON().client_id;return route.fulfill({json:{ok:true,client:fixtures.clients.find(c=>c.id===cid),memberships:fixtures.client_memberships.filter(m=>m.client_id===cid),domains:fixtures.client_email_domains.filter(d=>d.client_id===cid),roles:fixtures.staffing_requests.filter(r=>r.client_id===cid)}})}
  if(table==='user')return route.fulfill({json:{id:'00000000-0000-4000-8000-000000000001',email:'admin@benchpro.in'}});
  rows=(fixtures[table]||[]).filter(r=>[...u.searchParams].every(([k,v])=>v.startsWith('eq.')?String(r[k])===v.slice(3):v==='is.null'?r[k]==null:true));
  if(table==='project_applications')rows=rows.map(a=>({...a,candidate_accounts:fixtures.candidate_accounts.find(c=>c.id===a.candidate_id),shortlist_reviews:fixtures.shortlist_reviews.filter(r=>r.application_id===a.id).map(r=>({id:r.id}))}));
  const offset=Number(u.searchParams.get('offset')||0),limit=Number(u.searchParams.get('limit')||1000),total=rows.length;rows=rows.slice(offset,offset+limit);
  return route.fulfill({json:rows,headers:{'content-range':rows.length?`${offset}-${offset+rows.length-1}/${total}`:`*/${total}`}});
 });
 try{
  await page.goto('http://127.0.0.1:4188/admin.html?data=test');await page.getByText('Test dataset · saved records',{exact:true}).waitFor();await page.locator('[data-page=talent]').click();await page.getByText('Aditi Rao',{exact:true}).waitFor();
  assert.equal(await page.locator('#admin-content tbody tr').count(),20);assert.match(await page.locator('#admin-content a').first().getAttribute('href'),/data=test/);await page.screenshot({path:path.join(out,'admin-talent.png')});
  await page.locator('#admin-talent-tab').selectOption('applications');assert.equal(await page.locator('#admin-content tbody tr').count(),30);
  await page.locator('[data-page=contacts]').click();assert.equal(await page.locator('.admin-team-grid > *').count(),6);
  await page.locator('[data-page=clients]').click();await page.locator('#admin-client-panel .client-toggle').filter({hasText:'Meridian Cloud Services'}).click();await page.getByRole('link',{name:'Manage portal access'}).waitFor();
  const cid=fixtures.clients.find(c=>c.company_name.includes('Meridian')).id;
  await page.goto('http://127.0.0.1:4188/client.html?manage='+cid+'&tab=shortlists');await page.locator('[data-submission]').first().waitFor();assert.equal(await page.locator('[data-submission]').count(),2);
  await page.locator('[data-submission]').first().click();await page.locator('#csBody .sl-fit-rating').waitFor();assert.equal(await page.locator('#csFeedback').count(),0);await page.screenshot({path:path.join(out,'client-profile.png')});
  await page.goto('http://127.0.0.1:4188/recruiting.html?data=test');await page.locator('[data-review]').first().waitFor();assert.equal(await page.locator('[data-review]').count(),12);await page.getByRole('tab',{name:'Incoming applications',exact:true}).click();assert.equal(await page.locator('#slRows .sl-row').count(),30);
  await page.locator('#slNew').click();assert.equal(await page.locator('#slCreateForm [name=candidate_id] option').count(),21);assert.equal(await page.locator('#slCreateForm [name=staffing_request_id] option').count(),1+fixtures.staffing_requests.filter(r=>r.client_id&&r.status!=='closed').length);await page.locator('[data-close]').first().click();await page.screenshot({path:path.join(out,'recruiting-applications.png')});
  await page.setViewportSize({width:390,height:844});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));await page.screenshot({path:path.join(out,'recruiting-mobile.png')});await page.setViewportSize({width:1440,height:1000});
  await page.goto('http://127.0.0.1:4188/publishing.html?data=test');await page.locator('#publishingWorkspace:visible').waitFor();assert.equal(await page.locator('#listings button').count(),10);await page.locator('#listings button').first().click();await page.locator('.publishing-applicant').first().waitFor();assert.equal(await page.locator('button[data-action=published]').isVisible(),false);assert.equal(await page.locator('#viewListing').isVisible(),false);await page.screenshot({path:path.join(out,'test-projects.png')});
  await page.goto('http://127.0.0.1:4188/admin.html');await page.getByText('Live operating data',{exact:true}).waitFor();await page.locator('[data-page=talent]').click();await page.getByText('No profiles match this search.',{exact:true}).waitFor();assert.equal(await page.locator('#admin-content tbody tr').count(),0);
  assert.ok(calls.some(p=>p.includes('candidate_accounts?')&&p.includes('is_demo=eq.true')));assert.deepEqual(errors,[]);
  console.log('PASS: demo admin 20 profiles / 30 applications / 6 teams; 10 projects; 12 submissions; client view excludes withdrawn profile; demo mode navigation and mobile layout; live totals exclude mocks.');
 }catch(e){await page.screenshot({path:path.join(out,'failure.png')});console.error('PAGE ERRORS',errors);console.error('ALERTS',await page.locator('[role=alert]').allTextContents());throw e}finally{await browser.close();server.close()}
})().catch(e=>{console.error(e);server.close();process.exitCode=1});
