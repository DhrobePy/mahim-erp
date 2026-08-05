<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const orders = ref<any[]>([])
const customers = ref<any[]>([])
const items = ref<any[]>([])
const lcs = ref<any[]>([])
const loading = ref(true)

const columns = computed(() => [
  { key: 'so_no', label: t('sales.index.columns.so') },
  { key: 'customer', label: t('sales.index.columns.buyer') },
  { key: 'order_date', label: t('sales.index.columns.date') },
  { key: 'lc', label: t('sales.index.columns.lc') },
  { key: 'lines', label: t('sales.index.columns.lines') },
  { key: 'status', label: t('sales.index.columns.status') },
  { key: 'actions', label: '' }
])

const load = async () => {
  loading.value = true
  const [o, c, i, l] = await Promise.all([
    client.from('sales_orders')
      .select('*, parties(name), lcs(lc_no), sales_order_lines(id, item_id, qty, unit_price, delivered_qty, items(sku))')
      .is('deleted_at', null)
      .order('created_at', { ascending: false }),
    client.from('parties').select('id, name').eq('is_customer', true).is('deleted_at', null).order('name'),
    client.from('items').select('id, sku, name').eq('is_active', true).is('deleted_at', null).order('sku'),
    client.from('lcs').select('id, lc_no').eq('status', 'active')
  ])
  orders.value = o.data ?? []
  customers.value = c.data ?? []
  items.value = i.data ?? []
  lcs.value = l.data ?? []
  loading.value = false
}
onMounted(load)

const open = ref(false)
const saving = ref(false)
const form = reactive({
  customer_party_id: null as string | null,
  lc_id: null as string | null,
  is_deemed_export: true,
  note: ''
})
const lines = ref<any[]>([])
const blankLine = () => ({ item_id: null, qty: 0, unit_price: 0 })
const openNew = () => {
  Object.assign(form, { customer_party_id: null, lc_id: null, is_deemed_export: true, note: '' })
  lines.value = [blankLine()]
  open.value = true
}

const save = async () => {
  if (!form.customer_party_id) { toast.add({ title: t('sales.index.toast.pick_buyer'), color: 'red' }); return }
  saving.value = true
  try {
    const { data: so, error } = await client.from('sales_orders').insert({ ...form } as any).select('id').single()
    if (error) throw error
    const payload = lines.value.filter((l) => l.item_id && l.qty > 0)
      .map((l) => ({ ...l, so_id: (so as any).id }))
    if (!payload.length) throw new Error(t('sales.index.toast.add_line'))
    const res = await client.from('sales_order_lines').insert(payload as any)
    if (res.error) throw res.error
    toast.add({ title: t('sales.index.toast.created') })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('sales.index.toast.save_failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

const statusColor = (s: string) =>
  ({ open: 'blue', partially_delivered: 'yellow', delivered: 'green', closed: 'gray', cancelled: 'red' } as any)[s] || 'gray'
const statusLabel = (s: string) => t(`sales.statuses.${s}`)
const onDelete = async (row: any) => {
  if (await deleteRecord('sales_orders', row.id, row.so_no)) await load()
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('sales.kicker')" :title="t('sales.index.title')" :subtitle="t('sales.index.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('sales.index.new_order') }}</UButton>
    </PageHeader>

    <UCard>
      <UTable :rows="orders" :columns="columns" :loading="loading">
        <template #so_no-data="{ row }">
          <NuxtLink :to="`/sales/${row.id}`" class="num font-medium text-amber-600 dark:text-amber-400 hover:underline">{{ row.so_no }}</NuxtLink>
        </template>
        <template #customer-data="{ row }">
          <NuxtLink :to="`/parties/${row.customer_party_id}`" class="hover:underline">{{ row.parties?.name }}</NuxtLink>
        </template>
        <template #lc-data="{ row }">
          <UBadge v-if="row.lcs" size="xs" variant="subtle" color="green">{{ row.lcs.lc_no }}</UBadge>
          <UBadge v-else size="xs" variant="subtle" color="amber">{{ t('sales.index.pre_lc') }}</UBadge>
        </template>
        <template #lines-data="{ row }">
          <div class="text-xs space-y-0.5">
            <div v-for="l in row.sales_order_lines" :key="l.id">
              {{ l.items?.sku }} — <span class="num">{{ l.delivered_qty }}/{{ l.qty }}</span> @ <span class="num text-amber-600 dark:text-amber-400">৳{{ l.unit_price }}</span>
            </div>
          </div>
        </template>
        <template #status-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="statusColor(row.status)">{{ statusLabel(row.status) }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton v-if="canWrite" icon="i-heroicons-trash" size="xs" color="red" variant="ghost" :aria-label="t('sales.index.delete_aria')" @click="onDelete(row)" />
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('sales.index.empty') }}</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('sales.index.modal_title') }}</p></template>
        <div class="grid grid-cols-2 gap-4 mb-4">
          <UFormGroup :label="t('sales.index.buyer_label')" required>
            <USelect v-model="form.customer_party_id" :options="customers" option-attribute="name" value-attribute="id" :placeholder="t('sales.index.buyer_placeholder')" />
          </UFormGroup>
          <UFormGroup :label="t('sales.index.lc_label')">
            <USelect v-model="form.lc_id" :options="lcs" option-attribute="lc_no" value-attribute="id" :placeholder="t('sales.index.lc_placeholder')" />
          </UFormGroup>
          <div class="col-span-2">
            <UCheckbox v-model="form.is_deemed_export" :label="t('sales.index.deemed_export_checkbox')" />
          </div>
        </div>
        <div class="space-y-2">
          <div v-for="(l, idx) in lines" :key="idx" class="grid grid-cols-3 gap-2">
            <UFormGroup :label="t('sales.index.item_label')">
              <USelect v-model="l.item_id" :options="items" option-attribute="sku" value-attribute="id" :placeholder="t('sales.index.item_placeholder')" />
            </UFormGroup>
            <UFormGroup :label="t('sales.index.qty_label')"><UInput v-model.number="l.qty" type="number" /></UFormGroup>
            <UFormGroup :label="t('sales.index.unit_price_label')"><UInput v-model.number="l.unit_price" type="number" /></UFormGroup>
          </div>
          <UButton size="xs" variant="soft" icon="i-heroicons-plus" @click="lines.push(blankLine())">{{ t('sales.index.add_line') }}</UButton>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ t('sales.index.create_order') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
