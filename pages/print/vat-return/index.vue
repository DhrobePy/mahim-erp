<script setup lang="ts">
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()
const { money } = useFmt()
const { logoUrl } = useCompanyLogo()

const from = (route.query.from as string) || ''
const to = (route.query.to as string) || ''
const company = ref<any>(null)
const rows = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const { data } = await client.from('v_vat_transactions').select('*').order('txn_date', { ascending: true })
  rows.value = data ?? []
  const companyId = (data as any)?.[0]?.company_id
  if (companyId) {
    const { data: c } = await client.from('companies').select('*').eq('id', companyId).single()
    company.value = c
  } else {
    const { data: c } = await client.from('companies').select('*').limit(1).single()
    company.value = c
  }
  loading.value = false
  if (route.query.auto) setTimeout(() => window.print(), 600)
}
onMounted(load)

const filtered = computed(() => rows.value.filter((r) => {
  if (from && r.txn_date < from) return false
  if (to && r.txn_date > to) return false
  return true
}))
const output = computed(() => filtered.value.filter((r) => r.vat_side === 'output'))
const input = computed(() => filtered.value.filter((r) => r.vat_side === 'input'))
const outputTotal = computed(() => output.value.reduce((s, r) => s + Number(r.vat_amount), 0))
const inputTotal = computed(() => input.value.reduce((s, r) => s + Number(r.vat_amount), 0))
const netPayable = computed(() => outputTotal.value - inputTotal.value)

const fmtDate = (d?: string) => d
  ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' })
  : '—'
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink to="/accounting/vat-return" class="back">← back</NuxtLink>
      <button class="print-btn" @click="() => window.print()">🖨 Print</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">Loading…</div>

    <div v-else class="sheet">
      <div class="letterhead">
        <img v-if="company && logoUrl(company)" :src="logoUrl(company)" class="co-logo" alt="Company logo">
        <div class="co-name">{{ company?.legal_name || company?.name }}</div>
        <div class="title">VAT RETURN WORKING PAPER (MUSHAK 9.1 BASIS)</div>
        <div class="small">{{ from ? `${fmtDate(from)} to ${fmtDate(to)}` : 'All-time' }}</div>
      </div>

      <table class="lines">
        <thead><tr><th>Date</th><th>Document</th><th class="num">VAT (৳)</th></tr></thead>
        <tbody>
          <tr class="section-row"><td colspan="3">Output VAT — Mushak 6.3 (domestic cash sales)</td></tr>
          <tr v-for="(r, i) in output" :key="'o'+i"><td>{{ fmtDate(r.txn_date) }}</td><td>{{ r.doc_no }}</td><td class="num">{{ Number(r.vat_amount).toLocaleString('en-IN') }}</td></tr>
          <tr class="subtotal-row"><td colspan="2">Total output VAT</td><td class="num">{{ money(outputTotal) }}</td></tr>

          <tr class="section-row"><td colspan="3">Input VAT credit — Mushak 6.1 (GRNs)</td></tr>
          <tr v-for="(r, i) in input" :key="'i'+i"><td>{{ fmtDate(r.txn_date) }}</td><td>{{ r.doc_no }}</td><td class="num">{{ Number(r.vat_amount).toLocaleString('en-IN') }}</td></tr>
          <tr class="subtotal-row"><td colspan="2">Total input VAT credit</td><td class="num">{{ money(inputTotal) }}</td></tr>

          <tr class="total-row"><td colspan="2">Net VAT payable to NBR</td><td class="num">{{ money(netPayable) }}</td></tr>
        </tbody>
      </table>

      <p class="small disclaimer">Working paper only — reconcile against actual Mushak 6.1/6.3 registers before filing Mushak 9.1.</p>
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
  padding: 20mm 18mm; box-shadow: 0 2px 12px rgba(0,0,0,.4); font-size: 12px; line-height: 1.6;
}
.letterhead { text-align: center; border-bottom: 2px solid #111; padding-bottom: 10px; margin-bottom: 18px; }
.co-logo { max-height: 48px; max-width: 220px; margin: 0 auto 6px; display: block; object-fit: contain; }
.co-name { font-size: 20px; font-weight: 700; letter-spacing: 1px; }
.title { margin-top: 8px; font-size: 13px; font-weight: 700; letter-spacing: 1px; }
.small { font-size: 11px; color: #333; margin-top: 4px; }
table.lines { width: 100%; border-collapse: collapse; margin: 16px 0; }
table.lines th, table.lines td { border: 1px solid #ccc; padding: 4px 8px; }
table.lines thead th { background: #f4f4f5; text-align: left; }
table.lines .num { text-align: right; font-family: 'JetBrains Mono', monospace; }
tr.section-row td { font-weight: 700; background: #fafafa; }
tr.subtotal-row td { font-weight: 700; }
tr.total-row td { font-weight: 700; font-size: 14px; border-top: 2px solid #111; }
.disclaimer { margin-top: 20px; font-style: italic; }
@media print {
  .no-print { display: none !important; }
  .print-root { background: #fff; padding: 0; }
  .sheet { box-shadow: none; margin: 0; min-height: auto; }
}
</style>
