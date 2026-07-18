// Per-user, per-page permission grants (migration 0019) — replaces the
// fixed role tiers for day-to-day module access. Admins always pass
// (checked server-side too, via has_permission()/has_module_view()) so
// this is a UI convenience layer, not the actual security boundary.
export interface PermissionModule {
  key: string
  label: string
  group_label: string
  sort_order: number
}

export const usePermissions = () => {
  const client = useSupabaseClient()
  const user = useSupabaseUser()
  const { profile, activeCompanyId } = useProfile()

  const modules = useState<PermissionModule[]>('erp-permission-modules', () => [])
  const grants = useState<Set<string>>('erp-permission-grants', () => new Set())

  const load = async () => {
    if (!user.value || !activeCompanyId.value) {
      grants.value = new Set()
      return
    }
    const [{ data: mods }, { data: g }] = await Promise.all([
      modules.value.length ? Promise.resolve({ data: modules.value }) : client.from('permission_modules').select('*').order('sort_order'),
      client.from('user_permissions').select('module_key, action')
        .eq('user_id', user.value.id).eq('company_id', activeCompanyId.value)
    ])
    modules.value = (mods as any) ?? []
    grants.value = new Set((g ?? []).map((row: any) => `${row.module_key}.${row.action}`))
  }

  const isAdmin = computed(() => profile.value?.role === 'admin')
  const canView = (moduleKey: string) => isAdmin.value || grants.value.has(`${moduleKey}.view`) || grants.value.has(`${moduleKey}.write`)
  const canWriteModule = (moduleKey: string) => isAdmin.value || grants.value.has(`${moduleKey}.write`)

  const groupedModules = computed(() => {
    const out: Record<string, PermissionModule[]> = {}
    for (const m of modules.value) {
      out[m.group_label] = out[m.group_label] ?? []
      out[m.group_label].push(m)
    }
    return out
  })

  // For a given user (not necessarily the current one) — used by the
  // admin permission editor. Returns a plain module_key -> {view, write}
  // map so the grid can be v-modeled directly.
  const loadFor = async (targetUserId: string, companyId: string) => {
    const { data } = await client.from('user_permissions').select('module_key, action')
      .eq('user_id', targetUserId).eq('company_id', companyId)
    const out: Record<string, { view: boolean; write: boolean }> = {}
    for (const m of modules.value) out[m.key] = { view: false, write: false }
    for (const row of (data ?? []) as any[]) {
      out[row.module_key] = out[row.module_key] ?? { view: false, write: false }
      out[row.module_key][row.action as 'view' | 'write'] = true
    }
    return out
  }

  const saveFor = async (targetUserId: string, companyId: string, state: Record<string, { view: boolean; write: boolean }>) => {
    await client.from('user_permissions').delete().eq('user_id', targetUserId).eq('company_id', companyId)
    const rows: any[] = []
    for (const [moduleKey, { view, write }] of Object.entries(state)) {
      if (view) rows.push({ user_id: targetUserId, company_id: companyId, module_key: moduleKey, action: 'view' })
      if (write) rows.push({ user_id: targetUserId, company_id: companyId, module_key: moduleKey, action: 'write' })
    }
    if (rows.length) {
      const { error } = await client.from('user_permissions').insert(rows)
      if (error) throw error
    }
  }

  return { modules, groupedModules, load, canView, canWriteModule, loadFor, saveFor }
}
