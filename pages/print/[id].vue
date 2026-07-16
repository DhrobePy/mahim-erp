<script setup lang="ts">
// Bank document set for an invoice: Bill of Exchange (first + second of
// exchange), Commercial Invoice, Packing List. Everything auto-fills
// from the invoice → challan → LC chain; packing weights are editable
// on screen before printing. ?auto=1 opens the print dialog on load.
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()
const { num, money } = useFmt()
const { takaWords } = useTakaWords()

const id = route.params.id as string
const inv = ref<any>(null)
const company = ref<any>(null)
const bill = ref<any>(null)
const challanLines = ref<any[]>([])
const loading = ref(true)

const docs = reactive({ boe: true, ci: true, pl: true, dc: true })
const activeDocs = computed(() =>
  (['boe', 'ci', 'pl', 'dc'] as const).filter((k) => docs[k]).map((k) => (k === 'dc' ? 'challan' : k)) as Array<'boe' | 'ci' | 'pl' | 'challan'>)

const { defaultsFor } = useLcClauses()
const clauses = ref<string[]>([])
let saveTimer: any = null
watch(clauses, (v) => {
  clearTimeout(saveTimer)
  saveTimer = setTimeout(async () => {
    await client.from('invoices').update({ print_clauses: v } as any).eq('id', id)
  }, 600)
}, { deep: true })

const pack = ref<any[]>([])   // editable packing rows

const load = async () => {
  loading.value = true
  const { data: i } = await client.from('invoices')
    .select(`*, parties(name, address, phone, bin_no),
      lcs(lc_no, opened_at, usance_days, lc_type, bank:bank_party_id(name, address)),
      sales_orders(so_no),
      delivery_challans!invoices_challan_id_fkey(id, challan_no, challan_kind, document_date, actual_delivery_date),
      invoice_lines(id, qty, unit_price, items(sku, name, size_spec))`)
    .eq('id', id).single()
  inv.value = i
  if (i) {
    const [{ data: c }, { data: b }, { data: cl }] = await Promise.all([
      client.from('companies').select('*').eq('id', (i as any).company_id).single(),
      client.from('bills').select('bill_no, maturity_date, accepted_at').eq('invoice_id', id).maybeSingle(),
      (i as any).delivery_challans?.id
        ? client.from('delivery_challan_lines')
            .select('id, qty, unit_price, items(sku, name, size_spec), batches(batch_no)')
            .eq('challan_id', (i as any).delivery_challans.id)
        : Promise.resolve({ data: [] })
    ])
    company.value = c
    bill.value = b
    challanLines.value = cl ?? []
    pack.value = ((i as any).invoice_lines ?? []).map((l: any) => ({
      sku: l.items?.sku, name: l.items?.name, spec: l.items?.size_spec,
      qty: Number(l.qty), cartons: '', net: '', gross: ''
    }))
    const saved = (i as any).print_clauses
    clauses.value = Array.isArray(saved) && saved.length
      ? saved
      : [...new Set([...defaultsFor('boe'), ...defaultsFor('ci'), ...defaultsFor('pl'), ...defaultsFor('challan')])]
  }
  loading.value = false
  if (route.query.auto) setTimeout(() => window.print(), 600)
}
onMounted(load)

const total = computed(() => Number(inv.value?.total ?? 0))
const totalQty = computed(() =>
  (inv.value?.invoice_lines ?? []).reduce((s: number, l: any) => s + Number(l.qty), 0))
const packTotals = computed(() => ({
  cartons: pack.value.reduce((s, r) => s + (Number(r.cartons) || 0), 0),
  net: pack.value.reduce((s, r) => s + (Number(r.net) || 0), 0),
  gross: pack.value.reduce((s, r) => s + (Number(r.gross) || 0), 0)
}))
const fmtDate = (d?: string) => d
  ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' })
  : '—'
</script>

