<script setup lang="ts">
const client = useSupabaseClient()
const user = useSupabaseUser()
const toast = useToast()
const { canWrite } = useProfile()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const orders = ref<any[]>([])
const items = ref<any[]>([])
const boms = ref<any[]>([])
const warehouses = ref<any[]>([])
const loading = ref(true)

const statusColor: Record<string, string> = {
  planned: 'blue', released: 'indigo', in_progress: 'amber',
  completed: 'green', cancelled: 'gray'
}

const columns = computed(() => [
  { key: 'order_no', label: t('production.columns.order_no') },
  { key: 'item', label: t('production.columns.item') },
  { key: 'planned_qty', label: t('production.columns.planned') },
  { key: 'produced_qty', label: t('production.columns.produced') },
  { key: 'status', label: t('common.status') },
  { key: 'planned_date', label: t('common.date') },
  { key: 'actions', label: '' }
])

const finishedItems = computed(() =>
  items.value.filter((i) => ['finished_good', 'wip'].includes(i.item_type))
)

const load = async () => {
  loading.value = true
  const [{ data: o }, { data: it }, { data: b }, { data: wh }] = await Promise.all([
    client.from('production_orders')
      .select('*, items:finished_item_id(name, sku)')
      .is('deleted_at', null)
      .order('created_at', { ascending: false }),
    client.from('items').select('id, sku, name, item_type').eq('is_active', true).is('deleted_at', null).order('name'),
    client.from('boms').select('id, name, finished_item_id, output_qty').eq('is_active', true).is('deleted_at', null),
    client.from('warehouses').select('id, code, name').is('deleted_at', null)
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
    toast.add({ title: t('production.select_finished_item'), color: 'red' })
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
    toast.add({ title: t('production.order_created') })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('common.save_failed'), description: e.message, color: 'red' })
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
    toast.add({ title: t('production.order_completed', { order_no: row.order_no }), description: t('production.stock_posted') })
    await load()
  } catch (e: any) {
    toast.add({ title: t('production.completion_failed'), description: e.message, color: 'red' })
  } finally {
    completing.value = null
  }
}

const deleteOrder = async (row: any) => {
  const ok = await deleteRecord('production_orders', row.id, row.order_no)
  if (ok) await load()
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('production.kicker')" :title="t('production.title')" :subtitle="t('production.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('production.new_order') }}</UButton>
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
          <div class="flex items-center gap-1.5 justify-end">
            <UButton
              v-if="canWrite && row.status !== 'completed' && row.status !== 'cancelled'"
              size="xs" color="green" variant="soft"
              :loading="completing === row.id"
              @click="completeOrder(row)"
            >{{ t('production.complete') }}</UButton>
            <UButton
              v-if="canWrite && row.status !== 'completed' && row.status !== 'cancelled'"
              icon="i-heroicons-trash" color="red" variant="ghost" size="xs" @click="deleteOrder(row)"
            />
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('production.no_orders') }}</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('production.new_order_title') }}</p></template>
        <div class="space-y-4">
          <UFormGroup :label="t('production.fields.finished_item')" required>
            <USelect
              v-model="form.finished_item_id" :options="finishedItems"
              option-attribute="name" value-attribute="id" :placeholder="t('production.fields.select')"
            />
          </UFormGroup>
          <UFormGroup :label="t('production.fields.bom')">
            <USelect
              v-model="form.bom_id" :options="bomOptions"
              option-attribute="name" value-attribute="id" :placeholder="t('production.fields.optional')"
            />
          </UFormGroup>
          <div class="grid grid-cols-2 gap-4">
            <UFormGroup :label="t('production.fields.planned_qty')" required>
              <UInput v-model.number="form.planned_qty" type="number" />
            </UFormGroup>
            <UFormGroup :label="t('production.fields.output_warehouse')">
              <USelect v-model="form.warehouse_id" :options="warehouses" option-attribute="code" value-attribute="id" />
            </UFormGroup>
            <UFormGroup :label="t('production.fields.planned_date')" class="col-span-2">
              <UInput v-model="form.planned_date" type="date" />
            </UFormGroup>
          </div>
          <UFormGroup :label="t('common.notes')">
            <UInput v-model="form.notes" />
          </UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ t('production.create') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
