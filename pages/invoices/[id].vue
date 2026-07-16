<script setup lang="ts">
const route = useRoute()
const client = useSupabaseClient()
const { money, num } = useFmt()
const { docLink } = useDocLink()

const id = route.params.id as string
const inv = ref<any>(null)
const bill = ref<any>(null)
const journals = ref<any[]>([])
const creditNotes = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [i, b, j, cn] = await Promise.all([
    client.from('invoices')
      .select('*, parties(id, name), lcs(id, lc_no), sales_orders(id, so_no), delivery_challans!invoices_challan_id_fkey(id, challan_no, challan_kind, document_date, actual_delivery_date), invoice_lines(id, qty, unit_price, items(sku, name))')
      .eq('id', id).single(),
    client.from('bills').select('*, lbpd_disbursements(id, principal, advance_pct, status, interest_paid)').eq('invoice_id', id).maybeSingle(),
    client.from('journals').select('id, journal_no, journal_date, memo').eq('ref_table', 'invoices').eq('ref_id', id),
    client.from('credit_notes').select('cn_no, qty, unit_price, scrap_unit_value, reason, created_at').eq('invoice_id', id)
  ])
  inv.value = i.data
  bill.value = b.data
  journals.value = j.data ?? []
  creditNotes.value = cn.data ?? []
  loading.value = false
}
onMounted(load)
</script>

<template>
  <div v-if="inv">
    <PageHeader kicker="Sales &amp; Local LC" :title="inv.invoice_no" :subtitle="`${inv.invoice_date} · ${inv.is_deemed_export ? 'deemed export (0% VAT, Mushak 6.3)' : 'domestic'}`">
      <UBadge variant="subtle" :color="inv.status === 'settled' ? 'green' : inv.status === 'billed' ? 'purple' : 'blue'">{{ inv.status }}</UBadge>
      <UButton
        icon="i-heroicons-printer" variant="soft"
        :to="`/print/${inv.id}`" target="_blank"
      >Print bank set</UButton>
    </PageHeader>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
      <StatCard label="Total" :value="money(inv.total)" tone="amber" />
      <StatCard label="COGS" :value="money(inv.cogs_total)" />
      <StatCard label="Margin" :value="money(Number(inv.total) - Number(inv.cogs_total))" :tone="Number(inv.total) - Number(inv.cogs_total) >= 0 ? 'green' : 'red'" />
      <StatCard label="Buyer" :value="inv.parties?.name ?? '—'" />
    </div>

    <div class="flex flex-wrap gap-3 mb-4 text-[12.5px]">
      <NuxtLink :to="`/parties/${inv.parties?.id}`" class="text-amber-600 dark:text-amber-400 hover:underline">→ buyer</NuxtLink>
      <NuxtLink v-if="inv.sales_orders" :to="`/sales/${inv.sales_orders.id}`" class="text-amber-600 dark:text-amber-400 hover:underline">→ order {{ inv.sales_orders.so_no }}</NuxtLink>
      <NuxtLink v-if="inv.lcs" :to="`/lcs/${inv.lcs.id}`" class="text-amber-600 dark:text-amber-400 hover:underline">→ LC {{ inv.lcs.lc_no }}</NuxtLink>
      <NuxtLink v-if="bill" to="/banking" class="text-amber-600 dark:text-amber-400 hover:underline">→ bill {{ bill.bill_no }} ({{ bill.status }})</NuxtLink>
    </div>

    <div class="grid grid-cols-1 xl:grid-cols-2 gap-4">
      <UCard>
        <template #header>
          <p class="microlabel text-gray-400 dark:text-zinc-500">
            Lines — challan {{ inv.delivery_challans?.challan_no }}
            <span v-if="inv.delivery_challans?.challan_kind === 'covering'" class="text-purple-400">(covering set)</span>
          </p>
        </template>
        <div v-for="l in inv.invoice_lines" :key="l.id" class="flex justify-between py-1.5 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
          <span class="dark:text-zinc-200">{{ l.items?.sku }} — {{ l.items?.name }}</span>
          <span class="num">{{ num(l.qty, 0) }} × ৳{{ l.unit_price }} = <span class="font-medium dark:text-zinc-100">{{ money(l.qty * l.unit_price) }}</span></span>
        </div>
        <div v-if="inv.delivery_challans && inv.delivery_challans.document_date !== inv.delivery_challans.actual_delivery_date" class="mt-2 text-[11.5px] num text-amber-600 dark:text-amber-400">
          Document date {{ inv.delivery_challans.document_date }} · actual delivery {{ inv.delivery_challans.actual_delivery_date }}
        </div>
      </UCard>

      <div class="space-y-4">
        <UCard v-if="bill">
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Bill &amp; financing</p></template>
          <div class="text-[13px] space-y-1">
            <div class="flex justify-between"><span>Bill</span><span class="num">{{ bill.bill_no }} · {{ bill.status }}</span></div>
            <div class="flex justify-between"><span>Maturity</span><span class="num">{{ bill.maturity_date ?? '—' }}</span></div>
            <div v-for="d in bill.lbpd_disbursements" :key="d.id" class="flex justify-between">
              <span>LBPD {{ d.advance_pct }}% ({{ d.status }})</span>
              <span class="num text-amber-600 dark:text-amber-400">{{ money(d.principal) }}</span>
            </div>
          </div>
        </UCard>

        <UCard v-if="creditNotes.length">
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Returns / credit notes</p></template>
          <div v-for="c in creditNotes" :key="c.cn_no" class="flex justify-between py-1 text-[13px]">
            <span class="num text-red-500 dark:text-red-400">{{ c.cn_no }}</span>
            <span class="num text-gray-500 dark:text-zinc-500">{{ num(c.qty, 0) }} × ৳{{ c.unit_price }} · scrap ৳{{ c.scrap_unit_value }}</span>
          </div>
        </UCard>

        <UCard>
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Postings</p></template>
          <div v-if="!journals.length" class="text-sm text-gray-400 py-2 text-center">No journals reference this invoice.</div>
          <div v-for="j in journals" :key="j.id" class="flex justify-between py-1 text-[13px]">
            <NuxtLink :to="docLink('journals', j.id)!" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ j.journal_no }}</NuxtLink>
            <span class="text-gray-500 dark:text-zinc-500 truncate ml-3">{{ j.memo }}</span>
          </div>
        </UCard>
      </div>
    </div>
  </div>
  <div v-else-if="!loading" class="text-sm text-gray-400 py-10 text-center">Invoice not found.</div>
</template>
