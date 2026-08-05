<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { grouped } = useBoardAgendas()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const resolutions = ref<any[]>([])
const directors = ref<any[]>([])
const loading = ref(true)

const meetingTypeOptions = computed(() => [
  { value: 'board_meeting', label: t('admin.resolutions.meeting_types.board_meeting') },
  { value: 'agm', label: t('admin.resolutions.meeting_types.agm') },
  { value: 'egm', label: t('admin.resolutions.meeting_types.egm') },
  { value: 'circular_resolution', label: t('admin.resolutions.meeting_types.circular_resolution') }
])
const meetingTypeLabel = computed<Record<string, string>>(() => Object.fromEntries(meetingTypeOptions.value.map((o) => [o.value, o.label])))
const statusColor: Record<string, string> = { draft: 'gray', passed: 'green', circulated: 'blue' }
const statusLabel = computed<Record<string, string>>(() => ({
  draft: t('admin.resolutions.status.draft'),
  passed: t('admin.resolutions.status.passed'),
  circulated: t('admin.resolutions.status.circulated')
}))

const load = async () => {
  loading.value = true
  const [r, d] = await Promise.all([
    client.from('board_resolutions')
      .select('*, board_resolution_agendas(id), board_resolution_attendees(director_id)')
      .is('deleted_at', null)
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
  if (error) toast.add({ title: t('admin.resolutions.toasts.update_failed'), description: error.message, color: 'red' })
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
  const tpl = byKey(key)
  if (tpl) { agenda.title = tpl.title; agenda.resolution_text = tpl.text; agenda.is_standard = true }
}

const save = async () => {
  const validAgendas = agendas.value.filter((a) => a.title && a.resolution_text)
  if (!validAgendas.length) { toast.add({ title: t('admin.resolutions.validation.agenda_required'), color: 'red' }); return }
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
    toast.add({ title: t('admin.resolutions.toasts.resolution_created') })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('common.save_failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

const remove = async (row: any) => {
  if (await deleteRecord('board_resolutions', row.id, row.resolution_no)) await load()
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('admin.resolutions.kicker')" :title="t('admin.resolutions.title')" :subtitle="t('admin.resolutions.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('admin.resolutions.new_resolution_btn') }}</UButton>
    </PageHeader>

    <UCard>
      <UTable
        :rows="resolutions" :loading="loading"
        :columns="[
          { key: 'resolution_no', label: t('admin.resolutions.columns.no') }, { key: 'meeting_no', label: t('admin.resolutions.columns.meeting') },
          { key: 'meeting_date', label: t('admin.resolutions.columns.date') }, { key: 'agendas', label: t('admin.resolutions.columns.agendas') },
          { key: 'status', label: t('admin.resolutions.columns.status') }, { key: 'actions', label: '' }
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
          <UBadge size="xs" variant="subtle" :color="statusColor[row.status]">{{ statusLabel[row.status] }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton icon="i-heroicons-printer" size="xs" color="gray" variant="ghost" :to="`/print/resolution/${row.id}`" target="_blank" :aria-label="t('admin.resolutions.print_aria')" />
            <UButton v-if="canWrite && row.status === 'draft'" size="2xs" variant="soft" color="green" @click="setStatus(row, 'passed')">{{ t('admin.resolutions.mark_passed_btn') }}</UButton>
            <UButton v-if="canWrite" icon="i-heroicons-trash" size="xs" color="red" variant="ghost" @click="remove(row)" />
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('admin.resolutions.empty') }}</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-3xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('admin.resolutions.form.title') }}</p></template>
        <div class="space-y-4">
          <div class="grid grid-cols-2 gap-3">
            <UFormGroup :label="t('admin.resolutions.form.meeting_type')">
              <USelect v-model="form.meeting_type" :options="meetingTypeOptions" option-attribute="label" value-attribute="value" />
            </UFormGroup>
            <UFormGroup :label="t('admin.resolutions.form.meeting_no')" :hint="t('admin.resolutions.form.meeting_no_hint')"><UInput v-model="form.meeting_no" /></UFormGroup>
            <UFormGroup :label="t('admin.resolutions.form.date')"><UInput v-model="form.meeting_date" type="date" /></UFormGroup>
            <UFormGroup :label="t('admin.resolutions.form.chairperson')"><UInput v-model="form.chairperson" /></UFormGroup>
            <UFormGroup :label="t('admin.resolutions.form.venue')" class="col-span-2"><UInput v-model="form.venue" /></UFormGroup>
          </div>

          <div>
            <p class="microlabel text-gray-400 dark:text-zinc-500 mb-1.5">{{ t('admin.resolutions.form.attendees') }}</p>
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
              <p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('admin.resolutions.form.agenda_items') }}</p>
              <UButton size="xs" variant="soft" icon="i-heroicons-plus" @click="agendas.push(blankAgenda())">{{ t('admin.resolutions.form.add_agenda') }}</UButton>
            </div>
            <div v-for="(a, i) in agendas" :key="i" class="mb-3 p-2.5 rounded ring-1 ring-gray-100 dark:ring-zinc-800 space-y-2">
              <div class="flex items-center gap-2">
                <span class="num text-xs text-gray-400 w-5">{{ i + 1 }}.</span>
                <USelect
                  :options="Object.entries(grouped).flatMap(([cat, items]) => items.map(tpl => ({ value: tpl.key, label: `${cat} — ${tpl.title}` })))"
                  option-attribute="label" value-attribute="value" :placeholder="t('admin.resolutions.form.template_placeholder')"
                  class="flex-1" @update:model-value="(k: string) => applyTemplate(a, k)"
                />
              </div>
              <UInput v-model="a.title" :placeholder="t('admin.resolutions.form.agenda_title_placeholder')" />
              <UTextarea v-model="a.resolution_text" :rows="2" :placeholder="t('admin.resolutions.form.resolution_text_placeholder')" />
            </div>
          </div>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ t('admin.resolutions.form.create') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
