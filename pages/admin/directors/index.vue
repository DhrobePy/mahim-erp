<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { num } = useFmt()

const rows = ref<any[]>([])
const loading = ref(true)

const columns = [
  { key: 'full_name', label: 'Name' },
  { key: 'designation', label: 'Designation' },
  { key: 'nid_no', label: 'NID' },
  { key: 'shares', label: 'Shares' },
  { key: 'appointment_date', label: 'Appointed' },
  { key: 'status', label: '' },
  { key: 'actions', label: '' }
]

const designationOptions = [
  { value: 'chairman', label: 'Chairman' },
  { value: 'managing_director', label: 'Managing Director' },
  { value: 'director', label: 'Director' },
  { value: 'partner', label: 'Partner' },
  { value: 'company_secretary', label: 'Company Secretary' }
]
const designationLabel: Record<string, string> = Object.fromEntries(designationOptions.map((o) => [o.value, o.label]))

const load = async () => {
  loading.value = true
  const { data } = await client.from('company_directors').select('*').order('appointment_date')
  rows.value = data ?? []
  loading.value = false
}
onMounted(load)

const totalShares = computed(() => rows.value.filter((r) => r.is_active).reduce((s, r) => s + Number(r.shares_held), 0))
const sharePct = (r: any) => totalShares.value ? ((Number(r.shares_held) / totalShares.value) * 100).toFixed(1) : '0.0'

const open = ref(false)
const saving = ref(false)
const blank = () => ({
  id: null as string | null, full_name: '', designation: 'director', father_or_spouse_name: '',
  nid_no: '', tin_no: '', nationality: 'Bangladeshi', address: '', phone: '', email: '',
  shares_held: 0, share_face_value: 100, appointment_date: new Date().toISOString().slice(0, 10),
  resignation_date: null as string | null, is_active: true
})
const form = reactive(blank())
const openNew = () => { Object.assign(form, blank()); open.value = true }
const openEdit = (row: any) => { Object.assign(form, blank(), row); open.value = true }

const save = async () => {
  if (!form.full_name) { toast.add({ title: 'Name is required', color: 'red' }); return }
  saving.value = true
  const payload: any = { ...form }
  delete payload.id
  try {
    const res = form.id
      ? await client.from('company_directors').update(payload).eq('id', form.id)
      : await client.from('company_directors').insert(payload)
    if (res.error) throw res.error
    toast.add({ title: form.id ? 'Updated' : 'Director added' })
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
    <PageHeader kicker="Admin" title="Directors &amp; partners" subtitle="Governance register — feeds RJSC Form XII and Schedule X">
      <UButton icon="i-heroicons-printer" variant="soft" to="/print/rjsc/form12" target="_blank">Form XII</UButton>
      <UButton icon="i-heroicons-printer" variant="soft" to="/print/rjsc/schedulex" target="_blank">Schedule X</UButton>
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New director</UButton>
    </PageHeader>

    <UCard>
      <UTable :rows="rows" :columns="columns" :loading="loading">
        <template #full_name-data="{ row }">
          <button class="hover:underline cursor-pointer dark:text-zinc-200" @click="openEdit(row)">{{ row.full_name }}</button>
        </template>
        <template #designation-data="{ row }">
          <UBadge size="xs" variant="subtle">{{ designationLabel[row.designation] }}</UBadge>
        </template>
        <template #nid_no-data="{ row }"><span class="num text-xs">{{ row.nid_no || '—' }}</span></template>
        <template #shares-data="{ row }">
          <span class="num">{{ num(row.shares_held, 0) }}</span>
          <span class="text-[10px] text-gray-400 dark:text-zinc-600 ml-1">({{ sharePct(row) }}%)</span>
        </template>
        <template #status-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="row.is_active ? 'green' : 'gray'">{{ row.is_active ? 'active' : 'resigned' }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <UButton v-if="canWrite" icon="i-heroicons-pencil-square" color="gray" variant="ghost" size="xs" @click="openEdit(row)" />
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">No directors or partners recorded yet.</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ form.id ? 'Edit director / partner' : 'New director / partner' }}</p></template>
        <div class="grid grid-cols-2 gap-3">
          <UFormGroup label="Full name" required class="col-span-2"><UInput v-model="form.full_name" /></UFormGroup>
          <UFormGroup label="Designation">
            <USelect v-model="form.designation" :options="designationOptions" option-attribute="label" value-attribute="value" />
          </UFormGroup>
          <UFormGroup label="Nationality"><UInput v-model="form.nationality" /></UFormGroup>
          <UFormGroup label="Father's / spouse's name" class="col-span-2"><UInput v-model="form.father_or_spouse_name" /></UFormGroup>
          <UFormGroup label="NID no."><UInput v-model="form.nid_no" /></UFormGroup>
          <UFormGroup label="TIN"><UInput v-model="form.tin_no" /></UFormGroup>
          <UFormGroup label="Address" class="col-span-2"><UInput v-model="form.address" /></UFormGroup>
          <UFormGroup label="Phone"><UInput v-model="form.phone" /></UFormGroup>
          <UFormGroup label="Email"><UInput v-model="form.email" /></UFormGroup>
          <UFormGroup label="Shares held"><UInput v-model.number="form.shares_held" type="number" /></UFormGroup>
          <UFormGroup label="Face value / share (৳)"><UInput v-model.number="form.share_face_value" type="number" /></UFormGroup>
          <UFormGroup label="Appointment date"><UInput v-model="form.appointment_date" type="date" /></UFormGroup>
          <UFormGroup label="Resignation date"><UInput v-model="form.resignation_date" type="date" /></UFormGroup>
          <div class="col-span-2"><UCheckbox v-model="form.is_active" label="Currently active" /></div>
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
