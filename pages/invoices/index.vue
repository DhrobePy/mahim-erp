<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const invoices = ref<any[]>([])
const loading = ref(true)

const columns = computed(() => [
  { key: 'invoice_no', label: t('invoices.list.columns.invoice') },
  { key: 'customer', label: t('invoices.list.columns.buyer') },
  { key: 'invoice_date', label: t('common.date') },
  { key: 'challan', label: t('invoices.list.columns.challan') },
  { key: 'lc', label: t('invoices.list.columns.lc') },
  { key: 'total', label: t('invoices.list.columns.total') },
  { key: 'status', label: t('common.status') },
  { key: 'actions', label: '' }
])

const load = async () => {
  loading.value = true
  const { data } = await client.from('invoices')
    .select('*, parties(name), lcs(lc_no), delivery_challans!invoices_challan_id_fkey(challan_no, challan_kind), invoice_lines(id, qty, unit_price, item_id, items(sku))')
    .is('deleted_at', null)
    .order('created_at', { ascending: false })
  invoices.value = data ?? []
  loading.value = false
}
onMounted(load)

const makeBill = async (row: any) => {
  const { error } = await client.rpc('create_bill', { p_invoice_id: row.id } as any)
  if (error) toast.add({ title: t('invoices.list.bill_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('invoices.list.bill_submitted', { invoice: row.invoice_no }) }); await load() }
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
  if (error) toast.add({ title: t('invoices.list.return_dialog.return_failed'), description: error.message, color: 'red' })
  else {
    toast.add({ title: t('invoices.list.return_dialog.credit_note_issued') })
    retOpen.value = false
    await load()
  }
}

const onDelete = async (row: any) => {
  if (await deleteRecord('invoices', row.id, row.invoice_no)) await load()
}

const statusColor = (s: string) =>
  ({ open: 'blue', billed: 'purple', settled: 'green' } as any)[s] || 'gray'
</script>

<template>
  <div>
    <PageHeader :kicker="t('invoices.list.kicker')" :title="t('invoices.list.title')" :subtitle="t('invoices.list.subtitle')" />

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
          >{{ t('invoices.list.covering') }}</UBadge>
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
              :to="`/print/${row.id}`" target="_blank" :aria-label="t('invoices.list.print_aria')"
            />
            <UButton
              v-if="canWrite && row.lc_id && row.status === 'open'"
              size="xs" variant="soft" @click="makeBill(row)"
            >{{ t('invoices.list.submit_bill') }}</UButton>
            <UButton
              v-if="canWrite && row.status !== 'open'"
              size="xs" variant="soft" color="red" @click="openReturn(row)"
            >{{ t('invoices.list.return') }}</UButton>
            <UButton v-if="canWrite" icon="i-heroicons-trash" size="xs" color="red" variant="ghost" :aria-label="t('common.delete')" @click="onDelete(row)" />
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('invoices.list.empty') }}</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="retOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('invoices.list.return_dialog.title', { invoice: retTarget?.invoice_no }) }}</p></template>
        <div class="space-y-4">
          <UFormGroup :label="t('invoices.list.return_dialog.item')">
            <USelect
              v-model="retForm.item_id"
              :options="(retTarget?.invoice_lines ?? []).map((l: any) => ({ id: l.item_id, sku: l.items?.sku }))"
              option-attribute="sku" value-attribute="id"
            />
          </UFormGroup>
          <UFormGroup :label="t('invoices.list.return_dialog.returned_qty')"><UInput v-model.number="retForm.qty" type="number" /></UFormGroup>
          <UFormGroup :label="t('invoices.list.return_dialog.scrap_unit_value')" :hint="t('invoices.list.return_dialog.scrap_unit_value_hint')">
            <UInput v-model.number="retForm.scrap_unit_value" type="number" />
          </UFormGroup>
          <UFormGroup :label="t('invoices.list.return_dialog.reason')"><UInput v-model="retForm.reason" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="retOpen = false">{{ t('common.cancel') }}</UButton>
            <UButton color="red" @click="saveReturn">{{ t('invoices.list.return_dialog.issue_credit_note') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
