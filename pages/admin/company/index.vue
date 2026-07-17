<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { profile, activeCompanyId, memberships, setActiveCompany } = useProfile()

const company = ref<any>(null)
const children = ref<any[]>([])
const loading = ref(true)
const saving = ref(false)
const uploadingLogo = ref(false)

const load = async () => {
  loading.value = true
  const [{ data: c }, { data: kids }] = await Promise.all([
    client.from('companies').select('*').eq('id', activeCompanyId.value).single(),
    client.from('companies').select('*').eq('parent_company_id', activeCompanyId.value).order('created_at')
  ])
  company.value = c
  children.value = kids ?? []
  loading.value = false
}
onMounted(load)

const logoUrl = computed(() =>
  company.value?.logo_path
    ? client.storage.from('company-assets').getPublicUrl(company.value.logo_path).data.publicUrl
    : null)

const saveProfile = async () => {
  saving.value = true
  const { error } = await client.from('companies').update({
    name: company.value.name, legal_name: company.value.legal_name, address: company.value.address,
    bin_no: company.value.bin_no, tin_no: company.value.tin_no, phone: company.value.phone,
    email: company.value.email, website: company.value.website
  } as any).eq('id', activeCompanyId.value)
  if (error) toast.add({ title: 'Save failed', description: error.message, color: 'red' })
  else toast.add({ title: 'Company profile updated' })
  saving.value = false
}

const onLogo = async (ev: Event) => {
  const file = (ev.target as HTMLInputElement).files?.[0]
  if (!file) return
  uploadingLogo.value = true
  try {
    const path = `${activeCompanyId.value}/logo-${Date.now()}-${file.name}`
    const up = await client.storage.from('company-assets').upload(path, file, { upsert: true })
    if (up.error) throw up.error
    const { error } = await client.from('companies').update({ logo_path: path } as any).eq('id', activeCompanyId.value)
    if (error) throw error
    company.value.logo_path = path
    toast.add({ title: 'Logo updated' })
  } catch (e: any) {
    toast.add({ title: 'Upload failed', description: e.message, color: 'red' })
  } finally {
    uploadingLogo.value = false
    ;(ev.target as HTMLInputElement).value = ''
  }
}

// --- New subsidiary ---
const open = ref(false)
const subSaving = ref(false)
const sub = reactive({ name: '', code: '', legal_name: '' })
const openNew = () => { Object.assign(sub, { name: '', code: '', legal_name: '' }); open.value = true }
const createSub = async () => {
  if (!sub.name || !sub.code) { toast.add({ title: 'Name and code are required', color: 'red' }); return }
  subSaving.value = true
  try {
    const { error } = await client.rpc('create_child_company', {
      p_name: sub.name, p_code: sub.code, p_legal_name: sub.legal_name || null, p_parent_id: activeCompanyId.value
    } as any)
    if (error) throw error
    toast.add({ title: `${sub.name} created` })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: 'Failed', description: e.message, color: 'red' })
  } finally {
    subSaving.value = false
  }
}

const switchTo = async (companyId: string) => {
  await setActiveCompany(companyId)
  toast.add({ title: 'Switched active company' })
  await load()
}
</script>

