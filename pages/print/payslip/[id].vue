<script setup lang="ts">
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()
const { money } = useFmt()
const { takaWords } = useTakaWords()
const { logoUrl } = useCompanyLogo()

const id = route.params.id as string
const line = ref<any>(null)
const company = ref<any>(null)
const loading = ref(true)

const load = async () => {
  loading.value = true
  const { data } = await client.from('payroll_lines')
    .select('*, payroll_runs(run_no, label, period_year, period_month, run_type, company_id), employees(emp_no, full_name, designation, department, nid_no)')
    .eq('id', id).single()
  line.value = data
  if (data) {
    const { data: c } = await client.from('companies').select('*').eq('id', (data as any).payroll_runs.company_id).single()
    company.value = c
  }
  loading.value = false
  if (route.query.auto) setTimeout(() => window.print(), 600)
}
onMounted(load)

const monthName = (m: number) => new Date(2000, m - 1, 1).toLocaleDateString('en-GB', { month: 'long' })
const earnings = computed(() => [
  { label: `Gross salary (incl. basic ৳${Number(line.value?.basic ?? 0).toLocaleString('en-IN')})`, amount: Number(line.value?.gross ?? 0) },
  { label: 'Attendance allowance', amount: Number(line.value?.attendance_allowance ?? 0) },
  { label: `Overtime (${line.value?.ot_hours ?? 0}h @ ৳${line.value?.ot_rate ?? 0}/h)`, amount: Number(line.value?.ot_amount ?? 0) }
])
const deductions = computed(() => [
  { label: 'Absence deduction', amount: Number(line.value?.absence_deduction ?? 0) },
  { label: 'Loan recovery', amount: Number(line.value?.loan_recovery ?? 0) }
])
const grossEarnings = computed(() => earnings.value.reduce((s, e) => s + e.amount, 0))
const totalDeductions = computed(() => deductions.value.reduce((s, d) => s + d.amount, 0))
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink :to="`/hr/${line?.employee_id}`" class="back">← back</NuxtLink>
      <button class="print-btn" @click="() => window.print()">🖨 Print</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">Loading…</div>

    <div v-else-if="line && company" class="sheet">
      <div class="letterhead">
        <img v-if="logoUrl(company)" :src="logoUrl(company)" class="co-logo" alt="Company logo">
        <div class="co-name">{{ company.legal_name || company.name }}</div>
        <div class="title">PAYSLIP{{ line.payroll_runs?.run_type === 'festival_bonus' ? ' — FESTIVAL BONUS' : '' }}</div>
        <div class="small">
          {{ line.payroll_runs?.run_type === 'festival_bonus' ? line.payroll_runs?.label : `${monthName(line.payroll_runs?.period_month)} ${line.payroll_runs?.period_year}` }}
          — {{ line.payroll_runs?.run_no }}
        </div>
      </div>

      <table class="meta">
        <tbody>
          <tr>
            <td><div class="small">Employee</div><b>{{ line.employees?.emp_no }} — {{ line.employees?.full_name }}</b></td>
            <td><div class="small">Designation</div><b>{{ line.employees?.designation || '—' }}</b></td>
            <td><div class="small">Department</div><b>{{ line.employees?.department || '—' }}</b></td>
          </tr>
          <tr>
            <td><div class="small">Days present</div><b class="mono">{{ line.days_present }}</b></td>
            <td><div class="small">Days absent</div><b class="mono">{{ line.days_absent }}</b></td>
            <td><div class="small">NID</div><b class="mono">{{ line.employees?.nid_no || '—' }}</b></td>
          </tr>
        </tbody>
      </table>

      <div class="cols">
        <table class="lines">
          <thead><tr><th colspan="2">Earnings</th></tr></thead>
          <tbody>
            <tr v-for="e in earnings" :key="e.label"><td>{{ e.label }}</td><td class="num">{{ money(e.amount) }}</td></tr>
            <tr class="total-row"><td>Gross earnings</td><td class="num">{{ money(grossEarnings) }}</td></tr>
          </tbody>
        </table>
        <table class="lines">
          <thead><tr><th colspan="2">Deductions</th></tr></thead>
          <tbody>
            <tr v-for="d in deductions" :key="d.label"><td>{{ d.label }}</td><td class="num">{{ money(d.amount) }}</td></tr>
            <tr class="total-row"><td>Total deductions</td><td class="num">{{ money(totalDeductions) }}</td></tr>
          </tbody>
        </table>
      </div>

      <table class="lines net-table">
        <tbody><tr class="total-row"><td>Net pay</td><td class="num">{{ money(line.net_pay) }}</td></tr></tbody>
      </table>
      <p class="small words">In words: {{ takaWords(line.net_pay) }}</p>

      <div class="sig-block">
        <p><b>For {{ company.legal_name || company.name }}</b></p>
        <div class="sig-line" />
        <p class="small">Authorised Signature</p>
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
  padding: 20mm 18mm; box-shadow: 0 2px 12px rgba(0,0,0,.4); font-size: 13px; line-height: 1.6;
}
.letterhead { text-align: center; border-bottom: 2px solid #111; padding-bottom: 10px; margin-bottom: 18px; }
.co-logo { max-height: 48px; max-width: 220px; margin: 0 auto 6px; display: block; object-fit: contain; }
.co-name { font-size: 20px; font-weight: 700; letter-spacing: 1px; }
.title { margin-top: 8px; font-size: 14px; font-weight: 700; letter-spacing: 2px; }
.small { font-size: 11px; color: #333; }
.mono { font-family: 'JetBrains Mono', monospace; font-size: 12px; }
table.meta { width: 100%; border-collapse: collapse; margin: 14px 0; }
table.meta td { border: 1px solid #444; padding: 6px 8px; vertical-align: top; }
.cols { display: flex; gap: 16px; margin: 16px 0 0; }
table.lines { width: 100%; border-collapse: collapse; }
table.lines th, table.lines td { border: 1px solid #ccc; padding: 5px 8px; }
table.lines thead th { background: #f4f4f5; text-align: left; }
table.lines .num { text-align: right; font-family: 'JetBrains Mono', monospace; }
tr.total-row td { font-weight: 700; border-top: 2px solid #111; }
.net-table { margin-top: 10px; }
.words { margin-top: 6px; font-style: italic; }
.sig-block { margin-top: 40px; }
.sig-line { border-top: 1px solid #111; width: 200px; margin: 46px 0 4px; }
@media print {
  .no-print { display: none !important; }
  .print-root { background: #fff; padding: 0; }
  .sheet { box-shadow: none; margin: 0; min-height: auto; }
}
</style>
