<script setup lang="ts">
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()
const { money } = useFmt()
const { takaWords } = useTakaWords()
const { logoUrl } = useCompanyLogo()

const id = route.params.id as string
const loan = ref<any>(null)
const company = ref<any>(null)
const loading = ref(true)

const load = async () => {
  loading.value = true
  const { data } = await client.from('employee_loans').select('*, employees(emp_no, full_name, designation, nid_no, joining_date, company_id)').eq('id', id).single()
  loan.value = data
  if (data) {
    const { data: c } = await client.from('companies').select('*').eq('id', (data as any).employees.company_id).single()
    company.value = c
  }
  loading.value = false
  if (route.query.auto) setTimeout(() => window.print(), 600)
}
onMounted(load)

const fmtDate = (d?: string) => d
  ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' })
  : '—'
const tenureMonths = computed(() => loan.value && Number(loan.value.monthly_installment) > 0
  ? Math.ceil(Number(loan.value.principal) / Number(loan.value.monthly_installment)) : 0)
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink :to="`/hr/${loan?.employee_id}`" class="back">← back</NuxtLink>
      <button class="print-btn" @click="() => window.print()">🖨 Print</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">Loading…</div>

    <div v-else-if="loan && company" class="sheet">
      <div class="letterhead">
        <img v-if="logoUrl(company)" :src="logoUrl(company)" class="co-logo" alt="Company logo">
        <div class="co-name">{{ company.legal_name || company.name }}</div>
        <div class="title">STAFF LOAN AGREEMENT</div>
      </div>

      <div class="row spread ref-row">
        <div>Loan Ref: <b class="mono">{{ loan.loan_no }}</b></div>
        <div>Date: <b>{{ fmtDate(loan.disbursed_at) }}</b></div>
      </div>

      <p class="body-text">
        This agreement is made between <b>{{ company.legal_name || company.name }}</b> ("the Company") and
        <b>{{ loan.employees?.full_name }}</b>, Employee ID <b class="mono">{{ loan.employees?.emp_no }}</b>,
        holding the position of {{ loan.employees?.designation || '—' }} ("the Employee"), for a staff loan on the following terms:
      </p>

      <table class="meta">
        <tbody>
          <tr>
            <td><div class="small">Principal amount</div><b class="mono">{{ money(loan.principal) }}</b></td>
            <td><div class="small">Monthly installment</div><b class="mono">{{ money(loan.monthly_installment) }}</b></td>
            <td><div class="small">Repayment tenure</div><b>{{ tenureMonths }} month(s)</b></td>
          </tr>
        </tbody>
      </table>
      <p class="small words">Principal in words: {{ takaWords(loan.principal) }}</p>

      <ol class="terms">
        <li>The Company shall disburse <b>{{ money(loan.principal) }}</b> to the Employee as an interest-free staff loan.</li>
        <li>The Employee agrees to repay the loan through monthly deductions of <b>{{ money(loan.monthly_installment) }}</b> from salary, commencing the payroll cycle immediately following disbursement, until the full principal is recovered.</li>
        <li>Should the Employee's service with the Company terminate for any reason before the loan is fully repaid, the outstanding balance shall become immediately due and shall be recovered from any final settlement (salary, gratuity, or other dues) payable to the Employee.</li>
        <li>This loan is granted at the sole discretion of the Company as a staff welfare measure and does not constitute a precedent or entitlement for future loans.</li>
        <li>Both parties acknowledge and agree to the terms set out above by their signatures below.</li>
      </ol>

      <div class="sig-cols">
        <div class="sig-block">
          <div class="sig-line" />
          <p class="small">Employee — {{ loan.employees?.full_name }}</p>
        </div>
        <div class="sig-block">
          <div class="sig-line" />
          <p class="small">For {{ company.legal_name || company.name }} — Authorised Signature</p>
        </div>
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
  padding: 20mm 18mm; box-shadow: 0 2px 12px rgba(0,0,0,.4); font-size: 13px; line-height: 1.7;
}
.letterhead { text-align: center; border-bottom: 2px solid #111; padding-bottom: 10px; margin-bottom: 18px; }
.co-logo { max-height: 48px; max-width: 220px; margin: 0 auto 6px; display: block; object-fit: contain; }
.co-name { font-size: 20px; font-weight: 700; letter-spacing: 1px; }
.title { margin-top: 8px; font-size: 14px; font-weight: 700; letter-spacing: 2px; }
.small { font-size: 11px; color: #333; }
.mono { font-family: 'JetBrains Mono', monospace; font-size: 12px; }
.row { display: flex; }
.spread { justify-content: space-between; }
.ref-row { margin-bottom: 18px; }
.body-text { text-align: justify; margin: 12px 0; }
table.meta { width: 100%; border-collapse: collapse; margin: 14px 0; }
table.meta td { border: 1px solid #444; padding: 6px 8px; vertical-align: top; }
.words { font-style: italic; margin-bottom: 14px; }
.terms { padding-left: 20px; margin: 16px 0; }
.terms li { margin-bottom: 10px; text-align: justify; }
.sig-cols { display: flex; justify-content: space-between; margin-top: 40px; gap: 40px; }
.sig-block { flex: 1; }
.sig-line { border-top: 1px solid #111; margin: 46px 0 4px; }
@media print {
  .no-print { display: none !important; }
  .print-root { background: #fff; padding: 0; }
  .sheet { box-shadow: none; margin: 0; min-height: auto; }
}
</style>
