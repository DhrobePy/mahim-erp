<script setup lang="ts">
const route = useRoute()
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money } = useFmt()

const accountId = route.params.accountId as string
const account = ref<any>(null)
const glAccountId = ref<string | null>(null)
const stmtLines = ref<any[]>([])
const journalLines = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [{ data: a }, { data: cba }, { data: sl }] = await Promise.all([
    client.from('v_cash_bank_balances').select('*').eq('id', accountId).single(),
    client.from('cash_bank_accounts').select('gl_account_id').eq('id', accountId).single(),
    client.from('bank_statement_lines').select('*').eq('cash_bank_account_id', accountId).order('txn_date', { ascending: false })
  ])
  account.value = a
  glAccountId.value = (cba as any)?.gl_account_id ?? null
  stmtLines.value = sl ?? []

  if (glAccountId.value) {
    const { data: jl } = await client.from('journal_lines')
      .select('id, debit, credit, note, journals(journal_no, journal_date, memo)')
      .eq('account_id', glAccountId.value)
      .order('id', { ascending: false })
    journalLines.value = jl ?? []
  } else {
    journalLines.value = []
  }
  loading.value = false
}
onMounted(load)

const matchedJournalLineIds = computed(() => new Set((stmtLines.value ?? []).filter((l) => l.matched_journal_line_id).map((l) => l.matched_journal_line_id)))
const unmatchedStmtLines = computed(() => stmtLines.value.filter((l) => !l.matched_journal_line_id))
const matchedStmtLines = computed(() => stmtLines.value.filter((l) => l.matched_journal_line_id))
const unmatchedJournalLines = computed(() => journalLines.value.filter((l) => !matchedJournalLineIds.value.has(l.id)))
const journalById = (id: string) => journalLines.value.find((l) => l.id === id)

const selectedStmt = ref<string | null>(null)
const selectedJournal = ref<string | null>(null)
const amountsAlign = computed(() => {
  if (!selectedStmt.value || !selectedJournal.value) return null
  const s = stmtLines.value.find((l) => l.id === selectedStmt.value)
  const j = journalLines.value.find((l) => l.id === selectedJournal.value)
  if (!s || !j) return null
  const sAmt = Number(s.debit) > 0 ? Number(s.debit) : Number(s.credit)
  const jAmt = Number(j.debit) > 0 ? Number(j.debit) : Number(j.credit)
  return Math.abs(sAmt - jAmt) < 0.01
})

const matching = ref(false)
const doMatch = async () => {
  if (!selectedStmt.value || !selectedJournal.value) return
  matching.value = true
  const { error } = await client.rpc('match_statement_line', { p_line_id: selectedStmt.value, p_journal_line_id: selectedJournal.value } as any)
  if (error) toast.add({ title: 'Match failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Matched' }); selectedStmt.value = null; selectedJournal.value = null; await load() }
  matching.value = false
}
const unmatch = async (stmtLineId: string) => {
  const { error } = await client.rpc('match_statement_line', { p_line_id: stmtLineId, p_journal_line_id: null } as any)
  if (error) toast.add({ title: 'Unmatch failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Unmatched' }); await load() }
}

// --- Add statement line(s) ---
const addOpen = ref(false)
const addForm = reactive({ txn_date: new Date().toISOString().slice(0, 10), description: '', debit: 0, credit: 0 })
const openAdd = () => {
  Object.assign(addForm, { txn_date: new Date().toISOString().slice(0, 10), description: '', debit: 0, credit: 0 })
  addOpen.value = true
}
const saving = ref(false)
const saveLine = async () => {
  if (!addForm.debit && !addForm.credit) { toast.add({ title: 'Enter a debit or credit amount', color: 'red' }); return }
  if (addForm.debit && addForm.credit) { toast.add({ title: 'Enter debit OR credit, not both', color: 'red' }); return }
  saving.value = true
  const { error } = await client.from('bank_statement_lines').insert({ cash_bank_account_id: accountId, ...addForm } as any)
  if (error) toast.add({ title: 'Save failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Statement line added' }); await load() }
  saving.value = false
}

const stmtBalance = computed(() => stmtLines.value.reduce((s, l) => s + Number(l.credit) - Number(l.debit), 0))
</script>

