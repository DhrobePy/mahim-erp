// Admin-only user editing (name / email / password reset). Mirrors
// admin-create-user's auth model: the caller's own JWT identifies them,
// then a service-role client independently verifies they're actually an
// admin of the target user's company before touching anything — never
// trusts the client's own claim.
import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Missing Authorization header')

    const { user_id, company_id, full_name, email, password } = await req.json()
    if (!user_id || !company_id) throw new Error('user_id and company_id are required')
    if (password && password.length < 8) throw new Error('Password must be at least 8 characters')

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } }
    })
    const { data: { user: caller }, error: callerErr } = await callerClient.auth.getUser()
    if (callerErr || !caller) throw new Error('Not authenticated')

    const admin = createClient(supabaseUrl, serviceKey)

    const { data: membership } = await admin
      .from('company_members')
      .select('role, is_active')
      .eq('user_id', caller.id)
      .eq('company_id', company_id)
      .maybeSingle()
    if (!membership || membership.role !== 'admin' || membership.is_active === false) {
      throw new Error('Only an admin of this company can edit users')
    }

    // Defense in depth: the target must actually belong to this company —
    // an admin of company A can't reach into company B via this endpoint.
    const { data: targetMembership } = await admin
      .from('company_members')
      .select('user_id')
      .eq('user_id', user_id)
      .eq('company_id', company_id)
      .maybeSingle()
    if (!targetMembership) throw new Error('User is not a member of this company')

    const authUpdate: Record<string, unknown> = {}
    if (email) authUpdate.email = email
    if (password) authUpdate.password = password
    if (full_name !== undefined) authUpdate.user_metadata = { full_name }

    if (Object.keys(authUpdate).length) {
      const { error: updateErr } = await admin.auth.admin.updateUserById(user_id, authUpdate)
      if (updateErr) throw updateErr
    }

    const profileUpdate: Record<string, unknown> = {}
    if (full_name !== undefined) profileUpdate.full_name = full_name
    if (email) profileUpdate.email = email
    if (Object.keys(profileUpdate).length) {
      const { error: profileErr } = await admin.from('profiles').update(profileUpdate).eq('id', user_id)
      if (profileErr) throw profileErr
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : String(e) }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400
    })
  }
})
