<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()

const invoices = ref<any[]>([])
const loading = ref(true)

const columns = [
  { key: 'invoice_no', label: 'Invoice' },
  { key: 'customer', label: 'Buyer' },
  { key: 'invoice_date', label: 'Date' },
  { key: 'challan', label: 'Challan' },
  { key: 'lc', label: 'LC' },
  { key: 'total', label: 'Total (৳)' },
  { key: 'status', label: 'Status' },
  { key: 'actions', label: '' }
]

const load = async () => {
  loading.value = true
  const { data } = await client.from('invoices')
    .select('*, parties(name), lcs(lc_no), delivery_challans!invoices_challan_id_fkey(challan_no, challan_kind), invoice_lines(id, qty, unit_price, item_id, items(sku))')
    .order('created_at', { ascending: false })
  invoices.value = data ?? []
  loading.value = false
}
onMounted(load)

const makeBill = async (row: any) => {
  const { error } = await client.rpc('create_bill', { p_invoice_id: row.id } as any)
  if (error) toast.add({ title: 'Bill failed', description: error.message, color: 'red' })
  else { toast.add({ title: `Bill submitted for ${row.invoice_no} — see Banking` }); await load() }
}

// --- Sales return ---
const retOpen = ref(false)
const retTarget = ref<any>(null)
const retForm = reactive({ item_id: null as string | null, qty: 0, scrap_unit_value: 0, reason: '' })
const openReturn = (row: any) => {
  retTarget.value = row
  Object.assign(retForm, { item_id: row.invoice_lines?.[0]?.item_id ?? null, qty: 0, scrap_unit_value: 0, reason: '' })
  retOpen.value = true
}
const saveReturn = async () => {
  const { error } = await client.rpc('process_sales_return', {
    p_invoice_id: retTarget.value.id,
    p_item_id: retForm.item_id,
    p_qty: retForm.qty,
    p_scrap_unit_value: retForm.scrap_unit_value,
    p_reason: retForm.reason || null
  } as any)
  if (error) toast.add({ title: 'Return failed', description: error.message, color: 'red' })
  else {
    toast.add({ title: 'Credit note issued — stock downgraded to scrap' })
    retOpen.value = false
    await load()
  }
}

const statusColor = (s: string) =>
  ({ open: 'blue', billed: 'purple', settled: 'green' } as any)[s] || 'gray'
</script>

<template>
  <div>
    <PageHeader kicker="Sales &amp; Local LC" title="Invoices" subtitle="Created from issued challans; submit bills against LC invoices for LBPD" />

    <UCard>
      <UTable :rows="invoices" :columns="columns" :loading="loading">
        <template #customer-data="{ row }">
          <NuxtLink :to="`/parties/${row.customer_party_id}`" class="hover:underline">{{ row.parties?.name }}</NuxtLink>
        </template>
        <template #challan-data="{ row }">
          {{ row.delivery_challans?.challan_no }}
          <UBadge
            v-if="row.delivery_challans?.challan_kind === 'covering'"
            size="xs" variant="subtle" color="purple" class="ml-1"
          >covering</UBadge>
        </template>
        <template #invoice_no-data="{ row }">
          <NuxtLink :to="`/invoices/${row.id}`" class="num font-medium text-amber-600 dark:text-amber-400 hover:underline">{{ row.invoice_no }}</NuxtLink>
        </template>
        <template #total-data="{ row }">
          <span class="num font-semibold text-amber-600 dark:text-amber-400">{{ Number(row.total).toLocaleString('en-IN') }}</span>
        </template>
        <template #lc-data="{ row }">
          <NuxtLink v-if="row.lc_id" :to="`/lcs/${row.lc_id}`" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ row.lcs?.lc_no }}</NuxtLink>
          <span v-else>—</span>
        </template>
        <template #status-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="statusColor(row.status)">{{ row.status }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton
              icon="i-heroicons-printer" size="xs" color="gray" variant="ghost"
              :to="`/print/${row.id}`" target="_blank" aria-label="Print bank document set"
            />
            <UButton
              v-if="canWrite && row.lc_id && row.status === 'open'"
              size="xs" variant="soft" @click="makeBill(row)"
            >Submit bill</UButton>
            <UButton
              v-if="canWrite && row.status !== 'open'"
              size="xs" variant="soft" color="red" @click="openReturn(row)"
            >Return</UButton>
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">No invoices — issue and invoice a challan first.</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="retOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">Sales return against {{ retTarget?.invoice_no }}</p></template>
        <div class="space-y-4">
          <UFormGroup label="Item">
            <USelect
              v-model="retForm.item_id"
              :options="(retTarget?.invoice_lines ?? []).map((l: any) => ({ id: l.item_id, sku: l.items?.sku }))"
              option-attribute="sku" value-attribute="id"
            />
          </UFormGroup>
          <UFormGroup label="Returned qty"><UInput v-model.number="retForm.qty" type="number" /></UFormGroup>
          <UFormGroup label="Scrap unit value (৳)" hint="branded stock downgrades to scrap at this value">
            <UInput v-model.number="retForm.scrap_unit_value" type="number" />
          </UFormGroup>
          <UFormGroup label="Reason"><UInput v-model="retForm.reason" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="retOpen = false">Cancel</UButton>
            <UButton color="red" @click="saveReturn">Issue credit note</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
