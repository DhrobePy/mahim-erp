<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { profile, activeCompanyId } = useProfile()
const user = useSupabaseUser()

const rows = ref<any[]>([])
const loading = ref(true)

const roleOptions = ['admin', 'manager', 'store', 'production', 'sales', 'accounts', 'viewer']

// Role capabilities, shown so privileges are explicit rather than folklore.
const privileges: Record<string, string> = {
  admin: 'Everything + member management, CoA, audit trail',
  manager: 'Write access to all operational modules',
  store: 'Stock, GRNs, challans dispatch',
  production: 'BOMs, production orders, completion posting',
  sales: 'Read-only (sales pages) — write coming with quotations',
  accounts: 'Read-only (finance pages)',
  viewer: 'Read-only everywhere'
}

const load = async () => {
  loading.value = true
  const [{ data: profiles }, { data: members }] = await Promise.all([
    client.from('profiles').select('id, full_name, is_active, created_at').order('created_at'),
    client.from('company_members').select('user_id, role, is_active').eq('company_id', activeCompanyId.value)
  ])
  const byUser = new Map((members ?? []).map((m: any) => [m.user_id, m]))
  rows.value = (profiles ?? []).map((p: any) => ({
    ...p,
    membership: byUser.get(p.id) ?? null,
    pendingRole: byUser.get(p.id)?.role ?? null
  }))
  loading.value = false
}
onMounted(load)

const setRole = async (row: any, role: string) => {
  const { error } = await client.from('company_members').upsert({
    user_id: row.id, company_id: activeCompanyId.value, role, is_active: true
  } as any, { onConflict: 'user_id,company_id' })
  if (error) toast.add({ title: 'Update failed', description: error.message, color: 'red' })
  else { toast.add({ title: `${row.full_name || 'User'} → ${role}` }); await load() }
}

const revoke = async (row: any) => {
  const { error } = await client.from('company_members')
    .update({ is_active: false } as any)
    .eq('user_id', row.id).eq('company_id', activeCompanyId.value)
  if (error) toast.add({ title: 'Revoke failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Access revoked' }); await load() }
}
</script>

<template>
  <div>
    <PageHeader kicker="Admin" title="Access &amp; roles" subtitle="Per-company memberships — enforced by database row-level security, not just the UI" />

    <UCard v-if="profile?.role !== 'admin'">
      <p class="text-sm text-gray-500 py-4 text-center">Only admins can manage access.</p>
    </UCard>

    <template v-else>
      <UCard class="mb-4">
        <UTable
          :rows="rows" :loading="loading"
          :columns="[
            { key: 'full_name', label: 'User' },
            { key: 'role', label: 'Role in this company' },
            { key: 'privilege', label: 'Privileges' },
            { key: 'actions', label: '' }
          ]"
        >
          <template #full_name-data="{ row }">
            <div class="flex items-center gap-2">
              <UAvatar :alt="row.full_name || '?'" size="2xs" :ui="{ background: 'bg-zinc-700' }" />
              <span class="dark:text-zinc-200">{{ row.full_name || row.id.slice(0, 8) }}</span>
              <UBadge v-if="row.id === user?.id" size="xs" variant="subtle">you</UBadge>
            </div>
          </template>
          <template #role-data="{ row }">
            <div class="flex items-center gap-2">
              <USelect
                :model-value="row.pendingRole"
                :options="roleOptions"
                placeholder="No access"
                size="xs"
                class="w-32"
                :disabled="row.id === user?.id"
                @update:model-value="(v: string) => setRole(row, v)"
              />
              <UBadge
                v-if="!row.membership || row.membership.is_active === false"
                size="xs" variant="subtle" color="red"
              >no access</UBadge>
            </div>
          </template>
          <template #privilege-data="{ row }">
            <span class="text-xs text-gray-500 dark:text-zinc-500">
              {{ row.membership?.is_active ? privileges[row.membership.role] : '—' }}
            </span>
          </template>
          <template #actions-data="{ row }">
            <UButton
              v-if="row.membership?.is_active && row.id !== user?.id"
              size="xs" variant="soft" color="red" @click="revoke(row)"
            >Revoke</UButton>
          </template>
        </UTable>
      </UCard>

      <p class="text-xs text-gray-400 dark:text-zinc-600">
        New users appear here after they sign up at the login screen — they see no data
        until a role is assigned. Roles apply per company; changing your own role is
        deliberately disabled.
      </p>
    </template>
  </div>
</template>
