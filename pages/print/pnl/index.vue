<script setup lang="ts">
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()
const { money } = useFmt()
const { logoUrl } = useCompanyLogo()

const from = (route.query.from as string) || ''
const to = (route.query.to as string) || ''
const company = ref<any>(null)
const loading = ref(true)
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
  const { data: accts } = await client.from('accounts').select('id, code, name, account_type, company_id').in('account_type', ['income', 'expense'])
  const accountIds = (accts ?? []).map((a) => a.id)
  const accountMap = new Map((accts ?? []).map((a) => [a.id, a]))
  let lines: any[] = []
  if (accountIds.length) {
    const { data } = await client.from('journal_lines').select('account_id, debit, credit, journals(journal_date)').in('account_id', accountIds)
    lines = data ?? []
  }
  rawLines.value = lines.map((l) => ({ ...l, account: accountMap.get(l.account_id) }))
  const firstCompanyId = accts?.[0]?.company_id
  if (firstCompanyId) {
    const { data: c } = await client.from('companies').select('*').eq('id', firstCompanyId).single()
    company.value = c
  }
  loading.value = false
  if (route.query.auto) setTimeout(() => window.print(), 600)
}
onMounted(load)

const filtered = computed(() =>
  rawLines.value.filter((l) => {
    const d = l.journals?.journal_date
    if (!d) return false
    if (from && d < from) return false
    if (to && d > to) return false
    return true
  })
)
const byAccount = computed(() => {
  const m = new Map<string, { code: string; name: string; type: string; amount: number }>()
  for (const l of filtered.value) {
    const a = l.account
    if (!a) continue
    const existing = m.get(a.id) ?? { code: a.code, name: a.name, type: a.account_type, amount: 0 }
    const delta = a.account_type === 'income' ? Number(l.credit) - Number(l.debit) : Number(l.debit) - Number(l.credit)
    existing.amount += delta
    m.set(a.id, existing)
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

const fmtDate = (d?: string) => d
  ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' })
  : '—'
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink to="/accounting/pnl" class="back">← back</NuxtLink>
      <button class="print-btn" @click="() => window.print()">🖨 Print</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">Loading…</div>

    <div v-else class="sheet">
      <div class="letterhead">
        <img v-if="company && logoUrl(company)" :src="logoUrl(company)" class="co-logo" alt="Company logo">
        <div class="co-name">{{ company?.legal_name || company?.name }}</div>
        <div class="title">PROFIT &amp; LOSS STATEMENT</div>
        <div class="small">{{ from ? `${fmtDate(from)} to ${fmtDate(to)}` : 'All-time (since inception)' }}</div>
      </div>

      <table class="pnl-table">
        <tbody>
          <tr class="section"><td>Revenue</td><td class="num">{{ money(revenue) }}</td></tr>
          <tr v-for="a in section('revenue')" :key="a.code" class="detail"><td>{{ a.code }} — {{ a.name }}</td><td class="num">{{ money(a.amount) }}</td></tr>

          <tr class="section"><td>Cost of goods sold</td><td class="num">({{ money(cogs) }})</td></tr>
          <tr v-for="a in section('cogs')" :key="a.code" class="detail"><td>{{ a.code }} — {{ a.name }}</td><td class="num">({{ money(a.amount) }})</td></tr>

          <tr class="subtotal"><td>Gross profit</td><td class="num">{{ money(grossProfit) }}</td></tr>

          <tr class="section"><td>Operating expenses</td><td class="num">({{ money(opex) }})</td></tr>
          <tr v-for="a in section('operating_expense')" :key="a.code" class="detail"><td>{{ a.code }} — {{ a.name }}</td><td class="num">({{ money(a.amount) }})</td></tr>

          <tr class="section"><td>Financial expenses</td><td class="num">({{ money(finExpense) }})</td></tr>
          <tr v-for="a in section('financial_expense')" :key="a.code" class="detail"><td>{{ a.code }} — {{ a.name }}</td><td class="num">({{ money(a.amount) }})</td></tr>

          <tr class="total"><td>Net profit</td><td class="num">{{ money(netProfit) }}</td></tr>
        </tbody>
      </table>

      <p class="small disclaimer">This is a management working paper generated from posted GL entries. It is not an audited financial statement.</p>
    </div>
  </div>
</template>

<style scoped>
.print-root { min-height: 100vh; background: #3f3f46; padding: 16px 0 48px; font-family: Georgia, 'Times New Roman', serif; }
.toolbar {
  position: sticky; top: 0; z-index: 5; display: flex; gap: 18px; align-items: center; justify-content: center;
  background: #18181b; color: #e4e4e7; padding: 10px; margin: -16px 0 16px; font-family: Inter, sans-serif; font-size: 13px;
}
.toolbar .back { color: #fbbf24; text-decoration: none; }
.print-btn { background: #f59e0b; color: #000; border: 0; border-radius: 4px; padding: 6px 16px; font-weight: 600; cursor: pointer; }
.sheet {
  width: 210mm; min-height: 200mm; margin: 0 auto 20px; background: #fff; color: #111;
  padding: 20mm 18mm; box-shadow: 0 2px 12px rgba(0,0,0,.4); font-size: 13px; line-height: 1.6;
}
.letterhead { text-align: center; border-bottom: 2px solid #111; padding-bottom: 10px; margin-bottom: 18px; }
.co-logo { max-height: 48px; max-width: 220px; margin: 0 auto 6px; display: block; object-fit: contain; }
.co-name { font-size: 20px; font-weight: 700; letter-spacing: 1px; }
.title { margin-top: 8px; font-size: 14px; font-weight: 700; letter-spacing: 2px; }
.small { font-size: 11px; color: #333; margin-top: 4px; }
table.pnl-table { width: 100%; border-collapse: collapse; margin: 18px 0; }
table.pnl-table td { padding: 3px 4px; }
table.pnl-table .num { text-align: right; font-family: 'JetBrains Mono', monospace; }
tr.section td { font-weight: 700; padding-top: 10px; }
tr.detail td { font-size: 11px; color: #444; padding-left: 16px; }
tr.subtotal td { font-weight: 700; border-top: 1px solid #111; padding-top: 8px; }
tr.total td { font-weight: 700; font-size: 15px; border-top: 2px solid #111; padding-top: 10px; }
.disclaimer { margin-top: 24px; font-style: italic; }
@media print {
  .no-print { display: none !important; }
  .print-root { background: #fff; padding: 0; }
  .sheet { box-shadow: none; margin: 0; min-height: auto; }
}
</style>
