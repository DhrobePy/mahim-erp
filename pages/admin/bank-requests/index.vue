<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money } = useFmt()
const { all: serviceTemplates, byValue } = useBankRequestTemplates()

const branches = ref<any[]>([])
const banks = ref<any[]>([])
const requests = ref<any[]>([])
const resolutions = ref<any[]>([])
const loading = ref(true)

const statusColor: Record<string, string> = { draft: 'gray', submitted: 'blue', acknowledged: 'amber', completed: 'green' }
const serviceLabel: Record<string, string> = Object.fromEntries(serviceTemplates.map((t) => [t.value, t.label]))

const load = async () => {
  loading.value = true
  const [b, bk, r, res] = await Promise.all([
    client.from('bank_branches').select('*, parties(name)').order('created_at'),
    client.from('parties').select('id, name').eq('is_bank', true).order('name'),
    client.from('bank_service_requests').select('*, bank_branches(branch_name, parties(name))').order('created_at', { ascending: false }),
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
  if (!branchForm.bank_party_id || !branchForm.branch_name) { toast.add({ title: 'Bank and branch name are required', color: 'red' }); return }
  const { error } = await client.from('bank_branches').insert({ ...branchForm } as any)
  if (error) toast.add({ title: 'Failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Branch added' }); branchOpen.value = false; await load() }
}

// --- New request ---
const open = ref(false)
const saving = ref(false)
const form = reactive({
  branch_id: null as string | null, service_type: 'lc_issue', reference_no: '', subject: '', body: '',
  amount: null as number | null, tenor_or_period: '', board_resolution_id: null as string | null,
  request_date: new Date().toISOString().slice(0, 10)
})
const openNew = () => {
  const t = byValue('lc_issue')
  Object.assign(form, {
    branch_id: null, service_type: 'lc_issue', reference_no: '', subject: t?.subject ?? '', body: t?.body ?? '',
    amount: null, tenor_or_period: '', board_resolution_id: null, request_date: new Date().toISOString().slice(0, 10)
  })
  open.value = true
}
const onServiceChange = (v: string) => {
  const t = byValue(v)
  if (t) { form.subject = t.subject; form.body = t.body }
}

const save = async () => {
  if (!form.branch_id) { toast.add({ title: 'Pick a branch', color: 'red' }); return }
  if (!form.subject) { toast.add({ title: 'Subject is required', color: 'red' }); return }
  saving.value = true
  const { error } = await client.from('bank_service_requests').insert({ ...form } as any)
  if (error) toast.add({ title: 'Save failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Bank service request created' }); open.value = false; await load() }
  saving.value = false
}

const setStatus = async (row: any, status: string) => {
  const { error } = await client.from('bank_service_requests').update({ status } as any).eq('id', row.id)
  if (error) toast.add({ title: 'Update failed', description: error.message, color: 'red' })
  else await load()
}
</script>

