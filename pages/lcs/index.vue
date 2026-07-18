<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite, activeCompanyId, memberships } = useProfile()
const { extractLc } = usePdfExtract()
const ownCompanyName = computed(() => memberships.value.find((m) => m.company_id === activeCompanyId.value)?.company?.name)

const lcs = ref<any[]>([])
const customerParties = ref<any[]>([])
const supplierParties = ref<any[]>([])
const banks = ref<any[]>([])
const cashBankAccounts = ref<any[]>([])
const loading = ref(true)

const roleOptions = [
  { value: 'export_local', label: 'Export — Local LC (back-to-back)' },
  { value: 'export_direct', label: 'Export — Direct (foreign)' },
  { value: 'import', label: 'Import (foreign)' }
]
const roleLabel: Record<string, string> = Object.fromEntries(roleOptions.map((r) => [r.value, r.label]))
const roleColor: Record<string, string> = { export_local: 'green', export_direct: 'blue', import: 'amber' }
const roleShort: Record<string, string> = { export_local: 'Local export', export_direct: 'Direct export', import: 'Import' }

const columns = [
  { key: 'lc_no', label: 'LC no.' },
  { key: 'role', label: 'Role' },
  { key: 'counterparty', label: 'Counterparty' },
  { key: 'bank', label: 'Issuing bank' },
  { key: 'terms', label: 'Active terms' },
  { key: 'lc_type', label: 'Type' },
  { key: 'status', label: 'Status' },
  { key: 'actions', label: '' }
]

const load = async () => {
  loading.value = true
  const [l, cp, sp, b, cba] = await Promise.all([
    client.from('lcs')
      .select('*, counterparty:counterparty_party_id(name, is_foreign, country), bank:bank_party_id(name), lc_amendments(version, amount, quantity, tolerance_pct, expiry_date, bank_fee, note)')
      .order('created_at', { ascending: false }),
    client.from('parties').select('id, name').eq('is_customer', true).order('name'),
    client.from('parties').select('id, name').eq('is_supplier', true).order('name'),
    client.from('parties').select('id, name').eq('is_bank', true).order('name'),
    client.from('cash_bank_accounts').select('id, name').eq('is_active', true).order('name')
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
const counterpartyLabel = computed(() => form.lc_role === 'import' ? 'Supplier' : 'Buyer')

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
      title: found ? `Extracted ${found} field(s) as ${roleLabel[f.lc_role || 'export_local']} — review before saving` : 'No fields recognised',
      description: f.applicant ? `Applicant on document: ${f.applicant}` : f.beneficiary ? `Beneficiary on document: ${f.beneficiary}` : undefined,
      color: found ? 'green' : 'amber'
    })
  } catch (e: any) {
    toast.add({ title: 'Extraction failed', description: e.message, color: 'red' })
  } finally {
    extracting.value = false
    ;(ev.target as HTMLInputElement).value = ''
  }
}

const save = async () => {
  if (!form.lc_no || !form.counterparty_party_id) {
    toast.add({ title: `LC number and ${counterpartyLabel.value.toLowerCase()} are required`, color: 'red' }); return
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
      toast.add({ title: 'LC updated' })
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
      toast.add({ title: 'LC registered (v1 terms)' })
    }
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: 'LC failed', description: e.message, color: 'red' })
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
  if (error) toast.add({ title: 'Amendment failed', description: error.message, color: 'red' })
  else {
    toast.add({ title: `Amendment v${next} recorded${amendForm.bank_fee > 0 ? ' — MT707 fee posted' : ''}` })
    amendOpen.value = false
    await load()
  }
}
</script>

