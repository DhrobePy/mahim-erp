<script setup lang="ts">
const client = useSupabaseClient()
const { money } = useFmt()

const summary = ref<any>(null)
const entries = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [{ data: s }, { data: e }] = await Promise.all([
    client.from('v_ait_summary').select('*').maybeSingle(),
    client.from('bank_charge_entries').select('*, cash_bank_accounts(name)').eq('category', 'ait_deducted').order('entry_date', { ascending: false })
  ])
  summary.value = s
  entries.value = e ?? []
  loading.value = false
}
onMounted(load)
</script>

<template>
  <div>
    <PageHeader kicker="Finance" title="Advance Income Tax (AIT) summary" subtitle="Advance tax paid / deducted at source (adjustable against final liability) vs. TDS withheld from others (payable to NBR)">
      <UButton icon="i-heroicons-printer" variant="soft" to="/print/ait-summary" target="_blank">Print</UButton>
    </PageHeader>

    <div class="grid grid-cols-2 gap-4 mb-6">
      <StatCard label="Advance income tax paid (1250)" :value="money(summary?.advance_tax_paid ?? 0)" sub="Adjustable against final corporate tax liability" />
      <StatCard label="TDS withheld payable (2500)" :value="money(summary?.tds_withheld_payable ?? 0)" tone="amber" sub="Owed to NBR from deductions made on others' payments" />
    </div>

    <UCard :loading="loading">
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">AIT deducted at source — detail</p></template>
      <UTable
        :rows="entries"
        :columns="[
          { key: 'entry_no', label: 'No.' }, { key: 'entry_date', label: 'Date' },
          { key: 'account', label: 'Account' }, { key: 'description', label: 'Description' },
          { key: 'reference_no', label: 'Reference' }, { key: 'amount', label: 'Amount (৳)' }
        ]"
      >
        <template #entry_no-data="{ row }"><span class="num text-amber-600 dark:text-amber-400 font-medium">{{ row.entry_no }}</span></template>
        <template #entry_date-data="{ row }"><span class="num">{{ row.entry_date }}</span></template>
        <template #account-data="{ row }">{{ row.cash_bank_accounts?.name }}</template>
        <template #amount-data="{ row }"><span class="num font-semibold">{{ money(row.amount) }}</span></template>
        <template #empty-state><div class="text-center py-6 text-sm text-gray-400">No AIT deductions recorded yet.</div></template>
      </UTable>
    </UCard>
  </div>
</template>
