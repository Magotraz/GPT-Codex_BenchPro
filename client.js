/* BenchPro client workspace. All data access uses the signed-in user's token. */
(() => {
  'use strict';
  const SUPABASE_URL = 'https://ttmkcmeqiawrzbvymhal.supabase.co';
  const KEY = 'sb_publishable_kYY2o5gsLpUww-bgH0az4A_nQhdMiaN';
  const CLIENT_KEY = 'benchpro_candidate_session', STAFF_KEY = 'benchpro_staff_session';
  const params = new URLSearchParams(location.search), managementId = params.get('manage');
  const $ = id => document.getElementById(id), M = window.BenchProClientModel;
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  let session = null, client = null, actorMembership = null, members = [], roles = [], domains = [];
  let isStaffMode = !!managementId, loaded = false, refreshPromise = null, workspaceLoad = null, detailId = null;
  const state = { tab: params.get('tab') || 'overview', filter: params.get('filter') || 'all',
    search: params.get('q') || '', owner: params.get('owner') || 'all', sort: params.get('sort') || 'newest', page: 1 };
  if (!['all', 'current', 'new', 'closed'].includes(state.filter)) state.filter = 'all';
  if (!['newest', 'oldest', 'start', 'title'].includes(state.sort)) state.sort = 'newest';
  const PAGE_SIZE = 8;
  const canManage = () => loaded && (isStaffMode || actorMembership?.role === 'superuser');
  const canAssign = () => loaded && !isStaffMode && actorMembership?.role === 'superuser';
  const iconPaths = {
    overview: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
    roles: '<rect x="3" y="7" width="18" height="14" rx="2"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 12a20 20 0 0 0 18 0M10 12v3h4v-3"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    team: '<circle cx="9" cy="8" r="3"/><path d="M3 21v-2a6 6 0 0 1 12 0v2M16 5a3 3 0 0 1 0 6M18 15a5 5 0 0 1 3 4v2"/>',
    help: '<circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 1 1 4 2c-1.2.8-1.5 1.2-1.5 2.5M12 17h.01"/>',
    spark: '<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5L12 3ZM20 2v4M18 4h4"/>',
    search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
    chart: '<path d="M4 3v17h17M9 15V9M14 15V5M19 15v-4"/>',
    shield: '<path d="m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6l8-3Z"/><path d="m8 12 3 3 5-6"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 10h18M8 14h3M8 17h7"/>',
    upload: '<path d="M12 16V3m-5 5 5-5 5 5M4 15v5a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-5"/>',
    document: '<path d="M14 2H5v20h14V7l-5-5ZM14 2v6h5M8 12h8M8 16h6"/>',
    logout: '<path d="M9 4H4v16h5M9 12h12m-4-4 4 4-4 4"/>',
    menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
    right: '<path d="m9 5 7 7-7 7"/>', left: '<path d="m15 5-7 7 7 7"/>',
    close: '<path d="m6 6 12 12M6 18 18 6"/>',
    mail: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 6 9 7 9-7"/>',
    edit: '<path d="m15 4 5 5M4 20l5-1L21 7a2 2 0 0 0-5-5L4 15l-1 6Z"/>'
  };
  const icon = name => `<svg viewBox="0 0 24 24" aria-hidden="true">${iconPaths[name] || iconPaths.roles}</svg>`;
  document.querySelectorAll('[data-icon]').forEach(node => { node.innerHTML = icon(node.dataset.icon); });
  const badge = status => `<span class="badge ${esc(M.statuses[status]?.color || 'closed')}">${esc(M.statuses[status]?.label || status || 'Not set')}</span>`;
  const memberBadge = status => `<span class="badge ${esc(status)}">${esc({ active: 'Active', invited: 'Invited', removed: 'Removed' }[status] || status)}</span>`;
  const ownerOf = role => members.find(member => member.id === role.client_assignee_membership_id);
  const reference = role => 'BP–' + String(role.id).slice(0, 8).toUpperCase();
  function fmtDate(value) {
    if (!value) return 'Not set';
    const date = new Date(/^\d{4}-\d{2}-\d{2}$/.test(value) ? value + 'T00:00:00' : value);
    return Number.isNaN(date.getTime()) ? 'Not set' : date.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
  }
  function greetingName() {
    const metadata = session?.user?.user_metadata || {};
    const value = metadata.first_name || metadata.given_name || metadata.full_name || metadata.name || session?.user?.email?.split('@')[0] || 'there';
    const first = String(value).trim().split(/[\s._+-]+/)[0] || 'there';
    return first.charAt(0).toLocaleUpperCase() + first.slice(1);
  }
  function feedback(node, message, error = false) {
    node.textContent = message; node.hidden = !message; node.classList.toggle('error', error);
  }
  const showError = message => feedback($('pageFeedback'), message || 'Something went wrong. Please try again.', true);
  function saveSession(value) { sessionStorage.setItem(managementId ? STAFF_KEY : CLIENT_KEY, JSON.stringify(value)); }
  function getSession() { try { return JSON.parse(sessionStorage.getItem(managementId ? STAFF_KEY : CLIENT_KEY) || 'null'); } catch { return null; } }
  function auth(path, payload, token) {
    return fetch(SUPABASE_URL + '/auth/v1/' + path, { method: 'POST', headers: { apikey: KEY, Authorization: 'Bearer ' + (token || KEY), 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
  }
  async function readResponse(response, fallback) {
    const data = (await response.json().catch(() => ({}))) ?? {};
    if (!response.ok || data.error) throw new Error(data.message || data.msg || data.error_description || data.error || fallback);
    return data;
  }
  async function accessToken() {
    if (!session?.refresh_token) throw new Error('Please sign in again.');
    if (session.expires_at > Date.now() / 1000 + 60) return session.access_token;
    // Concurrent workspace requests share one refresh to avoid rotating-token races.
    if (!refreshPromise) refreshPromise = (async () => {
      const response = await auth('token?grant_type=refresh_token', { refresh_token: session.refresh_token });
      if (!response.ok) throw new Error('Your session expired. Sign in again.');
      session = await response.json(); session.expires_at ||= Math.floor(Date.now() / 1000) + (session.expires_in || 3600);
      saveSession(session); return session.access_token;
    })().finally(() => { refreshPromise = null; });
    return refreshPromise;
  }
  async function api(path, options = {}) {
    const token = await accessToken();
    return fetch(SUPABASE_URL + '/rest/v1/' + path, { ...options, headers: { apikey: KEY, Authorization: 'Bearer ' + token, 'Content-Type': 'application/json', ...(options.headers || {}) } });
  }
  async function callAccess(action, values = {}, targetClientId = client?.id) {
    if (!targetClientId) throw new Error('Choose a valid client.');
    const token = await accessToken();
    return readResponse(await fetch(SUPABASE_URL + '/functions/v1/client-access', { method: 'POST', headers: { apikey: KEY, Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }, body: JSON.stringify({ action, client_id: targetClientId, ...values }) }), 'Could not update client access. Please try again.');
  }
  function showSignedIn() {
    $('passwordSetupView')?.remove(); $('authView').hidden = true; $('dashboard').hidden = false;
    document.body.classList.add('dashboard-mode');
    $('accountName').textContent = greetingName(); $('accountInitials').textContent = M.initials(greetingName());
    $('accountName').title = session?.user?.email || '';
  }
  function showSignedOut(message = '') {
    closeMenu(); $('passwordSetupView')?.remove(); $('dashboard').hidden = true; $('authView').hidden = false;
    document.body.classList.remove('dashboard-mode');
    document.querySelectorAll('dialog[open]').forEach(dialog => dialog.close());
    feedback($('authFeedback'), message, !!message);
  }
  function handleLoadError(error) {
    const message = error?.message || 'Could not load your workspace.';
    if (/session (?:is )?invalid|session expired|sign in again/i.test(message)) {
      sessionStorage.removeItem(managementId ? STAFF_KEY : CLIENT_KEY); session = null; showSignedOut(message); return;
    }
    showError(message + (loaded ? ' Your last loaded view is still shown.' : ' Use Refresh to try again.'));
  }
  function persistView() {
    const url = new URL(location.href);
    for (const [key, value, defaultValue] of [['tab', state.tab, 'overview'], ['filter', state.filter, 'all'], ['q', state.search, ''], ['owner', state.owner, 'all'], ['sort', state.sort, 'newest']]) {
      if (value === defaultValue) url.searchParams.delete(key); else url.searchParams.set(key, value);
    }
    history.replaceState(null, '', url.pathname + url.search + url.hash);
  }
  function setActiveTab(tab, focus = false) {
    if (!['overview', 'roles', 'post-role', 'team', 'help'].includes(tab) || (tab === 'team' && !canManage()) || (tab === 'post-role' && isStaffMode)) tab = 'overview';
    state.tab = tab;
    const copy = {
      overview: ['YOUR HIRING, AT A GLANCE', isStaffMode ? 'Client workspace' : 'Welcome, ' + greetingName(), canManage() ? 'A clear view of your roles, your team, and what’s next.' : 'Your assigned roles, key dates, and next steps.'],
      roles: ['FROM BRIEF TO DELIVERY', 'Your roles', canManage() ? 'Every role. Every owner. One clear view.' : 'The roles your superuser has assigned to you.'],
      'post-role': ['LET’S BUILD YOUR NEXT TEAM', 'Post a new role', 'Share your brief. We’ll take it from there.'],
      team: ['GREAT WORK STARTS WITH YOUR TEAM', 'Team access', 'Bring your colleagues together. Keep access in the right hands.'],
      help: ['WE’RE HERE TO HELP', 'Help & support', 'Find your way around your BenchPro workspace.']
    }[tab];
    $('pageEyebrow').textContent = copy[0]; $('title').textContent = copy[1]; $('pageDescription').textContent = copy[2];
    $('breadcrumb').textContent = { overview: 'Overview', roles: 'Roles', 'post-role': 'Post a role', team: 'Team access', help: 'Help & support' }[tab];
    document.querySelectorAll('[data-tab]').forEach(button => {
      if (button.dataset.tab === tab) button.setAttribute('aria-current', 'page'); else button.removeAttribute('aria-current');
    });
    document.querySelectorAll('[data-panel]').forEach(panel => { panel.hidden = panel.dataset.panel !== tab; });
    $('headerPostRole').hidden = !loaded || isStaffMode || tab === 'post-role';
    persistView(); closeMenu();
    if (focus) { $('mainContent').focus({ preventScroll: true }); window.scrollTo({ top: 0, behavior: 'instant' }); }
  }
  function openRoleList(filter = 'all', owner = 'all') {
    state.filter = filter; state.owner = owner; state.search = ''; state.page = 1;
    syncFilters(); renderRoles(); setActiveTab('roles', true);
  }
  function empty(title, message, action = '') {
    return `<div class="empty-state"><span class="empty-symbol">${icon('roles')}</span><h3>${esc(title)}</h3><p>${esc(message)}</p>${action}</div>`;
  }
  function renderOverview() {
    const count = M.counts(roles), upcoming = M.upcoming(roles);
    const tiles = [
      ['Open roles', count.open, 'All requests still in progress', 'roles', 'current', 'all'],
      ['Awaiting review', count.review, 'With the BenchPro team', 'clock', 'new', 'all'],
      canManage() ? ['Unassigned', count.unassigned, 'Open roles without an owner', 'team', 'current', 'unassigned'] : ['Your roles', count.total, 'Assigned to you', 'team', 'all', 'all'],
      ['Closed roles', count.closed, 'Your role request history', 'check', 'closed', 'all']
    ];
    $('metrics').innerHTML = tiles.map(([label, value, note, symbol, filter, owner]) => `<button class="metric" data-open-filter="${filter}" data-owner="${owner}"><span class="metric-label">${label}</span><span class="metric-icon">${icon(symbol)}</span><strong class="metric-value">${value}</strong><span class="metric-note">${note}</span></button>`).join('');
    const attention = [];
    if (canAssign() && count.unassigned) attention.push(['team', `${count.unassigned} open role${count.unassigned === 1 ? ' needs' : 's need'} an owner`, 'Give each request a clear point of contact.', 'Assign owner', 'data-open-filter="current" data-owner="unassigned"']);
    if (upcoming.length) attention.push(['calendar', `${upcoming.length} target start date${upcoming.length === 1 ? '' : 's'} coming up`, 'Review requests planned to start in the next 14 days.', 'Review roles', 'data-upcoming="true"']);
    const invited = canManage() ? members.filter(m => m.status === 'invited').length : 0;
    if (invited) attention.push(['mail', `${invited} team invitation${invited === 1 ? '' : 's'} pending`, 'Your colleagues haven’t joined the workspace yet.', 'View team', 'data-go-tab="team"']);
    $('attentionCount').textContent = attention.length;
    $('attentionList').innerHTML = attention.length ? attention.map(([symbol, title, note, label, action]) => `<div class="attention-row"><span class="attention-symbol">${icon(symbol)}</span><div class="attention-copy"><strong>${esc(title)}</strong><p>${esc(note)}</p></div><button class="text-button attention-action" ${action}>${label} <span aria-hidden="true">→</span></button></div>`).join('') : `<div class="attention-clear"><span class="attention-symbol">${icon('check')}</span><div><strong>You’re all caught up</strong><p>${roles.length ? 'No outstanding owner assignments or upcoming target dates to review.' : canManage() ? 'Post your first role to get your project hiring started.' : 'Your assigned roles will appear here when your superuser adds them.'}</p></div></div>`;
    const active = [...roles].filter(r => r.status !== 'closed').sort((a,b) => String(b.created_at).localeCompare(String(a.created_at))).slice(0, 5);
    $('activeRoles').innerHTML = active.length ? active.map(role => `<button class="active-role" data-open-role="${esc(role.id)}"><span class="role-symbol">${icon('roles')}</span><span class="active-role-copy"><strong class="active-role-name">${esc(role.role_or_skills)}</strong><span class="active-role-sub">${esc(role.project_duration || 'Duration to be confirmed')} · ${esc(ownerOf(role)?.email || 'Unassigned')}</span></span>${badge(role.status)}<span class="row-chevron">${icon('right')}</span></button>`).join('') : empty('Ready for your next project?', canManage() ? 'Your open role requests will appear here.' : 'No open roles are assigned to you yet.', !isStaffMode ? '<button class="text-button" data-go-tab="post-role">Post a role →</button>' : '');
    const knownStatuses = Object.keys(M.statuses);
    const pipelineStatuses = [...new Set([...knownStatuses, ...roles.map(r => r.status || 'unknown')])];
    $('pipelineScope').textContent = canManage() ? 'Across your company' : 'Only roles assigned to you';
    $('pipeline').innerHTML = `<div class="pipeline-total"><strong>${count.total}</strong><span>total role${count.total === 1 ? '' : 's'}</span></div><div class="pipeline-bar" aria-hidden="true">${pipelineStatuses.map(status => { const n = roles.filter(r => (r.status || 'unknown') === status).length; return n ? `<span class="pipeline-segment pipeline-${knownStatuses.includes(status) ? status : 'closed'}" style="flex:${n}"></span>` : ''; }).join('')}</div>${pipelineStatuses.map(status => `<div class="pipeline-row"><span class="pipeline-${knownStatuses.includes(status) ? status : 'closed'}"></span><span>${esc(M.statuses[status]?.label || status)}</span><strong>${roles.filter(r => (r.status || 'unknown') === status).length}</strong></div>`).join('')}`;
    $('recentActivity').innerHTML = roles.length ? [...roles].sort((a,b) => String(b.created_at).localeCompare(String(a.created_at))).slice(0,3).map(role => `<div class="activity-item"><span class="activity-marker">${icon('plus')}</span><div class="activity-content"><button class="text-button" data-open-role="${esc(role.id)}">${esc(role.role_or_skills)}</button><p>Submitted ${esc(fmtDate(role.created_at))}</p></div></div>`).join('') : '<p class="small">New role requests will appear here.</p>';
    $('scopeNote').textContent = canManage() ? 'Showing all roles for ' + client.company_name : 'Showing only roles assigned to you';
  }
  function syncFilters() {
    $('roleSearch').value = state.search; $('roleSort').value = state.sort;
    $('ownerFilter').innerHTML = '<option value="all">All owners</option><option value="unassigned">Unassigned</option>' + members.map(m => `<option value="${esc(m.id)}">${esc(m.email)}${m.status === 'removed' ? ' (removed)' : ''}</option>`).join('');
    if (!canManage()) state.owner = 'all';
    if (!['all','unassigned', ...members.map(m => m.id)].includes(state.owner)) state.owner = 'all';
    $('ownerFilter').value = state.owner; $('ownerFilter').hidden = !canManage();
  }
  function renderRoles() {
    const filtered = M.filterRoles(roles, members, state), pages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
    state.page = Math.min(state.page, pages);
    const start = (state.page - 1) * PAGE_SIZE, visible = filtered.slice(start, start + PAGE_SIZE);
    document.querySelectorAll('[data-role-filter]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.roleFilter === state.filter)));
    $('allRoleCount').textContent = roles.length;
    const rows = visible.map(role => {
      const owner = ownerOf(role);
      return `<tr><td><button class="role-link" data-open-role="${esc(role.id)}">${esc(role.role_or_skills)}</button><span class="role-reference">${esc(reference(role))} · ${esc(role.project_duration || 'Duration not set')}</span></td><td>${badge(role.status)}</td><td>${role.client_assignee_membership_id ? `<div class="owner-cell"><span class="avatar" aria-hidden="true">${esc(M.initials(owner?.email || 'Team member'))}</span><span class="owner-email" title="${esc(owner?.email || 'Team member')}">${canManage() ? esc(owner?.email || 'Team member') : 'Assigned to you'}</span></div>` : '<span class="unassigned">Unassigned</span>'}</td><td><span class="role-date">${esc(role.target_start_date ? fmtDate(role.target_start_date) : 'Start not set')}<small>Added ${esc(fmtDate(role.created_at))}</small></span></td><td><button class="icon-button" data-open-role="${esc(role.id)}" aria-label="Open ${esc(role.role_or_skills)}">${icon('right')}</button></td></tr>`;
    }).join('');
    $('roles').innerHTML = visible.length ? `<table class="role-table"><caption class="sr-only">Role requests visible to your account</caption><thead><tr><th scope="col">Role</th><th scope="col">Status</th><th scope="col">Owner</th><th scope="col">Target start</th><th scope="col"><span class="sr-only">Open role</span></th></tr></thead><tbody>${rows}</tbody></table>` : roles.length ? empty('No matching roles', 'Try another search, owner, or status.', '<button class="text-button" data-clear-filters>Clear filters →</button>') : empty(canManage() ? 'Your next hire starts here' : 'No assigned roles yet', canManage() ? 'Post a role and keep track of your requests in one place.' : 'Ask your client superuser to assign a role to you.', !isStaffMode ? '<button class="button" data-go-tab="post-role">Post a role</button>' : '');
    $('rolesResult').textContent = filtered.length ? `${start + 1}–${Math.min(start + PAGE_SIZE, filtered.length)} of ${filtered.length} roles` : '0 roles';
    $('pageNumber').textContent = `${state.page} / ${pages}`;
    $('previousPage').disabled = state.page === 1; $('nextPage').disabled = state.page >= pages;
  }
  function renderTeam() {
    // Do not place any team-management UI in the DOM for a team member.
    $('members').innerHTML = ''; $('domains').innerHTML = '';
    if (!canManage()) { $('inviteForm').hidden = true; return; }
    const active = members.filter(m => m.status === 'active').length, invited = members.filter(m => m.status === 'invited').length;
    $('teamSummary').textContent = `${active} active member${active === 1 ? '' : 's'} · ${invited} pending invitation${invited === 1 ? '' : 's'}`;
    $('inviteRoleField').hidden = !isStaffMode;
    if (!isStaffMode) $('inviteRole').value = 'recruiter';
    $('inviteHint').textContent = domains.length ? 'Approved company domains: ' + domains.map(d => '@' + d.domain).join(', ') : 'Ask BenchPro Admin to approve a company email domain before inviting teammates.';
    $('members').innerHTML = members.length ? [...members].sort((a,b) => ({active:0,invited:1,removed:2}[a.status] ?? 3) - ({active:0,invited:1,removed:2}[b.status] ?? 3)).map(member => {
      const own = member.user_id === session.user.id, assigned = roles.filter(r => r.client_assignee_membership_id === member.id).length;
      return `<article class="team-member"><span class="avatar" aria-hidden="true">${esc(M.initials(member.email))}</span><div class="member-copy"><strong>${esc(member.email)}${own ? '<span class="self-tag">You</span>' : ''}</strong><small>${member.role === 'superuser' ? 'Client superuser' : 'Team member'}</small></div><span class="member-role-count">${assigned} role${assigned === 1 ? '' : 's'}</span>${memberBadge(member.status)}${!own && ['active','invited'].includes(member.status) ? `<button class="text-button" data-manage-member="${esc(member.id)}" aria-label="Manage ${esc(member.email)}">Manage</button>` : ''}</article>`;
    }).join('') : empty('Your team starts here', 'Invite a colleague from an approved company domain.');
    $('domainBlock').hidden = !isStaffMode;
    if (isStaffMode) $('domains').innerHTML = domains.length ? domains.map(d => `<span class="domain">@${esc(d.domain)}<button data-domain-remove="${esc(d.domain)}" aria-label="Remove approved domain ${esc(d.domain)}">×</button></span>`).join('') : '<p class="small">No approved domain has been configured.</p>';
  }
  function render() {
    $('clientName').textContent = client.company_name; $('companyInitials').textContent = M.initials(client.company_name);
    $('modeLabel').textContent = isStaffMode ? 'BenchPro Admin recovery' : 'Client workspace';
    $('accountRole').textContent = isStaffMode ? 'BenchPro Admin' : canManage() ? 'Client superuser' : 'Team member';
    $('navRoleCount').textContent = roles.length;
    $('postRoleTab').hidden = isStaffMode; $('teamTab').hidden = !canManage(); $('manageDivider').hidden = !canManage();
    renderOverview(); syncFilters(); renderRoles(); renderTeam(); setActiveTab(state.tab);
    $('lastRefreshed').textContent = 'Updated ' + new Date().toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
    $('workspaceContent').hidden = false;
    if ($('roleDetailDialog').open) {
      if (roles.some(role => role.id === detailId)) renderRoleDetail(detailId);
      else $('roleDetailDialog').close();
    }
    prefillContact();
  }
  function loadWorkspace() {
    // A mutation finishing during Refresh must get a fresh read after that refresh.
    if (workspaceLoad) return workspaceLoad.catch(() => {}).then(loadWorkspace);
    workspaceLoad = fetchWorkspace().finally(() => { workspaceLoad = null; });
    return workspaceLoad;
  }
  async function fetchWorkspace() {
    showSignedIn(); feedback($('pageFeedback'), '');
    $('loadingState').hidden = loaded; $('refresh').disabled = true; $('refresh').setAttribute('aria-busy', 'true');
    try {
      let nextClient, nextMembership = null, nextMembers, nextDomains, nextRoles;
      if (managementId) {
        const workspace = await callAccess('get_staff_workspace', {}, managementId);
        nextClient = workspace.client; nextMembers = workspace.memberships || []; nextDomains = workspace.domains || []; nextRoles = workspace.roles || [];
      } else {
        const mp = new URLSearchParams({ select: 'id,client_id,role,status,email,user_id', user_id: 'eq.' + session.user.id, status: 'eq.active' });
        const own = await readResponse(await api('client_memberships?' + mp), 'Could not check your client access.');
        const clientId = new URLSearchParams(location.search).get('client_id');
        nextMembership = clientId ? own.find(m => m.client_id === clientId) : own[0];
        if (!nextMembership) {
          loaded = false; roles = []; members = []; $('workspaceContent').hidden = true; $('teamTab').hidden = true; $('headerPostRole').hidden = true;
          $('roleDetailDialog').close(); $('memberDialog').close();
          const candidate = await api('candidate_accounts?select=id&user_id=eq.' + session.user.id + '&limit=1');
          if (candidate.ok && (await candidate.json()).length) { location.replace('candidate.html'); return; }
          throw new Error('No active client access was found for this email. Ask your client superuser to invite you.');
        }
        nextClient = (await readResponse(await api('clients?select=id,company_name,company_size,business_type&id=eq.' + nextMembership.client_id + '&limit=1'), 'Could not load your company.'))[0];
        if (!nextClient) throw new Error('Client record not found.');
        const memberParams = new URLSearchParams({ select: 'id,client_id,user_id,email,role,status,created_at', client_id: 'eq.' + nextClient.id, order: 'created_at.asc' });
        const domainParams = new URLSearchParams({ select: 'domain', client_id: 'eq.' + nextClient.id });
        const roleParams = new URLSearchParams({ select: 'id,client_id,role_or_skills,project_duration,target_start_date,project_details,status,created_at,jd_file_path,jd_file_name,client_assignee_membership_id', client_id: 'eq.' + nextClient.id, order: 'created_at.desc' });
        [nextMembers, nextDomains, nextRoles] = await Promise.all([
          api('client_memberships?' + memberParams).then(r => readResponse(r, 'Could not load team details.')),
          api('client_email_domains?' + domainParams).then(r => readResponse(r, 'Could not load company domains.')),
          api('staffing_requests?' + roleParams).then(r => readResponse(r, 'Could not load your roles.'))
        ]);
      }
      if (!nextClient) throw new Error('Client record not found.');
      // All metrics, searches and drawers use this same permission-scoped list.
      actorMembership = nextMembership; client = nextClient; members = nextMembers; domains = nextDomains;
      roles = M.visibleRoles(nextRoles, nextMembership, isStaffMode); loaded = true; render();
    } finally {
      $('loadingState').hidden = true; $('refresh').disabled = false; $('refresh').removeAttribute('aria-busy');
    }
  }
  function prefillContact() {
    const metadata = session?.user?.user_metadata || {};
    if (!$('contactName').value) $('contactName').value = metadata.full_name || metadata.name || [metadata.first_name, metadata.last_name].filter(Boolean).join(' ');
    if (!$('workEmail').value) $('workEmail').value = session?.user?.email || '';
  }
  function renderRoleDetail(id) {
    const role = roles.find(r => r.id === id); if (!role) return;
    const owner = ownerOf(role);
    const options = '<option value="">Unassigned</option>' + members.filter(m => m.status === 'active').map(m => `<option value="${esc(m.id)}" ${m.id === role.client_assignee_membership_id ? 'selected' : ''}>${esc(m.email)}</option>`).join('');
    const assignment = canAssign() ? `<div class="owner-summary"><span class="avatar">${esc(owner ? M.initials(owner.email) : '—')}</span><span class="owner-email">${esc(owner?.email || (role.client_assignee_membership_id ? 'Previous team member' : 'Unassigned'))}</span><button class="text-button" id="editAssignment">${role.client_assignee_membership_id ? 'Edit' : 'Assign owner'}</button></div><div id="assignmentEditor" class="assignment-editor" hidden><label class="sr-only" for="assignmentOwner">Choose role owner</label><select id="assignmentOwner" data-assignment="${esc(role.id)}" data-previous="${esc(role.client_assignee_membership_id || '')}">${options}</select><button id="cancelAssignment" class="text-button">Cancel</button></div>` : `<div class="owner-summary"><span class="avatar">${esc(M.initials(owner?.email || greetingName()))}</span><span class="owner-email">${isStaffMode ? esc(owner?.email || 'Unassigned') : 'Assigned to you'}</span></div>`;
    $('roleDetailContent').innerHTML = `<div class="detail-top"><p class="eyebrow">ROLE DETAILS</p><button class="icon-button" data-close-dialog="roleDetailDialog" aria-label="Close role details">${icon('close')}</button></div><div class="detail-heading">${badge(role.status)}<h2 id="detailTitle">${esc(role.role_or_skills)}</h2><p>Submitted ${esc(fmtDate(role.created_at))}</p></div><div class="detail-body"><section class="detail-section"><h3>Role owner</h3>${assignment}</section><section class="detail-section"><dl class="detail-grid"><div><dt>Project duration</dt><dd>${esc(role.project_duration || 'Not specified')}</dd></div><div><dt>Target start date</dt><dd>${esc(fmtDate(role.target_start_date))}</dd></div></dl></section><section class="detail-section"><h3>The brief</h3><p class="detail-description">${esc(role.project_details || 'No additional project details were provided.')}</p></section>${role.jd_file_path ? `<section class="detail-section"><h3>Job description</h3><button class="attachment-button" data-view-jd="${esc(role.id)}">${icon('document')}<span>${esc(role.jd_file_name || 'Role description')}<small>Open secure document</small></span>${icon('right')}</button></section>` : ''}<div id="detailFeedback" class="feedback dialog-feedback" role="status" hidden></div><div class="detail-reference">Role reference: ${esc(role.id)}<button class="text-button" data-copy-reference="${esc(role.id)}">Copy reference</button></div></div>`;
  }
  function openRole(id) {
    if (!roles.some(role => role.id === id)) return;
    detailId = id; renderRoleDetail(id); $('roleDetailDialog').showModal();
  }
  function confirmAction(message, title = 'Confirm role assignment', action = 'Assign role') {
    return new Promise(resolve => {
      const dialog = $('assignmentConfirmDialog');
      $('assignmentDialogTitle').textContent = title; $('assignmentDialogMessage').textContent = message;
      $('confirmationAction').textContent = action;
      dialog.returnValue = ''; dialog.addEventListener('close', () => resolve(dialog.returnValue === 'confirm'), { once: true });
      dialog.showModal(); dialog.querySelector('[value="cancel"]').focus();
    });
  }
  async function changeAssignment(select) {
    if (!canAssign()) return;
    const previous = select.dataset.previous, next = select.value, id = select.dataset.assignment;
    if (previous === next) return;
    const member = members.find(m => m.id === next);
    if (!await confirmAction(next ? `${previous ? 'Reassign' : 'Assign'} this role to ${member?.email || 'this teammate'}? They will be able to view this role in their workspace.` : 'Remove the current owner? This role will remain visible to client superusers.', 'Confirm role assignment', next ? 'Assign role' : 'Unassign role')) { select.value = previous; return; }
    select.disabled = true;
    try {
      await readResponse(await api('rpc/assign_client_role', { method: 'POST', body: JSON.stringify({ target_request_id: id, target_membership_id: next || null }) }), 'Could not update the role owner.');
      await loadWorkspace();
      feedback($('detailFeedback'), next ? 'Role assigned to ' + member.email + '.' : 'This role is now unassigned.');
    } catch (error) { select.value = previous; if ($('detailFeedback')) feedback($('detailFeedback'), error.message, true); }
    finally { select.disabled = false; }
  }
  function openMember(id) {
    if (!canManage()) return;
    const member = members.find(m => m.id === id);
    if (!member || member.user_id === session.user.id || !['active','invited'].includes(member.status)) return;
    const assigned = roles.filter(r => r.client_assignee_membership_id === id).length;
    const options = members.filter(m => m.status === 'active' && m.id !== id).map(m => `<option value="${esc(m.id)}">${esc(m.email)}</option>`).join('');
    $('memberDialogContent').innerHTML = `<div class="modal-body member-modal"><button class="icon-button modal-close" data-close-dialog="memberDialog" aria-label="Close teammate details">${icon('close')}</button><span class="modal-symbol">${icon('team')}</span><h2 id="memberDialogTitle">${member.status === 'invited' ? 'Manage invitation' : 'Manage teammate'}</h2><p>${esc(member.email)}</p><p class="small">${assigned} role${assigned === 1 ? '' : 's'} assigned. Removing access keeps their BenchPro account and history.</p>${assigned ? `<div class="field"><label for="transferOwner">Transfer assigned roles before removing access</label><select id="transferOwner" required><option value="">Choose a replacement…</option>${options}</select>${!options ? '<p class="small">Invite or activate another teammate first.</p>' : ''}</div>` : ''}<div id="memberFeedback" class="feedback dialog-feedback" role="status" hidden></div></div><div class="modal-actions"><button class="button secondary" data-close-dialog="memberDialog">Keep access</button><button class="button danger" data-remove-member="${esc(id)}" ${assigned && !options ? 'disabled' : ''}>${member.status === 'invited' ? 'Cancel invitation' : 'Remove access'}</button></div>`;
    $('memberDialog').showModal();
  }
  async function removeMember(button) {
    if (!canManage()) return;
    const id = button.dataset.removeMember, replacement = $('transferOwner')?.value || null;
    if (roles.some(r => r.client_assignee_membership_id === id) && !replacement) {
      feedback($('memberFeedback'), 'Choose who should receive these roles first.', true); $('transferOwner').focus(); return;
    }
    button.disabled = true;
    try {
      const result = await callAccess('remove_member', { membership_id: id, replacement_membership_id: replacement });
      $('memberDialog').close(); await loadWorkspace(); feedback($('pageFeedback'), result.message || 'Client access removed. Their account and history have been kept.');
    } catch (error) { feedback($('memberFeedback'), error.message, true); }
    finally { button.disabled = false; }
  }
  async function viewJd(button) {
    const role = roles.find(r => r.id === button.dataset.viewJd);
    if (!role?.jd_file_path) return;
    button.disabled = true;
    // Open synchronously so browsers do not block the document after the fetch.
    const popup = window.open('about:blank', '_blank'); if (popup) popup.opener = null;
    try {
      const path = role.jd_file_path.split('/').map(encodeURIComponent).join('/');
      const result = await readResponse(await fetch(SUPABASE_URL + '/storage/v1/object/sign/client-role-jds/' + path, { method: 'POST', headers: { apikey: KEY, Authorization: 'Bearer ' + await accessToken(), 'Content-Type': 'application/json' }, body: JSON.stringify({ expiresIn: 120 }) }), 'Could not open the document.');
      const url = new URL(result.signedURL, SUPABASE_URL + '/storage/v1/');
      if (!/^https:$/.test(url.protocol) || url.origin !== new URL(SUPABASE_URL).origin) throw new Error('The document link could not be verified.');
      // Supabase returns a storage-relative /object/sign/... path.
      const href = result.signedURL.startsWith('/object/') ? SUPABASE_URL + '/storage/v1' + result.signedURL : url.href;
      if (popup) popup.location.replace(href); else {
        const message = $('detailFeedback'); feedback(message, 'Your browser blocked the new tab. ');
        const link = document.createElement('a'); link.href = href; link.target = '_blank'; link.rel = 'noopener'; link.textContent = 'Open document'; message.append(link);
      }
    } catch (error) { popup?.close(); feedback($('detailFeedback'), error.message, true); }
    finally { button.disabled = false; }
  }
  function fieldError(input, message) {
    let error = $(input.id + '-error');
    if (!error) { error = document.createElement('span'); error.id = input.id + '-error'; error.className = 'field-error'; input.closest('.field').append(error); }
    error.textContent = message; error.hidden = !message;
    if (message) { input.setAttribute('aria-invalid', 'true'); input.setAttribute('aria-describedby', error.id); }
    else { input.removeAttribute('aria-invalid'); input.removeAttribute('aria-describedby'); }
  }
  function validateField(input) {
    let message = '';
    if (input.required && !input.value.trim()) message = 'Please enter ' + ({ roleTitle:'a role or key skills.', contactName:'your name.', designation:'your designation.', workEmail:'a work email.', phone:'a phone number.' }[input.id] || 'this field.');
    else if (input.type === 'email' && input.value && !input.validity.valid) message = 'Enter a valid email address.';
    else if (input.minLength > 0 && input.value && input.value.trim().length < input.minLength) message = `Use at least ${input.minLength} characters.`;
    if (input.type === 'file' && input.files[0]) {
      if (!/\.(pdf|doc|docx)$/i.test(input.files[0].name)) message = 'Choose a PDF, DOC, or DOCX file.';
      else if (input.files[0].size > 10485760) message = 'Choose a file smaller than 10 MB.';
    }
    fieldError(input, message); return !message;
  }
  async function submitRole(event) {
    event.preventDefault(); if (isStaffMode || !loaded) return;
    const form = event.currentTarget, inputs = [...form.querySelectorAll('input,textarea')];
    const valid = inputs.map(validateField).every(Boolean);
    if (!valid) { form.querySelector('[aria-invalid=true]').focus(); feedback($('formFeedback'), 'Please check the highlighted fields.', true); return; }
    const data = new FormData(form), file = data.get('jd'), button = form.querySelector('[type=submit]');
    button.disabled = true; button.textContent = 'Sending request…'; feedback($('formFeedback'), '');
    let createdId = null;
    try {
      const value = key => String(data.get(key) || '').trim();
      const request = { id: crypto.randomUUID(), client_id: client.id, company_name: client.company_name,
        contact_name: value('contact_name'), designation: value('designation'), work_email: value('work_email').toLowerCase(), phone_number: value('phone_number'),
        role_or_skills: value('role_or_skills'), project_duration: value('project_duration') || null, target_start_date: value('target_start_date') || null,
        work_location_timezone: value('work_location_timezone') || null, project_details: value('project_details') || null,
        company_size: client.company_size || null, business_type: client.business_type || null, status: 'new' };
      await readResponse(await api('staffing_requests', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: JSON.stringify(request) }), 'Could not submit the role. Please try again.');
      createdId = request.id;
      if (file?.size) {
        const extension = file.name.split('.').pop().toLowerCase();
        const mime = { pdf:'application/pdf',doc:'application/msword',docx:'application/vnd.openxmlformats-officedocument.wordprocessingml.document' }[extension];
        const base = file.name.replace(/\.[^.]+$/, '').replace(/[^A-Za-z0-9_-]/g, '_').slice(0, 70) || 'role-description';
        const path = `requests/${createdId}/${crypto.randomUUID()}_${base}.${extension}`;
        const response = await fetch(SUPABASE_URL + '/storage/v1/object/client-role-jds/' + path.split('/').map(encodeURIComponent).join('/'), { method:'POST', headers:{ apikey:KEY, Authorization:'Bearer ' + await accessToken(), 'Content-Type':mime, 'x-upsert':'false' }, body:file });
        if (!response.ok) throw new Error('The role was saved, but the job description could not be uploaded. Contact your BenchPro representative with this reference: ' + createdId + '.');
        const linked = await readResponse(await api('staffing_requests?id=eq.' + createdId + '&select=id,jd_file_path', { method:'PATCH', headers:{Prefer:'return=representation'}, body:JSON.stringify({jd_file_path:path,jd_file_name:file.name,jd_file_size:file.size,jd_file_type:mime}) }), 'The role was saved, but its attachment could not be linked. Contact BenchPro with reference ' + createdId + '.');
        if (!Array.isArray(linked) || !linked.some(row => row.id === createdId && row.jd_file_path === path)) throw new Error('The role was saved, but its attachment could not be linked. Contact BenchPro with reference ' + createdId + '.');
      }
      form.reset(); inputs.forEach(input => fieldError(input, '')); prefillContact();
      openRoleList('new');
      await loadWorkspace();
      feedback($('pageFeedback'), canManage() ? 'Role submitted. Your BenchPro team will review the request and follow up.' : 'Role submitted for review. Your superuser will assign an owner; it will appear in your list if assigned to you.');
    } catch (error) {
      if (createdId) {
        // The record exists: clear the form so a retry cannot create a duplicate role.
        form.reset(); prefillContact(); setActiveTab('roles');
        await loadWorkspace().catch(() => {});
        showError(error.message + ' Do not submit the role again.');
      } else feedback($('formFeedback'), error.message || 'Could not submit your role.', true);
    } finally { button.disabled = false; button.innerHTML = 'Send role request <span aria-hidden="true">→</span>'; }
  }
  const mobileLayout = window.matchMedia('(max-width: 780px)');
  function syncMenuAccess() {
    const open = mobileLayout.matches && document.body.classList.contains('nav-open');
    $('workspaceSidebar').inert = mobileLayout.matches && !open;
    document.querySelector('.workspace-body').inert = open;
  }
  function closeMenu() { document.body.classList.remove('nav-open'); $('navBackdrop').hidden = true; $('menuToggle').setAttribute('aria-expanded', 'false'); syncMenuAccess(); }
  mobileLayout.addEventListener('change', closeMenu);
  syncMenuAccess();
  $('menuToggle').addEventListener('click', () => {
    const open = !document.body.classList.contains('nav-open');
    document.body.classList.toggle('nav-open', open); $('navBackdrop').hidden = !open; $('menuToggle').setAttribute('aria-expanded', String(open));
    syncMenuAccess();
    if (open) document.querySelector('[data-tab][aria-current=page]').focus();
  });
  $('navBackdrop').addEventListener('click', closeMenu);
  $('closeNavigation').addEventListener('click', () => { closeMenu(); $('menuToggle').focus(); });
  document.addEventListener('keydown', event => {
    if (!document.body.classList.contains('nav-open')) return;
    if (event.key === 'Escape') { closeMenu(); $('menuToggle').focus(); }
    if (event.key === 'Tab') {
      const focusable = [...$('workspaceSidebar').querySelectorAll('a,button')].filter(node => node.getClientRects().length && !node.disabled);
      const first = focusable[0], last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
  });
  document.addEventListener('click', event => {
    const button = event.target.closest('button'); if (!button || button.disabled) return;
    if (button.dataset.tab) setActiveTab(button.dataset.tab, true);
    if (button.dataset.goTab) setActiveTab(button.dataset.goTab, true);
    if (button.dataset.openFilter) openRoleList(button.dataset.openFilter, button.dataset.owner || 'all');
    if (button.dataset.openRole) openRole(button.dataset.openRole);
    if (button.dataset.closeDialog) $(button.dataset.closeDialog).close();
    if (button.dataset.manageMember) openMember(button.dataset.manageMember);
    if (button.dataset.removeMember) void removeMember(button);
    if (button.dataset.viewJd) void viewJd(button);
    if (button.hasAttribute('data-clear-filters')) openRoleList();
    if (button.hasAttribute('data-upcoming')) { state.sort = 'start'; openRoleList('current'); }
    if (button.dataset.roleFilter) { state.filter = button.dataset.roleFilter; state.page = 1; renderRoles(); persistView(); }
    if (button.id === 'editAssignment') { $('assignmentEditor').hidden = false; button.hidden = true; $('assignmentOwner').focus(); }
    if (button.id === 'cancelAssignment') { $('assignmentEditor').hidden = true; $('assignmentOwner').value = $('assignmentOwner').dataset.previous; $('editAssignment').hidden = false; $('editAssignment').focus(); }
    if (button.dataset.copyReference) navigator.clipboard.writeText(button.dataset.copyReference).then(() => { button.textContent = 'Reference copied'; }).catch(() => { button.textContent = 'Select and copy the reference above'; });
  });
  $('roleDetailDialog').addEventListener('change', event => { if (event.target.matches('[data-assignment]')) void changeAssignment(event.target); });
  $('roleDetailDialog').addEventListener('close', () => { detailId = null; });
  $('roleSearch').addEventListener('input', event => { state.search = event.target.value; state.page = 1; renderRoles(); persistView(); });
  $('ownerFilter').addEventListener('change', event => { state.owner = event.target.value; state.page = 1; renderRoles(); persistView(); });
  $('roleSort').addEventListener('change', event => { state.sort = event.target.value; state.page = 1; renderRoles(); persistView(); });
  $('previousPage').addEventListener('click', () => { state.page = Math.max(1, state.page - 1); renderRoles(); });
  $('nextPage').addEventListener('click', () => { state.page++; renderRoles(); });
  $('refresh').addEventListener('click', () => loadWorkspace().catch(handleLoadError));
  $('newRoleForm').addEventListener('submit', submitRole);
  $('newRoleForm').addEventListener('input', event => { if (event.target.hasAttribute('aria-invalid')) validateField(event.target); });
  $('newRoleForm').addEventListener('change', event => { if (event.target.type === 'file') validateField(event.target); });
  $('showInvite').addEventListener('click', () => { if (!canManage()) return; $('inviteForm').hidden = false; $('inviteEmail').focus(); });
  $('cancelInvite').addEventListener('click', () => { $('inviteForm').hidden = true; $('showInvite').focus(); });
  $('inviteForm').addEventListener('submit', async event => {
    event.preventDefault(); if (!canManage()) return;
    const form = event.currentTarget, button = form.querySelector('[type=submit]'); button.disabled = true;
    try {
      const result = await callAccess('invite', { email: $('inviteEmail').value.trim().toLowerCase(), role: isStaffMode ? $('inviteRole').value : 'recruiter' });
      form.reset(); form.hidden = true; await loadWorkspace(); feedback($('pageFeedback'), result.message || 'Invitation sent.');
    } catch (error) { showError(error.message); } finally { button.disabled = false; }
  });
  $('domainForm').addEventListener('submit', async event => {
    event.preventDefault(); if (!isStaffMode || !canManage()) return;
    const button = event.currentTarget.querySelector('button'); button.disabled = true;
    try { const result = await callAccess('add_domain', { domain: $('newDomain').value.trim() }); $('domainForm').reset(); await loadWorkspace(); feedback($('pageFeedback'), 'Approved @' + result.domain + ' for this client.'); }
    catch (error) { showError(error.message); } finally { button.disabled = false; }
  });
  $('domains').addEventListener('click', async event => {
    const button = event.target.closest('[data-domain-remove]'); if (!button || !isStaffMode) return;
    if (!await confirmAction('Remove @' + button.dataset.domainRemove + ' from the approved domains for this company?', 'Remove approved domain', 'Remove domain')) return;
    button.disabled = true;
    try { await callAccess('remove_domain', { domain: button.dataset.domainRemove }); await loadWorkspace(); feedback($('pageFeedback'), 'Approved domain removed.'); }
    catch (error) { showError(error.message); } finally { button.disabled = false; }
  });
  $('loginForm').addEventListener('submit', async event => {
    event.preventDefault(); $('loginButton').disabled = true; feedback($('authFeedback'), '');
    try {
      session = await readResponse(await auth('token?grant_type=password', { email: $('email').value.trim().toLowerCase(), password: $('password').value }), 'Email or password not recognized.');
      session.expires_at ||= Math.floor(Date.now()/1000) + (session.expires_in || 3600); saveSession(session);
      loaded = false; $('workspaceContent').hidden = true;
    } catch (error) { showSignedOut(error.message); $('loginButton').disabled = false; return; }
    try { await loadWorkspace(); } catch (error) { handleLoadError(error); } finally { $('loginButton').disabled = false; }
  });
  $('signOut').addEventListener('click', async () => {
    $('signOut').disabled = true;
    try { await auth('logout', {}, await accessToken()); } catch { /* Clear the local session even when offline. */ }
    sessionStorage.removeItem(managementId ? STAFF_KEY : CLIENT_KEY); session = null;
    if (!managementId) location.replace('login.html'); else { showSignedOut(); $('signOut').disabled = false; }
  });
  $('forgotPassword').addEventListener('click', async () => {
    if (!$('email').reportValidity() || !$('email').value.trim()) { $('email').focus(); return; }
    $('forgotPassword').disabled = true;
    try { await readResponse(await auth('recover?redirect_to=' + encodeURIComponent(location.origin + '/login.html'), { email:$('email').value.trim().toLowerCase() }), 'Could not send a reset email.'); feedback($('authFeedback'), 'If an account exists for that address, a password reset link is on its way.'); }
    catch (error) { feedback($('authFeedback'), error.message, true); } finally { $('forgotPassword').disabled = false; }
  });
  async function passwordSetup(hash) {
    session = { access_token:hash.get('access_token'), refresh_token:hash.get('refresh_token'), expires_at:Math.floor(Date.now()/1000) + Number(hash.get('expires_in') || 3600) };
    session.user = await readResponse(await fetch(SUPABASE_URL + '/auth/v1/user', { headers:{apikey:KEY,Authorization:'Bearer ' + session.access_token} }), 'Could not verify this invitation.');
    saveSession(session); history.replaceState(null, '', location.pathname + location.search);
    const panel = document.createElement('section'); panel.id = 'passwordSetupView'; panel.className = 'login-card';
    panel.innerHTML = '<h1>Set your password</h1><p>Choose a password to finish setting up client portal access.</p><form id="setPassword"><div class="field"><label for="newPassword">Password</label><input id="newPassword" type="password" minlength="6" required autocomplete="new-password"><span class="small">Use 6 or more characters with a letter, a number, and a special character.</span></div><button class="button" type="submit">Set password</button></form><div id="setFeedback" class="feedback" role="status" hidden></div>';
    $('authView').hidden = true; $('authView').after(panel);
    panel.querySelector('form').addEventListener('submit', async event => {
      event.preventDefault(); const password = $('newPassword').value, button = panel.querySelector('button');
      if (!/^(?=.*[A-Za-z])(?=.*\d)(?=.*[^A-Za-z0-9\s]).{6,}$/.test(password)) { feedback($('setFeedback'), 'Use 6 or more characters with a letter, a number, and a special character.', true); return; }
      button.disabled = true;
      try { session.user = await readResponse(await fetch(SUPABASE_URL + '/auth/v1/user', { method:'PUT',headers:{apikey:KEY,Authorization:'Bearer ' + await accessToken(),'Content-Type':'application/json'},body:JSON.stringify({password}) }), 'Could not set your password.'); saveSession(session); await loadWorkspace(); }
      catch (error) { if ($('setFeedback')) feedback($('setFeedback'), error.message, true); else handleLoadError(error); }
      finally { button.disabled = false; }
    });
  }
  (async () => {
    const hash = new URLSearchParams(location.hash.slice(1));
    if (hash.get('error_code')) { history.replaceState(null, '', location.pathname + location.search); showSignedOut('This invitation could not be verified. Ask BenchPro Admin for a fresh invitation.'); return; }
    if (hash.has('access_token') && hash.has('refresh_token')) { try { await passwordSetup(hash); } catch (error) { showSignedOut(error.message); } return; }
    session = getSession();
    if (!session?.access_token) { if (!managementId) location.replace('login.html'); else showSignedOut(); return; }
    try {
      if (!session.user?.id) { session.user = await readResponse(await fetch(SUPABASE_URL + '/auth/v1/user', { headers:{apikey:KEY,Authorization:'Bearer ' + await accessToken()} }), 'Please sign in again.'); saveSession(session); }
      await loadWorkspace();
    } catch (error) { handleLoadError(error); }
  })();
})();
