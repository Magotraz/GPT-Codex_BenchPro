/* Pure view helpers. Server-side RLS remains the authority for client access. */
(function (root) {
  'use strict';
  const statuses = {
    new: { label: 'Awaiting review', color: 'new' },
    contacted: { label: 'In discussion', color: 'contacted' },
    qualified: { label: 'Qualified', color: 'qualified' },
    closed: { label: 'Closed', color: 'closed' }
  };
  function visibleRoles(roles, membership, staffMode = false) {
    if (staffMode) return roles;
    if (!membership?.id || membership.status !== 'active') return [];
    if (membership.role === 'superuser') return roles;
    return roles.filter(role => role.client_assignee_membership_id === membership.id);
  }
  function filterRoles(roles, members, state) {
    const query = (state.search || '').trim().toLocaleLowerCase();
    const emails = new Map(members.map(member => [member.id, member.email]));
    const filtered = roles.filter(role => {
      if (state.filter === 'current' && role.status === 'closed') return false;
      if (['new', 'closed'].includes(state.filter) && role.status !== state.filter) return false;
      if (state.owner === 'unassigned' && role.client_assignee_membership_id) return false;
      if (state.owner && !['all', 'unassigned'].includes(state.owner) && role.client_assignee_membership_id !== state.owner) return false;
      return !query || [role.role_or_skills, emails.get(role.client_assignee_membership_id), role.id]
        .some(value => String(value || '').toLocaleLowerCase().includes(query));
    });
    return filtered.sort((a, b) => {
      if (state.sort === 'title') return String(a.role_or_skills || '').localeCompare(String(b.role_or_skills || ''));
      if (state.sort === 'start') return (a.target_start_date || '9999').localeCompare(b.target_start_date || '9999');
      const order = String(b.created_at || '').localeCompare(String(a.created_at || ''));
      return state.sort === 'oldest' ? -order : order;
    });
  }
  function counts(roles) {
    return { total: roles.length, open: roles.filter(r => r.status !== 'closed').length,
      review: roles.filter(r => r.status === 'new').length,
      unassigned: roles.filter(r => r.status !== 'closed' && !r.client_assignee_membership_id).length,
      closed: roles.filter(r => r.status === 'closed').length };
  }
  function upcoming(roles, now = new Date()) {
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const end = new Date(today); end.setDate(end.getDate() + 14);
    return roles.filter(role => {
      if (!role.target_start_date || role.status === 'closed') return false;
      const date = new Date(role.target_start_date + 'T00:00:00');
      return date >= today && date <= end;
    });
  }
  function initials(value) {
    return String(value || 'B').split('@')[0].split(/[\s._+-]+/).filter(Boolean).slice(0, 2).map(s => s[0].toLocaleUpperCase()).join('');
  }
  const model = { statuses, visibleRoles, filterRoles, counts, upcoming, initials };
  if (typeof module !== 'undefined' && module.exports) module.exports = model;
  else root.BenchProClientModel = model;
})(typeof globalThis !== 'undefined' ? globalThis : this);
