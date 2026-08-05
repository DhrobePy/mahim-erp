<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money } = useFmt()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const entries = ref<any[]>([])
const accounts = ref<any[]>([])
const loading = ref(true)

const categories = computed(() => [
  { value: 'lc_fee', label: t('accounting.bank_charges.categories.lc_fee') },
  { value: 'swift_fee', label: t('accounting.bank_charges.categories.swift_fee') },
  { value: 'service_charge', label: t('accounting.bank_charges.categories.service_charge') },
  { value: 'legal_fee', label: t('accounting.bank_charges.categories.legal_fee') },
  { value: 'ait_deducted', label: t('accounting.bank_charges.categories.ait_deducted') },
  { value: 'other', label: t('accounting.bank_charges.categories.other') }
])
const categoryLabel = computed<Record<string, string>>(() => Object.fromEntries(categories.value.map((c) => [c.value, c.label])))
const categoryColor: Record<string, string> = {
  lc_fee: 'blue', swift_fee: 'blue', service_charge: 'gray', legal_fee: 'purple', ait_deducted: 'amber', other: 'gray'
}

const load = async () => {
  loading.value = true
  const [e, a] = await Promise.all([
    client.from('bank_charge_entries').select('*, cash_bank_accounts(name)').is('deleted_at', null).order('created_at', { ascending: false }),
    client.from('cash_bank_accounts').select('id, name').eq('is_active', true).is('deleted_at', null).order('name')
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
  if (!form.cash_bank_account_id) { toast.add({ title: t('accounting.bank_charges.toasts.pick_account'), color: 'red' }); return }
  if (!form.amount || form.amount <= 0) { toast.add({ title: t('accounting.bank_charges.toasts.positive_amount'), color: 'red' }); return }
  saving.value = true
  const payload: any = { ...form, reference_no: form.reference_no || null }
  const { error } = await client.from('bank_charge_entries').insert(payload)
  if (error) toast.add({ title: t('accounting.bank_charges.toasts.failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('accounting.bank_charges.toasts.posted') }); open.value = false; await load() }
  saving.value = false
}

const debitAccount = (cat: string) => ({ legal_fee: '5430 Legal & Professional Fees', ait_deducted: '1250 Advance Income Tax' } as any)[cat] || '5400 Bank Charges & LC Fees'

const remove = async (row: any) => {
  if (await deleteRecord('bank_charge_entries', row.id, row.entry_no)) await load()
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('accounting.kicker')" :title="t('accounting.bank_charges.title')" :subtitle="t('accounting.bank_charges.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('accounting.bank_charges.new_entry') }}</UButton>
    </PageHeader>

    <UCard>
      <UTable
        :rows="entries" :loading="loading"
        :columns="[
          { key: 'entry_no', label: t('accounting.bank_charges.columns.no') }, { key: 'entry_date', label: t('common.date') },
          { key: 'account', label: t('accounting.bank_charges.columns.account') }, { key: 'category', label: t('accounting.bank_charges.columns.category') },
          { key: 'description', label: t('accounting.bank_charges.columns.description') }, { key: 'amount', label: t('accounting.bank_charges.columns.amount') },
          { key: 'vat_amount', label: t('accounting.bank_charges.columns.vat') }, { key: 'actions', label: '' }
        ]"
      >
        <template #entry_no-data="{ row }"><span class="num font-medium text-amber-600 dark:text-amber-400">{{ row.entry_no }}</span></template>
        <template #entry_date-data="{ row }"><span class="num">{{ row.entry_date }}</span></template>
        <template #account-data="{ row }">{{ row.cash_bank_accounts?.name }}</template>
        <template #category-data="{ row }"><UBadge size="xs" variant="subtle" :color="categoryColor[row.category]">{{ categoryLabel[row.category] }}</UBadge></template>
        <template #amount-data="{ row }"><span class="num font-semibold">{{ money(row.amount) }}</span></template>
        <template #vat_amount-data="{ row }"><span class="num">{{ row.vat_amount > 0 ? money(row.vat_amount) : '—' }}</span></template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton v-if="canWrite" icon="i-heroicons-trash" color="red" variant="ghost" size="xs" @click="remove(row)" />
          </div>
        </template>
        <template #empty-state><div class="text-center py-6 text-sm text-gray-400">{{ t('accounting.bank_charges.empty') }}</div></template>
      </UTable>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('accounting.bank_charges.dialog.title') }}</p></template>
        <div class="space-y-3">
          <UFormGroup :label="t('common.date')"><UInput v-model="form.entry_date" type="date" /></UFormGroup>
          <UFormGroup :label="t('accounting.bank_charges.dialog.account_charged')" required>
            <USelect v-model="form.cash_bank_account_id" :options="accounts" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup :label="t('accounting.bank_charges.dialog.category')">
            <USelect v-model="form.category" :options="categories" option-attribute="label" value-attribute="value" />
          </UFormGroup>
          <p class="text-xs text-gray-400">{{ t('accounting.bank_charges.dialog.posts_to', { account: debitAccount(form.category) }) }}</p>
          <UFormGroup :label="t('accounting.bank_charges.dialog.description')"><UInput v-model="form.description" :placeholder="t('accounting.bank_charges.dialog.description_placeholder')" /></UFormGroup>
          <UFormGroup :label="t('accounting.bank_charges.dialog.reference_no')" :hint="t('accounting.bank_charges.dialog.reference_no_hint')"><UInput v-model="form.reference_no" /></UFormGroup>
          <div class="grid grid-cols-2 gap-3">
            <UFormGroup :label="t('accounting.bank_charges.dialog.amount')"><UInput v-model.number="form.amount" type="number" /></UFormGroup>
            <UFormGroup :label="t('accounting.bank_charges.dialog.vat_creditable')" :hint="t('accounting.bank_charges.dialog.vat_creditable_hint')">
              <UInput v-model.number="form.vat_amount" type="number" />
            </UFormGroup>
          </div>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ t('accounting.bank_charges.dialog.post_entry') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
