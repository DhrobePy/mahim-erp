<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const employees = ref<any[]>([])
const loans = ref<any[]>([])
const cashBankAccounts = ref<any[]>([])
const loading = ref(true)

const columns = computed(() => [
  { key: 'emp_no', label: t('hr.employees.columns.id') },
  { key: 'full_name', label: t('hr.employees.columns.name') },
  { key: 'designation', label: t('hr.employees.columns.designation') },
  { key: 'joining_date', label: t('hr.employees.columns.joined') },
  { key: 'basic_salary', label: t('hr.employees.columns.basic') },
  { key: 'gross_salary', label: t('hr.employees.columns.gross') },
  { key: 'ot_rate', label: t('hr.employees.columns.ot_rate') },
  { key: 'actions', label: '' }
])

const load = async () => {
  loading.value = true
  const [e, l, cba] = await Promise.all([
    client.from('employees').select('*').is('deleted_at', null).order('emp_no'),
    client.from('employee_loans').select('*, employees(full_name)').order('created_at', { ascending: false }),
    client.from('cash_bank_accounts').select('id, name').eq('is_active', true).is('deleted_at', null).order('name')
  ])
  employees.value = e.data ?? []
  loans.value = l.data ?? []
  cashBankAccounts.value = cba.data ?? []
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
  biometric_id: '', phone: '', nid_no: '', is_active: true,
  date_of_birth: null as string | null, blood_group: '', marital_status: '', father_name: '',
  present_address: '', permanent_address: '', emergency_contact_name: '', emergency_contact_phone: ''
})
const form = reactive(blank())
const openNew = () => { Object.assign(form, blank()); open.value = true }
const openEdit = (row: any) => { Object.assign(form, blank(), row); open.value = true }
const removeEmployee = async (row: any) => {
  const ok = await deleteRecord('employees', row.id, row.full_name)
  if (ok) await load()
}
const save = async () => {
  saving.value = true
  const payload: any = { ...form }
  delete payload.id; delete payload.company_id; delete payload.emp_no; delete payload.created_at
  try {
    const res = form.id
      ? await client.from('employees').update(payload).eq('id', form.id)
      : await client.from('employees').insert(payload)
    if (res.error) throw res.error
    toast.add({ title: form.id ? t('hr.employees.toast.employee_updated') : t('hr.employees.toast.employee_added') })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('hr.employees.toast.save_failed'), description: e.message, color: 'red' })
  } finally { saving.value = false }
}

