<script setup lang="ts">
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()
const { logoUrl } = useCompanyLogo()

const id = route.params.id as string
const acr = ref<any>(null)
const emp = ref<any>(null)
const company = ref<any>(null)
const loading = ref(true)

const gradeLabel: Record<string, string> = {
  outstanding: 'Outstanding', very_good: 'Very Good', good: 'Good', satisfactory: 'Satisfactory', poor: 'Poor'
}

const load = async () => {
  loading.value = true
  const { data } = await client.from('employee_acr').select('*, employees(emp_no, full_name, designation, department, joining_date, company_id)').eq('id', id).single()
  acr.value = data
  emp.value = (data as any)?.employees
  if (emp.value) {
    const { data: c } = await client.from('companies').select('*').eq('id', emp.value.company_id).single()
    company.value = c
  }
  loading.value = false
  if (route.query.auto) setTimeout(() => window.print(), 600)
}
onMounted(load)

const ratings = computed(() => acr.value ? [
  { label: 'Job knowledge', value: acr.value.job_knowledge_rating },
  { label: 'Quality of work', value: acr.value.quality_of_work_rating },
  { label: 'Integrity', value: acr.value.integrity_rating },
  { label: 'Punctuality & attendance', value: acr.value.punctuality_rating },
  { label: 'Initiative', value: acr.value.initiative_rating }
] : [])
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink :to="`/hr/${acr?.employee_id}`" class="back">← back</NuxtLink>
      <button class="print-btn" @click="() => window.print()">🖨 Print</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">Loading…</div>

    <div v-else-if="acr && emp && company" class="sheet">
      <div class="letterhead">
        <img v-if="logoUrl(company)" :src="logoUrl(company)" class="co-logo" alt="Company logo">
        <div class="co-name">{{ company.legal_name || company.name }}</div>
        <div class="title">ANNUAL CONFIDENTIAL REPORT — {{ acr.review_year }}</div>
        <div v-if="acr.status === 'draft'" class="draft-badge">DRAFT — NOT YET FINALIZED</div>
      </div>

      <table class="meta">
        <tbody>
          <tr>
            <td><div class="small">Employee</div><b>{{ emp.emp_no }} — {{ emp.full_name }}</b></td>
            <td><div class="small">Designation</div><b>{{ emp.designation || '—' }}</b></td>
            <td><div class="small">Department</div><b>{{ emp.department || '—' }}</b></td>
          </tr>
          <tr>
            <td colspan="2"><div class="small">Reviewing officer</div><b>{{ acr.reviewing_officer || '—' }}</b></td>
            <td><div class="small">Review year</div><b class="mono">{{ acr.review_year }}</b></td>
          </tr>
        </tbody>
      </table>

      <table class="lines">
        <thead><tr><th>Assessment area</th><th class="num">Rating (1-5)</th></tr></thead>
        <tbody>
          <tr v-for="r in ratings" :key="r.label"><td>{{ r.label }}</td><td class="num">{{ r.value ?? '—' }}</td></tr>
        </tbody>
      </table>

      <p class="section-label">Overall grade</p>
      <p class="grade">{{ gradeLabel[acr.overall_grade] }}</p>

      <p class="section-label">Strengths</p>
      <p class="body-text">{{ acr.strengths || '—' }}</p>

      <p class="section-label">Areas of improvement</p>
      <p class="body-text">{{ acr.areas_of_improvement || '—' }}</p>

      <p class="section-label">Reporting officer's remarks</p>
      <p class="body-text">{{ acr.reporting_officer_remarks || '—' }}</p>

      <p class="section-label">Employee's remarks (right of reply)</p>
      <p class="body-text">{{ acr.employee_remarks || '—' }}</p>

      <div class="sig-cols">
        <div class="sig-block">
          <div class="sig-line" />
          <p class="small">Employee acknowledgment</p>
        </div>
        <div class="sig-block">
          <div class="sig-line" />
          <p class="small">Reporting officer — {{ acr.reviewing_officer || '' }}</p>
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
  padding: 20mm 18mm; box-shadow: 0 2px 12px rgba(0,0,0,.4); font-size: 13px; line-height: 1.6;
}
.letterhead { text-align: center; border-bottom: 2px solid #111; padding-bottom: 10px; margin-bottom: 18px; }
.co-logo { max-height: 48px; max-width: 220px; margin: 0 auto 6px; display: block; object-fit: contain; }
.co-name { font-size: 20px; font-weight: 700; letter-spacing: 1px; }
.title { margin-top: 8px; font-size: 13px; font-weight: 700; letter-spacing: 1px; }
.draft-badge { margin-top: 8px; display: inline-block; background: #fef3c7; border: 1px solid #d97706; color: #78350f; font-weight: 700; font-size: 10px; padding: 3px 10px; letter-spacing: 0.5px; }
.small { font-size: 11px; color: #333; }
.mono { font-family: 'JetBrains Mono', monospace; font-size: 12px; }
table.meta { width: 100%; border-collapse: collapse; margin: 14px 0; }
table.meta td { border: 1px solid #444; padding: 6px 8px; vertical-align: top; }
table.lines { width: 100%; border-collapse: collapse; margin: 14px 0; }
table.lines th, table.lines td { border: 1px solid #ccc; padding: 5px 8px; text-align: left; }
table.lines thead th { background: #f4f4f5; }
table.lines .num { text-align: right; font-family: 'JetBrains Mono', monospace; }
.section-label { font-weight: 700; margin: 14px 0 2px; font-size: 11.5px; text-transform: uppercase; letter-spacing: 0.5px; color: #444; }
.grade { font-size: 16px; font-weight: 700; }
.body-text { text-align: justify; margin: 0 0 4px; }
.sig-cols { display: flex; justify-content: space-between; margin-top: 40px; gap: 40px; }
.sig-block { flex: 1; }
.sig-line { border-top: 1px solid #111; margin: 46px 0 4px; }
@media print {
  .no-print { display: none !important; }
  .print-root { background: #fff; padding: 0; }
  .sheet { box-shadow: none; margin: 0; min-height: auto; }
}
</style>
