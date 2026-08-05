<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const rows = ref<any[]>([])
const loading = ref(true)
const search = ref('')

const columns = [
  { key: 'code', label: t('parties.columns.code') },
  { key: 'name', label: t('parties.columns.name') },
  { key: 'roles', label: t('parties.columns.roles') },
  { key: 'phone', label: t('parties.columns.phone') },
  { key: 'bin_no', label: t('parties.columns.bin') },
  { key: 'actions', label: '' }
]

const load = async () => {
  loading.value = true
  const { data } = await client.from('parties').select('*').is('deleted_at', null).order('code')
  rows.value = data ?? []
  loading.value = false
}
onMounted(load)

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  if (!q) return rows.value
  return rows.value.filter((p) =>
    p.code.toLowerCase().includes(q) || p.name.toLowerCase().includes(q)
  )
})

const roleBadges = (p: any) => {
  const r: string[] = []
  if (p.is_customer) r.push(t('parties.roles.customer'))
  if (p.is_supplier) r.push(t('parties.roles.supplier'))
  if (p.is_transporter) r.push(t('parties.roles.transporter'))
  if (p.is_bank) r.push(t('parties.roles.bank'))
  if (p.is_foreign) r.push(p.country ? `${t('parties.roles.foreign')} · ${p.country}` : t('parties.roles.foreign'))
  return r
}

const open = ref(false)
const saving = ref(false)
const blank = () => ({
  id: null as string | null,
  code: '', name: '', is_customer: false, is_supplier: false,
  is_transporter: false, is_bank: false,
  phone: '', email: '', address: '', bin_no: '', tin_no: '', is_active: true,
  is_foreign: false, country: ''
})
const form = reactive(blank())
const openNew = () => { Object.assign(form, blank()); open.value = true }
const openEdit = (row: any) => { Object.assign(form, blank(), row); open.value = true }

const removeParty = async (row: any) => {
  const ok = await deleteRecord('parties', row.id, row.name)
  if (ok) await load()
}

const save = async () => {
  saving.value = true
  const payload: any = { ...form }
  delete payload.id
  delete payload.company_id
  delete payload.created_at
  delete payload.updated_at
  delete payload.notes
  try {
    const res = form.id
      ? await client.from('parties').update(payload).eq('id', form.id)
      : await client.from('parties').insert(payload)
    if (res.error) throw res.error
    toast.add({ title: form.id ? t('parties.party_updated') : t('parties.party_created') })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('common.save_failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('parties.kicker')" :title="t('parties.title')" :subtitle="t('parties.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('parties.new_party') }}</UButton>
    </PageHeader>

    <UCard>
      <template #header>
        <UInput v-model="search" icon="i-heroicons-magnifying-glass" :placeholder="t('parties.search_placeholder')" />
      </template>
      <UTable :rows="filtered" :columns="columns" :loading="loading">
        <template #code-data="{ row }">
          <NuxtLink :to="`/parties/${row.id}`" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ row.code }}</NuxtLink>
        </template>
        <template #name-data="{ row }">
          <NuxtLink :to="`/parties/${row.id}`" class="hover:underline dark:text-zinc-200">{{ row.name }}</NuxtLink>
        </template>
        <template #roles-data="{ row }">
          <div class="flex gap-1">
            <UBadge v-for="r in roleBadges(row)" :key="r" size="xs" variant="subtle">{{ r }}</UBadge>
          </div>
        </template>
        <template #bin_no-data="{ row }">{{ row.bin_no || '—' }}</template>
        <template #phone-data="{ row }">{{ row.phone || '—' }}</template>
        <template #actions-data="{ row }">
          <UButton v-if="canWrite" icon="i-heroicons-pencil-square" color="gray" variant="ghost" size="xs" @click="openEdit(row)" />
          <UButton v-if="canWrite" icon="i-heroicons-trash" color="red" variant="ghost" size="xs" @click="removeParty(row)" />
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('parties.empty') }}</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ form.id ? t('parties.edit_party') : t('parties.new_party_title') }}</p></template>
        <div class="grid grid-cols-2 gap-4">
          <UFormGroup :label="t('parties.fields.code')" required><UInput v-model="form.code" /></UFormGroup>
          <UFormGroup :label="t('parties.fields.name')" required><UInput v-model="form.name" /></UFormGroup>
          <div class="col-span-2 flex flex-wrap gap-4">
            <UCheckbox v-model="form.is_customer" :label="t('parties.checkboxes.customer')" />
            <UCheckbox v-model="form.is_supplier" :label="t('parties.checkboxes.supplier')" />
            <UCheckbox v-model="form.is_transporter" :label="t('parties.checkboxes.transporter')" />
            <UCheckbox v-model="form.is_bank" :label="t('parties.checkboxes.bank')" />
            <UCheckbox v-model="form.is_foreign" :label="t('parties.checkboxes.foreign')" />
          </div>
          <UFormGroup :label="t('parties.fields.phone')"><UInput v-model="form.phone" /></UFormGroup>
          <UFormGroup :label="t('parties.fields.email')"><UInput v-model="form.email" /></UFormGroup>
          <UFormGroup :label="t('parties.fields.bin')"><UInput v-model="form.bin_no" /></UFormGroup>
          <UFormGroup :label="t('parties.fields.tin')"><UInput v-model="form.tin_no" /></UFormGroup>
          <UFormGroup :label="t('parties.fields.address')" class="col-span-2"><UInput v-model="form.address" /></UFormGroup>
          <UFormGroup v-if="form.is_foreign" :label="t('parties.fields.country')"><UInput v-model="form.country" :placeholder="t('parties.country_placeholder')" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ t('common.save') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
