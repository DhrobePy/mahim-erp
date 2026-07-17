<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { grouped } = useBoardAgendas()

const resolutions = ref<any[]>([])
const directors = ref<any[]>([])
const loading = ref(true)

const meetingTypeOptions = [
  { value: 'board_meeting', label: 'Board Meeting' },
  { value: 'agm', label: 'Annual General Meeting (AGM)' },
  { value: 'egm', label: 'Extraordinary General Meeting (EGM)' },
  { value: 'circular_resolution', label: 'Circular Resolution' }
]
const meetingTypeLabel: Record<string, string> = Object.fromEntries(meetingTypeOptions.map((o) => [o.value, o.label]))
const statusColor: Record<string, string> = { draft: 'gray', passed: 'green', circulated: 'blue' }

const load = async () => {
  loading.value = true
  const [r, d] = await Promise.all([
    client.from('board_resolutions')
      .select('*, board_resolution_agendas(id), board_resolution_attendees(director_id)')
      .order('meeting_date', { ascending: false }),
    client.from('company_directors').select('id, full_name, designation').eq('is_active', true).order('full_name')
  ])
  resolutions.value = r.data ?? []
  directors.value = d.data ?? []
  loading.value = false
}
onMounted(load)

const setStatus = async (row: any, status: string) => {
  const { error } = await client.from('board_resolutions').update({ status } as any).eq('id', row.id)
  if (error) toast.add({ title: 'Update failed', description: error.message, color: 'red' })
  else await load()
}

// --- New resolution ---
const open = ref(false)
const saving = ref(false)
const form = reactive({
  meeting_type: 'board_meeting', meeting_no: '', meeting_date: new Date().toISOString().slice(0, 10),
  venue: '', chairperson: ''
})
const attendeeIds = ref<string[]>([])
const agendas = ref<any[]>([])
const blankAgenda = () => ({ title: '', resolution_text: '', is_standard: false })

const openNew = () => {
  Object.assign(form, {
    meeting_type: 'board_meeting', meeting_no: '', meeting_date: new Date().toISOString().slice(0, 10),
    venue: '', chairperson: ''
  })
  attendeeIds.value = directors.value.map((d) => d.id)
  agendas.value = [blankAgenda()]
  open.value = true
}
const toggleAttendee = (id: string) => {
  const i = attendeeIds.value.indexOf(id)
  if (i === -1) attendeeIds.value.push(id); else attendeeIds.value.splice(i, 1)
}
const applyTemplate = (agenda: any, key: string) => {
  const { byKey } = useBoardAgendas()
  const t = byKey(key)
  if (t) { agenda.title = t.title; agenda.resolution_text = t.text; agenda.is_standard = true }
}

const save = async () => {
  const validAgendas = agendas.value.filter((a) => a.title && a.resolution_text)
  if (!validAgendas.length) { toast.add({ title: 'Add at least one agenda item', color: 'red' }); return }
  saving.value = true
  try {
    const { data: res, error } = await client.from('board_resolutions').insert({ ...form } as any).select('id').single()
    if (error) throw error
    const rid = (res as any).id
    const aRes = await client.from('board_resolution_agendas').insert(
      validAgendas.map((a, i) => ({ ...a, resolution_id: rid, agenda_no: i + 1 })) as any
    )
    if (aRes.error) throw aRes.error
    if (attendeeIds.value.length) {
      const tRes = await client.from('board_resolution_attendees').insert(
        attendeeIds.value.map((director_id) => ({ resolution_id: rid, director_id })) as any
      )
      if (tRes.error) throw tRes.error
    }
    toast.add({ title: 'Board resolution created' })
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
    <PageHeader kicker="Admin" title="Board resolutions" subtitle="Minutes with choosable or manual agenda items — doubles as the bank's mandate paper trail">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New resolution</UButton>
    </PageHeader>

    <UCard>
      <UTable
        :rows="resolutions" :loading="loading"
        :columns="[
          { key: 'resolution_no', label: 'No.' }, { key: 'meeting_no', label: 'Meeting' },
          { key: 'meeting_date', label: 'Date' }, { key: 'agendas', label: 'Agendas' },
          { key: 'status', label: 'Status' }, { key: 'actions', label: '' }
        ]"
      >
        <template #resolution_no-data="{ row }"><span class="num font-medium text-amber-600 dark:text-amber-400">{{ row.resolution_no }}</span></template>
        <template #meeting_no-data="{ row }">
          {{ row.meeting_no || '—' }}
          <UBadge size="xs" variant="subtle" class="ml-1">{{ meetingTypeLabel[row.meeting_type] }}</UBadge>
        </template>
        <template #meeting_date-data="{ row }"><span class="num">{{ row.meeting_date }}</span></template>
        <template #agendas-data="{ row }"><span class="num">{{ row.board_resolution_agendas?.length ?? 0 }}</span></template>
        <template #status-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="statusColor[row.status]">{{ row.status }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton icon="i-heroicons-printer" size="xs" color="gray" variant="ghost" :to="`/print/resolution/${row.id}`" target="_blank" aria-label="Print" />
            <UButton v-if="canWrite && row.status === 'draft'" size="2xs" variant="soft" color="green" @click="setStatus(row, 'passed')">Mark passed</UButton>
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">No board resolutions yet.</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-3xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New board resolution</p></template>
        <div class="space-y-4">
          <div class="grid grid-cols-2 gap-3">
            <UFormGroup label="Meeting type">
              <USelect v-model="form.meeting_type" :options="meetingTypeOptions" option-attribute="label" value-attribute="value" />
            </UFormGroup>
            <UFormGroup label="Meeting no." hint="e.g. 18th Board Meeting"><UInput v-model="form.meeting_no" /></UFormGroup>
            <UFormGroup label="Date"><UInput v-model="form.meeting_date" type="date" /></UFormGroup>
            <UFormGroup label="Chairperson"><UInput v-model="form.chairperson" /></UFormGroup>
            <UFormGroup label="Venue" class="col-span-2"><UInput v-model="form.venue" /></UFormGroup>
          </div>

          <div>
            <p class="microlabel text-gray-400 dark:text-zinc-500 mb-1.5">Attendees</p>
            <div class="flex flex-wrap gap-3">
              <UCheckbox
                v-for="d in directors" :key="d.id"
                :model-value="attendeeIds.includes(d.id)" :label="d.full_name"
                @update:model-value="toggleAttendee(d.id)"
              />
            </div>
          </div>

          <div>
            <div class="flex items-center justify-between mb-2">
              <p class="microlabel text-gray-400 dark:text-zinc-500">Agenda items</p>
              <UButton size="xs" variant="soft" icon="i-heroicons-plus" @click="agendas.push(blankAgenda())">Add agenda</UButton>
            </div>
            <div v-for="(a, i) in agendas" :key="i" class="mb-3 p-2.5 rounded ring-1 ring-gray-100 dark:ring-zinc-800 space-y-2">
              <div class="flex items-center gap-2">
                <span class="num text-xs text-gray-400 w-5">{{ i + 1 }}.</span>
                <USelect
                  :options="Object.entries(grouped).flatMap(([cat, items]) => items.map(t => ({ value: t.key, label: `${cat} — ${t.title}` })))"
                  option-attribute="label" value-attribute="value" placeholder="Pick a standard template… (optional)"
                  class="flex-1" @update:model-value="(k: string) => applyTemplate(a, k)"
                />
              </div>
              <UInput v-model="a.title" placeholder="Agenda title" />
              <UTextarea v-model="a.resolution_text" :rows="2" placeholder="RESOLVED THAT…" />
            </div>
          </div>
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
