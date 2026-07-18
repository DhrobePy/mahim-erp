<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()

const pos = ref<any[]>([])
const suppliers = ref<any[]>([])
const items = ref<any[]>([])
const loading = ref(true)

const statusColor: Record<string, string> = {
  draft: 'gray', approved: 'blue', partially_received: 'amber', received: 'green', closed: 'gray', cancelled: 'red'
}

const load = async () => {
  loading.value = true
  const [{ data: p }, { data: sp }, { data: it }] = await Promise.all([
    client.from('purchase_orders')
      .select('*, parties(name), purchase_order_lines(id, qty, unit_price, received_qty)')
      .order('created_at', { ascending: false }),
    client.from('parties').select('id, name').eq('is_supplier', true).order('name'),
    client.from('items').select('id, sku, name').eq('item_type', 'raw_material').eq('is_active', true).order('sku')
  ])
  pos.value = (p ?? []).map((row: any) => ({
    ...row,
    lineCount: row.purchase_order_lines.length,
    value: row.purchase_order_lines.reduce((s: number, l: any) => s + l.qty * l.unit_price, 0)
  }))
  suppliers.value = sp ?? []
  items.value = it ?? []
  loading.value = false
}
onMounted(load)

// --- New PO ---
const open = ref(false)
const saving = ref(false)
const form = reactive({
  supplier_party_id: null as string | null,
  order_date: new Date().toISOString().slice(0, 10),
  expected_date: null as string | null,
  currency: 'BDT',
  freight_cost: 0, customs_duty: 0, clearing_agent_fee: 0, other_landed_cost: 0,
  note: ''
})
const lines = ref<{ item_id: string | null; qty: number; unit_price: number }[]>([])
const addLine = () => lines.value.push({ item_id: null, qty: 1, unit_price: 0 })
const removeLine = (i: number) => lines.value.splice(i, 1)

const totalValue = computed(() => lines.value.reduce((s, l) => s + (Number(l.qty) || 0) * (Number(l.unit_price) || 0), 0))
const totalLanded = computed(() => Number(form.freight_cost) + Number(form.customs_duty) + Number(form.clearing_agent_fee) + Number(form.other_landed_cost))
const landedUnitCost = (l: { qty: number; unit_price: number }) => {
  if (!totalValue.value || !l.qty) return l.unit_price || 0
  const lineValue = (Number(l.qty) || 0) * (Number(l.unit_price) || 0)
  return (Number(l.unit_price) || 0) + (lineValue / totalValue.value) * totalLanded.value / (Number(l.qty) || 1)
}

const openNew = () => {
  Object.assign(form, {
    supplier_party_id: null, order_date: new Date().toISOString().slice(0, 10), expected_date: null,
    currency: 'BDT', freight_cost: 0, customs_duty: 0, clearing_agent_fee: 0, other_landed_cost: 0, note: ''
  })
  lines.value = [{ item_id: null, qty: 1, unit_price: 0 }]
  open.value = true
}

