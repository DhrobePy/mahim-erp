<script setup lang="ts">
const client = useSupabaseClient()
const { num, money } = useFmt()
const { t } = useI18n()
const { movementTypeLabel } = useStockMovementLabel()

const stats = reactive({
  bank: 0, receivables: 0, lbpd: 0, stockValue: 0,
  items: 0, lowStock: 0, openOrders: 0, unbilled: 0
})

// Tween each figure from its previous value to the newly-loaded one on
// every fetch (initial load and the 60s auto-refresh alike) instead of
// snapping — the numbers are the whole point of this page, they should
// feel alive when they move, not just appear.
const animBank = useAnimatedNumber(() => stats.bank)
const animReceivables = useAnimatedNumber(() => stats.receivables)
const animLbpd = useAnimatedNumber(() => stats.lbpd)
const animStockValue = useAnimatedNumber(() => stats.stockValue)
const animItems = useAnimatedNumber(() => stats.items)
const animLowStock = useAnimatedNumber(() => stats.lowStock)
const animOpenOrders = useAnimatedNumber(() => stats.openOrders)
const animUnbilled = useAnimatedNumber(() => stats.unbilled)

const recent = ref<any[]>([])
const journals = ref<any[]>([])
const loading = ref(true)
const error = ref(false)
const lastUpdated = ref<Date | null>(null)

// Pulls `data`/`count` out of a Promise.allSettled entry, treating a
// rejected promise or a Supabase-level { error } the same way: as a gap
// to degrade around, never as a reason to blank the whole dashboard.
const pluck = <T,>(r: PromiseSettledResult<any>, field: 'data' | 'count'): T | null => {
  if (r.status !== 'fulfilled' || r.value?.error) return null
  return r.value[field] ?? null
}

const load = async () => {
  loading.value = true
  try {
    const results = await Promise.allSettled([
      client.from('account_balances').select('code, balance'),
      // count: 'exact' without head: true — a HEAD-only count request is
      // liable to get silently aborted in some environments (observed in
      // local dev); a normal GET with a Prefer: count header is just as
      // cheap for a handful of id-only rows and doesn't have that failure mode.
      client.from('items').select('id', { count: 'exact' }).eq('is_active', true).is('deleted_at', null),
      client.from('current_stock').select('item_id, qty, stock_value'),
      client.from('production_orders').select('id', { count: 'exact' })
        .in('status', ['planned', 'released', 'in_progress']),
      client.from('delivery_challans').select('id', { count: 'exact' })
        .eq('status', 'delivered_unbilled'),
      client.from('stock_movements')
        .select('id, movement_type, quantity, moved_at, ref_no, items(name, reorder_level)')
        .order('moved_at', { ascending: false }).limit(9),
      client.from('journals').select('id, journal_no, journal_date, memo').order('created_at', { ascending: false }).limit(6),
      client.from('items').select('id, reorder_level').is('deleted_at', null)
    ])

    error.value = results.some((r) => r.status === 'rejected' || (r.status === 'fulfilled' && r.value?.error))

    const balances = pluck<any[]>(results[0], 'data')
    const itemCount = pluck<number>(results[1], 'count')
    const stockRows = pluck<any[]>(results[2], 'data')
    const openCount = pluck<number>(results[3], 'count')
    const unbilledCount = pluck<number>(results[4], 'count')
    const movements = pluck<any[]>(results[5], 'data')
    const jvs = pluck<any[]>(results[6], 'data')
    const lowStockItems = pluck<any[]>(results[7], 'data')

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

    const qtyByItem = new Map<string, number>()
    ;(stockRows ?? []).forEach((r: any) => qtyByItem.set(r.item_id, (qtyByItem.get(r.item_id) || 0) + Number(r.qty)))
    stats.lowStock = (lowStockItems ?? []).filter((i: any) =>
      Number(i.reorder_level) > 0 && (qtyByItem.get(i.id) || 0) <= Number(i.reorder_level)
    ).length

    recent.value = movements ?? []
    journals.value = jvs ?? []
    lastUpdated.value = new Date()
  } catch {
    error.value = true
  } finally {
    loading.value = false
  }
}

let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  load()
  timer = setInterval(load, 60000)
})
onUnmounted(() => { if (timer) clearInterval(timer) })

const updatedLabel = computed(() => lastUpdated.value
  ? t('dashboard.updated_at', { time: lastUpdated.value.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }) })
  : '')
</script>

