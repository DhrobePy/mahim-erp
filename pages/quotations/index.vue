<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money, num } = useFmt()
const { deleteRecord } = useRecycleBin()
const { replaceLines } = useLineReconcile()
const { t } = useI18n()

const docs = ref<any[]>([])
const parties = ref<any[]>([])
const items = ref<any[]>([])
const loading = ref(true)

const columns = computed(() => [
  { key: 'doc_no', label: t('quotations.index.columns.doc') },
  { key: 'doc_type', label: t('quotations.index.columns.type') },
  { key: 'customer', label: t('quotations.index.columns.buyer') },
  { key: 'dates', label: t('quotations.index.columns.dates') },
  { key: 'total', label: t('quotations.index.columns.total') },
  { key: 'status', label: t('quotations.index.columns.status') },
  { key: 'actions', label: '' }
])

const load = async () => {
  loading.value = true
  const [d, p, i] = await Promise.all([
    client.from('sales_documents')
      .select('*, parties(name), parent:parent_doc_id(doc_no), sales_document_lines(id, item_id, qty, unit_price)')
      .is('deleted_at', null)
      .order('created_at', { ascending: false }),
    client.from('parties').select('id, name').eq('is_customer', true).is('deleted_at', null).order('name'),
    client.from('items').select('id, sku, name').eq('is_active', true).is('deleted_at', null).order('sku')
  ])
  docs.value = d.data ?? []
  parties.value = p.data ?? []
  items.value = i.data ?? []
  loading.value = false
}
onMounted(load)

const docTotal = (row: any) =>
  (row.sales_document_lines ?? []).reduce((s: number, l: any) => s + l.qty * l.unit_price, 0)

const typeLabel = computed<Record<string, string>>(() => ({
  quotation: t('quotations.doc_types.quotation'),
  pi: t('quotations.doc_types.pi'),
  contract: t('quotations.doc_types.contract')
}))
const typeColor: Record<string, string> = { quotation: 'gray', pi: 'blue', contract: 'purple' }
const statusColor: Record<string, string> = {
  draft: 'gray', sent: 'blue', accepted: 'green', expired: 'red', converted: 'purple', cancelled: 'red'
}
const statusLabel = computed<Record<string, string>>(() => ({
  draft: t('common.draft'),
  sent: t('quotations.statuses.sent'),
  accepted: t('quotations.statuses.accepted'),
  expired: t('quotations.statuses.expired'),
  converted: t('quotations.statuses.converted'),
  cancelled: t('quotations.statuses.cancelled')
}))
const isExpired = (row: any) => row.valid_until && row.valid_until < new Date().toISOString().slice(0, 10)
  && ['draft', 'sent'].includes(row.status)

// --- New document ---
const open = ref(false)
const saving = ref(false)
const docTypeOptions = computed(() => [
  { value: 'quotation', label: t('quotations.doc_types.quotation') },
  { value: 'pi', label: t('quotations.doc_types.pi') },
  { value: 'contract', label: t('quotations.doc_types.contract') }
])
const form = reactive({
  id: null as string | null,
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
    id: null, doc_type: 'quotation', customer_party_id: null,
    valid_until: new Date(Date.now() + 15 * 86400000).toISOString().slice(0, 10),
    payment_terms: 'Irrevocable Local L/C, at sight', delivery_terms: 'Ex-factory, Dhaka',
    is_deemed_export: true, notes: ''
  })
  lines.value = [blankLine()]
  open.value = true
}
const openEdit = (row: any) => {
  Object.assign(form, {
    id: row.id, doc_type: row.doc_type, customer_party_id: row.customer_party_id, valid_until: row.valid_until,
    payment_terms: row.payment_terms, delivery_terms: row.delivery_terms, is_deemed_export: row.is_deemed_export,
    notes: row.notes ?? ''
  })
  lines.value = (row.sales_document_lines ?? []).map((l: any) => ({ item_id: l.item_id, qty: l.qty, unit_price: l.unit_price }))
  if (!lines.value.length) lines.value = [blankLine()]
  open.value = true
}

