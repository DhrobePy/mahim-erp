<script setup lang="ts">
// RJSC Form XII — Particulars of Directors, Managers etc. Draft
// preparation aid built from the Directors & Partners register;
// verify against the current RJSC-prescribed form before filing.
definePageMeta({ layout: false })

const client = useSupabaseClient()
const { activeCompanyId, load: loadProfile } = useProfile()

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

const designationLabel: Record<string, string> = {
  chairman: 'Chairman', managing_director: 'Managing Director', director: 'Director',
  partner: 'Partner', company_secretary: 'Company Secretary'
}
const fmtDate = (d?: string) => d
  ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' })
  : '—'
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink to="/admin/directors" class="back">← back</NuxtLink>
      <button class="print-btn" @click="() => window.print()">🖨 Print</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">Loading…</div>

    <div v-else-if="company" class="sheet">
      <p class="form-tag">FORM XII</p>
      <p class="form-tag small">[The Companies Act, 1994 — Section 115(1)]</p>
      <div class="doc-title">PARTICULARS OF DIRECTORS, MANAGER AND MANAGING AGENTS<br>AND OF ANY CHANGE THEREIN</div>

      <table class="meta">
        <tbody>
          <tr>
            <td>
              <div class="small">Name of the Company</div>
              <b>{{ company.legal_name || company.name }}</b>
            </td>
            <td>
              <div class="small">Registered Address</div>
              {{ company.address || '—' }}
            </td>
          </tr>
        </tbody>
      </table>

      <table class="lines">
        <thead>
          <tr>
            <th style="width: 24px;">SL</th><th>Present Name</th><th>Father's / Spouse's Name</th>
            <th>Designation</th><th>Nationality</th><th>NID No.</th><th>Address</th>
            <th>Date of Appointment</th>
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
          <tr v-if="!directors.length"><td colspan="8" class="small" style="text-align:center;">No active directors recorded.</td></tr>
        </tbody>
      </table>

      <p class="disclaimer">
        Draft prepared from the company's internal register for reference in filing preparation only.
        Verify against the current RJSC-prescribed Form XII and supporting documents before submission.
      </p>

      <div class="row spread sig-block">
        <div class="sig"><div class="sig-line" /><div class="small">Signature of Managing Director / Director</div></div>
        <div class="sig"><div class="sig-line" /><div class="small">Signature of Company Secretary</div></div>
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
