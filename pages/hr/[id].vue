<script setup lang="ts">
const route = useRoute()
const client = useSupabaseClient()
const { money, num } = useFmt()

const id = route.params.id as string
const emp = ref<any>(null)
const att = ref<any[]>([])
const loans = ref<any[]>([])
const payslips = ref<any[]>([])
const loading = ref(true)

const monthStart = () => {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`
}

const load = async () => {
  loading.value = true
  const [e, a, l, p] = await Promise.all([
    client.from('employees').select('*').eq('id', id).single(),
    client.from('attendance').select('att_date, status, ot_hours, is_late').eq('employee_id', id).gte('att_date', monthStart()).order('att_date', { ascending: false }),
    client.from('employee_loans').select('*').eq('employee_id', id).order('created_at', { ascending: false }),
    client.from('payroll_lines').select('*, payroll_runs(run_no, label, status, run_type)').eq('employee_id', id).order('id', { ascending: false }).limit(12)
  ])
  emp.value = e.data
  att.value = a.data ?? []
  loans.value = l.data ?? []
  payslips.value = p.data ?? []
  loading.value = false
}
onMounted(load)

const present = computed(() => att.value.filter((a) => a.status === 'present').length)
const absent = computed(() => att.value.filter((a) => a.status === 'absent').length)
const otHours = computed(() => att.value.reduce((s, a) => s + Number(a.ot_hours), 0))
const otRate = computed(() => emp.value ? Math.round((emp.value.basic_salary / 208) * 2 * 100) / 100 : 0)
const tenure = computed(() => {
  if (!emp.value) return ''
  const j = new Date(emp.value.joining_date)
  const months = (Date.now() - j.getTime()) / (30.44 * 24 * 3600 * 1000)
  return months >= 12 ? `${Math.floor(months / 12)}y ${Math.floor(months % 12)}m` : `${Math.floor(months)}m`
})
</script>

<template>
  <div v-if="emp">
    <PageHeader
      kicker="HR"
      :title="`${emp.emp_no} · ${emp.full_name}`"
      :subtitle="`${emp.designation || '—'}${emp.department ? ' · ' + emp.department : ''} · joined ${emp.joining_date} (${tenure})`"
    >
      <UBadge variant="subtle" :color="emp.is_active ? 'green' : 'red'">{{ emp.is_active ? 'active' : 'inactive' }}</UBadge>
    </PageHeader>

    <div class="grid grid-cols-2 lg:grid-cols-5 gap-3 mb-4">
      <StatCard label="Basic" :value="money(emp.basic_salary)" />
      <StatCard label="Gross" :value="money(emp.gross_salary)" />
      <StatCard label="OT rate/hr (BLA)" :value="money(otRate)" tone="amber" />
      <StatCard label="This month" :value="`${present}P / ${absent}A`" :tone="absent ? 'red' : 'green'" />
      <StatCard label="OT this month" :value="num(otHours, 1) + 'h'" />
    </div>

    <div class="grid grid-cols-1 xl:grid-cols-2 gap-4">
      <div class="space-y-4">
        <UCard>
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Payslip history</p></template>
          <div v-if="!payslips.length" class="text-sm text-gray-400 py-3 text-center">No payroll runs yet.</div>
          <div v-for="p in payslips" :key="p.id" class="flex justify-between py-1.5 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
            <span>
              <NuxtLink to="/hr/payroll" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ p.payroll_runs?.run_no }}</NuxtLink>
              <span class="text-gray-500 dark:text-zinc-500 ml-2">{{ p.payroll_runs?.label }}</span>
              <UBadge v-if="p.payroll_runs?.run_type === 'festival_bonus'" size="xs" variant="subtle" color="purple" class="ml-1">bonus</UBadge>
            </span>
            <span class="num font-medium dark:text-zinc-100">{{ money(p.net_pay) }}</span>
          </div>
        </UCard>

        <UCard v-if="loans.length">
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Loans</p></template>
          <div v-for="l in loans" :key="l.id" class="flex justify-between py-1.5 text-[13px]">
            <span class="num">{{ l.loan_no }} · {{ l.status }}</span>
            <span class="num">bal <span class="text-amber-600 dark:text-amber-400 font-medium">{{ money(l.balance) }}</span> / {{ money(l.principal) }} @ {{ money(l.monthly_installment) }}/mo</span>
          </div>
        </UCard>
      </div>

      <UCard>
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Attendance this month</p></template>
        <div v-if="!att.length" class="text-sm text-gray-400 py-3 text-center">No records this month.</div>
        <div v-for="a in att" :key="a.att_date" class="flex justify-between py-1 text-[12.5px]">
          <span class="num text-gray-500 dark:text-zinc-500">{{ a.att_date }}</span>
          <span class="flex items-center gap-2">
            <span v-if="a.is_late" class="microlabel text-amber-600 dark:text-amber-400">late</span>
            <span v-if="Number(a.ot_hours)" class="num text-purple-500 dark:text-purple-400">+{{ a.ot_hours }}h OT</span>
            <UBadge size="xs" variant="subtle" :color="a.status === 'present' ? 'green' : a.status === 'absent' ? 'red' : 'gray'">{{ a.status }}</UBadge>
          </span>
        </div>
      </UCard>
    </div>
  </div>
  <div v-else-if="!loading" class="text-sm text-gray-400 py-10 text-center">Employee not found.</div>
</template>
