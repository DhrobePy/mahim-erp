<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { deleteRecord } = useRecycleBin()
const { replaceLines } = useLineReconcile()
const { t } = useI18n()

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
      .select('*, parties(name), purchase_order_lines(id, item_id, qty, unit_price, received_qty)')
      .is('deleted_at', null)
      .order('created_at', { ascending: false }),
    client.from('parties').select('id, name').eq('is_supplier', true).is('deleted_at', null).order('name'),
    client.from('items').select('id, sku, name').eq('item_type', 'raw_material').eq('is_active', true).is('deleted_at', null).order('sku')
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
  id: null as string | null,
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
    id: null, supplier_party_id: null, order_date: new Date().toISOString().slice(0, 10), expected_date: null,
    currency: 'BDT', freight_cost: 0, customs_duty: 0, clearing_agent_fee: 0, other_landed_cost: 0, note: ''
  })
  lines.value = [{ item_id: null, qty: 1, unit_price: 0 }]
  open.value = true
}
const openEdit = (row: any) => {
  Object.assign(form, {
    id: row.id, supplier_party_id: row.supplier_party_id, order_date: row.order_date, expected_date: row.expected_date,
    currency: row.currency, freight_cost: row.freight_cost, customs_duty: row.customs_duty,
    clearing_agent_fee: row.clearing_agent_fee, other_landed_cost: row.other_landed_cost, note: row.note ?? ''
  })
  lines.value = row.purchase_order_lines.map((l: any) => ({ item_id: l.item_id, qty: l.qty, unit_price: l.unit_price }))
  if (!lines.value.length) lines.value = [{ item_id: null, qty: 1, unit_price: 0 }]
  open.value = true
}

