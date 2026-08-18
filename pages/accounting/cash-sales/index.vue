<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money } = useFmt()
const { deleteRecord } = useRecycleBin()
const { replaceLines } = useLineReconcile()
const { t } = useI18n()

const sales = ref<any[]>([])
const customers = ref<any[]>([])
const items = ref<any[]>([])
const cashBankAccounts = ref<any[]>([])
const loading = ref(true)

const columns = computed(() => [
  { key: 'sale_no', label: t('accounting.cash_sales.columns.no') },
  { key: 'sale_date', label: t('common.date') },
  { key: 'customer', label: t('accounting.cash_sales.columns.customer') },
  { key: 'account', label: t('accounting.cash_sales.columns.account') },
  { key: 'lines', label: t('accounting.cash_sales.columns.lines') },
  { key: 'total', label: t('accounting.cash_sales.columns.total') },
  { key: 'status', label: t('common.status') },
  { key: 'actions', label: '' }
])

const load = async () => {
  loading.value = true
  const [s, c, i, cba] = await Promise.all([
    client.from('cash_sales')
      .select('*, parties(name), cash_bank_accounts(name), cash_sale_lines(id, item_id, qty, unit_price, items(sku))')
      .is('deleted_at', null)
      .order('created_at', { ascending: false }),
    client.from('parties').select('id, name').eq('is_customer', true).is('deleted_at', null).order('name'),
    client.from('items').select('id, sku, name').eq('is_active', true).is('deleted_at', null).order('sku'),
    client.from('cash_bank_accounts').select('id, name').eq('is_active', true).is('deleted_at', null).order('name')
  ])
  sales.value = s.data ?? []
  customers.value = c.data ?? []
  items.value = i.data ?? []
  cashBankAccounts.value = cba.data ?? []
  loading.value = false
}
onMounted(load)

const lineTotal = (row: any) => (row.cash_sale_lines ?? []).reduce((s: number, l: any) => s + Number(l.qty) * Number(l.unit_price), 0)
const rowTotal = (row: any) => {
  const sub = lineTotal(row)
  return row.vat_applicable ? sub * (1 + Number(row.vat_rate) / 100) : sub
}

const open = ref(false)
const saving = ref(false)
const form = reactive({
  id: null as string | null,
  customer_party_id: null as string | null,
  customer_name: '',
  cash_bank_account_id: null as string | null,
  vat_applicable: true,
  vat_rate: 15,
  sale_date: new Date().toISOString().slice(0, 10)
})
const walkIn = ref(true)
const lines = ref<any[]>([])
const blankLine = () => ({ item_id: null, qty: 0, unit_price: 0 })
const openNew = () => {
  Object.assign(form, {
    id: null, customer_party_id: null, customer_name: '', cash_bank_account_id: null,
    vat_applicable: true, vat_rate: 15, sale_date: new Date().toISOString().slice(0, 10)
  })
  walkIn.value = true
  lines.value = [blankLine()]
  open.value = true
}
const openEdit = (row: any) => {
  Object.assign(form, {
    id: row.id, customer_party_id: row.customer_party_id, customer_name: row.customer_name ?? '',
    cash_bank_account_id: row.cash_bank_account_id, vat_applicable: row.vat_applicable,
    vat_rate: row.vat_rate, sale_date: row.sale_date
  })
  walkIn.value = !row.customer_party_id
  lines.value = (row.cash_sale_lines ?? []).map((l: any) => ({ item_id: l.item_id, qty: l.qty, unit_price: l.unit_price }))
  if (!lines.value.length) lines.value = [blankLine()]
  open.value = true
}

const draftSubtotal = computed(() => lines.value.reduce((s, l) => s + (Number(l.qty) || 0) * (Number(l.unit_price) || 0), 0))
const draftVat = computed(() => form.vat_applicable ? draftSubtotal.value * form.vat_rate / 100 : 0)
const draftTotal = computed(() => draftSubtotal.value + draftVat.value)

