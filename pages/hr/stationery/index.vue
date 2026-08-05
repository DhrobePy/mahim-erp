<script setup lang="ts">
const { t } = useI18n()
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money } = useFmt()
const { deleteRecord } = useRecycleBin()

const items = ref<any[]>([])
const stock = ref<any[]>([])
const employees = ref<any[]>([])
const cashBankAccounts = ref<any[]>([])
const parties = ref<any[]>([])
const receipts = ref<any[]>([])
const issues = ref<any[]>([])
const usage = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [i, s, e, cba, p, r, iss, u] = await Promise.all([
    client.from('items').select('id, sku, name, reorder_level, standard_cost').eq('item_type', 'consumable').eq('is_active', true).is('deleted_at', null).order('name'),
    client.from('current_stock').select('item_id, qty, stock_value'),
    client.from('employees').select('id, emp_no, full_name').eq('is_active', true).is('deleted_at', null).order('full_name'),
    client.from('cash_bank_accounts').select('id, name').eq('is_active', true).is('deleted_at', null).order('name'),
    client.from('parties').select('id, name').eq('is_supplier', true).is('deleted_at', null).order('name'),
    client.from('stationery_receipts').select('*, items(sku, name)').is('deleted_at', null).order('created_at', { ascending: false }).limit(20),
    client.from('stationery_issues').select('*, items(sku, name), employees(emp_no, full_name)').is('deleted_at', null).order('created_at', { ascending: false }).limit(20),
    client.from('v_stationery_usage_by_employee').select('*').order('total_cost', { ascending: false })
  ])
  items.value = i.data ?? []
  stock.value = s.data ?? []
  employees.value = e.data ?? []
  cashBankAccounts.value = cba.data ?? []
  parties.value = p.data ?? []
  receipts.value = r.data ?? []
  issues.value = iss.data ?? []
  usage.value = u.data ?? []
  loading.value = false
}
onMounted(load)

const stockFor = (itemId: string) => stock.value.filter((s) => s.item_id === itemId).reduce((acc, s) => ({ qty: acc.qty + Number(s.qty), value: acc.value + Number(s.stock_value) }), { qty: 0, value: 0 })
const rows = computed(() => items.value.map((it) => ({ ...it, ...stockFor(it.id) })))
const totalValue = computed(() => rows.value.reduce((s, r) => s + r.value, 0))
const lowStockCount = computed(() => rows.value.filter((r) => r.qty <= r.reorder_level).length)

const columns = computed(() => [
  { key: 'sku', label: t('hr.stationery.current_stock.columns.sku') }, { key: 'name', label: t('hr.stationery.current_stock.columns.item') },
  { key: 'qty', label: t('hr.stationery.current_stock.columns.on_hand') }, { key: 'reorder_level', label: t('hr.stationery.current_stock.columns.reorder_at') },
  { key: 'value', label: t('hr.stationery.current_stock.columns.value') }
])
const usageColumns = computed(() => [
  { key: 'emp_no', label: t('hr.stationery.usage_by_person.columns.id') }, { key: 'full_name', label: t('hr.stationery.usage_by_person.columns.employee') },
  { key: 'issue_count', label: t('hr.stationery.usage_by_person.columns.issues') }, { key: 'total_qty', label: t('hr.stationery.usage_by_person.columns.total_qty') }, { key: 'total_cost', label: t('hr.stationery.usage_by_person.columns.total_cost') }
])

