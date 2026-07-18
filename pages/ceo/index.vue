<script setup lang="ts">
// Executive overview: the whole running business on one screen, every
// figure clickable through to its module. Built entirely from the GL
// and operational tables — nothing here is hand-keyed.
const client = useSupabaseClient()
const { money, num } = useFmt()

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
  const [b, lp, so, ub, bl, al, inv, st, emp, pr, fac, dis] = await Promise.all([
    client.from('account_balances').select('code, name, account_type, balance'),
    client.from('lc_profitability').select('*'),
    client.from('sales_orders').select('id, so_no, status, parties(name), sales_order_lines(qty, unit_price, delivered_qty)').in('status', ['open', 'partially_delivered']),
    client.from('delivery_challans').select('id, challan_no, actual_delivery_date, customer_party_id, parties(name), delivery_challan_lines(qty, unit_price)').eq('status', 'delivered_unbilled'),
    client.from('bills').select('id, bill_no, amount, maturity_date, status, lc_id, lcs(lc_no)').in('status', ['accepted', 'discounted', 'overdue']),
    client.from('v_lc_alerts').select('*'),
    client.from('invoices').select('customer_party_id, total, parties(name)'),
    client.from('current_stock').select('stock_value'),
    client.from('employees').select('id', { count: 'exact', head: true }).eq('is_active', true),
    client.from('payroll_runs').select('run_no, label, total_net, status').eq('run_type', 'monthly').order('created_at', { ascending: false }).limit(1),
    client.from('bank_facilities').select('id, name, limit_amount'),
    client.from('lbpd_disbursements').select('facility_id, principal, status')
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
    <PageHeader kicker="Executive" title="CEO overview" subtitle="The running business at a glance — every number clicks through to its source" />

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
        <template v-if="a.alert_type === 'overdue'">⚠ OVERDUE — bill {{ a.bill_no }} on {{ a.lc_no }} (maturity {{ a.maturity_date }})</template>
        <template v-else-if="a.alert_type === 'maturity_soon'">Bill {{ a.bill_no }} on {{ a.lc_no }} matures in {{ a.days }} day(s)</template>
        <template v-else>Unresolved discrepancy on {{ a.lc_no }}</template>
      </NuxtLink>
    </div>

    <!-- Financial position -->
    <p class="microlabel text-gray-400 dark:text-zinc-500 mb-2">Where the money is</p>
    <div class="grid grid-cols-2 lg:grid-cols-4 xl:grid-cols-7 gap-3 mb-5">
      <NuxtLink to="/accounting"><StatCard label="Bank + cash" :value="money(cash)" :tone="cash < 0 ? 'red' : 'default'" /></NuxtLink>
      <NuxtLink to="/banking"><StatCard label="Bills receivable (LC)" :value="money(receivableLc)" /></NuxtLink>
      <NuxtLink to="/challans"><StatCard label="Delivered, not invoiced" :value="money(gdni)" :tone="gdni > 0 ? 'amber' : 'default'" sub="pre-LC risk" /></NuxtLink>
      <NuxtLink to="/stock"><StatCard label="Stock" :value="money(stockValue)" /></NuxtLink>
      <NuxtLink to="/procurement"><StatCard label="We owe (AP + wages)" :value="money(payable)" :tone="payable > 0 ? 'red' : 'default'" /></NuxtLink>
      <NuxtLink to="/banking"><StatCard label="Bank debt" :value="money(debt)" :tone="debt > 0 ? 'red' : 'default'" /></NuxtLink>
      <NuxtLink to="/accounting"><StatCard label="Net position" :value="money(netPosition)" :tone="netPosition >= 0 ? 'green' : 'red'" /></NuxtLink>
    </div>

    <!-- P&L + pipeline -->
    <p class="microlabel text-gray-400 dark:text-zinc-500 mb-2">Earning &amp; pipeline</p>
    <div class="grid grid-cols-2 lg:grid-cols-4 xl:grid-cols-6 gap-3 mb-5">
      <NuxtLink to="/invoices"><StatCard label="Revenue (to date)" :value="money(typeTotals.income)" /></NuxtLink>
      <NuxtLink to="/accounting"><StatCard label="Expenses" :value="money(typeTotals.expense)" /></NuxtLink>
      <NuxtLink to="/accounting"><StatCard label="Net profit" :value="money(netProfit)" :tone="netProfit >= 0 ? 'green' : 'red'" /></NuxtLink>
      <NuxtLink to="/sales"><StatCard label="Undelivered orders" :value="money(pipelineValue)" :sub="openSos.length + ' order(s)'" /></NuxtLink>
      <NuxtLink to="/challans"><StatCard label="Awaiting LC cover" :value="money(totalUnbilled)" :sub="unbilled.length + ' delivery(ies)'" :tone="totalUnbilled > 0 ? 'amber' : 'default'" /></NuxtLink>
      <NuxtLink to="/banking"><StatCard label="Bills awaiting maturity" :value="money(billsAwaiting)" :sub="bills.length + ' bill(s)'" /></NuxtLink>
    </div>

    <div class="grid grid-cols-1 xl:grid-cols-3 gap-4">
      <!-- LC book -->
      <UCard class="xl:col-span-2">
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">LC contract book — profit per contract</p></template>
        <UTable
          :rows="pnlRows"
          :columns="[
            { key: 'lc_no', label: 'LC' }, { key: 'status', label: 'Status' },
            { key: 'revenue', label: 'Revenue (৳)' }, { key: 'cogs_net', label: 'COGS (৳)' },
            { key: 'fin', label: 'Fees + int (৳)' }, { key: 'contract_profit', label: 'Profit (৳)' }
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
          <template #empty-state><div class="text-center py-4 text-sm text-gray-400">No LC contracts yet.</div></template>
        </UTable>
      </UCard>

      <div class="space-y-4">
        <!-- Top customers -->
        <UCard>
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Top buyers by lifetime billing</p></template>
          <div v-if="!topCustomers.length" class="text-sm text-gray-400 py-3 text-center">No invoices yet.</div>
          <div v-for="c in topCustomers" :key="c.id" class="flex justify-between py-1.5 text-[13px]">
            <NuxtLink :to="`/parties/${c.id}`" class="text-amber-600 dark:text-amber-400 hover:underline truncate">{{ c.name }}</NuxtLink>
            <span class="num font-medium dark:text-zinc-100">{{ money(c.total) }}</span>
          </div>
        </UCard>

        <!-- Facilities -->
        <UCard>
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Facility headroom</p></template>
          <div v-if="!facilities.length" class="text-sm text-gray-400 py-3 text-center">No facilities.</div>
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
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">People</p></template>
          <div class="flex justify-between py-1 text-[13px]">
            <NuxtLink to="/hr" class="hover:underline">Headcount</NuxtLink>
            <span class="num font-medium dark:text-zinc-100">{{ headcount }}</span>
          </div>
          <div v-if="lastPayroll" class="flex justify-between py-1 text-[13px]">
            <NuxtLink to="/hr/payroll" class="hover:underline">Last payroll ({{ lastPayroll.label }})</NuxtLink>
            <span class="num font-medium dark:text-zinc-100">{{ money(lastPayroll.total_net) }} · {{ lastPayroll.status }}</span>
          </div>
        </UCard>

        <!-- Pre-LC deliveries detail -->
        <UCard v-if="unbilled.length">
          <template #header><p class="microlabel text-amber-600 dark:text-amber-400">Goods out on trust (no LC yet)</p></template>
          <div v-for="c in unbilled" :key="c.id" class="flex justify-between py-1.5 text-[13px]">
            <span>
              <NuxtLink to="/challans" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ c.challan_no }}</NuxtLink>
              <NuxtLink :to="`/parties/${c.customer_party_id}`" class="text-gray-500 dark:text-zinc-500 ml-2 hover:underline">{{ c.parties?.name }}</NuxtLink>
            </span>
            <span class="num">{{ money(unbilledValue(c)) }} <span class="text-gray-400 dark:text-zinc-600">since {{ c.actual_delivery_date }}</span></span>
          </div>
        </UCard>
      </div>
    </div>
  </div>
</template>
