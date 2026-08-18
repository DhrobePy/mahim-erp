<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { moneyIn, num } = useFmt()
const { t } = useI18n()

const bills = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const { data, error } = await client.from('bills')
    .select(`
      id, bill_no, amount, submitted_at, accepted_at, maturity_date, received_at, status,
      lcs!inner(id, lc_no, lc_role, lc_type, usance_days, currency,
        counterparty:counterparty_party_id(name),
        bank:bank_party_id(name),
        lc_amendments(version, amount)),
      lbpd_disbursements(disbursed_at, settled_at, status)
    `)
    .eq('lcs.lc_role', 'export_local')
    .is('deleted_at', null)
    .order('submitted_at', { ascending: false })
  if (error) { toast.add({ title: t('lc_tracker.toast.load_failed'), description: error.message, color: 'red' }); loading.value = false; return }

  bills.value = (data ?? []).map((row: any) => {
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
      submitted_at: row.submitted_at,
      accepted_at: row.accepted_at,
      lbpd_created_at: lbpd?.disbursed_at ?? null,
      maturity_date: row.maturity_date,
      received_at: row.received_at,
      status: row.status
    }
  })
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
  { key: 'status', label: t('common.status') }
])
</script>

<template>
  <div>
    <PageHeader :kicker="t('lc_tracker.kicker')" :title="t('lc_tracker.title')" :subtitle="t('lc_tracker.subtitle')" />

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
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('lc_tracker.empty') }}</div>
        </template>
      </UTable>
    </UCard>
  </div>
</template>
