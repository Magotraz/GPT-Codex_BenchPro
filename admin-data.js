(function(root){
  async function readAll(request,path){
    const rows=[];let offset=0;
    // Use Content-Range rather than assuming the project's row cap is 1,000.
    while(true){
      const params=new URLSearchParams(path.split('?')[1]||'');params.set('limit','500');params.set('offset',String(offset));
      const response=await request(path.split('?')[0]+'?'+params,{headers:{Prefer:'count=exact'}});
      if(!response.ok)throw new Error('Could not load '+path.split('?')[0]+'. Refresh or check staff access.');
      const page=await response.json();if(!Array.isArray(page))throw new Error('Invalid data response.');
      rows.push(...page);offset+=page.length;
      const range=response.headers.get('content-range'),total=range&&range.split('/')[1]!=='*'?Number(range.split('/')[1]):null;
      if(total!==null&&Number.isFinite(total)&&offset>=total)return rows;
      if(!page.length){if(total!==null&&offset<total)throw new Error('Data changed during loading. Please refresh.');return rows;}
      if(offset>100000)throw new Error('This dataset needs a server-side report. Totals have not been displayed.');
    }
  }
  if(typeof module==='object'&&module.exports)module.exports={readAll};else root.BenchProAdminData={readAll};
})(typeof window!=='undefined'?window:globalThis);
