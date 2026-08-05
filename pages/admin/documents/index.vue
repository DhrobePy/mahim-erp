<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const docs = ref<any[]>([])
const loading = ref(true)
const expanded = ref<string | null>(null)

const docTypeOptions = computed(() => [
  { value: 'trade_license', label: t('admin.documents.doc_types.trade_license') },
  { value: 'incorporation_certificate', label: t('admin.documents.doc_types.incorporation_certificate') },
  { value: 'moa_aoa', label: t('admin.documents.doc_types.moa_aoa') },
  { value: 'tin_certificate', label: t('admin.documents.doc_types.tin_certificate') },
  { value: 'vat_bin_certificate', label: t('admin.documents.doc_types.vat_bin_certificate') },
  { value: 'fire_license', label: t('admin.documents.doc_types.fire_license') },
  { value: 'environment_clearance', label: t('admin.documents.doc_types.environment_clearance') },
  { value: 'factory_license', label: t('admin.documents.doc_types.factory_license') },
  { value: 'boiler_certificate', label: t('admin.documents.doc_types.boiler_certificate') },
  { value: 'bsci_sedex_audit', label: t('admin.documents.doc_types.bsci_sedex_audit') },
  { value: 'fsc_coc_certificate', label: t('admin.documents.doc_types.fsc_coc_certificate') },
  { value: 'import_registration_certificate', label: t('admin.documents.doc_types.import_registration_certificate') },
  { value: 'export_registration_certificate', label: t('admin.documents.doc_types.export_registration_certificate') },
  { value: 'effluent_treatment_certificate', label: t('admin.documents.doc_types.effluent_treatment_certificate') },
  { value: 'electrical_installation_license', label: t('admin.documents.doc_types.electrical_installation_license') },
  { value: 'bsti_certification', label: t('admin.documents.doc_types.bsti_certification') },
  { value: 'trademark_design_registration', label: t('admin.documents.doc_types.trademark_design_registration') },
  { value: 'labour_welfare_registration', label: t('admin.documents.doc_types.labour_welfare_registration') },
  { value: 'group_insurance_certificate', label: t('admin.documents.doc_types.group_insurance_certificate') },
  { value: 'bank_charge_document', label: t('admin.documents.doc_types.bank_charge_document') },
  { value: 'noc_certificate', label: t('admin.documents.doc_types.noc_certificate') },
  { value: 'bank_account_doc', label: t('admin.documents.doc_types.bank_account_doc') },
  { value: 'membership_certificate', label: t('admin.documents.doc_types.membership_certificate') },
  { value: 'other', label: t('admin.documents.doc_types.other') }
])
const docTypeLabel = computed<Record<string, string>>(() => Object.fromEntries(docTypeOptions.value.map((o) => [o.value, o.label])))

const load = async () => {
  loading.value = true
  const { data } = await client.from('company_documents').select('*').is('deleted_at', null).order('expiry_date', { nullsFirst: false })
  docs.value = data ?? []
  loading.value = false
}
onMounted(load)

const today = new Date().toISOString().slice(0, 10)
const expiryStatus = (row: any) => {
  if (!row.expiry_date) return null
  if (row.expiry_date < today) return { label: t('admin.documents.expiry.expired'), color: 'red' }
  if (row.expiry_date < new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10)) return { label: t('admin.documents.expiry.expiring_soon'), color: 'amber' }
  return { label: t('admin.documents.expiry.valid'), color: 'green' }
}

// --- Upload ---
const open = ref(false)
const saving = ref(false)
const form = reactive({
  doc_type: 'trade_license', title: '', doc_no: '', issue_date: '', expiry_date: '', notes: ''
})
const file = ref<File | null>(null)
const openNew = () => {
  Object.assign(form, { doc_type: 'trade_license', title: '', doc_no: '', issue_date: '', expiry_date: '', notes: '' })
  file.value = null
  open.value = true
}
const onFile = (ev: Event) => { file.value = (ev.target as HTMLInputElement).files?.[0] ?? null }

