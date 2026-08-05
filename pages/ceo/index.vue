<script setup lang="ts">
// Executive overview: the whole running business on one screen, every
// figure clickable through to its module. Built entirely from the GL
// and operational tables — nothing here is hand-keyed.
const client = useSupabaseClient()
const { money, num } = useFmt()
const { t } = useI18n()

// Same fixed identity colors as the dashboard where the concept overlaps
// (bank, receivables, stock, the pre-LC exposure family) so the same figure
// reads as the same color everywhere in the app; new concepts on this page
// get the theme's remaining hues, reused per row since the two rows are
// never compared against each other as one combined legend.
const CARD = {
  bank: { accent: '#3987e5', icon: 'i-heroicons-banknotes' },
  billsReceivableLc: { accent: '#9085e9', icon: 'i-heroicons-receipt-percent' },
  gdni: { accent: '#d55181', icon: 'i-heroicons-truck' },
  stock: { accent: '#199e70', icon: 'i-heroicons-cube' },
  payable: { accent: '#d95926', icon: 'i-heroicons-credit-card' },
  debt: { accent: '#e66767', icon: 'i-heroicons-scale' },
  netPosition: { accent: '#22c55e', icon: 'i-heroicons-chart-bar' },
  revenue: { accent: '#22c55e', icon: 'i-heroicons-arrow-trending-up' },
  expenses: { accent: '#e66767', icon: 'i-heroicons-arrow-trending-down' },
  netProfit: { accent: '#c98500', icon: 'i-heroicons-chart-pie' },
  pipeline: { accent: '#9085e9', icon: 'i-heroicons-shopping-cart' },
  awaitingLc: { accent: '#d55181', icon: 'i-heroicons-truck' },
  billsMaturity: { accent: '#3987e5', icon: 'i-heroicons-clock' }
} as const

const sparklines = reactive<Record<string, number[]>>({
  bank: [], billsReceivableLc: [], gdni: [], stock: [], payable: [], debt: [], netPosition: [],
  revenue: [], expenses: [], netProfit: [], pipeline: [], awaitingLc: []
})

const loading = ref(true)
const bal = ref<Map<string, number>>(new Map())
const typeTotals = ref<Record<string, number>>({})
const pnlRows = ref<any[]>([])
const openSos = ref<any[]>([])
const unbilled = ref<any[]>([])
const bills = ref<any[]>([])
const alerts = ref<any[]>([])
const topCustomers = ref<any[]>([])
const stockValue = ref(0)
const headcount = ref(0)
const lastPayroll = ref<any>(null)
const facilities = ref<any[]>([])
const disbs = ref<any[]>([])

