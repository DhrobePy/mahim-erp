<script setup lang="ts">
const route = useRoute()
const client = useSupabaseClient()
const { money } = useFmt()

const id = route.params.id as string
const party = ref<any>(null)
const balances = ref<any[]>([])
const sos = ref<any[]>([])
const invoices = ref<any[]>([])
const grns = ref<any[]>([])
const debitNotes = ref<any[]>([])
const lcs = ref<any[]>([])
const recentLines = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [p, bal, s, i, g, dn, l, jl] = await Promise.all([
    client.from('parties').select('*').eq('id', id).single(),
    client.from('journal_lines')
      .select('debit, credit, accounts(code, name, account_type)')
      .eq('party_id', id),
    client.from('sales_orders').select('id, so_no, order_date, status, lcs(lc_no)').eq('customer_party_id', id).order('created_at', { ascending: false }).limit(15),
    client.from('invoices').select('id, invoice_no, invoice_date, total, status').eq('customer_party_id', id).order('created_at', { ascending: false }).limit(15),
    client.from('grns').select('id, grn_no, grn_date, status, mushak_61_no').eq('supplier_party_id', id).order('created_at', { ascending: false }).limit(15),
    client.from('debit_notes').select('dn_no, qty, amount, created_at').eq('supplier_party_id', id).limit(10),
    client.from('lcs').select('id, lc_no, status, opened_at').or(`counterparty_party_id.eq.${id},bank_party_id.eq.${id}`).limit(15),
    client.from('journal_lines')
      .select('debit, credit, note, journal_id, accounts(code, name), journals(journal_no, journal_date, memo)')
      .eq('party_id', id).order('journal_id', { ascending: false }).limit(20)
  ])
  party.value = p.data
  // per-account net balance for this party
  const agg = new Map<string, any>()
  for (const row of (bal.data ?? []) as any[]) {
    const k = row.accounts?.code
    const cur = agg.get(k) ?? { ...row.accounts, net: 0 }
    cur.net += Number(row.debit) - Number(row.credit)
    agg.set(k, cur)
  }
  balances.value = [...agg.values()].filter((b) => Math.abs(b.net) > 0.004)
  sos.value = s.data ?? []
  invoices.value = i.data ?? []
  grns.value = g.data ?? []
  debitNotes.value = dn.data ?? []
  lcs.value = l.data ?? []
  recentLines.value = jl.data ?? []
  loading.value = false
}
onMounted(load)

const receivable = computed(() =>
  balances.value.filter((b) => b.account_type === 'asset').reduce((s, b) => s + b.net, 0))
const payable = computed(() =>
  -balances.value.filter((b) => b.account_type === 'liability').reduce((s, b) => s + b.net, 0))
const roles = computed(() => {
  const r: string[] = []
  if (party.value?.is_customer) r.push('customer')
  if (party.value?.is_supplier) r.push('supplier')
  if (party.value?.is_transporter) r.push('transporter')
  if (party.value?.is_bank) r.push('bank')
  return r
})
</script>

