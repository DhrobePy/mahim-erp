<script setup lang="ts">
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()

const id = route.params.id as string
const letter = ref<any>(null)
const company = ref<any>(null)
const loading = ref(true)

const load = async () => {
  loading.value = true
  const { data } = await client.from('forwarding_letters').select('*').eq('id', id).single()
  letter.value = data
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
      <NuxtLink to="/admin/forwarding" class="back">← back</NuxtLink>
      <button class="print-btn" @click="() => window.print()">🖨 Print</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">Loading…</div>

    <div v-else-if="letter && company" class="sheet">
      <div class="letterhead">
        <div class="co-name">{{ company.legal_name || company.name }}</div>
        <div class="small">{{ company.address || '' }}</div>
        <div class="small">{{ company.phone ? 'Tel: ' + company.phone : '' }}{{ company.email ? ' · ' + company.email : '' }}</div>
      </div>

      <div class="row spread ref-row">
        <div>Ref: <b class="mono">{{ letter.letter_no }}</b></div>
        <div>Date: <b>{{ fmtDate(letter.letter_date) }}</b></div>
      </div>

      <div class="to-block">
        <div>To,</div>
        <div><b>{{ letter.to_name }}</b></div>
        <div v-if="letter.to_address">{{ letter.to_address }}</div>
      </div>

      <p class="subject"><b>Subject: {{ letter.subject }}</b></p>

      <p class="body-text">Dear Sir / Madam,</p>
      <p class="body-text">{{ letter.body || 'Please find enclosed the following documents for your kind perusal and necessary action.' }}</p>

      <div v-if="letter.enclosures" class="enclosures">
        <p class="small"><b>Enclosures:</b></p>
        <ol>
          <li v-for="(e, i) in letter.enclosures.split(',').map((s: string) => s.trim()).filter(Boolean)" :key="i">{{ e }}</li>
        </ol>
      </div>

      <p class="body-text">Thanking you.</p>

      <div class="sig-block">
        <p>Yours faithfully,</p>
        <div class="sig-line" />
        <p><b>For {{ company.legal_name || company.name }}</b></p>
        <p class="small">Authorised Signature</p>
      </div>

      <p v-if="letter.cc" class="small cc">CC: {{ letter.cc }}</p>
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
.co-name { font-size: 20px; font-weight: 700; letter-spacing: 1px; }
.small { font-size: 11px; color: #333; }
.mono { font-family: 'JetBrains Mono', monospace; font-size: 12px; }
.row { display: flex; }
.spread { justify-content: space-between; }
.ref-row { margin-bottom: 18px; }
.to-block { margin-bottom: 16px; }
.subject { margin: 16px 0; text-decoration: underline; }
.body-text { text-align: justify; margin: 10px 0; }
.enclosures { margin: 14px 0; }
.enclosures ol { margin: 4px 0 0 18px; padding: 0; }
.sig-block { margin-top: 50px; }
.sig-line { border-top: 1px solid #111; width: 200px; margin: 46px 0 4px; }
.cc { margin-top: 30px; }
@media print {
  .no-print { display: none !important; }
  .print-root { background: #fff; padding: 0; }
  .sheet { box-shadow: none; margin: 0; min-height: auto; }
}
</style>
