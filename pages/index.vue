<script setup lang="ts">
const client = useSupabaseClient()
const { num, money } = useFmt()

const stats = reactive({
  bank: 0, receivables: 0, lbpd: 0, stockValue: 0,
  items: 0, lowStock: 0, openOrders: 0, unbilled: 0
})
const recent = ref<any[]>([])
const journals = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [
    { data: balances },
    { count: itemCount },
    { data: stockRows },
    { count: openCount },
    { count: unbilledCount },
    { data: movements },
    { data: jvs }
  ] = await Promise.all([
    client.from('account_balances').select('code, balance'),
    client.from('items').select('id', { count: 'exact', head: true }).eq('is_active', true),
    client.from('current_stock').select('item_id, qty, stock_value'),
    client.from('production_orders').select('id', { count: 'exact', head: true })
      .in('status', ['planned', 'released', 'in_progress']),
    client.from('delivery_challans').select('id', { count: 'exact', head: true })
      .eq('status', 'delivered_unbilled'),
    client.from('stock_movements')
      .select('id, movement_type, quantity, moved_at, ref_no, items(name, reorder_level)')
      .order('moved_at', { ascending: false }).limit(9),
    client.from('journals').select('id, journal_no, journal_date, memo').order('created_at', { ascending: false }).limit(6)
  ])

  const bal = (code: string) => Number((balances ?? []).find((b: any) => b.code === code)?.balance ?? 0)
  const balPrefix = (prefix: string) => (balances ?? [])
    .filter((b: any) => b.code === prefix || b.code.startsWith(prefix + '-'))
    .reduce((s: number, b: any) => s + Number(b.balance ?? 0), 0)
  stats.bank = balPrefix('1100') + balPrefix('1150')
  stats.receivables = bal('1200') + bal('1210') + bal('1220')
  stats.lbpd = -(bal('2300') + bal('2310'))
  stats.stockValue = (stockRows ?? []).reduce((s: number, r: any) => s + Number(r.stock_value || 0), 0)
  stats.items = itemCount ?? 0
  stats.openOrders = openCount ?? 0
  stats.unbilled = unbilledCount ?? 0

  const { data: items } = await client.from('items').select('id, reorder_level')
  const qtyByItem = new Map<string, number>()
  ;(stockRows ?? []).forEach((r: any) => qtyByItem.set(r.item_id, (qtyByItem.get(r.item_id) || 0) + Number(r.qty)))
  stats.lowStock = (items ?? []).filter((i: any) =>
    Number(i.reorder_level) > 0 && (qtyByItem.get(i.id) || 0) <= Number(i.reorder_level)
  ).length

  recent.value = movements ?? []
  journals.value = jvs ?? []
  loading.value = false
}
onMounted(load)
</script>

<template>
  <div>
    <PageHeader kicker="Operations" title="Dashboard" subtitle="Live position across stock, receivables and bank exposure" />

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-3">
      <StatCard label="Bank + cash" :value="money(stats.bank)" :tone="stats.bank < 0 ? 'red' : 'default'" />
      <StatCard label="Receivables (AR + LC + GDNI)" :value="money(stats.receivables)" />
      <StatCard label="LBPD / PAD exposure" :value="money(stats.lbpd)" :tone="stats.lbpd > 0 ? 'amber' : 'default'" />
      <StatCard label="Stock value" :value="money(stats.stockValue)" />
    </div>
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
      <StatCard label="Active items" :value="num(stats.items, 0)" />
      <StatCard label="Low stock" :value="num(stats.lowStock, 0)" :tone="stats.lowStock ? 'red' : 'green'" />
      <StatCard label="Open production" :value="num(stats.openOrders, 0)" />
      <StatCard label="Delivered, unbilled (pre-LC)" :value="num(stats.unbilled, 0)" :tone="stats.unbilled ? 'amber' : 'default'" />
    </div>

    <div class="grid grid-cols-1 xl:grid-cols-3 gap-3">
      <UCard class="xl:col-span-2">
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Stock movements</p></template>
        <div v-if="loading" class="text-sm text-gray-400 py-6 text-center">Loading…</div>
        <div v-else-if="!recent.length" class="text-sm text-gray-400 py-6 text-center">No movements yet.</div>
        <ul v-else class="divide-y divide-gray-100 dark:divide-zinc-800/60 -my-1">
          <li v-for="m in recent" :key="m.id" class="py-[7px] flex items-center justify-between gap-3 text-[13px]">
            <div class="min-w-0 flex items-center gap-2">
              <span class="truncate dark:text-zinc-200">{{ m.items?.name || '—' }}</span>
              <span class="num text-[11px] text-gray-400 dark:text-zinc-600">{{ m.ref_no }}</span>
            </div>
            <div class="flex items-center gap-3 shrink-0">
              <span class="microlabel text-gray-400 dark:text-zinc-500">{{ m.movement_type }}</span>
              <span class="num font-medium w-24 text-right" :class="Number(m.quantity) >= 0 ? 'text-emerald-600 dark:text-emerald-400' : 'text-red-600 dark:text-red-400'">
                {{ Number(m.quantity) >= 0 ? '+' : '' }}{{ num(m.quantity) }}
              </span>
            </div>
          </li>
        </ul>
      </UCard>

      <UCard>
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Latest journals</p></template>
        <ul class="divide-y divide-gray-100 dark:divide-zinc-800/60 -my-1">
          <li v-for="j in journals" :key="j.id" class="py-[7px] text-[12px]">
            <div class="flex items-center justify-between">
              <NuxtLink :to="`/accounting/journal/${j.id}`" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ j.journal_no }}</NuxtLink>
              <span class="num text-gray-400 dark:text-zinc-600">{{ j.journal_date }}</span>
            </div>
            <p class="text-gray-500 dark:text-zinc-400 truncate">{{ j.memo }}</p>
          </li>
          <li v-if="!journals.length" class="py-4 text-center text-sm text-gray-400">Nothing posted yet.</li>
        </ul>
      </UCard>
    </div>
  </div>
</template>
