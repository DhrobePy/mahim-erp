<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()

const employees = ref<any[]>([])
const loans = ref<any[]>([])
const loading = ref(true)

const columns = [
  { key: 'emp_no', label: 'ID' },
  { key: 'full_name', label: 'Name' },
  { key: 'designation', label: 'Designation' },
  { key: 'joining_date', label: 'Joined' },
  { key: 'basic_salary', label: 'Basic (৳)' },
  { key: 'gross_salary', label: 'Gross (৳)' },
  { key: 'ot_rate', label: 'OT rate/hr' },
  { key: 'actions', label: '' }
]

const load = async () => {
  loading.value = true
  const [e, l] = await Promise.all([
    client.from('employees').select('*').order('emp_no'),
    client.from('employee_loans').select('*, employees(full_name)').order('created_at', { ascending: false })
  ])
  employees.value = e.data ?? []
  loans.value = l.data ?? []
  loading.value = false
}
onMounted(load)

const otRate = (e: any) => Math.round((e.basic_salary / 208) * 2 * 100) / 100

const open = ref(false)
const saving = ref(false)
const blank = () => ({
  id: null as string | null, full_name: '', designation: '', department: '',
  joining_date: new Date().toISOString().slice(0, 10),
  basic_salary: 0, gross_salary: 0, attendance_allowance: 0,
  biometric_id: '', phone: '', nid_no: '', is_active: true
})
const form = reactive(blank())
const openNew = () => { Object.assign(form, blank()); open.value = true }
const openEdit = (row: any) => { Object.assign(form, blank(), row); open.value = true }
const save = async () => {
  saving.value = true
  const payload: any = { ...form }
  delete payload.id; delete payload.company_id; delete payload.emp_no; delete payload.created_at
  try {
    const res = form.id
      ? await client.from('employees').update(payload).eq('id', form.id)
      : await client.from('employees').insert(payload)
    if (res.error) throw res.error
    toast.add({ title: form.id ? 'Employee updated' : 'Employee added' })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: 'Save failed', description: e.message, color: 'red' })
  } finally { saving.value = false }
}

// --- Loan disbursement ---
const loanOpen = ref(false)
const loanForm = reactive({ employee_id: null as string | null, principal: 0, installment: 0, note: '' })
const openLoan = (row?: any) => {
  Object.assign(loanForm, { employee_id: row?.id ?? null, principal: 0, installment: 0, note: '' })
  loanOpen.value = true
}
const saveLoan = async () => {
  const { error } = await client.rpc('disburse_employee_loan', {
    p_employee_id: loanForm.employee_id,
    p_principal: loanForm.principal,
    p_installment: loanForm.installment,
    p_note: loanForm.note || null
  } as any)
  if (error) toast.add({ title: 'Loan failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Loan disbursed & posted' }); loanOpen.value = false; await load() }
}
</script>

