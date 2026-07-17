<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()

const docs = ref<any[]>([])
const loading = ref(true)
const expanded = ref<string | null>(null)

const docTypeOptions = [
  { value: 'trade_license', label: 'Trade License' },
  { value: 'incorporation_certificate', label: 'Incorporation Certificate' },
  { value: 'moa_aoa', label: 'Memorandum & Articles of Association' },
  { value: 'tin_certificate', label: 'TIN Certificate' },
  { value: 'vat_bin_certificate', label: 'VAT / BIN Certificate' },
  { value: 'fire_license', label: 'Fire License' },
  { value: 'environment_clearance', label: 'Environment Clearance' },
  { value: 'factory_license', label: 'Factory License (DIFE)' },
  { value: 'boiler_certificate', label: 'Boiler Certificate' },
  { value: 'bsci_sedex_audit', label: 'BSCI / Sedex Audit Certificate' },
  { value: 'fsc_coc_certificate', label: 'FSC Chain of Custody Certificate' },
  { value: 'import_registration_certificate', label: 'Import Registration Certificate (IRC)' },
  { value: 'export_registration_certificate', label: 'Export Registration Certificate (ERC)' },
  { value: 'effluent_treatment_certificate', label: 'Effluent Treatment (ETP) Certificate' },
  { value: 'electrical_installation_license', label: 'Electrical Installation License' },
  { value: 'bsti_certification', label: 'BSTI Certification' },
  { value: 'trademark_design_registration', label: 'Trademark / Design Registration' },
  { value: 'labour_welfare_registration', label: 'Labour Welfare Fund Registration' },
  { value: 'group_insurance_certificate', label: 'Group Insurance Certificate' },
  { value: 'bank_charge_document', label: 'Bank Charge / Mortgage Document' },
  { value: 'noc_certificate', label: 'No Objection Certificate (NOC)' },
  { value: 'bank_account_doc', label: 'Bank Account Document' },
  { value: 'membership_certificate', label: 'Membership Certificate' },
  { value: 'other', label: 'Other' }
]
const docTypeLabel: Record<string, string> = Object.fromEntries(docTypeOptions.map((o) => [o.value, o.label]))

const load = async () => {
  loading.value = true
  const { data } = await client.from('company_documents').select('*').order('expiry_date', { nullsFirst: false })
  docs.value = data ?? []
  loading.value = false
}
onMounted(load)

const today = new Date().toISOString().slice(0, 10)
const expiryStatus = (row: any) => {
  if (!row.expiry_date) return null
  if (row.expiry_date < today) return { label: 'expired', color: 'red' }
  if (row.expiry_date < new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10)) return { label: 'expiring soon', color: 'amber' }
  return { label: 'valid', color: 'green' }
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
  if (!form.title) { toast.add({ title: 'Title is required', color: 'red' }); return }
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
    toast.add({ title: 'Document saved' })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: 'Save failed', description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

const openFile = async (row: any) => {
  if (!row.file_path) return
  const { data } = client.storage.from('company-assets').getPublicUrl(row.file_path)
  if (data?.publicUrl) window.open(data.publicUrl, '_blank')
}
</script>

<template>
  <div>
    <PageHeader kicker="Admin" title="Company documents" subtitle="Trade license, incorporation papers, certificates — with expiry tracking and legal review">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">Upload document</UButton>
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
            </div>
          </div>
          <div v-if="expanded === d.id" class="mt-2.5 pl-5 grid grid-cols-2 gap-4">
            <div class="text-[12.5px] space-y-1 text-gray-500 dark:text-zinc-400">
              <div v-if="d.doc_no">Doc no: <span class="num dark:text-zinc-300">{{ d.doc_no }}</span></div>
              <div v-if="d.issue_date">Issued: <span class="num dark:text-zinc-300">{{ d.issue_date }}</span></div>
              <div v-if="d.notes">{{ d.notes }}</div>
            </div>
            <AdminLegalReview ref-table="company_documents" :ref-id="d.id" />
          </div>
        </div>
        <p v-if="!docs.length && !loading" class="text-center py-6 text-sm text-gray-400">No documents uploaded yet.</p>
      </div>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">Upload company document</p></template>
        <div class="space-y-3">
          <UFormGroup label="Type">
            <USelect v-model="form.doc_type" :options="docTypeOptions" option-attribute="label" value-attribute="value" />
          </UFormGroup>
          <UFormGroup label="Title" required><UInput v-model="form.title" placeholder="e.g. Trade License 2026-27" /></UFormGroup>
          <UFormGroup label="Document no."><UInput v-model="form.doc_no" /></UFormGroup>
          <div class="grid grid-cols-2 gap-3">
            <UFormGroup label="Issue date"><UInput v-model="form.issue_date" type="date" /></UFormGroup>
            <UFormGroup label="Expiry date"><UInput v-model="form.expiry_date" type="date" /></UFormGroup>
          </div>
          <UFormGroup label="Notes"><UInput v-model="form.notes" /></UFormGroup>
          <UFormGroup label="File">
            <input type="file" @change="onFile">
          </UFormGroup>
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
