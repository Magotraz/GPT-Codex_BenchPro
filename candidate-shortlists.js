/* Compatibility for an older cached candidate page. Approval actions are retired. */
(function(){
  document.querySelector('[data-view="introductions"]')?.remove();
  window.CandidateShortlists={load:async()=>{},open:()=>location.assign('candidate.html?view=applications'),reset(){}};
})();
