<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()

const rows = ref<any[]>([])
const loading = ref(true)
const search = ref('')

const columns = [
  { key: 'code', label: 'Code' },
  { key: 'name', label: 'Name' },
  { key: 'roles', label: 'Roles' },
  { key: 'phone', label: 'Phone' },
  { key: 'bin_no', label: 'BIN' },
  { key: 'actions', label: '' }
]

const load = async () => {
  loading.value = true
  const { data } = await client.from('parties').select('*').order('code')
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
  if (p.is_customer) r.push('customer')
  if (p.is_supplier) r.push('supplier')
  if (p.is_transporter) r.push('transporter')
  if (p.is_bank) r.push('bank')
  return r
}

const open = ref(false)
const saving = ref(false)
const blank = () => ({
  id: null as string | null,
  code: '', name: '', is_customer: false, is_supplier: false,
  is_transporter: false, is_bank: false,
  phone: '', email: '', address: '', bin_no: '', tin_no: '', is_active: true
})
const form = reactive(blank())
const openNew = () => { Object.assign(form, blank()); open.value = true }
const openEdit = (row: any) => { Object.assign(form, blank(), row); open.value = true }

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
    toast.add({ title: form.id ? 'Party updated' : 'Party created' })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: 'Save failed', description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div>
    <PageHeader kicker="Procurement" title="Parties" subtitle="Customers, suppliers, transporters &amp; banks">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New party</UButton>
    </PageHeader>

    <UCard>
      <template #header>
        <UInput v-model="search" icon="i-heroicons-magnifying-glass" placeholder="Search code or name…" />
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
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">No parties yet.</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ form.id ? 'Edit party' : 'New party' }}</p></template>
        <div class="grid grid-cols-2 gap-4">
          <UFormGroup label="Code" required><UInput v-model="form.code" /></UFormGroup>
          <UFormGroup label="Name" required><UInput v-model="form.name" /></UFormGroup>
          <div class="col-span-2 flex flex-wrap gap-4">
            <UCheckbox v-model="form.is_customer" label="Customer" />
            <UCheckbox v-model="form.is_supplier" label="Supplier" />
            <UCheckbox v-model="form.is_transporter" label="Transporter" />
            <UCheckbox v-model="form.is_bank" label="Bank" />
          </div>
          <UFormGroup label="Phone"><UInput v-model="form.phone" /></UFormGroup>
          <UFormGroup label="Email"><UInput v-model="form.email" /></UFormGroup>
          <UFormGroup label="BIN (VAT reg.)"><UInput v-model="form.bin_no" /></UFormGroup>
          <UFormGroup label="TIN"><UInput v-model="form.tin_no" /></UFormGroup>
          <UFormGroup label="Address" class="col-span-2"><UInput v-model="form.address" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">Cancel</UButton>
            <UButton :loading="saving" @click="save">Save</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