const save = async () => {
  if (!form.cash_bank_account_id) { toast.add({ title: t('accounting.cash_sales.toasts.pick_account'), color: 'red' }); return }
  if (!walkIn.value && !form.customer_party_id) { toast.add({ title: t('accounting.cash_sales.toasts.pick_customer'), color: 'red' }); return }
  const payload = lines.value.filter((l) => l.item_id && l.qty > 0)
  if (!payload.length) { toast.add({ title: t('accounting.cash_sales.toasts.add_line'), color: 'red' }); return }
  saving.value = true
  try {
    const headerPayload: any = {
      cash_bank_account_id: form.cash_bank_account_id,
      vat_applicable: form.vat_applicable,
      vat_rate: form.vat_rate,
      sale_date: form.sale_date,
      customer_party_id: walkIn.value ? null : form.customer_party_id,
      customer_name: walkIn.value ? (form.customer_name || null) : null
    }
    if (form.id) {
      const { error } = await client.from('cash_sales').update(headerPayload).eq('id', form.id)
      if (error) throw error
      await replaceLines('cash_sale_lines', 'cash_sale_id', form.id, payload.map((l) => ({ ...l, cash_sale_id: form.id })))
      toast.add({ title: t('accounting.cash_sales.toasts.updated_draft') })
    } else {
      const { data: cs, error } = await client.from('cash_sales').insert(headerPayload).select('id').single()
      if (error) throw error
      const res = await client.from('cash_sale_lines').insert(
        payload.map((l) => ({ ...l, cash_sale_id: (cs as any).id })) as any
      )
      if (res.error) throw res.error
      toast.add({ title: t('accounting.cash_sales.toasts.saved_draft') })
    }
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('accounting.cash_sales.toasts.save_failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

const completing = ref<string | null>(null)
const complete = async (row: any) => {
  completing.value = row.id
  const { error } = await client.rpc('complete_cash_sale', { p_id: row.id } as any)
  if (error) toast.add({ title: t('accounting.cash_sales.toasts.completion_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('accounting.cash_sales.toasts.completed', { sale: row.sale_no }) }); await load() }
  completing.value = null
}

const statusColor = (s: string) => ({ draft: 'gray', completed: 'green' } as any)[s] || 'gray'

const remove = async (row: any) => {
  if (await deleteRecord('cash_sales', row.id, row.sale_no)) await load()
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('accounting.kicker')" :title="t('accounting.cash_sales.title')" :subtitle="t('accounting.cash_sales.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('accounting.cash_sales.new_sale') }}</UButton>
    </PageHeader>

    <UCard>
      <UTable :rows="sales" :columns="columns" :loading="loading">
        <template #sale_no-data="{ row }">
          <span class="num font-medium text-amber-600 dark:text-amber-400">{{ row.sale_no }}</span>
        </template>
        <template #sale_date-data="{ row }"><span class="num">{{ row.sale_date }}</span></template>
        <template #customer-data="{ row }">
          <NuxtLink v-if="row.customer_party_id" :to="`/parties/${row.customer_party_id}`" class="hover:underline">{{ row.parties?.name }}</NuxtLink>
          <span v-else class="text-gray-500 dark:text-zinc-500">{{ row.customer_name || t('accounting.cash_sales.walk_in') }}</span>
        </template>
        <template #account-data="{ row }">{{ row.cash_bank_accounts?.name }}</template>
        <template #lines-data="{ row }">
          <div class="text-xs space-y-0.5">
            <div v-for="l in row.cash_sale_lines" :key="l.id">
              {{ l.items?.sku }} — <span class="num">{{ l.qty }}</span> @ <span class="num text-amber-600 dark:text-amber-400">৳{{ l.unit_price }}</span>
            </div>
          </div>
        </template>
        <template #total-data="{ row }"><span class="num font-semibold">{{ money(rowTotal(row)) }}</span></template>
        <template #status-data="{ row }"><UBadge size="xs" variant="subtle" :color="statusColor(row.status)">{{ row.status }}</UBadge></template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton icon="i-heroicons-printer" size="xs" color="gray" variant="ghost" :to="`/print/cashsale/${row.id}`" target="_blank" :aria-label="t('accounting.cash_sales.print_aria')" />
            <UButton v-if="canWrite && row.status === 'draft'" icon="i-heroicons-pencil-square" variant="ghost" size="xs" @click="openEdit(row)" />
            <UButton v-if="canWrite && row.status === 'draft'" size="xs" variant="soft" color="green" :loading="completing === row.id" @click="complete(row)">{{ t('accounting.cash_sales.complete') }}</UButton>
            <UButton v-if="canWrite" icon="i-heroicons-trash" color="red" variant="ghost" size="xs" @click="remove(row)" />
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('accounting.cash_sales.empty') }}</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ form.id ? t('accounting.cash_sales.dialog.edit_title') : t('accounting.cash_sales.dialog.title') }}</p></template>
        <div class="grid grid-cols-2 gap-4 mb-4">
          <UFormGroup :label="t('common.date')"><UInput v-model="form.sale_date" type="date" /></UFormGroup>
          <UFormGroup :label="t('accounting.cash_sales.dialog.received_into')" required>
            <USelect v-model="form.cash_bank_account_id" :options="cashBankAccounts" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <div class="col-span-2">
            <UFormGroup :label="t('accounting.cash_sales.dialog.customer')">
              <div class="flex gap-2 mb-2">
                <button
                  class="px-3 py-1 rounded text-xs border cursor-pointer"
                  :class="walkIn ? 'border-amber-500 text-amber-600 dark:text-amber-400 bg-amber-50/60 dark:bg-amber-500/10' : 'border-gray-200 dark:border-zinc-700 text-gray-500'"
                  @click="walkIn = true"
                >{{ t('accounting.cash_sales.dialog.walk_in_tab') }}</button>
                <button
                  class="px-3 py-1 rounded text-xs border cursor-pointer"
                  :class="!walkIn ? 'border-amber-500 text-amber-600 dark:text-amber-400 bg-amber-50/60 dark:bg-amber-500/10' : 'border-gray-200 dark:border-zinc-700 text-gray-500'"
                  @click="walkIn = false"
                >{{ t('accounting.cash_sales.dialog.registered_party_tab') }}</button>
              </div>
              <UInput v-if="walkIn" v-model="form.customer_name" :placeholder="t('accounting.cash_sales.dialog.walk_in_placeholder')" />
              <USelect v-else v-model="form.customer_party_id" :options="customers" option-attribute="name" value-attribute="id" placeholder="—" />
            </UFormGroup>
          </div>
          <div class="col-span-2 flex items-center gap-4">
            <UCheckbox v-model="form.vat_applicable" :label="t('accounting.cash_sales.dialog.vat_applicable')" />
            <UInput v-if="form.vat_applicable" v-model.number="form.vat_rate" type="number" class="w-20" />
            <span v-if="form.vat_applicable" class="text-xs text-gray-400">{{ t('accounting.cash_sales.dialog.vat_suffix') }}</span>
          </div>
        </div>
        <div class="space-y-2">
          <div v-for="(l, idx) in lines" :key="idx" class="grid grid-cols-3 gap-2">
            <UFormGroup :label="t('accounting.cash_sales.dialog.item')">
              <USelect v-model="l.item_id" :options="items" option-attribute="sku" value-attribute="id" placeholder="—" />
            </UFormGroup>
            <UFormGroup :label="t('accounting.cash_sales.dialog.qty')"><UInput v-model.number="l.qty" type="number" /></UFormGroup>
            <UFormGroup :label="t('accounting.cash_sales.dialog.unit_price')"><UInput v-model.number="l.unit_price" type="number" /></UFormGroup>
          </div>
          <UButton size="xs" variant="soft" icon="i-heroicons-plus" @click="lines.push(blankLine())">{{ t('accounting.cash_sales.dialog.add_line') }}</UButton>
        </div>
        <div class="mt-4 text-sm space-y-1 border-t border-gray-100 dark:border-zinc-800 pt-3">
          <div class="flex justify-between"><span class="text-gray-500">{{ t('accounting.cash_sales.dialog.subtotal') }}</span><span class="num">{{ money(draftSubtotal) }}</span></div>
          <div v-if="form.vat_applicable" class="flex justify-between"><span class="text-gray-500">{{ t('accounting.cash_sales.dialog.vat', { rate: form.vat_rate }) }}</span><span class="num">{{ money(draftVat) }}</span></div>
          <div class="flex justify-between font-semibold"><span>{{ t('common.total') }}</span><span class="num text-amber-600 dark:text-amber-400">{{ money(draftTotal) }}</span></div>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ form.id ? t('common.save') : t('accounting.cash_sales.dialog.save_draft') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
