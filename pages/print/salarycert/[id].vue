<script setup lang="ts">
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()
const { money } = useFmt()
const { takaWords } = useTakaWords()
const { logoUrl } = useCompanyLogo()

const id = route.params.id as string
const emp = ref<any>(null)
const company = ref<any>(null)
const loading = ref(true)

const load = async () => {
  loading.value = true
  const { data } = await client.from('employees').select('*').eq('id', id).single()
  emp.value = data
  if (data) {
    const { data: c } = await client.from('companies').select('*').eq('id', (data as any).company_id).single()
    company.value = c
  }
  loading.value = false
  if (route.query.auto) setTimeout(() => window.print(), 600)
}
onMounted(load)

const today = new Date().toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' })
const fmtDate = (d?: string) => d
  ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' })
  : '—'
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink :to="`/hr/${id}`" class="back">← back</NuxtLink>
      <button class="print-btn" @click="() => window.print()">🖨 Print</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">Loading…</div>

    <div v-else-if="emp && company" class="sheet">
      <div class="letterhead">
        <img v-if="logoUrl(company)" :src="logoUrl(company)" class="co-logo" alt="Company logo">
        <div class="co-name">{{ company.legal_name || company.name }}</div>
        <div class="small">{{ company.address || '' }}</div>
      </div>

      <div class="row spread ref-row">
        <div>Ref: <b class="mono">SC/{{ emp.emp_no }}/{{ new Date().getFullYear() }}</b></div>
        <div>Date: <b>{{ today }}</b></div>
      </div>

      <p class="subject"><b>TO WHOM IT MAY CONCERN</b></p>

      <p class="body-text">
        This is to certify that <b>{{ emp.full_name }}</b>{{ emp.father_name ? ', son/daughter of ' + emp.father_name + ',' : '' }}
        bearing National ID No. <b class="mono">{{ emp.nid_no || '—' }}</b> and Employee ID <b class="mono">{{ emp.emp_no }}</b>,
        has been employed with {{ company.legal_name || company.name }} as
        <b>{{ emp.designation || '—' }}</b>{{ emp.department ? ' in the ' + emp.department + ' department' : '' }}
        since <b>{{ fmtDate(emp.joining_date) }}</b> and continues to serve in that capacity as of the date of issue of this certificate.
      </p>

      <p class="body-text">
        {{ emp.full_name }} draws a monthly gross salary of <b>{{ money(emp.gross_salary) }}</b>
        ({{ takaWords(emp.gross_salary) }}), comprising a basic salary of {{ money(emp.basic_salary) }} plus allowances.
      </p>

      <p class="body-text">
        This certificate is issued at the request of the employee for whatever purpose it may serve.
      </p>

      <table class="meta">
        <tbody>
          <tr>
            <td><div class="small">Designation</div><b>{{ emp.designation || '—' }}</b></td>
            <td><div class="small">Department</div><b>{{ emp.department || '—' }}</b></td>
            <td><div class="small">Joining date</div><b>{{ fmtDate(emp.joining_date) }}</b></td>
            <td><div class="small">Monthly gross (৳)</div><b class="mono">{{ money(emp.gross_salary) }}</b></td>
          </tr>
        </tbody>
      </table>

      <div class="sig-block">
        <p>Yours faithfully,</p>
        <div class="sig-line" />
        <p><b>For {{ company.legal_name || company.name }}</b></p>
        <p class="small">Authorised Signature — Human Resources</p>
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
.small { font-size: 11px; color: #333; }
.mono { font-family: 'JetBrains Mono', monospace; font-size: 12px; }
.row { display: flex; }
.spread { justify-content: space-between; }
.ref-row { margin-bottom: 18px; }
.subject { margin: 16px 0; text-align: center; text-decoration: underline; }
.body-text { text-align: justify; margin: 12px 0; }
table.meta { width: 100%; border-collapse: collapse; margin: 18px 0; }
table.meta td { border: 1px solid #444; padding: 6px 8px; vertical-align: top; }
.sig-block { margin-top: 40px; }
.sig-line { border-top: 1px solid #111; width: 200px; margin: 46px 0 4px; }
@media print {
  .no-print { display: none !important; }
  .print-root { background: #fff; padding: 0; }
  .sheet { box-shadow: none; margin: 0; min-height: auto; }
}
</style>
