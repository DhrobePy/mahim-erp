<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money } = useFmt()

const entries = ref<any[]>([])
const accounts = ref<any[]>([])
const loading = ref(true)

const categories = [
  { value: 'lc_fee', label: 'LC fee' },
  { value: 'swift_fee', label: 'SWIFT fee' },
  { value: 'service_charge', label: 'Service charge' },
  { value: 'legal_fee', label: 'Legal & professional fee' },
  { value: 'ait_deducted', label: 'AIT deducted at source' },
  { value: 'other', label: 'Other' }
]
const categoryLabel: Record<string, string> = Object.fromEntries(categories.map((c) => [c.value, c.label]))
const categoryColor: Record<string, string> = {
  lc_fee: 'blue', swift_fee: 'blue', service_charge: 'gray', legal_fee: 'purple', ait_deducted: 'amber', other: 'gray'
}

const load = async () => {
  loading.value = true
  const [e, a] = await Promise.all([
    client.from('bank_charge_entries').select('*, cash_bank_accounts(name)').order('created_at', { ascending: false }),
    client.from('cash_bank_accounts').select('id, name').eq('is_active', true).order('name')
  ])
  entries.value = e.data ?? []
  accounts.value = a.data ?? []
  loading.value = false
}
onMounted(load)

const open = ref(false)
const saving = ref(false)
const form = reactive({
  entry_date: new Date().toISOString().slice(0, 10),
  cash_bank_account_id: null as string | null, category: 'service_charge',
  description: '', amount: 0, vat_amount: 0, reference_no: ''
})
const openNew = () => {
  Object.assign(form, {
    entry_date: new Date().toISOString().slice(0, 10), cash_bank_account_id: null, category: 'service_charge',
    description: '', amount: 0, vat_amount: 0, reference_no: ''
  })
  open.value = true
}
const save = async () => {
  if (!form.cash_bank_account_id) { toast.add({ title: 'Pick the account charged', color: 'red' }); return }
  if (!form.amount || form.amount <= 0) { toast.add({ title: 'Amount must be positive', color: 'red' }); return }
  saving.value = true
  const payload: any = { ...form, reference_no: form.reference_no || null }
  const { error } = await client.from('bank_charge_entries').insert(payload)
  if (error) toast.add({ title: 'Entry failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Charge posted' }); open.value = false; await load() }
  saving.value = false
}

const debitAccount = (cat: string) => ({ legal_fee: '5430 Legal & Professional Fees', ait_deducted: '1250 Advance Income Tax' } as any)[cat] || '5400 Bank Charges & LC Fees'
</script>

<template>
  <div>
    <PageHeader kicker="Finance" title="Bank charges, fees &amp; AIT" subtitle="LC fees, SWIFT charges, service charges, legal fees and AIT deducted at source — each posts against the right expense/asset account">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New entry</UButton>
    </PageHeader>

    <UCard>
      <UTable
        :rows="entries" :loading="loading"
        :columns="[
          { key: 'entry_no', label: 'No.' }, { key: 'entry_date', label: 'Date' },
          { key: 'account', label: 'Account' }, { key: 'category', label: 'Category' },
          { key: 'description', label: 'Description' }, { key: 'amount', label: 'Amount (৳)' },
          { key: 'vat_amount', label: 'VAT (৳)' }
        ]"
      >
        <template #entry_no-data="{ row }"><span class="num font-medium text-amber-600 dark:text-amber-400">{{ row.entry_no }}</span></template>
        <template #entry_date-data="{ row }"><span class="num">{{ row.entry_date }}</span></template>
        <template #account-data="{ row }">{{ row.cash_bank_accounts?.name }}</template>
        <template #category-data="{ row }"><UBadge size="xs" variant="subtle" :color="categoryColor[row.category]">{{ categoryLabel[row.category] }}</UBadge></template>
        <template #amount-data="{ row }"><span class="num font-semibold">{{ money(row.amount) }}</span></template>
        <template #vat_amount-data="{ row }"><span class="num">{{ row.vat_amount > 0 ? money(row.vat_amount) : '—' }}</span></template>
        <template #empty-state><div class="text-center py-6 text-sm text-gray-400">No charge entries yet.</div></template>
      </UTable>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New bank charge / fee entry</p></template>
        <div class="space-y-3">
          <UFormGroup label="Date"><UInput v-model="form.entry_date" type="date" /></UFormGroup>
          <UFormGroup label="Account charged" required>
            <USelect v-model="form.cash_bank_account_id" :options="accounts" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup label="Category">
            <USelect v-model="form.category" :options="categories" option-attribute="label" value-attribute="value" />
          </UFormGroup>
          <p class="text-xs text-gray-400">Posts to {{ debitAccount(form.category) }}</p>
          <UFormGroup label="Description"><UInput v-model="form.description" placeholder="e.g. LC issuance commission, court filing fee" /></UFormGroup>
          <UFormGroup label="Reference no." hint="optional — debit advice / voucher no."><UInput v-model="form.reference_no" /></UFormGroup>
          <div class="grid grid-cols-2 gap-3">
            <UFormGroup label="Amount (৳)"><UInput v-model.number="form.amount" type="number" /></UFormGroup>
            <UFormGroup label="Of which creditable VAT (৳)" hint="only if separately shown — confirm with accountant">
              <UInput v-model.number="form.vat_amount" type="number" />
            </UFormGroup>
          </div>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">Cancel</UButton>
            <UButton :loading="saving" @click="save">Post entry</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
