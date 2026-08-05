<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { num } = useFmt()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const rows = ref<any[]>([])
const loading = ref(true)

const columns = computed(() => [
  { key: 'full_name', label: t('admin.directors.columns.name') },
  { key: 'designation', label: t('admin.directors.columns.designation') },
  { key: 'nid_no', label: t('admin.directors.columns.nid') },
  { key: 'shares', label: t('admin.directors.columns.shares') },
  { key: 'appointment_date', label: t('admin.directors.columns.appointed') },
  { key: 'status', label: '' },
  { key: 'actions', label: '' }
])

const designationOptions = computed(() => [
  { value: 'chairman', label: t('admin.directors.designations.chairman') },
  { value: 'managing_director', label: t('admin.directors.designations.managing_director') },
  { value: 'director', label: t('admin.directors.designations.director') },
  { value: 'partner', label: t('admin.directors.designations.partner') },
  { value: 'company_secretary', label: t('admin.directors.designations.company_secretary') }
])
const designationLabel = computed<Record<string, string>>(() => Object.fromEntries(designationOptions.value.map((o) => [o.value, o.label])))

const load = async () => {
  loading.value = true
  const { data } = await client.from('company_directors').select('*').is('deleted_at', null).order('appointment_date')
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
  if (!form.full_name) { toast.add({ title: t('admin.directors.validation.name_required'), color: 'red' }); return }
  saving.value = true
  const payload: any = { ...form }
  delete payload.id
  try {
    const res = form.id
      ? await client.from('company_directors').update(payload).eq('id', form.id)
      : await client.from('company_directors').insert(payload)
    if (res.error) throw res.error
    toast.add({ title: form.id ? t('admin.directors.toasts.updated') : t('admin.directors.toasts.director_added') })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('common.save_failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

const remove = async (row: any) => {
  if (await deleteRecord('company_directors', row.id, row.full_name)) await load()
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('admin.directors.kicker')" :title="t('admin.directors.title')" :subtitle="t('admin.directors.subtitle')">
      <UButton icon="i-heroicons-printer" variant="soft" to="/print/rjsc/form12" target="_blank">{{ t('admin.directors.form12_btn') }}</UButton>
      <UButton icon="i-heroicons-printer" variant="soft" to="/print/rjsc/schedulex" target="_blank">{{ t('admin.directors.schedulex_btn') }}</UButton>
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('admin.directors.new_director_btn') }}</UButton>
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
          <UBadge size="xs" variant="subtle" :color="row.is_active ? 'green' : 'gray'">{{ row.is_active ? t('admin.directors.status.active') : t('admin.directors.status.resigned') }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton v-if="canWrite" icon="i-heroicons-pencil-square" color="gray" variant="ghost" size="xs" @click="openEdit(row)" />
            <UButton v-if="canWrite" icon="i-heroicons-trash" color="red" variant="ghost" size="xs" @click="remove(row)" />
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('admin.directors.empty') }}</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ form.id ? t('admin.directors.form.edit_title') : t('admin.directors.form.new_title') }}</p></template>
        <div class="grid grid-cols-2 gap-3">
          <UFormGroup :label="t('admin.directors.form.full_name')" required class="col-span-2"><UInput v-model="form.full_name" /></UFormGroup>
          <UFormGroup :label="t('admin.directors.form.designation')">
            <USelect v-model="form.designation" :options="designationOptions" option-attribute="label" value-attribute="value" />
          </UFormGroup>
          <UFormGroup :label="t('admin.directors.form.nationality')"><UInput v-model="form.nationality" /></UFormGroup>
          <UFormGroup :label="t('admin.directors.form.father_or_spouse_name')" class="col-span-2"><UInput v-model="form.father_or_spouse_name" /></UFormGroup>
          <UFormGroup :label="t('admin.directors.form.nid_no')"><UInput v-model="form.nid_no" /></UFormGroup>
          <UFormGroup :label="t('admin.directors.form.tin')"><UInput v-model="form.tin_no" /></UFormGroup>
          <UFormGroup :label="t('admin.directors.form.address')" class="col-span-2"><UInput v-model="form.address" /></UFormGroup>
          <UFormGroup :label="t('admin.directors.form.phone')"><UInput v-model="form.phone" /></UFormGroup>
          <UFormGroup :label="t('admin.directors.form.email')"><UInput v-model="form.email" /></UFormGroup>
          <UFormGroup :label="t('admin.directors.form.shares_held')"><UInput v-model.number="form.shares_held" type="number" /></UFormGroup>
          <UFormGroup :label="t('admin.directors.form.face_value')"><UInput v-model.number="form.share_face_value" type="number" /></UFormGroup>
          <UFormGroup :label="t('admin.directors.form.appointment_date')"><UInput v-model="form.appointment_date" type="date" /></UFormGroup>
          <UFormGroup :label="t('admin.directors.form.resignation_date')"><UInput v-model="form.resignation_date" type="date" /></UFormGroup>
          <div class="col-span-2"><UCheckbox v-model="form.is_active" :label="t('admin.directors.form.currently_active')" /></div>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ t('admin.directors.form.save') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
