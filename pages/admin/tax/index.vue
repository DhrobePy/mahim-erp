<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money } = useFmt()

const statements = ref<any[]>([])
const directors = ref<any[]>([])
const totalsByStatement = ref<Record<string, any>>({})
const loading = ref(true)

const categoryOptions = [
  { value: 'business_capital', label: 'Business capital', group: 'assets' },
  { value: 'non_agri_property', label: 'Non-agricultural property', group: 'assets' },
  { value: 'agri_property', label: 'Agricultural property', group: 'assets' },
  { value: 'investments', label: 'Investments (shares, FDR, savings certificates)', group: 'assets' },
  { value: 'motor_vehicles', label: 'Motor vehicles', group: 'assets' },
  { value: 'ornaments', label: 'Ornaments / jewellery', group: 'assets' },
  { value: 'furniture_electronics', label: 'Furniture & electronics', group: 'assets' },
  { value: 'cash_bank', label: 'Cash in hand / at bank', group: 'assets' },
  { value: 'other_assets', label: 'Other assets', group: 'assets' },
  { value: 'mortgage_liability', label: 'Mortgage liability', group: 'liabilities' },
  { value: 'bank_loan_liability', label: 'Bank loan liability', group: 'liabilities' },
  { value: 'other_liability', label: 'Other liability', group: 'liabilities' }
]
const categoryLabel: Record<string, string> = Object.fromEntries(categoryOptions.map((o) => [o.value, o.label]))

const load = async () => {
  loading.value = true
  const [s, d, t] = await Promise.all([
    client.from('it10b_statements').select('*, company_directors(full_name)').order('created_at', { ascending: false }),
    client.from('company_directors').select('id, full_name').eq('is_active', true).order('full_name'),
    client.from('v_it10b_totals').select('*')
  ])
  statements.value = s.data ?? []
  directors.value = d.data ?? []
  totalsByStatement.value = Object.fromEntries((t.data ?? []).map((r: any) => [r.statement_id, r]))
  loading.value = false
}
onMounted(load)

const netWealth = (id: string) => {
  const t = totalsByStatement.value[id]
  return t ? Number(t.total_assets || 0) - Number(t.total_liabilities || 0) : 0
}

// --- Create ---
const open = ref(false)
const saving = ref(false)
const form = reactive({
  director_id: null as string | null, individual_name: '', individual_tin: '',
  assessment_year: '', statement_date: new Date().toISOString().slice(0, 10),
  opening_net_wealth: 0, total_income: 0, total_expenditure: 0
})
const lines = ref<any[]>([])
const blankLine = () => ({ category: 'business_capital', description: '', amount: 0 })
const openNew = () => {
  const now = new Date().getFullYear()
  Object.assign(form, {
    director_id: null, individual_name: '', individual_tin: '',
    assessment_year: `${now}-${now + 1}`, statement_date: new Date().toISOString().slice(0, 10),
    opening_net_wealth: 0, total_income: 0, total_expenditure: 0
  })
  lines.value = [blankLine()]
  open.value = true
}

const save = async () => {
  if (!form.director_id && !form.individual_name) {
    toast.add({ title: 'Pick a director or enter an individual name', color: 'red' }); return
  }
  if (!form.assessment_year) { toast.add({ title: 'Assessment year is required', color: 'red' }); return }
  const validLines = lines.value.filter((l) => l.description && l.amount)
  saving.value = true
  try {
    const { data: st, error } = await client.from('it10b_statements').insert({ ...form } as any).select('id').single()
    if (error) throw error
    if (validLines.length) {
      const res = await client.from('it10b_lines').insert(
        validLines.map((l) => ({ ...l, statement_id: (st as any).id })) as any
      )
      if (res.error) throw res.error
    }
    toast.add({ title: 'IT-10B statement created' })
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
    <PageHeader kicker="Admin" title="Tax — IT-10B" subtitle="Wealth statement draft builder, per director/partner and assessment year">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New statement</UButton>
    </PageHeader>

    <div class="mb-4 px-3 py-2 rounded ring-1 ring-amber-500/30 bg-amber-50/40 dark:bg-amber-500/[0.04] text-[12.5px] text-amber-700 dark:text-amber-400">
      Draft preparation aid only — verify figures and the current NBR form version with a registered tax practitioner before filing.
    </div>

    <UCard>
      <UTable
        :rows="statements" :loading="loading"
        :columns="[
          { key: 'who', label: 'Individual' }, { key: 'assessment_year', label: 'Assessment year' },
          { key: 'statement_date', label: 'Date' }, { key: 'net_wealth', label: 'Net wealth (৳)' }, { key: 'actions', label: '' }
        ]"
      >
        <template #who-data="{ row }">{{ row.company_directors?.full_name || row.individual_name }}</template>
        <template #statement_date-data="{ row }"><span class="num">{{ row.statement_date }}</span></template>
        <template #net_wealth-data="{ row }"><span class="num font-medium text-amber-600 dark:text-amber-400">{{ money(netWealth(row.id)) }}</span></template>
        <template #actions-data="{ row }">
          <UButton icon="i-heroicons-printer" size="xs" color="gray" variant="ghost" :to="`/print/it10b/${row.id}`" target="_blank" aria-label="Print" />
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">No IT-10B statements yet.</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-3xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New IT-10B statement</p></template>
        <div class="space-y-4">
          <div class="grid grid-cols-2 gap-3">
            <UFormGroup label="Director / partner">
              <USelect v-model="form.director_id" :options="directors" option-attribute="full_name" value-attribute="id" placeholder="— or enter name below —" />
            </UFormGroup>
            <UFormGroup label="Individual name (if not listed)">
              <UInput v-model="form.individual_name" :disabled="!!form.director_id" />
            </UFormGroup>
            <UFormGroup label="TIN"><UInput v-model="form.individual_tin" /></UFormGroup>
            <UFormGroup label="Assessment year" required><UInput v-model="form.assessment_year" placeholder="2025-2026" /></UFormGroup>
            <UFormGroup label="Statement date"><UInput v-model="form.statement_date" type="date" /></UFormGroup>
            <UFormGroup label="Opening net wealth (৳)"><UInput v-model.number="form.opening_net_wealth" type="number" /></UFormGroup>
            <UFormGroup label="Total income this year (৳)"><UInput v-model.number="form.total_income" type="number" /></UFormGroup>
            <UFormGroup label="Total expenditure this year (৳)"><UInput v-model.number="form.total_expenditure" type="number" /></UFormGroup>
          </div>

          <div>
            <div class="flex items-center justify-between mb-2">
              <p class="microlabel text-gray-400 dark:text-zinc-500">Assets &amp; liabilities</p>
              <UButton size="xs" variant="soft" icon="i-heroicons-plus" @click="lines.push(blankLine())">Add line</UButton>
            </div>
            <div v-for="(l, i) in lines" :key="i" class="grid grid-cols-12 gap-2 mb-2 items-center">
              <USelect v-model="l.category" :options="categoryOptions" option-attribute="label" value-attribute="value" class="col-span-5" />
              <UInput v-model="l.description" placeholder="Description" class="col-span-4" />
              <UInput v-model.number="l.amount" type="number" placeholder="Amount ৳" class="col-span-3" />
            </div>
            <p class="text-[11px] text-gray-400 dark:text-zinc-600">Liability categories (mortgage / bank loan / other) are netted off automatically in the total.</p>
          </div>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">Cancel</UButton>
            <UButton :loading="saving" @click="save">Save</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