<template>
  <div v-if="party">
    <PageHeader
      kicker="Parties"
      :title="party.name"
      :subtitle="`${party.code}${party.phone ? ' · ' + party.phone : ''}${party.address ? ' · ' + party.address : ''}${party.bin_no ? ' · BIN ' + party.bin_no : ''}`"
    >
      <UBadge v-for="r in roles" :key="r" variant="subtle">{{ r }}</UBadge>
    </PageHeader>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
      <StatCard label="Receivable from them" :value="money(receivable)" :tone="receivable > 0 ? 'amber' : 'default'" />
      <StatCard label="Payable to them" :value="money(payable)" :tone="payable > 0 ? 'red' : 'default'" />
      <StatCard label="Invoices" :value="invoices.length" :sub="money(invoices.reduce((s, i) => s + Number(i.total), 0)) + ' lifetime'" />
      <StatCard label="Open orders" :value="sos.filter(s => ['open','partially_delivered'].includes(s.status)).length" />
    </div>

    <div class="grid grid-cols-1 xl:grid-cols-2 gap-4">
      <div class="space-y-4">
        <UCard v-if="balances.length">
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Ledger position by account</p></template>
          <div v-for="b in balances" :key="b.code" class="flex justify-between py-1 text-[13px]">
            <span><span class="num text-gray-400 dark:text-zinc-600 mr-2">{{ b.code }}</span>{{ b.name }}</span>
            <span class="num font-medium" :class="b.net >= 0 ? 'dark:text-zinc-100' : 'text-red-500 dark:text-red-400'">
              {{ money(Math.abs(b.net)) }} {{ b.net >= 0 ? 'Dr' : 'Cr' }}
            </span>
          </div>
        </UCard>

        <UCard v-if="sos.length">
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Sales orders</p></template>
          <div v-for="s in sos" :key="s.id" class="flex justify-between py-1 text-[13px]">
            <NuxtLink :to="`/sales/${s.id}`" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ s.so_no }}</NuxtLink>
            <span class="text-gray-500 dark:text-zinc-500">{{ s.order_date }} · {{ s.status }}{{ s.lcs ? ' · ' + s.lcs.lc_no : '' }}</span>
          </div>
        </UCard>

        <UCard v-if="lcs.length">
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">LCs</p></template>
          <div v-for="l in lcs" :key="l.id" class="flex justify-between py-1 text-[13px]">
            <NuxtLink :to="`/lcs/${l.id}`" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ l.lc_no }}</NuxtLink>
            <span class="text-gray-500 dark:text-zinc-500">{{ l.opened_at }} · {{ l.status }}</span>
          </div>
        </UCard>

        <UCard v-if="grns.length || debitNotes.length">
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Supplier history</p></template>
          <div v-for="g in grns" :key="g.id" class="flex justify-between py-1 text-[13px]">
            <NuxtLink to="/procurement" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ g.grn_no }}</NuxtLink>
            <span class="text-gray-500 dark:text-zinc-500">{{ g.grn_date }} · {{ g.status }}{{ g.mushak_61_no ? ' · 6.1 ' + g.mushak_61_no : '' }}</span>
          </div>
          <div v-for="d in debitNotes" :key="d.dn_no" class="flex justify-between py-1 text-[13px]">
            <span class="num text-red-500 dark:text-red-400">{{ d.dn_no }}</span>
            <span class="num text-gray-500 dark:text-zinc-500">gap {{ d.qty }} · {{ money(d.amount) }}</span>
          </div>
        </UCard>
      </div>

      <div class="space-y-4">
        <UCard v-if="invoices.length">
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Invoices</p></template>
          <div v-for="i in invoices" :key="i.id" class="flex justify-between py-1 text-[13px]">
            <NuxtLink :to="`/invoices/${i.id}`" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ i.invoice_no }}</NuxtLink>
            <span class="num text-gray-500 dark:text-zinc-500">{{ i.invoice_date }} · {{ money(i.total) }} · {{ i.status }}</span>
          </div>
        </UCard>

        <UCard>
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Recent ledger entries</p></template>
          <div v-if="!recentLines.length" class="text-sm text-gray-400 py-3 text-center">No postings yet.</div>
          <div v-for="(l, i) in recentLines" :key="i" class="py-1.5 border-b border-gray-100 dark:border-zinc-800/60 last:border-0 text-[12.5px]">
            <div class="flex justify-between">
              <NuxtLink :to="`/accounting/journal/${l.journal_id}`" class="num text-amber-600 dark:text-amber-400 hover:underline">
                {{ l.journals?.journal_no }}
              </NuxtLink>
              <span class="num" :class="Number(l.debit) ? 'dark:text-zinc-100' : 'text-gray-500 dark:text-zinc-500'">
                {{ Number(l.debit) ? 'Dr ' + money(l.debit) : 'Cr ' + money(l.credit) }}
              </span>
            </div>
            <p class="text-gray-500 dark:text-zinc-500">{{ l.accounts?.code }} {{ l.accounts?.name }} — {{ l.journals?.memo }}</p>
          </div>
        </UCard>
      </div>
    </div>
  </div>
  <div v-else-if="!loading" class="text-sm text-gray-400 py-10 text-center">Party not found.</div>
</template>
