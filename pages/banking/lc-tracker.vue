<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite, activeCompanyId } = useProfile()
const { moneyIn, num } = useFmt()
const { t } = useI18n()

const bills = ref<any[]>([])
const lcOptions = ref<any[]>([])
const facilities = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [b, l, f] = await Promise.all([
    client.from('bills')
      .select(`
        id, bill_no, amount, submitted_at, accepted_at, maturity_date, received_at, status,
        lcs!inner(id, lc_no, lc_role, lc_type, usance_days, currency,
          counterparty:counterparty_party_id(name),
          bank:bank_party_id(name),
          lc_amendments(version, amount)),
        lbpd_disbursements(id, disbursed_at, principal, facility_id, settled_at, status)
      `)
      .eq('lcs.lc_role', 'export_local')
      .is('deleted_at', null)
      .order('submitted_at', { ascending: false }),
    client.from('lcs').select('id, lc_no, currency').eq('lc_role', 'export_local').eq('status', 'active').order('lc_no'),
    client.from('bank_facilities').select('id, name').eq('facility_type', 'lbpd').order('name')
  ])
  if (b.error) { toast.add({ title: t('lc_tracker.toast.load_failed'), description: b.error.message, color: 'red' }); loading.value = false; return }

  bills.value = (b.data ?? []).map((row: any) => {
    const amendments = [...(row.lcs.lc_amendments ?? [])].sort((a: any, b: any) => b.version - a.version)
    const lbpd = (row.lbpd_disbursements ?? [])[0] ?? null
    return {
      id: row.id,
      bill_no: row.bill_no,
      lc_id: row.lcs.id,
      lc_no: row.lcs.lc_no,
      bank: row.lcs.bank?.name ?? '—',
      party: row.lcs.counterparty?.name ?? '—',
      currency: row.lcs.currency,
      lc_amount: amendments[0]?.amount ?? null,
      tenure: row.lcs.lc_type === 'usance' ? row.lcs.usance_days : null,
      lc_type: row.lcs.lc_type,
      amount: row.amount,
      submitted_at: row.submitted_at,
      accepted_at: row.accepted_at,
      lbpd_id: lbpd?.id ?? null,
      lbpd_created_at: lbpd?.disbursed_at ?? null,
      lbpd_facility_id: lbpd?.facility_id ?? null,
      lbpd_principal: lbpd?.principal ?? null,
      maturity_date: row.maturity_date,
      received_at: row.received_at,
      status: row.status
    }
  })
  lcOptions.value = l.data ?? []
  facilities.value = f.data ?? []
  loading.value = false
}
onMounted(load)

const today = new Date().toISOString().slice(0, 10)
const isOverdue = (row: any) => !row.received_at && row.maturity_date && row.maturity_date < today
const isDueSoon = (row: any) => !row.received_at && row.maturity_date && row.maturity_date >= today &&
  row.maturity_date <= new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 10)

const stats = computed(() => {
  const open = bills.value.filter((b) => !b.received_at)
  return {
    openCount: open.length,
    pendingAcceptance: bills.value.filter((b) => !b.accepted_at).length,
    dueSoon: open.filter(isDueSoon).length,
    overdue: open.filter(isOverdue).length,
    outstandingBdt: open.filter((b) => b.currency === 'BDT').reduce((s, b) => s + Number(b.lc_amount || 0), 0)
  }
})

const statusOptions = computed(() => [
  { value: 'submitted', label: t('lc_tracker.statuses.submitted') },
  { value: 'accepted', label: t('lc_tracker.statuses.accepted') },
  { value: 'discounted', label: t('lc_tracker.statuses.discounted') },
  { value: 'realized', label: t('lc_tracker.statuses.realized') },
  { value: 'overdue', label: t('lc_tracker.statuses.overdue') }
])
const statusColor = (s: string) =>
  ({ submitted: 'gray', accepted: 'blue', discounted: 'purple', realized: 'green', overdue: 'red' } as any)[s] || 'gray'
const statusLabel = (s: string) => t(`lc_tracker.statuses.${s}`)
const fmtDate = (d: string | null) => d || '—'

