<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money, num } = useFmt()

const docs = ref<any[]>([])
const parties = ref<any[]>([])
const items = ref<any[]>([])
const loading = ref(true)

const columns = [
  { key: 'doc_no', label: 'Doc' },
  { key: 'doc_type', label: 'Type' },
  { key: 'customer', label: 'Buyer' },
  { key: 'dates', label: 'Date / valid until' },
  { key: 'total', label: 'Total (৳)' },
  { key: 'status', label: 'Status' },
  { key: 'actions', label: '' }
]

const load = async () => {
  loading.value = true
  const [d, p, i] = await Promise.all([
    client.from('sales_documents')
      .select('*, parties(name), parent:parent_doc_id(doc_no), sales_document_lines(qty, unit_price)')
      .order('created_at', { ascending: false }),
    client.from('parties').select('id, name').eq('is_customer', true).order('name'),
    client.from('items').select('id, sku, name').eq('is_active', true).order('sku')
  ])
  docs.value = d.data ?? []
  parties.value = p.data ?? []
  items.value = i.data ?? []
  loading.value = false
}
onMounted(load)

const docTotal = (row: any) =>
  (row.sales_document_lines ?? []).reduce((s: number, l: any) => s + l.qty * l.unit_price, 0)

const typeLabel: Record<string, string> = { quotation: 'Quotation', pi: 'Proforma Invoice', contract: 'Sales Contract' }
const typeColor: Record<string, string> = { quotation: 'gray', pi: 'blue', contract: 'purple' }
const statusColor: Record<string, string> = {
  draft: 'gray', sent: 'blue', accepted: 'green', expired: 'red', converted: 'purple', cancelled: 'red'
}
const isExpired = (row: any) => row.valid_until && row.valid_until < new Date().toISOString().slice(0, 10)
  && ['draft', 'sent'].includes(row.status)

// --- New document ---
const open = ref(false)
const saving = ref(false)
const docTypeOptions = [
  { value: 'quotation', label: 'Quotation' },
  { value: 'pi', label: 'Proforma Invoice' },
  { value: 'contract', label: 'Sales Contract' }
]
const form = reactive({
  doc_type: 'quotation',
  customer_party_id: null as string | null,
  valid_until: new Date(Date.now() + 15 * 86400000).toISOString().slice(0, 10),
  payment_terms: 'Irrevocable Local L/C, at sight',
  delivery_terms: 'Ex-factory, Dhaka',
  is_deemed_export: true,
  notes: ''
})
const lines = ref<any[]>([])
const blankLine = () => ({ item_id: null, qty: 0, unit_price: 0 })
const openNew = () => {
  Object.assign(form, {
    doc_type: 'quotation', customer_party_id: null,
    valid_until: new Date(Date.now() + 15 * 86400000).toISOString().slice(0, 10),
    payment_terms: 'Irrevocable Local L/C, at sight', delivery_terms: 'Ex-factory, Dhaka',
    is_deemed_export: true, notes: ''
  })
  lines.value = [blankLine()]
  open.value = true
}

