<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { deleteRecord } = useRecycleBin()
const { replaceLines } = useLineReconcile()
const { t } = useI18n()

const grns = ref<any[]>([])
const debitNotes = ref<any[]>([])
const suppliers = ref<any[]>([])
const items = ref<any[]>([])
const warehouses = ref<any[]>([])
const openPOs = ref<any[]>([])
const loading = ref(true)

const columns = [
  { key: 'grn_no', label: t('procurement.grn.columns.grn_no') },
  { key: 'supplier', label: t('procurement.grn.columns.supplier') },
  { key: 'grn_date', label: t('procurement.grn.columns.date') },
  { key: 'mushak_61_no', label: t('procurement.grn.columns.mushak_61') },
  { key: 'status', label: t('procurement.grn.columns.status') },
  { key: 'actions', label: '' }
]

const load = async () => {
  loading.value = true
  const [g, d, s, i, w, po] = await Promise.all([
    client.from('grns').select('*, parties(name), grn_lines(id, item_id, invoice_qty, accepted_qty, unit_price, gross_weight, core_tare_weight, moisture_pct, batch_no, is_fsc, po_line_id)').is('deleted_at', null).order('created_at', { ascending: false }),
    client.from('debit_notes').select('*, parties(name)').order('created_at', { ascending: false }),
    client.from('parties').select('id, code, name').eq('is_supplier', true).is('deleted_at', null).order('name'),
    client.from('items').select('id, sku, name').eq('is_active', true).is('deleted_at', null).order('sku'),
    client.from('warehouses').select('id, code, name').is('deleted_at', null).order('code'),
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
  if (!remaining.length) { toast.add({ title: t('procurement.grn.toast.po_nothing_left'), color: 'amber' }); return }
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
  id: null as string | null,
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
  Object.assign(form, { id: null, supplier_party_id: null, warehouse_id: null, mushak_61_no: '', vat_applicable: true, note: '' })
  lines.value = [blankLine()]
  selectedPOId.value = null
  open.value = true
}
const openEdit = (row: any) => {
  Object.assign(form, {
    id: row.id, supplier_party_id: row.supplier_party_id, warehouse_id: row.warehouse_id,
    mushak_61_no: row.mushak_61_no ?? '', vat_applicable: row.vat_applicable, note: row.note ?? ''
  })
  lines.value = (row.grn_lines ?? []).map((l: any) => ({
    item_id: l.item_id, invoice_qty: l.invoice_qty, gross_weight: l.gross_weight,
    core_tare_weight: l.core_tare_weight, moisture_pct: l.moisture_pct, unit_price: l.unit_price,
    batch_no: l.batch_no ?? '', is_fsc: l.is_fsc, po_line_id: l.po_line_id
  }))
  if (!lines.value.length) lines.value = [blankLine()]
  selectedPOId.value = null
  open.value = true
}

// live preview of the QA true-net computation
const trueNet = (l: any) =>
  Math.round(((l.gross_weight || l.invoice_qty || 0) - (l.core_tare_weight || 0))
    * (1 - Math.max((l.moisture_pct || 0) - 12, 0) / 100) * 1000) / 1000

const save = async (complete: boolean) => {
  if (!form.supplier_party_id) {
    toast.add({ title: t('procurement.grn.toast.pick_supplier'), color: 'red' }); return
  }
  saving.value = true
  try {
    const headerPayload: any = {
      supplier_party_id: form.supplier_party_id, warehouse_id: form.warehouse_id,
      mushak_61_no: form.mushak_61_no, vat_applicable: form.vat_applicable, note: form.note
    }
    const lineRows = lines.value.filter((l) => l.item_id).map((l) => ({ ...l, batch_no: l.batch_no || null }))
    if (!lineRows.length) throw new Error(t('procurement.grn.toast.add_line_required'))
    let grnId = form.id
    if (form.id) {
      const { error } = await client.from('grns').update(headerPayload).eq('id', form.id)
      if (error) throw error
      await replaceLines('grn_lines', 'grn_id', form.id, lineRows.map((l) => ({ ...l, grn_id: form.id })))
    } else {
      const { data: grn, error } = await client.from('grns').insert(headerPayload).select('id').single()
      if (error) throw error
      grnId = (grn as any).id
      const res = await client.from('grn_lines').insert(lineRows.map((l) => ({ ...l, grn_id: grnId })) as any)
      if (res.error) throw res.error
    }
    if (complete) {
      const rpc = await client.rpc('complete_grn', { p_grn_id: grnId } as any)
      if (rpc.error) throw rpc.error
    }
    toast.add({ title: complete ? t('procurement.grn.toast.completed_and_posted') : (form.id ? t('procurement.grn.toast.updated_draft') : t('procurement.grn.toast.saved_draft')) })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('procurement.grn.toast.grn_failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

const completeDraft = async (row: any) => {
  const { error } = await client.rpc('complete_grn', { p_grn_id: row.id } as any)
  if (error) toast.add({ title: t('procurement.grn.toast.completion_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('procurement.grn.toast.named_completed', { grn: row.grn_no }) }); await load() }
}

const deleteGrn = async (row: any) => {
  const ok = await deleteRecord('grns', row.id, row.grn_no)
  if (ok) await load()
}

const statusColor = (s: string) =>
  s === 'completed' ? 'green' : s === 'cancelled' ? 'red' : 'yellow'
</script>

<template>
  <div>
    <PageHeader :kicker="t('procurement.grn.kicker')" :title="t('procurement.grn.title')" :subtitle="t('procurement.grn.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('procurement.grn.new_grn') }}</UButton>
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
          <UBadge size="xs" variant="subtle" :color="statusColor(row.status)">{{ t(`procurement.statuses.${row.status}`) }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <div class="flex items-center gap-1.5 justify-end">
            <UButton
              v-if="canWrite && row.status === 'draft'"
              icon="i-heroicons-pencil-square" size="xs" variant="ghost" @click="openEdit(row)"
            />
            <UButton
              v-if="canWrite && row.status === 'draft'"
              size="xs" variant="soft" @click="completeDraft(row)"
            >{{ t('procurement.grn.complete_and_post') }}</UButton>
            <UButton
              v-if="canWrite && row.status === 'draft'"
              icon="i-heroicons-trash" color="red" variant="ghost" size="xs" @click="deleteGrn(row)"
            />
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('procurement.grn.empty') }}</div>
        </template>
      </UTable>
    </UCard>

    <UCard>
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('procurement.grn.debit_notes_header') }}</p></template>
      <UTable
        :rows="debitNotes"
        :columns="[
          { key: 'dn_no', label: t('procurement.grn.dn_columns.dn_no') },
          { key: 'supplier', label: t('procurement.grn.dn_columns.supplier') },
          { key: 'qty', label: t('procurement.grn.dn_columns.qty_gap') },
          { key: 'amount', label: t('procurement.grn.dn_columns.amount') },
          { key: 'reason', label: t('procurement.grn.dn_columns.reason') }
        ]"
      >
        <template #supplier-data="{ row }">
          <NuxtLink :to="`/parties/${row.supplier_party_id}`" class="hover:underline">{{ row.parties?.name }}</NuxtLink>
        </template>
        <template #qty-data="{ row }"><span class="num">{{ row.qty }}</span></template>
        <template #amount-data="{ row }"><span class="num text-red-600 dark:text-red-400">{{ row.amount }}</span></template>
        <template #empty-state>
          <div class="text-center py-4 text-sm text-gray-400">{{ t('procurement.grn.no_debit_notes') }}</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-3xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ form.id ? t('procurement.grn.form.edit_title') : t('procurement.grn.form.title') }}</p></template>
        <div class="grid grid-cols-3 gap-3 mb-4">
          <UFormGroup :label="t('procurement.grn.form.supplier')" required>
            <USelect v-model="form.supplier_party_id" :options="suppliers" option-attribute="name" value-attribute="id" :placeholder="t('procurement.grn.form.supplier_placeholder')" />
          </UFormGroup>
          <UFormGroup :label="t('procurement.grn.form.warehouse')">
            <USelect v-model="form.warehouse_id" :options="warehouses" option-attribute="name" value-attribute="id" :placeholder="t('procurement.grn.form.warehouse_placeholder')" />
          </UFormGroup>
          <UFormGroup :label="t('procurement.grn.form.mushak_61_no')">
            <UInput v-model="form.mushak_61_no" />
          </UFormGroup>
          <UFormGroup v-if="supplierPOs.length" :label="t('procurement.grn.form.receive_against_po')" class="col-span-3" :hint="t('procurement.grn.form.receive_against_po_hint')">
            <USelect
              v-model="selectedPOId" :options="supplierPOs" option-attribute="po_no" value-attribute="id"
              :placeholder="t('procurement.grn.form.standalone_receipt')" @update:model-value="applyPO"
            />
          </UFormGroup>
        </div>

        <div class="space-y-3">
          <div v-for="(l, idx) in lines" :key="idx" class="grid grid-cols-4 gap-2 items-end border-b border-gray-100 dark:border-zinc-800/60 pb-3">
            <UFormGroup :label="t('procurement.grn.form.item')" class="col-span-2">
              <USelect v-model="l.item_id" :options="items" option-attribute="sku" value-attribute="id" :placeholder="t('procurement.grn.form.item_placeholder')" />
            </UFormGroup>
            <UFormGroup :label="t('procurement.grn.form.invoice_qty')"><UInput v-model.number="l.invoice_qty" type="number" /></UFormGroup>
            <UFormGroup :label="t('procurement.grn.form.unit_price')"><UInput v-model.number="l.unit_price" type="number" /></UFormGroup>
            <UFormGroup :label="t('procurement.grn.form.gross_weight')"><UInput v-model.number="l.gross_weight" type="number" /></UFormGroup>
            <UFormGroup :label="t('procurement.grn.form.core_tare')"><UInput v-model.number="l.core_tare_weight" type="number" /></UFormGroup>
            <UFormGroup :label="t('procurement.grn.form.moisture_pct')"><UInput v-model.number="l.moisture_pct" type="number" step="0.1" /></UFormGroup>
            <UFormGroup :label="t('procurement.grn.form.batch_no')"><UInput v-model="l.batch_no" :placeholder="t('procurement.grn.form.batch_no_placeholder')" /></UFormGroup>
            <div class="col-span-4 flex items-center justify-between text-xs text-gray-500">
              <UCheckbox v-model="l.is_fsc" :label="t('procurement.grn.form.fsc_certified')" />
              <span>
                {{ t('procurement.grn.form.true_net') }} <span class="num font-semibold text-emerald-600 dark:text-emerald-400">{{ trueNet(l) }}</span>
                <span v-if="l.invoice_qty && trueNet(l) < l.invoice_qty" class="num text-amber-600 dark:text-amber-400 ml-1">
                  {{ t('procurement.grn.form.gap_note', { gap: Math.round((l.invoice_qty - trueNet(l)) * 1000) / 1000 }) }}
                </span>
              </span>
            </div>
          </div>
          <UButton size="xs" variant="soft" icon="i-heroicons-plus" @click="lines.push(blankLine())">{{ t('procurement.grn.form.add_line') }}</UButton>
        </div>

        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton color="gray" variant="soft" :loading="saving" @click="save(false)">{{ form.id ? t('common.save') : t('procurement.grn.form.save_draft') }}</UButton>
            <UButton :loading="saving" @click="save(true)">{{ t('procurement.grn.complete_and_post') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
