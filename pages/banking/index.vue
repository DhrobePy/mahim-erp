<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const facilities = ref<any[]>([])
const bills = ref<any[]>([])
const disbursements = ref<any[]>([])
const banks = ref<any[]>([])
const cashBankAccounts = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [f, b, d, bk, cba] = await Promise.all([
    client.from('bank_facilities').select('*, parties(name)').is('deleted_at', null).order('created_at'),
    client.from('bills').select('*, lcs(lc_no), invoices(invoice_no)').is('deleted_at', null).order('created_at', { ascending: false }),
    client.from('lbpd_disbursements').select('*, bills(bill_no, amount)').is('deleted_at', null).order('created_at', { ascending: false }),
    client.from('parties').select('id, name').eq('is_bank', true).is('deleted_at', null).order('name'),
    client.from('cash_bank_accounts').select('id, name').eq('kind', 'bank').eq('is_active', true).is('deleted_at', null).order('name')
  ])
  facilities.value = f.data ?? []
  bills.value = b.data ?? []
  disbursements.value = d.data ?? []
  banks.value = bk.data ?? []
  cashBankAccounts.value = cba.data ?? []
  loading.value = false
}
onMounted(load)

const exposure = (fac: any) =>
  disbursements.value
    .filter((d) => d.facility_id === fac.id && ['open', 'forced_pad'].includes(d.status))
    .reduce((s, d) => s + Number(d.principal), 0)