<template>
  <div>
    <PageHeader kicker="Finance" :title="`Reconcile — ${account?.name ?? ''}`" subtitle="Enter statement lines, then match each against the corresponding GL journal line">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openAdd">Add statement line</UButton>
    </PageHeader>

    <div v-if="account" class="grid grid-cols-3 gap-4 mb-6">
      <StatCard label="Ledger balance (GL)" :value="money(account.balance)" />
      <StatCard label="Statement balance (entered)" :value="money(stmtBalance)" />
      <StatCard label="Unreconciled lines" :value="String(unmatchedStmtLines.length)" />
    </div>

    <div class="grid grid-cols-2 gap-4">
      <UCard>
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Bank statement — unmatched</p></template>
        <div v-if="!unmatchedStmtLines.length" class="text-sm text-gray-400 py-3 text-center">All statement lines matched.</div>
        <label
          v-for="l in unmatchedStmtLines" :key="l.id"
          class="flex items-center gap-2 py-2 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0 cursor-pointer"
        >
          <input v-model="selectedStmt" type="radio" :value="l.id" class="accent-amber-500">
          <span class="flex-1">
            <span class="num text-xs text-gray-400">{{ l.txn_date }}</span> — {{ l.description || '—' }}
          </span>
          <span class="num" :class="l.credit > 0 ? 'text-emerald-600 dark:text-emerald-400' : 'text-red-600 dark:text-red-400'">
            {{ l.credit > 0 ? '+' : '-' }}{{ money(l.credit > 0 ? l.credit : l.debit) }}
          </span>
        </label>
      </UCard>

      <UCard>
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">GL journal lines — unmatched</p></template>
        <div v-if="!unmatchedJournalLines.length" class="text-sm text-gray-400 py-3 text-center">All journal lines matched.</div>
        <label
          v-for="l in unmatchedJournalLines" :key="l.id"
          class="flex items-center gap-2 py-2 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0 cursor-pointer"
        >
          <input v-model="selectedJournal" type="radio" :value="l.id" class="accent-amber-500">
          <span class="flex-1">
            <span class="num text-xs text-gray-400">{{ l.journals?.journal_date }}</span>
            <span class="num text-xs text-gray-400 ml-1">{{ l.journals?.journal_no }}</span> — {{ l.note || l.journals?.memo }}
          </span>
          <span class="num" :class="l.debit > 0 ? 'text-emerald-600 dark:text-emerald-400' : 'text-red-600 dark:text-red-400'">
            {{ l.debit > 0 ? '+' : '-' }}{{ money(l.debit > 0 ? l.debit : l.credit) }}
          </span>
        </label>
      </UCard>
    </div>

    <div v-if="canWrite && selectedStmt && selectedJournal" class="sticky bottom-4 mt-4 flex justify-center">
      <UCard :ui="{ body: { padding: 'px-4 py-2' } }" class="shadow-lg">
        <div class="flex items-center gap-3">
          <UBadge v-if="amountsAlign === false" size="xs" color="amber" variant="subtle">amounts differ</UBadge>
          <UBadge v-else-if="amountsAlign" size="xs" color="green" variant="subtle">amounts match</UBadge>
          <UButton :loading="matching" @click="doMatch">Match selected pair</UButton>
        </div>
      </UCard>
    </div>

    <UCard class="mt-6">
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Reconciled</p></template>
      <div v-if="!matchedStmtLines.length" class="text-sm text-gray-400 py-3 text-center">Nothing reconciled yet.</div>
      <div v-for="l in matchedStmtLines" :key="l.id" class="flex items-center justify-between py-2 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
        <span>
          <span class="num text-xs text-gray-400">{{ l.txn_date }}</span> — {{ l.description || '—' }}
          <span class="text-xs text-gray-400 mx-1">↔</span>
          <span class="num text-xs text-amber-600 dark:text-amber-400">{{ journalById(l.matched_journal_line_id)?.journals?.journal_no }}</span>
        </span>
        <div class="flex items-center gap-2">
          <span class="num">{{ money(l.credit > 0 ? l.credit : l.debit) }}</span>
          <UButton v-if="canWrite" size="2xs" variant="ghost" color="gray" @click="unmatch(l.id)">Unmatch</UButton>
        </div>
      </div>
    </UCard>

    <USlideover v-model="addOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">Add statement line</p></template>
        <div class="space-y-3">
          <UFormGroup label="Date"><UInput v-model="addForm.txn_date" type="date" /></UFormGroup>
          <UFormGroup label="Description"><UInput v-model="addForm.description" placeholder="as shown on the bank statement" /></UFormGroup>
          <div class="grid grid-cols-2 gap-3">
            <UFormGroup label="Debit (৳)" hint="money out"><UInput v-model.number="addForm.debit" type="number" /></UFormGroup>
            <UFormGroup label="Credit (৳)" hint="money in"><UInput v-model.number="addForm.credit" type="number" /></UFormGroup>
          </div>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="addOpen = false">Close</UButton>
            <UButton :loading="saving" @click="saveLine">Add &amp; continue</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
