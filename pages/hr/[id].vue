<script setup lang="ts">
const route = useRoute()
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money, num } = useFmt()

const id = route.params.id as string
const emp = ref<any>(null)
const att = ref<any[]>([])
const loans = ref<any[]>([])
const payslips = ref<any[]>([])
const stationeryUsage = ref<any[]>([])
const acrs = ref<any[]>([])
const assistance = ref<any[]>([])
const cashBankAccounts = ref<any[]>([])
const loading = ref(true)

const monthStart = () => {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`
}

const load = async () => {
  loading.value = true
  const [e, a, l, p, si, acr, asst, cba] = await Promise.all([
    client.from('employees').select('*').eq('id', id).single(),
    client.from('attendance').select('att_date, status, ot_hours, is_late').eq('employee_id', id).gte('att_date', monthStart()).order('att_date', { ascending: false }),
    client.from('employee_loans').select('*').eq('employee_id', id).order('created_at', { ascending: false }),
    client.from('payroll_lines').select('*, payroll_runs(run_no, label, status, run_type)').eq('employee_id', id).order('id', { ascending: false }).limit(12),
    client.from('stationery_issues').select('*, items(sku, name)').eq('employee_id', id).order('issue_date', { ascending: false }),
    client.from('employee_acr').select('*').eq('employee_id', id).order('review_year', { ascending: false }),
    client.from('employee_assistance').select('*').eq('employee_id', id).order('created_at', { ascending: false }),
    client.from('cash_bank_accounts').select('id, name').eq('is_active', true).order('name')
  ])
  emp.value = e.data
  att.value = a.data ?? []
  loans.value = l.data ?? []
  payslips.value = p.data ?? []
  stationeryUsage.value = si.data ?? []
  acrs.value = acr.data ?? []
  assistance.value = asst.data ?? []
  cashBankAccounts.value = cba.data ?? []
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
const stationeryTotalCost = computed(() => stationeryUsage.value.reduce((s, r) => s + Number(r.qty) * Number(r.unit_cost), 0))

const gradeColor: Record<string, string> = {
  outstanding: 'green', very_good: 'green', good: 'blue', satisfactory: 'amber', poor: 'red'
}
const gradeLabel: Record<string, string> = {
  outstanding: 'Outstanding', very_good: 'Very good', good: 'Good', satisfactory: 'Satisfactory', poor: 'Poor'
}

// --- New ACR ---
const acrOpen = ref(false)
const savingAcr = ref(false)
const acrForm = reactive({
  review_year: new Date().getFullYear(), reviewing_officer: '',
  job_knowledge_rating: 3, quality_of_work_rating: 3, integrity_rating: 3, punctuality_rating: 3, initiative_rating: 3,
  overall_grade: 'good', strengths: '', areas_of_improvement: '', reporting_officer_remarks: '', employee_remarks: '', status: 'draft'
})
const openAcr = () => {
  Object.assign(acrForm, {
    review_year: new Date().getFullYear(), reviewing_officer: '',
    job_knowledge_rating: 3, quality_of_work_rating: 3, integrity_rating: 3, punctuality_rating: 3, initiative_rating: 3,
    overall_grade: 'good', strengths: '', areas_of_improvement: '', reporting_officer_remarks: '', employee_remarks: '', status: 'draft'
  })
  acrOpen.value = true
}
const saveAcr = async () => {
  savingAcr.value = true
  const { error } = await client.from('employee_acr').insert({ employee_id: id, ...acrForm })
  if (error) toast.add({ title: 'Save failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'ACR saved' }); acrOpen.value = false; await load() }
  savingAcr.value = false
}

// --- New assistance request ---
const assistOpen = ref(false)
const savingAssist = ref(false)
const assistForm = reactive({ assistance_type: 'welfare', amount: 0, reason: '', request_date: new Date().toISOString().slice(0, 10) })
const openAssist = () => {
  Object.assign(assistForm, { assistance_type: 'welfare', amount: 0, reason: '', request_date: new Date().toISOString().slice(0, 10) })
  assistOpen.value = true
}
const saveAssist = async () => {
  if (!assistForm.amount) { toast.add({ title: 'Amount is required', color: 'red' }); return }
  savingAssist.value = true
  const { error } = await client.from('employee_assistance').insert({ employee_id: id, ...assistForm })
  if (error) toast.add({ title: 'Save failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Assistance request created' }); assistOpen.value = false; await load() }
  savingAssist.value = false
}
const approveAssist = async (row: any) => {
  const { error } = await client.from('employee_assistance').update({ status: 'approved' }).eq('id', row.id)
  if (error) toast.add({ title: 'Failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Approved' }); await load() }
}
const rejectAssist = async (row: any) => {
  const { error } = await client.from('employee_assistance').update({ status: 'rejected' }).eq('id', row.id)
  if (error) toast.add({ title: 'Failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Rejected' }); await load() }
}
const payOpen = ref(false)
const payTarget = ref<any>(null)
const payAccount = ref<string | null>(null)
const openPay = (row: any) => { payTarget.value = row; payAccount.value = null; payOpen.value = true }
const confirmPay = async () => {
  const { error } = await client.rpc('pay_employee_assistance', { p_id: payTarget.value.id, p_cash_bank_account_id: payAccount.value } as any)
  if (error) toast.add({ title: 'Payment failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Paid — posted to GL' }); payOpen.value = false; await load() }
}
const assistStatusColor: Record<string, string> = { requested: 'gray', approved: 'blue', paid: 'green', rejected: 'red' }
</script>

<template>
  <div v-if="emp">
    <PageHeader
      kicker="HR"
      :title="`${emp.emp_no} · ${emp.full_name}`"
      :subtitle="`${emp.designation || '—'}${emp.department ? ' · ' + emp.department : ''} · joined ${emp.joining_date} (${tenure})`"
    >
      <UBadge variant="subtle" :color="emp.is_active ? 'green' : 'red'">{{ emp.is_active ? 'active' : 'inactive' }}</UBadge>
      <UButton icon="i-heroicons-document-text" variant="soft" :to="`/print/salarycert/${emp.id}`" target="_blank">Salary certificate</UButton>
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
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Personal information</p></template>
          <table class="w-full text-[13px]">
            <tbody>
              <tr><td class="py-1 text-gray-500 dark:text-zinc-500 w-1/3">Father's name</td><td class="dark:text-zinc-200">{{ emp.father_name || '—' }}</td></tr>
              <tr><td class="py-1 text-gray-500 dark:text-zinc-500">Date of birth</td><td class="num dark:text-zinc-200">{{ emp.date_of_birth || '—' }}</td></tr>
              <tr><td class="py-1 text-gray-500 dark:text-zinc-500">Blood group</td><td class="dark:text-zinc-200">{{ emp.blood_group || '—' }}</td></tr>
              <tr><td class="py-1 text-gray-500 dark:text-zinc-500">Marital status</td><td class="dark:text-zinc-200">{{ emp.marital_status || '—' }}</td></tr>
              <tr><td class="py-1 text-gray-500 dark:text-zinc-500">NID no.</td><td class="num dark:text-zinc-200">{{ emp.nid_no || '—' }}</td></tr>
              <tr><td class="py-1 text-gray-500 dark:text-zinc-500">Phone</td><td class="num dark:text-zinc-200">{{ emp.phone || '—' }}</td></tr>
              <tr><td class="py-1 text-gray-500 dark:text-zinc-500 align-top">Present address</td><td class="dark:text-zinc-200">{{ emp.present_address || '—' }}</td></tr>
              <tr><td class="py-1 text-gray-500 dark:text-zinc-500 align-top">Permanent address</td><td class="dark:text-zinc-200">{{ emp.permanent_address || '—' }}</td></tr>
              <tr><td class="py-1 text-gray-500 dark:text-zinc-500">Emergency contact</td><td class="dark:text-zinc-200">{{ emp.emergency_contact_name || '—' }}{{ emp.emergency_contact_phone ? ' · ' + emp.emergency_contact_phone : '' }}</td></tr>
            </tbody>
          </table>
        </UCard>

        <UCard>
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Payslip history</p></template>
          <div v-if="!payslips.length" class="text-sm text-gray-400 py-3 text-center">No payroll runs yet.</div>
          <div v-for="p in payslips" :key="p.id" class="flex justify-between items-center py-1.5 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
            <span>
              <NuxtLink to="/hr/payroll" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ p.payroll_runs?.run_no }}</NuxtLink>
              <span class="text-gray-500 dark:text-zinc-500 ml-2">{{ p.payroll_runs?.label }}</span>
              <UBadge v-if="p.payroll_runs?.run_type === 'festival_bonus'" size="xs" variant="subtle" color="purple" class="ml-1">bonus</UBadge>
            </span>
            <span class="flex items-center gap-2">
              <span class="num font-medium dark:text-zinc-100">{{ money(p.net_pay) }}</span>
              <UButton icon="i-heroicons-printer" size="2xs" color="gray" variant="ghost" :to="`/print/payslip/${p.id}`" target="_blank" aria-label="Print payslip" />
            </span>
          </div>
        </UCard>

        <UCard v-if="loans.length">
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Loans</p></template>
          <div v-for="l in loans" :key="l.id" class="flex justify-between items-center py-1.5 text-[13px]">
            <span class="num">{{ l.loan_no }} · {{ l.status }}</span>
            <span class="flex items-center gap-2">
              <span class="num">bal <span class="text-amber-600 dark:text-amber-400 font-medium">{{ money(l.balance) }}</span> / {{ money(l.principal) }} @ {{ money(l.monthly_installment) }}/mo</span>
              <UButton icon="i-heroicons-printer" size="2xs" color="gray" variant="ghost" :to="`/print/loanagreement/${l.id}`" target="_blank" aria-label="Print loan agreement" />
            </span>
          </div>
        </UCard>

        <UCard>
          <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Stationery / inventory usage</p></template>
          <div v-if="!stationeryUsage.length" class="text-sm text-gray-400 py-3 text-center">No stationery issued yet.</div>
          <div v-for="s in stationeryUsage" :key="s.id" class="flex justify-between py-1.5 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
            <span><span class="num text-xs text-gray-400 mr-2">{{ s.issue_date }}</span>{{ s.items?.name }} <span class="num text-gray-400">×{{ s.qty }}</span></span>
            <span class="num">{{ money(s.qty * s.unit_cost) }}</span>
          </div>
          <div v-if="stationeryUsage.length" class="flex justify-between pt-2 mt-1 border-t border-gray-200 dark:border-zinc-700 text-[13px] font-semibold">
            <span>Total</span><span class="num text-amber-600 dark:text-amber-400">{{ money(stationeryTotalCost) }}</span>
          </div>
        </UCard>
      </div>

      <div class="space-y-4">
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

        <UCard>
          <template #header>
            <div class="flex items-center justify-between">
              <p class="microlabel text-gray-400 dark:text-zinc-500">Annual Confidential Report (ACR)</p>
              <UButton v-if="canWrite" size="2xs" variant="soft" icon="i-heroicons-plus" @click="openAcr">New ACR</UButton>
            </div>
          </template>
          <div v-if="!acrs.length" class="text-sm text-gray-400 py-3 text-center">No ACR on file yet.</div>
          <div v-for="a in acrs" :key="a.id" class="flex justify-between items-center py-1.5 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
            <span>
              <span class="num font-medium">{{ a.review_year }}</span>
              <UBadge size="xs" variant="subtle" :color="gradeColor[a.overall_grade]" class="ml-2">{{ gradeLabel[a.overall_grade] }}</UBadge>
              <UBadge v-if="a.status === 'draft'" size="xs" variant="subtle" color="gray" class="ml-1">draft</UBadge>
            </span>
            <UButton icon="i-heroicons-printer" size="2xs" color="gray" variant="ghost" :to="`/print/acr/${a.id}`" target="_blank" aria-label="Print ACR" />
          </div>
        </UCard>

        <UCard>
          <template #header>
            <div class="flex items-center justify-between">
              <p class="microlabel text-gray-400 dark:text-zinc-500">Welfare &amp; medical assistance</p>
              <UButton v-if="canWrite" size="2xs" variant="soft" icon="i-heroicons-plus" @click="openAssist">New request</UButton>
            </div>
          </template>
          <div v-if="!assistance.length" class="text-sm text-gray-400 py-3 text-center">No requests on file.</div>
          <div v-for="a in assistance" :key="a.id" class="py-1.5 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
            <div class="flex justify-between items-center">
              <span>
                <span class="num text-amber-600 dark:text-amber-400 font-medium">{{ a.request_no }}</span>
                <UBadge size="xs" variant="subtle" color="gray" class="ml-1">{{ a.assistance_type }}</UBadge>
                <UBadge size="xs" variant="subtle" :color="assistStatusColor[a.status]" class="ml-1">{{ a.status }}</UBadge>
              </span>
              <span class="num font-medium">{{ money(a.amount) }}</span>
            </div>
            <div class="flex justify-between items-center mt-0.5">
              <p class="text-xs text-gray-500 dark:text-zinc-500">{{ a.reason }}</p>
              <div v-if="canWrite" class="flex gap-1">
                <UButton v-if="a.status === 'requested'" size="2xs" variant="soft" color="green" @click="approveAssist(a)">Approve</UButton>
                <UButton v-if="a.status === 'requested'" size="2xs" variant="soft" color="red" @click="rejectAssist(a)">Reject</UButton>
                <UButton v-if="a.status === 'approved'" size="2xs" variant="soft" color="amber" @click="openPay(a)">Pay</UButton>
              </div>
            </div>
          </div>
        </UCard>
      </div>
    </div>

    <USlideover v-model="acrOpen" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New Annual Confidential Report</p></template>
        <div class="space-y-3">
          <div class="grid grid-cols-2 gap-3">
            <UFormGroup label="Review year"><UInput v-model.number="acrForm.review_year" type="number" /></UFormGroup>
            <UFormGroup label="Reviewing officer"><UInput v-model="acrForm.reviewing_officer" /></UFormGroup>
          </div>
          <div class="grid grid-cols-3 gap-3">
            <UFormGroup label="Job knowledge (1-5)"><UInput v-model.number="acrForm.job_knowledge_rating" type="number" min="1" max="5" /></UFormGroup>
            <UFormGroup label="Quality of work (1-5)"><UInput v-model.number="acrForm.quality_of_work_rating" type="number" min="1" max="5" /></UFormGroup>
            <UFormGroup label="Integrity (1-5)"><UInput v-model.number="acrForm.integrity_rating" type="number" min="1" max="5" /></UFormGroup>
            <UFormGroup label="Punctuality (1-5)"><UInput v-model.number="acrForm.punctuality_rating" type="number" min="1" max="5" /></UFormGroup>
            <UFormGroup label="Initiative (1-5)"><UInput v-model.number="acrForm.initiative_rating" type="number" min="1" max="5" /></UFormGroup>
            <UFormGroup label="Overall grade">
              <USelect v-model="acrForm.overall_grade" :options="[
                { value: 'outstanding', label: 'Outstanding' }, { value: 'very_good', label: 'Very good' },
                { value: 'good', label: 'Good' }, { value: 'satisfactory', label: 'Satisfactory' }, { value: 'poor', label: 'Poor' }
              ]" option-attribute="label" value-attribute="value" />
            </UFormGroup>
          </div>
          <UFormGroup label="Strengths"><UTextarea v-model="acrForm.strengths" :rows="2" /></UFormGroup>
          <UFormGroup label="Areas of improvement"><UTextarea v-model="acrForm.areas_of_improvement" :rows="2" /></UFormGroup>
          <UFormGroup label="Reporting officer remarks"><UTextarea v-model="acrForm.reporting_officer_remarks" :rows="2" /></UFormGroup>
          <UFormGroup label="Employee remarks" hint="employee's right of reply"><UTextarea v-model="acrForm.employee_remarks" :rows="2" /></UFormGroup>
          <UFormGroup label="Status">
            <USelect v-model="acrForm.status" :options="[{ value: 'draft', label: 'Draft' }, { value: 'finalized', label: 'Finalized' }]" option-attribute="label" value-attribute="value" />
          </UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="acrOpen = false">Cancel</UButton>
            <UButton :loading="savingAcr" @click="saveAcr">Save</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="assistOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New welfare / medical assistance request</p></template>
        <div class="space-y-3">
          <UFormGroup label="Type">
            <USelect v-model="assistForm.assistance_type" :options="[{ value: 'welfare', label: 'Welfare' }, { value: 'medical', label: 'Medical' }]" option-attribute="label" value-attribute="value" />
          </UFormGroup>
          <UFormGroup label="Date"><UInput v-model="assistForm.request_date" type="date" /></UFormGroup>
          <UFormGroup label="Amount (৳)"><UInput v-model.number="assistForm.amount" type="number" /></UFormGroup>
          <UFormGroup label="Reason"><UTextarea v-model="assistForm.reason" :rows="3" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="assistOpen = false">Cancel</UButton>
            <UButton :loading="savingAssist" @click="saveAssist">Submit</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="payOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header>
          <p class="font-medium">Pay {{ payTarget?.request_no }} <span class="num text-amber-500">(৳{{ Number(payTarget?.amount).toLocaleString('en-IN') }})</span></p>
        </template>
        <div class="space-y-4">
          <UFormGroup label="Pay from account">
            <USelect v-model="payAccount" :options="cashBankAccounts" option-attribute="name" value-attribute="id" placeholder="— default bank account —" />
          </UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="payOpen = false">Cancel</UButton>
            <UButton color="green" @click="confirmPay">Pay</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
  <div v-else-if="!loading" class="text-sm text-gray-400 py-10 text-center">Employee not found.</div>
</template>