<template>
  <div>
    <PageHeader kicker="Sales &amp; Trade Finance" title="Letters of Credit" subtitle="Local export (back-to-back), direct foreign export, and import LCs — master-child versioning per contract">
      <label v-if="canWrite" class="cursor-pointer">
        <span class="inline-flex items-center gap-1.5 text-sm px-2.5 py-1.5 rounded bg-gray-100 dark:bg-zinc-800 text-gray-700 dark:text-zinc-300 hover:bg-gray-200 dark:hover:bg-zinc-700 font-medium">
          <UIcon name="i-heroicons-document-arrow-up" class="text-base" />
          {{ extracting ? 'Extracting…' : 'Register from PDF' }}
        </span>
        <input type="file" accept="application/pdf" class="hidden" :disabled="extracting" @change="fromPdf">
      </label>
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">Register LC</UButton>
    </PageHeader>

    <UCard>
      <UTable :rows="lcs" :columns="columns" :loading="loading">
        <template #role-data="{ row }"><UBadge size="xs" variant="subtle" :color="roleColor[row.lc_role]">{{ roleShort[row.lc_role] }}</UBadge></template>
        <template #counterparty-data="{ row }">
          {{ row.counterparty?.name }}
          <UBadge v-if="row.counterparty?.is_foreign" size="xs" variant="subtle" color="gray" class="ml-1">{{ row.counterparty?.country || 'foreign' }}</UBadge>
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
            <span v-if="active(row).expiry_date"> · exp {{ active(row).expiry_date }}</span>
          </div>
        </template>
        <template #lc_type-data="{ row }">
          {{ row.lc_type }}<span v-if="row.lc_type === 'usance'"> {{ row.usance_days }}d</span>
        </template>
        <template #status-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="row.status === 'active' ? 'green' : 'gray'">{{ row.status }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton v-if="canWrite" icon="i-heroicons-pencil-square" size="xs" color="gray" variant="ghost" @click="openEdit(row)" aria-label="Edit LC" />
            <UButton v-if="canWrite && row.status === 'active'" size="xs" variant="soft" @click="openAmend(row)">Amend</UButton>
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">No LCs registered.</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ editId ? 'Edit LC' : 'Register LC (v1 terms)' }}</p></template>
        <div class="grid grid-cols-2 gap-4">
          <UFormGroup label="Role" required class="col-span-2">
            <USelect v-model="form.lc_role" :options="roleOptions" option-attribute="label" value-attribute="value" />
          </UFormGroup>
          <UFormGroup label="LC number" required><UInput v-model="form.lc_no" /></UFormGroup>
          <UFormGroup :label="counterpartyLabel" required>
            <USelect v-model="form.counterparty_party_id" :options="counterpartyOptions" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup label="Issuing bank">
            <USelect v-model="form.bank_party_id" :options="banks" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup label="Currency">
            <USelect v-model="form.currency" :options="['BDT', 'USD', 'EUR', 'GBP', 'CNY']" />
          </UFormGroup>
          <UFormGroup label="Type">
            <USelect v-model="form.lc_type" :options="[{ value: 'sight', label: 'Sight' }, { value: 'usance', label: 'Usance' }]" option-attribute="label" value-attribute="value" />
          </UFormGroup>
          <UFormGroup v-if="form.lc_type === 'usance'" label="Usance days">
            <UInput v-model.number="form.usance_days" type="number" />
          </UFormGroup>
          <UFormGroup label="Opened"><UInput v-model="form.opened_at" type="date" /></UFormGroup>
          <template v-if="!editId">
            <UFormGroup :label="`Amount (${form.currency})`"><UInput v-model.number="form.amount" type="number" /></UFormGroup>
            <UFormGroup label="Quantity"><UInput v-model.number="form.quantity" type="number" /></UFormGroup>
            <UFormGroup label="Tolerance %"><UInput v-model.number="form.tolerance_pct" type="number" /></UFormGroup>
            <UFormGroup label="Expiry"><UInput v-model="form.expiry_date" type="date" /></UFormGroup>
          </template>
          <p v-else class="col-span-2 text-xs text-gray-400 dark:text-zinc-500">
            Amount, quantity, tolerance and expiry are versioned terms — use "Amend" on the list to change those.
          </p>

          <template v-if="isForeign">
            <div class="col-span-2 border-t border-gray-100 dark:border-zinc-800 pt-3 mt-1">
              <p class="microlabel text-gray-400 dark:text-zinc-500">Shipment &amp; foreign trade terms</p>
            </div>
            <UFormGroup label="Incoterm" hint="e.g. CFR, FOB, CIF, EXW"><UInput v-model="form.incoterm" /></UFormGroup>
            <UFormGroup label="Latest shipment date"><UInput v-model="form.latest_shipment_date" type="date" /></UFormGroup>
            <UFormGroup label="Port of loading"><UInput v-model="form.port_of_loading" /></UFormGroup>
            <UFormGroup label="Port of discharge"><UInput v-model="form.port_of_discharge" /></UFormGroup>
            <UFormGroup label="Presentation period (days)"><UInput v-model.number="form.presentation_period_days" type="number" /></UFormGroup>
            <UFormGroup label="Available with / by" class="col-span-2" hint="e.g. Any bank in China, by negotiation"><UInput v-model="form.available_with_by" /></UFormGroup>
          </template>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">Cancel</UButton>
            <UButton :loading="saving" @click="save">{{ editId ? 'Save' : 'Register' }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="amendOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header>
          <p class="font-medium">Amend {{ amendTarget?.lc_no }} → v{{ (active(amendTarget)?.version ?? 0) + 1 }}</p>
        </template>
        <div class="grid grid-cols-2 gap-4">
          <UFormGroup label="Amount"><UInput v-model.number="amendForm.amount" type="number" /></UFormGroup>
          <UFormGroup label="Quantity"><UInput v-model.number="amendForm.quantity" type="number" /></UFormGroup>
          <UFormGroup label="Tolerance %"><UInput v-model.number="amendForm.tolerance_pct" type="number" /></UFormGroup>
          <UFormGroup label="Expiry"><UInput v-model="amendForm.expiry_date" type="date" /></UFormGroup>
          <UFormGroup label="MT707 fee on us (৳)" hint="posts to 5400 if > 0">
            <UInput v-model.number="amendForm.bank_fee" type="number" />
          </UFormGroup>
          <UFormGroup v-if="amendForm.bank_fee > 0" label="Fee paid from" hint="which account the fee is debited from">
            <USelect v-model="amendForm.cash_bank_account_id" :options="cashBankAccounts" option-attribute="name" value-attribute="id" placeholder="— default bank account —" />
          </UFormGroup>
          <UFormGroup label="Note"><UInput v-model="amendForm.note" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="amendOpen = false">Cancel</UButton>
            <UButton @click="saveAmend">Record amendment</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
