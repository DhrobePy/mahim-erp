<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { all: topics, byValue } = useForwardingTopics()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const letters = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const { data } = await client.from('forwarding_letters').select('*').is('deleted_at', null).order('created_at', { ascending: false })
  letters.value = data ?? []
  loading.value = false
}
onMounted(load)

const open = ref(false)
const saving = ref(false)
const blank = () => ({
  topic: 'general', to_name: '', to_address: '', subject: '', body: '',
  enclosures: '', cc: '', letter_date: new Date().toISOString().slice(0, 10)
})
const form = reactive(blank())
const openNew = () => {
  Object.assign(form, blank())
  const tpl = byValue('general')
  if (tpl) { form.subject = tpl.subject; form.body = tpl.body }
  open.value = true
}
const onTopicChange = (v: string) => {
  const tpl = byValue(v)
  if (tpl) { form.subject = tpl.subject; form.body = tpl.body }
}

const save = async () => {
  if (!form.to_name || !form.subject) { toast.add({ title: t('admin.forwarding.validation.addressee_subject_required'), color: 'red' }); return }
  saving.value = true
  const { topic, ...payload } = form
  const { error } = await client.from('forwarding_letters').insert(payload as any)
  if (error) toast.add({ title: t('common.save_failed'), description: error.message, color: 'red' })
  else { toast.add({ title: t('admin.forwarding.toasts.letter_created') }); open.value = false; await load() }
  saving.value = false
}

const remove = async (row: any) => {
  if (await deleteRecord('forwarding_letters', row.id, row.subject)) await load()
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('admin.forwarding.kicker')" :title="t('admin.forwarding.title')" :subtitle="t('admin.forwarding.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('admin.forwarding.new_letter_btn') }}</UButton>
    </PageHeader>

    <UCard>
      <UTable
        :rows="letters" :loading="loading"
        :columns="[
          { key: 'letter_no', label: t('admin.forwarding.columns.no') }, { key: 'letter_date', label: t('admin.forwarding.columns.date') },
          { key: 'to_name', label: t('admin.forwarding.columns.to') }, { key: 'subject', label: t('admin.forwarding.columns.subject') }, { key: 'actions', label: '' }
        ]"
      >
        <template #letter_no-data="{ row }"><span class="num font-medium text-amber-600 dark:text-amber-400">{{ row.letter_no }}</span></template>
        <template #letter_date-data="{ row }"><span class="num">{{ row.letter_date }}</span></template>
        <template #actions-data="{ row }">
          <div class="flex gap-1 justify-end">
            <UButton icon="i-heroicons-printer" size="xs" color="gray" variant="ghost" :to="`/print/forwarding/${row.id}`" target="_blank" :aria-label="t('admin.forwarding.print_aria')" />
            <UButton v-if="canWrite" icon="i-heroicons-trash" size="xs" color="red" variant="ghost" @click="remove(row)" />
          </div>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('admin.forwarding.empty') }}</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('admin.forwarding.form.title') }}</p></template>
        <div class="space-y-3">
          <UFormGroup :label="t('admin.forwarding.form.topic')">
            <USelect v-model="form.topic" :options="topics" option-attribute="label" value-attribute="value" @update:model-value="onTopicChange" />
          </UFormGroup>
          <UFormGroup :label="t('admin.forwarding.form.date')"><UInput v-model="form.letter_date" type="date" /></UFormGroup>
          <UFormGroup :label="t('admin.forwarding.form.to')" required><UInput v-model="form.to_name" :placeholder="t('admin.forwarding.form.to_placeholder')" /></UFormGroup>
          <UFormGroup :label="t('admin.forwarding.form.address')"><UInput v-model="form.to_address" /></UFormGroup>
          <UFormGroup :label="t('admin.forwarding.form.subject')" required><UInput v-model="form.subject" /></UFormGroup>
          <UFormGroup :label="t('admin.forwarding.form.body')">
            <UTextarea v-model="form.body" :rows="4" :placeholder="t('admin.forwarding.form.body_placeholder')" />
          </UFormGroup>
          <UFormGroup :label="t('admin.forwarding.form.enclosures')"><UInput v-model="form.enclosures" :placeholder="t('admin.forwarding.form.enclosures_placeholder')" /></UFormGroup>
          <UFormGroup :label="t('admin.forwarding.form.cc')"><UInput v-model="form.cc" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ t('admin.forwarding.form.create') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
