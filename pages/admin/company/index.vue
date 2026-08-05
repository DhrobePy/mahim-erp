<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { profile, activeCompanyId, memberships, setActiveCompany } = useProfile()
const { t } = useI18n()

const company = ref<any>(null)
const children = ref<any[]>([])
const loading = ref(true)
const saving = ref(false)
const savingCosting = ref(false)
const uploadingLogo = ref(false)

const impliedOverheadPct = computed(() => {
  const mat = Number(company.value?.ref_material_cost) || 0
  const fac = Number(company.value?.ref_factory_cost) || 0
  return mat > 0 ? Math.round((fac / mat) * 1000) / 10 : 0
})

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
  if (error) toast.add({ title: t('common.save_failed'), description: error.message, color: 'red' })
  else toast.add({ title: t('admin.company.toasts.profile_updated') })
  saving.value = false
}

const saveCosting = async () => {
  savingCosting.value = true
  const { error } = await client.from('companies').update({
    ref_material_cost: company.value.ref_material_cost,
    ref_factory_cost: company.value.ref_factory_cost,
    default_margin_pct: company.value.default_margin_pct
  } as any).eq('id', activeCompanyId.value)
  if (error) toast.add({ title: t('common.save_failed'), description: error.message, color: 'red' })
  else toast.add({ title: t('admin.company.toasts.costing_updated') })
  savingCosting.value = false
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
    toast.add({ title: t('admin.company.toasts.logo_updated') })
  } catch (e: any) {
    toast.add({ title: t('admin.company.toasts.upload_failed'), description: e.message, color: 'red' })
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
  if (!sub.name || !sub.code) { toast.add({ title: t('admin.company.toasts.name_code_required'), color: 'red' }); return }
  subSaving.value = true
  try {
    const { error } = await client.rpc('create_child_company', {
      p_name: sub.name, p_code: sub.code, p_legal_name: sub.legal_name || null, p_parent_id: activeCompanyId.value
    } as any)
    if (error) throw error
    toast.add({ title: t('admin.company.toasts.created', { name: sub.name }) })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('admin.company.toasts.failed'), description: e.message, color: 'red' })
  } finally {
    subSaving.value = false
  }
}

const switchTo = async (companyId: string) => {
  await setActiveCompany(companyId)
  toast.add({ title: t('admin.company.toasts.switched') })
  await load()
}
</script>

