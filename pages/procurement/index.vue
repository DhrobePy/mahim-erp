<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()

const grns = ref<any[]>([])
const debitNotes = ref<any[]>([])
const suppliers = ref<any[]>([])
const items = ref<any[]>([])
const warehouses = ref<any[]>([])
const openPOs = ref<any[]>([])
const loading = ref(true)

const columns = [
  { key: 'grn_no', label: 'GRN' },
  { key: 'supplier', label: 'Supplier' },
  { key: 'grn_date', label: 'Date' },
  { key: 'mushak_61_no', label: 'Mushak 6.1' },
  { key: 'status', label: 'Status' },
  { key: 'actions', label: '' }
]

const load = async () => {
  loading.value = true
  const [g, d, s, i, w, po] = await Promise.all([
    client.from('grns').select('*, parties(name), grn_lines(id, item_id, invoice_qty, accepted_qty, unit_price)').order('created_at', { ascending: false }),
    client.from('debit_notes').select('*, parties(name)').order('created_at', { ascending: false }),
    client.from('parties').select('id, code, name').eq('is_supplier', true).order('name'),
    client.from('items').select('id, sku, name').eq('is_active', true).order('sku'),
    client.from('warehouses').select('id, code, name').order('code'),
    client.from('purchase_orders')
      .select('id, po_no, supplier_party_id, status, v_purchase_order_lines(id, item_id, qty, received_qty, landed_unit_cost)')
      .in('status', ['approved', 'partially_received'])
  ])
  grns.value = g.data ?? []
  debitNotes.value = d.data ?? []
  suppliers.value = s.data ?? []
  items.value = i.data ?? []
  warehouses.value = w.data ?? []
  openPOs.value = po.data ?? []
  loading.value = false
}
onMounted(load)

// PO picker in "New GRN" — filtered to the chosen supplier's open POs.
const supplierPOs = computed(() =>
  openPOs.value.filter((p) => p.supplier_party_id === form.supplier_party_id)
)
const selectedPOId = ref<string | null>(null)
const applyPO = (poId: string | null) => {
  const po = openPOs.value.find((p) => p.id === poId)
  if (!po) return
  const remaining = po.v_purchase_order_lines.filter((l: any) => l.received_qty < l.qty)
  if (!remaining.length) { toast.add({ title: 'This PO has nothing left to receive', color: 'amber' }); return }
  lines.value = remaining.map((l: any) => ({
    ...blankLine(),
    item_id: l.item_id,
    invoice_qty: l.qty - l.received_qty,
    gross_weight: null, // let complete_grn's coalesce fall back to invoice_qty — no scale reading yet
    unit_price: Number(l.landed_unit_cost).toFixed(4),
    po_line_id: l.id
  }))
}

// --- New GRN ---
const open = ref(false)
const saving = ref(false)
const form = reactive({
  supplier_party_id: null as string | null,
  warehouse_id: null as string | null,
  mushak_61_no: '',
  vat_applicable: true,
  note: ''
})
const lines = ref<any[]>([])
const blankLine = () => ({
  item_id: null, invoice_qty: 0, gross_weight: 0,
  core_tare_weight: 0, moisture_pct: 0, unit_price: 0, batch_no: '', is_fsc: false, po_line_id: null as string | null
})
const openNew = () => {
  Object.assign(form, { supplier_party_id: null, warehouse_id: null, mushak_61_no: '', vat_applicable: true, note: '' })
  lines.value = [blankLine()]
  selectedPOId.value = null
  open.value = true
}

// live preview of the QA true-net computation
const trueNet = (l: any) =>
  Math.round(((l.gross_weight || l.invoice_qty || 0) - (l.core_tare_weight || 0))
    * (1 - Math.max((l.moisture_pct || 0) - 12, 0) / 100) * 1000) / 1000

