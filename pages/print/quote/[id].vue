<script setup lang="ts">
// Single-sheet print for a Quotation / Proforma Invoice / Sales Contract.
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()
const { num } = useFmt()
const { takaWords } = useTakaWords()

const id = route.params.id as string
const doc = ref<any>(null)
const company = ref<any>(null)
const loading = ref(true)

const { defaultsFor } = useLcClauses()
const clauses = ref<string[]>([])
let saveTimer: any = null
watch(clauses, (v) => {
  clearTimeout(saveTimer)
  saveTimer = setTimeout(async () => {
    await client.from('sales_documents').update({ print_clauses: v } as any).eq('id', id)
  }, 600)
}, { deep: true })

const titleFor: Record<string, string> = { quotation: 'QUOTATION', pi: 'PROFORMA INVOICE', contract: 'SALES CONTRACT' }
const clauseDocFor: Record<string, 'quotation' | 'pi' | 'contract'> = { quotation: 'quotation', pi: 'pi', contract: 'contract' }

const load = async () => {
  loading.value = true
  const { data } = await client.from('sales_documents')
    .select('*, parties(name, address, phone, bin_no), sales_document_lines(id, qty, unit_price, items(sku, name, size_spec))')
    .eq('id', id).single()
  doc.value = data
  if (data) {
    const { data: c } = await client.from('companies').select('*').eq('id', (data as any).company_id).single()
    company.value = c
    const saved = (data as any).print_clauses
    clauses.value = Array.isArray(saved) && saved.length ? saved : defaultsFor(clauseDocFor[(data as any).doc_type])
  }
  loading.value = false
  if (route.query.auto) setTimeout(() => window.print(), 600)
}
onMounted(load)

const total = computed(() =>
  (doc.value?.sales_document_lines ?? []).reduce((s: number, l: any) => s + l.qty * l.unit_price, 0))
const fmtDate = (d?: string) => d
  ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' })
  : '—'
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink :to="`/quotations/${id}`" class="back">← back</NuxtLink>
      <PrintClausePicker v-if="doc" v-model="clauses" :docs="[clauseDocFor[doc.doc_type]]" />
      <button class="print-btn" @click="() => window.print()">🖨 Print</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">Loading…</div>

    <div v-else-if="doc && company" class="sheet">
      <div class="letterhead">
        <div class="co-name">{{ company.legal_name || company.name }}</div>
        <div class="small">{{ company.address || '' }}</div>
        <div class="small">BIN: {{ company.bin_no || '—' }} · TIN: {{ company.tin_no || '—' }}</div>
      </div>
      <div class="doc-title">{{ titleFor[doc.doc_type] }}</div>

      <table class="meta">
        <tbody>
          <tr>
            <td>
              <div class="small">Buyer</div>
              <b>{{ doc.parties?.name }}</b>
              <div class="small">{{ doc.parties?.address || '' }}</div>
              <div class="small">BIN: {{ doc.parties?.bin_no || '—' }}</div>
            </td>
            <td>
              <div>No: <b class="mono">{{ doc.doc_no }}</b></div>
              <div>Date: <b>{{ fmtDate(doc.doc_date) }}</b></div>
              <div>Valid until: <b>{{ fmtDate(doc.valid_until) }}</b></div>
            </td>
            <td>
              <div class="small">Payment terms</div>
              <div>{{ doc.payment_terms || '—' }}</div>
              <div class="small mt">Delivery terms</div>
              <div>{{ doc.delivery_terms || '—' }}</div>
            </td>
          </tr>
        </tbody>
      </table>

      <table class="lines">
        <thead>
          <tr>
            <th style="width: 30px;">SL</th><th>Description of Goods</th>
            <th>Size / Spec</th><th class="right">Quantity (Pcs)</th>
            <th class="right">Unit Price (৳)</th><th class="right">Amount (৳)</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(l, i) in doc.sales_document_lines" :key="l.id">
            <td>{{ i + 1 }}</td>
            <td>{{ l.items?.name }} <span class="small">({{ l.items?.sku }})</span></td>
            <td>{{ l.items?.size_spec || '—' }}</td>
            <td class="right mono">{{ num(l.qty, 0) }}</td>
            <td class="right mono">{{ num(l.unit_price) }}</td>
            <td class="right mono">{{ num(l.qty * l.unit_price) }}</td>
          </tr>
          <tr class="total-row">
            <td colspan="5"><b>TOTAL</b></td>
            <td class="right mono"><b>{{ num(total) }}</b></td>
          </tr>
        </tbody>
      </table>

      <p><b>Amount in words:</b> {{ takaWords(total) }}</p>
      <p v-if="doc.doc_type === 'pi'" class="small">
        This Proforma Invoice is issued for the purpose of opening a Local Letter of Credit in favour of the Beneficiary named above.
      </p>
      <p v-if="doc.notes" class="small">{{ doc.notes }}</p>

      <PrintClauseBlock :selected-keys="clauses" :doc="clauseDocFor[doc.doc_type]" />

      <div class="row spread sig-block">
        <div class="sig"><div class="sig-line" /><div class="small">Accepted by Buyer</div></div>
        <div class="sig">
          <div class="sig-line" />
          <div>For <b>{{ company.legal_name || company.name }}</b></div>
          <div class="small">Authorised Signature</div>
        </div>
      </div>
    </div>

    <div v-else-if="!loading" class="no-print" style="padding: 40px; text-align: center;">Document not found.</div>
  </div>