// --- Receive stock ---
const receiveOpen = ref(false)
const savingReceive = ref(false)
const receiveForm = reactive({
  receipt_date: new Date().toISOString().slice(0, 10), item_id: null as string | null,
  qty: 0, unit_cost: 0, party_id: null as string | null, cash_bank_account_id: null as string | null, reference_no: '', note: ''
})
const openReceive = () => {
  Object.assign(receiveForm, {
    receipt_date: new Date().toISOString().slice(0, 10), item_id: null, qty: 0, unit_cost: 0,
    party_id: null, cash_bank_account_id: null, reference_no: '', note: ''
  })
  receiveOpen.value = true
}
const saveReceive = async () => {
  if (!receiveForm.item_id || !receiveForm.qty) { toast.add({ title: t('hr.stationery.toast.pick_item_qty'), color: 'red' }); return }
  savingReceive.value = true
  const payload: any = { ...receiveForm, reference_no: receiveForm.reference_no || null }
  const { error } = await client.from('stationery_receipts').insert(payload)
  if (error) toast.add({ title: t('hr.stationery.toast.receipt_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('hr.stationery.toast.stock_received') }); receiveOpen.value = false; await load() }
  savingReceive.value = false
}

// --- Issue to employee ---
const issueOpen = ref(false)
const savingIssue = ref(false)
const issueForm = reactive({ issue_date: new Date().toISOString().slice(0, 10), item_id: null as string | null, employee_id: null as string | null, qty: 0, note: '' })
const openIssue = () => {
  Object.assign(issueForm, { issue_date: new Date().toISOString().slice(0, 10), item_id: null, employee_id: null, qty: 0, note: '' })
  issueOpen.value = true
}
const saveIssue = async () => {
  if (!issueForm.item_id || !issueForm.employee_id || !issueForm.qty) { toast.add({ title: t('hr.stationery.toast.pick_item_employee_qty'), color: 'red' }); return }
  savingIssue.value = true
  const { error } = await client.from('stationery_issues').insert({ ...issueForm })
  if (error) toast.add({ title: t('hr.stationery.toast.issue_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('hr.stationery.toast.issued') }); issueOpen.value = false; await load() }
  savingIssue.value = false
}

const removeReceipt = async (row: any) => {
  if (await deleteRecord('stationery_receipts', row.id, row.receipt_no)) await load()
}
const removeIssue = async (row: any) => {
  if (await deleteRecord('stationery_issues', row.id, row.issue_no)) await load()
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('hr.kicker')" :title="t('hr.stationery.title')" :subtitle="t('hr.stationery.subtitle')">
      <UButton variant="soft" icon="i-heroicons-cube" to="/items">{{ t('hr.stationery.manage_items') }}</UButton>
      <UButton v-if="canWrite" variant="soft" icon="i-heroicons-arrow-down-tray" @click="openReceive">{{ t('hr.stationery.receive_stock') }}</UButton>
      <UButton v-if="canWrite" icon="i-heroicons-arrow-up-tray" @click="openIssue">{{ t('hr.stationery.issue_to_employee') }}</UButton>
    </PageHeader>

    <div class="grid grid-cols-3 gap-4 mb-6">
      <StatCard :label="t('hr.stationery.stats.items')" :value="String(rows.length)" />
      <StatCard :label="t('hr.stationery.stats.stock_value')" :value="money(totalValue)" />
      <StatCard :label="t('hr.stationery.stats.below_reorder')" :value="String(lowStockCount)" :tone="lowStockCount > 0 ? 'red' : 'default'" />
    </div>

    <UCard class="mb-6" :loading="loading">
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('hr.stationery.current_stock.title') }}</p></template>
      <UTable
        :rows="rows"
        :columns="columns"
      >
        <template #qty-data="{ row }">
          <span class="num font-medium" :class="row.qty <= row.reorder_level ? 'text-red-600 dark:text-red-400' : ''">{{ row.qty }}</span>
        </template>
        <template #value-data="{ row }"><span class="num">{{ money(row.value) }}</span></template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('hr.stationery.current_stock.empty_prefix') }} <NuxtLink to="/items" class="text-amber-500 hover:underline">{{ t('hr.stationery.current_stock.empty_link') }}</NuxtLink> {{ t('hr.stationery.current_stock.empty_suffix') }}</div>
        </template>
      </UTable>
    </UCard>

    <div class="grid grid-cols-2 gap-4 mb-6">
      <UCard :loading="loading">
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('hr.stationery.recent_receipts.title') }}</p></template>
        <div v-if="!receipts.length" class="text-sm text-gray-400 py-3 text-center">{{ t('hr.stationery.recent_receipts.none') }}</div>
        <div v-for="r in receipts" :key="r.id" class="flex justify-between items-center py-1.5 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
          <span><span class="num text-xs text-gray-400 mr-2">{{ r.receipt_date }}</span>{{ r.items?.sku }} — <span class="num">{{ r.qty }}</span> @ ৳{{ r.unit_cost }}</span>
          <span class="flex items-center gap-1">
            <span class="num text-gray-500">{{ r.receipt_no }}</span>
            <UButton v-if="canWrite" icon="i-heroicons-trash" color="red" variant="ghost" size="xs" @click="removeReceipt(r)" />
          </span>
        </div>
      </UCard>
      <UCard :loading="loading">
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('hr.stationery.recent_issues.title') }}</p></template>
        <div v-if="!issues.length" class="text-sm text-gray-400 py-3 text-center">{{ t('hr.stationery.recent_issues.none') }}</div>
        <div v-for="r in issues" :key="r.id" class="flex justify-between items-center py-1.5 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
          <span><span class="num text-xs text-gray-400 mr-2">{{ r.issue_date }}</span>{{ r.items?.sku }} — <span class="num">{{ r.qty }}</span> → {{ r.employees?.full_name }}</span>
          <span class="flex items-center gap-1">
            <span class="num text-gray-500">{{ r.issue_no }}</span>
            <UButton v-if="canWrite" icon="i-heroicons-trash" color="red" variant="ghost" size="xs" @click="removeIssue(r)" />
          </span>
        </div>
      </UCard>
    </div>

    <UCard :loading="loading">
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('hr.stationery.usage_by_person.title') }}</p></template>
      <UTable
        :rows="usage"
        :columns="usageColumns"
      >
        <template #full_name-data="{ row }">
          <NuxtLink :to="`/hr/${row.employee_id}`" class="hover:underline text-amber-600 dark:text-amber-400">{{ row.full_name }}</NuxtLink>
        </template>
        <template #total_cost-data="{ row }"><span class="num font-medium">{{ money(row.total_cost) }}</span></template>
        <template #empty-state><div class="text-center py-6 text-sm text-gray-400">{{ t('hr.stationery.usage_by_person.empty') }}</div></template>
      </UTable>
    </UCard>

    <USlideover v-model="receiveOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('hr.stationery.receive_form.title') }}</p></template>
        <div class="space-y-3">
          <UFormGroup :label="t('hr.stationery.receive_form.date')"><UInput v-model="receiveForm.receipt_date" type="date" /></UFormGroup>
          <UFormGroup :label="t('hr.stationery.receive_form.item')" required>
            <USelect v-model="receiveForm.item_id" :options="items" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <div class="grid grid-cols-2 gap-3">
            <UFormGroup :label="t('hr.stationery.receive_form.qty')"><UInput v-model.number="receiveForm.qty" type="number" /></UFormGroup>
            <UFormGroup :label="t('hr.stationery.receive_form.unit_cost')"><UInput v-model.number="receiveForm.unit_cost" type="number" /></UFormGroup>
          </div>
          <UFormGroup :label="t('hr.stationery.receive_form.supplier')" :hint="t('hr.stationery.receive_form.supplier_hint')">
            <USelect v-model="receiveForm.party_id" :options="parties" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup :label="t('hr.stationery.receive_form.paid_from_account')" :hint="t('hr.stationery.receive_form.paid_from_account_hint')">
            <USelect v-model="receiveForm.cash_bank_account_id" :options="cashBankAccounts" option-attribute="name" value-attribute="id" :placeholder="t('hr.stationery.receive_form.on_credit_placeholder')" />
          </UFormGroup>
          <UFormGroup :label="t('hr.stationery.receive_form.reference_no')" :hint="t('hr.stationery.receive_form.reference_no_hint')"><UInput v-model="receiveForm.reference_no" /></UFormGroup>
          <UFormGroup :label="t('hr.stationery.receive_form.note')"><UInput v-model="receiveForm.note" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="receiveOpen = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="savingReceive" @click="saveReceive">{{ t('hr.stationery.receive_form.receive_button') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="issueOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('hr.stationery.issue_form.title') }}</p></template>
        <div class="space-y-3">
          <UFormGroup :label="t('hr.stationery.issue_form.date')"><UInput v-model="issueForm.issue_date" type="date" /></UFormGroup>
          <UFormGroup :label="t('hr.stationery.issue_form.item')" required>
            <USelect v-model="issueForm.item_id" :options="items" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup :label="t('hr.stationery.issue_form.employee')" required>
            <USelect v-model="issueForm.employee_id" :options="employees" option-attribute="full_name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup :label="t('hr.stationery.issue_form.qty')"><UInput v-model.number="issueForm.qty" type="number" /></UFormGroup>
          <UFormGroup :label="t('hr.stationery.issue_form.note')"><UInput v-model="issueForm.note" :placeholder="t('hr.stationery.issue_form.note_placeholder')" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="issueOpen = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="savingIssue" @click="saveIssue">{{ t('hr.stationery.issue_form.issue_button') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
