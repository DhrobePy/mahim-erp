<script setup lang="ts">
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()
const { money } = useFmt()
const { logoUrl } = useCompanyLogo()
const { locale: printLocale, t, toggle: toggleLang } = usePrintLocale()

const id = route.params.id as string
const req = ref<any>(null)
const company = ref<any>(null)
const loading = ref(true)

const serviceLabel = computed<Record<string, string>>(() => ({
  lc_issue: t('printTrade.bankrequest.services.lc_issue'),
  document_collection: t('printTrade.bankrequest.services.document_collection'),
  discrepancy: t('printTrade.bankrequest.services.discrepancy'),
  bank_statement: t('printTrade.bankrequest.services.bank_statement'),
  lbpd_issue: t('printTrade.bankrequest.services.lbpd_issue'),
  fdr: t('printTrade.bankrequest.services.fdr'),
  dps: t('printTrade.bankrequest.services.dps'),
  manual: t('printTrade.bankrequest.services.manual')
}))

const load = async () => {
  loading.value = true
  const { data } = await client.from('bank_service_requests')
    .select('*, bank_branches(branch_name, branch_address, parties(name)), board_resolutions(resolution_no, meeting_date)')
    .eq('id', id).single()
  req.value = data
  if (data) {
    const { data: c } = await client.from('companies').select('*').eq('id', (data as any).company_id).single()
    company.value = c
  }
  loading.value = false
  if (route.query.auto) setTimeout(() => window.print(), 600)
}
onMounted(load)

const fmtDate = (d?: string) => d
  ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' })
  : '—'
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink to="/admin/bank-requests" class="back">{{ t('printTrade.bankrequest.back') }}</NuxtLink>
      <button class="lang-btn" @click="toggleLang">{{ t('print.toolbar.lang_toggle') }}</button>
      <button class="print-btn" @click="() => window.print()">{{ t('print.toolbar.print_btn') }}</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">{{ t('print.toolbar.loading') }}</div>

    <div v-else-if="req && company" class="sheet" :lang="printLocale">
      <div class="letterhead">
        <img v-if="logoUrl(company)" :src="logoUrl(company)" class="co-logo" alt="Company logo">
        <div class="co-name">{{ company.legal_name || company.name }}</div>
        <div class="small">{{ company.address || '' }}</div>
      </div>

      <div class="row spread ref-row">
        <div>{{ t('printTrade.bankrequest.ref_label') }} <b class="mono">{{ req.request_no }}</b></div>
        <div>{{ t('printTrade.bankrequest.date_label') }} <b>{{ fmtDate(req.request_date) }}</b></div>
      </div>

      <div class="to-block">
        <div>{{ t('printTrade.bankrequest.to_label') }}</div>
        <div><b>{{ t('printTrade.bankrequest.branch_manager') }}</b></div>
        <div><b>{{ req.bank_branches?.parties?.name }}, {{ req.bank_branches?.branch_name }}</b></div>
        <div v-if="req.bank_branches?.branch_address">{{ req.bank_branches.branch_address }}</div>
      </div>

      <p class="subject"><b>{{ t('printTrade.bankrequest.subject_label', { subject: req.subject }) }}</b></p>

      <p class="body-text">{{ t('printTrade.bankrequest.dear_sir') }}</p>
      <p class="body-text">{{ req.body }}</p>

      <table class="meta">
        <tbody>
          <tr>
            <td><div class="small">{{ t('printTrade.bankrequest.service_label') }}</div><b>{{ serviceLabel[req.service_type] }}</b></td>
            <td v-if="req.reference_no"><div class="small">{{ t('printTrade.bankrequest.reference_label') }}</div><b class="mono">{{ req.reference_no }}</b></td>
            <td v-if="req.service_type === 'bank_statement' && req.statement_period_from">
              <div class="small">{{ t('printTrade.bankrequest.statement_period') }}</div>
              <b>{{ t('printTrade.bankrequest.statement_period_value', { from: fmtDate(req.statement_period_from), to: fmtDate(req.statement_period_to) }) }}</b>
            </td>
            <td v-if="req.amount"><div class="small">{{ t('printTrade.bankrequest.amount_label') }}</div><b class="mono">{{ money(req.amount) }}</b></td>
            <td v-if="req.tenor_or_period"><div class="small">{{ t('printTrade.bankrequest.tenor_period_label') }}</div><b>{{ req.tenor_or_period }}</b></td>
          </tr>
        </tbody>
      </table>

      <p v-if="req.board_resolutions" class="small">
        {{ t('printTrade.bankrequest.resolution_note', { no: req.board_resolutions.resolution_no, date: fmtDate(req.board_resolutions.meeting_date) }) }}
      </p>

      <p class="body-text">{{ t('printTrade.bankrequest.thanking_you') }}</p>

      <div class="sig-block">
        <p>{{ t('printTrade.bankrequest.yours_faithfully') }}</p>
        <div class="sig-line" />
        <p><b>{{ t('printTrade.bankrequest.for_company', { company: company.legal_name || company.name }) }}</b></p>
        <p class="small">{{ t('printTrade.bankrequest.authorised_signature') }}</p>
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
.small { font-size: 11px; color: #333; }
.mono { font-family: 'JetBrains Mono', monospace; font-size: 12px; }
.row { display: flex; }
.spread { justify-content: space-between; }
.ref-row { margin-bottom: 18px; }
.to-block { margin-bottom: 16px; }
.subject { margin: 16px 0; text-decoration: underline; }
.body-text { text-align: justify; margin: 10px 0; }
table.meta { width: 100%; border-collapse: collapse; margin: 14px 0; }
table.meta td { border: 1px solid #444; padding: 6px 8px; vertical-align: top; }
.sig-block { margin-top: 40px; }
.sig-line { border-top: 1px solid #111; width: 200px; margin: 46px 0 4px; }
@media print {
  .no-print { display: none !important; }
  .print-root { background: #fff; padding: 0; }
  .sheet { box-shadow: none; margin: 0; min-height: auto; }
}
</style>