const load = async () => {
  loading.value = true
  const [b, lp, so, ub, bl, al, inv, st, emp, pr, fac, dis, jl, mv] = await Promise.all([
    client.from('account_balances').select('code, name, account_type, balance'),
    client.from('lc_profitability').select('*'),
    client.from('sales_orders').select('id, so_no, status, created_at, parties(name), sales_order_lines(qty, unit_price, delivered_qty)').in('status', ['open', 'partially_delivered']),
    client.from('delivery_challans').select('id, challan_no, actual_delivery_date, customer_party_id, parties(name), delivery_challan_lines(qty, unit_price)').eq('status', 'delivered_unbilled'),
    client.from('bills').select('id, bill_no, amount, maturity_date, status, lc_id, lcs(lc_no)').in('status', ['accepted', 'discounted', 'overdue']),
    client.from('v_lc_alerts').select('*'),
    client.from('invoices').select('customer_party_id, total, parties(name)'),
    client.from('current_stock').select('stock_value'),
    client.from('employees').select('id', { count: 'exact', head: true }).eq('is_active', true).is('deleted_at', null),
    client.from('payroll_runs').select('run_no, label, total_net, status').eq('run_type', 'monthly').order('created_at', { ascending: false }).limit(1),
    client.from('bank_facilities').select('id, name, limit_amount').is('deleted_at', null),
    client.from('lbpd_disbursements').select('facility_id, principal, status'),
    // Sparkline feeds — same 14-day-activity approach as the dashboard.
    client.from('journal_lines').select('debit, credit, accounts(code, account_type), journals!inner(journal_date)')
      .order('journal_date', { foreignTable: 'journals', ascending: false }).limit(400),
    client.from('stock_movements').select('quantity, moved_at').order('moved_at', { ascending: false }).limit(200)
  ])

  bal.value = new Map((b.data ?? []).map((r: any) => [r.code, Number(r.balance)]))
  const tt: Record<string, number> = { income: 0, expense: 0 }
  for (const r of (b.data ?? []) as any[]) {
    if (r.account_type === 'income') tt.income += -Number(r.balance)
    if (r.account_type === 'expense') tt.expense += Number(r.balance)
  }
  typeTotals.value = tt
  pnlRows.value = lp.data ?? []
  openSos.value = so.data ?? []
  unbilled.value = ub.data ?? []
  bills.value = bl.data ?? []
  alerts.value = al.data ?? []
  stockValue.value = (st.data ?? []).reduce((s: number, r: any) => s + Number(r.stock_value || 0), 0)
  headcount.value = emp.count ?? 0
  lastPayroll.value = pr.data?.[0] ?? null
  facilities.value = fac.data ?? []
  disbs.value = dis.data ?? []

  const byCust = new Map<string, any>()
  for (const i of (inv.data ?? []) as any[]) {
    const cur = byCust.get(i.customer_party_id) ?? { id: i.customer_party_id, name: i.parties?.name, total: 0 }
    cur.total += Number(i.total)
    byCust.set(i.customer_party_id, cur)
  }
  topCustomers.value = [...byCust.values()].sort((a, b) => b.total - a.total).slice(0, 5)

  // 14-day sparklines, derived from what was actually posted/created —
  // cumulative net (debit − credit) per account prefix for balance-sheet
  // figures, raw daily counts for pipeline/activity figures.
  const jlRows = jl.data ?? []
  const moveHistory = mv.data ?? []
  const netByAccount = (prefixes: string[]) => bucketDaily(
    jlRows.filter((r: any) => prefixes.some((p) => r.accounts?.code === p || r.accounts?.code?.startsWith(p + '-'))),
    (r: any) => r.journals?.journal_date,
    (r: any) => Number(r.debit || 0) - Number(r.credit || 0),
    14, true
  )
  const netByType = (type: string) => bucketDaily(
    jlRows.filter((r: any) => r.accounts?.account_type === type),
    (r: any) => r.journals?.journal_date,
    (r: any) => Number(r.debit || 0) - Number(r.credit || 0),
    14, true
  )

  const cashSpark = netByAccount(['1100', '1150'])
  const billsReceivableLcSpark = netByAccount(['1210'])
  const receivableOpenSpark = netByAccount(['1200'])
  const gdniSpark = netByAccount(['1220'])
  const stockSpark = bucketDaily(moveHistory, (r: any) => r.moved_at, (r: any) => Number(r.quantity) || 0, 14, true)
  const payableRaw = netByAccount(['2100', '2110', '2200'])
  const debtRaw = netByAccount(['2300', '2310', '2320', '2330', '2400'])
  const incomeSpark = netByType('income').map((v) => -v)
  const expenseSpark = netByType('expense')

  sparklines.bank = cashSpark
  sparklines.billsReceivableLc = billsReceivableLcSpark
  sparklines.gdni = gdniSpark
  sparklines.stock = stockSpark
  sparklines.payable = payableRaw.map((v) => -v)
  sparklines.debt = debtRaw.map((v) => -v)
  sparklines.netPosition = cashSpark.map((v, i) =>
    v + billsReceivableLcSpark[i] + receivableOpenSpark[i] + gdniSpark[i] + stockSpark[i] + payableRaw[i] + debtRaw[i])
  sparklines.revenue = incomeSpark
  sparklines.expenses = expenseSpark
  sparklines.netProfit = incomeSpark.map((v, i) => v - expenseSpark[i])
  sparklines.pipeline = bucketDaily(so.data ?? [], (r: any) => r.created_at, () => 1, 14, false)
  sparklines.awaitingLc = bucketDaily(ub.data ?? [], (r: any) => r.actual_delivery_date, () => 1, 14, false)

  loading.value = false
}
onMounted(load)