// --- Loan disbursement ---
const loanOpen = ref(false)
const loanForm = reactive({ employee_id: null as string | null, principal: 0, installment: 0, note: '', cash_bank_account_id: null as string | null })
const openLoan = (row?: any) => {
  Object.assign(loanForm, { employee_id: row?.id ?? null, principal: 0, installment: 0, note: '', cash_bank_account_id: null })
  loanOpen.value = true
}
const saveLoan = async () => {
  const { error } = await client.rpc('disburse_employee_loan', {
    p_employee_id: loanForm.employee_id,
    p_principal: loanForm.principal,
    p_installment: loanForm.installment,
    p_note: loanForm.note || null,
    p_cash_bank_account_id: loanForm.cash_bank_account_id
  } as any)
  if (error) toast.add({ title: t('hr.employees.toast.loan_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('hr.employees.toast.loan_disbursed') }); loanOpen.value = false; await load() }
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('hr.kicker')" :title="t('hr.employees.title')" :subtitle="t('hr.employees.subtitle')">
      <UButton v-if="canWrite" variant="soft" icon="i-heroicons-banknotes" @click="openLoan()">{{ t('hr.employees.disburse_loan') }}</UButton>
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('hr.employees.new_employee') }}</UButton>
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
          <UButton v-if="canWrite" icon="i-heroicons-trash" color="red" variant="ghost" size="xs" @click="removeEmployee(row)" />
        </template>
        <template #empty-state><div class="text-center py-6 text-sm text-gray-400">{{ t('hr.employees.no_employees') }}</div></template>
      </UTable>
    </UCard>

    <UCard>
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('hr.employees.loans_header') }}</p></template>
      <UTable
        :rows="loans"
        :columns="[
          { key: 'loan_no', label: t('hr.employees.loans_columns.loan') }, { key: 'employee', label: t('hr.employees.loans_columns.employee') },
          { key: 'principal', label: t('hr.employees.loans_columns.principal') }, { key: 'monthly_installment', label: t('hr.employees.loans_columns.installment') },
          { key: 'balance', label: t('hr.employees.loans_columns.balance') }, { key: 'status', label: t('hr.employees.loans_columns.status') }
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
        <template #empty-state><div class="text-center py-4 text-sm text-gray-400">{{ t('hr.employees.no_loans') }}</div></template>
      </UTable>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ form.id ? t('hr.employees.edit_title') : t('hr.employees.new_title') }}</p></template>
        <div class="grid grid-cols-2 gap-4">
          <UFormGroup :label="t('hr.employees.form.full_name')" required class="col-span-2"><UInput v-model="form.full_name" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.form.designation')"><UInput v-model="form.designation" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.form.department')"><UInput v-model="form.department" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.form.joining_date')"><UInput v-model="form.joining_date" type="date" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.form.biometric_id')"><UInput v-model="form.biometric_id" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.form.basic_salary')"><UInput v-model.number="form.basic_salary" type="number" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.form.gross_salary')"><UInput v-model.number="form.gross_salary" type="number" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.form.attendance_allowance')"><UInput v-model.number="form.attendance_allowance" type="number" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.form.phone')"><UInput v-model="form.phone" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.form.nid_no')"><UInput v-model="form.nid_no" /></UFormGroup>
        </div>

        <p class="microlabel text-gray-400 dark:text-zinc-500 mt-5 mb-2">{{ t('hr.employees.form.personal_info') }}</p>
        <div class="grid grid-cols-2 gap-4">
          <UFormGroup :label="t('hr.employees.form.father_name')"><UInput v-model="form.father_name" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.form.date_of_birth')"><UInput v-model="form.date_of_birth" type="date" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.form.blood_group')"><UInput v-model="form.blood_group" :placeholder="t('hr.employees.form.blood_group_placeholder')" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.form.marital_status')"><UInput v-model="form.marital_status" :placeholder="t('hr.employees.form.marital_status_placeholder')" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.form.present_address')" class="col-span-2"><UTextarea v-model="form.present_address" :rows="2" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.form.permanent_address')" class="col-span-2"><UTextarea v-model="form.permanent_address" :rows="2" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.form.emergency_contact_name')"><UInput v-model="form.emergency_contact_name" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.form.emergency_contact_phone')"><UInput v-model="form.emergency_contact_phone" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ t('common.save') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="loanOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('hr.employees.loan_form.title') }}</p></template>
        <div class="space-y-4">
          <UFormGroup :label="t('hr.employees.loan_form.employee')" required>
            <USelect v-model="loanForm.employee_id" :options="employees.filter(e => e.is_active)" option-attribute="full_name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup :label="t('hr.employees.loan_form.principal')" :hint="t('hr.employees.loan_form.principal_hint')"><UInput v-model.number="loanForm.principal" type="number" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.loan_form.installment')"><UInput v-model.number="loanForm.installment" type="number" /></UFormGroup>
          <UFormGroup :label="t('hr.employees.loan_form.paid_from_account')">
            <USelect v-model="loanForm.cash_bank_account_id" :options="cashBankAccounts" option-attribute="name" value-attribute="id" :placeholder="t('hr.employees.loan_form.default_account_placeholder')" />
          </UFormGroup>
          <UFormGroup :label="t('hr.employees.loan_form.note')"><UInput v-model="loanForm.note" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="loanOpen = false">{{ t('common.cancel') }}</UButton>
            <UButton @click="saveLoan">{{ t('hr.employees.loan_form.disburse_button') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
