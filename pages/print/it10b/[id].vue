<script setup lang="ts">
// IT-10B — Statement of Assets, Liabilities and Expenses. Draft
// preparation aid built from the ERP's records — verify against the
// current NBR-prescribed form and figures with a registered tax
// practitioner before filing with the return.
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()
const { num, money } = useFmt()
const { takaWords } = useTakaWords()

const id = route.params.id as string
const statement = ref<any>(null)
const lines = ref<any[]>([])
const company = ref<any>(null)
const loading = ref(true)

const categoryLabel: Record<string, string> = {
  business_capital: 'Business capital', non_agri_property: 'Non-agricultural property (at cost)',
  agri_property: 'Agricultural property', investments: 'Investments (shares, FDR, savings certificates, bonds)',
  motor_vehicles: 'Motor vehicles', ornaments: 'Ornaments / jewellery',
  furniture_electronics: 'Furniture, home appliances & electronics', cash_bank: 'Cash in hand / at bank',
  other_assets: 'Other assets', mortgage_liability: 'Mortgage liability',
  bank_loan_liability: 'Bank loan liability', other_liability: 'Other liability'
}
const assetCats = ['business_capital', 'non_agri_property', 'agri_property', 'investments', 'motor_vehicles', 'ornaments', 'furniture_electronics', 'cash_bank', 'other_assets']
const liabilityCats = ['mortgage_liability', 'bank_loan_liability', 'other_liability']

const load = async () => {
  loading.value = true
  const { data: s } = await client.from('it10b_statements')
    .select('*, company_directors(full_name, nid_no, tin_no, address, designation)').eq('id', id).single()
  statement.value = s
  if (s) {
    const [{ data: l }, { data: c }] = await Promise.all([
      client.from('it10b_lines').select('*').eq('statement_id', id),
      client.from('companies').select('*').eq('id', (s as any).company_id).single()
    ])
    lines.value = l ?? []
    company.value = c
  }
  loading.value = false
  if (route.query.auto) setTimeout(() => window.print(), 600)
}
onMounted(load)

const linesFor = (cats: string[]) => lines.value.filter((l) => cats.includes(l.category))
const sumFor = (cats: string[]) => linesFor(cats).reduce((s, l) => s + Number(l.amount), 0)
const totalAssets = computed(() => sumFor(assetCats))
const totalLiabilities = computed(() => sumFor(liabilityCats))
const netWealth = computed(() => totalAssets.value - totalLiabilities.value)
const closingCheck = computed(() =>
  Number(statement.value?.opening_net_wealth ?? 0) + Number(statement.value?.total_income ?? 0) - Number(statement.value?.total_expenditure ?? 0))

