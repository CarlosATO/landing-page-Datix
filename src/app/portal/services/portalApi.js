export function createPortalApi(supabase) {
  async function getAuthHeaders() {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.access_token) return null;
    return {
      Authorization: `Bearer ${session.access_token}`,
      'Content-Type': 'application/json',
    };
  }

  async function request(url, body, method = 'POST') {
    const headers = await getAuthHeaders();
    if (!headers) throw new Error('No hay sesión activa.');

    const response = await fetch(url, {
      method,
      headers,
      body: JSON.stringify(body),
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.error || 'No se pudo completar la operación.');
    return data;
  }

  return {
    bootstrap: () => request('/api/portal/bootstrap', {}),
    updateCompany: (companyId, data) => request('/api/company/update', { companyId, data }),
    updateProfile: (companyId, updates) => request('/api/profile/update', { companyId, updates }, 'PATCH'),
    repairRoles: (companyId) => request('/api/company/repair-roles', { companyId }),
    inviteTeamMember: (payload) => request('/api/team/invite', payload),
    updateTeamMember: (payload) => request('/api/team/invite', payload, 'PATCH'),
    openBillingPortal: (companyId) => request('/api/stripe/portal', { companyId }),
    request,
    getAuthHeaders,
  };
}