const save = async (complete: boolean) => {
  if (!form.supplier_party_id) {
    toast.add({ title: 'Pick a supplier', color: 'red' }); return
  }
  saving.value = true
  try {
    const { data: grn, error } = await client.from('grns')
      .insert({ ...form } as any).select('id').single()
    if (error) throw error
    const payload = lines.value
      .filter((l) => l.item_id)
      .map((l) => ({ ...l, grn_id: (grn as any).id, batch_no: l.batch_no || null }))
    if (!payload.length) throw new Error('Add at least one line')
    const res = await client.from('grn_lines').insert(payload as any)
    if (res.error) throw res.error
    if (complete) {
      const rpc = await client.rpc('complete_grn', { p_grn_id: (grn as any).id } as any)
      if (rpc.error) throw rpc.error
    }
    toast.add({ title: complete ? 'GRN completed & posted' : 'GRN saved as draft' })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: 'GRN failed', description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

const completeDraft = async (row: any) => {
  const { error } = await client.rpc('complete_grn', { p_grn_id: row.id } as any)
  if (error) toast.add({ title: 'Completion failed', description: error.message, color: 'red' })
  else { toast.add({ title: `${row.grn_no} completed & posted` }); await load() }
}

const statusColor = (s: string) =>
  s === 'completed' ? 'green' : s === 'cancelled' ? 'red' : 'yellow'
</script>

<template>
  <div>
    <PageHeader kicker="Procurement" title="Goods receipt (GRN)" subtitle="QA-adjusted true net weight — liability posts on acceptance only">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New GRN</UButton>
    </PageHeader>

    <UCard class="mb-6">
      <UTable :rows="grns" :columns="columns" :loading="loading">
        <template #grn_no-data="{ row }">
          <span class="num font-medium dark:text-zinc-100">{{ row.grn_no }}</span>
        </template>
        <template #supplier-data="{ row }">
          <NuxtLink :to="`/parties/${row.supplier_party_id}`" class="hover:underline">{{ row.parties?.name }}</NuxtLink>
        </template>
        <template #mushak_61_no-data="{ row }">{{ row.mushak_61_no || '—' }}</template>
        <template #status-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="statusColor(row.status)">{{ row.status }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <UButton
            v-if="canWrite && row.status === 'draft'"
            size="xs" variant="soft" @click="completeDraft(row)"
          >Complete &amp; post</UButton>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">No GRNs yet.</div>
        </template>
      </UTable>
    </UCard>

    <UCard>
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Debit notes — QA gaps issued to suppliers</p></template>
      <UTable
        :rows="debitNotes"
        :columns="[
          { key: 'dn_no', label: 'DN' },
          { key: 'supplier', label: 'Supplier' },
          { key: 'qty', label: 'Qty gap' },
          { key: 'amount', label: 'Amount (৳)' },
          { key: 'reason', label: 'Reason' }
        ]"
      >
        <template #supplier-data="{ row }">
          <NuxtLink :to="`/parties/${row.supplier_party_id}`" class="hover:underline">{{ row.parties?.name }}</NuxtLink>
        </template>
        <template #qty-data="{ row }"><span class="num">{{ row.qty }}</span></template>
        <template #amount-data="{ row }"><span class="num text-red-600 dark:text-red-400">{{ row.amount }}</span></template>
        <template #empty-state>
          <div class="text-center py-4 text-sm text-gray-400">No debit notes.</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-3xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New GRN</p></template>
        <div class="grid grid-cols-3 gap-3 mb-4">
          <UFormGroup label="Supplier" required>
            <USelect v-model="form.supplier_party_id" :options="suppliers" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup label="Warehouse">
            <USelect v-model="form.warehouse_id" :options="warehouses" option-attribute="name" value-attribute="id" placeholder="Default" />
          </UFormGroup>
          <UFormGroup label="Supplier Mushak 6.1 no.">
            <UInput v-model="form.mushak_61_no" />
          </UFormGroup>
          <UFormGroup v-if="supplierPOs.length" label="Receive against purchase order" class="col-span-3" hint="Prefills lines with remaining qty and landed unit cost">
            <USelect
              v-model="selectedPOId" :options="supplierPOs" option-attribute="po_no" value-attribute="id"
              placeholder="Standalone receipt — no PO" @update:model-value="applyPO"
            />
          </UFormGroup>
        </div>

        <div class="space-y-3">
          <div v-for="(l, idx) in lines" :key="idx" class="grid grid-cols-4 gap-2 items-end border-b border-gray-100 dark:border-zinc-800/60 pb-3">
            <UFormGroup label="Item" class="col-span-2">
              <USelect v-model="l.item_id" :options="items" option-attribute="sku" value-attribute="id" placeholder="—" />
            </UFormGroup>
            <UFormGroup label="Invoice qty"><UInput v-model.number="l.invoice_qty" type="number" /></UFormGroup>
            <UFormGroup label="Unit price"><UInput v-model.number="l.unit_price" type="number" /></UFormGroup>
            <UFormGroup label="Gross wt."><UInput v-model.number="l.gross_weight" type="number" /></UFormGroup>
            <UFormGroup label="Core/tare"><UInput v-model.number="l.core_tare_weight" type="number" /></UFormGroup>
            <UFormGroup label="Moisture %"><UInput v-model.number="l.moisture_pct" type="number" step="0.1" /></UFormGroup>
            <UFormGroup label="Batch / roll"><UInput v-model="l.batch_no" placeholder="optional" /></UFormGroup>
            <div class="col-span-4 flex items-center justify-between text-xs text-gray-500">
              <UCheckbox v-model="l.is_fsc" label="FSC certified roll" />
              <span>
                True net: <span class="num font-semibold text-emerald-600 dark:text-emerald-400">{{ trueNet(l) }}</span>
                <span v-if="l.invoice_qty && trueNet(l) < l.invoice_qty" class="num text-amber-600 dark:text-amber-400 ml-1">
                  (gap {{ Math.round((l.invoice_qty - trueNet(l)) * 1000) / 1000 }} → debit note)
                </span>
              </span>
            </div>
          </div>
          <UButton size="xs" variant="soft" icon="i-heroicons-plus" @click="lines.push(blankLine())">Add line</UButton>
        </div>

        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">Cancel</UButton>
            <UButton color="gray" variant="soft" :loading="saving" @click="save(false)">Save draft</UButton>
            <UButton :loading="saving" @click="save(true)">Complete &amp; post</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
