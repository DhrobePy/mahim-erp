<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money } = useFmt()

const accounts = ref<any[]>([])
const banks = ref<any[]>([])
const branches = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [a, bk, br] = await Promise.all([
    client.from('v_cash_bank_balances').select('*').order('kind'),
    client.from('parties').select('id, name').eq('is_bank', true).order('name'),
    client.from('bank_branches').select('id, branch_name, bank_party_id').order('branch_name')
  ])
  accounts.value = a.data ?? []
  banks.value = bk.data ?? []
  branches.value = br.data ?? []
  loading.value = false
}
onMounted(load)

const bankAccounts = computed(() => accounts.value.filter((a) => a.kind === 'bank'))
const cashAccounts = computed(() => accounts.value.filter((a) => a.kind === 'cash'))

const open = ref(false)
const saving = ref(false)
const form = reactive({
  kind: 'bank', name: '', bank_party_id: null as string | null, branch_id: null as string | null,
  account_no: '', opening_balance: 0, opening_date: new Date().toISOString().slice(0, 10)
})
const branchesForBank = computed(() => branches.value.filter((b) => b.bank_party_id === form.bank_party_id))
const openNew = () => {
  Object.assign(form, {
    kind: 'bank', name: '', bank_party_id: null, branch_id: null,
    account_no: '', opening_balance: 0, opening_date: new Date().toISOString().slice(0, 10)
  })
  open.value = true
}

const save = async () => {
  if (!form.name) { toast.add({ title: 'Name is required', color: 'red' }); return }
  if (form.kind === 'bank' && !form.bank_party_id) { toast.add({ title: 'Pick a bank', color: 'red' }); return }
  saving.value = true
  try {
    const payload: any = { ...form }
    if (form.kind === 'cash') { payload.bank_party_id = null; payload.branch_id = null }
    const { error } = await client.from('cash_bank_accounts').insert(payload)
    if (error) throw error
    toast.add({ title: 'Account created' })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: 'Save failed', description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div>
    <PageHeader kicker="Finance" title="Bank &amp; cash accounts" subtitle="Every real account gets its own ledger line — the foundation for reconciliation, transfers and cash sales">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New account</UButton>
    </PageHeader>

    <div class="grid grid-cols-1 xl:grid-cols-2 gap-4">
      <UCard>
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Bank accounts</p></template>
        <div v-if="!bankAccounts.length" class="text-sm text-gray-400 py-3 text-center">None yet.</div>
        <NuxtLink
          v-for="a in bankAccounts" :key="a.id" :to="`/accounting/reconcile/${a.id}`"
          class="flex justify-between py-2 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0 hover:bg-gray-50 dark:hover:bg-zinc-900 -mx-1 px-1 rounded"
        >
          <span class="dark:text-zinc-200">
            {{ a.name }} <span class="num text-[11px] text-gray-400 dark:text-zinc-600">{{ a.gl_code }}</span>
            <UBadge v-if="!a.is_active" size="xs" variant="subtle" color="gray" class="ml-1">inactive</UBadge>
          </span>
          <span class="num font-medium">{{ money(a.balance) }}</span>
        </NuxtLink>
      </UCard>

      <UCard>
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Cash points</p></template>
        <div v-if="!cashAccounts.length" class="text-sm text-gray-400 py-3 text-center">None yet.</div>
        <div v-for="a in cashAccounts" :key="a.id" class="flex justify-between py-2 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
          <span class="dark:text-zinc-200">
            {{ a.name }} <span class="num text-[11px] text-gray-400 dark:text-zinc-600">{{ a.gl_code }}</span>
          </span>
          <span class="num font-medium">{{ money(a.balance) }}</span>
        </div>
      </UCard>
    </div>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New account</p></template>
        <div class="space-y-3">
          <UFormGroup label="Kind">
            <div class="flex gap-2">
              <button
                class="px-4 py-1.5 rounded text-sm border cursor-pointer"
                :class="form.kind === 'bank' ? 'border-amber-500 text-amber-600 dark:text-amber-400 bg-amber-50/60 dark:bg-amber-500/10' : 'border-gray-200 dark:border-zinc-700 text-gray-500'"
                @click="form.kind = 'bank'"
              >Bank account</button>
              <button
                class="px-4 py-1.5 rounded text-sm border cursor-pointer"
                :class="form.kind === 'cash' ? 'border-amber-500 text-amber-600 dark:text-amber-400 bg-amber-50/60 dark:bg-amber-500/10' : 'border-gray-200 dark:border-zinc-700 text-gray-500'"
                @click="form.kind = 'cash'"
              >Cash point</button>
            </div>
          </UFormGroup>
          <UFormGroup label="Name" required><UInput v-model="form.name" placeholder="e.g. IBBL Current A/C 1234, or Factory Cash Till" /></UFormGroup>
          <template v-if="form.kind === 'bank'">
            <UFormGroup label="Bank" required>
              <USelect v-model="form.bank_party_id" :options="banks" option-attribute="name" value-attribute="id" placeholder="—" />
            </UFormGroup>
            <UFormGroup label="Branch" hint="optional">
              <USelect v-model="form.branch_id" :options="branchesForBank" option-attribute="branch_name" value-attribute="id" placeholder="—" />
            </UFormGroup>
            <UFormGroup label="Account no."><UInput v-model="form.account_no" /></UFormGroup>
          </template>
          <div class="grid grid-cols-2 gap-3">
            <UFormGroup label="Opening balance (৳)"><UInput v-model.number="form.opening_balance" type="number" /></UFormGroup>
            <UFormGroup label="As of"><UInput v-model="form.opening_date" type="date" /></UFormGroup>
          </div>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">Cancel</UButton>
            <UButton :loading="saving" @click="save">Create</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