// --- Inline edit: Bills Received Date ---
const editingId = ref<string | null>(null)
const editValue = ref('')
const startEdit = (row: any) => { editingId.value = row.id; editValue.value = row.received_at ?? today }
const cancelEdit = () => { editingId.value = null }
const saveReceived = async (row: any) => {
  const { error } = await client.from('bills').update({ received_at: editValue.value || null }).eq('id', row.id)
  if (error) { toast.add({ title: t('lc_tracker.toast.save_failed'), description: error.message, color: 'red' }); return }
  row.received_at = editValue.value || null
  editingId.value = null
  toast.add({ title: t('lc_tracker.toast.saved') })
}
const clearReceived = async (row: any) => {
  const { error } = await client.from('bills').update({ received_at: null }).eq('id', row.id)
  if (error) { toast.add({ title: t('lc_tracker.toast.save_failed'), description: error.message, color: 'red' }); return }
  row.received_at = null
  toast.add({ title: t('lc_tracker.toast.cleared') })
}

// --- New / edit entry slideover ---
const open = ref(false)
const saving = ref(false)
const blankForm = () => ({
  id: null as string | null,
  lc_id: null as string | null,
  bill_no: '',
  amount: 0,
  status: 'submitted',
  submitted_at: today,
  accepted_at: null as string | null,
  maturity_date: null as string | null,
  received_at: null as string | null,
  lbpd_id: null as string | null,
  lbpd_facility_id: null as string | null,
  lbpd_created_at: null as string | null,
  lbpd_principal: null as number | null
})
const form = reactive(blankForm())
const openNew = () => { Object.assign(form, blankForm()); open.value = true }
const openEdit = (row: any) => {
  Object.assign(form, {
    id: row.id, lc_id: row.lc_id, bill_no: row.bill_no, amount: row.amount, status: row.status,
    submitted_at: row.submitted_at, accepted_at: row.accepted_at, maturity_date: row.maturity_date,
    received_at: row.received_at, lbpd_id: row.lbpd_id, lbpd_facility_id: row.lbpd_facility_id,
    lbpd_created_at: row.lbpd_created_at, lbpd_principal: row.lbpd_principal
  })
  open.value = true
}