const who = computed(() => statement.value?.company_directors?.full_name || statement.value?.individual_name)
const fmtDate = (d?: string) => d
  ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' })
  : '—'
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink to="/admin/tax" class="back">← back</NuxtLink>
      <button class="print-btn" @click="() => window.print()">🖨 Print</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">Loading…</div>

    <div v-else-if="statement" class="sheet">
      <p class="form-tag">IT-10B</p>
      <div class="doc-title">STATEMENT OF ASSETS, LIABILITIES AND EXPENSES</div>
      <p class="small center">as on {{ fmtDate(statement.statement_date) }} — Assessment Year {{ statement.assessment_year }}</p>

      <table class="meta">
        <tbody>
          <tr>
            <td>
              <div class="small">Name of Assessee</div>
              <b>{{ who }}</b>
              <div class="small">{{ statement.company_directors?.designation ? statement.company_directors.designation.replace('_', ' ') : '' }}</div>
            </td>
            <td>
              <div class="small">TIN</div>
              <b class="mono">{{ statement.individual_tin || statement.company_directors?.tin_no || '—' }}</b>
              <div class="small mt">NID</div>
              <b class="mono">{{ statement.company_directors?.nid_no || '—' }}</b>
            </td>
            <td>
              <div class="small">Address</div>
              {{ statement.company_directors?.address || '—' }}
            </td>
          </tr>
        </tbody>
      </table>

      <p class="section-hdr">A. STATEMENT OF ASSETS</p>
      <table class="lines">
        <thead><tr><th style="width:24px;">SL</th><th>Head of Asset</th><th>Description</th><th class="right">Amount (৳)</th></tr></thead>
        <tbody>
          <tr v-for="(l, i) in linesFor(assetCats)" :key="l.id">
            <td>{{ i + 1 }}</td><td>{{ categoryLabel[l.category] }}</td><td>{{ l.description }}</td>
            <td class="right mono">{{ num(l.amount) }}</td>
          </tr>
          <tr v-if="!linesFor(assetCats).length"><td colspan="4" class="small center">No asset lines recorded.</td></tr>
          <tr class="total-row"><td colspan="3"><b>TOTAL ASSETS</b></td><td class="right mono"><b>{{ num(totalAssets) }}</b></td></tr>
        </tbody>
      </table>

      <p class="section-hdr">B. STATEMENT OF LIABILITIES</p>
      <table class="lines">
        <thead><tr><th style="width:24px;">SL</th><th>Head of Liability</th><th>Description</th><th class="right">Amount (৳)</th></tr></thead>
        <tbody>
          <tr v-for="(l, i) in linesFor(liabilityCats)" :key="l.id">
            <td>{{ i + 1 }}</td><td>{{ categoryLabel[l.category] }}</td><td>{{ l.description }}</td>
            <td class="right mono">{{ num(l.amount) }}</td>
          </tr>
          <tr v-if="!linesFor(liabilityCats).length"><td colspan="4" class="small center">No liability lines recorded.</td></tr>
          <tr class="total-row"><td colspan="3"><b>TOTAL LIABILITIES</b></td><td class="right mono"><b>{{ num(totalLiabilities) }}</b></td></tr>
        </tbody>
      </table>

      <table class="lines">
        <tbody>
          <tr class="total-row"><td><b>NET WEALTH (A − B)</b></td><td class="right mono"><b>{{ num(netWealth) }}</b></td></tr>
        </tbody>
      </table>
      <p class="small">In words: {{ takaWords(netWealth) }}</p>

      <p class="section-hdr">C. RECONCILIATION OF WEALTH (LIFE STYLE STATEMENT)</p>
      <table class="lines">
        <tbody>
          <tr><td>Net wealth at the end of last income year (opening)</td><td class="right mono">{{ num(statement.opening_net_wealth) }}</td></tr>
          <tr><td>Add: Total income during the year</td><td class="right mono">{{ num(statement.total_income) }}</td></tr>
          <tr><td>Less: Total family expenditure during the year</td><td class="right mono">({{ num(statement.total_expenditure) }})</td></tr>
          <tr class="total-row"><td><b>Net wealth at the end of this income year (computed)</b></td><td class="right mono"><b>{{ num(closingCheck) }}</b></td></tr>
          <tr>
            <td><b>Net wealth per Statement A − B above (should match)</b></td>
            <td class="right mono"><b :class="Math.abs(closingCheck - netWealth) > 1 ? 'mismatch' : ''">{{ num(netWealth) }}</b></td>
          </tr>
        </tbody>
      </table>
      <p v-if="Math.abs(closingCheck - netWealth) > 1" class="small mismatch">
        Reconciliation does not tie out — review income/expenditure figures or asset/liability lines before filing.
      </p>

      <p class="disclaimer">
        Draft prepared from the company's internal records for reference in filing preparation only.
        Verify all figures and the current NBR-prescribed IT-10B format with a registered tax practitioner before submission.
      </p>

      <div class="row spread sig-block">
        <div class="sig"><div class="sig-line" /><div class="small">Signature of Assessee</div></div>
        <div class="sig"><div class="sig-line" /><div class="small">Date</div></div>
      </div>
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
  width: 210mm; min-height: 280mm; margin: 0 auto 20px; background: #fff; color: #111;
  padding: 16mm; box-shadow: 0 2px 12px rgba(0,0,0,.4); font-size: 12px; line-height: 1.5;
}
.form-tag { text-align: center; font-weight: 700; letter-spacing: 3px; margin: 0; }
.doc-title { text-align: center; font-size: 14px; font-weight: 700; margin: 6px 0 4px; }
.small { font-size: 10.5px; color: #333; }
.small.center { text-align: center; }
.mt { margin-top: 6px; }
.mono { font-family: 'JetBrains Mono', monospace; font-size: 11px; }
.row { display: flex; }
.spread { justify-content: space-between; }
.right { text-align: right; }
.center { text-align: center; }
.section-hdr { font-weight: 700; font-size: 11.5px; margin: 14px 0 4px; text-transform: uppercase; letter-spacing: .4px; border-bottom: 1px solid #111; padding-bottom: 2px; }
table.meta { width: 100%; border-collapse: collapse; margin: 10px 0; }
table.meta td { border: 1px solid #444; padding: 6px 8px; vertical-align: top; width: 33%; }
table.lines { width: 100%; border-collapse: collapse; margin: 4px 0 6px; }
table.lines th, table.lines td { border: 1px solid #444; padding: 4px 6px; font-size: 11px; }
table.lines th { background: #f0f0f0; font-size: 10px; text-transform: uppercase; letter-spacing: .3px; }
.total-row td { background: #fafafa; }
.mismatch { color: #a32d2d; }
.disclaimer { font-size: 9.5px; color: #666; font-style: italic; border-top: 1px dashed #999; padding-top: 6px; margin-top: 12px; }
.sig { text-align: center; }
.sig-line { border-top: 1px solid #111; width: 200px; margin: 40px auto 4px; }
.sig-block { margin-top: 20px; }
@media print {
  .no-print { display: none !important; }
  .print-root { background: #fff; padding: 0; }
  .sheet { box-shadow: none; margin: 0; min-height: auto; }
}
</style>