</template>

<style scoped>
.print-root { min-height: 100vh; background: #3f3f46; padding: 16px 0 48px; font-family: Georgia, 'Times New Roman', serif; }
.toolbar {
  position: sticky; top: 0; z-index: 5; display: flex; gap: 18px; align-items: center; justify-content: center;
  background: #18181b; color: #e4e4e7; padding: 10px; margin: -16px 0 16px;
  font-family: Inter, sans-serif; font-size: 13px;
}
.toolbar .back { color: #fbbf24; text-decoration: none; }
.print-btn { background: #f59e0b; color: #000; border: 0; border-radius: 4px; padding: 6px 16px; font-weight: 600; cursor: pointer; }

.sheet {
  width: 210mm; min-height: 280mm; margin: 0 auto 20px; background: #fff; color: #111;
  padding: 18mm 16mm; box-shadow: 0 2px 12px rgba(0,0,0,.4); font-size: 13px; line-height: 1.55;
}
.doc-title { text-align: center; font-size: 17px; font-weight: 700; letter-spacing: 3px; text-decoration: underline; margin: 8px 0 18px; }
.letterhead { text-align: center; border-bottom: 2px solid #111; padding-bottom: 8px; margin-bottom: 10px; }
.co-name { font-size: 20px; font-weight: 700; letter-spacing: 1px; }
.small { font-size: 11px; color: #333; }
.mt { margin-top: 6px; }
.mono { font-family: 'JetBrains Mono', monospace; font-size: 12px; }
.row { display: flex; }
.spread { justify-content: space-between; }
.right { text-align: right; }
.sig { text-align: center; }
.sig-line { border-top: 1px solid #111; width: 200px; margin: 48px auto 4px; }
.sig-block { margin-top: 60px; }
table.meta { width: 100%; border-collapse: collapse; margin-bottom: 12px; }
table.meta td { border: 1px solid #444; padding: 6px 8px; vertical-align: top; width: 33%; }
table.lines { width: 100%; border-collapse: collapse; margin: 6px 0 12px; }
table.lines th, table.lines td { border: 1px solid #444; padding: 5px 8px; }
table.lines th { background: #f0f0f0; font-size: 11px; text-transform: uppercase; letter-spacing: .5px; }
.total-row td { background: #fafafa; }

@media print {
  .no-print { display: none !important; }
  .print-root { background: #fff; padding: 0; }
  .sheet { box-shadow: none; margin: 0; min-height: auto; }
}
</style>
