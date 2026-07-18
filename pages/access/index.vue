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

// --- New user (admin-provisioned — public signup is disabled) ---
const open = ref(false)
const creating = ref(false)
const created = ref<{ email: string; password: string } | null>(null)
const form = reactive({ full_name: '', email: '', password: '', role: 'viewer' })

const genPassword = () => {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
  form.password = Array.from({ length: 12 }, () => chars[Math.floor(Math.random() * chars.length)]).join('')
}
const openNew = () => {
  Object.assign(form, { full_name: '', email: '', password: '', role: 'viewer' })
  genPassword()
  created.value = null
  open.value = true
}

const createUser = async () => {
  if (!form.email || !form.password) {
    toast.add({ title: 'Email and password are required', color: 'red' }); return
  }
  creating.value = true
  try {
    const { data: { session } } = await client.auth.getSession()
    const { data, error } = await client.functions.invoke('admin-create-user', {
      body: {
        email: form.email, full_name: form.full_name, password: form.password,
        role: form.role, company_id: activeCompanyId.value
      },
      headers: { Authorization: `Bearer ${session?.access_token}` }
    })
    if (error) throw error
    if (data?.error) throw new Error(data.error)
    created.value = { email: form.email, password: form.password }
    toast.add({ title: 'User created' })
    await load()
  } catch (e: any) {
    toast.add({ title: 'Create failed', description: e.message, color: 'red' })
  } finally {
    creating.value = false
  }
}

const copyCreds = async () => {
  if (!created.value) return
  await navigator.clipboard.writeText(`Email: ${created.value.email}\nPassword: ${created.value.password}`)
  toast.add({ title: 'Copied to clipboard' })
}
</script>

<template>
  <div>
    <PageHeader kicker="Admin" title="Access &amp; roles" subtitle="Per-company memberships — enforced by database row-level security, not just the UI">
      <UButton v-if="profile?.role === 'admin'" icon="i-heroicons-user-plus" @click="openNew">New user</UButton>
    </PageHeader>

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
        Public sign-up is disabled — use "New user" above to provision access. Roles
        apply per company; changing your own role is deliberately disabled.
      </p>
    </template>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-md' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New user</p></template>

        <div v-if="created" class="space-y-4">
          <div class="rounded ring-1 ring-amber-500/30 bg-amber-50/40 dark:bg-amber-500/[0.04] p-3 space-y-2">
            <p class="text-sm font-medium text-amber-600 dark:text-amber-400">Share these credentials with the user</p>
            <p class="text-xs text-gray-500 dark:text-zinc-500">This password won't be shown again — copy it now.</p>
            <div class="text-sm space-y-1">
              <p><span class="text-gray-500 dark:text-zinc-500">Email:</span> <span class="num">{{ created.email }}</span></p>
              <p><span class="text-gray-500 dark:text-zinc-500">Password:</span> <span class="num">{{ created.password }}</span></p>
            </div>
            <UButton size="xs" variant="soft" icon="i-heroicons-clipboard-document" @click="copyCreds">Copy</UButton>
          </div>
        </div>

        <div v-else class="space-y-4">
          <UFormGroup label="Full name">
            <UInput v-model="form.full_name" placeholder="Their name" />
          </UFormGroup>
          <UFormGroup label="Email" required>
            <UInput v-model="form.email" type="email" placeholder="them@company.com" />
          </UFormGroup>
          <UFormGroup label="Password" required hint="Auto-generated — editable">
            <div class="flex gap-2">
              <UInput v-model="form.password" class="flex-1" />
              <UButton size="xs" variant="soft" icon="i-heroicons-arrow-path" @click="genPassword" />
            </div>
          </UFormGroup>
          <UFormGroup label="Role in this company">
            <USelect v-model="form.role" :options="roleOptions" />
          </UFormGroup>
        </div>

        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ created ? 'Close' : 'Cancel' }}</UButton>
            <UButton v-if="!created" :loading="creating" @click="createUser">Create user</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
