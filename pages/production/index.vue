<script setup lang="ts">
const client = useSupabaseClient()
const user = useSupabaseUser()
const toast = useToast()
const { canWrite } = useProfile()

const orders = ref<any[]>([])
const items = ref<any[]>([])
const boms = ref<any[]>([])
const warehouses = ref<any[]>([])
const loading = ref(true)

const statusColor: Record<string, string> = {
  planned: 'blue', released: 'indigo', in_progress: 'amber',
  completed: 'green', cancelled: 'gray'
}

const columns = [
  { key: 'order_no', label: 'Order #' },
  { key: 'item', label: 'Finished item' },
  { key: 'planned_qty', label: 'Planned' },
  { key: 'produced_qty', label: 'Produced' },
  { key: 'status', label: 'Status' },
  { key: 'planned_date', label: 'Date' },
  { key: 'actions', label: '' }
]

const finishedItems = computed(() =>
  items.value.filter((i) => ['finished_good', 'wip'].includes(i.item_type))
)

const load = async () => {
  loading.value = true
  const [{ data: o }, { data: it }, { data: b }, { data: wh }] = await Promise.all([
    client.from('production_orders')
      .select('*, items:finished_item_id(name, sku)')
      .order('created_at', { ascending: false }),
    client.from('items').select('id, sku, name, item_type').eq('is_active', true).order('name'),
    client.from('boms').select('id, name, finished_item_id, output_qty').eq('is_active', true),
    client.from('warehouses').select('id, code, name')
  ])
  orders.value = o ?? []
  items.value = it ?? []
  boms.value = b ?? []
  warehouses.value = wh ?? []
  loading.value = false
}
onMounted(load)

// --- Create order ---
const open = ref(false)
const saving = ref(false)
const form = reactive({
  finished_item_id: null as string | null,
  bom_id: null as string | null,
  warehouse_id: null as string | null,
  planned_qty: 1,
  planned_date: new Date().toISOString().slice(0, 10),
  notes: ''
})

const bomOptions = computed(() =>
  boms.value.filter((b) => !form.finished_item_id || b.finished_item_id === form.finished_item_id)
)

const openNew = () => {
  Object.assign(form, {
    finished_item_id: null, bom_id: null,
    warehouse_id: warehouses.value.find((w) => w.code === 'FG')?.id ?? warehouses.value[0]?.id ?? null,
    planned_qty: 1, planned_date: new Date().toISOString().slice(0, 10), notes: ''
  })
  open.value = true
}

const save = async () => {
  if (!form.finished_item_id) {
    toast.add({ title: 'Select a finished item', color: 'red' })
    return
  }
  saving.value = true
  try {
    const { error } = await client.from('production_orders').insert({
      finished_item_id: form.finished_item_id,
      bom_id: form.bom_id,
      warehouse_id: form.warehouse_id,
      planned_qty: Number(form.planned_qty),
      planned_date: form.planned_date,
      notes: form.notes,
      created_by: user.value?.id
    })
    if (error) throw error
    toast.add({ title: 'Production order created' })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: 'Save failed', description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

// --- Complete order (posts stock via RPC) ---
const completing = ref<string | null>(null)
const completeOrder = async (row: any) => {
  completing.value = row.id
  try {
    const { error } = await client.rpc('complete_production_order', {
      p_order_id: row.id,
      p_qty: Number(row.planned_qty)
    })
    if (error) throw error
    toast.add({ title: `${row.order_no} completed`, description: 'Stock movements posted.' })
    await load()
  } catch (e: any) {
    toast.add({ title: 'Completion failed', description: e.message, color: 'red' })
  } finally {
    completing.value = null
  }
}
</script>

<template>
  <div>
    <PageHeader kicker="Operations" title="Production orders" subtitle="Complete an order to auto-post output and BOM consumption">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New order</UButton>
    </PageHeader>

    <UCard>
      <UTable :rows="orders" :columns="columns" :loading="loading">
        <template #order_no-data="{ row }"><span class="num font-medium text-amber-600 dark:text-amber-400">{{ row.order_no }}</span></template>
        <template #planned_qty-data="{ row }"><span class="num">{{ Number(row.planned_qty).toLocaleString('en-IN') }}</span></template>
        <template #produced_qty-data="{ row }"><span class="num font-medium dark:text-zinc-100">{{ Number(row.produced_qty).toLocaleString('en-IN') }}</span></template>
        <template #item-data="{ row }">{{ row.items?.name || '—' }}</template>
        <template #status-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="statusColor[row.status] || 'gray'">{{ row.status }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <UButton
            v-if="canWrite && row.status !== 'completed' && row.status !== 'cancelled'"
            size="xs" color="green" variant="soft"
            :loading="completing === row.id"
            @click="completeOrder(row)"
          >Complete</UButton>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">No production orders yet.</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New production order</p></template>
        <div class="space-y-4">
          <UFormGroup label="Finished item" required>
            <USelect
              v-model="form.finished_item_id" :options="finishedItems"
              option-attribute="name" value-attribute="id" placeholder="Select"
            />
          </UFormGroup>
          <UFormGroup label="BOM (drives material consumption)">
            <USelect
              v-model="form.bom_id" :options="bomOptions"
              option-attribute="name" value-attribute="id" placeholder="Optional"
            />
          </UFormGroup>
          <div class="grid grid-cols-2 gap-4">
            <UFormGroup label="Planned qty" required>
              <UInput v-model.number="form.planned_qty" type="number" />
            </UFormGroup>
            <UFormGroup label="Output warehouse">
              <USelect v-model="form.warehouse_id" :options="warehouses" option-attribute="code" value-attribute="id" />
            </UFormGroup>
            <UFormGroup label="Planned date" class="col-span-2">
              <UInput v-model="form.planned_date" type="date" />
            </UFormGroup>
          </div>
          <UFormGroup label="Notes">
            <UInput v-model="form.notes" />
          </UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">Cancel</UButton>
            <UButton :loading="saving" @click="save">Create</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