const g = (code: string) => bal.value.get(code) ?? 0
const gPrefix = (prefix: string) => [...bal.value.entries()]
  .filter(([code]) => code === prefix || code.startsWith(prefix + '-'))
  .reduce((s, [, v]) => s + v, 0)
const cash = computed(() => gPrefix('1100') + gPrefix('1150'))
const receivableLc = computed(() => g('1210'))
const receivableOpen = computed(() => g('1200'))
const gdni = computed(() => g('1220'))
const payable = computed(() => -(g('2100') + g('2110') + g('2200')))
const debt = computed(() => -(g('2300') + g('2310') + g('2320') + g('2330') + g('2400')))
const netPosition = computed(() =>
  cash.value + receivableLc.value + receivableOpen.value + gdni.value + stockValue.value - payable.value - debt.value)
const netProfit = computed(() => typeTotals.value.income - typeTotals.value.expense)

const soValue = (s: any) =>
  (s.sales_order_lines ?? []).reduce((t: number, l: any) => t + (l.qty - l.delivered_qty) * l.unit_price, 0)
const pipelineValue = computed(() => openSos.value.reduce((t, s) => t + soValue(s), 0))
const unbilledValue = (c: any) =>
  (c.delivery_challan_lines ?? []).reduce((t: number, l: any) => t + l.qty * l.unit_price, 0)
const totalUnbilled = computed(() => unbilled.value.reduce((t, c) => t + unbilledValue(c), 0))
const billsAwaiting = computed(() => bills.value.reduce((t, b) => t + Number(b.amount), 0))
const exposure = (f: any) =>
  disbs.value.filter((d) => d.facility_id === f.id && d.status !== 'settled')
    .reduce((s, d) => s + Number(d.principal), 0)
</script>

