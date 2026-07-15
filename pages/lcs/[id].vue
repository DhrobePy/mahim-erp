<script setup lang="ts">
const route = useRoute()
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money } = useFmt()
const { extractLc } = usePdfExtract()

const lcId = route.params.id as string
const lc = ref<any>(null)
const events = ref<any[]>([])
const bills = ref<any[]>([])
const docs = ref<any[]>([])
const pnl = ref<any>(null)
const alerts = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [l, e, b, d, p, a] = await Promise.all([
    client.from('lcs').select('*, buyer:buyer_party_id(name), bank:bank_party_id(name), lc_amendments(version, amount, quantity, tolerance_pct, expiry_date, bank_fee, created_at)').eq('id', lcId).single(),
    client.from('lc_events').select('*').eq('lc_id', lcId).order('created_at', { ascending: false }),
    client.from('bills').select('*, invoices(invoice_no)').eq('lc_id', lcId).order('created_at'),
    client.from('lc_documents').select('*').eq('lc_id', lcId).order('created_at', { ascending: false }),
    client.from('lc_profitability').select('*').eq('lc_id', lcId).single(),
    client.from('v_lc_alerts').select('*').eq('lc_id', lcId)
  ])
  lc.value = l.data
  if (lc.value) {
    lc.value.amendments = [...(lc.value.lc_amendments ?? [])].sort((x: any, y: any) => y.version - x.version)
  }
  events.value = e.data ?? []
  bills.value = b.data ?? []
  docs.value = d.data ?? []
  pnl.value = p.data
  alerts.value = a.data ?? []
  loading.value = false
}
onMounted(load)

const active = computed(() => lc.value?.amendments?.[0])

// --- Manual timeline events ---
const eventForm = reactive({ event_type: 'note', detail: '' })
const eventOptions = [
  { value: 'docs_submitted', label: 'Documents submitted to bank' },
  { value: 'discrepancy', label: 'Discrepancy raised' },
  { value: 'discrepancy_resolved', label: 'Discrepancy resolved' },
  { value: 'matured', label: 'Matured' },
  { value: 'note', label: 'Note' }
]
const addEvent = async () => {
  const { error } = await client.from('lc_events').insert({
    company_id: lc.value.company_id, lc_id: lcId,
    event_type: eventForm.event_type, detail: eventForm.detail || null
  } as any)
  if (error) toast.add({ title: 'Event failed', description: error.message, color: 'red' })
  else { eventForm.detail = ''; await load() }
}

// --- Document upload with extraction ---
const uploading = ref(false)
const docType = ref('lc')
const onFile = async (ev: Event) => {
  const file = (ev.target as HTMLInputElement).files?.[0]
  if (!file) return
  uploading.value = true
  try {
    let extracted: any = {}
    if (file.type === 'application/pdf') {
      try { extracted = await extractLc(file) } catch { extracted = { error: 'extraction failed' } }
    }
    const path = `${lc.value.company_id}/${lcId}/${Date.now()}-${file.name}`
    const up = await client.storage.from('lc-docs').upload(path, file)
    if (up.error) throw up.error
    const { raw_text, ...fields } = extracted
    const ins = await client.from('lc_documents').insert({
      company_id: lc.value.company_id, lc_id: lcId, doc_type: docType.value,
      original_name: file.name, file_path: path, extracted: fields
    } as any)
    if (ins.error) throw ins.error
    toast.add({ title: 'Document stored', description: Object.keys(fields).length ? 'Fields extracted — review below' : undefined })
    await load()
  } catch (e: any) {
    toast.add({ title: 'Upload failed', description: e.message, color: 'red' })
  } finally {
    uploading.value = false
    ;(ev.target as HTMLInputElement).value = ''
  }
}

const openDoc = async (doc: any) => {
  const { data } = await client.storage.from('lc-docs').createSignedUrl(doc.file_path, 300)
  if (data?.signedUrl) window.open(data.signedUrl, '_blank')
}

const closeOut = async () => {
  const { error } = await client.rpc('close_lc', { p_lc_id: lcId } as any)
  if (error) toast.add({ title: 'Close-out blocked', description: error.message, color: 'amber' })
  else { toast.add({ title: 'LC closed — final P&L recorded on the timeline' }); await load() }
}

const eventIcon = (t: string) => ({
  opened: 'i-heroicons-flag', amendment: 'i-heroicons-pencil-square',
  docs_submitted: 'i-heroicons-paper-airplane', discrepancy: 'i-heroicons-exclamation-triangle',
  discrepancy_resolved: 'i-heroicons-check-circle', acceptance: 'i-heroicons-hand-thumb-up',
  discounted: 'i-heroicons-banknotes', matured: 'i-heroicons-clock', realized: 'i-heroicons-check-badge',
  overdue: 'i-heroicons-fire', forced_pad: 'i-heroicons-fire', note: 'i-heroicons-chat-bubble-bottom-center-text',
  closed: 'i-heroicons-lock-closed'
} as any)[t] || 'i-heroicons-ellipsis-horizontal'

