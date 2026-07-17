<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money } = useFmt()

const transfers = ref<any[]>([])
const accounts = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [t, a] = await Promise.all([
    client.from('account_transfers')
      .select('*, from:cash_bank_accounts!account_transfers_from_account_id_fkey(name), to:cash_bank_accounts!account_transfers_to_account_id_fkey(name)')
      .order('created_at', { ascending: false }),
    client.from('cash_bank_accounts').select('id, name').eq('is_active', true).order('name')
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
  if (!form.from_account_id || !form.to_account_id) { toast.add({ title: 'Pick both accounts', color: 'red' }); return }
  if (form.from_account_id === form.to_account_id) { toast.add({ title: 'From and to must differ', color: 'red' }); return }
  if (!form.amount || form.amount <= 0) { toast.add({ title: 'Amount must be positive', color: 'red' }); return }
  saving.value = true
  const { error } = await client.from('account_transfers').insert({ ...form } as any)
  if (error) toast.add({ title: 'Transfer failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Transfer posted' }); open.value = false; await load() }
  saving.value = false
}
</script>

<template>
  <div>
    <PageHeader kicker="Finance" title="Inter-account transfers" subtitle="Move funds between bank accounts or bank ↔ cash — posts a contra journal instantly">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New transfer</UButton>
    </PageHeader>

    <UCard>
      <UTable
        :rows="transfers" :loading="loading"
        :columns="[
          { key: 'transfer_no', label: 'No.' }, { key: 'transfer_date', label: 'Date' },
          { key: 'from', label: 'From' }, { key: 'to', label: 'To' },
          { key: 'amount', label: 'Amount (৳)' }, { key: 'note', label: 'Note' }
        ]"
      >
        <template #transfer_no-data="{ row }"><span class="num font-medium text-amber-600 dark:text-amber-400">{{ row.transfer_no }}</span></template>
        <template #transfer_date-data="{ row }"><span class="num">{{ row.transfer_date }}</span></template>
        <template #from-data="{ row }">{{ row.from?.name }}</template>
        <template #to-data="{ row }">{{ row.to?.name }}</template>
        <template #amount-data="{ row }"><span class="num font-semibold">{{ money(row.amount) }}</span></template>
        <template #empty-state><div class="text-center py-6 text-sm text-gray-400">No transfers yet.</div></template>
      </UTable>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New transfer</p></template>
        <div class="space-y-3">
          <UFormGroup label="Date"><UInput v-model="form.transfer_date" type="date" /></UFormGroup>
          <UFormGroup label="From" required>
            <USelect v-model="form.from_account_id" :options="accounts" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup label="To" required>
            <USelect v-model="form.to_account_id" :options="accounts" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup label="Amount (৳)"><UInput v-model.number="form.amount" type="number" /></UFormGroup>
          <UFormGroup label="Note"><UInput v-model="form.note" placeholder="e.g. moving float to factory till" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">Cancel</UButton>
            <UButton :loading="saving" @click="save">Transfer</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
