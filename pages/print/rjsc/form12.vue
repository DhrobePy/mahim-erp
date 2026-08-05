<script setup lang="ts">
// RJSC Form XII — Particulars of Directors, Managers etc. Draft
// preparation aid built from the Directors & Partners register;
// verify against the current RJSC-prescribed form before filing.
definePageMeta({ layout: false })

const client = useSupabaseClient()
const { activeCompanyId, load: loadProfile } = useProfile()
const { locale: printLocale, t, toggle: toggleLang } = usePrintLocale()

const company = ref<any>(null)
const directors = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  if (!activeCompanyId.value) await loadProfile()
  const [{ data: c }, { data: d }] = await Promise.all([
    client.from('companies').select('*').eq('id', activeCompanyId.value).single(),
    client.from('company_directors').select('*').eq('is_active', true).order('appointment_date')
  ])
  company.value = c
  directors.value = d ?? []
  loading.value = false
}
onMounted(load)

const designationLabel = computed<Record<string, string>>(() => ({
  chairman: t('printGov.rjscForm12.designations.chairman'),
  managing_director: t('printGov.rjscForm12.designations.managing_director'),
  director: t('printGov.rjscForm12.designations.director'),
  partner: t('printGov.rjscForm12.designations.partner'),
  company_secretary: t('printGov.rjscForm12.designations.company_secretary')
}))
const fmtDate = (d?: string) => d
  ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' })
  : '—'
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink to="/admin/directors" class="back">{{ t('printGov.rjscForm12.back') }}</NuxtLink>
      <button class="lang-btn" @click="toggleLang">{{ t('print.toolbar.lang_toggle') }}</button>
      <button class="print-btn" @click="() => window.print()">{{ t('print.toolbar.print_btn') }}</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">{{ t('print.toolbar.loading') }}</div>

    <div v-else-if="company" class="sheet" :lang="printLocale">
      <p class="form-tag">{{ t('printGov.rjscForm12.form_tag') }}</p>
      <p class="form-tag small">{{ t('printGov.rjscForm12.act_section') }}</p>
      <div class="doc-title">{{ t('printGov.rjscForm12.doc_title_l1') }}<br>{{ t('printGov.rjscForm12.doc_title_l2') }}</div>

      <table class="meta">
        <tbody>
          <tr>
            <td>
              <div class="small">{{ t('printGov.rjscForm12.name_of_company') }}</div>
              <b>{{ company.legal_name || company.name }}</b>
            </td>
            <td>
              <div class="small">{{ t('printGov.rjscForm12.registered_address') }}</div>
              {{ company.address || '—' }}
            </td>
          </tr>
        </tbody>
      </table>

      <table class="lines">
        <thead>
          <tr>
            <th style="width: 24px;">{{ t('printGov.rjscForm12.col_sl') }}</th><th>{{ t('printGov.rjscForm12.col_present_name') }}</th><th>{{ t('printGov.rjscForm12.col_father_spouse') }}</th>
            <th>{{ t('printGov.rjscForm12.col_designation') }}</th><th>{{ t('printGov.rjscForm12.col_nationality') }}</th><th>{{ t('printGov.rjscForm12.col_nid') }}</th><th>{{ t('printGov.rjscForm12.col_address') }}</th>
            <th>{{ t('printGov.rjscForm12.col_appointment_date') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(d, i) in directors" :key="d.id">
            <td>{{ i + 1 }}</td>
            <td>{{ d.full_name }}</td>
            <td>{{ d.father_or_spouse_name || '—' }}</td>
            <td>{{ designationLabel[d.designation] }}</td>
            <td>{{ d.nationality }}</td>
            <td class="mono">{{ d.nid_no || '—' }}</td>
            <td>{{ d.address || '—' }}</td>
            <td class="mono">{{ fmtDate(d.appointment_date) }}</td>
          </tr>
          <tr v-if="!directors.length"><td colspan="8" class="small" style="text-align:center;">{{ t('printGov.rjscForm12.no_directors') }}</td></tr>
        </tbody>
      </table>

      <p class="disclaimer">
        {{ t('printGov.rjscForm12.disclaimer') }}
      </p>

      <div class="row spread sig-block">
        <div class="sig"><div class="sig-line" /><div class="small">{{ t('printGov.rjscForm12.sig_director') }}</div></div>
        <div class="sig"><div class="sig-line" /><div class="small">{{ t('printGov.rjscForm12.sig_secretary') }}</div></div>
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
  width: 297mm; min-height: 200mm; margin: 0 auto 20px; background: #fff; color: #111;
  padding: 16mm; box-shadow: 0 2px 12px rgba(0,0,0,.4); font-size: 12px; line-height: 1.5;
}
.form-tag { text-align: center; font-weight: 700; letter-spacing: 2px; margin: 0; }
.form-tag.small { font-size: 11px; font-weight: 400; letter-spacing: 0; margin-bottom: 10px; }
.doc-title { text-align: center; font-size: 14px; font-weight: 700; margin: 6px 0 16px; }
.small { font-size: 10.5px; color: #333; }
.mono { font-family: 'JetBrains Mono', monospace; font-size: 11px; }
.row { display: flex; }
.spread { justify-content: space-between; }
table.meta { width: 100%; border-collapse: collapse; margin-bottom: 12px; }
table.meta td { border: 1px solid #444; padding: 6px 8px; vertical-align: top; width: 50%; }
table.lines { width: 100%; border-collapse: collapse; margin: 6px 0 14px; }
table.lines th, table.lines td { border: 1px solid #444; padding: 5px 6px; font-size: 11px; }
table.lines th { background: #f0f0f0; font-size: 10px; text-transform: uppercase; letter-spacing: .3px; }
.disclaimer { font-size: 10px; color: #666; font-style: italic; border-top: 1px dashed #999; padding-top: 8px; margin-top: 10px; }
.sig { text-align: center; }
.sig-line { border-top: 1px solid #111; width: 220px; margin: 48px auto 4px; }
.sig-block { margin-top: 30px; }
@media print {
  .no-print { display: none !important; }
  .print-root { background: #fff; padding: 0; }
  .sheet { box-shadow: none; margin: 0; min-height: auto; }
  @page { size: A4 landscape; }
}
</style>