<template>
  <div>
    <PageHeader kicker="Admin" title="Bank service requests" subtitle="Approach a branch for LC issue, collection, discrepancy, statements, LBPD, FDR, DPS or any other service">
      <UButton v-if="canWrite" variant="soft" icon="i-heroicons-building-library" @click="openBranch">New branch</UButton>
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New request</UButton>
    </PageHeader>

    <UCard class="mb-4">
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Bank branches</p></template>
      <div v-if="!branches.length" class="text-sm text-gray-400 py-3 text-center">No branches registered yet.</div>
      <div v-for="b in branches" :key="b.id" class="flex justify-between py-1.5 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
        <span class="dark:text-zinc-200">{{ b.parties?.name }} — {{ b.branch_name }}</span>
        <span class="text-gray-500 dark:text-zinc-500">{{ b.contact_person }}{{ b.phone ? ' · ' + b.phone : '' }}</span>
      </div>
    </UCard>

    <UCard>
      <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">Requests</p></template>
      <UTable
        :rows="requests" :loading="loading"
        :columns="[
          { key: 'request_no', label: 'No.' }, { key: 'service_type', label: 'Service' },
          { key: 'branch', label: 'Branch' }, { key: 'subject', label: 'Subject' },
          { key: 'amount', label: 'Amount (৳)' }, { key: 'status', label: 'Status' }, { key: 'actions', label: '' }
        ]"
      >
        <template #request_no-data="{ row }"><span class="num font-medium text-amber-600 dark:text-amber-400">{{ row.request_no }}</span></template>
        <template #service_type-data="{ row }"><UBadge size="xs" variant="subtle">{{ serviceLabel[row.service_type] }}</UBadge></template>
        <template #branch-data="{ row }">{{ row.bank_branches?.parties?.name }} — {{ row.bank_branches?.branch_name }}</template>
        <template #amount-data="{ row }"><span class="num">{{ row.amount ? money(row.amount) : '—' }}</span></template>
        <template #status-data="{ row }"><UBadge size="xs" variant="subtle" :color="statusColor[row.status]">{{ row.status }}</UBadge></template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton icon="i-heroicons-printer" size="xs" color="gray" variant="ghost" :to="`/print/bankrequest/${row.id}`" target="_blank" aria-label="Print" />
            <UButton v-if="canWrite && row.status === 'draft'" size="2xs" variant="soft" @click="setStatus(row, 'submitted')">Submitted</UButton>
            <UButton v-if="canWrite && row.status === 'submitted'" size="2xs" variant="soft" color="amber" @click="setStatus(row, 'acknowledged')">Acknowledged</UButton>
            <UButton v-if="canWrite && row.status === 'acknowledged'" size="2xs" variant="soft" color="green" @click="setStatus(row, 'completed')">Completed</UButton>
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">No bank service requests yet.</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="branchOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New bank branch</p></template>
        <div class="space-y-3">
          <UFormGroup label="Bank" required>
            <USelect v-model="branchForm.bank_party_id" :options="banks" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup label="Branch name" required><UInput v-model="branchForm.branch_name" placeholder="e.g. Narayanganj Branch" /></UFormGroup>
          <UFormGroup label="Address"><UInput v-model="branchForm.branch_address" /></UFormGroup>
          <UFormGroup label="Routing no."><UInput v-model="branchForm.routing_no" /></UFormGroup>
          <UFormGroup label="Contact person"><UInput v-model="branchForm.contact_person" /></UFormGroup>
          <UFormGroup label="Phone"><UInput v-model="branchForm.phone" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="branchOpen = false">Cancel</UButton>
            <UButton @click="saveBranch">Add branch</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New bank service request</p></template>
        <div class="space-y-3">
          <UFormGroup label="Branch" required>
            <USelect v-model="form.branch_id" :options="branches.map(b => ({ id: b.id, label: `${b.parties?.name} — ${b.branch_name}` }))" option-attribute="label" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup label="Service">
            <USelect v-model="form.service_type" :options="serviceTemplates" option-attribute="label" value-attribute="value" @update:model-value="onServiceChange" />
          </UFormGroup>
          <div class="grid grid-cols-2 gap-3">
            <UFormGroup label="Date"><UInput v-model="form.request_date" type="date" /></UFormGroup>
            <UFormGroup label="Reference no." hint="LC/bill/facility being referenced"><UInput v-model="form.reference_no" /></UFormGroup>
            <UFormGroup label="Amount (৳)"><UInput v-model.number="form.amount" type="number" /></UFormGroup>
            <UFormGroup label="Tenor / period"><UInput v-model="form.tenor_or_period" placeholder="e.g. 12 months" /></UFormGroup>
          </div>
          <UFormGroup label="Subject" required><UInput v-model="form.subject" /></UFormGroup>
          <UFormGroup label="Body"><UTextarea v-model="form.body" :rows="4" /></UFormGroup>
          <UFormGroup label="Authorizing board resolution" hint="optional">
            <USelect v-model="form.board_resolution_id" :options="resolutions" option-attribute="resolution_no" value-attribute="id" placeholder="—" />
          </UFormGroup>
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
