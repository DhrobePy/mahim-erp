<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money } = useFmt()
const { all: serviceTemplates, byValue } = useBankRequestTemplates()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const branches = ref<any[]>([])
const banks = ref<any[]>([])
const requests = ref<any[]>([])
const resolutions = ref<any[]>([])
const loading = ref(true)

const statusColor: Record<string, string> = { draft: 'gray', submitted: 'blue', acknowledged: 'amber', completed: 'green' }
const serviceLabel: Record<string, string> = Object.fromEntries(serviceTemplates.map((tpl) => [tpl.value, tpl.label]))
const statusLabel = computed<Record<string, string>>(() => ({
  draft: t('admin.bank_requests.status.draft'),
  submitted: t('admin.bank_requests.status.submitted'),
  acknowledged: t('admin.bank_requests.status.acknowledged'),
  completed: t('admin.bank_requests.status.completed')
}))

const load = async () => {
  loading.value = true
  const [b, bk, r, res] = await Promise.all([
    client.from('bank_branches').select('*, parties(name)').is('deleted_at', null).order('created_at'),
    client.from('parties').select('id, name').eq('is_bank', true).is('deleted_at', null).order('name'),
    client.from('bank_service_requests').select('*, bank_branches(branch_name, parties(name))').is('deleted_at', null).order('created_at', { ascending: false }),
    client.from('board_resolutions').select('id, resolution_no, meeting_no').order('meeting_date', { ascending: false })
  ])
  branches.value = b.data ?? []
  banks.value = bk.data ?? []
  requests.value = r.data ?? []
  resolutions.value = res.data ?? []
  loading.value = false
}
onMounted(load)

