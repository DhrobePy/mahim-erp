<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()

const orders = ref<any[]>([])
const customers = ref<any[]>([])
const items = ref<any[]>([])
const lcs = ref<any[]>([])
const loading = ref(true)

const columns = [
  { key: 'so_no', label: 'SO' },
  { key: 'customer', label: 'Buyer' },
  { key: 'order_date', label: 'Date' },
  { key: 'lc', label: 'LC' },
  { key: 'lines', label: 'Lines' },
  { key: 'status', label: 'Status' }
]

const load = async () => {
  loading.value = true
  const [o, c, i, l] = await Promise.all([
    client.from('sales_orders')
      .select('*, parties(name), lcs(lc_no), sales_order_lines(id, item_id, qty, unit_price, delivered_qty, items(sku))')
      .order('created_at', { ascending: false }),
    client.from('parties').select('id, name').eq('is_customer', true).order('name'),
    client.from('items').select('id, sku, name').eq('is_active', true).order('sku'),
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
  if (!form.customer_party_id) { toast.add({ title: 'Pick a buyer', color: 'red' }); return }
  saving.value = true
  try {
    const { data: so, error } = await client.from('sales_orders').insert({ ...form } as any).select('id').single()
    if (error) throw error
    const payload = lines.value.filter((l) => l.item_id && l.qty > 0)
      .map((l) => ({ ...l, so_id: (so as any).id }))
    if (!payload.length) throw new Error('Add at least one line')
    const res = await client.from('sales_order_lines').insert(payload as any)
    if (res.error) throw res.error
    toast.add({ title: 'Sales order created' })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: 'Save failed', description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

const statusColor = (s: string) =>
  ({ open: 'blue', partially_delivered: 'yellow', delivered: 'green', closed: 'gray', cancelled: 'red' } as any)[s] || 'gray'
</script>

<template>
  <div>
    <PageHeader kicker="Sales &amp; Local LC" title="Sales orders" subtitle="Verbal orders welcome — the LC can attach later (flow B)">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New order</UButton>
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
          <UBadge v-else size="xs" variant="subtle" color="amber">pre-LC</UBadge>
        </template>
        <template #lines-data="{ row }">
          <div class="text-xs space-y-0.5">
            <div v-for="l in row.sales_order_lines" :key="l.id">
              {{ l.items?.sku }} — <span class="num">{{ l.delivered_qty }}/{{ l.qty }}</span> @ <span class="num text-amber-600 dark:text-amber-400">৳{{ l.unit_price }}</span>
            </div>
          </div>
        </template>
        <template #status-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="statusColor(row.status)">{{ row.status }}</UBadge>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">No sales orders yet.</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New sales order</p></template>
        <div class="grid grid-cols-2 gap-4 mb-4">
          <UFormGroup label="Buyer" required>
            <USelect v-model="form.customer_party_id" :options="customers" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup label="LC (leave empty if verbal / pending)">
            <USelect v-model="form.lc_id" :options="lcs" option-attribute="lc_no" value-attribute="id" placeholder="No LC yet" />
          </UFormGroup>
          <div class="col-span-2">
            <UCheckbox v-model="form.is_deemed_export" label="Deemed export (zero-rated, revenue account 4100)" />
          </div>
        </div>
        <div class="space-y-2">
          <div v-for="(l, idx) in lines" :key="idx" class="grid grid-cols-3 gap-2">
            <UFormGroup label="Item">
              <USelect v-model="l.item_id" :options="items" option-attribute="sku" value-attribute="id" placeholder="—" />
            </UFormGroup>
            <UFormGroup label="Qty"><UInput v-model.number="l.qty" type="number" /></UFormGroup>
            <UFormGroup label="Unit price (৳)"><UInput v-model.number="l.unit_price" type="number" /></UFormGroup>
          </div>
          <UButton size="xs" variant="soft" icon="i-heroicons-plus" @click="lines.push(blankLine())">Add line</UButton>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">Cancel</UButton>
            <UButton :loading="saving" @click="save">Create order</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