<template>
  <div class="print-root">
    <!-- toolbar (screen only) -->
    <div class="no-print toolbar">
      <NuxtLink :to="`/invoices/${id}`" class="back">← back to invoice</NuxtLink>
      <label><input v-model="docs.boe" type="checkbox"> Bill of Exchange</label>
      <label><input v-model="docs.ci" type="checkbox"> Commercial Invoice</label>
      <label><input v-model="docs.pl" type="checkbox"> Packing List</label>
      <label><input v-model="docs.dc" type="checkbox"> Delivery Challan</label>
      <PrintClausePicker v-model="clauses" :docs="activeDocs" />
      <button class="print-btn" @click="() => window.print()">🖨 Print</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">Loading…</div>

    <template v-else-if="inv && company">
      <!-- ============ BILL OF EXCHANGE (first + second) ============ -->
      <template v-if="docs.boe">
        <div v-for="copy in ['FIRST', 'SECOND']" :key="copy" class="sheet">
          <div class="doc-title">BILL OF EXCHANGE</div>
          <div class="row spread">
            <div>
              <div>No. <b class="mono">{{ bill?.bill_no ?? inv.invoice_no }}</b></div>
              <div>For <b class="mono">৳ {{ num(total) }}</b></div>
            </div>
            <div class="right">
              <div>{{ company.address || 'Dhaka, Bangladesh' }}</div>
              <div>Date: <b>{{ fmtDate(inv.invoice_date) }}</b></div>
            </div>
          </div>

          <p class="boe-body">
            At <b>{{ inv.lcs?.lc_type === 'usance' ? `${inv.lcs?.usance_days} (${takaWords(inv.lcs?.usance_days ?? 0).replace('Taka ', '').replace(' Only', '')}) days sight` : 'sight' }}</b>
            of this <b>{{ copy }}</b> Bill of Exchange
            ({{ copy === 'FIRST' ? 'Second' : 'First' }} of the same tenor and date being unpaid),
            pay to the order of <b>ourselves</b> the sum of
            <b>{{ takaWords(total) }}</b>.
          </p>

          <p class="boe-body">
            Value received against our Commercial Invoice No. <b class="mono">{{ inv.invoice_no }}</b>
            dated {{ fmtDate(inv.invoice_date) }}, drawn under Irrevocable Letter of Credit
            No. <b class="mono">{{ inv.lcs?.lc_no ?? '—' }}</b>
            dated {{ fmtDate(inv.lcs?.opened_at) }}
            issued by <b>{{ inv.lcs?.bank?.name ?? '—' }}</b>.
          </p>

          <PrintClauseBlock :selected-keys="clauses" doc="boe" />

          <div class="row spread boe-foot">
            <div>
              <div class="small">To:</div>
              <div><b>{{ inv.lcs?.bank?.name ?? '—' }}</b></div>
              <div class="small">{{ inv.lcs?.bank?.address || '' }}</div>
              <div class="small">A/C: {{ inv.parties?.name }}</div>
            </div>
            <div class="sig">
              <div class="sig-line" />
              <div>For <b>{{ company.legal_name || company.name }}</b></div>
              <div class="small">Authorised Signature</div>
            </div>
          </div>
        </div>
      </template>

      <!-- ================= COMMERCIAL INVOICE ====================== -->
      <div v-if="docs.ci" class="sheet">
        <div class="letterhead">
          <div class="co-name">{{ company.legal_name || company.name }}</div>
          <div class="small">{{ company.address || '' }}</div>
          <div class="small">BIN: {{ company.bin_no || '—' }} · TIN: {{ company.tin_no || '—' }}</div>
        </div>
        <div class="doc-title">COMMERCIAL INVOICE</div>

        <table class="meta">
          <tbody>
            <tr>
              <td>
                <div class="small">Buyer / Applicant</div>
                <b>{{ inv.parties?.name }}</b>
                <div class="small">{{ inv.parties?.address || '' }}</div>
                <div class="small">BIN: {{ inv.parties?.bin_no || '—' }}</div>
              </td>
              <td>
                <div>Invoice No: <b class="mono">{{ inv.invoice_no }}</b></div>
                <div>Date: <b>{{ fmtDate(inv.invoice_date) }}</b></div>
                <div>Challan: <b class="mono">{{ inv.delivery_challans?.challan_no }}</b> dt. {{ fmtDate(inv.delivery_challans?.document_date) }}</div>
                <div v-if="inv.sales_orders">Order Ref: <b class="mono">{{ inv.sales_orders.so_no }}</b></div>
              </td>
              <td>
                <div>L/C No: <b class="mono">{{ inv.lcs?.lc_no ?? '—' }}</b></div>
                <div>L/C Date: <b>{{ fmtDate(inv.lcs?.opened_at) }}</b></div>
                <div>Issuing Bank: <b>{{ inv.lcs?.bank?.name ?? '—' }}</b></div>
                <div v-if="inv.lcs?.lc_type === 'usance'">Tenor: <b>{{ inv.lcs.usance_days }} days sight</b></div>
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
            <tr v-for="(l, i) in inv.invoice_lines" :key="l.id">
              <td>{{ i + 1 }}</td>
              <td>{{ l.items?.name }} <span class="small">({{ l.items?.sku }})</span></td>
              <td>{{ l.items?.size_spec || '—' }}</td>
              <td class="right mono">{{ num(l.qty, 0) }}</td>
              <td class="right mono">{{ num(l.unit_price) }}</td>
              <td class="right mono">{{ num(l.qty * l.unit_price) }}</td>
            </tr>
            <tr class="total-row">
              <td colspan="3"><b>TOTAL</b></td>
              <td class="right mono"><b>{{ num(totalQty, 0) }}</b></td>
              <td />
              <td class="right mono"><b>{{ num(total) }}</b></td>
            </tr>
          </tbody>
        </table>

        <p><b>Amount in words:</b> {{ takaWords(total) }}</p>
        <p v-if="inv.is_deemed_export" class="small">
          Deemed export against back-to-back L/C — VAT @ 0% (Mushak 6.3 issued with delivery challan
          {{ inv.delivery_challans?.challan_no }}).
        </p>

        <PrintClauseBlock :selected-keys="clauses" doc="ci" />

        <div class="row spread sig-block">
          <div class="sig"><div class="sig-line" /><div class="small">Prepared by</div></div>
          <div class="sig">
            <div class="sig-line" />
            <div>For <b>{{ company.legal_name || company.name }}</b></div>
            <div class="small">Authorised Signature</div>
          </div>
        </div>
      </div>

      <!-- =================== PACKING LIST ========================== -->
      <div v-if="docs.pl" class="sheet">
        <div class="letterhead">
          <div class="co-name">{{ company.legal_name || company.name }}</div>
          <div class="small">{{ company.address || '' }}</div>
        </div>
        <div class="doc-title">PACKING LIST</div>

        <table class="meta">
          <tbody>
            <tr>
              <td>
                <div class="small">Buyer</div>
                <b>{{ inv.parties?.name }}</b>
              </td>
              <td>
                <div>Invoice No: <b class="mono">{{ inv.invoice_no }}</b> dt. {{ fmtDate(inv.invoice_date) }}</div>
                <div>Challan: <b class="mono">{{ inv.delivery_challans?.challan_no }}</b></div>
              </td>
              <td>
                <div>L/C No: <b class="mono">{{ inv.lcs?.lc_no ?? '—' }}</b></div>
              </td>
            </tr>
          </tbody>
        </table>

        <table class="lines">
          <thead>
            <tr>
              <th style="width: 30px;">SL</th><th>Description</th>
              <th class="right">Qty (Pcs)</th><th class="right">Cartons / Bundles</th>
              <th class="right">Net Wt. (kg)</th><th class="right">Gross Wt. (kg)</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(r, i) in pack" :key="i">
              <td>{{ i + 1 }}</td>
              <td>{{ r.name }} <span class="small">({{ r.sku }}{{ r.spec ? ' · ' + r.spec : '' }})</span></td>
              <td class="right mono">{{ num(r.qty, 0) }}</td>
              <td class="right"><input v-model="r.cartons" class="cell mono" placeholder="…"></td>
              <td class="right"><input v-model="r.net" class="cell mono" placeholder="…"></td>
              <td class="right"><input v-model="r.gross" class="cell mono" placeholder="…"></td>
            </tr>
            <tr class="total-row">
              <td colspan="2"><b>TOTAL</b></td>
              <td class="right mono"><b>{{ num(totalQty, 0) }}</b></td>
              <td class="right mono"><b>{{ packTotals.cartons || '—' }}</b></td>
              <td class="right mono"><b>{{ packTotals.net || '—' }}</b></td>
              <td class="right mono"><b>{{ packTotals.gross || '—' }}</b></td>
            </tr>
          </tbody>
        </table>

        <p class="small">Packing: export-standard corrugated bundles/cartons. Country of origin: Bangladesh.</p>

        <PrintClauseBlock :selected-keys="clauses" doc="pl" />

        <div class="row spread sig-block">
          <div class="sig"><div class="sig-line" /><div class="small">Prepared by</div></div>
          <div class="sig">
            <div class="sig-line" />
            <div>For <b>{{ company.legal_name || company.name }}</b></div>
            <div class="small">Authorised Signature</div>
          </div>
        </div>
      </div>

      <!-- =================== DELIVERY CHALLAN ======================= -->
      <div v-if="docs.dc && inv.delivery_challans" class="sheet">
        <div class="letterhead">
          <div class="co-name">{{ company.legal_name || company.name }}</div>
          <div class="small">{{ company.address || '' }}</div>
        </div>
        <div class="doc-title">
          DELIVERY CHALLAN
          <span v-if="inv.delivery_challans.challan_kind === 'covering'" class="kind-tag">(Covering Set)</span>
          <span v-else-if="inv.delivery_challans.challan_kind === 'original'" class="kind-tag">(Pre-LC Original)</span>
        </div>

        <table class="meta">
          <tbody>
            <tr>
              <td>
                <div class="small">Consignee / Buyer</div>
                <b>{{ inv.parties?.name }}</b>
                <div class="small">{{ inv.parties?.address || '' }}</div>
              </td>
              <td>
                <div>Challan No: <b class="mono">{{ inv.delivery_challans.challan_no }}</b></div>
                <div>Date: <b>{{ fmtDate(inv.delivery_challans.document_date) }}</b></div>
                <div v-if="inv.delivery_challans.actual_delivery_date !== inv.delivery_challans.document_date" class="small">
                  Actual delivery: {{ fmtDate(inv.delivery_challans.actual_delivery_date) }}
                </div>
                <div v-if="inv.sales_orders">Order Ref: <b class="mono">{{ inv.sales_orders.so_no }}</b></div>
              </td>
              <td>
                <div>L/C No: <b class="mono">{{ inv.lcs?.lc_no ?? '—' }}</b></div>
                <div>Invoice No: <b class="mono">{{ inv.invoice_no }}</b></div>
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
            <tr v-for="(l, i) in challanLines" :key="l.id">
              <td>{{ i + 1 }}</td>
              <td>{{ l.items?.name }} <span class="small">({{ l.items?.sku }})</span></td>
              <td>{{ l.items?.size_spec || '—' }}</td>
              <td class="mono">{{ l.batches?.batch_no || '—' }}</td>
              <td class="right mono">{{ num(l.qty, 0) }}</td>
            </tr>
            <tr class="total-row">
              <td colspan="4"><b>TOTAL</b></td>
              <td class="right mono"><b>{{ num(challanLines.reduce((s, l) => s + Number(l.qty), 0), 0) }}</b></td>
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
    </template>

    <div v-else-if="!loading" class="no-print" style="padding: 40px; text-align: center;">Invoice not found.</div>
  </div>