// --- New branch ---
const branchOpen = ref(false)
const branchForm = reactive({ bank_party_id: null as string | null, branch_name: '', branch_address: '', routing_no: '', contact_person: '', phone: '' })
const openBranch = () => {
  Object.assign(branchForm, { bank_party_id: null, branch_name: '', branch_address: '', routing_no: '', contact_person: '', phone: '' })
  branchOpen.value = true
}
const saveBranch = async () => {
  if (!branchForm.bank_party_id || !branchForm.branch_name) { toast.add({ title: t('admin.bank_requests.validation.branch_name_required'), color: 'red' }); return }
  const { error } = await client.from('bank_branches').insert({ ...branchForm } as any)
  if (error) toast.add({ title: t('admin.bank_requests.toasts.failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('admin.bank_requests.toasts.branch_added') }); branchOpen.value = false; await load() }
}

// --- New request ---
const open = ref(false)
const saving = ref(false)
const form = reactive({
  branch_id: null as string | null, service_type: 'lc_issue', reference_no: '', subject: '', body: '',
  amount: null as number | null, tenor_or_period: '', board_resolution_id: null as string | null,
  request_date: new Date().toISOString().slice(0, 10),
  statement_period_from: '', statement_period_to: ''
})
const openNew = () => {
  const tpl = byValue('lc_issue')
  Object.assign(form, {
    branch_id: null, service_type: 'lc_issue', reference_no: '', subject: tpl?.subject ?? '', body: tpl?.body ?? '',
    amount: null, tenor_or_period: '', board_resolution_id: null, request_date: new Date().toISOString().slice(0, 10),
    statement_period_from: '', statement_period_to: ''
  })
  open.value = true
}
const onServiceChange = (v: string) => {
  const tpl = byValue(v)
  if (tpl) { form.subject = tpl.subject; form.body = tpl.body }
}

const save = async () => {
  if (!form.branch_id) { toast.add({ title: t('admin.bank_requests.validation.pick_branch'), color: 'red' }); return }
  if (!form.subject) { toast.add({ title: t('admin.bank_requests.validation.subject_required'), color: 'red' }); return }
  if (form.service_type === 'bank_statement' && (!form.statement_period_from || !form.statement_period_to)) {
    toast.add({ title: t('admin.bank_requests.validation.statement_period_required'), color: 'red' }); return
  }
  saving.value = true
  const payload: any = {
    ...form,
    statement_period_from: form.statement_period_from || null,
    statement_period_to: form.statement_period_to || null
  }
  const { error } = await client.from('bank_service_requests').insert(payload)
  if (error) toast.add({ title: t('common.save_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('admin.bank_requests.toasts.request_created') }); open.value = false; await load() }
  saving.value = false
}

const setStatus = async (row: any, status: string) => {
  const { error } = await client.from('bank_service_requests').update({ status } as any).eq('id', row.id)
  if (error) toast.add({ title: t('admin.bank_requests.toasts.update_failed'), description: error.message, color: 'red' })
  else await load()
}

const removeBranch = async (row: any) => {
  if (await deleteRecord('bank_branches', row.id, row.branch_name)) await load()
}
const removeRequest = async (row: any) => {
  if (await deleteRecord('bank_service_requests', row.id, row.request_no)) await load()
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('admin.bank_requests.kicker')" :title="t('admin.bank_requests.title')" :subtitle="t('admin.bank_requests.subtitle')">
      <UButton v-if="canWrite" variant="soft" icon="i-heroicons-building-library" @click="openBranch">{{ t('admin.bank_requests.new_branch_btn') }}</UButton>
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('admin.bank_requests.new_request_btn') }}</UButton>
    </PageHeader>

    <UCard class="mb-4">
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('admin.bank_requests.branches.card_title') }}</p></template>
      <div v-if="!branches.length" class="text-sm text-gray-400 py-3 text-center">{{ t('admin.bank_requests.branches.empty') }}</div>
      <div v-for="b in branches" :key="b.id" class="flex justify-between items-center py-1.5 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
        <span class="dark:text-zinc-200">{{ b.parties?.name }} — {{ b.branch_name }}</span>
        <span class="flex items-center gap-2">
          <span class="text-gray-500 dark:text-zinc-500">{{ b.contact_person }}{{ b.phone ? ' · ' + b.phone : '' }}</span>
          <UButton v-if="canWrite" icon="i-heroicons-trash" size="2xs" color="red" variant="ghost" @click="removeBranch(b)" />
        </span>
      </div>
    </UCard>

    <UCard>
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('admin.bank_requests.requests.card_title') }}</p></template>
      <UTable
        :rows="requests" :loading="loading"
        :columns="[
          { key: 'request_no', label: t('admin.bank_requests.requests.columns.no') }, { key: 'service_type', label: t('admin.bank_requests.requests.columns.service') },
          { key: 'branch', label: t('admin.bank_requests.requests.columns.branch') }, { key: 'subject', label: t('admin.bank_requests.requests.columns.subject') },
          { key: 'amount', label: t('admin.bank_requests.requests.columns.amount_period') }, { key: 'status', label: t('admin.bank_requests.requests.columns.status') }, { key: 'actions', label: '' }
        ]"
      >
        <template #request_no-data="{ row }"><span class="num font-medium text-amber-600 dark:text-amber-400">{{ row.request_no }}</span></template>
        <template #service_type-data="{ row }"><UBadge size="xs" variant="subtle">{{ serviceLabel[row.service_type] }}</UBadge></template>
        <template #branch-data="{ row }">{{ row.bank_branches?.parties?.name }} — {{ row.bank_branches?.branch_name }}</template>
        <template #amount-data="{ row }">
          <span v-if="row.service_type === 'bank_statement'" class="num text-xs">
            {{ row.statement_period_from ? `${row.statement_period_from} → ${row.statement_period_to}` : '—' }}
          </span>
          <span v-else class="num">{{ row.amount ? money(row.amount) : '—' }}</span>
        </template>
        <template #status-data="{ row }"><UBadge size="xs" variant="subtle" :color="statusColor[row.status]">{{ statusLabel[row.status] }}</UBadge></template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton icon="i-heroicons-printer" size="xs" color="gray" variant="ghost" :to="`/print/bankrequest/${row.id}`" target="_blank" :aria-label="t('admin.bank_requests.requests.print_aria')" />
            <UButton v-if="canWrite && row.status === 'draft'" size="2xs" variant="soft" @click="setStatus(row, 'submitted')">{{ t('admin.bank_requests.requests.mark_submitted') }}</UButton>
            <UButton v-if="canWrite && row.status === 'submitted'" size="2xs" variant="soft" color="amber" @click="setStatus(row, 'acknowledged')">{{ t('admin.bank_requests.requests.mark_acknowledged') }}</UButton>
            <UButton v-if="canWrite && row.status === 'acknowledged'" size="2xs" variant="soft" color="green" @click="setStatus(row, 'completed')">{{ t('admin.bank_requests.requests.mark_completed') }}</UButton>
            <UButton v-if="canWrite" icon="i-heroicons-trash" size="xs" color="red" variant="ghost" @click="removeRequest(row)" />
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('admin.bank_requests.requests.empty') }}</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="branchOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('admin.bank_requests.new_branch.title') }}</p></template>
        <div class="space-y-3">
          <UFormGroup :label="t('admin.bank_requests.new_branch.bank')" required>
            <USelect v-model="branchForm.bank_party_id" :options="banks" option-attribute="name" value-attribute="id" :placeholder="t('admin.bank_requests.select_placeholder')" />
          </UFormGroup>
          <UFormGroup :label="t('admin.bank_requests.new_branch.branch_name')" required><UInput v-model="branchForm.branch_name" :placeholder="t('admin.bank_requests.new_branch.branch_name_placeholder')" /></UFormGroup>
          <UFormGroup :label="t('admin.bank_requests.new_branch.address')"><UInput v-model="branchForm.branch_address" /></UFormGroup>
          <UFormGroup :label="t('admin.bank_requests.new_branch.routing_no')"><UInput v-model="branchForm.routing_no" /></UFormGroup>
          <UFormGroup :label="t('admin.bank_requests.new_branch.contact_person')"><UInput v-model="branchForm.contact_person" /></UFormGroup>
          <UFormGroup :label="t('admin.bank_requests.new_branch.phone')"><UInput v-model="branchForm.phone" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="branchOpen = false">{{ t('common.cancel') }}</UButton>
            <UButton @click="saveBranch">{{ t('admin.bank_requests.new_branch.add_branch') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('admin.bank_requests.new_request.title') }}</p></template>
        <div class="space-y-3">
          <UFormGroup :label="t('admin.bank_requests.new_request.branch')" required>
            <USelect v-model="form.branch_id" :options="branches.map(b => ({ id: b.id, label: `${b.parties?.name} — ${b.branch_name}` }))" option-attribute="label" value-attribute="id" :placeholder="t('admin.bank_requests.select_placeholder')" />
          </UFormGroup>
          <UFormGroup :label="t('admin.bank_requests.new_request.service')">
            <USelect v-model="form.service_type" :options="serviceTemplates" option-attribute="label" value-attribute="value" @update:model-value="onServiceChange" />
          </UFormGroup>
          <div class="grid grid-cols-2 gap-3">
            <UFormGroup :label="t('admin.bank_requests.new_request.date')"><UInput v-model="form.request_date" type="date" /></UFormGroup>
            <UFormGroup :label="t('admin.bank_requests.new_request.reference_no')" :hint="t('admin.bank_requests.new_request.reference_no_hint')"><UInput v-model="form.reference_no" /></UFormGroup>
          </div>
          <div v-if="form.service_type === 'bank_statement'" class="grid grid-cols-2 gap-3">
            <UFormGroup :label="t('admin.bank_requests.new_request.statement_from')" required><UInput v-model="form.statement_period_from" type="date" /></UFormGroup>
            <UFormGroup :label="t('admin.bank_requests.new_request.statement_to')" required><UInput v-model="form.statement_period_to" type="date" /></UFormGroup>
          </div>
          <div v-else class="grid grid-cols-2 gap-3">
            <UFormGroup :label="t('admin.bank_requests.new_request.amount')"><UInput v-model.number="form.amount" type="number" /></UFormGroup>
            <UFormGroup :label="t('admin.bank_requests.new_request.tenor_period')"><UInput v-model="form.tenor_or_period" :placeholder="t('admin.bank_requests.new_request.tenor_period_placeholder')" /></UFormGroup>
          </div>
          <UFormGroup :label="t('admin.bank_requests.new_request.subject')" required><UInput v-model="form.subject" /></UFormGroup>
          <UFormGroup :label="t('admin.bank_requests.new_request.body')"><UTextarea v-model="form.body" :rows="4" /></UFormGroup>
          <UFormGroup :label="t('admin.bank_requests.new_request.board_resolution')" :hint="t('admin.bank_requests.new_request.board_resolution_hint')">
            <USelect v-model="form.board_resolution_id" :options="resolutions" option-attribute="resolution_no" value-attribute="id" :placeholder="t('admin.bank_requests.select_placeholder')" />
          </UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ t('admin.bank_requests.new_request.create') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
