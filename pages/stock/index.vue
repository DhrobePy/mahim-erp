<script setup lang="ts">
const client = useSupabaseClient()
const user = useSupabaseUser()
const toast = useToast()
const { canWrite } = useProfile()
const { t } = useI18n()

const rows = ref<any[]>([])
const items = ref<any[]>([])
const warehouses = ref<any[]>([])
const loading = ref(true)

const columns = computed(() => [
  { key: 'item', label: t('stock.columns.item') },
  { key: 'sku', label: t('stock.columns.sku') },
  { key: 'warehouse', label: t('stock.columns.warehouse') },
  { key: 'qty', label: t('stock.columns.qty') },
  { key: 'reorder', label: t('stock.columns.reorder') },
  { key: 'status', label: t('common.status') }
])

const load = async () => {
  loading.value = true
  const [{ data: stock }, { data: it }, { data: wh }] = await Promise.all([
    client.from('current_stock').select('*'),
    client.from('items').select('id, sku, name, reorder_level, uoms(code)').is('deleted_at', null),
    client.from('warehouses').select('id, code, name').is('deleted_at', null)
  ])
  items.value = it ?? []
  warehouses.value = wh ?? []

  const itemMap = new Map((it ?? []).map((i: any) => [i.id, i]))
  const whMap = new Map((wh ?? []).map((w: any) => [w.id, w]))
  rows.value = (stock ?? [])
    .map((s: any) => {
      const item = itemMap.get(s.item_id)
      return {
        item: item?.name || '—',
        sku: item?.sku || '—',
        uom: item?.uoms?.code || '',
        warehouse: whMap.get(s.warehouse_id)?.code || '—',
        qty: Number(s.qty),
        reorder: Number(item?.reorder_level || 0)
      }
    })
    .sort((a, b) => a.item.localeCompare(b.item))
  loading.value = false
}
onMounted(load)

// --- Stock adjustment / opening entry ---
const open = ref(false)
const saving = ref(false)
const adj = reactive({
  item_id: null as string | null,
  warehouse_id: null as string | null,
  movement_type: 'adjustment',
  quantity: 0,
  unit_cost: 0,
  note: ''
})
const adjTypes = computed(() => [
  { value: 'opening', label: t('stock.adj_types.opening') },
  { value: 'adjustment', label: t('stock.adj_types.adjustment') },
  { value: 'grn_in', label: t('stock.adj_types.grn_in') }
])

const openAdj = () => {
  Object.assign(adj, { item_id: null, warehouse_id: warehouses.value[0]?.id ?? null, movement_type: 'adjustment', quantity: 0, unit_cost: 0, note: '' })
  open.value = true
}

const saveAdj = async () => {
  if (!adj.item_id || !adj.warehouse_id) {
    toast.add({ title: t('stock.select_item_warehouse'), color: 'red' })
    return
  }
  saving.value = true
  try {
    const { error } = await client.from('stock_movements').insert({
      item_id: adj.item_id,
      warehouse_id: adj.warehouse_id,
      movement_type: adj.movement_type,
      quantity: Number(adj.quantity),
      unit_cost: Number(adj.unit_cost),
      ref_no: 'MANUAL',
      note: adj.note,
      created_by: user.value?.id
    })
    if (error) throw error
    toast.add({ title: t('stock.stock_updated') })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('stock.failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('stock.kicker')" :title="t('stock.title')" :subtitle="t('stock.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openAdj">{{ t('stock.stock_entry') }}</UButton>
    </PageHeader>

    <UCard>
      <UTable :rows="rows" :columns="columns" :loading="loading">
        <template #qty-data="{ row }">
          <span class="num font-semibold dark:text-zinc-100">{{ Number(row.qty).toLocaleString('en-IN') }}</span>
          <span class="text-gray-400 dark:text-zinc-600 text-xs ml-1">{{ row.uom }}</span>
        </template>
        <template #status-data="{ row }">
          <UBadge
            v-if="row.reorder > 0 && row.qty <= row.reorder"
            size="xs" color="amber" variant="subtle"
          >{{ t('stock.low') }}</UBadge>
          <UBadge v-else size="xs" color="green" variant="subtle">{{ t('stock.ok') }}</UBadge>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('stock.no_stock') }}</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('stock.stock_entry') }}</p></template>
        <div class="space-y-4">
          <UFormGroup :label="t('stock.fields.item')" required>
            <USelect
              v-model="adj.item_id" :options="items"
              option-attribute="name" value-attribute="id" :placeholder="t('stock.fields.select_item')"
            />
          </UFormGroup>
          <div class="grid grid-cols-2 gap-4">
            <UFormGroup :label="t('stock.fields.warehouse')" required>
              <USelect v-model="adj.warehouse_id" :options="warehouses" option-attribute="code" value-attribute="id" />
            </UFormGroup>
            <UFormGroup :label="t('common.type')">
              <USelect v-model="adj.movement_type" :options="adjTypes" option-attribute="label" value-attribute="value" />
            </UFormGroup>
            <UFormGroup :label="t('stock.fields.quantity')" required>
              <UInput v-model.number="adj.quantity" type="number" />
            </UFormGroup>
            <UFormGroup :label="t('stock.fields.unit_cost')">
              <UInput v-model.number="adj.unit_cost" type="number" />
            </UFormGroup>
          </div>
          <UFormGroup :label="t('common.note')">
            <UInput v-model="adj.note" />
          </UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="saveAdj">{{ t('stock.post') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
