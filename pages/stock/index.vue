<script setup lang="ts">
const client = useSupabaseClient()
const user = useSupabaseUser()
const toast = useToast()
const { canWrite } = useProfile()

const rows = ref<any[]>([])
const items = ref<any[]>([])
const warehouses = ref<any[]>([])
const loading = ref(true)

const columns = [
  { key: 'item', label: 'Item' },
  { key: 'sku', label: 'SKU' },
  { key: 'warehouse', label: 'Warehouse' },
  { key: 'qty', label: 'Qty' },
  { key: 'reorder', label: 'Reorder' },
  { key: 'status', label: 'Status' }
]

const load = async () => {
  loading.value = true
  const [{ data: stock }, { data: it }, { data: wh }] = await Promise.all([
    client.from('current_stock').select('*'),
    client.from('items').select('id, sku, name, reorder_level, uoms(code)'),
    client.from('warehouses').select('id, code, name')
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
const adjTypes = [
  { value: 'opening', label: 'Opening balance' },
  { value: 'adjustment', label: 'Adjustment' },
  { value: 'grn_in', label: 'Goods receipt (in)' }
]

const openAdj = () => {
  Object.assign(adj, { item_id: null, warehouse_id: warehouses.value[0]?.id ?? null, movement_type: 'adjustment', quantity: 0, unit_cost: 0, note: '' })
  open.value = true
}

const saveAdj = async () => {
  if (!adj.item_id || !adj.warehouse_id) {
    toast.add({ title: 'Select item and warehouse', color: 'red' })
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
    toast.add({ title: 'Stock updated' })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: 'Failed', description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div>
    <PageHeader kicker="Operations" title="Stock" subtitle="Current balance by item and warehouse">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openAdj">Stock entry</UButton>
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
          >Low</UBadge>
          <UBadge v-else size="xs" color="green" variant="subtle">OK</UBadge>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">No stock yet. Add a stock entry to begin.</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">Stock entry</p></template>
        <div class="space-y-4">
          <UFormGroup label="Item" required>
            <USelect
              v-model="adj.item_id" :options="items"
              option-attribute="name" value-attribute="id" placeholder="Select item"
            />
          </UFormGroup>
          <div class="grid grid-cols-2 gap-4">
            <UFormGroup label="Warehouse" required>
              <USelect v-model="adj.warehouse_id" :options="warehouses" option-attribute="code" value-attribute="id" />
            </UFormGroup>
            <UFormGroup label="Type">
              <USelect v-model="adj.movement_type" :options="adjTypes" option-attribute="label" value-attribute="value" />
            </UFormGroup>
            <UFormGroup label="Quantity (+in / −out)" required>
              <UInput v-model.number="adj.quantity" type="number" />
            </UFormGroup>
            <UFormGroup label="Unit cost (৳)">
              <UInput v-model.number="adj.unit_cost" type="number" />
            </UFormGroup>
          </div>
          <UFormGroup label="Note">
            <UInput v-model="adj.note" />
          </UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">Cancel</UButton>
            <UButton :loading="saving" @click="saveAdj">Post</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
