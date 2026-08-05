<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { profile, activeCompanyId } = useProfile()
const user = useSupabaseUser()
const { groupedModules, load: loadPermissionCatalog, loadFor, saveFor } = usePermissions()
const { t } = useI18n()

const rows = ref<any[]>([])
const loading = ref(true)

// Only two tiers now: admin (everything, manages permissions) or member
// (starts with nothing but the dashboard — exact capabilities are the
// per-page grants below, not a predefined bundle).
const roleOptions = computed(() => [
  { value: 'admin', label: t('system.access.role_admin') },
  { value: 'viewer', label: t('system.access.role_member') }
])

const load = async () => {
  loading.value = true
  const [{ data: profiles }, { data: members }] = await Promise.all([
    client.from('profiles').select('id, full_name, email, is_active, created_at').order('created_at'),
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
onMounted(() => { load(); loadPermissionCatalog() })

const setRole = async (row: any, role: string) => {
  const { error } = await client.from('company_members').upsert({
    user_id: row.id, company_id: activeCompanyId.value, role, is_active: true
  } as any, { onConflict: 'user_id,company_id' })
  if (error) toast.add({ title: t('system.access.toast.update_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('system.access.toast.role_changed', { name: row.full_name || t('system.access.user_fallback'), role }) }); await load() }
}

const revoke = async (row: any) => {
  const { error } = await client.from('company_members')
    .update({ is_active: false } as any)
    .eq('user_id', row.id).eq('company_id', activeCompanyId.value)
  if (error) toast.add({ title: t('system.access.toast.revoke_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('system.access.toast.access_revoked') }); await load() }
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
    toast.add({ title: t('system.access.toast.email_password_required'), color: 'red' }); return
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
    toast.add({ title: t('system.access.toast.user_created') })
    await load()
  } catch (e: any) {
    toast.add({ title: t('system.access.toast.create_failed'), description: e.message, color: 'red' })
  } finally {
    creating.value = false
  }
}

const copyCreds = async () => {
  if (!created.value) return
  await navigator.clipboard.writeText(
    `${t('system.access.new_user_slideover.email_label')} ${created.value.email}\n${t('system.access.new_user_slideover.password_label')} ${created.value.password}`
  )
  toast.add({ title: t('system.access.toast.copied') })
}

// --- Per-user permission editor (the actual "not predefined" access list) ---
const permOpen = ref(false)
const permSaving = ref(false)
const permTarget = ref<any>(null)
const permState = ref<Record<string, { view: boolean; write: boolean }>>({})

const openPermissions = async (row: any) => {
  permTarget.value = row
  permState.value = await loadFor(row.id, activeCompanyId.value as string)
  permOpen.value = true
}
// Write implies view — no point letting someone edit a page they can't see.
const toggleWrite = (key: string, v: boolean) => {
  permState.value[key].write = v
  if (v) permState.value[key].view = true
}
const toggleView = (key: string, v: boolean) => {
  permState.value[key].view = v
  if (!v) permState.value[key].write = false
}
const savePermissions = async () => {
  permSaving.value = true
  try {
    await saveFor(permTarget.value.id, activeCompanyId.value as string, permState.value)
    toast.add({ title: t('system.access.toast.permissions_updated', { name: permTarget.value.full_name || t('system.access.user_fallback') }) })
    permOpen.value = false
  } catch (e: any) {
    toast.add({ title: t('common.save_failed'), description: e.message, color: 'red' })
  } finally {
    permSaving.value = false
  }
}

// --- Edit user (name / email / password reset) ---
const editOpen = ref(false)
const editSaving = ref(false)
const editTarget = ref<any>(null)
const editForm = reactive({ full_name: '', email: '', password: '' })

const openEdit = (row: any) => {
  editTarget.value = row
  Object.assign(editForm, { full_name: row.full_name ?? '', email: row.email ?? '', password: '' })
  editOpen.value = true
}
const genEditPassword = () => {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
  editForm.password = Array.from({ length: 12 }, () => chars[Math.floor(Math.random() * chars.length)]).join('')
}
const saveEdit = async () => {
  editSaving.value = true
  try {
    const { data: { session } } = await client.auth.getSession()
    const { data, error } = await client.functions.invoke('admin-update-user', {
      body: {
        user_id: editTarget.value.id, company_id: activeCompanyId.value,
        full_name: editForm.full_name, email: editForm.email,
        password: editForm.password || undefined
      },
      headers: { Authorization: `Bearer ${session?.access_token}` }
    })
    if (error) throw error
    if (data?.error) throw new Error(data.error)
    toast.add({ title: t('system.access.toast.user_updated') })
    editOpen.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('system.access.toast.update_failed'), description: e.message, color: 'red' })
  } finally {
    editSaving.value = false
  }
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('nav.sections.admin')" :title="t('system.access.title')" :subtitle="t('system.access.subtitle')">
      <UButton v-if="profile?.role === 'admin'" icon="i-heroicons-user-plus" @click="openNew">{{ t('system.access.new_user') }}</UButton>
    </PageHeader>

    <UCard v-if="profile?.role !== 'admin'">
      <p class="text-sm text-gray-500 py-4 text-center">{{ t('system.access.admin_only') }}</p>
    </UCard>

    <template v-else>
      <UCard class="mb-4">
        <UTable
          :rows="rows" :loading="loading"
          :columns="[
            { key: 'full_name', label: t('system.access.columns.user') },
            { key: 'role', label: t('system.access.columns.tier') },
            { key: 'actions', label: '' }
          ]"
        >
          <template #full_name-data="{ row }">
            <div class="flex items-center gap-2">
              <UAvatar :alt="row.full_name || '?'" size="2xs" :ui="{ background: 'bg-zinc-700' }" />
              <span class="dark:text-zinc-200">{{ row.full_name || row.id.slice(0, 8) }}</span>
              <UBadge v-if="row.id === user?.id" size="xs" variant="subtle">{{ t('system.access.you_badge') }}</UBadge>
            </div>
          </template>
          <template #role-data="{ row }">
            <div class="flex items-center gap-2">
              <USelect
                :model-value="row.pendingRole"
                :options="roleOptions"
                option-attribute="label" value-attribute="value"
                :placeholder="t('system.access.no_access_placeholder')"
                size="xs"
                class="w-52"
                :disabled="row.id === user?.id"
                @update:model-value="(v: string) => setRole(row, v)"
              />
              <UBadge
                v-if="!row.membership || row.membership.is_active === false"
                size="xs" variant="subtle" color="red"
              >{{ t('system.access.no_access_badge') }}</UBadge>
            </div>
          </template>
          <template #actions-data="{ row }">
            <div class="flex items-center gap-2 justify-end">
              <UButton
                v-if="row.membership?.is_active"
                size="xs" variant="soft" icon="i-heroicons-pencil-square" @click="openEdit(row)"
              >{{ t('common.edit') }}</UButton>
              <UButton
                v-if="row.membership?.is_active && row.membership.role !== 'admin'"
                size="xs" variant="soft" icon="i-heroicons-adjustments-horizontal" @click="openPermissions(row)"
              >{{ t('system.access.permissions') }}</UButton>
              <UButton
                v-if="row.membership?.is_active && row.id !== user?.id"
                size="xs" variant="soft" color="red" @click="revoke(row)"
              >{{ t('system.access.revoke') }}</UButton>
            </div>
          </template>
        </UTable>
      </UCard>

      <p class="text-xs text-gray-400 dark:text-zinc-600">
        {{ t('system.access.footer_note') }}
      </p>
    </template>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-md' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('system.access.new_user') }}</p></template>

        <div v-if="created" class="space-y-4">
          <div class="rounded ring-1 ring-amber-500/30 bg-amber-50/40 dark:bg-amber-500/[0.04] p-3 space-y-2">
            <p class="text-sm font-medium text-amber-600 dark:text-amber-400">{{ t('system.access.new_user_slideover.share_creds') }}</p>
            <p class="text-xs text-gray-500 dark:text-zinc-500">{{ t('system.access.new_user_slideover.password_note') }}</p>
            <div class="text-sm space-y-1">
              <p><span class="text-gray-500 dark:text-zinc-500">{{ t('system.access.new_user_slideover.email_label') }}</span> <span class="num">{{ created.email }}</span></p>
              <p><span class="text-gray-500 dark:text-zinc-500">{{ t('system.access.new_user_slideover.password_label') }}</span> <span class="num">{{ created.password }}</span></p>
            </div>
            <UButton size="xs" variant="soft" icon="i-heroicons-clipboard-document" @click="copyCreds">{{ t('system.access.new_user_slideover.copy') }}</UButton>
          </div>
        </div>

        <div v-else class="space-y-4">
          <UFormGroup :label="t('system.access.new_user_slideover.full_name')">
            <UInput v-model="form.full_name" :placeholder="t('system.access.new_user_slideover.full_name_placeholder')" />
          </UFormGroup>
          <UFormGroup :label="t('system.access.new_user_slideover.email')" required>
            <UInput v-model="form.email" type="email" :placeholder="t('system.access.new_user_slideover.email_placeholder')" />
          </UFormGroup>
          <UFormGroup :label="t('system.access.new_user_slideover.password')" required :hint="t('system.access.new_user_slideover.password_hint')">
            <div class="flex gap-2">
              <UInput v-model="form.password" class="flex-1" />
              <UButton size="xs" variant="soft" icon="i-heroicons-arrow-path" @click="genPassword" />
            </div>
          </UFormGroup>
          <UFormGroup :label="t('system.access.new_user_slideover.role')">
            <USelect v-model="form.role" :options="roleOptions" option-attribute="label" value-attribute="value" />
          </UFormGroup>
        </div>

        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ created ? t('common.close') : t('common.cancel') }}</UButton>
            <UButton v-if="!created" :loading="creating" @click="createUser">{{ t('system.access.new_user_slideover.create_user') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="permOpen" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header>
          <p class="font-medium">{{ t('system.access.permissions_slideover.title', { name: permTarget?.full_name || t('system.access.user_fallback') }) }}</p>
          <p class="text-xs text-gray-500">{{ t('system.access.permissions_slideover.subtitle') }}</p>
        </template>

        <div class="space-y-5">
          <div v-for="(mods, group) in groupedModules" :key="group">
            <p class="microlabel text-amber-600 dark:text-amber-400 mb-2">{{ group }}</p>
            <div class="space-y-1.5">
              <div
                v-for="m in mods" :key="m.key"
                class="flex items-center justify-between rounded ring-1 ring-gray-100 dark:ring-zinc-800 px-3 py-2"
              >
                <span class="text-sm dark:text-zinc-200">{{ m.label }}</span>
                <div class="flex items-center gap-4">
                  <UCheckbox
                    :model-value="permState[m.key]?.view" :label="t('system.access.permissions_slideover.view')"
                    @update:model-value="(v: boolean) => toggleView(m.key, v)"
                  />
                  <UCheckbox
                    :model-value="permState[m.key]?.write" :label="t('system.access.permissions_slideover.write')"
                    @update:model-value="(v: boolean) => toggleWrite(m.key, v)"
                  />
                </div>
              </div>
            </div>
          </div>
        </div>

        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="permOpen = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="permSaving" @click="savePermissions">{{ t('system.access.permissions_slideover.save') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="editOpen" :ui="{ width: 'w-screen max-w-md' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('system.access.edit_slideover.title') }}</p></template>

        <div class="space-y-4">
          <UFormGroup :label="t('system.access.edit_slideover.full_name')">
            <UInput v-model="editForm.full_name" :placeholder="t('system.access.edit_slideover.full_name_placeholder')" />
          </UFormGroup>
          <UFormGroup :label="t('system.access.edit_slideover.email')">
            <UInput v-model="editForm.email" type="email" :placeholder="t('system.access.edit_slideover.email_placeholder')" />
          </UFormGroup>
          <UFormGroup :label="t('system.access.edit_slideover.new_password')" :hint="t('system.access.edit_slideover.new_password_hint')">
            <div class="flex gap-2">
              <UInput v-model="editForm.password" :placeholder="t('system.access.edit_slideover.new_password_placeholder')" class="flex-1" />
              <UButton size="xs" variant="soft" icon="i-heroicons-arrow-path" @click="genEditPassword" />
            </div>
          </UFormGroup>
        </div>

        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="editOpen = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="editSaving" @click="saveEdit">{{ t('system.access.edit_slideover.save') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
