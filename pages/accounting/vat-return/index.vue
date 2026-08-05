<script setup lang="ts">
const client = useSupabaseClient()
const { money } = useFmt()
const { t } = useI18n()

const loading = ref(true)
const from = ref(new Date().toISOString().slice(0, 8) + '01')
const to = ref(new Date().toISOString().slice(0, 10))
const rows = ref<any[]>([])

const load = async () => {
  loading.value = true
  const { data } = await client.from('v_vat_transactions').select('*').order('txn_date', { ascending: false })
  rows.value = data ?? []
  loading.value = false
}
onMounted(load)

const filtered = computed(() => rows.value.filter((r) => {
  if (from.value && r.txn_date < from.value) return false
  if (to.value && r.txn_date > to.value) return false
  return true
}))
const output = computed(() => filtered.value.filter((r) => r.vat_side === 'output'))
const input = computed(() => filtered.value.filter((r) => r.vat_side === 'input'))
const outputTotal = computed(() => output.value.reduce((s, r) => s + Number(r.vat_amount), 0))
const inputTotal = computed(() => input.value.reduce((s, r) => s + Number(r.vat_amount), 0))
const netPayable = computed(() => outputTotal.value - inputTotal.value)

const printUrl = computed(() => `/print/vat-return?from=${from.value}&to=${to.value}`)
</script>

<template>
  <div>
    <PageHeader :kicker="t('accounting.kicker')" :title="t('accounting.vat_return.title')" :subtitle="t('accounting.vat_return.subtitle')">
      <UButton icon="i-heroicons-printer" variant="soft" :to="printUrl" target="_blank">{{ t('accounting.vat_return.print') }}</UButton>
    </PageHeader>

    <UCard class="mb-4">
      <div class="flex items-end gap-3">
        <UFormGroup :label="t('accounting.vat_return.from')"><UInput v-model="from" type="date" /></UFormGroup>
        <UFormGroup :label="t('accounting.vat_return.to')"><UInput v-model="to" type="date" /></UFormGroup>
      </div>
    </UCard>

    <div class="grid grid-cols-3 gap-4 mb-6">
      <StatCard :label="t('accounting.vat_return.output_vat')" :value="money(outputTotal)" />
      <StatCard :label="t('accounting.vat_return.input_vat')" :value="money(inputTotal)" />
      <StatCard :label="t('accounting.vat_return.net_payable')" :value="money(netPayable)" :tone="netPayable >= 0 ? 'amber' : 'green'" />
    </div>

    <div class="grid grid-cols-2 gap-4">
      <UCard :loading="loading">
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('accounting.vat_return.output_header') }}</p></template>
        <div v-if="!output.length" class="text-sm text-gray-400 py-3 text-center">{{ t('accounting.vat_return.none_in_range') }}</div>
        <div v-for="(r, i) in output" :key="i" class="flex justify-between py-1.5 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
          <span><span class="num text-xs text-gray-400 mr-2">{{ r.txn_date }}</span>{{ r.doc_no }}</span>
          <span class="num">{{ money(r.vat_amount) }}</span>
        </div>
      </UCard>
      <UCard :loading="loading">
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('accounting.vat_return.input_header') }}</p></template>
        <div v-if="!input.length" class="text-sm text-gray-400 py-3 text-center">{{ t('accounting.vat_return.none_in_range') }}</div>
        <div v-for="(r, i) in input" :key="i" class="flex justify-between py-1.5 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
          <span><span class="num text-xs text-gray-400 mr-2">{{ r.txn_date }}</span>{{ r.doc_no }}</span>
          <span class="num">{{ money(r.vat_amount) }}</span>
        </div>
      </UCard>
    </div>
  </div>
</template>
