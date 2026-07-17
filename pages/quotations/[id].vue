<script setup lang="ts">
const route = useRoute()
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money, num } = useFmt()

const id = route.params.id as string
const doc = ref<any>(null)
const children = ref<any[]>([])
const loading = ref(true)

const typeLabel: Record<string, string> = { quotation: 'Quotation', pi: 'Proforma Invoice', contract: 'Sales Contract' }
const statusColor: Record<string, string> = {
  draft: 'gray', sent: 'blue', accepted: 'green', expired: 'red', converted: 'purple', cancelled: 'red'
}

const load = async () => {
  loading.value = true
  const { data } = await client.from('sales_documents')
    .select(`*, parties(id, name, address, phone), parent:parent_doc_id(id, doc_no, doc_type),
      sales_orders(id, so_no), sales_document_lines(id, qty, unit_price, items(sku, name))`)
    .eq('id', id).single()
  doc.value = data
  if (data) {
    const { data: c } = await client.from('sales_documents')
      .select('id, doc_no, doc_type, status').eq('parent_doc_id', id)
    children.value = c ?? []
  }
  loading.value = false
}
onMounted(load)

const total = computed(() =>
  (doc.value?.sales_document_lines ?? []).reduce((s: number, l: any) => s + l.qty * l.unit_price, 0))

const setStatus = async (status: string) => {
  const { error } = await client.from('sales_documents').update({ status } as any).eq('id', id)
  if (error) toast.add({ title: 'Update failed', description: error.message, color: 'red' })
  else await load()
}
const convert = async (toType: string) => {
  const { error } = await client.rpc('convert_sales_document', { p_id: id, p_to_type: toType } as any)
  if (error) toast.add({ title: 'Conversion failed', description: error.message, color: 'red' })
  else { toast.add({ title: `Converted to ${typeLabel[toType]}` }); await load() }
}
const toOrder = async () => {
  const { error } = await client.rpc('sales_document_to_order', { p_id: id } as any)
  if (error) toast.add({ title: 'Conversion failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Sales order created' }); await load() }
}
</script>

<template>
  <div v-if="doc">
    <PageHeader kicker="Sales &amp; Local LC" :title="`${typeLabel[doc.doc_type]} ${doc.doc_no}`" :subtitle="`${doc.parties?.name} · ${doc.doc_date} · valid until ${doc.valid_until || '—'}`">
      <UBadge variant="subtle" :color="statusColor[doc.status]">{{ doc.status }}</UBadge>
      <UButton icon="i-heroicons-printer" variant="soft" :to="`/print/quote/${doc.id}`" target="_blank">Print</UButton>
      <template v-if="canWrite && ['draft', 'sent', 'accepted'].includes(doc.status)">
        <UButton v-if="doc.status === 'draft'" size="sm" variant="soft" @click="setStatus('sent')">Mark sent</UButton>
        <UButton v-if="doc.status === 'sent'" size="sm" variant="soft" color="green" @click="setStatus('accepted')">Mark accepted</UButton>
        <UButton v-if="doc.doc_type === 'quotation'" size="sm" variant="soft" color="blue" @click="convert('pi')">Convert → PI</UButton>
        <UButton v-if="doc.doc_type !== 'contract'" size="sm" variant="soft" color="purple" @click="convert('contract')">Convert → Contract</UButton>
        <UButton size="sm" variant="soft" color="amber" @click="toOrder">Convert → Sales order</UButton>
      </template>
    </PageHeader>

    <div class="flex flex-wrap gap-3 mb-4 text-[12.5px]">
      <NuxtLink :to="`/parties/${doc.customer_party_id}`" class="text-amber-600 dark:text-amber-400 hover:underline">→ buyer profile</NuxtLink>
      <NuxtLink v-if="doc.parent" :to="`/quotations/${doc.parent.id}`" class="text-amber-600 dark:text-amber-400 hover:underline">
        → generated from {{ typeLabel[doc.parent.doc_type] }} {{ doc.parent.doc_no }}
      </NuxtLink>
      <NuxtLink v-for="c in children" :key="c.id" :to="`/quotations/${c.id}`" class="text-amber-600 dark:text-amber-400 hover:underline">
        → {{ typeLabel[c.doc_type] }} {{ c.doc_no }} ({{ c.status }})
      </NuxtLink>
      <NuxtLink v-if="doc.sales_orders" :to="`/sales/${doc.sales_orders.id}`" class="text-amber-600 dark:text-amber-400 hover:underline">
        → sales order {{ doc.sales_orders.so_no }}
      </NuxtLink>
    </div>

    <div class="grid grid-cols-1 xl:grid-cols-2 gap-4">
      <UCard>
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Lines</p></template>
        <div v-for="l in doc.sales_document_lines" :key="l.id" class="flex justify-between py-1.5 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
          <span class="dark:text-zinc-200">{{ l.items?.sku }} — {{ l.items?.name }}</span>
          <span class="num">{{ num(l.qty, 0) }} × ৳{{ l.unit_price }} = <span class="font-medium dark:text-zinc-100">{{ money(l.qty * l.unit_price) }}</span></span>
        </div>
        <div class="flex justify-between pt-2 mt-1 border-t border-gray-200 dark:border-zinc-800 text-[13px] font-semibold">
          <span>Total</span><span class="num text-amber-600 dark:text-amber-400">{{ money(total) }}</span>
        </div>
      </UCard>

      <UCard>
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Terms</p></template>
        <div class="text-[13px] space-y-2">
          <div><span class="text-gray-500 dark:text-zinc-500">Payment:</span> {{ doc.payment_terms || '—' }}</div>
          <div><span class="text-gray-500 dark:text-zinc-500">Delivery:</span> {{ doc.delivery_terms || '—' }}</div>
          <div><span class="text-gray-500 dark:text-zinc-500">Basis:</span> {{ doc.is_deemed_export ? 'Deemed export (0% VAT)' : 'Domestic (15% VAT)' }}</div>
          <div v-if="doc.notes"><span class="text-gray-500 dark:text-zinc-500">Notes:</span> {{ doc.notes }}</div>
        </div>
      </UCard>
    </div>
  </div>
  <div v-else-if="!loading" class="text-sm text-gray-400 py-10 text-center">Document not found.</div>
</template>
