<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money } = useFmt()

const computations = ref<any[]>([])
const totalsByComp = ref<Record<string, any>>({})
const loading = ref(true)

const load = async () => {
  loading.value = true
  const { data } = await client.from('company_tax_computations')
    .select('*, company_tax_adjustment_lines(id, adj_type, description, amount)')
    .order('assessment_year', { ascending: false })
  computations.value = data ?? []
  const { data: totals } = await client.from('v_tax_computation_totals').select('*')
  totalsByComp.value = Object.fromEntries((totals ?? []).map((t: any) => [t.computation_id, t]))
  loading.value = false
}
onMounted(load)

const taxable = (row: any) => totalsByComp.value[row.id]?.taxable_income ?? row.net_profit_per_accounts
const taxPayable = (row: any) => Math.max(0, taxable(row)) * Number(row.tax_rate_pct) / 100
const netPayable = (row: any) => taxPayable(row) - Number(row.advance_tax_paid) - Number(row.tds_credit)

// --- New computation ---
const open = ref(false)
const saving = ref(false)
const form = reactive({
  assessment_year: '', net_profit_per_accounts: 0, tax_rate_pct: 27.5,
  advance_tax_paid: 0, tds_credit: 0, notes: ''
})
const openNew = () => {
  Object.assign(form, { assessment_year: '', net_profit_per_accounts: 0, tax_rate_pct: 27.5, advance_tax_paid: 0, tds_credit: 0, notes: '' })
  open.value = true
}
const pullFromPnl = async () => {
  const { data } = await client.from('v_profit_and_loss').select('amount')
  form.net_profit_per_accounts = Math.round(((data ?? []).reduce((s: number, r: any) => s + Number(r.amount), 0)) * 100) / 100
  toast.add({ title: 'Pulled cumulative net profit from posted GL entries' })
}
const pullFromAit = async () => {
  const { data } = await client.from('v_ait_summary').select('*').maybeSingle()
  form.advance_tax_paid = Number(data?.advance_tax_paid ?? 0)
  toast.add({ title: 'Pulled advance tax paid from AIT summary' })
}
const save = async () => {
  if (!form.assessment_year) { toast.add({ title: 'Assessment year is required (e.g. 2025-2026)', color: 'red' }); return }
  saving.value = true
  const { error } = await client.from('company_tax_computations').insert({ ...form } as any)
  if (error) toast.add({ title: 'Save failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Tax computation created' }); open.value = false; await load() }
  saving.value = false
}

// --- Adjustment lines ---
const expanded = ref<string | null>(null)
const lineForm = reactive({ adj_type: 'addback', description: '', amount: 0 })
const addingLine = ref(false)
const addLine = async (computationId: string) => {
  if (!lineForm.description || !lineForm.amount) { toast.add({ title: 'Description and amount are required', color: 'red' }); return }
  addingLine.value = true
  const { error } = await client.from('company_tax_adjustment_lines').insert({ computation_id: computationId, ...lineForm } as any)
  if (error) toast.add({ title: 'Failed', description: error.message, color: 'red' })
  else {
    toast.add({ title: 'Adjustment added' })
    Object.assign(lineForm, { adj_type: 'addback', description: '', amount: 0 })
    await load()
  }
  addingLine.value = false
}
const removeLine = async (id: string) => {
  const { error } = await client.from('company_tax_adjustment_lines').delete().eq('id', id)
  if (error) toast.add({ title: 'Failed', description: error.message, color: 'red' })
  else await load()
}
</script>

