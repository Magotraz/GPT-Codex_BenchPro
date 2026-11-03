/* Candidate profile enhancements. Drafts stay in this tab until explicitly saved. */
(function(){
  'use strict';
  const $=id=>document.getElementById(id),form=$('profileForm'),M=window.CandidateModel,E=window.ProjectsModel.esc;
  let saved=null,baseline='',dirty=false;
  const snapshot=()=>JSON.stringify([...new FormData(form)].filter(([k])=>k!=='resume_file'));
  function draft(){const data=Object.fromEntries(new FormData(form));return {...saved,...data,skills:String(data.skills||'').split(',').map(s=>s.trim()).filter(Boolean),resume_file_path:$('resumeFile').files.length?'pending-upload':saved?.resume_file_path}}
  function render(){const p=draft(),checks=M.completeness(p),done=checks.filter(x=>x.done).length,percent=Math.round(done/checks.length*100),essentials=M.readiness(p).filter(x=>x.done).length;
    $('cwProfileProgress').innerHTML=`<div class="cw-section-heading"><div><span class="cw-eyebrow">BUILD A STRONGER PROFILE</span><h2>${percent}% complete</h2></div><span class="cw-caption">${essentials}/5 application essentials</span></div><div class="cw-progress-track" role="progressbar" aria-label="Profile completeness" aria-valuenow="${percent}" aria-valuemin="0" aria-valuemax="100"><div style="width:${percent}%"></div></div><div class="cw-profile-checks">${checks.map(c=>`<button type="button" class="${c.done?'complete':''}" data-field="${c.field}">${c.done?'✓':'+'} ${E(c.label)}</button>`).join('')}</div><p class="cw-caption">${dirty?'Previewing your unsaved changes. ':''}Preferences and experience add context; only the five application essentials are required to apply. This is not a screening score.</p>`;
  }
  function changed(){dirty=snapshot()!==baseline||!!$('resumeFile').files.length;$('cwUnsaved').hidden=!dirty;render()}
  window.addEventListener('candidate-profile-changed',e=>{saved=e.detail;baseline=snapshot();dirty=false;$('cwUnsaved').hidden=true;clearErrors();render()});
  form.addEventListener('input',changed);form.addEventListener('change',changed);
  window.addEventListener('beforeunload',e=>{if(dirty){e.preventDefault();e.returnValue=''}});
  function clearErrors(){form.querySelectorAll('.cw-field-error').forEach(n=>n.remove());for(const input of form.elements){input.removeAttribute('aria-invalid');input.removeAttribute('aria-describedby');if(input.setCustomValidity)input.setCustomValidity('')}}
  form.addEventListener('submit',e=>{
    clearErrors();
    for(const key of ['full_name','primary_role']){const input=form.elements[key];if(input.value.trim().length<2)input.setCustomValidity('Please enter at least two characters.')}
    const phone=form.elements.phone_number;if(phone.value.trim()&&phone.value.trim().length<7)phone.setCustomValidity('Include your country code and phone number (at least 7 characters).');
    for(const key of ['linkedin_url','portfolio_url']){const input=form.elements[key];if(input.value.trim()&&!/^https?:\/\//i.test(input.value.trim()))input.setCustomValidity('Enter a link starting with https:// or http://.')}
    const skills=form.elements.skills;if(skills.value.split(',').filter(s=>s.trim()).length>30)skills.setCustomValidity('Add up to 30 skills, separated by commas.');
    let first=null;
    for(const input of form.elements){if(input.willValidate&&!input.validity.valid){const note=document.createElement('span');note.className='cw-field-error';note.id='error-'+input.name;note.textContent=input.validationMessage;input.setAttribute('aria-invalid','true');input.setAttribute('aria-describedby',note.id);input.insertAdjacentElement('afterend',note);first=first||input}}
    if(first){e.preventDefault();e.stopImmediatePropagation();first.focus();first.scrollIntoView({block:'center'});$('saveFeedback').textContent='Please check the highlighted fields.'}
  },true);
  form.addEventListener('input',e=>{const input=e.target;if(input.setCustomValidity)input.setCustomValidity('');const note=$('error-'+input.name);if(note){note.remove();input.removeAttribute('aria-invalid');input.removeAttribute('aria-describedby')}});
  $('cwPreviewProfile').onclick=()=>{const p=draft(),value=v=>E(String(v||'Not added yet'));
    $('cwProfilePreviewBody').innerHTML=`<article class="cw-profile-preview"><h3>${value(p.full_name)}</h3><p>${value(p.primary_role)} · ${value(p.country_or_timezone)}</p><div class="cw-tags">${p.skills.map(s=>`<span>${E(s)}</span>`).join('')}</div><p class="cw-preserve">${value(p.profile_summary)}</p><dl class="cw-detail-grid"><div><dt>Experience</dt><dd>${p.years_experience!==''&&p.years_experience!=null?E(p.years_experience)+' years':'Not added yet'}</dd></div><div><dt>Availability</dt><dd>${value(window.ProjectsModel.availability[p.availability])}</dd></div><div><dt>Work arrangement</dt><dd>${value(p.preferred_work_mode)}</dd></div><div><dt>Preferred location</dt><dd>${value(p.preferred_location)}</dd></div><div><dt>Weekly availability</dt><dd>${p.weekly_hours?E(p.weekly_hours)+' hours':'Not added yet'}</dd></div><div><dt>Resume</dt><dd>${value($('resumeFile').files[0]?.name||p.resume_file_name)}</dd></div></dl></article>`;
    $('cwProfilePreview').showModal();
  };
})();