</template>

<style scoped>
.print-root { min-height: 100vh; background: #3f3f46; padding: 16px 0 48px; font-family: Georgia, 'Times New Roman', serif; }
.toolbar {
  position: sticky; top: 0; z-index: 5; display: flex; gap: 18px; align-items: center; justify-content: center;
  background: #18181b; color: #e4e4e7; padding: 10px; margin: -16px 0 16px;
  font-family: Inter, sans-serif; font-size: 13px;
}
.toolbar label { display: flex; gap: 6px; align-items: center; cursor: pointer; }
.toolbar .back { color: #fbbf24; text-decoration: none; }
.print-btn { background: #f59e0b; color: #000; border: 0; border-radius: 4px; padding: 6px 16px; font-weight: 600; cursor: pointer; }

.sheet {
  width: 210mm; min-height: 280mm; margin: 0 auto 20px; background: #fff; color: #111;
  padding: 18mm 16mm; box-shadow: 0 2px 12px rgba(0,0,0,.4); font-size: 13px; line-height: 1.55;
}
.doc-title { text-align: center; font-size: 17px; font-weight: 700; letter-spacing: 3px; text-decoration: underline; margin: 8px 0 18px; }
.kind-tag { display: block; font-size: 11px; letter-spacing: 1px; text-decoration: none; color: #555; margin-top: 2px; }
.cell-line { border-bottom: 1px dotted #999; height: 18px; }
.letterhead { text-align: center; border-bottom: 2px solid #111; padding-bottom: 8px; margin-bottom: 10px; }
.co-name { font-size: 20px; font-weight: 700; letter-spacing: 1px; }
.small { font-size: 11px; color: #333; }
.mono { font-family: 'JetBrains Mono', monospace; font-size: 12px; }
.row { display: flex; }
.spread { justify-content: space-between; }
.right { text-align: right; }
.boe-body { margin: 16px 0; text-align: justify; font-size: 14px; }
.boe-foot { margin-top: 60px; align-items: flex-end; }
.sig { text-align: center; }
.sig-line { border-top: 1px solid #111; width: 200px; margin: 48px auto 4px; }
.sig-block { margin-top: 70px; }
table.meta { width: 100%; border-collapse: collapse; margin-bottom: 12px; }
table.meta td { border: 1px solid #444; padding: 6px 8px; vertical-align: top; width: 33%; }
table.lines { width: 100%; border-collapse: collapse; margin: 6px 0 12px; }
table.lines th, table.lines td { border: 1px solid #444; padding: 5px 8px; }
table.lines th { background: #f0f0f0; font-size: 11px; text-transform: uppercase; letter-spacing: .5px; }
.total-row td { background: #fafafa; }
.cell { width: 90px; border: 0; border-bottom: 1px dotted #999; text-align: right; font-size: 13px; background: transparent; outline: none; }

@media print {
  .no-print { display: none !important; }
  .print-root { background: #fff; padding: 0; }
  .sheet { box-shadow: none; margin: 0; page-break-after: always; min-height: auto; }
  .cell { border-bottom: 0; }
}
</style>