const save = async () => {
  if (!form.customer_party_id) { toast.add({ title: 'Pick a buyer', color: 'red' }); return }
  const payload = lines.value.filter((l) => l.item_id && l.qty > 0)
  if (!payload.length) { toast.add({ title: 'Add at least one line', color: 'red' }); return }
  saving.value = true
  try {
    const { data: doc, error } = await client.from('sales_documents').insert({ ...form } as any).select('id').single()
    if (error) throw error
    const res = await client.from('sales_document_lines').insert(
      payload.map((l) => ({ ...l, sales_document_id: (doc as any).id })) as any
    )
    if (res.error) throw res.error
    toast.add({ title: `${typeLabel[form.doc_type]} created` })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: 'Save failed', description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

// --- Actions ---
const setStatus = async (row: any, status: string) => {
  const { error } = await client.from('sales_documents').update({ status } as any).eq('id', row.id)
  if (error) toast.add({ title: 'Update failed', description: error.message, color: 'red' })
  else { await load() }
}
const convert = async (row: any, toType: string) => {
  const { error } = await client.rpc('convert_sales_document', { p_id: row.id, p_to_type: toType } as any)
  if (error) toast.add({ title: 'Conversion failed', description: error.message, color: 'red' })
  else { toast.add({ title: `Converted to ${typeLabel[toType]}` }); await load() }
}
const toOrder = async (row: any) => {
  const { error } = await client.rpc('sales_document_to_order', { p_id: row.id } as any)
  if (error) toast.add({ title: 'Conversion failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Sales order created' }); await load() }
}
</script>

<template>
  <div>
    <PageHeader kicker="Sales &amp; Local LC" title="Quotations, PI &amp; contracts" subtitle="Pre-order paper trail — convert forward as the deal firms up, or generate a PI from an existing order">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New document</UButton>
    </PageHeader>

    <UCard>
      <UTable :rows="docs" :columns="columns" :loading="loading">
        <template #doc_no-data="{ row }">
          <NuxtLink :to="`/quotations/${row.id}`" class="num font-medium text-amber-600 dark:text-amber-400 hover:underline">{{ row.doc_no }}</NuxtLink>
          <div v-if="row.parent" class="text-[10px] text-gray-400 dark:text-zinc-600">from {{ row.parent.doc_no }}</div>
        </template>
        <template #doc_type-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="typeColor[row.doc_type]">{{ typeLabel[row.doc_type] }}</UBadge>
        </template>
        <template #customer-data="{ row }">
          <NuxtLink :to="`/parties/${row.customer_party_id}`" class="hover:underline">{{ row.parties?.name }}</NuxtLink>
        </template>
        <template #dates-data="{ row }">
          <div class="text-xs num">
            <div>{{ row.doc_date }}</div>
            <div class="text-gray-400 dark:text-zinc-600">valid {{ row.valid_until || '—' }}</div>
          </div>
        </template>
        <template #total-data="{ row }">
          <span class="num font-medium">{{ num(docTotal(row)) }}</span>
        </template>
        <template #status-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="isExpired(row) ? 'red' : statusColor[row.status]">
            {{ isExpired(row) ? 'expired' : row.status }}
          </UBadge>
        </template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end items-center">
            <UButton icon="i-heroicons-printer" size="xs" color="gray" variant="ghost" :to="`/print/quote/${row.id}`" target="_blank" aria-label="Print" />
            <template v-if="canWrite && ['draft', 'sent', 'accepted'].includes(row.status)">
              <UButton v-if="row.status === 'draft'" size="2xs" variant="soft" @click="setStatus(row, 'sent')">Sent</UButton>
              <UButton v-if="row.status === 'sent'" size="2xs" variant="soft" color="green" @click="setStatus(row, 'accepted')">Accepted</UButton>
              <UButton v-if="row.doc_type === 'quotation'" size="2xs" variant="soft" color="blue" @click="convert(row, 'pi')">→ PI</UButton>
              <UButton v-if="row.doc_type !== 'contract'" size="2xs" variant="soft" color="purple" @click="convert(row, 'contract')">→ Contract</UButton>
              <UButton size="2xs" variant="soft" color="amber" @click="toOrder(row)">→ Order</UButton>
              <UButton size="2xs" variant="ghost" color="red" @click="setStatus(row, 'cancelled')">Cancel</UButton>
            </template>
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">No quotations, PIs or contracts yet.</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New document</p></template>
        <div class="grid grid-cols-2 gap-4 mb-4">
          <UFormGroup label="Type" required>
            <USelect v-model="form.doc_type" :options="docTypeOptions" option-attribute="label" value-attribute="value" />
          </UFormGroup>
          <UFormGroup label="Buyer" required>
            <USelect v-model="form.customer_party_id" :options="parties" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup label="Valid until">
            <UInput v-model="form.valid_until" type="date" />
          </UFormGroup>
          <UFormGroup label="Deemed export">
            <UCheckbox v-model="form.is_deemed_export" label="Zero-rated (Mushak 6.3)" />
          </UFormGroup>
          <UFormGroup label="Payment terms" class="col-span-2">
            <UInput v-model="form.payment_terms" />
          </UFormGroup>
          <UFormGroup label="Delivery terms" class="col-span-2">
            <UInput v-model="form.delivery_terms" />
          </UFormGroup>
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
            <UButton :loading="saving" @click="save">Create</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