// --- Facility ---
const facOpen = ref(false)
const facForm = reactive({ bank_party_id: null as string | null, name: '', facility_type: 'lbpd', limit_amount: 0, interest_rate: 12 })
const saveFacility = async () => {
  const { error } = await client.from('bank_facilities').insert({ ...facForm } as any)
  if (error) toast.add({ title: t('banking.toasts.facility_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('banking.toasts.facility_added') }); facOpen.value = false; await load() }
}

// --- Bill actions ---
const acceptBill = async (row: any) => {
  const { error } = await client.rpc('accept_bill', { p_bill_id: row.id } as any)
  if (error) toast.add({ title: t('banking.toasts.acceptance_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('banking.toasts.bill_accepted', { bill: row.bill_no }) }); await load() }
}

const discOpen = ref(false)
const discTarget = ref<any>(null)
const discForm = reactive({ facility_id: null as string | null, advance_pct: 85, cash_bank_account_id: null as string | null })
const openDiscount = (row: any) => {
  discTarget.value = row
  Object.assign(discForm, { facility_id: facilities.value[0]?.id ?? null, advance_pct: 85, cash_bank_account_id: null })
  discOpen.value = true
}
const saveDiscount = async () => {
  const { error } = await client.rpc('disburse_lbpd', {
    p_bill_id: discTarget.value.id,
    p_facility_id: discForm.facility_id,
    p_advance_pct: discForm.advance_pct,
    p_cash_bank_account_id: discForm.cash_bank_account_id
  } as any)
  if (error) toast.add({ title: t('banking.toasts.disbursement_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('banking.toasts.lbpd_disbursed') }); discOpen.value = false; await load() }
}

// --- Settlement / forced PAD ---
const setOpen = ref(false)
const setTarget = ref<any>(null)
const setForm = reactive({ interest: 0 })
const openSettle = (row: any) => { setTarget.value = row; setForm.interest = 0; setOpen.value = true }
const saveSettle = async () => {
  const { error } = await client.rpc('settle_lbpd', {
    p_disbursement_id: setTarget.value.id, p_interest: setForm.interest
  } as any)
  if (error) toast.add({ title: t('banking.toasts.settlement_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('banking.toasts.settled') }); setOpen.value = false; await load() }
}
const forcePad = async (row: any) => {
  const { error } = await client.rpc('convert_to_forced_pad', { p_disbursement_id: row.id } as any)
  if (error) toast.add({ title: t('banking.toasts.conversion_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('banking.toasts.converted_forced_pad'), color: 'amber' }); await load() }
}

const removeFacility = async (row: any) => {
  if (await deleteRecord('bank_facilities', row.id, row.name)) await load()
}
const removeBill = async (row: any) => {
  if (await deleteRecord('bills', row.id, row.bill_no)) await load()
}
const removeDisbursement = async (row: any) => {
  if (await deleteRecord('lbpd_disbursements', row.id, row.bills?.bill_no ?? row.id)) await load()
}

const billColor = (s: string) =>
  ({ submitted: 'gray', accepted: 'blue', discounted: 'purple', realized: 'green', overdue: 'red' } as any)[s] || 'gray'
const disbColor = (s: string) =>
  ({ open: 'blue', settled: 'green', forced_pad: 'red' } as any)[s] || 'gray'
</script>

<template>
  <div>
    <PageHeader :kicker="t('banking.kicker')" :title="t('banking.title')" :subtitle="t('banking.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="facOpen = true">{{ t('banking.new_facility') }}</UButton>
    </PageHeader>

    <UCard class="mb-6">
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('banking.facilities.header') }}</p></template>
      <UTable
        :rows="facilities" :loading="loading"
        :columns="[
          { key: 'name', label: t('banking.facilities.columns.facility') }, { key: 'bank', label: t('banking.facilities.columns.bank') },
          { key: 'facility_type', label: t('common.type') }, { key: 'limit_amount', label: t('banking.facilities.columns.limit') },
          { key: 'exposure', label: t('banking.facilities.columns.exposure') }, { key: 'interest_rate', label: t('banking.facilities.columns.rate') },
          { key: 'actions', label: '' }
        ]"
      >
        <template #bank-data="{ row }">
          <NuxtLink :to="`/parties/${row.bank_party_id}`" class="hover:underline">{{ row.parties?.name }}</NuxtLink>
        </template>
        <template #limit_amount-data="{ row }">
          <span class="num">{{ Number(row.limit_amount).toLocaleString('en-IN') }}</span>
        </template>
        <template #exposure-data="{ row }">
          <span class="num font-medium" :class="exposure(row) > row.limit_amount * 0.9 ? 'text-red-600 dark:text-red-400' : 'text-emerald-600 dark:text-emerald-400'">
            {{ exposure(row).toLocaleString('en-IN') }}
          </span>
        </template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton v-if="canWrite" icon="i-heroicons-trash" color="red" variant="ghost" size="xs" @click="removeFacility(row)" />
          </div>
        </template>
        <template #empty-state><div class="text-center py-4 text-sm text-gray-400">{{ t('banking.facilities.empty') }}</div></template>
      </UTable>
    </UCard>

    <UCard class="mb-6">
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('banking.bills.header') }}</p></template>
      <UTable
        :rows="bills" :loading="loading"
        :columns="[
          { key: 'bill_no', label: t('banking.bills.columns.bill') }, { key: 'invoice', label: t('banking.bills.columns.invoice') },
          { key: 'lc', label: t('banking.bills.columns.lc') }, { key: 'amount', label: t('banking.bills.columns.amount') },
          { key: 'maturity_date', label: t('banking.bills.columns.maturity') }, { key: 'status', label: t('common.status') },
          { key: 'actions', label: '' }
        ]"
      >
        <template #bill_no-data="{ row }">
          <span class="num font-medium dark:text-zinc-100">{{ row.bill_no }}</span>
        </template>
        <template #invoice-data="{ row }">
          <NuxtLink :to="`/invoices/${row.invoice_id}`" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ row.invoices?.invoice_no }}</NuxtLink>
        </template>
        <template #lc-data="{ row }">
          <NuxtLink :to="`/lcs/${row.lc_id}`" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ row.lcs?.lc_no }}</NuxtLink>
        </template>
        <template #amount-data="{ row }">
          <span class="num font-semibold text-amber-600 dark:text-amber-400">{{ Number(row.amount).toLocaleString('en-IN') }}</span>
        </template>
        <template #maturity_date-data="{ row }"><span class="num">{{ row.maturity_date || '—' }}</span></template>
        <template #status-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="billColor(row.status)">{{ row.status }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton v-if="canWrite && row.status === 'submitted'" size="xs" variant="soft" @click="acceptBill(row)">{{ t('banking.bills.accept') }}</UButton>
            <UButton v-if="canWrite && row.status === 'accepted'" size="xs" variant="soft" color="purple" @click="openDiscount(row)">{{ t('banking.bills.discount') }}</UButton>
            <UButton v-if="canWrite" icon="i-heroicons-trash" color="red" variant="ghost" size="xs" @click="removeBill(row)" />
          </div>
        </template>
        <template #empty-state><div class="text-center py-4 text-sm text-gray-400">{{ t('banking.bills.empty') }}</div></template>
      </UTable>
    </UCard>

    <UCard>
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('banking.disbursements.header') }}</p></template>
      <UTable
        :rows="disbursements" :loading="loading"
        :columns="[
          { key: 'bill', label: t('banking.disbursements.columns.bill') }, { key: 'principal', label: t('banking.disbursements.columns.advance') },
          { key: 'advance_pct', label: t('banking.disbursements.columns.pct') }, { key: 'disbursed_at', label: t('banking.disbursements.columns.disbursed') },
          { key: 'status', label: t('common.status') }, { key: 'actions', label: '' }
        ]"
      >
        <template #bill-data="{ row }">
          {{ row.bills?.bill_no }} <span class="num text-gray-400 dark:text-zinc-500">(৳{{ Number(row.bills?.amount).toLocaleString('en-IN') }})</span>
        </template>
        <template #principal-data="{ row }">
          <span class="num font-semibold text-amber-600 dark:text-amber-400">{{ Number(row.principal).toLocaleString('en-IN') }}</span>
        </template>
        <template #status-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="disbColor(row.status)">{{ row.status }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton v-if="canWrite && row.status !== 'settled'" size="xs" variant="soft" color="green" @click="openSettle(row)">{{ t('banking.disbursements.settle') }}</UButton>
            <UButton v-if="canWrite && row.status === 'open'" size="xs" variant="soft" color="red" @click="forcePad(row)">{{ t('banking.disbursements.forced_pad') }}</UButton>
            <UButton v-if="canWrite" icon="i-heroicons-trash" color="red" variant="ghost" size="xs" @click="removeDisbursement(row)" />
          </div>
        </template>
        <template #empty-state><div class="text-center py-4 text-sm text-gray-400">{{ t('banking.disbursements.empty') }}</div></template>
      </UTable>
    </UCard>

    <USlideover v-model="facOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('banking.facility_dialog.title') }}</p></template>
        <div class="grid grid-cols-2 gap-4">
          <UFormGroup :label="t('banking.facility_dialog.bank')" required>
            <USelect v-model="facForm.bank_party_id" :options="banks" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup :label="t('common.name')" required><UInput v-model="facForm.name" /></UFormGroup>
          <UFormGroup :label="t('banking.facility_dialog.type')">
            <USelect v-model="facForm.facility_type" :options="['lbpd', 'od', 'cc', 'term']" />
          </UFormGroup>
          <UFormGroup :label="t('banking.facility_dialog.limit')"><UInput v-model.number="facForm.limit_amount" type="number" /></UFormGroup>
          <UFormGroup :label="t('banking.facility_dialog.interest_rate')"><UInput v-model.number="facForm.interest_rate" type="number" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="facOpen = false">{{ t('common.cancel') }}</UButton>
            <UButton @click="saveFacility">{{ t('banking.facility_dialog.add') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="discOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('banking.discount_dialog.title', { bill: discTarget?.bill_no }) }} <span class="num text-amber-500">(৳{{ Number(discTarget?.amount).toLocaleString('en-IN') }})</span></p></template>
        <div class="space-y-4">
          <UFormGroup :label="t('banking.discount_dialog.facility')" required>
            <USelect v-model="discForm.facility_id" :options="facilities" option-attribute="name" value-attribute="id" />
          </UFormGroup>
          <UFormGroup :label="t('banking.discount_dialog.advance_pct')" :hint="t('banking.discount_dialog.advance_pct_hint')">
            <UInput v-model.number="discForm.advance_pct" type="number" />
          </UFormGroup>
          <UFormGroup :label="t('banking.discount_dialog.credit_account')" :hint="t('banking.discount_dialog.credit_account_hint')">
            <USelect v-model="discForm.cash_bank_account_id" :options="cashBankAccounts" option-attribute="name" value-attribute="id" :placeholder="t('banking.discount_dialog.credit_account_placeholder')" />
          </UFormGroup>
          <p class="text-sm text-gray-500">
            {{ t('banking.discount_dialog.cash_now_label') }} <span class="num font-semibold text-emerald-600 dark:text-emerald-400">৳{{ (Math.round((discTarget?.amount ?? 0) * discForm.advance_pct) / 100).toLocaleString('en-IN') }}</span>
          </p>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="discOpen = false">{{ t('common.cancel') }}</UButton>
            <UButton color="purple" @click="saveDiscount">{{ t('banking.discount_dialog.disburse') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="setOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header>
          <p class="font-medium">{{ t('banking.settle_dialog.title', { bill: setTarget?.bills?.bill_no }) }}</p>
        </template>
        <div class="space-y-4">
          <p class="text-sm text-gray-500">
            {{ t('banking.settle_dialog.body', { amount: setTarget?.bills?.amount, principal: setTarget?.principal, penalty: setTarget?.status === 'forced_pad' ? t('banking.settle_dialog.penalty_suffix') : '' }) }}
          </p>
          <UFormGroup :label="t('banking.settle_dialog.interest_charged')">
            <UInput v-model.number="setForm.interest" type="number" />
          </UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="setOpen = false">{{ t('common.cancel') }}</UButton>
            <UButton color="green" @click="saveSettle">{{ t('banking.settle_dialog.settle') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