<template>
  <div>
    <PageHeader kicker="Admin" title="Corporate tax computation" subtitle="Net profit per accounts → addbacks / deductions → taxable income → tax → less advance tax / TDS → payable. Draft working paper — review with a registered tax practitioner before filing.">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New computation</UButton>
    </PageHeader>

    <UCard :loading="loading">
      <div class="divide-y divide-gray-100 dark:divide-zinc-800/60">
        <div v-for="row in computations" :key="row.id" class="py-3">
          <div class="flex items-center justify-between">
            <button class="text-left cursor-pointer" @click="expanded = expanded === row.id ? null : row.id">
              <span class="num text-sm font-medium text-amber-600 dark:text-amber-400">AY {{ row.assessment_year }}</span>
              <span class="text-xs text-gray-500 dark:text-zinc-500 ml-3">
                taxable <span class="num text-gray-900 dark:text-zinc-100 font-medium">{{ money(taxable(row)) }}</span>
                · tax <span class="num text-gray-900 dark:text-zinc-100 font-medium">{{ money(taxPayable(row)) }}</span>
                · net payable
                <span class="num font-semibold" :class="netPayable(row) >= 0 ? 'text-amber-600 dark:text-amber-400' : 'text-emerald-600 dark:text-emerald-400'">{{ money(netPayable(row)) }}</span>
              </span>
            </button>
            <UButton icon="i-heroicons-printer" size="xs" color="gray" variant="ghost" :to="`/print/taxcomputation/${row.id}`" target="_blank" aria-label="Print" />
          </div>

          <div v-if="expanded === row.id" class="mt-3 space-y-3">
            <table class="w-full text-sm max-w-md">
              <tbody>
                <tr><td class="py-1 text-gray-500">Net profit per accounts</td><td class="text-right num">{{ money(row.net_profit_per_accounts) }}</td></tr>
                <tr v-for="l in row.company_tax_adjustment_lines" :key="l.id" class="text-xs">
                  <td class="py-0.5 pl-3 text-gray-500">
                    {{ l.adj_type === 'addback' ? '+ ' : '− ' }}{{ l.description }}
                    <button v-if="canWrite" class="text-red-400 hover:text-red-500 ml-1 cursor-pointer" @click="removeLine(l.id)">✕</button>
                  </td>
                  <td class="text-right num">{{ money(l.amount) }}</td>
                </tr>
                <tr class="font-semibold border-t border-gray-100 dark:border-zinc-800"><td class="py-1">Taxable income</td><td class="text-right num">{{ money(taxable(row)) }}</td></tr>
                <tr><td class="py-1 text-gray-500">Tax @ {{ row.tax_rate_pct }}%</td><td class="text-right num">{{ money(taxPayable(row)) }}</td></tr>
                <tr><td class="py-1 text-gray-500">Less: advance tax paid</td><td class="text-right num">({{ money(row.advance_tax_paid) }})</td></tr>
                <tr><td class="py-1 text-gray-500">Less: TDS credit</td><td class="text-right num">({{ money(row.tds_credit) }})</td></tr>
                <tr class="font-semibold border-t-2 border-gray-200 dark:border-zinc-700"><td class="py-1">Net tax payable / (refundable)</td><td class="text-right num">{{ money(netPayable(row)) }}</td></tr>
              </tbody>
            </table>

            <div v-if="canWrite" class="flex items-end gap-2 max-w-lg">
              <UFormGroup label="Type">
                <USelect v-model="lineForm.adj_type" :options="[{ value: 'addback', label: 'Addback' }, { value: 'deduction', label: 'Deduction' }]" option-attribute="label" value-attribute="value" />
              </UFormGroup>
              <UFormGroup label="Description" class="flex-1"><UInput v-model="lineForm.description" placeholder="e.g. Depreciation per accounts vs. tax depreciation" /></UFormGroup>
              <UFormGroup label="Amount (৳)"><UInput v-model.number="lineForm.amount" type="number" class="w-32" /></UFormGroup>
              <UButton size="sm" :loading="addingLine" @click="addLine(row.id)">Add</UButton>
            </div>
            <p v-if="row.notes" class="text-xs text-gray-500 italic">{{ row.notes }}</p>
          </div>
        </div>
        <div v-if="!computations.length && !loading" class="text-center py-6 text-sm text-gray-400">No tax computations yet.</div>
      </div>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New tax computation</p></template>
        <div class="space-y-3">
          <UFormGroup label="Assessment year" required hint="e.g. 2025-2026"><UInput v-model="form.assessment_year" /></UFormGroup>
          <UFormGroup label="Net profit per accounts (৳)">
            <div class="flex gap-2">
              <UInput v-model.number="form.net_profit_per_accounts" type="number" class="flex-1" />
              <UButton size="xs" variant="soft" @click="pullFromPnl">Pull from P&amp;L</UButton>
            </div>
          </UFormGroup>
          <UFormGroup label="Tax rate % (annual)"><UInput v-model.number="form.tax_rate_pct" type="number" /></UFormGroup>
          <UFormGroup label="Advance tax (AIT) paid (৳)">
            <div class="flex gap-2">
              <UInput v-model.number="form.advance_tax_paid" type="number" class="flex-1" />
              <UButton size="xs" variant="soft" @click="pullFromAit">Pull from AIT summary</UButton>
            </div>
          </UFormGroup>
          <UFormGroup label="TDS credit (৳)"><UInput v-model.number="form.tds_credit" type="number" /></UFormGroup>
          <UFormGroup label="Notes"><UTextarea v-model="form.notes" :rows="3" /></UFormGroup>
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
