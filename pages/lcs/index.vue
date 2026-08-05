<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite, activeCompanyId, memberships } = useProfile()
const { extractLc } = usePdfExtract()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()
const ownCompanyName = computed(() => memberships.value.find((m) => m.company_id === activeCompanyId.value)?.company?.name)

const lcs = ref<any[]>([])
const customerParties = ref<any[]>([])
const supplierParties = ref<any[]>([])
const banks = ref<any[]>([])
const cashBankAccounts = ref<any[]>([])
const loading = ref(true)

const roleOptions = computed(() => [
  { value: 'export_local', label: t('lcs.roles.export_local') },
  { value: 'export_direct', label: t('lcs.roles.export_direct') },
  { value: 'import', label: t('lcs.roles.import') }
])
const roleLabel = computed<Record<string, string>>(() => Object.fromEntries(roleOptions.value.map((r) => [r.value, r.label])))
const roleColor: Record<string, string> = { export_local: 'green', export_direct: 'blue', import: 'amber' }
const roleShort = computed<Record<string, string>>(() => ({
  export_local: t('lcs.roles_short.export_local'), export_direct: t('lcs.roles_short.export_direct'), import: t('lcs.roles_short.import')
}))
const statusLabel = computed<Record<string, string>>(() => ({
  active: t('lcs.statuses.active'), closed: t('lcs.statuses.closed'), cancelled: t('lcs.statuses.cancelled')
}))
const lcTypeLabel = computed<Record<string, string>>(() => ({ sight: t('lcs.lc_types.sight'), usance: t('lcs.lc_types.usance') }))

const columns = computed(() => [
  { key: 'lc_no', label: t('lcs.index.columns.lc_no') },
  { key: 'role', label: t('lcs.index.columns.role') },
  { key: 'counterparty', label: t('lcs.index.columns.counterparty') },
  { key: 'bank', label: t('lcs.index.columns.bank') },
  { key: 'terms', label: t('lcs.index.columns.terms') },
  { key: 'lc_type', label: t('lcs.index.columns.type') },
  { key: 'status', label: t('lcs.index.columns.status') },
  { key: 'actions', label: '' }
])

const load = async () => {
  loading.value = true
  const [l, cp, sp, b, cba] = await Promise.all([
    client.from('lcs')
      .select('*, counterparty:counterparty_party_id(name, is_foreign, country), bank:bank_party_id(name), lc_amendments(version, amount, quantity, tolerance_pct, expiry_date, bank_fee, note)')
      .is('deleted_at', null)
      .order('created_at', { ascending: false }),
    client.from('parties').select('id, name').eq('is_customer', true).is('deleted_at', null).order('name'),
    client.from('parties').select('id, name').eq('is_supplier', true).is('deleted_at', null).order('name'),
    client.from('parties').select('id, name').eq('is_bank', true).is('deleted_at', null).order('name'),
    client.from('cash_bank_accounts').select('id, name').eq('is_active', true).is('deleted_at', null).order('name')
  ])
  lcs.value = (l.data ?? []).map((row: any) => ({
    ...row,
    amendments: [...(row.lc_amendments ?? [])].sort((a: any, b: any) => b.version - a.version)
  }))
  customerParties.value = cp.data ?? []
  supplierParties.value = sp.data ?? []
  banks.value = b.data ?? []
  cashBankAccounts.value = cba.data ?? []
  loading.value = false
}
onMounted(load)

const active = (row: any) => row.amendments?.[0]

// --- New / edit LC header (v1 terms only created on new) ---
const open = ref(false)
const saving = ref(false)
const editId = ref<string | null>(null)
const suppressRoleWatch = ref(false)
const form = reactive({
  lc_no: '', lc_role: 'export_local', counterparty_party_id: null as string | null, bank_party_id: null as string | null,
  lc_type: 'usance', usance_days: 90, opened_at: new Date().toISOString().slice(0, 10),
  currency: 'BDT', amount: 0, quantity: null as number | null, tolerance_pct: 5, expiry_date: null as string | null,
  incoterm: '', port_of_loading: '', port_of_discharge: '', latest_shipment_date: null as string | null,
  presentation_period_days: null as number | null, available_with_by: ''
})
const isForeign = computed(() => form.lc_role !== 'export_local')
const counterpartyOptions = computed(() => form.lc_role === 'import' ? supplierParties.value : customerParties.value)
const counterpartyLabel = computed(() => form.lc_role === 'import' ? t('lcs.index.supplier_label') : t('lcs.index.buyer_label'))

