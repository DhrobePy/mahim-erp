<script setup lang="ts">
const client = useSupabaseClient()
const { money } = useFmt()

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
    <PageHeader kicker="Finance" title="VAT return working paper" subtitle="Mushak 9.1 basis — output VAT on domestic cash sales vs. input VAT credit from GRNs">
      <UButton icon="i-heroicons-printer" variant="soft" :to="printUrl" target="_blank">Print</UButton>
    </PageHeader>

    <UCard class="mb-4">
      <div class="flex items-end gap-3">
        <UFormGroup label="From"><UInput v-model="from" type="date" /></UFormGroup>
        <UFormGroup label="To"><UInput v-model="to" type="date" /></UFormGroup>
      </div>
    </UCard>

    <div class="grid grid-cols-3 gap-4 mb-6">
      <StatCard label="Output VAT (collected)" :value="money(outputTotal)" />
      <StatCard label="Input VAT (credit)" :value="money(inputTotal)" />
      <StatCard label="Net payable to NBR" :value="money(netPayable)" :tone="netPayable >= 0 ? 'amber' : 'green'" />
    </div>

    <div class="grid grid-cols-2 gap-4">
      <UCard :loading="loading">
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Output VAT — Mushak 6.3 (cash sales)</p></template>
        <div v-if="!output.length" class="text-sm text-gray-400 py-3 text-center">None in range.</div>
        <div v-for="(r, i) in output" :key="i" class="flex justify-between py-1.5 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
          <span><span class="num text-xs text-gray-400 mr-2">{{ r.txn_date }}</span>{{ r.doc_no }}</span>
          <span class="num">{{ money(r.vat_amount) }}</span>
        </div>
      </UCard>
      <UCard :loading="loading">
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Input VAT — Mushak 6.1 (GRNs)</p></template>
        <div v-if="!input.length" class="text-sm text-gray-400 py-3 text-center">None in range.</div>
        <div v-for="(r, i) in input" :key="i" class="flex justify-between py-1.5 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
          <span><span class="num text-xs text-gray-400 mr-2">{{ r.txn_date }}</span>{{ r.doc_no }}</span>
          <span class="num">{{ money(r.vat_amount) }}</span>
        </div>
      </UCard>
    </div>
  </div>
</template>
