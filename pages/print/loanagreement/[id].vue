<script setup lang="ts">
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()
const { money } = useFmt()
const { takaWords } = useTakaWords()
const { logoUrl } = useCompanyLogo()
const { locale: printLocale, t, toggle: toggleLang } = usePrintLocale()

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

const introText = computed(() => loan.value && company.value ? t('printHr.loanagreement.intro', {
  company: company.value.legal_name || company.value.name,
  name: loan.value.employees?.full_name,
  empNo: loan.value.employees?.emp_no,
  designation: loan.value.employees?.designation || '—'
}) : '')
const term1Text = computed(() => loan.value ? t('printHr.loanagreement.term1', { principal: money(loan.value.principal) }) : '')
const term2Text = computed(() => loan.value ? t('printHr.loanagreement.term2', { installment: money(loan.value.monthly_installment) }) : '')
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink :to="`/hr/${loan?.employee_id}`" class="back">{{ t('printHr.loanagreement.back') }}</NuxtLink>
      <button class="lang-btn" @click="toggleLang">{{ t('print.toolbar.lang_toggle') }}</button>
      <button class="print-btn" @click="() => window.print()">{{ t('print.toolbar.print_btn') }}</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">{{ t('print.toolbar.loading') }}</div>

    <div v-else-if="loan && company" class="sheet" :lang="printLocale">
      <div class="letterhead">
        <img v-if="logoUrl(company)" :src="logoUrl(company)" class="co-logo" alt="Company logo">
        <div class="co-name">{{ company.legal_name || company.name }}</div>
        <div class="title">{{ t('printHr.loanagreement.title') }}</div>
      </div>

      <div class="row spread ref-row">
        <div>{{ t('printHr.loanagreement.loan_ref_label') }} <b class="mono">{{ loan.loan_no }}</b></div>
        <div>{{ t('printHr.loanagreement.date_label') }} <b>{{ fmtDate(loan.disbursed_at) }}</b></div>
      </div>

      <p class="body-text">{{ introText }}</p>

      <table class="meta">
        <tbody>
          <tr>
            <td><div class="small">{{ t('printHr.loanagreement.principal_amount_label') }}</div><b class="mono">{{ money(loan.principal) }}</b></td>
            <td><div class="small">{{ t('printHr.loanagreement.monthly_installment_label') }}</div><b class="mono">{{ money(loan.monthly_installment) }}</b></td>
            <td><div class="small">{{ t('printHr.loanagreement.repayment_tenure_label') }}</div><b>{{ tenureMonths }} {{ t('printHr.loanagreement.months_suffix') }}</b></td>
          </tr>
        </tbody>
      </table>
      <p class="small words">{{ t('printHr.loanagreement.principal_in_words', { words: takaWords(loan.principal) }) }}</p>

      <ol class="terms">
        <li>{{ term1Text }}</li>
        <li>{{ term2Text }}</li>
        <li>{{ t('printHr.loanagreement.term3') }}</li>
        <li>{{ t('printHr.loanagreement.term4') }}</li>
        <li>{{ t('printHr.loanagreement.term5') }}</li>
      </ol>

      <div class="sig-cols">
        <div class="sig-block">
          <div class="sig-line" />
          <p class="small">{{ t('printHr.loanagreement.employee_sig_label', { name: loan.employees?.full_name }) }}</p>
        </div>
        <div class="sig-block">
          <div class="sig-line" />
          <p class="small">{{ t('printHr.loanagreement.for_company_sig_label', { company: company.legal_name || company.name }) }}</p>
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
.lang-btn { background: transparent; color: #e4e4e7; border: 1px solid #52525b; border-radius: 4px; padding: 5px 14px; font-weight: 500; cursor: pointer; }
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