<template>
  <div>
    <PageHeader :kicker="t('ceo.kicker')" :title="t('ceo.title')" :subtitle="t('ceo.subtitle')" />

    <!-- Alert strip -->
    <div v-if="alerts.length" class="mb-4 space-y-1">
      <NuxtLink
        v-for="(a, i) in alerts" :key="i" :to="`/lcs/${a.lc_id}`"
        class="block px-3 py-2 rounded ring-1 text-[13px] num cursor-pointer hover:opacity-80"
        :class="a.alert_type === 'overdue'
          ? 'ring-red-500/40 bg-red-500/5 text-red-500 dark:text-red-400'
          : a.alert_type === 'maturity_soon'
            ? 'ring-amber-500/40 bg-amber-500/5 text-amber-600 dark:text-amber-400'
            : 'ring-purple-500/40 bg-purple-500/5 text-purple-500 dark:text-purple-400'"
      >
        <template v-if="a.alert_type === 'overdue'">{{ t('ceo.alerts.overdue', { bill: a.bill_no, lc: a.lc_no, date: a.maturity_date }) }}</template>
        <template v-else-if="a.alert_type === 'maturity_soon'">{{ t('ceo.alerts.maturity_soon', { bill: a.bill_no, lc: a.lc_no, days: a.days }) }}</template>
        <template v-else>{{ t('ceo.alerts.discrepancy', { lc: a.lc_no }) }}</template>
      </NuxtLink>
    </div>

    <!-- Financial position -->
    <p class="microlabel text-gray-400 dark:text-zinc-500 mb-2">{{ t('ceo.sections.money') }}</p>
    <div class="grid grid-cols-2 lg:grid-cols-4 xl:grid-cols-7 gap-3 mb-5">
      <StatCard :label="t('ceo.stats.bank')" :value="money(cash)" :tone="cash < 0 ? 'red' : 'default'" to="/accounting" :accent="CARD.bank.accent" :icon="CARD.bank.icon" :points="sparklines.bank" />
      <StatCard :label="t('ceo.stats.bills_receivable_lc')" :value="money(receivableLc)" to="/banking" :accent="CARD.billsReceivableLc.accent" :icon="CARD.billsReceivableLc.icon" :points="sparklines.billsReceivableLc" />
      <StatCard :label="t('ceo.stats.delivered_not_invoiced')" :value="money(gdni)" :tone="gdni > 0 ? 'amber' : 'default'" :sub="t('ceo.stats.pre_lc_risk')" to="/challans" :accent="CARD.gdni.accent" :icon="CARD.gdni.icon" :points="sparklines.gdni" />
      <StatCard :label="t('ceo.stats.stock')" :value="money(stockValue)" to="/stock" :accent="CARD.stock.accent" :icon="CARD.stock.icon" :points="sparklines.stock" />
      <StatCard :label="t('ceo.stats.payable')" :value="money(payable)" :tone="payable > 0 ? 'red' : 'default'" to="/procurement" :accent="CARD.payable.accent" :icon="CARD.payable.icon" :points="sparklines.payable" />
      <StatCard :label="t('ceo.stats.bank_debt')" :value="money(debt)" :tone="debt > 0 ? 'red' : 'default'" to="/banking" :accent="CARD.debt.accent" :icon="CARD.debt.icon" :points="sparklines.debt" />
      <StatCard :label="t('ceo.stats.net_position')" :value="money(netPosition)" :tone="netPosition >= 0 ? 'green' : 'red'" to="/accounting" :accent="CARD.netPosition.accent" :icon="CARD.netPosition.icon" :points="sparklines.netPosition" />
    </div>

    <!-- P&L + pipeline -->
    <p class="microlabel text-gray-400 dark:text-zinc-500 mb-2">{{ t('ceo.sections.earning_pipeline') }}</p>
    <div class="grid grid-cols-2 lg:grid-cols-4 xl:grid-cols-6 gap-3 mb-5">
      <StatCard :label="t('ceo.stats.revenue')" :value="money(typeTotals.income)" to="/invoices" :accent="CARD.revenue.accent" :icon="CARD.revenue.icon" :points="sparklines.revenue" />
      <StatCard :label="t('ceo.stats.expenses')" :value="money(typeTotals.expense)" to="/accounting" :accent="CARD.expenses.accent" :icon="CARD.expenses.icon" :points="sparklines.expenses" />
      <StatCard :label="t('ceo.stats.net_profit')" :value="money(netProfit)" :tone="netProfit >= 0 ? 'green' : 'red'" to="/accounting" :accent="CARD.netProfit.accent" :icon="CARD.netProfit.icon" :points="sparklines.netProfit" />
      <StatCard :label="t('ceo.stats.undelivered_orders')" :value="money(pipelineValue)" :sub="openSos.length + ' ' + t('ceo.orders_suffix')" to="/sales" :accent="CARD.pipeline.accent" :icon="CARD.pipeline.icon" :points="sparklines.pipeline" />
      <StatCard :label="t('ceo.stats.awaiting_lc_cover')" :value="money(totalUnbilled)" :sub="unbilled.length + ' ' + t('ceo.deliveries_suffix')" :tone="totalUnbilled > 0 ? 'amber' : 'default'" to="/challans" :accent="CARD.awaitingLc.accent" :icon="CARD.awaitingLc.icon" :points="sparklines.awaitingLc" />
      <StatCard :label="t('ceo.stats.bills_awaiting_maturity')" :value="money(billsAwaiting)" :sub="bills.length + ' ' + t('ceo.bills_suffix')" to="/banking" :accent="CARD.billsMaturity.accent" :icon="CARD.billsMaturity.icon" />
    </div>

    <div class="grid grid-cols-1 xl:grid-cols-3 gap-4">
      <!-- LC book -->
      <UCard class="xl:col-span-2">
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('ceo.sections.lc_book') }}</p></template>
        <UTable
          :rows="pnlRows"
          :columns="[
            { key: 'lc_no', label: t('ceo.table.lc') }, { key: 'status', label: t('common.status') },
            { key: 'revenue', label: t('ceo.table.revenue') }, { key: 'cogs_net', label: t('ceo.table.cogs') },
            { key: 'fin', label: t('ceo.table.fees_interest') }, { key: 'contract_profit', label: t('ceo.table.profit') }
          ]"
        >
          <template #lc_no-data="{ row }">
            <NuxtLink :to="`/lcs/${row.lc_id}`" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ row.lc_no }}</NuxtLink>
          </template>
          <template #status-data="{ row }">
            <UBadge size="xs" variant="subtle" :color="row.status === 'active' ? 'green' : 'gray'">{{ row.status }}</UBadge>
          </template>
          <template #revenue-data="{ row }"><span class="num">{{ num(row.revenue) }}</span></template>
          <template #cogs_net-data="{ row }"><span class="num">{{ num(row.cogs_net) }}</span></template>
          <template #fin-data="{ row }"><span class="num">{{ num(Number(row.bank_fees) + Number(row.interest)) }}</span></template>
          <template #contract_profit-data="{ row }">
            <span class="num font-semibold" :class="Number(row.contract_profit) >= 0 ? 'text-emerald-600 dark:text-emerald-400' : 'text-red-600 dark:text-red-400'">
              {{ num(row.contract_profit) }}
            </span>
          </template>
          <template #empty-state><div class="text-center py-4 text-sm text-gray-400">{{ t('ceo.empty.lc_contracts') }}</div></template>
        </UTable>
      </UCard>

      <div class="space-y-4">
        <!-- Top customers -->
        <UCard>
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('ceo.sections.top_buyers') }}</p></template>
          <div v-if="!topCustomers.length" class="text-sm text-gray-400 py-3 text-center">{{ t('ceo.empty.invoices') }}</div>
          <div v-for="c in topCustomers" :key="c.id" class="flex justify-between py-1.5 text-[13px]">
            <NuxtLink :to="`/parties/${c.id}`" class="text-amber-600 dark:text-amber-400 hover:underline truncate">{{ c.name }}</NuxtLink>
            <span class="num font-medium dark:text-zinc-100">{{ money(c.total) }}</span>
          </div>
        </UCard>

        <!-- Facilities -->
        <UCard>
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('ceo.sections.facility_headroom') }}</p></template>
          <div v-if="!facilities.length" class="text-sm text-gray-400 py-3 text-center">{{ t('ceo.empty.facilities') }}</div>
          <div v-for="f in facilities" :key="f.id" class="py-1.5">
            <div class="flex justify-between text-[13px]">
              <NuxtLink to="/banking" class="hover:underline">{{ f.name }}</NuxtLink>
              <span class="num">{{ money(exposure(f)) }} / {{ money(f.limit_amount) }}</span>
            </div>
            <div class="h-1 rounded bg-gray-100 dark:bg-zinc-800 mt-1">
              <div
                class="h-1 rounded"
                :class="exposure(f) > f.limit_amount * 0.9 ? 'bg-red-500' : 'bg-amber-500'"
                :style="{ width: Math.min((exposure(f) / (f.limit_amount || 1)) * 100, 100) + '%' }"
              />
            </div>
          </div>
        </UCard>

        <!-- People -->
        <UCard>
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('ceo.sections.people') }}</p></template>
          <div class="flex justify-between py-1 text-[13px]">
            <NuxtLink to="/hr" class="hover:underline">{{ t('ceo.headcount') }}</NuxtLink>
            <span class="num font-medium dark:text-zinc-100">{{ headcount }}</span>
          </div>
          <div v-if="lastPayroll" class="flex justify-between py-1 text-[13px]">
            <NuxtLink to="/hr/payroll" class="hover:underline">{{ t('ceo.last_payroll', { label: lastPayroll.label }) }}</NuxtLink>
            <span class="num font-medium dark:text-zinc-100">{{ money(lastPayroll.total_net) }} · {{ lastPayroll.status }}</span>
          </div>
        </UCard>

        <!-- Pre-LC deliveries detail -->
        <UCard v-if="unbilled.length">
          <template #header><p class="microlabel text-amber-600 dark:text-amber-400">{{ t('ceo.sections.pre_lc') }}</p></template>
          <div v-for="c in unbilled" :key="c.id" class="flex justify-between py-1.5 text-[13px]">
            <span>
              <NuxtLink to="/challans" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ c.challan_no }}</NuxtLink>
              <NuxtLink :to="`/parties/${c.customer_party_id}`" class="text-gray-500 dark:text-zinc-500 ml-2 hover:underline">{{ c.parties?.name }}</NuxtLink>
            </span>
            <span class="num">{{ money(unbilledValue(c)) }} <span class="text-gray-400 dark:text-zinc-600">{{ t('ceo.since', { date: c.actual_delivery_date }) }}</span></span>
          </div>
        </UCard>
      </div>
    </div>
  </div>
</template>