const save = async () => {
  if (!form.supplier_party_id) { toast.add({ title: 'Pick a supplier', color: 'red' }); return }
  const validLines = lines.value.filter((l) => l.item_id && l.qty > 0)
  if (!validLines.length) { toast.add({ title: 'Add at least one line item', color: 'red' }); return }
  saving.value = true
  try {
    const { data: po, error } = await client.from('purchase_orders').insert({
      supplier_party_id: form.supplier_party_id, order_date: form.order_date, expected_date: form.expected_date,
      currency: form.currency, freight_cost: form.freight_cost, customs_duty: form.customs_duty,
      clearing_agent_fee: form.clearing_agent_fee, other_landed_cost: form.other_landed_cost, note: form.note
    } as any).select('id').single()
    if (error) throw error
    const { error: lErr } = await client.from('purchase_order_lines').insert(
      validLines.map((l) => ({ po_id: (po as any).id, item_id: l.item_id, qty: l.qty, unit_price: l.unit_price }))
    )
    if (lErr) throw lErr
    toast.add({ title: 'Purchase order created as draft' })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: 'Save failed', description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

const approve = async (row: any) => {
  const { error } = await client.rpc('approve_purchase_order', { p_po_id: row.id } as any)
  if (error) toast.add({ title: 'Approve failed', description: error.message, color: 'red' })
  else { toast.add({ title: `${row.po_no} approved` }); await load() }
}
const cancel = async (row: any) => {
  if (!confirm(`Cancel ${row.po_no}?`)) return
  const { error } = await client.rpc('cancel_purchase_order', { p_po_id: row.id } as any)
  if (error) toast.add({ title: 'Cancel failed', description: error.message, color: 'red' })
  else { toast.add({ title: `${row.po_no} cancelled` }); await load() }
}
</script>

<template>
  <div>
    <PageHeader kicker="Procurement" title="Purchase orders" subtitle="Raise, approve, and receive raw-material orders — landed cost (freight/duty/clearing) allocated across lines">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New purchase order</UButton>
    </PageHeader>

    <div v-if="loading" class="text-sm text-gray-400">Loading…</div>
    <div v-else-if="!pos.length" class="text-sm text-gray-400">No purchase orders yet.</div>

    <UCard v-else>
      <UTable
        :rows="pos"
        :columns="[
          { key: 'po_no', label: 'PO no.' }, { key: 'supplier', label: 'Supplier' },
          { key: 'order_date', label: 'Order date' }, { key: 'lines', label: 'Lines' },
          { key: 'value', label: 'Value' }, { key: 'status', label: 'Status' }, { key: 'actions', label: '' }
        ]"
      >
        <template #po_no-data="{ row }">
          <NuxtLink :to="`/procurement/purchase-orders/${row.id}`" class="num font-medium text-amber-600 dark:text-amber-400 hover:underline">
            {{ row.po_no }}
          </NuxtLink>
        </template>
        <template #supplier-data="{ row }">{{ row.parties?.name }}</template>
        <template #order_date-data="{ row }"><span class="num">{{ row.order_date }}</span></template>
        <template #lines-data="{ row }"><span class="num">{{ row.lineCount }}</span></template>
        <template #value-data="{ row }"><span class="num">৳{{ row.value.toFixed(2) }}</span></template>
        <template #status-data="{ row }">
          <UBadge size="xs" :color="statusColor[row.status]" variant="subtle">{{ row.status.replace('_', ' ') }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <div class="flex items-center gap-1.5 justify-end">
            <UButton v-if="canWrite && row.status === 'draft'" size="xs" variant="soft" @click="approve(row)">Approve</UButton>
            <UButton
              v-if="canWrite && ['draft','approved'].includes(row.status)"
              size="xs" variant="soft" color="red" @click="cancel(row)"
            >Cancel</UButton>
          </div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-3xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header>
          <p class="font-medium">New purchase order</p>
          <p class="text-xs text-gray-500">Created as draft — approve before receiving against it</p>
        </template>

        <div class="space-y-5">
          <div class="grid grid-cols-2 gap-4">
            <UFormGroup label="Supplier" required class="col-span-2">
              <USelect v-model="form.supplier_party_id" :options="suppliers" option-attribute="name" value-attribute="id" placeholder="Select supplier" />
            </UFormGroup>
            <UFormGroup label="Order date"><UInput v-model="form.order_date" type="date" /></UFormGroup>
            <UFormGroup label="Expected delivery"><UInput v-model="form.expected_date" type="date" /></UFormGroup>
            <UFormGroup label="Currency">
              <USelect v-model="form.currency" :options="['BDT', 'USD', 'EUR']" />
            </UFormGroup>
          </div>

          <div>
            <div class="flex items-center justify-between mb-2">
              <p class="text-sm font-medium">Line items</p>
              <UButton size="xs" variant="soft" icon="i-heroicons-plus" @click="addLine">Add</UButton>
            </div>
            <div v-for="(l, i) in lines" :key="i" class="grid grid-cols-12 gap-2 mb-2 items-center">
              <USelect v-model="l.item_id" :options="items" option-attribute="sku" value-attribute="id" placeholder="Raw material" class="col-span-4" />
              <UInput v-model.number="l.qty" type="number" placeholder="Qty" class="col-span-2" />
              <UInput v-model.number="l.unit_price" type="number" placeholder="Unit price" class="col-span-2" />
              <span class="col-span-3 text-xs text-gray-500 dark:text-zinc-500 num">
                landed: ৳{{ landedUnitCost(l).toFixed(4) }}/unit
              </span>
              <UButton icon="i-heroicons-trash" color="red" variant="ghost" size="xs" class="col-span-1" @click="removeLine(i)" />
            </div>
          </div>

          <div>
            <p class="microlabel text-gray-400 dark:text-zinc-500 mb-1.5">Landed costs (allocated across lines by value share)</p>
            <div class="grid grid-cols-4 gap-2">
              <UFormGroup label="Freight"><UInput v-model.number="form.freight_cost" type="number" /></UFormGroup>
              <UFormGroup label="Customs duty"><UInput v-model.number="form.customs_duty" type="number" /></UFormGroup>
              <UFormGroup label="Clearing fee"><UInput v-model.number="form.clearing_agent_fee" type="number" /></UFormGroup>
              <UFormGroup label="Other"><UInput v-model.number="form.other_landed_cost" type="number" /></UFormGroup>
            </div>
          </div>

          <UFormGroup label="Note"><UTextarea v-model="form.note" :rows="2" /></UFormGroup>

          <div class="rounded ring-1 ring-amber-500/30 bg-amber-50/40 dark:bg-amber-500/[0.04] p-3 flex justify-between text-sm">
            <span class="text-gray-500 dark:text-zinc-500">Ex-factory value</span>
            <span class="num font-medium">৳{{ totalValue.toFixed(2) }}</span>
            <span class="text-gray-500 dark:text-zinc-500">Landed costs</span>
            <span class="num font-medium text-amber-600 dark:text-amber-400">৳{{ totalLanded.toFixed(2) }}</span>
          </div>
        </div>

        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">Cancel</UButton>
            <UButton :loading="saving" @click="save">Save as draft</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