const save = async () => {
  if (!form.supplier_party_id) { toast.add({ title: t('procurement.po.toast.pick_supplier'), color: 'red' }); return }
  const validLines = lines.value.filter((l) => l.item_id && l.qty > 0)
  if (!validLines.length) { toast.add({ title: t('procurement.po.toast.add_line_required'), color: 'red' }); return }
  saving.value = true
  try {
    const headerPayload: any = {
      supplier_party_id: form.supplier_party_id, order_date: form.order_date, expected_date: form.expected_date,
      currency: form.currency, freight_cost: form.freight_cost, customs_duty: form.customs_duty,
      clearing_agent_fee: form.clearing_agent_fee, other_landed_cost: form.other_landed_cost, note: form.note
    }
    if (form.id) {
      const { error } = await client.from('purchase_orders').update(headerPayload).eq('id', form.id)
      if (error) throw error
      await replaceLines('purchase_order_lines', 'po_id', form.id, validLines.map((l) => ({ po_id: form.id, item_id: l.item_id, qty: l.qty, unit_price: l.unit_price })))
      toast.add({ title: t('procurement.po.toast.updated_draft') })
    } else {
      const { data: po, error } = await client.from('purchase_orders').insert(headerPayload).select('id').single()
      if (error) throw error
      const { error: lErr } = await client.from('purchase_order_lines').insert(
        validLines.map((l) => ({ po_id: (po as any).id, item_id: l.item_id, qty: l.qty, unit_price: l.unit_price }))
      )
      if (lErr) throw lErr
      toast.add({ title: t('procurement.po.toast.created_draft') })
    }
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('procurement.po.toast.save_failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

const approve = async (row: any) => {
  const { error } = await client.rpc('approve_purchase_order', { p_po_id: row.id } as any)
  if (error) toast.add({ title: t('procurement.po.toast.approve_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('procurement.po.toast.named_approved', { po: row.po_no }) }); await load() }
}
const cancel = async (row: any) => {
  const ok = await deleteRecord('purchase_orders', row.id, row.po_no)
  if (ok) await load()
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('procurement.po.kicker')" :title="t('procurement.po.title')" :subtitle="t('procurement.po.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('procurement.po.new_po') }}</UButton>
    </PageHeader>

    <div v-if="loading" class="text-sm text-gray-400">{{ t('common.loading') }}</div>
    <div v-else-if="!pos.length" class="text-sm text-gray-400">{{ t('procurement.po.empty') }}</div>

    <UCard v-else>
      <UTable
        :rows="pos"
        :columns="[
          { key: 'po_no', label: t('procurement.po.columns.po_no') }, { key: 'supplier', label: t('procurement.po.columns.supplier') },
          { key: 'order_date', label: t('procurement.po.columns.order_date') }, { key: 'lines', label: t('procurement.po.columns.lines') },
          { key: 'value', label: t('procurement.po.columns.value') }, { key: 'status', label: t('procurement.po.columns.status') }, { key: 'actions', label: '' }
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
          <UBadge size="xs" :color="statusColor[row.status]" variant="subtle">{{ t(`procurement.statuses.${row.status}`) }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <div class="flex items-center gap-1.5 justify-end">
            <UButton v-if="canWrite && row.status === 'draft'" icon="i-heroicons-pencil-square" size="xs" variant="ghost" @click="openEdit(row)" />
            <UButton v-if="canWrite && row.status === 'draft'" size="xs" variant="soft" @click="approve(row)">{{ t('procurement.po.approve') }}</UButton>
            <UButton
              v-if="canWrite && ['draft','approved'].includes(row.status)"
              size="xs" variant="soft" color="red" @click="cancel(row)"
            >{{ t('procurement.po.cancel') }}</UButton>
          </div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-3xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header>
          <p class="font-medium">{{ form.id ? t('procurement.po.form.edit_title') : t('procurement.po.form.title') }}</p>
          <p class="text-xs text-gray-500">{{ t('procurement.po.form.subtitle') }}</p>
        </template>

        <div class="space-y-5">
          <div class="grid grid-cols-2 gap-4">
            <UFormGroup :label="t('procurement.po.form.supplier')" required class="col-span-2">
              <USelect v-model="form.supplier_party_id" :options="suppliers" option-attribute="name" value-attribute="id" :placeholder="t('procurement.po.form.supplier_placeholder')" />
            </UFormGroup>
            <UFormGroup :label="t('procurement.po.form.order_date')"><UInput v-model="form.order_date" type="date" /></UFormGroup>
            <UFormGroup :label="t('procurement.po.form.expected_delivery')"><UInput v-model="form.expected_date" type="date" /></UFormGroup>
            <UFormGroup :label="t('procurement.po.form.currency')">
              <USelect v-model="form.currency" :options="['BDT', 'USD', 'EUR']" />
            </UFormGroup>
          </div>

          <div>
            <div class="flex items-center justify-between mb-2">
              <p class="text-sm font-medium">{{ t('procurement.po.form.line_items') }}</p>
              <UButton size="xs" variant="soft" icon="i-heroicons-plus" @click="addLine">{{ t('procurement.po.form.add') }}</UButton>
            </div>
            <div v-for="(l, i) in lines" :key="i" class="grid grid-cols-12 gap-2 mb-2 items-center">
              <USelect v-model="l.item_id" :options="items" option-attribute="sku" value-attribute="id" :placeholder="t('procurement.po.form.item_placeholder')" class="col-span-4" />
              <UInput v-model.number="l.qty" type="number" :placeholder="t('procurement.po.form.qty_placeholder')" class="col-span-2" />
              <UInput v-model.number="l.unit_price" type="number" :placeholder="t('procurement.po.form.unit_price_placeholder')" class="col-span-2" />
              <span class="col-span-3 text-xs text-gray-500 dark:text-zinc-500 num">
                {{ t('procurement.po.form.landed_per_unit', { cost: landedUnitCost(l).toFixed(4) }) }}
              </span>
              <UButton icon="i-heroicons-trash" color="red" variant="ghost" size="xs" class="col-span-1" @click="removeLine(i)" />
            </div>
          </div>

          <div>
            <p class="microlabel text-gray-400 dark:text-zinc-500 mb-1.5">{{ t('procurement.po.form.landed_costs_header') }}</p>
            <div class="grid grid-cols-4 gap-2">
              <UFormGroup :label="t('procurement.po.form.freight')"><UInput v-model.number="form.freight_cost" type="number" /></UFormGroup>
              <UFormGroup :label="t('procurement.po.form.customs_duty')"><UInput v-model.number="form.customs_duty" type="number" /></UFormGroup>
              <UFormGroup :label="t('procurement.po.form.clearing_fee')"><UInput v-model.number="form.clearing_agent_fee" type="number" /></UFormGroup>
              <UFormGroup :label="t('procurement.po.form.other')"><UInput v-model.number="form.other_landed_cost" type="number" /></UFormGroup>
            </div>
          </div>

          <UFormGroup :label="t('procurement.po.form.note')"><UTextarea v-model="form.note" :rows="2" /></UFormGroup>

          <div class="rounded ring-1 ring-amber-500/30 bg-amber-50/40 dark:bg-amber-500/[0.04] p-3 flex justify-between text-sm">
            <span class="text-gray-500 dark:text-zinc-500">{{ t('procurement.po.form.ex_factory_value') }}</span>
            <span class="num font-medium">৳{{ totalValue.toFixed(2) }}</span>
            <span class="text-gray-500 dark:text-zinc-500">{{ t('procurement.po.form.landed_costs') }}</span>
            <span class="num font-medium text-amber-600 dark:text-amber-400">৳{{ totalLanded.toFixed(2) }}</span>
          </div>
        </div>

        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ form.id ? t('common.save') : t('procurement.po.form.save_as_draft') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
