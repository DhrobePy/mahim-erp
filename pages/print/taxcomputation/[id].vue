<script setup lang="ts">
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()
const { money } = useFmt()
const { logoUrl } = useCompanyLogo()

const id = route.params.id as string
const row = ref<any>(null)
const totals = ref<any>(null)
const company = ref<any>(null)
const loading = ref(true)

const load = async () => {
  loading.value = true
  const { data } = await client.from('company_tax_computations')
    .select('*, company_tax_adjustment_lines(id, adj_type, description, amount)')
    .eq('id', id).single()
  row.value = data
  if (data) {
    const { data: t } = await client.from('v_tax_computation_totals').select('*').eq('computation_id', id).maybeSingle()
    totals.value = t
    const { data: c } = await client.from('companies').select('*').eq('id', (data as any).company_id).single()
    company.value = c
  }
  loading.value = false
  if (route.query.auto) setTimeout(() => window.print(), 600)
}
onMounted(load)

const taxable = computed(() => totals.value?.taxable_income ?? row.value?.net_profit_per_accounts ?? 0)
const taxPayable = computed(() => Math.max(0, taxable.value) * Number(row.value?.tax_rate_pct ?? 0) / 100)
const netPayable = computed(() => taxPayable.value - Number(row.value?.advance_tax_paid ?? 0) - Number(row.value?.tds_credit ?? 0))
const addbacks = computed(() => (row.value?.company_tax_adjustment_lines ?? []).filter((l: any) => l.adj_type === 'addback'))
const deductions = computed(() => (row.value?.company_tax_adjustment_lines ?? []).filter((l: any) => l.adj_type === 'deduction'))
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink to="/admin/tax/corporate" class="back">← back</NuxtLink>
      <button class="print-btn" @click="() => window.print()">🖨 Print</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">Loading…</div>

    <div v-else-if="row && company" class="sheet">
      <div class="disclaimer-band">
        DRAFT WORKING PAPER — NOT A FILED TAX RETURN. Review with a registered tax practitioner / chartered accountant before submission to NBR.
      </div>

      <div class="letterhead">
        <img v-if="logoUrl(company)" :src="logoUrl(company)" class="co-logo" alt="Company logo">
        <div class="co-name">{{ company.legal_name || company.name }}</div>
        <div class="title">CORPORATE TAX COMPUTATION — ASSESSMENT YEAR {{ row.assessment_year }}</div>
      </div>

      <table class="calc">
        <tbody>
          <tr class="section"><td>Net profit per accounts</td><td class="num">{{ money(row.net_profit_per_accounts) }}</td></tr>

          <tr class="subsection"><td colspan="2">Add: Inadmissible expenses / addbacks</td></tr>
          <tr v-for="l in addbacks" :key="l.id" class="detail"><td>{{ l.description }}</td><td class="num">{{ money(l.amount) }}</td></tr>
          <tr v-if="!addbacks.length" class="detail"><td colspan="2">— none —</td></tr>

          <tr class="subsection"><td colspan="2">Less: Allowable deductions</td></tr>
          <tr v-for="l in deductions" :key="l.id" class="detail"><td>{{ l.description }}</td><td class="num">({{ money(l.amount) }})</td></tr>
          <tr v-if="!deductions.length" class="detail"><td colspan="2">— none —</td></tr>

          <tr class="subtotal"><td>Taxable income</td><td class="num">{{ money(taxable) }}</td></tr>
          <tr class="section"><td>Tax @ {{ row.tax_rate_pct }}%</td><td class="num">{{ money(taxPayable) }}</td></tr>
          <tr class="detail"><td>Less: Advance income tax (AIT) paid</td><td class="num">({{ money(row.advance_tax_paid) }})</td></tr>
          <tr class="detail"><td>Less: TDS credit</td><td class="num">({{ money(row.tds_credit) }})</td></tr>
          <tr class="total"><td>Net tax payable / (refundable)</td><td class="num">{{ money(netPayable) }}</td></tr>
        </tbody>
      </table>

      <p v-if="row.notes" class="small notes">Notes: {{ row.notes }}</p>

      <div class="sig-block">
        <p>Prepared by,</p>
        <div class="sig-line" />
        <p class="small">Accounts Department — {{ company.legal_name || company.name }}</p>
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
  width: 210mm; min-height: 200mm; margin: 0 auto 20px; background: #fff; color: #111;
  padding: 16mm 18mm 20mm; box-shadow: 0 2px 12px rgba(0,0,0,.4); font-size: 12px; line-height: 1.6;
}
.disclaimer-band {
  background: #fef3c7; border: 1px solid #d97706; color: #78350f; font-weight: 700; font-size: 10.5px;
  text-align: center; padding: 6px 10px; margin-bottom: 14px; letter-spacing: 0.3px;
}
.letterhead { text-align: center; border-bottom: 2px solid #111; padding-bottom: 10px; margin-bottom: 18px; }
.co-logo { max-height: 48px; max-width: 220px; margin: 0 auto 6px; display: block; object-fit: contain; }
.co-name { font-size: 20px; font-weight: 700; letter-spacing: 1px; }
.title { margin-top: 8px; font-size: 12.5px; font-weight: 700; letter-spacing: 0.5px; }
.small { font-size: 11px; color: #333; }
table.calc { width: 100%; border-collapse: collapse; margin: 16px 0; }
table.calc td { padding: 3px 4px; }
table.calc .num { text-align: right; font-family: 'JetBrains Mono', monospace; }
tr.section td { font-weight: 700; padding-top: 10px; }
tr.subsection td { font-weight: 600; padding-top: 8px; color: #444; font-size: 11px; }
tr.detail td { font-size: 11px; color: #444; padding-left: 16px; }
tr.subtotal td { font-weight: 700; border-top: 1px solid #111; padding-top: 8px; }
tr.total td { font-weight: 700; font-size: 15px; border-top: 2px solid #111; padding-top: 10px; }
.notes { margin-top: 16px; }
.sig-block { margin-top: 40px; }
.sig-line { border-top: 1px solid #111; width: 200px; margin: 46px 0 4px; }
@media print {
  .no-print { display: none !important; }
  .print-root { background: #fff; padding: 0; }
  .sheet { box-shadow: none; margin: 0; min-height: auto; }
}
</style>