const save = async () => {
  if (!form.lc_id) { toast.add({ title: t('lc_tracker.toast.pick_lc'), color: 'red' }); return }
  if (!form.bill_no) { toast.add({ title: t('lc_tracker.toast.bill_no_required'), color: 'red' }); return }
  saving.value = true
  try {
    const billPayload: any = {
      lc_id: form.lc_id, bill_no: form.bill_no, amount: form.amount, status: form.status,
      submitted_at: form.submitted_at, accepted_at: form.accepted_at || null,
      maturity_date: form.maturity_date || null, received_at: form.received_at || null
    }
    let billId = form.id
    if (form.id) {
      const { error } = await client.from('bills').update(billPayload).eq('id', form.id)
      if (error) throw error
    } else {
      const { data: b, error } = await client.from('bills').insert({ ...billPayload, company_id: activeCompanyId.value }).select('id').single()
      if (error) throw error
      billId = (b as any).id
    }

    // LBPD: create/update/remove alongside the bill, since it's tracked in the same slideover.
    if (form.lbpd_facility_id && form.lbpd_created_at && form.lbpd_principal) {
      const lbpdPayload: any = {
        bill_id: billId, facility_id: form.lbpd_facility_id, disbursed_at: form.lbpd_created_at, principal: form.lbpd_principal
      }
      if (form.lbpd_id) {
        const { error } = await client.from('lbpd_disbursements').update(lbpdPayload).eq('id', form.lbpd_id)
        if (error) throw error
      } else {
        const { error } = await client.from('lbpd_disbursements').insert({ ...lbpdPayload, company_id: activeCompanyId.value, advance_pct: 0 })
        if (error) throw error
      }
    } else if (form.lbpd_id) {
      const { error } = await client.from('lbpd_disbursements').delete().eq('id', form.lbpd_id)
      if (error) throw error
    }

    toast.add({ title: form.id ? t('lc_tracker.toast.updated') : t('lc_tracker.toast.created') })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('lc_tracker.toast.save_failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

const columns = computed(() => [
  { key: 'lc_no', label: t('lc_tracker.columns.lc_no') },
  { key: 'bank', label: t('lc_tracker.columns.bank') },
  { key: 'party', label: t('lc_tracker.columns.party') },
  { key: 'lc_amount', label: t('lc_tracker.columns.lc_amount') },
  { key: 'tenure', label: t('lc_tracker.columns.tenure') },
  { key: 'submitted_at', label: t('lc_tracker.columns.docs_submitted') },
  { key: 'accepted_at', label: t('lc_tracker.columns.acceptance') },
  { key: 'lbpd_created_at', label: t('lc_tracker.columns.lbpd_created') },
  { key: 'maturity_date', label: t('lc_tracker.columns.maturity') },
  { key: 'received_at', label: t('lc_tracker.columns.received') },
  { key: 'status', label: t('common.status') },
  { key: 'actions', label: '' }
])
</script>

<template>
  <div>
    <PageHeader :kicker="t('lc_tracker.kicker')" :title="t('lc_tracker.title')" :subtitle="t('lc_tracker.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('lc_tracker.new_entry') }}</UButton>
    </PageHeader>

    <div class="grid grid-cols-2 md:grid-cols-5 gap-3 mb-6">
      <StatCard :label="t('lc_tracker.stats.open')" :value="stats.openCount" icon="i-heroicons-document-text" accent="#f59e0b" />
      <StatCard :label="t('lc_tracker.stats.outstanding')" :value="moneyIn(stats.outstandingBdt, 'BDT')" :sub="t('lc_tracker.stats.outstanding_sub')" icon="i-heroicons-banknotes" accent="#38bdf8" />
      <StatCard :label="t('lc_tracker.stats.pending_acceptance')" :value="stats.pendingAcceptance" icon="i-heroicons-clock" accent="#a78bfa" />
      <StatCard :label="t('lc_tracker.stats.due_soon')" :value="stats.dueSoon" :tone="stats.dueSoon > 0 ? 'amber' : 'default'" icon="i-heroicons-exclamation-triangle" accent="#f59e0b" />
      <StatCard :label="t('lc_tracker.stats.overdue')" :value="stats.overdue" :tone="stats.overdue > 0 ? 'red' : 'default'" icon="i-heroicons-fire" accent="#ef4444" />
    </div>

    <UCard>
      <UTable :rows="bills" :columns="columns" :loading="loading">
        <template #lc_no-data="{ row }">
          <NuxtLink :to="`/lcs/${row.lc_id}`" class="num font-medium text-amber-600 dark:text-amber-400 hover:underline">{{ row.lc_no }}</NuxtLink>
          <div class="text-[10.5px] text-gray-400 dark:text-zinc-600 num">{{ row.bill_no }}</div>
        </template>
        <template #bank-data="{ row }">{{ row.bank }}</template>
        <template #party-data="{ row }">{{ row.party }}</template>
        <template #lc_amount-data="{ row }">
          <span class="num font-medium">{{ row.lc_amount != null ? moneyIn(row.lc_amount, row.currency) : '—' }}</span>
        </template>
        <template #tenure-data="{ row }">
          <span class="num">{{ row.lc_type === 'usance' ? t('lc_tracker.tenure_days', { days: row.tenure }) : t('lc_tracker.sight') }}</span>
        </template>
        <template #submitted_at-data="{ row }"><span class="num">{{ fmtDate(row.submitted_at) }}</span></template>
        <template #accepted_at-data="{ row }"><span class="num" :class="!row.accepted_at ? 'text-gray-400 dark:text-zinc-600' : ''">{{ fmtDate(row.accepted_at) }}</span></template>
        <template #lbpd_created_at-data="{ row }"><span class="num" :class="!row.lbpd_created_at ? 'text-gray-400 dark:text-zinc-600' : ''">{{ fmtDate(row.lbpd_created_at) }}</span></template>
        <template #maturity_date-data="{ row }">
          <span class="num" :class="isOverdue(row) ? 'text-red-600 dark:text-red-400 font-medium' : isDueSoon(row) ? 'text-amber-600 dark:text-amber-400 font-medium' : ''">
            {{ fmtDate(row.maturity_date) }}
          </span>
        </template>
        <template #received_at-data="{ row }">
          <div v-if="editingId === row.id" class="flex items-center gap-1">
            <input v-model="editValue" type="date" class="text-xs num bg-white dark:bg-zinc-800 border border-gray-300 dark:border-zinc-700 rounded px-1.5 py-0.5">
            <UButton icon="i-heroicons-check" size="2xs" color="green" variant="soft" @click="saveReceived(row)" />
            <UButton icon="i-heroicons-x-mark" size="2xs" color="gray" variant="ghost" @click="cancelEdit" />
          </div>
          <div v-else class="flex items-center gap-1 group">
            <span class="num" :class="!row.received_at ? 'text-gray-400 dark:text-zinc-600' : 'text-emerald-600 dark:text-emerald-400 font-medium'">{{ fmtDate(row.received_at) }}</span>
            <UButton v-if="canWrite" icon="i-heroicons-pencil-square" size="2xs" variant="ghost" class="opacity-0 group-hover:opacity-100" @click="startEdit(row)" />
            <UButton v-if="canWrite && row.received_at" icon="i-heroicons-x-mark" size="2xs" color="red" variant="ghost" class="opacity-0 group-hover:opacity-100" @click="clearReceived(row)" />
          </div>
        </template>
        <template #status-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="statusColor(row.status)">{{ statusLabel(row.status) }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <UButton v-if="canWrite" icon="i-heroicons-pencil-square" size="xs" variant="ghost" @click="openEdit(row)" />
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('lc_tracker.empty') }}</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ form.id ? t('lc_tracker.modal.edit_title') : t('lc_tracker.modal.new_title') }}</p></template>
        <div class="grid grid-cols-2 gap-4">
          <UFormGroup :label="t('lc_tracker.modal.lc_label')" required class="col-span-2">
            <USelect v-model="form.lc_id" :options="lcOptions" option-attribute="lc_no" value-attribute="id" :placeholder="t('lc_tracker.modal.lc_placeholder')" />
          </UFormGroup>
          <UFormGroup :label="t('lc_tracker.modal.bill_no_label')" required><UInput v-model="form.bill_no" /></UFormGroup>
          <UFormGroup :label="t('lc_tracker.modal.amount_label')"><UInput v-model.number="form.amount" type="number" /></UFormGroup>
          <UFormGroup :label="t('common.status')">
            <USelect v-model="form.status" :options="statusOptions" option-attribute="label" value-attribute="value" />
          </UFormGroup>
          <UFormGroup :label="t('lc_tracker.columns.docs_submitted')"><UInput v-model="form.submitted_at" type="date" /></UFormGroup>
          <UFormGroup :label="t('lc_tracker.columns.acceptance')"><UInput v-model="form.accepted_at" type="date" /></UFormGroup>
          <UFormGroup :label="t('lc_tracker.columns.maturity')"><UInput v-model="form.maturity_date" type="date" /></UFormGroup>
          <UFormGroup :label="t('lc_tracker.columns.received')"><UInput v-model="form.received_at" type="date" /></UFormGroup>

          <div class="col-span-2 border-t border-gray-100 dark:border-zinc-800 pt-3 mt-1">
            <p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('lc_tracker.modal.lbpd_header') }}</p>
          </div>
          <UFormGroup :label="t('lc_tracker.modal.lbpd_facility_label')">
            <USelect v-model="form.lbpd_facility_id" :options="facilities" option-attribute="name" value-attribute="id" :placeholder="t('lc_tracker.modal.lbpd_facility_placeholder')" />
          </UFormGroup>
          <UFormGroup :label="t('lc_tracker.columns.lbpd_created')"><UInput v-model="form.lbpd_created_at" type="date" /></UFormGroup>
          <UFormGroup :label="t('lc_tracker.modal.lbpd_principal_label')" class="col-span-2">
            <UInput v-model.number="form.lbpd_principal" type="number" />
          </UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ form.id ? t('common.save') : t('lc_tracker.modal.create') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
