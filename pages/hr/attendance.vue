<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const day = ref(new Date().toISOString().slice(0, 10))
const employees = ref<any[]>([])
const rows = ref<any[]>([])
const loading = ref(true)
const saving = ref(false)

const statusKeys = ['present', 'absent', 'leave', 'holiday', 'weekend']
const statusOptions = computed(() => statusKeys.map((value) => ({ value, label: t(`hr.attendance.status_options.${value}`) })))

const load = async () => {
  loading.value = true
  const [e, a] = await Promise.all([
    client.from('employees').select('id, emp_no, full_name').eq('is_active', true).is('deleted_at', null).order('emp_no'),
    client.from('attendance').select('*').eq('att_date', day.value).is('deleted_at', null)
  ])
  employees.value = e.data ?? []
  const existing = new Map((a.data ?? []).map((r: any) => [r.employee_id, r]))
  rows.value = employees.value.map((emp) => {
    const ex: any = existing.get(emp.id)
    return {
      id: ex?.id ?? null,
      employee_id: emp.id,
      emp_no: emp.emp_no,
      full_name: emp.full_name,
      status: ex?.status ?? 'present',
      ot_hours: ex?.ot_hours ?? 0,
      is_late: ex?.is_late ?? false
    }
  })
  loading.value = false
}
onMounted(load)
watch(day, load)

const saveAll = async () => {
  saving.value = true
  try {
    const payload = rows.value.map((r) => ({
      employee_id: r.employee_id,
      att_date: day.value,
      status: r.status,
      ot_hours: r.ot_hours || 0,
      is_late: r.is_late
    }))
    const { error } = await client.from('attendance')
      .upsert(payload as any, { onConflict: 'employee_id,att_date' })
    if (error) throw error
    toast.add({ title: `Attendance saved for ${day.value}` })
  } catch (e: any) {
    toast.add({ title: 'Save failed', description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

const remove = async (row: any) => {
  if (await deleteRecord('attendance', row.id, `${row.full_name} — ${day.value}`)) await load()
}
</script>

<template>
  <div>
    <PageHeader kicker="HR" title="Attendance" subtitle="Daily register — OT capped at 4h/day (Sedex/BSCI guardrail, enforced by the database)">
      <UInput v-model="day" type="date" class="num" />
      <UButton v-if="canWrite" :loading="saving" @click="saveAll">Save day</UButton>
    </PageHeader>

    <UCard>
      <UTable
        :rows="rows" :loading="loading"
        :columns="[
          { key: 'emp_no', label: 'ID' }, { key: 'full_name', label: 'Employee' },
          { key: 'status', label: 'Status' }, { key: 'ot_hours', label: 'OT hours' },
          { key: 'is_late', label: 'Late' }, { key: 'actions', label: '' }
        ]"
      >
        <template #status-data="{ row }">
          <USelect v-model="row.status" :options="statusOptions" :disabled="!canWrite" size="xs" class="w-32" />
        </template>
        <template #ot_hours-data="{ row }">
          <UInput v-model.number="row.ot_hours" type="number" step="0.5" min="0" max="4" :disabled="!canWrite || row.status !== 'present'" size="xs" class="w-20" />
        </template>
        <template #is_late-data="{ row }">
          <UCheckbox v-model="row.is_late" :disabled="!canWrite" />
        </template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton v-if="canWrite && row.id" icon="i-heroicons-trash" color="red" variant="ghost" size="xs" @click="remove(row)" />
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">No active employees — add them in HR → Employees.</div>
        </template>
      </UTable>
    </UCard>
  </div>
</template>
