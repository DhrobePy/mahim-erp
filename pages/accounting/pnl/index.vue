<script setup lang="ts">
const client = useSupabaseClient()
const { money } = useFmt()

const loading = ref(true)
const from = ref('')
const to = ref('')

const rawLines = ref<any[]>([])

const pnlSection = (code: string) => {
  if (code.startsWith('41') || code.startsWith('42') || code.startsWith('43') || code === '4900') return 'revenue'
  if (code === '5100') return 'cogs'
  if (['5400', '5410', '5420', '5430'].includes(code)) return 'financial_expense'
  if (code.startsWith('5')) return 'operating_expense'
  return 'other'
}

const load = async () => {
  loading.value = true
  const { data: accts } = await client.from('accounts').select('id, code, name, account_type').in('account_type', ['income', 'expense'])
  const accountIds = (accts ?? []).map((a) => a.id)
  const accountMap = new Map((accts ?? []).map((a) => [a.id, a]))
  let lines: any[] = []
  if (accountIds.length) {
    const { data } = await client.from('journal_lines').select('account_id, debit, credit, journals(journal_date)').in('account_id', accountIds)
    lines = data ?? []
  }
  rawLines.value = lines.map((l) => ({ ...l, account: accountMap.get(l.account_id) }))
  loading.value = false
}
onMounted(load)

const filtered = computed(() =>
  rawLines.value.filter((l) => {
    const d = l.journals?.journal_date
    if (!d) return false
    if (from.value && d < from.value) return false
    if (to.value && d > to.value) return false
    return true
  })
)

const byAccount = computed(() => {
  const m = new Map<string, { code: string; name: string; type: string; amount: number }>()
  for (const l of filtered.value) {
    const a = l.account
    if (!a) continue
    const key = a.id
    const existing = m.get(key) ?? { code: a.code, name: a.name, type: a.account_type, amount: 0 }
    const delta = a.account_type === 'income' ? Number(l.credit) - Number(l.debit) : Number(l.debit) - Number(l.credit)
    existing.amount += delta
    m.set(key, existing)
  }
  return Array.from(m.values()).filter((x) => Math.abs(x.amount) > 0.005).sort((a, b) => a.code.localeCompare(b.code))
})

const section = (sec: string) => byAccount.value.filter((x) => pnlSection(x.code) === sec)
const sectionTotal = (sec: string) => section(sec).reduce((s, x) => s + x.amount, 0)

const revenue = computed(() => sectionTotal('revenue'))
const cogs = computed(() => sectionTotal('cogs'))
const grossProfit = computed(() => revenue.value - cogs.value)
const opex = computed(() => sectionTotal('operating_expense'))
const finExpense = computed(() => sectionTotal('financial_expense'))
const netProfit = computed(() => grossProfit.value - opex.value - finExpense.value)

const printUrl = computed(() => `/print/pnl?from=${from.value}&to=${to.value}`)
</script>

<template>
  <div>
    <PageHeader kicker="Finance" title="Profit &amp; Loss" subtitle="Revenue → COGS → gross profit → operating &amp; financial expenses → net profit">
      <UButton icon="i-heroicons-printer" variant="soft" :to="printUrl" target="_blank">Print</UButton>
    </PageHeader>

    <UCard class="mb-4">
      <div class="flex items-end gap-3">
        <UFormGroup label="From" hint="leave blank for all-time"><UInput v-model="from" type="date" /></UFormGroup>
        <UFormGroup label="To"><UInput v-model="to" type="date" /></UFormGroup>
      </div>
    </UCard>

    <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
      <StatCard label="Revenue" :value="money(revenue)" />
      <StatCard label="Gross profit" :value="money(grossProfit)" tone="green" />
      <StatCard label="Total expenses" :value="money(opex + finExpense + cogs)" tone="red" />
      <StatCard label="Net profit" :value="money(netProfit)" :tone="netProfit >= 0 ? 'green' : 'red'" />
    </div>

    <UCard :loading="loading">
      <table class="w-full text-sm">
        <tbody>
          <tr class="font-semibold"><td class="py-1.5">Revenue</td><td class="text-right num">{{ money(revenue) }}</td></tr>
          <tr v-for="a in section('revenue')" :key="a.code" class="text-xs text-gray-500 dark:text-zinc-400">
            <td class="py-0.5 pl-4"><span class="num text-gray-400 mr-1">{{ a.code }}</span>{{ a.name }}</td>
            <td class="text-right num">{{ money(a.amount) }}</td>
          </tr>

          <tr class="font-semibold border-t border-gray-100 dark:border-zinc-800"><td class="py-1.5 pt-3">Cost of goods sold</td><td class="text-right num">({{ money(cogs) }})</td></tr>
          <tr v-for="a in section('cogs')" :key="a.code" class="text-xs text-gray-500 dark:text-zinc-400">
            <td class="py-0.5 pl-4"><span class="num text-gray-400 mr-1">{{ a.code }}</span>{{ a.name }}</td>
            <td class="text-right num">({{ money(a.amount) }})</td>
          </tr>

          <tr class="font-semibold border-t border-gray-200 dark:border-zinc-700">
            <td class="py-1.5 pt-3">Gross profit</td><td class="text-right num text-emerald-600 dark:text-emerald-400">{{ money(grossProfit) }}</td>
          </tr>

          <tr class="font-semibold border-t border-gray-100 dark:border-zinc-800"><td class="py-1.5 pt-3">Operating expenses</td><td class="text-right num">({{ money(opex) }})</td></tr>
          <tr v-for="a in section('operating_expense')" :key="a.code" class="text-xs text-gray-500 dark:text-zinc-400">
            <td class="py-0.5 pl-4"><span class="num text-gray-400 mr-1">{{ a.code }}</span>{{ a.name }}</td>
            <td class="text-right num">({{ money(a.amount) }})</td>
          </tr>

          <tr class="font-semibold border-t border-gray-100 dark:border-zinc-800"><td class="py-1.5 pt-3">Financial expenses (bank charges, interest, legal)</td><td class="text-right num">({{ money(finExpense) }})</td></tr>
          <tr v-for="a in section('financial_expense')" :key="a.code" class="text-xs text-gray-500 dark:text-zinc-400">
            <td class="py-0.5 pl-4"><span class="num text-gray-400 mr-1">{{ a.code }}</span>{{ a.name }}</td>
            <td class="text-right num">({{ money(a.amount) }})</td>
          </tr>

          <tr class="font-semibold border-t-2 border-gray-300 dark:border-zinc-600 text-base">
            <td class="py-2 pt-3">Net profit</td>
            <td class="text-right num" :class="netProfit >= 0 ? 'text-emerald-600 dark:text-emerald-400' : 'text-red-600 dark:text-red-400'">{{ money(netProfit) }}</td>
          </tr>
        </tbody>
      </table>
    </UCard>
  </div>
</template>
