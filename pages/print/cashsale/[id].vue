<script setup lang="ts">
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()
const { money } = useFmt()
const { takaWords } = useTakaWords()
const { logoUrl } = useCompanyLogo()

const id = route.params.id as string
const sale = ref<any>(null)
const company = ref<any>(null)
const loading = ref(true)

const load = async () => {
  loading.value = true
  const { data } = await client.from('cash_sales')
    .select('*, parties(name, address), cash_bank_accounts(name), cash_sale_lines(id, qty, unit_price, items(sku, name))')
    .eq('id', id).single()
  sale.value = data
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

const subtotal = computed(() => (sale.value?.cash_sale_lines ?? []).reduce((s: number, l: any) => s + Number(l.qty) * Number(l.unit_price), 0))
const vatAmount = computed(() => sale.value?.vat_applicable ? subtotal.value * Number(sale.value.vat_rate) / 100 : 0)
const total = computed(() => subtotal.value + vatAmount.value)
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink to="/accounting/cash-sales" class="back">← back</NuxtLink>
      <button class="print-btn" @click="() => window.print()">🖨 Print</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">Loading…</div>

    <div v-else-if="sale && company" class="sheet">
      <div class="letterhead">
        <img v-if="logoUrl(company)" :src="logoUrl(company)" class="co-logo" alt="Company logo">
        <div class="co-name">{{ company.legal_name || company.name }}</div>
        <div class="small">{{ company.address || '' }}</div>
        <div class="title">CASH SALE RECEIPT</div>
      </div>

      <div class="row spread ref-row">
        <div>Receipt No: <b class="mono">{{ sale.sale_no }}</b></div>
        <div>Date: <b>{{ fmtDate(sale.sale_date) }}</b></div>
      </div>

      <div class="row spread ref-row">
        <div>Received from: <b>{{ sale.parties?.name || sale.customer_name || 'Walk-in customer' }}</b></div>
        <div>Received into: <b>{{ sale.cash_bank_accounts?.name }}</b></div>
      </div>

      <table class="lines">
        <thead>
          <tr><th>#</th><th>Item</th><th class="num">Qty</th><th class="num">Unit price (৳)</th><th class="num">Amount (৳)</th></tr>
        </thead>
        <tbody>
          <tr v-for="(l, idx) in sale.cash_sale_lines" :key="l.id">
            <td>{{ idx + 1 }}</td>
            <td>{{ l.items?.sku }} — {{ l.items?.name }}</td>
            <td class="num">{{ l.qty }}</td>
            <td class="num">{{ Number(l.unit_price).toLocaleString('en-IN') }}</td>
            <td class="num">{{ (l.qty * l.unit_price).toLocaleString('en-IN') }}</td>
          </tr>
        </tbody>
        <tfoot>
          <tr><td colspan="4" class="num">Subtotal</td><td class="num">{{ money(subtotal) }}</td></tr>
          <tr v-if="sale.vat_applicable"><td colspan="4" class="num">VAT ({{ sale.vat_rate }}%)</td><td class="num">{{ money(vatAmount) }}</td></tr>
          <tr class="total-row"><td colspan="4" class="num">Total</td><td class="num">{{ money(total) }}</td></tr>
        </tfoot>
      </table>

      <p class="small words">In words: {{ takaWords(total) }}</p>

      <div class="sig-block">
        <p>Received by,</p>
        <div class="sig-line" />
        <p><b>For {{ company.legal_name || company.name }}</b></p>
        <p class="small">Authorised Signature</p>
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
  width: 210mm; min-height: 200mm; margin: 0 auto 20px; background: #fff; color: #111;
  padding: 20mm 18mm; box-shadow: 0 2px 12px rgba(0,0,0,.4); font-size: 13px; line-height: 1.7;
}
.letterhead { text-align: center; border-bottom: 2px solid #111; padding-bottom: 10px; margin-bottom: 18px; }
.co-logo { max-height: 48px; max-width: 220px; margin: 0 auto 6px; display: block; object-fit: contain; }
.co-name { font-size: 20px; font-weight: 700; letter-spacing: 1px; }
.small { font-size: 11px; color: #333; }
.title { margin-top: 8px; font-size: 14px; font-weight: 700; letter-spacing: 2px; }
.mono { font-family: 'JetBrains Mono', monospace; font-size: 12px; }
.row { display: flex; }
.spread { justify-content: space-between; }
.ref-row { margin-bottom: 10px; }
table.lines { width: 100%; border-collapse: collapse; margin: 18px 0 8px; }
table.lines th, table.lines td { border: 1px solid #444; padding: 6px 8px; }
table.lines thead th { background: #f4f4f5; text-align: left; }
table.lines .num { text-align: right; font-family: 'JetBrains Mono', monospace; }
.total-row td { font-weight: 700; border-top: 2px solid #111; }
.words { margin-top: 4px; font-style: italic; }
.sig-block { margin-top: 40px; }
.sig-line { border-top: 1px solid #111; width: 200px; margin: 46px 0 4px; }
@media print {
  .no-print { display: none !important; }
  .print-root { background: #fff; padding: 0; }
  .sheet { box-shadow: none; margin: 0; min-height: auto; }
}
</style>
