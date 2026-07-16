<script setup lang="ts">
// Standalone Delivery Challan print — works for any challan regardless
// of invoice status, which matters for pre-LC originals: the truck
// needs a signed challan long before an LC or invoice exists.
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()
const { num } = useFmt()

const id = route.params.id as string
const ch = ref<any>(null)
const company = ref<any>(null)
const lines = ref<any[]>([])
const loading = ref(true)

const { defaultsFor } = useLcClauses()
const clauses = ref<string[]>([])
let saveTimer: any = null
watch(clauses, (v) => {
  clearTimeout(saveTimer)
  saveTimer = setTimeout(async () => {
    await client.from('delivery_challans').update({ print_clauses: v } as any).eq('id', id)
  }, 600)
}, { deep: true })

const load = async () => {
  loading.value = true
  const { data: c } = await client.from('delivery_challans')
    .select(`*, parties(name, address, bin_no), lcs(lc_no), sales_orders(so_no),
      covers:covers_challan_id(challan_no)`)
    .eq('id', id).single()
  ch.value = c
  if (c) {
    const [{ data: co }, { data: ln }] = await Promise.all([
      client.from('companies').select('*').eq('id', (c as any).company_id).single(),
      client.from('delivery_challan_lines')
        .select('id, qty, unit_price, items(sku, name, size_spec), batches(batch_no)')
        .eq('challan_id', id)
    ])
    company.value = co
    lines.value = ln ?? []
    const saved = (c as any).print_clauses
    clauses.value = Array.isArray(saved) && saved.length ? saved : defaultsFor('challan')
  }
  loading.value = false
  if (route.query.auto) setTimeout(() => window.print(), 600)
}
onMounted(load)

const totalQty = computed(() => lines.value.reduce((s, l) => s + Number(l.qty), 0))
const fmtDate = (d?: string) => d
  ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' })
  : '—'
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink to="/challans" class="back">← back to challans</NuxtLink>
      <PrintClausePicker v-model="clauses" :docs="['challan']" />
      <button class="print-btn" @click="() => window.print()">🖨 Print</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">Loading…</div>

    <div v-else-if="ch && company" class="sheet">
      <div class="letterhead">
        <div class="co-name">{{ company.legal_name || company.name }}</div>
        <div class="small">{{ company.address || '' }}</div>
      </div>
      <div class="doc-title">
        DELIVERY CHALLAN
        <span v-if="ch.challan_kind === 'covering'" class="kind-tag">(Covering Set{{ ch.covers ? ' — covers ' + ch.covers.challan_no : '' }})</span>
        <span v-else-if="ch.challan_kind === 'original'" class="kind-tag">(Pre-LC Original — internal series)</span>
      </div>

      <table class="meta">
        <tbody>
          <tr>
            <td>
              <div class="small">Consignee / Buyer</div>
              <b>{{ ch.parties?.name }}</b>
              <div class="small">{{ ch.parties?.address || '' }}</div>
            </td>
            <td>
              <div>Challan No: <b class="mono">{{ ch.challan_no }}</b></div>
              <div>Date: <b>{{ fmtDate(ch.document_date) }}</b></div>
              <div v-if="ch.actual_delivery_date !== ch.document_date" class="small">
                Actual delivery: {{ fmtDate(ch.actual_delivery_date) }}
              </div>
              <div v-if="ch.sales_orders">Order Ref: <b class="mono">{{ ch.sales_orders.so_no }}</b></div>
            </td>
            <td>
              <div>L/C No: <b class="mono">{{ ch.lcs?.lc_no ?? 'Not yet assigned' }}</b></div>
              <div>Status: <b>{{ ch.status.replace(/_/g, ' ') }}</b></div>
            </td>
          </tr>
        </tbody>
      </table>

      <table class="lines">
        <thead>
          <tr>
            <th style="width: 30px;">SL</th><th>Description of Goods</th>
            <th>Size / Spec</th><th>Batch / Roll</th><th class="right">Quantity (Pcs)</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(l, i) in lines" :key="l.id">
            <td>{{ i + 1 }}</td>
            <td>{{ l.items?.name }} <span class="small">({{ l.items?.sku }})</span></td>
            <td>{{ l.items?.size_spec || '—' }}</td>
            <td class="mono">{{ l.batches?.batch_no || '—' }}</td>
            <td class="right mono">{{ num(l.qty, 0) }}</td>
          </tr>
          <tr class="total-row">
            <td colspan="4"><b>TOTAL</b></td>
            <td class="right mono"><b>{{ num(totalQty, 0) }}</b></td>
          </tr>
        </tbody>
      </table>

      <table class="meta" style="margin-top: 4px;">
        <tbody>
          <tr>
            <td><div class="small">Vehicle No.</div><div class="cell-line">&nbsp;</div></td>
            <td><div class="small">Driver Name</div><div class="cell-line">&nbsp;</div></td>
            <td><div class="small">Gate Pass No.</div><div class="cell-line">&nbsp;</div></td>
          </tr>
        </tbody>
      </table>

      <PrintClauseBlock :selected-keys="clauses" doc="challan" />

      <div class="row spread sig-block">
        <div class="sig"><div class="sig-line" /><div class="small">Dispatched by</div></div>
        <div class="sig"><div class="sig-line" /><div class="small">Received by (Buyer's Signature &amp; Seal)</div></div>
      </div>
    </div>

    <div v-else-if="!loading" class="no-print" style="padding: 40px; text-align: center;">Challan not found.</div>
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
.kind-tag { display: block; font-size: 11px; letter-spacing: 1px; text-decoration: none; color: #555; margin-top: 2px; }
.letterhead { text-align: center; border-bottom: 2px solid #111; padding-bottom: 8px; margin-bottom: 10px; }
.co-name { font-size: 20px; font-weight: 700; letter-spacing: 1px; }
.small { font-size: 11px; color: #333; }
.mono { font-family: 'JetBrains Mono', monospace; font-size: 12px; }
.row { display: flex; }
.spread { justify-content: space-between; }
.right { text-align: right; }
.sig { text-align: center; }
.sig-line { border-top: 1px solid #111; width: 200px; margin: 48px auto 4px; }
.sig-block { margin-top: 70px; }
.cell-line { border-bottom: 1px dotted #999; height: 18px; }
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
