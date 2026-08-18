<script setup lang="ts">
const route = useRoute()
const router = useRouter()
const client = useSupabaseClient()
const { money } = useFmt()
const { docLink } = useDocLink()
const { canWrite } = useProfile()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const id = route.params.id as string
const journal = ref<any>(null)
const loading = ref(true)

const load = async () => {
  loading.value = true
  const { data } = await client.from('journals')
    .select('*, journal_lines(id, debit, credit, note, accounts(code, name), parties(id, name), cost_centers(code, name))')
    .eq('id', id).single()
  journal.value = data
  loading.value = false
}
onMounted(load)

const totals = computed(() => ({
  d: (journal.value?.journal_lines ?? []).reduce((s: number, l: any) => s + Number(l.debit), 0),
  c: (journal.value?.journal_lines ?? []).reduce((s: number, l: any) => s + Number(l.credit), 0)
}))
const sourceLink = computed(() => docLink(journal.value?.ref_table, journal.value?.ref_id))
const removeJournal = async () => {
  if (await deleteRecord('journals', journal.value.id, journal.value.journal_no)) router.push('/accounting')
}
</script>

<template>
  <div v-if="journal">
    <PageHeader :kicker="t('accounting.kicker')" :title="journal.journal_no" :subtitle="`${journal.journal_date} · ${journal.memo ?? ''}`">
      <NuxtLink
        v-if="sourceLink"
        :to="sourceLink"
        class="text-[12.5px] text-amber-600 dark:text-amber-400 hover:underline self-center"
      >{{ t('accounting.journal_detail.source_link', { table: journal.ref_table?.replace(/_/g, ' ') }) }}</NuxtLink>
      <UButton
        v-if="canWrite && !journal.ref_table" icon="i-heroicons-trash" color="red" variant="soft" size="xs"
        @click="removeJournal"
      >{{ t('accounting.journal_detail.delete') }}</UButton>
    </PageHeader>

    <UCard>
      <template #header>
        <div class="flex justify-between">
          <p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('accounting.journal_detail.header') }}</p>
          <span class="num text-xs" :class="Math.abs(totals.d - totals.c) < 0.01 ? 'text-emerald-500' : 'text-red-500'">
            {{ t('accounting.journal_detail.balance_line', { debit: money(totals.d), credit: money(totals.c) }) }}
          </span>
        </div>
      </template>
      <table class="w-full text-[13px]">
        <thead>
          <tr class="text-left microlabel text-gray-400 dark:text-zinc-500">
            <th class="py-1.5 pr-3">{{ t('accounting.journal_detail.columns.account') }}</th>
            <th class="pr-3">{{ t('accounting.journal_detail.columns.party') }}</th>
            <th class="pr-3">{{ t('accounting.journal_detail.columns.cost_center') }}</th>
            <th class="text-right pr-3">{{ t('accounting.journal_detail.columns.debit') }}</th>
            <th class="text-right">{{ t('accounting.journal_detail.columns.credit') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="l in journal.journal_lines" :key="l.id" class="border-t border-gray-100 dark:border-zinc-800/60">
            <td class="py-1.5 pr-3" :class="Number(l.credit) ? 'pl-6' : ''">
              <span class="num text-gray-400 dark:text-zinc-600 mr-1.5">{{ l.accounts?.code }}</span>
              <span class="dark:text-zinc-200">{{ l.accounts?.name }}</span>
              <span v-if="l.note" class="text-gray-400 dark:text-zinc-600 text-[11.5px] ml-1">({{ l.note }})</span>
            </td>
            <td class="pr-3">
              <NuxtLink v-if="l.parties" :to="`/parties/${l.parties.id}`" class="text-amber-600 dark:text-amber-400 hover:underline text-[12px]">
                {{ l.parties.name }}
              </NuxtLink>
              <span v-else class="text-gray-400 dark:text-zinc-700">—</span>
            </td>
            <td class="pr-3 text-[12px] text-gray-500 dark:text-zinc-500">{{ l.cost_centers?.code ?? '—' }}</td>
            <td class="text-right pr-3 num font-medium dark:text-zinc-100">{{ Number(l.debit) ? Number(l.debit).toLocaleString('en-IN') : '' }}</td>
            <td class="text-right num text-gray-500 dark:text-zinc-400">{{ Number(l.credit) ? Number(l.credit).toLocaleString('en-IN') : '' }}</td>
          </tr>
        </tbody>
      </table>
    </UCard>
  </div>
  <div v-else-if="!loading" class="text-sm text-gray-400 py-10 text-center">{{ t('accounting.journal_detail.not_found') }}</div>
</template>