const save = async () => {
  if (!form.customer_party_id) { toast.add({ title: t('quotations.index.toast.pick_buyer'), color: 'red' }); return }
  const payload = lines.value.filter((l) => l.item_id && l.qty > 0)
  if (!payload.length) { toast.add({ title: t('quotations.index.toast.add_line'), color: 'red' }); return }
  saving.value = true
  try {
    const headerPayload: any = {
      doc_type: form.doc_type, customer_party_id: form.customer_party_id, valid_until: form.valid_until,
      payment_terms: form.payment_terms, delivery_terms: form.delivery_terms, is_deemed_export: form.is_deemed_export,
      notes: form.notes
    }
    if (form.id) {
      const { error } = await client.from('sales_documents').update(headerPayload).eq('id', form.id)
      if (error) throw error
      await replaceLines('sales_document_lines', 'sales_document_id', form.id, payload.map((l) => ({ ...l, sales_document_id: form.id })))
      toast.add({ title: t('quotations.index.toast.updated') })
    } else {
      const { data: doc, error } = await client.from('sales_documents').insert(headerPayload).select('id').single()
      if (error) throw error
      const res = await client.from('sales_document_lines').insert(
        payload.map((l) => ({ ...l, sales_document_id: (doc as any).id })) as any
      )
      if (res.error) throw res.error
      toast.add({ title: t('quotations.index.toast.created', { type: typeLabel.value[form.doc_type] }) })
    }
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('quotations.index.toast.save_failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

// --- Actions ---
const setStatus = async (row: any, status: string) => {
  const { error } = await client.from('sales_documents').update({ status } as any).eq('id', row.id)
  if (error) toast.add({ title: t('quotations.index.toast.update_failed'), description: error.message, color: 'red' })
  else { await load() }
}
const convert = async (row: any, toType: string) => {
  const { error } = await client.rpc('convert_sales_document', { p_id: row.id, p_to_type: toType } as any)
  if (error) toast.add({ title: t('quotations.index.toast.conversion_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('quotations.index.toast.converted', { type: typeLabel.value[toType] }) }); await load() }
}
const toOrder = async (row: any) => {
  const { error } = await client.rpc('sales_document_to_order', { p_id: row.id } as any)
  if (error) toast.add({ title: t('quotations.index.toast.conversion_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('quotations.index.toast.order_created') }); await load() }
}
const onDelete = async (row: any) => {
  if (await deleteRecord('sales_documents', row.id, row.doc_no)) await load()
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('quotations.kicker')" :title="t('quotations.index.title')" :subtitle="t('quotations.index.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('quotations.index.new_document') }}</UButton>
    </PageHeader>

    <UCard>
      <UTable :rows="docs" :columns="columns" :loading="loading">
        <template #doc_no-data="{ row }">
          <NuxtLink :to="`/quotations/${row.id}`" class="num font-medium text-amber-600 dark:text-amber-400 hover:underline">{{ row.doc_no }}</NuxtLink>
          <div v-if="row.parent" class="text-[10px] text-gray-400 dark:text-zinc-600">{{ t('quotations.index.from', { doc: row.parent.doc_no }) }}</div>
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
            <div class="text-gray-400 dark:text-zinc-600">{{ t('quotations.index.valid', { date: row.valid_until || '—' }) }}</div>
          </div>
        </template>
        <template #total-data="{ row }">
          <span class="num font-medium">{{ num(docTotal(row)) }}</span>
        </template>
        <template #status-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="isExpired(row) ? 'red' : statusColor[row.status]">
            {{ isExpired(row) ? t('quotations.statuses.expired') : statusLabel[row.status] }}
          </UBadge>
        </template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end items-center">
            <UButton icon="i-heroicons-printer" size="xs" color="gray" variant="ghost" :to="`/print/quote/${row.id}`" target="_blank" :aria-label="t('quotations.index.print_aria')" />
            <UButton v-if="canWrite && row.status === 'draft'" icon="i-heroicons-pencil-square" size="xs" variant="ghost" @click="openEdit(row)" />
            <template v-if="canWrite && ['draft', 'sent', 'accepted'].includes(row.status)">
              <UButton v-if="row.status === 'draft'" size="2xs" variant="soft" @click="setStatus(row, 'sent')">{{ t('quotations.index.sent') }}</UButton>
              <UButton v-if="row.status === 'sent'" size="2xs" variant="soft" color="green" @click="setStatus(row, 'accepted')">{{ t('quotations.index.accepted') }}</UButton>
              <UButton v-if="row.doc_type === 'quotation'" size="2xs" variant="soft" color="blue" @click="convert(row, 'pi')">{{ t('quotations.index.to_pi') }}</UButton>
              <UButton v-if="row.doc_type !== 'contract'" size="2xs" variant="soft" color="purple" @click="convert(row, 'contract')">{{ t('quotations.index.to_contract') }}</UButton>
              <UButton size="2xs" variant="soft" color="amber" @click="toOrder(row)">{{ t('quotations.index.to_order') }}</UButton>
              <UButton size="2xs" variant="ghost" color="red" @click="setStatus(row, 'cancelled')">{{ t('quotations.index.cancel') }}</UButton>
            </template>
            <UButton v-if="canWrite" icon="i-heroicons-trash" size="xs" color="red" variant="ghost" :aria-label="t('quotations.index.delete_aria')" @click="onDelete(row)" />
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('quotations.index.empty') }}</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ form.id ? t('quotations.index.modal_title_edit') : t('quotations.index.modal_title') }}</p></template>
        <div class="grid grid-cols-2 gap-4 mb-4">
          <UFormGroup :label="t('quotations.index.type_label')" required>
            <USelect v-model="form.doc_type" :options="docTypeOptions" option-attribute="label" value-attribute="value" />
          </UFormGroup>
          <UFormGroup :label="t('quotations.index.buyer_label')" required>
            <USelect v-model="form.customer_party_id" :options="parties" option-attribute="name" value-attribute="id" :placeholder="t('quotations.index.buyer_placeholder')" />
          </UFormGroup>
          <UFormGroup :label="t('quotations.index.valid_until_label')">
            <UInput v-model="form.valid_until" type="date" />
          </UFormGroup>
          <UFormGroup :label="t('quotations.index.deemed_export_label')">
            <UCheckbox v-model="form.is_deemed_export" :label="t('quotations.index.zero_rated')" />
          </UFormGroup>
          <UFormGroup :label="t('quotations.index.payment_terms_label')" class="col-span-2">
            <UInput v-model="form.payment_terms" />
          </UFormGroup>
          <UFormGroup :label="t('quotations.index.delivery_terms_label')" class="col-span-2">
            <UInput v-model="form.delivery_terms" />
          </UFormGroup>
        </div>
        <div class="space-y-2">
          <div v-for="(l, idx) in lines" :key="idx" class="grid grid-cols-3 gap-2">
            <UFormGroup :label="t('quotations.index.item_label')">
              <USelect v-model="l.item_id" :options="items" option-attribute="sku" value-attribute="id" :placeholder="t('quotations.index.item_placeholder')" />
            </UFormGroup>
            <UFormGroup :label="t('quotations.index.qty_label')"><UInput v-model.number="l.qty" type="number" /></UFormGroup>
            <UFormGroup :label="t('quotations.index.unit_price_label')"><UInput v-model.number="l.unit_price" type="number" /></UFormGroup>
          </div>
          <UButton size="xs" variant="soft" icon="i-heroicons-plus" @click="lines.push(blankLine())">{{ t('quotations.index.add_line') }}</UButton>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ form.id ? t('common.save') : t('quotations.index.create') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
