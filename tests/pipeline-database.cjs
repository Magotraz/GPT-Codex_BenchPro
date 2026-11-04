// Isolated PostgreSQL-compatible engine. No production connection or records.
// Requires @electric-sql/pglite in the external QA toolchain (NODE_PATH).
const {PGlite}=require('@electric-sql/pglite'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
async function database(){
  const db=new PGlite();await db.waitReady;
  await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
    create schema auth;create schema storage;
    create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}');
    create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
    create function auth.uid() returns uuid language sql stable as $$select nullif(auth.jwt()->>'sub','')::uuid$$;
    create function auth.role() returns text language sql stable as $$select auth.jwt()->>'role'$$;
    grant usage on schema auth,storage,public to anon,authenticated,service_role;
    create table storage.buckets(id text primary key,name text,public boolean default false,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid default gen_random_uuid() primary key,bucket_id text references storage.buckets(id),name text,metadata jsonb,owner uuid,unique(bucket_id,name));
    alter table storage.objects enable row level security;
    grant select,insert,update,delete on storage.objects to authenticated;grant all on all tables in schema storage to service_role;
    create function storage.foldername(name text) returns text[] language sql immutable as $$select (string_to_array(name,'/'))[1:array_length(string_to_array(name,'/'),1)-1]$$;
    create function storage.filename(name text) returns text language sql immutable as $$select (string_to_array(name,'/'))[array_length(string_to_array(name,'/'),1)]$$;
  `);
  for(const file of fs.readdirSync(path.join(root,'supabase/migrations')).filter(f=>f.endsWith('.sql')).sort()){
    const sql=fs.readFileSync(path.join(root,'supabase/migrations',file),'utf8');try{await db.exec(sql)}catch(e){console.error('Migration failed:',file,e.message,sql.slice(Math.max(0,Number(e.position)-150),Number(e.position)+150));throw e}
  }
  return db;
}
if(require.main===module)(async()=>{const db=await database();try{for(const file of ['shortlists-rls.sql','pipeline-rls.sql']){if(!fs.existsSync(path.join(__dirname,file)))continue;const result=await db.exec(fs.readFileSync(path.join(__dirname,file),'utf8'));console.log(file,JSON.stringify(result.flatMap(r=>r.rows||[]).filter(r=>r.result)))}}finally{await db.close()}})().catch(e=>{console.error(e.message,e.where||'',e.detail||'');process.exitCode=1});
module.exports={database};
