<script setup lang="ts">
const client = useSupabaseClient()
const { money } = useFmt()
const { t } = useI18n()

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
    <PageHeader :kicker="t('accounting.kicker')" :title="t('accounting.ait_summary.title')" :subtitle="t('accounting.ait_summary.subtitle')">
      <UButton icon="i-heroicons-printer" variant="soft" to="/print/ait-summary" target="_blank">{{ t('common.print') }}</UButton>
    </PageHeader>

    <div class="grid grid-cols-2 gap-4 mb-6">
      <StatCard :label="t('accounting.ait_summary.stats.advance_paid.label')" :value="money(summary?.advance_tax_paid ?? 0)" :sub="t('accounting.ait_summary.stats.advance_paid.sub')" />
      <StatCard :label="t('accounting.ait_summary.stats.tds_payable.label')" :value="money(summary?.tds_withheld_payable ?? 0)" tone="amber" :sub="t('accounting.ait_summary.stats.tds_payable.sub')" />
    </div>

    <UCard :loading="loading">
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('accounting.ait_summary.detail_header') }}</p></template>
      <UTable
        :rows="entries"
        :columns="[
          { key: 'entry_no', label: t('accounting.ait_summary.columns.no') }, { key: 'entry_date', label: t('common.date') },
          { key: 'account', label: t('accounting.ait_summary.columns.account') }, { key: 'description', label: t('accounting.ait_summary.columns.description') },
          { key: 'reference_no', label: t('accounting.ait_summary.columns.reference') }, { key: 'amount', label: t('accounting.ait_summary.columns.amount') }
        ]"
      >
        <template #entry_no-data="{ row }"><span class="num text-amber-600 dark:text-amber-400 font-medium">{{ row.entry_no }}</span></template>
        <template #entry_date-data="{ row }"><span class="num">{{ row.entry_date }}</span></template>
        <template #account-data="{ row }">{{ row.cash_bank_accounts?.name }}</template>
        <template #amount-data="{ row }"><span class="num font-semibold">{{ money(row.amount) }}</span></template>
        <template #empty-state><div class="text-center py-6 text-sm text-gray-400">{{ t('accounting.ait_summary.empty') }}</div></template>
      </UTable>
    </UCard>
  </div>
</template>
