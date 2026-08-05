<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money } = useFmt()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const transfers = ref<any[]>([])
const accounts = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [t, a] = await Promise.all([
    client.from('account_transfers')
      .select('*, from:cash_bank_accounts!account_transfers_from_account_id_fkey(name), to:cash_bank_accounts!account_transfers_to_account_id_fkey(name)')
      .is('deleted_at', null)
      .order('created_at', { ascending: false }),
    client.from('cash_bank_accounts').select('id, name').eq('is_active', true).is('deleted_at', null).order('name')
  ])
  transfers.value = t.data ?? []
  accounts.value = a.data ?? []
  loading.value = false
}
onMounted(load)

const open = ref(false)
const saving = ref(false)
const form = reactive({
  transfer_date: new Date().toISOString().slice(0, 10),
  from_account_id: null as string | null, to_account_id: null as string | null,
  amount: 0, note: ''
})
const openNew = () => {
  Object.assign(form, { transfer_date: new Date().toISOString().slice(0, 10), from_account_id: null, to_account_id: null, amount: 0, note: '' })
  open.value = true
}
const save = async () => {
  if (!form.from_account_id || !form.to_account_id) { toast.add({ title: t('accounting.transfers.toasts.pick_both'), color: 'red' }); return }
  if (form.from_account_id === form.to_account_id) { toast.add({ title: t('accounting.transfers.toasts.must_differ'), color: 'red' }); return }
  if (!form.amount || form.amount <= 0) { toast.add({ title: t('accounting.transfers.toasts.positive_amount'), color: 'red' }); return }
  saving.value = true
  const { error } = await client.from('account_transfers').insert({ ...form } as any)
  if (error) toast.add({ title: t('accounting.transfers.toasts.failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('accounting.transfers.toasts.posted') }); open.value = false; await load() }
  saving.value = false
}

const remove = async (row: any) => {
  if (await deleteRecord('account_transfers', row.id, row.transfer_no)) await load()
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('accounting.kicker')" :title="t('accounting.transfers.title')" :subtitle="t('accounting.transfers.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('accounting.transfers.new_transfer') }}</UButton>
    </PageHeader>

    <UCard>
      <UTable
        :rows="transfers" :loading="loading"
        :columns="[
          { key: 'transfer_no', label: t('accounting.transfers.columns.no') }, { key: 'transfer_date', label: t('common.date') },
          { key: 'from', label: t('accounting.transfers.columns.from') }, { key: 'to', label: t('accounting.transfers.columns.to') },
          { key: 'amount', label: t('accounting.transfers.columns.amount') }, { key: 'note', label: t('common.note') },
          { key: 'actions', label: '' }
        ]"
      >
        <template #transfer_no-data="{ row }"><span class="num font-medium text-amber-600 dark:text-amber-400">{{ row.transfer_no }}</span></template>
        <template #transfer_date-data="{ row }"><span class="num">{{ row.transfer_date }}</span></template>
        <template #from-data="{ row }">{{ row.from?.name }}</template>
        <template #to-data="{ row }">{{ row.to?.name }}</template>
        <template #amount-data="{ row }"><span class="num font-semibold">{{ money(row.amount) }}</span></template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton v-if="canWrite" icon="i-heroicons-trash" color="red" variant="ghost" size="xs" @click="remove(row)" />
          </div>
        </template>
        <template #empty-state><div class="text-center py-6 text-sm text-gray-400">{{ t('accounting.transfers.empty') }}</div></template>
      </UTable>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('accounting.transfers.dialog.title') }}</p></template>
        <div class="space-y-3">
          <UFormGroup :label="t('common.date')"><UInput v-model="form.transfer_date" type="date" /></UFormGroup>
          <UFormGroup :label="t('accounting.transfers.dialog.from')" required>
            <USelect v-model="form.from_account_id" :options="accounts" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup :label="t('accounting.transfers.dialog.to')" required>
            <USelect v-model="form.to_account_id" :options="accounts" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup :label="t('accounting.transfers.dialog.amount')"><UInput v-model.number="form.amount" type="number" /></UFormGroup>
          <UFormGroup :label="t('common.note')"><UInput v-model="form.note" :placeholder="t('accounting.transfers.dialog.note_placeholder')" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ t('accounting.transfers.dialog.transfer_btn') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
