<script setup lang="ts">
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()
const { money } = useFmt()
const { logoUrl } = useCompanyLogo()

const company = ref<any>(null)
const summary = ref<any>(null)
const entries = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [{ data: s }, { data: e }] = await Promise.all([
    client.from('v_ait_summary').select('*').maybeSingle(),
    client.from('bank_charge_entries').select('*, cash_bank_accounts(name)').eq('category', 'ait_deducted').order('entry_date', { ascending: true })
  ])
  summary.value = s
  entries.value = e ?? []
  const companyId = (s as any)?.company_id ?? (e as any)?.[0]?.company_id
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

const fmtDate = (d?: string) => d
  ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' })
  : '—'
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink to="/accounting/ait-summary" class="back">← back</NuxtLink>
      <button class="print-btn" @click="() => window.print()">🖨 Print</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">Loading…</div>

    <div v-else class="sheet">
      <div class="letterhead">
        <img v-if="company && logoUrl(company)" :src="logoUrl(company)" class="co-logo" alt="Company logo">
        <div class="co-name">{{ company?.legal_name || company?.name }}</div>
        <div class="title">ADVANCE INCOME TAX (AIT) SUMMARY</div>
      </div>

      <table class="meta">
        <tbody>
          <tr>
            <td><div class="small">Advance income tax paid</div><b>{{ money(summary?.advance_tax_paid ?? 0) }}</b></td>
            <td><div class="small">TDS withheld payable</div><b>{{ money(summary?.tds_withheld_payable ?? 0) }}</b></td>
          </tr>
        </tbody>
      </table>

      <table class="lines">
        <thead><tr><th>Date</th><th>Voucher</th><th>Account</th><th>Description</th><th>Reference</th><th class="num">Amount (৳)</th></tr></thead>
        <tbody>
          <tr v-for="r in entries" :key="r.id">
            <td>{{ fmtDate(r.entry_date) }}</td><td>{{ r.entry_no }}</td><td>{{ r.cash_bank_accounts?.name }}</td>
            <td>{{ r.description }}</td><td>{{ r.reference_no }}</td><td class="num">{{ Number(r.amount).toLocaleString('en-IN') }}</td>
          </tr>
        </tbody>
      </table>

      <p class="small disclaimer">Working paper only — cross-check against original AIT/TDS certificates before tax return filing.</p>
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
.small { font-size: 11px; color: #333; }
table.meta { width: 100%; border-collapse: collapse; margin: 14px 0; }
table.meta td { border: 1px solid #444; padding: 6px 8px; }
table.lines { width: 100%; border-collapse: collapse; margin: 16px 0; }
table.lines th, table.lines td { border: 1px solid #ccc; padding: 4px 8px; }
table.lines thead th { background: #f4f4f5; text-align: left; }
table.lines .num { text-align: right; font-family: 'JetBrains Mono', monospace; }
.disclaimer { margin-top: 20px; font-style: italic; }
@media print {
  .no-print { display: none !important; }
  .print-root { background: #fff; padding: 0; }
  .sheet { box-shadow: none; margin: 0; min-height: auto; }
}
</style>
