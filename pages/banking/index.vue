<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()

const facilities = ref<any[]>([])
const bills = ref<any[]>([])
const disbursements = ref<any[]>([])
const banks = ref<any[]>([])
const cashBankAccounts = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [f, b, d, bk, cba] = await Promise.all([
    client.from('bank_facilities').select('*, parties(name)').order('created_at'),
    client.from('bills').select('*, lcs(lc_no), invoices(invoice_no)').order('created_at', { ascending: false }),
    client.from('lbpd_disbursements').select('*, bills(bill_no, amount)').order('created_at', { ascending: false }),
    client.from('parties').select('id, name').eq('is_bank', true).order('name'),
    client.from('cash_bank_accounts').select('id, name').eq('kind', 'bank').eq('is_active', true).order('name')
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
  if (error) toast.add({ title: 'Facility failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Facility added' }); facOpen.value = false; await load() }
}

// --- Bill actions ---
const acceptBill = async (row: any) => {
  const { error } = await client.rpc('accept_bill', { p_bill_id: row.id } as any)
  if (error) toast.add({ title: 'Acceptance failed', description: error.message, color: 'red' })
  else { toast.add({ title: `${row.bill_no} accepted — maturity set from usance` }); await load() }
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
  if (error) toast.add({ title: 'Disbursement failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'LBPD disbursed — cash in bank' }); discOpen.value = false; await load() }
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
  if (error) toast.add({ title: 'Settlement failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Settled — margin credited, bill realized' }); setOpen.value = false; await load() }
}
const forcePad = async (row: any) => {
  const { error } = await client.rpc('convert_to_forced_pad', { p_disbursement_id: row.id } as any)
  if (error) toast.add({ title: 'Conversion failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Converted to forced PAD (penalty profile)', color: 'amber' }); await load() }
}

const billColor = (s: string) =>
  ({ submitted: 'gray', accepted: 'blue', discounted: 'purple', realized: 'green', overdue: 'red' } as any)[s] || 'gray'
const disbColor = (s: string) =>
  ({ open: 'blue', settled: 'green', forced_pad: 'red' } as any)[s] || 'gray'
</script>

<template>
  <div>
    <PageHeader kicker="Finance" title="Banking / LBPD" subtitle="Facilities → bill acceptance → discounting → maturity settlement (or forced PAD)">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="facOpen = true">New facility</UButton>
    </PageHeader>

    <UCard class="mb-6">
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Facilities</p></template>
      <UTable
        :rows="facilities" :loading="loading"
        :columns="[
          { key: 'name', label: 'Facility' }, { key: 'bank', label: 'Bank' },
          { key: 'facility_type', label: 'Type' }, { key: 'limit_amount', label: 'Limit (৳)' },
          { key: 'exposure', label: 'Exposure (৳)' }, { key: 'interest_rate', label: 'Rate %' }
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
        <template #empty-state><div class="text-center py-4 text-sm text-gray-400">No facilities.</div></template>
      </UTable>
    </UCard>

    <UCard class="mb-6">
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Bills under LC</p></template>
      <UTable
        :rows="bills" :loading="loading"
        :columns="[
          { key: 'bill_no', label: 'Bill' }, { key: 'invoice', label: 'Invoice' },
          { key: 'lc', label: 'LC' }, { key: 'amount', label: 'Amount (৳)' },
          { key: 'maturity_date', label: 'Maturity' }, { key: 'status', label: 'Status' },
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
            <UButton v-if="canWrite && row.status === 'submitted'" size="xs" variant="soft" @click="acceptBill(row)">Accept</UButton>
            <UButton v-if="canWrite && row.status === 'accepted'" size="xs" variant="soft" color="purple" @click="openDiscount(row)">Discount (LBPD)</UButton>
          </div>
        </template>
        <template #empty-state><div class="text-center py-4 text-sm text-gray-400">No bills submitted.</div></template>
      </UTable>
    </UCard>

    <UCard>
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">LBPD disbursements</p></template>
      <UTable
        :rows="disbursements" :loading="loading"
        :columns="[
          { key: 'bill', label: 'Bill' }, { key: 'principal', label: 'Advance (৳)' },
          { key: 'advance_pct', label: '%' }, { key: 'disbursed_at', label: 'Disbursed' },
          { key: 'status', label: 'Status' }, { key: 'actions', label: '' }
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
            <UButton v-if="canWrite && row.status !== 'settled'" size="xs" variant="soft" color="green" @click="openSettle(row)">Settle</UButton>
            <UButton v-if="canWrite && row.status === 'open'" size="xs" variant="soft" color="red" @click="forcePad(row)">Forced PAD</UButton>
          </div>
        </template>
        <template #empty-state><div class="text-center py-4 text-sm text-gray-400">No disbursements.</div></template>
      </UTable>
    </UCard>

    <USlideover v-model="facOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New bank facility</p></template>
        <div class="grid grid-cols-2 gap-4">
          <UFormGroup label="Bank" required>
            <USelect v-model="facForm.bank_party_id" :options="banks" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup label="Name" required><UInput v-model="facForm.name" /></UFormGroup>
          <UFormGroup label="Type">
            <USelect v-model="facForm.facility_type" :options="['lbpd', 'od', 'cc', 'term']" />
          </UFormGroup>
          <UFormGroup label="Limit (৳)"><UInput v-model.number="facForm.limit_amount" type="number" /></UFormGroup>
          <UFormGroup label="Interest rate % (annual)"><UInput v-model.number="facForm.interest_rate" type="number" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="facOpen = false">Cancel</UButton>
            <UButton @click="saveFacility">Add facility</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="discOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">Discount {{ discTarget?.bill_no }} <span class="num text-amber-500">(৳{{ Number(discTarget?.amount).toLocaleString('en-IN') }})</span></p></template>
        <div class="space-y-4">
          <UFormGroup label="Facility" required>
            <USelect v-model="discForm.facility_id" :options="facilities" option-attribute="name" value-attribute="id" />
          </UFormGroup>
          <UFormGroup label="Advance %" hint="80–90% typical">
            <UInput v-model.number="discForm.advance_pct" type="number" />
          </UFormGroup>
          <UFormGroup label="Credit to account" hint="which bank account receives the advance">
            <USelect v-model="discForm.cash_bank_account_id" :options="cashBankAccounts" option-attribute="name" value-attribute="id" placeholder="— default bank account —" />
          </UFormGroup>
          <p class="text-sm text-gray-500">
            Cash now: <span class="num font-semibold text-emerald-600 dark:text-emerald-400">৳{{ (Math.round((discTarget?.amount ?? 0) * discForm.advance_pct) / 100).toLocaleString('en-IN') }}</span>
          </p>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="discOpen = false">Cancel</UButton>
            <UButton color="purple" @click="saveDiscount">Disburse</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="setOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header>
          <p class="font-medium">Settle {{ setTarget?.bills?.bill_no }} at maturity</p>
        </template>
        <div class="space-y-4">
          <p class="text-sm text-gray-500">
            Bank remits ৳{{ setTarget?.bills?.amount }} — loan of ৳{{ setTarget?.principal }} closes,
            interest is charged{{ setTarget?.status === 'forced_pad' ? ' at the PENALTY account (5420)' : '' }},
            net margin lands in the bank account.
          </p>
          <UFormGroup label="Interest charged (৳)">
            <UInput v-model.number="setForm.interest" type="number" />
          </UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="setOpen = false">Cancel</UButton>
            <UButton color="green" @click="saveSettle">Settle</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