const eventColor = (t: string) => ({
  discrepancy: 'text-red-500', overdue: 'text-red-500', forced_pad: 'text-red-500',
  acceptance: 'text-emerald-500', realized: 'text-emerald-500', discrepancy_resolved: 'text-emerald-500',
  discounted: 'text-purple-400', amendment: 'text-amber-500', closed: 'text-zinc-400'
} as any)[t] || 'text-zinc-500'

const billColor = (s: string) =>
  ({ submitted: 'gray', accepted: 'blue', discounted: 'purple', realized: 'green', overdue: 'red' } as any)[s] || 'gray'
</script>

<template>
  <div v-if="lc">
    <PageHeader
      kicker="Sales &amp; Local LC"
      :title="`LC ${lc.lc_no}`"
      :subtitle="`${lc.lc_type}${lc.lc_type === 'usance' ? ' ' + lc.usance_days + 'd' : ''} · opened ${lc.opened_at}`"
    >
      <UBadge variant="subtle" :color="lc.status === 'active' ? 'green' : 'gray'">{{ lc.status }}</UBadge>
      <UButton v-if="canWrite && lc.status === 'active'" color="gray" variant="soft" icon="i-heroicons-lock-closed" @click="closeOut">
        Close out
      </UButton>
    </PageHeader>

    <div class="flex flex-wrap gap-3 mb-4 text-[12.5px]">
      <NuxtLink :to="`/parties/${lc.buyer_party_id}`" class="text-amber-600 dark:text-amber-400 hover:underline">
        → buyer: {{ lc.buyer?.name }}
      </NuxtLink>
      <NuxtLink v-if="lc.bank_party_id" :to="`/parties/${lc.bank_party_id}`" class="text-amber-600 dark:text-amber-400 hover:underline">
        → issuing bank: {{ lc.bank?.name }}
      </NuxtLink>
    </div>

    <div v-if="alerts.length" class="mb-4 space-y-1">
      <div
        v-for="(a, i) in alerts" :key="i"
        class="px-3 py-2 rounded ring-1 text-[13px] num"
        :class="a.alert_type === 'overdue'
          ? 'ring-red-500/40 bg-red-500/5 text-red-500 dark:text-red-400'
          : a.alert_type === 'maturity_soon'
            ? 'ring-amber-500/40 bg-amber-500/5 text-amber-600 dark:text-amber-400'
            : 'ring-purple-500/40 bg-purple-500/5 text-purple-500 dark:text-purple-400'"
      >
        <template v-if="a.alert_type === 'overdue'">Bill {{ a.bill_no }} is OVERDUE (maturity {{ a.maturity_date }}) — settle or convert to forced PAD</template>
        <template v-else-if="a.alert_type === 'maturity_soon'">Bill {{ a.bill_no }} matures in {{ a.days }} day(s) — {{ a.maturity_date }}</template>
        <template v-else>Open discrepancy — resolve it on the timeline below</template>
      </div>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-6 gap-3 mb-4">
      <StatCard label="Active terms" :value="active ? 'v' + active.version : '—'" :sub="active ? money(active.amount) + ' · ±' + active.tolerance_pct + '%' : ''" />
      <StatCard label="Revenue" :value="money(pnl?.revenue ?? 0)" />
      <StatCard label="Returns" :value="money(pnl?.returns ?? 0)" :tone="Number(pnl?.returns) > 0 ? 'red' : 'default'" />
      <StatCard label="COGS (net)" :value="money(pnl?.cogs_net ?? 0)" />
      <StatCard label="Bank fees + interest" :value="money(Number(pnl?.bank_fees ?? 0) + Number(pnl?.interest ?? 0))" />
      <StatCard label="Contract profit" :value="money(pnl?.contract_profit ?? 0)" :tone="Number(pnl?.contract_profit) >= 0 ? 'green' : 'red'" />
    </div>

    <div class="grid grid-cols-1 xl:grid-cols-2 gap-4">
      <!-- Timeline -->
      <UCard>
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Lifecycle timeline</p></template>
        <div v-if="canWrite && lc.status === 'active'" class="flex gap-2 mb-4">
          <USelect v-model="eventForm.event_type" :options="eventOptions" option-attribute="label" value-attribute="value" size="xs" class="w-56" />
          <UInput v-model="eventForm.detail" placeholder="Detail…" size="xs" class="flex-1" />
          <UButton size="xs" @click="addEvent">Add</UButton>
        </div>
        <div class="space-y-0">
          <div v-for="e in events" :key="e.id" class="flex gap-3 pb-4 relative">
            <div class="flex flex-col items-center">
              <UIcon :name="eventIcon(e.event_type)" class="text-base shrink-0" :class="eventColor(e.event_type)" />
              <div class="w-px flex-1 bg-gray-200 dark:bg-zinc-800 mt-1" />
            </div>
            <div class="min-w-0 -mt-0.5">
              <p class="text-[13px] font-medium dark:text-zinc-200">
                {{ e.event_type.replace(/_/g, ' ') }}
                <span class="num text-[11px] text-gray-400 dark:text-zinc-600 ml-2">{{ e.event_date }}</span>
              </p>
              <p v-if="e.detail" class="text-[12px] text-gray-500 dark:text-zinc-500">{{ e.detail }}</p>
            </div>
          </div>
          <p v-if="!events.length" class="text-sm text-gray-400 py-3 text-center">No events yet.</p>
        </div>
      </UCard>

      <div class="space-y-4">
        <!-- Bills -->
        <UCard>
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Bills under this LC</p></template>
          <UTable
            :rows="bills"
            :columns="[
              { key: 'bill_no', label: 'Bill' }, { key: 'invoice', label: 'Invoice' },
              { key: 'amount', label: 'Amount (৳)' }, { key: 'maturity_date', label: 'Maturity' },
              { key: 'status', label: 'Status' }
            ]"
          >
            <template #bill_no-data="{ row }"><span class="num">{{ row.bill_no }}</span></template>
            <template #invoice-data="{ row }">
              <NuxtLink :to="`/invoices/${row.invoice_id}`" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ row.invoices?.invoice_no }}</NuxtLink>
            </template>
            <template #amount-data="{ row }"><span class="num text-amber-600 dark:text-amber-400">{{ Number(row.amount).toLocaleString('en-IN') }}</span></template>
            <template #maturity_date-data="{ row }"><span class="num">{{ row.maturity_date || '—' }}</span></template>
            <template #status-data="{ row }">
              <UBadge size="xs" variant="subtle" :color="billColor(row.status)">{{ row.status }}</UBadge>
            </template>
            <template #empty-state><div class="text-center py-3 text-sm text-gray-400">No bills yet — submit one from Invoices.</div></template>
          </UTable>
        </UCard>

        <!-- Documents -->
        <UCard>
          <template #header>
            <div class="flex items-center justify-between">
              <p class="microlabel text-gray-400 dark:text-zinc-500">Documents</p>
              <div v-if="canWrite" class="flex items-center gap-2">
                <USelect v-model="docType" :options="['lc', 'amendment', 'bill', 'other']" size="xs" class="w-28" />
                <label class="cursor-pointer">
                  <span class="text-xs px-2 py-1 rounded bg-amber-500 text-black font-medium">
                    {{ uploading ? 'Extracting…' : 'Upload PDF' }}
                  </span>
                  <input type="file" accept="application/pdf" class="hidden" :disabled="uploading" @change="onFile">
                </label>
              </div>
            </div>
          </template>
          <div v-if="!docs.length" class="text-sm text-gray-400 py-3 text-center">
            No documents. Upload the bank's LC advice PDF — fields are extracted automatically.
          </div>
          <div v-for="d in docs" :key="d.id" class="py-2 border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
            <div class="flex items-center justify-between gap-2">
              <button class="text-[13px] font-medium text-amber-600 dark:text-amber-400 hover:underline cursor-pointer truncate" @click="openDoc(d)">
                {{ d.original_name }}
              </button>
              <div class="flex items-center gap-2 shrink-0">
                <UBadge size="xs" variant="subtle">{{ d.doc_type }}</UBadge>
                <span class="num text-[10px] text-gray-400 dark:text-zinc-600">{{ new Date(d.created_at).toLocaleDateString() }}</span>
              </div>
            </div>
            <p v-if="Object.keys(d.extracted || {}).length" class="num text-[11px] text-gray-500 dark:text-zinc-500 mt-0.5">
              <template v-for="(v, k) in d.extracted" :key="k">
                <span v-if="k !== 'error'" class="mr-3">{{ k }}: <span class="dark:text-zinc-300">{{ v }}</span></span>
              </template>
            </p>
          </div>
        </UCard>
      </div>
    </div>
  </div>
  <div v-else-if="!loading" class="text-sm text-gray-400 py-10 text-center">LC not found.</div>
</template>
