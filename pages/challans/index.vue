<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()

const challans = ref<any[]>([])
const orders = ref<any[]>([])
const lcs = ref<any[]>([])
const items = ref<any[]>([])
const loading = ref(true)

const columns = [
  { key: 'challan_no', label: 'Challan' },
  { key: 'challan_kind', label: 'Kind' },
  { key: 'customer', label: 'Buyer' },
  { key: 'dates', label: 'Doc / actual date' },
  { key: 'lc', label: 'LC' },
  { key: 'covers', label: 'Covers' },
  { key: 'status', label: 'Status' },
  { key: 'actions', label: '' }
]

const load = async () => {
  loading.value = true
  const [c, o, l, i] = await Promise.all([
    client.from('delivery_challans')
      .select('*, parties(name), lcs(lc_no), covers:covers_challan_id(challan_no), delivery_challan_lines(id, qty, unit_price, items(sku))')
      .order('created_at', { ascending: false }),
    client.from('sales_orders')
      .select('id, so_no, customer_party_id, lc_id, status, parties(name), sales_order_lines(item_id, qty, unit_price, delivered_qty, items(sku))')
      .in('status', ['open', 'partially_delivered']),
    client.from('lcs').select('id, lc_no').eq('status', 'active'),
    client.from('items').select('id, sku').eq('is_active', true).order('sku')
  ])
  challans.value = c.data ?? []
  orders.value = o.data ?? []
  lcs.value = l.data ?? []
  items.value = i.data ?? []
  loading.value = false
}
onMounted(load)

// --- New challan ---
const open = ref(false)
const saving = ref(false)
const form = reactive({
  so_id: null as string | null,
  challan_kind: 'standard',
  lc_id: null as string | null,
  actual_delivery_date: new Date().toISOString().slice(0, 10),
  document_date: new Date().toISOString().slice(0, 10)
})
const lines = ref<any[]>([])
const kindOptions = [
  { value: 'standard', label: 'Standard — LC in hand (official DC no.)' },
  { value: 'original', label: 'Original — pre-LC delivery (internal no., posts GDNI)' }
]
const openNew = () => {
  Object.assign(form, {
    so_id: null, challan_kind: 'standard', lc_id: null,
    actual_delivery_date: new Date().toISOString().slice(0, 10),
    document_date: new Date().toISOString().slice(0, 10)
  })
  lines.value = []
  open.value = true
}

// prefill lines with the SO's undelivered quantities
watch(() => form.so_id, (soId) => {
  const so = orders.value.find((o) => o.id === soId)
  if (!so) { lines.value = []; return }
  form.lc_id = so.lc_id
  lines.value = so.sales_order_lines.map((l: any) => ({
    item_id: l.item_id,
    sku: l.items?.sku,
    qty: Math.max(l.qty - l.delivered_qty, 0),
    unit_price: l.unit_price
  }))
})