<template>
  <div v-if="company">
    <PageHeader kicker="Admin" title="Company &amp; structure" subtitle="Profile, branding and the group hierarchy" />

    <div class="grid grid-cols-1 xl:grid-cols-2 gap-4">
      <UCard>
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Profile</p></template>
        <div class="flex items-center gap-4 mb-4">
          <div class="w-16 h-16 rounded ring-1 ring-gray-200 dark:ring-zinc-800 flex items-center justify-center overflow-hidden bg-white shrink-0">
            <img v-if="logoUrl" :src="logoUrl" class="w-full h-full object-contain" alt="Company logo">
            <UIcon v-else name="i-heroicons-building-office-2" class="text-2xl text-gray-300" />
          </div>
          <label class="cursor-pointer">
            <span class="text-xs px-2.5 py-1.5 rounded bg-gray-100 dark:bg-zinc-800 text-gray-700 dark:text-zinc-300 hover:bg-gray-200 dark:hover:bg-zinc-700 font-medium">
              {{ uploadingLogo ? 'Uploading…' : 'Upload logo' }}
            </span>
            <input type="file" accept="image/*" class="hidden" :disabled="uploadingLogo" @change="onLogo">
          </label>
        </div>
        <div class="grid grid-cols-2 gap-3">
          <UFormGroup label="Trading name"><UInput v-model="company.name" /></UFormGroup>
          <UFormGroup label="Legal name"><UInput v-model="company.legal_name" /></UFormGroup>
          <UFormGroup label="Address" class="col-span-2"><UInput v-model="company.address" /></UFormGroup>
          <UFormGroup label="BIN (VAT reg.)"><UInput v-model="company.bin_no" /></UFormGroup>
          <UFormGroup label="TIN"><UInput v-model="company.tin_no" /></UFormGroup>
          <UFormGroup label="Phone"><UInput v-model="company.phone" /></UFormGroup>
          <UFormGroup label="Email"><UInput v-model="company.email" /></UFormGroup>
          <UFormGroup label="Website" class="col-span-2"><UInput v-model="company.website" /></UFormGroup>
        </div>
        <div class="flex justify-end mt-4">
          <UButton :loading="saving" @click="saveProfile">Save profile</UButton>
        </div>
      </UCard>

      <UCard>
        <template #header>
          <div class="flex items-center justify-between">
            <p class="microlabel text-gray-400 dark:text-zinc-500">Group structure</p>
            <UButton v-if="profile?.role === 'admin'" size="xs" icon="i-heroicons-plus" @click="openNew">New subsidiary</UButton>
          </div>
        </template>
        <div class="text-[13px] mb-3">
          <div class="flex items-center gap-2 py-1.5 px-2 rounded bg-amber-50/60 dark:bg-amber-500/[0.06]">
            <UIcon name="i-heroicons-star" class="text-amber-500 text-sm" />
            <span class="font-medium dark:text-zinc-100">{{ company.name }}</span>
            <UBadge size="xs" variant="subtle">mother</UBadge>
            <UBadge v-if="activeCompanyId === company.id" size="xs" color="green" variant="subtle" class="ml-auto">active</UBadge>
          </div>
          <div v-for="k in children" :key="k.id" class="flex items-center gap-2 py-1.5 pl-6 pr-2">
            <UIcon name="i-heroicons-arrow-turn-down-right" class="text-gray-400 text-sm" />
            <span class="dark:text-zinc-200">{{ k.name }}</span>
            <span class="num text-[11px] text-gray-400 dark:text-zinc-600">{{ k.code }}</span>
            <UButton
              v-if="memberships.some(m => m.company_id === k.id) && activeCompanyId !== k.id"
              size="2xs" variant="soft" class="ml-auto" @click="switchTo(k.id)"
            >Switch to</UButton>
            <UBadge v-else-if="activeCompanyId === k.id" size="xs" color="green" variant="subtle" class="ml-auto">active</UBadge>
          </div>
          <p v-if="!children.length" class="text-gray-400 text-center py-3">No subsidiaries yet.</p>
        </div>
        <UButton
          v-if="activeCompanyId !== company.id"
          size="xs" variant="soft" block @click="switchTo(company.id)"
        >Switch to mother company</UButton>
      </UCard>
    </div>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New subsidiary under {{ company.name }}</p></template>
        <div class="space-y-4">
          <UFormGroup label="Trading name" required><UInput v-model="sub.name" /></UFormGroup>
          <UFormGroup label="Code" required hint="short, unique e.g. MAHIM-TRD"><UInput v-model="sub.code" /></UFormGroup>
          <UFormGroup label="Legal name"><UInput v-model="sub.legal_name" placeholder="defaults to trading name" /></UFormGroup>
          <p class="text-xs text-gray-400 dark:text-zinc-600">
            A full chart of accounts is seeded automatically, and you become admin of the new company.
          </p>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">Cancel</UButton>
            <UButton :loading="subSaving" @click="createSub">Create subsidiary</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
