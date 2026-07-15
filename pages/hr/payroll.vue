<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite, activeCompanyId } = useProfile()

const runs = ref<any[]>([])
const loading = ref(true)
const now = new Date()
const genForm = reactive({ year: now.getFullYear(), month: now.getMonth() + 1 })
const bonusForm = reactive({ year: now.getFullYear(), month: now.getMonth() + 1, label: '' })

const load = async () => {
  loading.value = true
  const { data } = await client.from('payroll_runs')
    .select('*, payroll_lines(id, employee_id, basic, gross, days_present, days_absent, ot_hours, ot_amount, attendance_allowance, absence_deduction, loan_recovery, net_pay, employees(emp_no, full_name))')
    .order('created_at', { ascending: false })
  runs.value = data ?? []
  loading.value = false
}
onMounted(load)

const generate = async () => {
  const { error } = await client.rpc('generate_payroll', {
    p_company: activeCompanyId.value, p_year: genForm.year, p_month: genForm.month
  } as any)
  if (error) toast.add({ title: 'Generation failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Payroll generated (draft)' }); await load() }
}

const generateBonus = async () => {
  if (!bonusForm.label) { toast.add({ title: 'Give the bonus a label (e.g. Eid-ul-Fitr 2026)', color: 'red' }); return }
  const { error } = await client.rpc('generate_festival_bonus', {
    p_company: activeCompanyId.value, p_year: bonusForm.year,
    p_month: bonusForm.month, p_label: bonusForm.label
  } as any)
  if (error) toast.add({ title: 'Bonus failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Festival bonus generated (tenure-prorated)' }); await load() }
}

const post = async (row: any) => {
  const { error } = await client.rpc('post_payroll', { p_run_id: row.id } as any)
  if (error) toast.add({ title: 'Posting failed', description: error.message, color: 'red' })
  else { toast.add({ title: `${row.run_no} posted to GL — loans amortised` }); await load() }
}
const pay = async (row: any) => {
  const { error } = await client.rpc('pay_payroll', { p_run_id: row.id } as any)
  if (error) toast.add({ title: 'Payment failed', description: error.message, color: 'red' })
  else { toast.add({ title: `${row.run_no} paid (Dr 2200 / Cr 1100)` }); await load() }
}

const expanded = ref<string | null>(null)
const statusColor = (s: string) => ({ draft: 'yellow', posted: 'blue', paid: 'green' } as any)[s] || 'gray'
</script>

<template>
  <div>
    <PageHeader kicker="HR" title="Payroll" subtitle="Generate → post to GL → pay. Bonus runs prorate on tenure." />

    <div v-if="canWrite" class="grid md:grid-cols-2 gap-4 mb-6">
      <UCard>
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Monthly payroll</p></template>
        <div class="flex items-end gap-2">
          <UFormGroup label="Year"><UInput v-model.number="genForm.year" type="number" class="w-24" /></UFormGroup>
          <UFormGroup label="Month"><UInput v-model.number="genForm.month" type="number" min="1" max="12" class="w-20" /></UFormGroup>
          <UButton @click="generate">Generate</UButton>
        </div>
      </UCard>
      <UCard>
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Festival bonus</p></template>
        <div class="flex items-end gap-2">
          <UFormGroup label="Year"><UInput v-model.number="bonusForm.year" type="number" class="w-24" /></UFormGroup>
          <UFormGroup label="Month"><UInput v-model.number="bonusForm.month" type="number" min="1" max="12" class="w-20" /></UFormGroup>
          <UFormGroup label="Label" class="flex-1"><UInput v-model="bonusForm.label" placeholder="Eid-ul-Fitr 2026" /></UFormGroup>
          <UButton color="purple" @click="generateBonus">Generate</UButton>
        </div>
      </UCard>
    </div>

    <UCard>
      <div class="divide-y divide-gray-100 dark:divide-zinc-800/60">
        <div v-for="r in runs" :key="r.id" class="py-3">
          <div class="flex items-center justify-between">
            <button class="text-left cursor-pointer" @click="expanded = expanded === r.id ? null : r.id">
              <span class="num text-sm font-medium text-amber-600 dark:text-amber-400">{{ r.run_no }}</span>
              <span class="text-sm text-gray-500 dark:text-zinc-400 ml-2">{{ r.label }}</span>
              <UBadge v-if="r.run_type === 'festival_bonus'" size="xs" variant="subtle" color="purple" class="ml-2">bonus</UBadge>
              <span class="text-xs text-gray-500 dark:text-zinc-500 ml-3">net <span class="num font-semibold text-gray-900 dark:text-zinc-100">৳{{ Number(r.total_net).toLocaleString('en-IN') }}</span></span>
            </button>
            <div class="flex items-center gap-2">
              <UBadge size="xs" variant="subtle" :color="statusColor(r.status)">{{ r.status }}</UBadge>
              <UButton v-if="canWrite && r.status === 'draft'" size="xs" variant="soft" @click="post(r)">Post to GL</UButton>
              <UButton v-if="canWrite && r.status === 'posted'" size="xs" variant="soft" color="green" @click="pay(r)">Pay</UButton>
            </div>
          </div>
          <div v-if="expanded === r.id" class="mt-3 overflow-x-auto">
            <table class="w-full text-xs">
              <thead class="text-gray-400 text-left">
                <tr>
                  <th class="py-1 pr-2">Employee</th><th class="pr-2">Present</th><th class="pr-2">Absent</th>
                  <th class="pr-2">OT h</th><th class="pr-2">OT ৳</th><th class="pr-2">Allowance</th>
                  <th class="pr-2">Absence ded.</th><th class="pr-2">Loan</th><th class="text-right">Net ৳</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="l in r.payroll_lines" :key="l.id" class="border-t border-gray-50 dark:border-zinc-800/60">
                  <td class="py-1 pr-2 dark:text-zinc-300">{{ l.employees?.emp_no }} {{ l.employees?.full_name }}</td>
                  <td class="pr-2 num">{{ l.days_present }}</td>
                  <td class="pr-2 num">{{ l.days_absent }}</td>
                  <td class="pr-2 num">{{ l.ot_hours }}</td>
                  <td class="pr-2 num">{{ Number(l.ot_amount).toLocaleString('en-IN') }}</td>
                  <td class="pr-2 num">{{ Number(l.attendance_allowance).toLocaleString('en-IN') }}</td>
                  <td class="pr-2 num text-red-600 dark:text-red-400">{{ Number(l.absence_deduction).toLocaleString('en-IN') }}</td>
                  <td class="pr-2 num text-amber-600 dark:text-amber-400">{{ Number(l.loan_recovery).toLocaleString('en-IN') }}</td>
                  <td class="text-right num font-semibold dark:text-zinc-100">{{ Number(l.net_pay).toLocaleString('en-IN') }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <div v-if="!runs.length && !loading" class="text-center py-6 text-sm text-gray-400">
          No payroll runs yet.
        </div>
      </div>
    </UCard>
  </div>
</template>
