<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()

const letters = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const { data } = await client.from('forwarding_letters').select('*').order('created_at', { ascending: false })
  letters.value = data ?? []
  loading.value = false
}
onMounted(load)

const open = ref(false)
const saving = ref(false)
const blank = () => ({
  to_name: '', to_address: '', subject: '', body: '',
  enclosures: '', cc: '', letter_date: new Date().toISOString().slice(0, 10)
})
const form = reactive(blank())
const openNew = () => { Object.assign(form, blank()); open.value = true }

const save = async () => {
  if (!form.to_name || !form.subject) { toast.add({ title: 'Addressee and subject are required', color: 'red' }); return }
  saving.value = true
  const { error } = await client.from('forwarding_letters').insert({ ...form } as any)
  if (error) toast.add({ title: 'Save failed', description: error.message, color: 'red' })
  else { toast.add({ title: 'Forwarding letter created' }); open.value = false; await load() }
  saving.value = false
}
</script>

<template>
  <div>
    <PageHeader kicker="Admin" title="Forwarding pad" subtitle="Correspondence covering letters — documents submitted to banks, buyers &amp; offices">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New letter</UButton>
    </PageHeader>

    <UCard>
      <UTable
        :rows="letters" :loading="loading"
        :columns="[
          { key: 'letter_no', label: 'No.' }, { key: 'letter_date', label: 'Date' },
          { key: 'to_name', label: 'To' }, { key: 'subject', label: 'Subject' }, { key: 'actions', label: '' }
        ]"
      >
        <template #letter_no-data="{ row }"><span class="num font-medium text-amber-600 dark:text-amber-400">{{ row.letter_no }}</span></template>
        <template #letter_date-data="{ row }"><span class="num">{{ row.letter_date }}</span></template>
        <template #actions-data="{ row }">
          <UButton icon="i-heroicons-printer" size="xs" color="gray" variant="ghost" :to="`/print/forwarding/${row.id}`" target="_blank" aria-label="Print" />
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">No forwarding letters yet.</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New forwarding letter</p></template>
        <div class="space-y-3">
          <UFormGroup label="Date"><UInput v-model="form.letter_date" type="date" /></UFormGroup>
          <UFormGroup label="To" required><UInput v-model="form.to_name" placeholder="e.g. Islami Bank Bangladesh, Narayanganj Branch" /></UFormGroup>
          <UFormGroup label="Address"><UInput v-model="form.to_address" /></UFormGroup>
          <UFormGroup label="Subject" required><UInput v-model="form.subject" /></UFormGroup>
          <UFormGroup label="Body">
            <UTextarea v-model="form.body" :rows="4" placeholder="Please find enclosed the following documents for your kind perusal and necessary action." />
          </UFormGroup>
          <UFormGroup label="Enclosures"><UInput v-model="form.enclosures" placeholder="Commercial Invoice, Packing List, Bill of Exchange…" /></UFormGroup>
          <UFormGroup label="CC"><UInput v-model="form.cc" /></UFormGroup>
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
