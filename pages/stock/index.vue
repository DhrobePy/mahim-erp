<script setup lang="ts">
const client = useSupabaseClient()
const user = useSupabaseUser()
const toast = useToast()
const { canWrite } = useProfile()
const { t } = useI18n()

const rows = ref<any[]>([])
const items = ref<any[]>([])
const warehouses = ref<any[]>([])
const manualEntries = ref<any[]>([])
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
  const [{ data: stock }, { data: it }, { data: wh }, { data: man }] = await Promise.all([
    client.from('current_stock').select('*'),
    client.from('items').select('id, sku, name, reorder_level, uoms(code)').is('deleted_at', null),
    client.from('warehouses').select('id, code, name').is('deleted_at', null),
    client.from('stock_movements')
      .select('id, item_id, warehouse_id, movement_type, quantity, unit_cost, note, moved_at, items(sku, name), warehouses(code)')
      .eq('ref_no', 'MANUAL')
      .order('moved_at', { ascending: false })
      .limit(100)
  ])
  items.value = it ?? []
  warehouses.value = wh ?? []
  manualEntries.value = man ?? []

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
  id: null as string | null,
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
  Object.assign(adj, { id: null, item_id: null, warehouse_id: warehouses.value[0]?.id ?? null, movement_type: 'adjustment', quantity: 0, unit_cost: 0, note: '' })
  open.value = true
}
const openEditAdj = (row: any) => {
  Object.assign(adj, {
    id: row.id, item_id: row.item_id, warehouse_id: row.warehouse_id, movement_type: row.movement_type,
    quantity: row.quantity, unit_cost: row.unit_cost, note: row.note ?? ''
  })
  open.value = true
}

const saveAdj = async () => {
  if (!adj.item_id || !adj.warehouse_id) {
    toast.add({ title: t('stock.select_item_warehouse'), color: 'red' })
    return
  }
  saving.value = true
  try {
    if (adj.id) {
      const { error } = await client.from('stock_movements').update({
        item_id: adj.item_id, warehouse_id: adj.warehouse_id, movement_type: adj.movement_type,
        quantity: Number(adj.quantity), unit_cost: Number(adj.unit_cost), note: adj.note
      }).eq('id', adj.id).eq('ref_no', 'MANUAL')
      if (error) throw error
      toast.add({ title: t('stock.stock_entry_updated') })
    } else {
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
    }
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('stock.failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

const removeAdj = async (row: any) => {
  if (!confirm(t('stock.delete_confirm', { note: row.note || row.items?.sku }))) return
  const { error } = await client.from('stock_movements').delete().eq('id', row.id).eq('ref_no', 'MANUAL')
  if (error) toast.add({ title: t('stock.failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('stock.stock_entry_deleted') }); await load() }
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('stock.kicker')" :title="t('stock.title')" :subtitle="t('stock.subtitle')">
      <UButton icon="i-heroicons-printer" variant="soft" color="gray" to="/print/stock" target="_blank">{{ t('common.print') }}</UButton>
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

    <UCard v-if="manualEntries.length" class="mt-6">
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('stock.manual_entries.header') }}</p></template>
      <UTable
        :rows="manualEntries"
        :columns="[
          { key: 'date', label: t('common.date') }, { key: 'item', label: t('stock.columns.item') },
          { key: 'warehouse', label: t('stock.columns.warehouse') }, { key: 'type', label: t('common.type') },
          { key: 'qty', label: t('stock.columns.qty') }, { key: 'note', label: t('common.note') },
          { key: 'actions', label: '' }
        ]"
      >
        <template #date-data="{ row }"><span class="num">{{ new Date(row.moved_at).toISOString().slice(0, 10) }}</span></template>
        <template #item-data="{ row }">{{ row.items?.sku }}</template>
        <template #warehouse-data="{ row }">{{ row.warehouses?.code }}</template>
        <template #type-data="{ row }">{{ t(`stock.adj_types.${row.movement_type}`) }}</template>
        <template #qty-data="{ row }"><span class="num">{{ Number(row.quantity).toLocaleString('en-IN') }}</span></template>
        <template #note-data="{ row }"><span class="text-gray-400 dark:text-zinc-500">{{ row.note || '—' }}</span></template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton v-if="canWrite" icon="i-heroicons-pencil-square" variant="ghost" size="xs" @click="openEditAdj(row)" />
            <UButton v-if="canWrite" icon="i-heroicons-trash" color="red" variant="ghost" size="xs" @click="removeAdj(row)" />
          </div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ adj.id ? t('stock.edit_entry') : t('stock.stock_entry') }}</p></template>
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
            <UButton :loading="saving" @click="saveAdj">{{ adj.id ? t('common.save') : t('stock.post') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