const save = async (issue: boolean) => {
  const so = orders.value.find((o) => o.id === form.so_id)
  if (!so) { toast.add({ title: 'Pick a sales order', color: 'red' }); return }
  if (form.challan_kind === 'standard' && !form.lc_id) {
    toast.add({ title: 'Standard challans need an LC — use an original (pre-LC) challan instead', color: 'red' })
    return
  }
  saving.value = true
  try {
    const { data: ch, error } = await client.from('delivery_challans').insert({
      so_id: form.so_id,
      challan_kind: form.challan_kind,
      lc_id: form.challan_kind === 'original' ? null : form.lc_id,
      customer_party_id: so.customer_party_id,
      actual_delivery_date: form.actual_delivery_date,
      document_date: form.document_date
    } as any).select('id').single()
    if (error) throw error
    const payload = lines.value.filter((l) => l.item_id && l.qty > 0)
      .map((l) => ({ challan_id: (ch as any).id, item_id: l.item_id, qty: l.qty, unit_price: l.unit_price }))
    if (!payload.length) throw new Error('Nothing to deliver')
    const res = await client.from('delivery_challan_lines').insert(payload as any)
    if (res.error) throw res.error
    if (issue) {
      const rpc = await client.rpc('issue_challan', { p_challan_id: (ch as any).id } as any)
      if (rpc.error) throw rpc.error
    }
    toast.add({ title: issue ? 'Challan issued — stock dispatched' : 'Challan saved as draft' })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: 'Challan failed', description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

const issueDraft = async (row: any) => {
  const { error } = await client.rpc('issue_challan', { p_challan_id: row.id } as any)
  if (error) toast.add({ title: 'Issue failed', description: error.message, color: 'red' })
  else { toast.add({ title: `${row.challan_no} issued` }); await load() }
}

// --- Covering set ---
const coverOpen = ref(false)
const coverTarget = ref<any>(null)
const coverForm = reactive({ lc_id: null as string | null, document_date: new Date().toISOString().slice(0, 10) })
const openCover = (row: any) => {
  coverTarget.value = row
  Object.assign(coverForm, { lc_id: null, document_date: new Date().toISOString().slice(0, 10) })
  coverOpen.value = true
}
const createCover = async () => {
  if (!coverForm.lc_id) { toast.add({ title: 'Pick the LC', color: 'red' }); return }
  const { error } = await client.rpc('create_covering_set', {
    p_original_id: coverTarget.value.id,
    p_lc_id: coverForm.lc_id,
    p_document_date: coverForm.document_date
  } as any)
  if (error) toast.add({ title: 'Covering failed', description: error.message, color: 'red' })
  else {
    toast.add({ title: 'Covering set issued (official series, no re-posting)' })
    coverOpen.value = false
    await load()
  }
}

const invoiceChallan = async (row: any) => {
  const { error } = await client.rpc('create_invoice_from_challan', { p_challan_id: row.id } as any)
  if (error) toast.add({ title: 'Invoicing failed', description: error.message, color: 'red' })
  else { toast.add({ title: `Invoice created for ${row.challan_no}` }); await load() }
}

const kindColor = (k: string) =>
  ({ standard: 'blue', original: 'amber', covering: 'purple' } as any)[k] || 'gray'
const statusColor = (s: string) =>
  ({ draft: 'gray', issued: 'blue', delivered_unbilled: 'amber', covered: 'purple', invoiced: 'green', cancelled: 'red' } as any)[s] || 'gray'
</script>

<template>
  <div>
    <PageHeader kicker="Sales &amp; Local LC" title="Delivery challans" subtitle="Standard (LC in hand) and pre-LC originals; covering sets issue once the LC lands">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New challan</UButton>
    </PageHeader>

    <UCard>
      <UTable :rows="challans" :columns="columns" :loading="loading">
        <template #challan_kind-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="kindColor(row.challan_kind)">{{ row.challan_kind }}</UBadge>
        </template>
        <template #customer-data="{ row }">
          <NuxtLink :to="`/parties/${row.customer_party_id}`" class="hover:underline">{{ row.parties?.name }}</NuxtLink>
        </template>
        <template #challan_no-data="{ row }">
          <span class="num font-medium dark:text-zinc-100">{{ row.challan_no }}</span>
        </template>
        <template #dates-data="{ row }">
          <div class="text-xs num">
            <div>{{ row.document_date }}</div>
            <div v-if="row.document_date !== row.actual_delivery_date" class="text-amber-600 dark:text-amber-400">
              actual {{ row.actual_delivery_date }}
            </div>
          </div>
        </template>
        <template #lc-data="{ row }">
          <NuxtLink v-if="row.lc_id" :to="`/lcs/${row.lc_id}`" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ row.lcs?.lc_no }}</NuxtLink>
          <span v-else>—</span>
        </template>
        <template #covers-data="{ row }">{{ row.covers?.challan_no || '—' }}</template>
        <template #status-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="statusColor(row.status)">{{ row.status }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton
              v-if="row.status !== 'draft'"
              icon="i-heroicons-printer" size="xs" color="gray" variant="ghost"
              :to="`/print/challan/${row.id}`" target="_blank" aria-label="Print delivery challan"
            />
            <UButton v-if="canWrite && row.status === 'draft'" size="xs" variant="soft" @click="issueDraft(row)">Issue</UButton>
            <UButton
              v-if="canWrite && row.challan_kind === 'original' && row.status === 'delivered_unbilled'"
              size="xs" variant="soft" color="purple" @click="openCover(row)"
            >Cover with LC</UButton>
            <UButton
              v-if="canWrite && row.status === 'issued' && row.challan_kind !== 'original'"
              size="xs" variant="soft" color="green" @click="invoiceChallan(row)"
            >Invoice</UButton>
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">No challans yet.</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New delivery challan</p></template>
        <div class="grid grid-cols-2 gap-4 mb-4">
          <UFormGroup label="Sales order" required>
            <USelect v-model="form.so_id" :options="orders" option-attribute="so_no" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup label="Kind" required>
            <USelect v-model="form.challan_kind" :options="kindOptions" option-attribute="label" value-attribute="value" />
          </UFormGroup>
          <UFormGroup v-if="form.challan_kind === 'standard'" label="LC" required>
            <USelect v-model="form.lc_id" :options="lcs" option-attribute="lc_no" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup label="Actual delivery date">
            <UInput v-model="form.actual_delivery_date" type="date" />
          </UFormGroup>
          <UFormGroup label="Document (printed) date">
            <UInput v-model="form.document_date" type="date" />
          </UFormGroup>
        </div>
        <div v-if="lines.length" class="space-y-2">
          <p class="text-xs uppercase tracking-wide text-gray-400">Lines (prefilled with undelivered qty)</p>
          <div v-for="(l, idx) in lines" :key="idx" class="grid grid-cols-3 gap-2 items-center">
            <span class="text-sm">{{ l.sku }}</span>
            <UInput v-model.number="l.qty" type="number" />
            <UInput v-model.number="l.unit_price" type="number" />
          </div>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">Cancel</UButton>
            <UButton color="gray" variant="soft" :loading="saving" @click="save(false)">Save draft</UButton>
            <UButton :loading="saving" @click="save(true)">Issue now</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="coverOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header>
          <p class="font-medium">Cover {{ coverTarget?.challan_no }} with an LC</p>
        </template>
        <div class="space-y-4">
          <p class="text-sm text-gray-500">
            Issues an official-series covering challan linked to the original.
            Stock and GDNI stay untouched — the invoice will clear GDNI.
          </p>
          <UFormGroup label="LC" required>
            <USelect v-model="coverForm.lc_id" :options="lcs" option-attribute="lc_no" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup label="Document date (matches LC window)">
            <UInput v-model="coverForm.document_date" type="date" />
          </UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="coverOpen = false">Cancel</UButton>
            <UButton color="purple" @click="createCover">Issue covering set</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
