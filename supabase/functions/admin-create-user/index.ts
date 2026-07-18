// Admin-only user provisioning. Public self-signup is disabled (see
// pages/login.vue and the Auth provider setting in the Supabase dashboard);
// this is now the only way a new user account gets created. Runs with the
// service role key (auto-injected by the Edge Function runtime) so it can
// call the Auth Admin API — something the anon key can never do, by design.
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

    const { email, full_name, password, role, company_id } = await req.json()
    if (!email || !password || !role || !company_id) {
      throw new Error('email, password, role and company_id are required')
    }
    if (password.length < 8) throw new Error('Password must be at least 8 characters')

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    // Identify the caller from their own session (respects their real JWT).
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } }
    })
    const { data: { user: caller }, error: callerErr } = await callerClient.auth.getUser()
    if (callerErr || !caller) throw new Error('Not authenticated')

    // Service-role client: verifies the caller is really an admin of this
    // company (can't trust the client to self-report that) and performs
    // the privileged create.
    const admin = createClient(supabaseUrl, serviceKey)

    const { data: membership } = await admin
      .from('company_members')
      .select('role, is_active')
      .eq('user_id', caller.id)
      .eq('company_id', company_id)
      .maybeSingle()

    if (!membership || membership.role !== 'admin' || membership.is_active === false) {
      throw new Error('Only an admin of this company can create users')
    }

    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: full_name || email }
    })
    if (createErr) throw createErr

    const { error: memberErr } = await admin.from('company_members').upsert(
      { user_id: created.user!.id, company_id, role, is_active: true },
      { onConflict: 'user_id,company_id' }
    )
    if (memberErr) throw memberErr

    return new Response(JSON.stringify({ user_id: created.user!.id }), {
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
