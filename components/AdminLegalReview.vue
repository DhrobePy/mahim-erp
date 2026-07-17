<script setup lang="ts">
// Polymorphic legal-review status widget — attaches to any document or
// contract via (refTable, refId). Every action inserts a new row in
// legal_reviews (history preserved); this shows the latest.
const props = defineProps<{ refTable: string; refId: string; compact?: boolean }>()

const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()

const latest = ref<any>(null)
const loading = ref(true)
const notes = ref('')

const load = async () => {
  loading.value = true
  const { data } = await client.from('v_latest_legal_review')
    .select('*').eq('ref_table', props.refTable).eq('ref_id', props.refId).maybeSingle()
  latest.value = data
  notes.value = data?.reviewer_notes ?? ''
  loading.value = false
}
onMounted(load)
watch(() => props.refId, load)

const statusColor: Record<string, string> = { pending: 'gray', approved: 'green', flagged: 'amber', rejected: 'red' }

const setStatus = async (status: string) => {
  const { data: { user } } = await client.auth.getUser()
  const { error } = await client.from('legal_reviews').insert({
    ref_table: props.refTable, ref_id: props.refId, status,
    reviewer_notes: notes.value || null, reviewed_by: user?.id
  } as any)
  if (error) toast.add({ title: 'Failed', description: error.message, color: 'red' })
  else { toast.add({ title: `Marked ${status}` }); await load() }
}
</script>

<template>
  <div>
    <div class="flex items-center gap-2 mb-1.5">
      <p class="microlabel text-gray-400 dark:text-zinc-500">Legal review</p>
      <UBadge size="xs" variant="subtle" :color="statusColor[latest?.status ?? 'pending']">{{ latest?.status ?? 'pending' }}</UBadge>
    </div>
    <p v-if="latest?.reviewer_notes" class="text-[12px] text-gray-500 dark:text-zinc-400 mb-2">{{ latest.reviewer_notes }}</p>
    <div v-if="canWrite" class="space-y-2">
      <UInput v-model="notes" size="xs" placeholder="Reviewer notes…" />
      <div class="flex gap-1.5">
        <UButton size="2xs" variant="soft" color="green" @click="setStatus('approved')">Approve</UButton>
        <UButton size="2xs" variant="soft" color="amber" @click="setStatus('flagged')">Flag</UButton>
        <UButton size="2xs" variant="soft" color="red" @click="setStatus('rejected')">Reject</UButton>
      </div>
    </div>
  </div>
</template>
