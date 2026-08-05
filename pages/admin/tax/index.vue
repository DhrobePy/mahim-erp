<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money } = useFmt()
const { t } = useI18n()

const statements = ref<any[]>([])
const directors = ref<any[]>([])
const totalsByStatement = ref<Record<string, any>>({})
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [s, d, tot] = await Promise.all([
    client.from('it10b_statements').select('*, company_directors(full_name)').order('created_at', { ascending: false }),
    client.from('company_directors').select('id, full_name').eq('is_active', true).order('full_name'),
    client.from('v_it10b_totals').select('*')
  ])
  statements.value = s.data ?? []
  directors.value = d.data ?? []
  totalsByStatement.value = Object.fromEntries((tot.data ?? []).map((r: any) => [r.statement_id, r]))
  loading.value = false
}
onMounted(load)

const netWealth = (id: string) => {
  const tot = totalsByStatement.value[id]
  return tot ? Number(tot.total_assets || 0) - Number(tot.total_liabilities || 0) : 0
}

const categoryOptions = computed(() => [
  { value: 'business_capital', label: t('admin.tax_index.categories.business_capital'), group: 'assets' },
  { value: 'non_agri_property', label: t('admin.tax_index.categories.non_agri_property'), group: 'assets' },
  { value: 'agri_property', label: t('admin.tax_index.categories.agri_property'), group: 'assets' },
  { value: 'investments', label: t('admin.tax_index.categories.investments'), group: 'assets' },
  { value: 'motor_vehicles', label: t('admin.tax_index.categories.motor_vehicles'), group: 'assets' },
  { value: 'ornaments', label: t('admin.tax_index.categories.ornaments'), group: 'assets' },
  { value: 'furniture_electronics', label: t('admin.tax_index.categories.furniture_electronics'), group: 'assets' },
  { value: 'cash_bank', label: t('admin.tax_index.categories.cash_bank'), group: 'assets' },
  { value: 'other_assets', label: t('admin.tax_index.categories.other_assets'), group: 'assets' },
  { value: 'mortgage_liability', label: t('admin.tax_index.categories.mortgage_liability'), group: 'liabilities' },
  { value: 'bank_loan_liability', label: t('admin.tax_index.categories.bank_loan_liability'), group: 'liabilities' },
  { value: 'other_liability', label: t('admin.tax_index.categories.other_liability'), group: 'liabilities' }
])

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
    toast.add({ title: t('admin.tax_index.validation.director_or_name_required'), color: 'red' }); return
  }
  if (!form.assessment_year) { toast.add({ title: t('admin.tax_index.validation.assessment_year_required'), color: 'red' }); return }
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
    toast.add({ title: t('admin.tax_index.toasts.statement_created') })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('common.save_failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('admin.tax_index.kicker')" :title="t('admin.tax_index.title')" :subtitle="t('admin.tax_index.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('admin.tax_index.new_statement_btn') }}</UButton>
    </PageHeader>

    <div class="mb-4 px-3 py-2 rounded ring-1 ring-amber-500/30 bg-amber-50/40 dark:bg-amber-500/[0.04] text-[12.5px] text-amber-700 dark:text-amber-400">
      {{ t('admin.tax_index.disclaimer') }}
    </div>

    <UCard>
      <UTable
        :rows="statements" :loading="loading"
        :columns="[
          { key: 'who', label: t('admin.tax_index.columns.individual') }, { key: 'assessment_year', label: t('admin.tax_index.columns.assessment_year') },
          { key: 'statement_date', label: t('admin.tax_index.columns.date') }, { key: 'net_wealth', label: t('admin.tax_index.columns.net_wealth') }, { key: 'actions', label: '' }
        ]"
      >
        <template #who-data="{ row }">{{ row.company_directors?.full_name || row.individual_name }}</template>
        <template #statement_date-data="{ row }"><span class="num">{{ row.statement_date }}</span></template>
        <template #net_wealth-data="{ row }"><span class="num font-medium text-amber-600 dark:text-amber-400">{{ money(netWealth(row.id)) }}</span></template>
        <template #actions-data="{ row }">
          <UButton icon="i-heroicons-printer" size="xs" color="gray" variant="ghost" :to="`/print/it10b/${row.id}`" target="_blank" :aria-label="t('admin.tax_index.print_aria')" />
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('admin.tax_index.empty') }}</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-3xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('admin.tax_index.form.title') }}</p></template>
        <div class="space-y-4">
          <div class="grid grid-cols-2 gap-3">
            <UFormGroup :label="t('admin.tax_index.form.director')">
              <USelect v-model="form.director_id" :options="directors" option-attribute="full_name" value-attribute="id" :placeholder="t('admin.tax_index.form.director_placeholder')" />
            </UFormGroup>
            <UFormGroup :label="t('admin.tax_index.form.individual_name')">
              <UInput v-model="form.individual_name" :disabled="!!form.director_id" />
            </UFormGroup>
            <UFormGroup :label="t('admin.tax_index.form.tin')"><UInput v-model="form.individual_tin" /></UFormGroup>
            <UFormGroup :label="t('admin.tax_index.form.assessment_year')" required><UInput v-model="form.assessment_year" :placeholder="t('admin.tax_index.form.assessment_year_placeholder')" /></UFormGroup>
            <UFormGroup :label="t('admin.tax_index.form.statement_date')"><UInput v-model="form.statement_date" type="date" /></UFormGroup>
            <UFormGroup :label="t('admin.tax_index.form.opening_net_wealth')"><UInput v-model.number="form.opening_net_wealth" type="number" /></UFormGroup>
            <UFormGroup :label="t('admin.tax_index.form.total_income')"><UInput v-model.number="form.total_income" type="number" /></UFormGroup>
            <UFormGroup :label="t('admin.tax_index.form.total_expenditure')"><UInput v-model.number="form.total_expenditure" type="number" /></UFormGroup>
          </div>

          <div>
            <div class="flex items-center justify-between mb-2">
              <p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('admin.tax_index.form.assets_liabilities') }}</p>
              <UButton size="xs" variant="soft" icon="i-heroicons-plus" @click="lines.push(blankLine())">{{ t('admin.tax_index.form.add_line') }}</UButton>
            </div>
            <div v-for="(l, i) in lines" :key="i" class="grid grid-cols-12 gap-2 mb-2 items-center">
              <USelect v-model="l.category" :options="categoryOptions" option-attribute="label" value-attribute="value" class="col-span-5" />
              <UInput v-model="l.description" :placeholder="t('admin.tax_index.form.description_placeholder')" class="col-span-4" />
              <UInput v-model.number="l.amount" type="number" :placeholder="t('admin.tax_index.form.amount_placeholder')" class="col-span-3" />
            </div>
            <p class="text-[11px] text-gray-400 dark:text-zinc-600">{{ t('admin.tax_index.form.liability_note') }}</p>
          </div>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ t('admin.tax_index.form.save') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
