<script setup lang="ts">
const route = useRoute()
const client = useSupabaseClient()
const { money, num } = useFmt()

const id = route.params.id as string
const so = ref<any>(null)
const challans = ref<any[]>([])
const invoices = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [s, c, i] = await Promise.all([
    client.from('sales_orders')
      .select('*, parties(id, name), lcs(id, lc_no), sales_order_lines(id, qty, unit_price, delivered_qty, items(sku, name))')
      .eq('id', id).single(),
    client.from('delivery_challans')
      .select('id, challan_no, challan_kind, status, document_date, actual_delivery_date, covers:covers_challan_id(challan_no)')
      .eq('so_id', id).order('created_at'),
    client.from('invoices').select('id, invoice_no, invoice_date, total, status').eq('so_id', id)
  ])
  so.value = s.data
  challans.value = c.data ?? []
  invoices.value = i.data ?? []
  loading.value = false
}
onMounted(load)

const orderValue = computed(() =>
  (so.value?.sales_order_lines ?? []).reduce((s: number, l: any) => s + l.qty * l.unit_price, 0))
const deliveredPct = computed(() => {
  const lines = so.value?.sales_order_lines ?? []
  const q = lines.reduce((s: number, l: any) => s + Number(l.qty), 0)
  const d = lines.reduce((s: number, l: any) => s + Number(l.delivered_qty), 0)
  return q ? Math.min(Math.round((d / q) * 100), 100) : 0
})
const kindColor = (k: string) => ({ standard: 'blue', original: 'amber', covering: 'purple' } as any)[k] || 'gray'
const statusColor = (s: string) =>
  ({ draft: 'gray', issued: 'blue', delivered_unbilled: 'amber', covered: 'purple', invoiced: 'green' } as any)[s] || 'gray'
</script>

<template>
  <div v-if="so">
    <PageHeader kicker="Sales &amp; Local LC" :title="so.so_no" :subtitle="`${so.order_date} · ${so.is_deemed_export ? 'deemed export' : 'domestic'}`">
      <UBadge variant="subtle" :color="so.status === 'delivered' ? 'green' : 'blue'">{{ so.status }}</UBadge>
    </PageHeader>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
      <StatCard label="Buyer" :value="so.parties?.name ?? '—'">
      </StatCard>
      <StatCard label="Order value" :value="money(orderValue)" />
      <StatCard label="Delivered" :value="deliveredPct + '%'" :tone="deliveredPct >= 95 ? 'green' : 'amber'" />
      <StatCard label="LC" :value="so.lcs?.lc_no ?? 'pre-LC'" :tone="so.lcs ? 'default' : 'amber'" />
    </div>
    <div class="flex gap-2 mb-4 text-[12.5px]">
      <NuxtLink :to="`/parties/${so.parties?.id}`" class="text-amber-600 dark:text-amber-400 hover:underline">→ buyer profile</NuxtLink>
      <NuxtLink v-if="so.lcs" :to="`/lcs/${so.lcs.id}`" class="text-amber-600 dark:text-amber-400 hover:underline">→ LC lifecycle</NuxtLink>
    </div>

    <div class="grid grid-cols-1 xl:grid-cols-2 gap-4">
      <UCard>
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Lines &amp; fulfilment</p></template>
        <div v-for="l in so.sales_order_lines" :key="l.id" class="py-2 border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
          <div class="flex justify-between text-[13px]">
            <span class="dark:text-zinc-200">{{ l.items?.sku }} — {{ l.items?.name }}</span>
            <span class="num">{{ num(l.delivered_qty, 0) }} / {{ num(l.qty, 0) }} @ ৳{{ l.unit_price }}</span>
          </div>
          <div class="h-1 rounded bg-gray-100 dark:bg-zinc-800 mt-1.5">
            <div
              class="h-1 rounded"
              :class="l.delivered_qty >= l.qty * 0.95 ? 'bg-emerald-500' : 'bg-amber-500'"
              :style="{ width: Math.min((l.delivered_qty / l.qty) * 100, 100) + '%' }"
            />
          </div>
        </div>
      </UCard>

      <div class="space-y-4">
        <UCard>
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Challans</p></template>
          <div v-if="!challans.length" class="text-sm text-gray-400 py-3 text-center">None yet.</div>
          <div v-for="c in challans" :key="c.id" class="flex items-center justify-between py-1.5 text-[13px]">
            <span>
              <NuxtLink to="/challans" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ c.challan_no }}</NuxtLink>
              <UBadge size="xs" variant="subtle" :color="kindColor(c.challan_kind)" class="ml-2">{{ c.challan_kind }}</UBadge>
              <span v-if="c.covers" class="num text-[11px] text-gray-400 dark:text-zinc-600 ml-1">covers {{ c.covers.challan_no }}</span>
            </span>
            <span class="flex items-center gap-2">
              <span class="num text-gray-500 dark:text-zinc-500">{{ c.document_date }}</span>
              <UBadge size="xs" variant="subtle" :color="statusColor(c.status)">{{ c.status }}</UBadge>
            </span>
          </div>
        </UCard>

        <UCard>
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Invoices</p></template>
          <div v-if="!invoices.length" class="text-sm text-gray-400 py-3 text-center">None yet.</div>
          <div v-for="i in invoices" :key="i.id" class="flex justify-between py-1.5 text-[13px]">
            <NuxtLink :to="`/invoices/${i.id}`" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ i.invoice_no }}</NuxtLink>
            <span class="num text-gray-500 dark:text-zinc-500">{{ i.invoice_date }} · {{ money(i.total) }} · {{ i.status }}</span>
          </div>
        </UCard>
      </div>
    </div>
  </div>
  <div v-else-if="!loading" class="text-sm text-gray-400 py-10 text-center">Sales order not found.</div>
</template>