<template>
  <div>
    <PageHeader kicker="HR" title="Employees" subtitle="OT rate = (basic / 208) × 2 per BLA 2006; loans capped at 6 × basic">
      <UButton v-if="canWrite" variant="soft" icon="i-heroicons-banknotes" @click="openLoan()">Disburse loan</UButton>
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New employee</UButton>
    </PageHeader>

    <UCard class="mb-6">
      <UTable :rows="employees" :columns="columns" :loading="loading">
        <template #emp_no-data="{ row }">
          <NuxtLink :to="`/hr/${row.id}`" class="num text-amber-600 dark:text-amber-400 hover:underline">{{ row.emp_no }}</NuxtLink>
        </template>
        <template #full_name-data="{ row }">
          <NuxtLink :to="`/hr/${row.id}`" class="hover:underline dark:text-zinc-200">{{ row.full_name }}</NuxtLink>
        </template>
        <template #basic_salary-data="{ row }"><span class="num">{{ Number(row.basic_salary).toLocaleString('en-IN') }}</span></template>
        <template #gross_salary-data="{ row }"><span class="num font-medium dark:text-zinc-100">{{ Number(row.gross_salary).toLocaleString('en-IN') }}</span></template>
        <template #ot_rate-data="{ row }"><span class="num text-amber-600 dark:text-amber-400">৳{{ otRate(row) }}</span></template>
        <template #actions-data="{ row }">
          <UButton v-if="canWrite" icon="i-heroicons-pencil-square" color="gray" variant="ghost" size="xs" @click="openEdit(row)" />
        </template>
        <template #empty-state><div class="text-center py-6 text-sm text-gray-400">No employees yet.</div></template>
      </UTable>
    </UCard>

    <UCard>
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Employee loans — amortised via payroll</p></template>
      <UTable
        :rows="loans"
        :columns="[
          { key: 'loan_no', label: 'Loan' }, { key: 'employee', label: 'Employee' },
          { key: 'principal', label: 'Principal (৳)' }, { key: 'monthly_installment', label: 'Installment' },
          { key: 'balance', label: 'Balance' }, { key: 'status', label: 'Status' }
        ]"
      >
        <template #employee-data="{ row }">
          <NuxtLink :to="`/hr/${row.employee_id}`" class="hover:underline">{{ row.employees?.full_name }}</NuxtLink>
        </template>
        <template #principal-data="{ row }"><span class="num">{{ Number(row.principal).toLocaleString('en-IN') }}</span></template>
        <template #monthly_installment-data="{ row }"><span class="num">{{ Number(row.monthly_installment).toLocaleString('en-IN') }}</span></template>
        <template #balance-data="{ row }"><span class="num font-medium text-amber-600 dark:text-amber-400">{{ Number(row.balance).toLocaleString('en-IN') }}</span></template>
        <template #status-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="row.status === 'active' ? 'blue' : 'green'">{{ row.status }}</UBadge>
        </template>
        <template #empty-state><div class="text-center py-4 text-sm text-gray-400">No loans.</div></template>
      </UTable>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ form.id ? 'Edit employee' : 'New employee' }}</p></template>
        <div class="grid grid-cols-2 gap-4">
          <UFormGroup label="Full name" required class="col-span-2"><UInput v-model="form.full_name" /></UFormGroup>
          <UFormGroup label="Designation"><UInput v-model="form.designation" /></UFormGroup>
          <UFormGroup label="Department"><UInput v-model="form.department" /></UFormGroup>
          <UFormGroup label="Joining date"><UInput v-model="form.joining_date" type="date" /></UFormGroup>
          <UFormGroup label="Biometric ID"><UInput v-model="form.biometric_id" /></UFormGroup>
          <UFormGroup label="Basic salary (৳)"><UInput v-model.number="form.basic_salary" type="number" /></UFormGroup>
          <UFormGroup label="Gross salary (৳)"><UInput v-model.number="form.gross_salary" type="number" /></UFormGroup>
          <UFormGroup label="Attendance allowance (৳/mo)"><UInput v-model.number="form.attendance_allowance" type="number" /></UFormGroup>
          <UFormGroup label="Phone"><UInput v-model="form.phone" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">Cancel</UButton>
            <UButton :loading="saving" @click="save">Save</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="loanOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">Disburse employee loan</p></template>
        <div class="space-y-4">
          <UFormGroup label="Employee" required>
            <USelect v-model="loanForm.employee_id" :options="employees.filter(e => e.is_active)" option-attribute="full_name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup label="Principal (৳)" hint="max 6 × basic"><UInput v-model.number="loanForm.principal" type="number" /></UFormGroup>
          <UFormGroup label="Monthly installment (৳)"><UInput v-model.number="loanForm.installment" type="number" /></UFormGroup>
          <UFormGroup label="Note"><UInput v-model="loanForm.note" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="loanOpen = false">Cancel</UButton>
            <UButton @click="saveLoan">Disburse (Dr 1240 / Cr 1100)</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