const blankForm = () => ({
  lc_no: '', lc_role: 'export_local', counterparty_party_id: null, bank_party_id: null, lc_type: 'usance',
  usance_days: 90, opened_at: new Date().toISOString().slice(0, 10),
  currency: 'BDT', amount: 0, quantity: null, tolerance_pct: 5, expiry_date: null,
  incoterm: '', port_of_loading: '', port_of_discharge: '', latest_shipment_date: null,
  presentation_period_days: null, available_with_by: ''
})
const openNew = () => {
  editId.value = null
  Object.assign(form, blankForm())
  open.value = true
}
const openEdit = (row: any) => {
  editId.value = row.id
  suppressRoleWatch.value = true
  Object.assign(form, blankForm(), {
    lc_no: row.lc_no, lc_role: row.lc_role, counterparty_party_id: row.counterparty_party_id, bank_party_id: row.bank_party_id,
    lc_type: row.lc_type, usance_days: row.usance_days, opened_at: row.opened_at, currency: row.currency,
    incoterm: row.incoterm ?? '', port_of_loading: row.port_of_loading ?? '', port_of_discharge: row.port_of_discharge ?? '',
    latest_shipment_date: row.latest_shipment_date, presentation_period_days: row.presentation_period_days,
    available_with_by: row.available_with_by ?? ''
  })
  open.value = true
  nextTick(() => { suppressRoleWatch.value = false })
}
watch(() => form.lc_role, (role) => {
  if (suppressRoleWatch.value) return
  form.counterparty_party_id = null
  if (role !== 'export_local' && form.currency === 'BDT') form.currency = 'USD'
  if (role === 'export_local') form.currency = 'BDT'
})

// "Register from PDF": extract fields client-side, prefill the form for
// review, and attach the source document to the LC on save.
const pdfFile = ref<File | null>(null)
const extracting = ref(false)
const fromPdf = async (ev: Event) => {
  const file = (ev.target as HTMLInputElement).files?.[0]
  if (!file) return
  extracting.value = true
  try {
    const f = await extractLc(file, ownCompanyName.value)
    openNew()
    pdfFile.value = file
    if (f.lc_no) form.lc_no = f.lc_no
    if (f.lc_role) form.lc_role = f.lc_role
    if (f.currency) form.currency = f.currency
    if (f.amount) form.amount = f.amount
    if (f.expiry_date) form.expiry_date = f.expiry_date
    if (f.usance_days) { form.lc_type = 'usance'; form.usance_days = f.usance_days }
    if (f.tolerance_pct) form.tolerance_pct = f.tolerance_pct
    if (f.incoterm) form.incoterm = f.incoterm
    if (f.port_of_loading) form.port_of_loading = f.port_of_loading
    if (f.port_of_discharge) form.port_of_discharge = f.port_of_discharge
    if (f.latest_shipment_date) form.latest_shipment_date = f.latest_shipment_date
    if (f.presentation_period_days) form.presentation_period_days = f.presentation_period_days
    if (f.available_with_by) form.available_with_by = f.available_with_by
    const found = Object.keys(f).filter((k) => k !== 'raw_text').length
    toast.add({
      title: found ? t('lcs.index.toast.extracted', { count: found, role: roleLabel.value[f.lc_role || 'export_local'] }) : t('lcs.index.toast.none_recognised'),
      description: f.applicant ? t('lcs.index.toast.applicant_on_doc', { name: f.applicant }) : f.beneficiary ? t('lcs.index.toast.beneficiary_on_doc', { name: f.beneficiary }) : undefined,
      color: found ? 'green' : 'amber'
    })
  } catch (e: any) {
    toast.add({ title: t('lcs.index.toast.extraction_failed'), description: e.message, color: 'red' })
  } finally {
    extracting.value = false
    ;(ev.target as HTMLInputElement).value = ''
  }
}