const save = async () => {
  if (!form.title) { toast.add({ title: t('admin.documents.validation.title_required'), color: 'red' }); return }
  saving.value = true
  try {
    let file_path: string | null = null
    if (file.value) {
      const path = `${Date.now()}-${file.value.name}`
      const up = await client.storage.from('company-assets').upload(path, file.value)
      if (up.error) throw up.error
      file_path = path
    }
    const { error } = await client.from('company_documents').insert({ ...form, file_path } as any)
    if (error) throw error
    toast.add({ title: t('admin.documents.toasts.document_saved') })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('common.save_failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

const openFile = async (row: any) => {
  if (!row.file_path) return
  const { data } = client.storage.from('company-assets').getPublicUrl(row.file_path)
  if (data?.publicUrl) window.open(data.publicUrl, '_blank')
}

const remove = async (row: any) => {
  if (await deleteRecord('company_documents', row.id, row.title)) await load()
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('admin.documents.kicker')" :title="t('admin.documents.title')" :subtitle="t('admin.documents.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('admin.documents.upload_btn') }}</UButton>
    </PageHeader>

    <UCard>
      <div class="divide-y divide-gray-100 dark:divide-zinc-800/60">
        <div v-for="d in docs" :key="d.id" class="py-2.5">
          <div class="flex items-center justify-between">
            <button class="text-left cursor-pointer flex items-center gap-2" @click="expanded = expanded === d.id ? null : d.id">
              <UIcon :name="expanded === d.id ? 'i-heroicons-chevron-down' : 'i-heroicons-chevron-right'" class="text-xs text-gray-400" />
              <span class="text-[13px] font-medium dark:text-zinc-200">{{ d.title }}</span>
              <UBadge size="xs" variant="subtle">{{ docTypeLabel[d.doc_type] }}</UBadge>
            </button>
            <div class="flex items-center gap-2">
              <span v-if="expiryStatus(d)" class="num text-[11px]">
                <UBadge size="xs" variant="subtle" :color="expiryStatus(d)!.color">
                  {{ expiryStatus(d)!.label }}{{ d.expiry_date ? ' · ' + d.expiry_date : '' }}
                </UBadge>
              </span>
              <UButton v-if="d.file_path" size="2xs" variant="ghost" icon="i-heroicons-arrow-top-right-on-square" @click="openFile(d)" />
              <UButton v-if="canWrite" size="2xs" color="red" variant="ghost" icon="i-heroicons-trash" @click="remove(d)" />
            </div>
          </div>
          <div v-if="expanded === d.id" class="mt-2.5 pl-5 grid grid-cols-2 gap-4">
            <div class="text-[12.5px] space-y-1 text-gray-500 dark:text-zinc-400">
              <div v-if="d.doc_no">{{ t('admin.documents.doc_no_label') }} <span class="num dark:text-zinc-300">{{ d.doc_no }}</span></div>
              <div v-if="d.issue_date">{{ t('admin.documents.issued_label') }} <span class="num dark:text-zinc-300">{{ d.issue_date }}</span></div>
              <div v-if="d.notes">{{ d.notes }}</div>
            </div>
            <AdminLegalReview ref-table="company_documents" :ref-id="d.id" />
          </div>
        </div>
        <p v-if="!docs.length && !loading" class="text-center py-6 text-sm text-gray-400">{{ t('admin.documents.empty') }}</p>
      </div>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('admin.documents.form.title') }}</p></template>
        <div class="space-y-3">
          <UFormGroup :label="t('admin.documents.form.type')">
            <USelect v-model="form.doc_type" :options="docTypeOptions" option-attribute="label" value-attribute="value" />
          </UFormGroup>
          <UFormGroup :label="t('admin.documents.form.doc_title')" required><UInput v-model="form.title" :placeholder="t('admin.documents.form.doc_title_placeholder')" /></UFormGroup>
          <UFormGroup :label="t('admin.documents.form.doc_no')"><UInput v-model="form.doc_no" /></UFormGroup>
          <div class="grid grid-cols-2 gap-3">
            <UFormGroup :label="t('admin.documents.form.issue_date')"><UInput v-model="form.issue_date" type="date" /></UFormGroup>
            <UFormGroup :label="t('admin.documents.form.expiry_date')"><UInput v-model="form.expiry_date" type="date" /></UFormGroup>
          </div>
          <UFormGroup :label="t('admin.documents.form.notes')"><UInput v-model="form.notes" /></UFormGroup>
          <UFormGroup :label="t('admin.documents.form.file')">
            <input type="file" @change="onFile">
          </UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ t('admin.documents.form.save') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