<template>
  <div v-if="company">
    <PageHeader :kicker="t('admin.company.kicker')" :title="t('admin.company.title')" :subtitle="t('admin.company.subtitle')" />

    <div class="grid grid-cols-1 xl:grid-cols-2 gap-4">
      <UCard>
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('admin.company.profile.card_title') }}</p></template>
        <div class="flex items-center gap-4 mb-4">
          <div class="w-16 h-16 rounded ring-1 ring-gray-200 dark:ring-zinc-800 flex items-center justify-center overflow-hidden bg-white shrink-0">
            <img v-if="logoUrl" :src="logoUrl" class="w-full h-full object-contain" alt="Company logo">
            <UIcon v-else name="i-heroicons-building-office-2" class="text-2xl text-gray-300" />
          </div>
          <label class="cursor-pointer">
            <span class="text-xs px-2.5 py-1.5 rounded bg-gray-100 dark:bg-zinc-800 text-gray-700 dark:text-zinc-300 hover:bg-gray-200 dark:hover:bg-zinc-700 font-medium">
              {{ uploadingLogo ? t('admin.company.profile.uploading') : t('admin.company.profile.upload_logo') }}
            </span>
            <input type="file" accept="image/*" class="hidden" :disabled="uploadingLogo" @change="onLogo">
          </label>
        </div>
        <div class="grid grid-cols-2 gap-3">
          <UFormGroup :label="t('admin.company.profile.trading_name')"><UInput v-model="company.name" /></UFormGroup>
          <UFormGroup :label="t('admin.company.profile.legal_name')"><UInput v-model="company.legal_name" /></UFormGroup>
          <UFormGroup :label="t('admin.company.profile.address')" class="col-span-2"><UInput v-model="company.address" /></UFormGroup>
          <UFormGroup :label="t('admin.company.profile.bin')"><UInput v-model="company.bin_no" /></UFormGroup>
          <UFormGroup :label="t('admin.company.profile.tin')"><UInput v-model="company.tin_no" /></UFormGroup>
          <UFormGroup :label="t('admin.company.profile.phone')"><UInput v-model="company.phone" /></UFormGroup>
          <UFormGroup :label="t('admin.company.profile.email')"><UInput v-model="company.email" /></UFormGroup>
          <UFormGroup :label="t('admin.company.profile.website')" class="col-span-2"><UInput v-model="company.website" /></UFormGroup>
        </div>
        <div class="flex justify-end mt-4">
          <UButton :loading="saving" @click="saveProfile">{{ t('admin.company.profile.save') }}</UButton>
        </div>
      </UCard>

      <UCard>
        <template #header>
          <div class="flex items-center justify-between">
            <p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('admin.company.structure.card_title') }}</p>
            <UButton v-if="profile?.role === 'admin'" size="xs" icon="i-heroicons-plus" @click="openNew">{{ t('admin.company.structure.new_subsidiary_btn') }}</UButton>
          </div>
        </template>
        <div class="text-[13px] mb-3">
          <div class="flex items-center gap-2 py-1.5 px-2 rounded bg-amber-50/60 dark:bg-amber-500/[0.06]">
            <UIcon name="i-heroicons-star" class="text-amber-500 text-sm" />
            <span class="font-medium dark:text-zinc-100">{{ company.name }}</span>
            <UBadge size="xs" variant="subtle">{{ t('admin.company.structure.mother_badge') }}</UBadge>
            <UBadge v-if="activeCompanyId === company.id" size="xs" color="green" variant="subtle" class="ml-auto">{{ t('admin.company.structure.active_badge') }}</UBadge>
          </div>
          <div v-for="k in children" :key="k.id" class="flex items-center gap-2 py-1.5 pl-6 pr-2">
            <UIcon name="i-heroicons-arrow-turn-down-right" class="text-gray-400 text-sm" />
            <span class="dark:text-zinc-200">{{ k.name }}</span>
            <span class="num text-[11px] text-gray-400 dark:text-zinc-600">{{ k.code }}</span>
            <UButton
              v-if="memberships.some(m => m.company_id === k.id) && activeCompanyId !== k.id"
              size="2xs" variant="soft" class="ml-auto" @click="switchTo(k.id)"
            >{{ t('admin.company.structure.switch_to') }}</UButton>
            <UBadge v-else-if="activeCompanyId === k.id" size="xs" color="green" variant="subtle" class="ml-auto">{{ t('admin.company.structure.active_badge') }}</UBadge>
          </div>
          <p v-if="!children.length" class="text-gray-400 text-center py-3">{{ t('admin.company.structure.no_subsidiaries') }}</p>
        </div>
        <UButton
          v-if="activeCompanyId !== company.id"
          size="xs" variant="soft" block @click="switchTo(company.id)"
        >{{ t('admin.company.structure.switch_to_mother') }}</UButton>
      </UCard>

      <UCard class="xl:col-span-2">
        <template #header>
          <p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('admin.company.costing.card_title') }}</p>
          <p class="text-xs text-gray-500 mt-0.5">{{ t('admin.company.costing.card_subtitle') }}</p>
        </template>
        <div class="grid grid-cols-2 gap-3">
          <UFormGroup :label="t('admin.company.costing.ref_material_cost')" :hint="t('admin.company.costing.ref_material_cost_hint')">
            <UInput v-model.number="company.ref_material_cost" type="number" />
          </UFormGroup>
          <UFormGroup :label="t('admin.company.costing.ref_factory_cost')" :hint="t('admin.company.costing.ref_factory_cost_hint')">
            <UInput v-model.number="company.ref_factory_cost" type="number" />
          </UFormGroup>
          <UFormGroup :label="t('admin.company.costing.implied_overhead_pct')" class="col-span-2">
            <div class="num text-lg font-semibold text-emerald-600 dark:text-emerald-400 py-1.5">{{ impliedOverheadPct }}%</div>
          </UFormGroup>
          <UFormGroup :label="t('admin.company.costing.default_margin_pct')" class="col-span-2" :hint="t('admin.company.costing.default_margin_pct_hint')">
            <UInput v-model.number="company.default_margin_pct" type="number" step="0.1" class="w-40" />
          </UFormGroup>
        </div>
        <div class="flex justify-end mt-4">
          <UButton :loading="savingCosting" @click="saveCosting">{{ t('admin.company.costing.save') }}</UButton>
        </div>
      </UCard>
    </div>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('admin.company.new_subsidiary.title', { name: company.name }) }}</p></template>
        <div class="space-y-4">
          <UFormGroup :label="t('admin.company.new_subsidiary.trading_name')" required><UInput v-model="sub.name" /></UFormGroup>
          <UFormGroup :label="t('admin.company.new_subsidiary.code')" required :hint="t('admin.company.new_subsidiary.code_hint')"><UInput v-model="sub.code" /></UFormGroup>
          <UFormGroup :label="t('admin.company.new_subsidiary.legal_name')"><UInput v-model="sub.legal_name" :placeholder="t('admin.company.new_subsidiary.legal_name_placeholder')" /></UFormGroup>
          <p class="text-xs text-gray-400 dark:text-zinc-600">
            {{ t('admin.company.new_subsidiary.note') }}
          </p>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="subSaving" @click="createSub">{{ t('admin.company.new_subsidiary.create') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