const save = async () => {
  if (!form.lc_no || !form.counterparty_party_id) {
    toast.add({ title: t('lcs.index.toast.lc_no_required', { label: counterpartyLabel.value.toLowerCase() }), color: 'red' }); return
  }
  saving.value = true
  try {
    const header: any = {
      lc_no: form.lc_no, lc_role: form.lc_role, counterparty_party_id: form.counterparty_party_id, bank_party_id: form.bank_party_id,
      lc_type: form.lc_type, usance_days: form.usance_days, opened_at: form.opened_at, currency: form.currency,
      incoterm: form.incoterm || null, port_of_loading: form.port_of_loading || null, port_of_discharge: form.port_of_discharge || null,
      latest_shipment_date: form.latest_shipment_date || null, presentation_period_days: form.presentation_period_days,
      available_with_by: form.available_with_by || null
    }

    if (editId.value) {
      const { error } = await client.from('lcs').update(header).eq('id', editId.value)
      if (error) throw error
      toast.add({ title: t('lcs.index.toast.lc_updated') })
    } else {
      const { data: lc, error } = await client.from('lcs').insert(header).select('id').single()
      if (error) throw error
      const res = await client.from('lc_amendments').insert({
        lc_id: (lc as any).id, version: 1, amount: form.amount, quantity: form.quantity,
        tolerance_pct: form.tolerance_pct, expiry_date: form.expiry_date
      } as any)
      if (res.error) throw res.error

      if (pdfFile.value) {
        const path = `${activeCompanyId.value}/${(lc as any).id}/${Date.now()}-${pdfFile.value.name}`
        const up = await client.storage.from('lc-docs').upload(path, pdfFile.value)
        if (!up.error) {
          await client.from('lc_documents').insert({
            lc_id: (lc as any).id, doc_type: 'lc',
            original_name: pdfFile.value.name, file_path: path,
            extracted: { source: 'register-from-pdf' }
          } as any)
        }
        pdfFile.value = null
      }
      toast.add({ title: t('lcs.index.toast.lc_registered') })
    }
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('lcs.index.toast.lc_failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

// --- Amendment (next version) ---
const amendOpen = ref(false)
const amendTarget = ref<any>(null)
const amendForm = reactive({ amount: 0, quantity: null as number | null, tolerance_pct: 5, expiry_date: null as string | null, bank_fee: 0, cash_bank_account_id: null as string | null, note: '' })
const openAmend = (row: any) => {
  amendTarget.value = row
  const a = active(row)
  Object.assign(amendForm, {
    amount: a?.amount ?? 0, quantity: a?.quantity, tolerance_pct: a?.tolerance_pct ?? 5,
    expiry_date: a?.expiry_date, bank_fee: 0, cash_bank_account_id: null, note: ''
  })
  amendOpen.value = true
}
const saveAmend = async () => {
  const next = (active(amendTarget.value)?.version ?? 0) + 1
  const { error } = await client.from('lc_amendments').insert({
    lc_id: amendTarget.value.id, version: next, ...amendForm
  } as any)
  if (error) toast.add({ title: t('lcs.index.toast.amendment_failed'), description: error.message, color: 'red' })
  else {
    toast.add({ title: t('lcs.index.toast.amendment_recorded', { version: next }) + (amendForm.bank_fee > 0 ? t('lcs.index.toast.amendment_fee_note') : '') })
    amendOpen.value = false
    await load()
  }
}

const onDelete = async (row: any) => {
  if (await deleteRecord('lcs', row.id, row.lc_no)) await load()
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('lcs.kicker')" :title="t('lcs.index.title')" :subtitle="t('lcs.index.subtitle')">
      <label v-if="canWrite" class="cursor-pointer">
        <span class="inline-flex items-center gap-1.5 text-sm px-2.5 py-1.5 rounded bg-gray-100 dark:bg-zinc-800 text-gray-700 dark:text-zinc-300 hover:bg-gray-200 dark:hover:bg-zinc-700 font-medium">
          <UIcon name="i-heroicons-document-arrow-up" class="text-base" />
          {{ extracting ? t('lcs.index.extracting') : t('lcs.index.register_from_pdf') }}
        </span>
        <input type="file" accept="application/pdf" class="hidden" :disabled="extracting" @change="fromPdf">
      </label>
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('lcs.index.register_lc') }}</UButton>
    </PageHeader>

    <UCard>
      <UTable :rows="lcs" :columns="columns" :loading="loading">
        <template #role-data="{ row }"><UBadge size="xs" variant="subtle" :color="roleColor[row.lc_role]">{{ roleShort[row.lc_role] }}</UBadge></template>
        <template #counterparty-data="{ row }">
          {{ row.counterparty?.name }}
          <UBadge v-if="row.counterparty?.is_foreign" size="xs" variant="subtle" color="gray" class="ml-1">{{ row.counterparty?.country || t('lcs.index.foreign_fallback') }}</UBadge>
        </template>
        <template #bank-data="{ row }">{{ row.bank?.name || '—' }}</template>
        <template #lc_no-data="{ row }">
          <NuxtLink :to="`/lcs/${row.id}`" class="num font-medium text-amber-600 dark:text-amber-400 hover:underline">
            {{ row.lc_no }}
          </NuxtLink>
        </template>
        <template #terms-data="{ row }">
          <div v-if="active(row)" class="text-xs num">
            <UBadge size="xs" variant="subtle" color="purple">v{{ active(row).version }}</UBadge>
            <span class="text-amber-600 dark:text-amber-400">{{ row.currency }} {{ active(row).amount }}</span> · {{ active(row).quantity ?? '—' }} pcs ±{{ active(row).tolerance_pct }}%
            <span v-if="active(row).expiry_date"> · {{ t('lcs.index.exp_label', { date: active(row).expiry_date }) }}</span>
          </div>
        </template>
        <template #lc_type-data="{ row }">
          {{ lcTypeLabel[row.lc_type] }}<span v-if="row.lc_type === 'usance'"> {{ t('lcs.usance_days_suffix', { days: row.usance_days }) }}</span>
        </template>
        <template #status-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="row.status === 'active' ? 'green' : 'gray'">{{ statusLabel[row.status] }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton v-if="canWrite" icon="i-heroicons-pencil-square" size="xs" color="gray" variant="ghost" @click="openEdit(row)" :aria-label="t('lcs.index.edit_aria')" />
            <UButton v-if="canWrite && row.status === 'active'" size="xs" variant="soft" @click="openAmend(row)">{{ t('lcs.index.amend') }}</UButton>
            <UButton v-if="canWrite" icon="i-heroicons-trash" size="xs" color="red" variant="ghost" :aria-label="t('lcs.index.delete_aria')" @click="onDelete(row)" />
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('lcs.index.empty') }}</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ editId ? t('lcs.index.modal.edit_title') : t('lcs.index.modal.register_title') }}</p></template>
        <div class="grid grid-cols-2 gap-4">
          <UFormGroup :label="t('lcs.index.modal.role_label')" required class="col-span-2">
            <USelect v-model="form.lc_role" :options="roleOptions" option-attribute="label" value-attribute="value" />
          </UFormGroup>
          <UFormGroup :label="t('lcs.index.modal.lc_no_label')" required><UInput v-model="form.lc_no" /></UFormGroup>
          <UFormGroup :label="counterpartyLabel" required>
            <USelect v-model="form.counterparty_party_id" :options="counterpartyOptions" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup :label="t('lcs.index.modal.bank_label')">
            <USelect v-model="form.bank_party_id" :options="banks" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup :label="t('lcs.index.modal.currency_label')">
            <USelect v-model="form.currency" :options="['BDT', 'USD', 'EUR', 'GBP', 'CNY']" />
          </UFormGroup>
          <UFormGroup :label="t('lcs.index.modal.type_label')">
            <USelect v-model="form.lc_type" :options="[{ value: 'sight', label: t('lcs.lc_types.sight') }, { value: 'usance', label: t('lcs.lc_types.usance') }]" option-attribute="label" value-attribute="value" />
          </UFormGroup>
          <UFormGroup v-if="form.lc_type === 'usance'" :label="t('lcs.index.modal.usance_days_label')">
            <UInput v-model.number="form.usance_days" type="number" />
          </UFormGroup>
          <UFormGroup :label="t('lcs.index.modal.opened_label')"><UInput v-model="form.opened_at" type="date" /></UFormGroup>
          <template v-if="!editId">
            <UFormGroup :label="t('lcs.index.modal.amount_label', { currency: form.currency })"><UInput v-model.number="form.amount" type="number" /></UFormGroup>
            <UFormGroup :label="t('lcs.index.modal.quantity_label')"><UInput v-model.number="form.quantity" type="number" /></UFormGroup>
            <UFormGroup :label="t('lcs.index.modal.tolerance_label')"><UInput v-model.number="form.tolerance_pct" type="number" /></UFormGroup>
            <UFormGroup :label="t('lcs.index.modal.expiry_label')"><UInput v-model="form.expiry_date" type="date" /></UFormGroup>
          </template>
          <p v-else class="col-span-2 text-xs text-gray-400 dark:text-zinc-500">
            {{ t('lcs.index.modal.amend_hint') }}
          </p>

          <template v-if="isForeign">
            <div class="col-span-2 border-t border-gray-100 dark:border-zinc-800 pt-3 mt-1">
              <p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('lcs.index.modal.shipment_terms_header') }}</p>
            </div>
            <UFormGroup :label="t('lcs.index.modal.incoterm_label')" :hint="t('lcs.index.modal.incoterm_hint')"><UInput v-model="form.incoterm" /></UFormGroup>
            <UFormGroup :label="t('lcs.index.modal.latest_shipment_label')"><UInput v-model="form.latest_shipment_date" type="date" /></UFormGroup>
            <UFormGroup :label="t('lcs.index.modal.port_loading_label')"><UInput v-model="form.port_of_loading" /></UFormGroup>
            <UFormGroup :label="t('lcs.index.modal.port_discharge_label')"><UInput v-model="form.port_of_discharge" /></UFormGroup>
            <UFormGroup :label="t('lcs.index.modal.presentation_period_label')"><UInput v-model.number="form.presentation_period_days" type="number" /></UFormGroup>
            <UFormGroup :label="t('lcs.index.modal.available_with_by_label')" class="col-span-2" :hint="t('lcs.index.modal.available_with_by_hint')"><UInput v-model="form.available_with_by" /></UFormGroup>
          </template>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ editId ? t('common.save') : t('lcs.index.modal.register') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="amendOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header>
          <p class="font-medium">{{ t('lcs.index.amend_modal.title', { no: amendTarget?.lc_no, version: (active(amendTarget)?.version ?? 0) + 1 }) }}</p>
        </template>
        <div class="grid grid-cols-2 gap-4">
          <UFormGroup :label="t('lcs.index.amend_modal.amount_label')"><UInput v-model.number="amendForm.amount" type="number" /></UFormGroup>
          <UFormGroup :label="t('lcs.index.amend_modal.quantity_label')"><UInput v-model.number="amendForm.quantity" type="number" /></UFormGroup>
          <UFormGroup :label="t('lcs.index.amend_modal.tolerance_label')"><UInput v-model.number="amendForm.tolerance_pct" type="number" /></UFormGroup>
          <UFormGroup :label="t('lcs.index.amend_modal.expiry_label')"><UInput v-model="amendForm.expiry_date" type="date" /></UFormGroup>
          <UFormGroup :label="t('lcs.index.amend_modal.fee_label')" :hint="t('lcs.index.amend_modal.fee_hint')">
            <UInput v-model.number="amendForm.bank_fee" type="number" />
          </UFormGroup>
          <UFormGroup v-if="amendForm.bank_fee > 0" :label="t('lcs.index.amend_modal.fee_paid_from_label')" :hint="t('lcs.index.amend_modal.fee_paid_from_hint')">
            <USelect v-model="amendForm.cash_bank_account_id" :options="cashBankAccounts" option-attribute="name" value-attribute="id" :placeholder="t('lcs.index.amend_modal.fee_default_option')" />
          </UFormGroup>
          <UFormGroup :label="t('lcs.index.amend_modal.note_label')"><UInput v-model="amendForm.note" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="amendOpen = false">{{ t('common.cancel') }}</UButton>
            <UButton @click="saveAmend">{{ t('lcs.index.amend_modal.record') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
