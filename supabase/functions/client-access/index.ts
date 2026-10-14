import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const reply = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return reply({ error: "Method not allowed." }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const appSiteUrl = Deno.env.get("APP_SITE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_PUBLISHABLE_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = request.headers.get("Authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return reply({ error: "Sign in to continue." }, 401);

  const authClient = createClient(url, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: { user }, error: authError } = await authClient.auth.getUser(token);
  if (authError || !user?.email) return reply({ error: "Your session is invalid. Sign in again." }, 401);
  const db = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const email = user.email.trim().toLowerCase();
  const domain = email.split("@").at(-1)!;
  const { data: isStaff } = await authClient.rpc("is_benchpro_staff_account");

  try {
    const body = await request.json();
    const action = String(body.action || "");
    const clientId = String(body.client_id || "");
    if (!/^[0-9a-f-]{36}$/i.test(clientId)) return reply({ error: "Choose a valid client." }, 400);

    if (action === "get_staff_workspace") {
      if (!isStaff) return reply({ error: "This account is not authorized for BenchPro staff recovery." }, 403);
      const [clientResult, membershipsResult, domainsResult, rolesResult] = await Promise.all([
        db.from("clients").select("id,company_name,company_size,business_type").eq("id", clientId).maybeSingle(),
        db.from("client_memberships").select("id,client_id,user_id,email,role,status,created_at").eq("client_id", clientId).order("created_at", { ascending: true }),
        db.from("client_email_domains").select("domain").eq("client_id", clientId),
        db.from("staffing_requests").select("id,client_id,role_or_skills,project_duration,target_start_date,project_details,status,created_at,jd_file_path,jd_file_name,client_assignee_membership_id").eq("client_id", clientId).order("created_at", { ascending: false }),
      ]);
      if (clientResult.error) throw clientResult.error;
      if (!clientResult.data) return reply({ error: "Client record not found." }, 404);
      if (membershipsResult.error) throw membershipsResult.error;
      if (domainsResult.error) throw domainsResult.error;
      if (rolesResult.error) throw rolesResult.error;
      return reply({ ok: true, client: clientResult.data, memberships: membershipsResult.data || [], domains: domainsResult.data || [], roles: rolesResult.data || [] });
    }

    if (action === "add_domain") {
      if (!isStaff) return reply({ error: "Only BenchPro staff can approve a client email domain." }, 403);
      const approvedDomain = String(body.domain || "").trim().toLowerCase().replace(/^@/, "");
      if (!/^(?=.{4,253}$)[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$/.test(approvedDomain)) return reply({ error: "Enter a valid company email domain." }, 400);
      const { error } = await db.from("client_email_domains").upsert({ client_id: clientId, domain: approvedDomain, created_by: user.id }, { onConflict: "client_id,domain" });
      if (error) throw error;
      return reply({ ok: true, domain: approvedDomain });
    }

    if (action === "remove_domain") {
      if (!isStaff) return reply({ error: "Only BenchPro staff can change approved client domains." }, 403);
      const approvedDomain = String(body.domain || "").trim().toLowerCase();
      const { count, error: countError } = await db.from("client_memberships").select("id", { count: "exact", head: true }).eq("client_id", clientId).in("status", ["active", "invited"]).like("email", `%@${approvedDomain}`);
      if (countError) throw countError;
      if (count) return reply({ error: "Move or deactivate active members using this domain before removing it." }, 409);
      const { error } = await db.from("client_email_domains").delete().eq("client_id", clientId).eq("domain", approvedDomain);
      if (error) throw error;
      return reply({ ok: true });
    }

    const { data: domains, error: domainError } = await db.from("client_email_domains").select("domain").eq("client_id", clientId);
    if (domainError) throw domainError;
    if (!isStaff && !domains?.some((row) => row.domain === domain)) return reply({ error: "Your account email is outside this client's approved domain." }, 403);
    const { data: memberships, error: membershipError } = await db.from("client_memberships").select("id,role,status,email,user_id").eq("client_id", clientId).eq("user_id", user.id).eq("status", "active");
    if (membershipError) throw membershipError;
    const actorMembership = memberships?.[0];
    const isSuperuser = actorMembership?.role === "superuser";

    if (action === "invite") {
      const targetEmail = String(body.email || "").trim().toLowerCase();
      const requestedRole = String(body.role || "recruiter");
      if (!/^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/i.test(targetEmail)) return reply({ error: "Enter a valid work email." }, 400);
      const targetDomain = targetEmail.split("@").at(-1)!;
      if (!domains?.some((row) => row.domain === targetDomain)) return reply({ error: "This email domain is not approved for this client." }, 403);
      const role = requestedRole === "superuser" ? "superuser" : "recruiter";
      if (role === "superuser" ? !isStaff : !(isStaff || isSuperuser)) return reply({ error: "BenchPro Admin manages superuser invitations. Only the client superuser can invite teammates." }, 403);

      const { data: existingInvite } = await db.from("client_memberships").select("id,status").eq("client_id", clientId).eq("email", targetEmail).in("status", ["invited", "active"]).maybeSingle();
      if (existingInvite) return reply({ error: "This email already has an active or pending membership for this client." }, 409);

      // Reserve the pending membership before Auth creates the invite. The database trigger activates it only after email confirmation.
      const { data: pending, error: insertError } = await db.from("client_memberships").insert({ client_id: clientId, email: targetEmail, role, status: "invited", invited_by: user.id }).select("id").single();
      if (insertError) throw insertError;
      try {
        const { data: usersPage, error: usersError } = await db.auth.admin.listUsers({ page: 1, perPage: 1000 });
        if (usersError) throw usersError;
        const found = usersPage.users.find((candidate) => candidate.email?.toLowerCase() === targetEmail);
        if (found) {
          if (!found.email_confirmed_at) throw new Error("This account has not confirmed its email yet. Ask the user to activate it first, then invite again.");
          const { error: attachError } = await db.from("client_memberships").update({ user_id: found.id, status: "active", activated_at: new Date().toISOString() }).eq("id", pending.id);
          if (attachError) throw attachError;
          return reply({ ok: true, message: "Existing verified account added to the client team." });
        }
        if (!appSiteUrl) throw new Error("Set APP_SITE_URL in the Edge Function secrets before sending invitations.");
        const { error: inviteError } = await db.auth.admin.inviteUserByEmail(targetEmail, { redirectTo: `${appSiteUrl.replace(/\/$/, "")}/client.html` });
        if (inviteError) throw inviteError;
        return reply({ ok: true, message: "Invitation sent. The membership activates after the user verifies their email." });
      } catch (error) {
        await db.from("client_memberships").delete().eq("id", pending.id);
        throw error;
      }
    }

    if (action === "remove_member") {
      if (!isStaff && !isSuperuser) return reply({ error: "Only BenchPro Admin or this client's superuser can remove teammates." }, 403);
      const memberId = String(body.membership_id || "");
      const replacementId = body.replacement_membership_id ? String(body.replacement_membership_id) : null;
      const { data: member, error: memberError } = await db.from("client_memberships").select("id,role,status,user_id").eq("id", memberId).eq("client_id", clientId).single();
      if (memberError || !member || !["active", "invited"].includes(member.status)) return reply({ error: "That teammate is no longer active." }, 404);
      if (member.user_id === user.id && !isStaff) return reply({ error: "Ask another client superuser or BenchPro Admin to remove your access." }, 409);
      if (!isStaff && member.role === "superuser") return reply({ error: "Only BenchPro Admin can recover or replace a client superuser." }, 403);
      if (member.role === "superuser" && member.status === "active") {
        const { count } = await db.from("client_memberships").select("id", { count: "exact", head: true }).eq("client_id", clientId).eq("role", "superuser").eq("status", "active");
        if ((count || 0) <= 1) return reply({ error: "Add another client superuser first. BenchPro Admin can restore access." }, 409);
      }
      if (replacementId) {
        const { data: replacement, error: replacementError } = await db.from("client_memberships").select("id").eq("id", replacementId).eq("client_id", clientId).eq("status", "active").single();
        if (replacementError || !replacement) return reply({ error: "Choose an active teammate from this client." }, 400);
      }
      const { error: transferError } = await authClient.rpc("release_client_member_roles", { target_client_id: clientId, departing_membership_id: memberId, replacement_membership_id: replacementId });
      if (transferError) throw transferError;
      const { error } = await db.from("client_memberships").update({ status: "removed", removed_at: new Date().toISOString() }).eq("id", memberId);
      if (error) throw error;
      return reply({ ok: true, message: replacementId ? "Membership removed; assigned roles moved to the selected teammate. Account and history retained." : "Membership removed. Account and history retained." });
    }

    if (action === "request_email_change") {
      if (isStaff || actorMembership?.role !== "superuser") {
        return reply({ error: "Only this client's superuser can request an account email change." }, 403);
      }
      const targetEmail = String(body.email || "").trim().toLowerCase();
      if (!/^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/i.test(targetEmail)) {
        return reply({ error: "Enter a valid new work email." }, 400);
      }
      const { data: activeMemberships, error: activeMembershipsError } = await db
        .from("client_memberships")
        .select("client_id")
        .eq("user_id", user.id)
        .eq("status", "active");
      if (activeMembershipsError) throw activeMembershipsError;
      const membershipClientIds = [...new Set((activeMemberships || []).map((row) => row.client_id))];
      const { data: approvedDomains, error: approvedDomainsError } = membershipClientIds.length
        ? await db.from("client_email_domains").select("client_id,domain").in("client_id", membershipClientIds)
        : { data: [], error: null };
      if (approvedDomainsError) throw approvedDomainsError;
      const targetDomain = targetEmail.split("@").at(-1)!;
      if (membershipClientIds.some((id) => !approvedDomains?.some((row) => row.client_id === id && row.domain === targetDomain))) {
        return reply({ error: "The new email domain must be approved for every client workspace linked to this account. Ask BenchPro Admin to approve it first." }, 403);
      }
      const updateResponse = await fetch(`${url}/auth/v1/user`, {
        method: "PUT",
        headers: { apikey: anonKey, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({ email: targetEmail }),
      });
      const updateResult = await updateResponse.json().catch(() => ({}));
      if (!updateResponse.ok) return reply({ error: updateResult.msg || updateResult.message || "Could not request an email change." }, updateResponse.status);
      return reply({ ok: true, message: "Check the new email inbox to verify the change. Your sign-in email updates after verification." });
    }

    return reply({ error: "Unknown client access action." }, 400);
  } catch (error) {
    console.error("client-access failed", error);
    return reply({ error: error instanceof Error ? error.message : "Client access request failed." }, 500);
  }
});