<template>
  <div>
    <PageHeader :kicker="t('dashboard.kicker')" :title="t('dashboard.title')" :subtitle="t('dashboard.subtitle')">
      <div class="flex items-center gap-3">
        <span v-if="updatedLabel" class="num text-[11px] text-gray-400 dark:text-zinc-500">{{ updatedLabel }}</span>
        <UButton icon="i-heroicons-arrow-path" size="xs" variant="ghost" :loading="loading" @click="load">
          {{ t('dashboard.refresh') }}
        </UButton>
      </div>
    </PageHeader>

    <div v-if="error" class="mb-3 flex items-center justify-between gap-3 rounded-md ring-1 ring-red-300/70 dark:ring-red-800/60 bg-red-50 dark:bg-red-950/30 px-4 py-2.5 text-sm text-red-700 dark:text-red-300">
      <span>{{ t('dashboard.load_failed') }}</span>
      <UButton size="xs" variant="soft" color="red" :loading="loading" @click="load">{{ t('dashboard.retry') }}</UButton>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-3">
      <StatCard :label="t('dashboard.stats.bank')" :value="money(animBank)" :tone="stats.bank < 0 ? 'red' : 'default'" to="/banking" :delay="0" />
      <StatCard :label="t('dashboard.stats.receivables')" :value="money(animReceivables)" to="/invoices" :delay="40" />
      <StatCard :label="t('dashboard.stats.lbpd')" :value="money(animLbpd)" :tone="stats.lbpd > 0 ? 'amber' : 'default'" to="/banking" :delay="80" />
      <StatCard :label="t('dashboard.stats.stock_value')" :value="money(animStockValue)" to="/stock" :delay="120" />
    </div>
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
      <StatCard :label="t('dashboard.stats.active_items')" :value="num(animItems, 0)" to="/items" :delay="160" />
      <StatCard :label="t('dashboard.stats.low_stock')" :value="num(animLowStock, 0)" :tone="stats.lowStock ? 'red' : 'green'" to="/stock" :delay="200" />
      <StatCard :label="t('dashboard.stats.open_production')" :value="num(animOpenOrders, 0)" to="/production" :delay="240" />
      <StatCard :label="t('dashboard.stats.unbilled')" :value="num(animUnbilled, 0)" :tone="stats.unbilled ? 'amber' : 'default'" to="/challans" :delay="280" />
    </div>

    <div class="grid grid-cols-1 xl:grid-cols-3 gap-3">
      <UCard class="xl:col-span-2 animate-fade-in-up" style="animation-delay: 320ms">
        <template #header>
          <h2 class="microlabel flex items-center gap-1.5 text-gray-400 dark:text-zinc-500">
            <UIcon name="i-heroicons-archive-box" class="text-[13px]" />
            {{ t('dashboard.stock_movements') }}
          </h2>
        </template>
        <div v-if="loading && !recent.length" class="space-y-2.5 py-1">
          <div v-for="i in 4" :key="i" class="flex items-center justify-between gap-3">
            <USkeleton class="h-3.5 w-40" />
            <USkeleton class="h-3.5 w-14" />
          </div>
        </div>
        <div v-else-if="!recent.length" class="text-sm text-gray-400 py-6 text-center">{{ t('dashboard.no_movements') }}</div>
        <ul v-else class="divide-y divide-gray-100 dark:divide-zinc-800/60 -my-1">
          <li v-for="m in recent" :key="m.id" class="py-[7px] flex items-center justify-between gap-3 text-[13px]">
            <div class="min-w-0 flex items-center gap-2">
              <span class="truncate dark:text-zinc-200">{{ m.items?.name || '—' }}</span>
              <span class="num text-[11px] text-gray-400 dark:text-zinc-600">{{ m.ref_no }}</span>
            </div>
            <div class="flex items-center gap-3 shrink-0">
              <span class="microlabel text-gray-400 dark:text-zinc-500">{{ movementTypeLabel(m.movement_type) }}</span>
              <span class="num font-medium w-24 text-right" :class="Number(m.quantity) >= 0 ? 'text-emerald-600 dark:text-emerald-400' : 'text-red-600 dark:text-red-400'">
                {{ Number(m.quantity) >= 0 ? '+' : '' }}{{ num(m.quantity) }}
              </span>
            </div>
          </li>
        </ul>
      </UCard>

      <UCard class="animate-fade-in-up" style="animation-delay: 360ms">
        <template #header>
          <h2 class="microlabel flex items-center gap-1.5 text-gray-400 dark:text-zinc-500">
            <UIcon name="i-heroicons-calculator" class="text-[13px]" />
            {{ t('dashboard.latest_journals') }}
          </h2>
        </template>
        <div v-if="loading && !journals.length" class="space-y-2.5 py-1">
          <div v-for="i in 3" :key="i" class="space-y-1.5">
            <div class="flex items-center justify-between">
              <USkeleton class="h-3 w-16" />
              <USkeleton class="h-3 w-20" />
            </div>
            <USkeleton class="h-2.5 w-full" />
          </div>
        </div>
        <ul v-else class="divide-y divide-gray-100 dark:divide-zinc-800/60 -my-1">
          <li v-for="j in journals" :key="j.id" class="py-[7px] text-[12px]">
            <div class="flex items-center justify-between">
              <NuxtLink :to="`/accounting/journal/${j.id}`" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ j.journal_no }}</NuxtLink>
              <span class="num text-gray-400 dark:text-zinc-600">{{ j.journal_date }}</span>
            </div>
            <p class="text-gray-500 dark:text-zinc-400 truncate">{{ j.memo }}</p>
          </li>
          <li v-if="!journals.length" class="py-4 text-center text-sm text-gray-400">{{ t('dashboard.nothing_posted') }}</li>
        </ul>
      </UCard>
    </div>
  </div>
</template>
