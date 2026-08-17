<script setup lang="ts">
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()
const { money } = useFmt()
const { logoUrl } = useCompanyLogo()
const { activeCompanyId, load: loadProfile } = useProfile()
const { locale: printLocale, t, toggle: toggleLang } = usePrintLocale()

const company = ref<any>(null)
const rows = ref<any[]>([])
const loading = ref(true)

// Only 1200 (Accounts Receivable) and 1210 (Bills Receivable — LC) carry a
// party_id when posted (invoices/create_invoice_from_challan) — GDNI (1220)
// is a company-wide bucket, never tagged to one customer, so it has no
// place in a per-customer statement and is deliberately left out here.
//
// Scoped to activeCompanyId, not just RLS — a user who belongs to more than
// one company (parent + subsidiaries) would otherwise get every company's
// rows and letterhead mixed together, since journal_lines RLS only checks
// membership, not "is this the company currently selected in the header."
// This page opens in its own tab (layout:false, so the default layout's
// useProfile().load() never runs) — load the profile ourselves first so
// activeCompanyId is actually populated before it's used below.
const load = async () => {
  loading.value = true
  await loadProfile()
  const { data } = await client
    .from('journal_lines')
    .select('debit, credit, party_id, accounts!inner(code), parties(name)')
    .eq('company_id', activeCompanyId.value)
    .in('accounts.code', ['1200', '1210'])
    .not('party_id', 'is', null)

  const byParty = new Map<string, { name: string; ar: number; lc: number }>()
  for (const r of (data ?? []) as any[]) {
    const key = r.party_id
    const entry = byParty.get(key) ?? { name: r.parties?.name || '—', ar: 0, lc: 0 }
    const net = Number(r.debit || 0) - Number(r.credit || 0)
    if (r.accounts?.code === '1200') entry.ar += net
    else entry.lc += net
    byParty.set(key, entry)
  }
  rows.value = [...byParty.values()]
    .map((r) => ({ ...r, total: r.ar + r.lc }))
    .filter((r) => Math.abs(r.total) >= 1)
    .sort((a, b) => b.total - a.total)

  const { data: c } = await client.from('companies').select('*').eq('id', activeCompanyId.value).single()
  company.value = c
  loading.value = false
  if (route.query.auto) setTimeout(() => window.print(), 600)
}
onMounted(load)

const grandTotal = computed(() => rows.value.reduce((s, r) => s + r.total, 0))
const today = new Date().toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' })
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink to="/parties" class="back">{{ t('printGov.receivables.back') }}</NuxtLink>
      <button class="lang-btn" @click="toggleLang">{{ t('print.toolbar.lang_toggle') }}</button>
      <button class="print-btn" @click="() => window.print()">{{ t('print.toolbar.print_btn') }}</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">{{ t('print.toolbar.loading') }}</div>

    <div v-else class="sheet" :lang="printLocale">
      <div class="letterhead">
        <img v-if="company && logoUrl(company)" :src="logoUrl(company)" class="co-logo" alt="Company logo">
        <div class="co-name">{{ company?.legal_name || company?.name }}</div>
        <div class="title">{{ t('printGov.receivables.title') }}</div>
        <div class="small">{{ t('printGov.receivables.as_of', { date: today }) }}</div>
      </div>

      <table class="lines">
        <thead>
          <tr>
            <th>{{ t('printGov.receivables.col_party') }}</th>
            <th class="num">{{ t('printGov.receivables.col_ar') }}</th>
            <th class="num">{{ t('printGov.receivables.col_lc') }}</th>
            <th class="num">{{ t('printGov.receivables.col_total') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!rows.length"><td colspan="4" class="empty">{{ t('printGov.receivables.empty') }}</td></tr>
          <tr v-for="(r, i) in rows" :key="i">
            <td>{{ r.name }}</td>
            <td class="num">{{ Number(r.ar).toLocaleString('en-IN') }}</td>
            <td class="num">{{ Number(r.lc).toLocaleString('en-IN') }}</td>
            <td class="num">{{ Number(r.total).toLocaleString('en-IN') }}</td>
          </tr>
          <tr v-if="rows.length" class="total-row">
            <td colspan="3">{{ t('printGov.receivables.grand_total') }}</td>
            <td class="num">{{ money(grandTotal) }}</td>
          </tr>
        </tbody>
      </table>

      <p class="small disclaimer">{{ t('printGov.receivables.disclaimer') }}</p>
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
.lang-btn { background: transparent; color: #e4e4e7; border: 1px solid #52525b; border-radius: 4px; padding: 5px 14px; font-weight: 500; cursor: pointer; }
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
table.lines .empty { text-align: center; color: #666; padding: 16px; }
tr.total-row td { font-weight: 700; font-size: 14px; border-top: 2px solid #111; }
.disclaimer { margin-top: 20px; font-style: italic; }
@media print {
  .no-print { display: none !important; }
  .print-root { background: #fff; padding: 0; }
  .sheet { box-shadow: none; margin: 0; min-height: auto; }
}
</style>
