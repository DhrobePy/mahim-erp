<script setup lang="ts">
const route = useRoute()
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { t } = useI18n()
const id = route.params.id as string

const po = ref<any>(null)
const lines = ref<any[]>([])
const grns = ref<any[]>([])
const loading = ref(true)

const statusColor: Record<string, string> = {
  draft: 'gray', approved: 'blue', partially_received: 'amber', received: 'green', closed: 'gray', cancelled: 'red'
}

const load = async () => {
  loading.value = true
  const [{ data: p }, { data: l }, { data: g }] = await Promise.all([
    client.from('purchase_orders').select('*, parties(name, phone, email, address)').eq('id', id).single(),
    client.from('v_purchase_order_lines').select('*, items(sku, name)').eq('po_id', id),
    client.from('grn_lines').select('grn_id, po_line_id, accepted_qty, grns(grn_no, grn_date, status)').in(
      'po_line_id', (await client.from('purchase_order_lines').select('id').eq('po_id', id)).data?.map((r: any) => r.id) ?? ['00000000-0000-0000-0000-000000000000']
    )
  ])
  po.value = p
  lines.value = l ?? []
  grns.value = g ?? []
  loading.value = false
}
onMounted(load)

const totalValue = computed(() => lines.value.reduce((s, l) => s + l.line_value, 0))
const totalLanded = computed(() => po.value ? po.value.freight_cost + po.value.customs_duty + po.value.clearing_agent_fee + po.value.other_landed_cost : 0)

const approve = async () => {
  const { error } = await client.rpc('approve_purchase_order', { p_po_id: id } as any)
  if (error) toast.add({ title: t('procurement.po.detail.approve_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('procurement.po.detail.approved_toast') }); await load() }
}
const cancel = async () => {
  if (!confirm(t('procurement.po.detail.cancel_confirm', { po: po.value.po_no }))) return
  const { error } = await client.rpc('cancel_purchase_order', { p_po_id: id } as any)
  if (error) toast.add({ title: t('procurement.po.detail.cancel_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('procurement.po.detail.cancelled_toast') }); await load() }
}
</script>

<template>
  <div v-if="loading" class="text-sm text-gray-400">{{ t('common.loading') }}</div>
  <div v-else-if="!po" class="text-sm text-gray-400">{{ t('procurement.po.detail.not_found') }}</div>
  <div v-else>
    <PageHeader :kicker="t('procurement.po.kicker')" :title="po.po_no" :subtitle="`${po.parties?.name} · ${t('procurement.po.detail.ordered_prefix')} ${po.order_date}`">
      <UBadge size="sm" :color="statusColor[po.status]" variant="subtle">{{ t(`procurement.statuses.${po.status}`) }}</UBadge>
      <UButton v-if="canWrite && po.status === 'draft'" size="sm" variant="soft" @click="approve">{{ t('procurement.po.approve') }}</UButton>
      <UButton v-if="canWrite && ['draft','approved'].includes(po.status)" size="sm" variant="soft" color="red" @click="cancel">{{ t('procurement.po.cancel') }}</UButton>
    </PageHeader>

    <div class="grid gap-4 md:grid-cols-3 mb-4">
      <StatCard :label="t('procurement.po.detail.ex_factory_value')" :value="`৳${totalValue.toFixed(2)}`" />
      <StatCard :label="t('procurement.po.detail.landed_costs')" :value="`৳${totalLanded.toFixed(2)}`" />
      <StatCard :label="t('procurement.po.detail.total_landed_value')" :value="`৳${(totalValue + totalLanded).toFixed(2)}`" />
    </div>

    <UCard class="mb-4">
      <template #header><p class="text-sm font-medium">{{ t('procurement.po.detail.line_items') }}</p></template>
      <UTable
        :rows="lines"
        :columns="[
          { key: 'item', label: t('procurement.po.detail.columns.item') }, { key: 'qty', label: t('procurement.po.detail.columns.ordered') }, { key: 'unit_price', label: t('procurement.po.detail.columns.ex_factory_price') },
          { key: 'landed_unit_cost', label: t('procurement.po.detail.columns.landed_unit_cost') }, { key: 'received_qty', label: t('procurement.po.detail.columns.received') }
        ]"
      >
        <template #item-data="{ row }">{{ row.items?.sku }} — {{ row.items?.name }}</template>
        <template #qty-data="{ row }"><span class="num">{{ row.qty }}</span></template>
        <template #unit_price-data="{ row }"><span class="num">৳{{ Number(row.unit_price).toFixed(4) }}</span></template>
        <template #landed_unit_cost-data="{ row }">
          <span class="num font-medium text-amber-600 dark:text-amber-400">৳{{ Number(row.landed_unit_cost).toFixed(4) }}</span>
        </template>
        <template #received_qty-data="{ row }">
          <span class="num" :class="row.received_qty >= row.qty ? 'text-green-600 dark:text-green-400' : ''">
            {{ row.received_qty }} / {{ row.qty }}
          </span>
        </template>
      </UTable>
    </UCard>

    <UCard v-if="po.note">
      <template #header><p class="text-sm font-medium">{{ t('procurement.po.detail.note') }}</p></template>
      <p class="text-sm text-gray-600 dark:text-zinc-400">{{ po.note }}</p>
    </UCard>

    <UCard v-if="grns.length" class="mt-4">
      <template #header><p class="text-sm font-medium">{{ t('procurement.po.detail.received_via') }}</p></template>
      <ul class="text-sm divide-y divide-gray-100 dark:divide-zinc-800/60">
        <li v-for="(g, i) in grns" :key="i" class="py-1.5 flex justify-between">
          <NuxtLink :to="`/procurement`" class="text-amber-600 dark:text-amber-400 hover:underline num">{{ g.grns?.grn_no }}</NuxtLink>
          <span class="text-gray-500 dark:text-zinc-500">{{ g.grns?.grn_date }} · {{ g.accepted_qty ?? '—' }} {{ t('procurement.po.detail.accepted') }}</span>
        </li>
      </ul>
    </UCard>
  </div>
</template>
