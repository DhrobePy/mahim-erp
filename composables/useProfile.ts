// Loads and caches the current user's ERP profile plus company memberships.
// Roles live per company (company_members) since 0002_multi_company; the
// exposed `profile.role` is the role in the active company so existing
// consumers (layout badge, canWrite checks) keep working unchanged.
export type ErpRole = 'admin' | 'manager' | 'store' | 'production' | 'sales' | 'accounts' | 'viewer'

export interface Membership {
  company_id: string
  role: ErpRole
  company: { id: string; code: string; name: string } | null
}

export interface Profile {
  id: string
  full_name: string | null
  role: ErpRole
  is_active: boolean
}

export const useProfile = () => {
  const user = useSupabaseUser()
  const client = useSupabaseClient()
  const profile = useState<Profile | null>('erp-profile', () => null)
  const memberships = useState<Membership[]>('erp-memberships', () => [])
  const activeCompanyId = useState<string | null>('erp-active-company', () => null)

  const load = async () => {
    if (!user.value) {
      profile.value = null
      memberships.value = []
      activeCompanyId.value = null
      return
    }
    const [{ data: p }, { data: m }] = await Promise.all([
      client
        .from('profiles')
        .select('id, full_name, is_active')
        .eq('id', user.value.id)
        .single(),
      client
        .from('company_members')
        .select('company_id, role, companies(id, code, name)')
        .eq('user_id', user.value.id)
        .eq('is_active', true)
    ])

    memberships.value = (m ?? []).map((row: any) => ({
      company_id: row.company_id,
      role: row.role,
      company: row.companies ?? null
    }))

    if (!activeCompanyId.value || !memberships.value.some(x => x.company_id === activeCompanyId.value)) {
      activeCompanyId.value = memberships.value[0]?.company_id ?? null
    }

    const activeRole: ErpRole =
      memberships.value.find(x => x.company_id === activeCompanyId.value)?.role ?? 'viewer'

    profile.value = p
      ? { id: (p as any).id, full_name: (p as any).full_name, is_active: (p as any).is_active, role: activeRole }
      : null
  }

  const setActiveCompany = async (companyId: string) => {
    activeCompanyId.value = companyId
    await load()
  }

  // Writers: everyone except plain viewers (in the active company).
  const canWrite = computed(() =>
    !!profile.value && ['admin', 'manager', 'store', 'production'].includes(profile.value.role)
  )

  return { profile, memberships, activeCompanyId, setActiveCompany, load, canWrite }
}
