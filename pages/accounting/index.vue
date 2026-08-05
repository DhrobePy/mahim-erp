<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite, activeCompanyId } = useProfile()
const { t } = useI18n()

const tb = ref<any[]>([])
const journals = ref<any[]>([])
const accounts = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [t, j, a] = await Promise.all([
    client.from('trial_balance').select('*'),
    client.from('journals')
      .select('*, journal_lines(id, debit, credit, note, accounts(code, name))')
      .order('created_at', { ascending: false }).limit(50),
    client.from('accounts').select('code, name').eq('is_postable', true).is('deleted_at', null).order('code')
  ])
  tb.value = t.data ?? []
  journals.value = j.data ?? []
  accounts.value = (a.data ?? []).map((x: any) => ({ ...x, label: `${x.code} — ${x.name}` }))
  loading.value = false
}
onMounted(load)

const totals = computed(() => ({
  debit: tb.value.reduce((s, r) => s + Number(r.debit_balance), 0),
  credit: tb.value.reduce((s, r) => s + Number(r.credit_balance), 0)
}))
const nonZero = computed(() => tb.value.filter((r) => Number(r.debit_balance) || Number(r.credit_balance)))

// --- Manual journal ---
const open = ref(false)
const saving = ref(false)
const memo = ref('')
const jdate = ref(new Date().toISOString().slice(0, 10))
const lines = ref<any[]>([])
const blankLine = () => ({ account: null as string | null, debit: 0, credit: 0, note: '' })
const openNew = () => {
  memo.value = ''
  jdate.value = new Date().toISOString().slice(0, 10)
  lines.value = [blankLine(), blankLine()]
  open.value = true
}
const sums = computed(() => ({
  d: lines.value.reduce((s, l) => s + (Number(l.debit) || 0), 0),
  c: lines.value.reduce((s, l) => s + (Number(l.credit) || 0), 0)
}))
const save = async () => {
  saving.value = true
  try {
    const payload = lines.value.filter((l) => l.account && (l.debit || l.credit))
    const { error } = await client.rpc('post_journal', {
      p_company: activeCompanyId.value,
      p_date: jdate.value,
      p_memo: memo.value || 'Manual journal',
      p_ref_table: null,
      p_ref_id: null,
      p_lines: payload
    } as any)
    if (error) throw error
    toast.add({ title: t('accounting.home.journal_dialog.posted') })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('accounting.home.journal_dialog.posting_failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

const expanded = ref<string | null>(null)
</script>

<template>
  <div>
    <PageHeader :kicker="t('accounting.kicker')" :title="t('accounting.home.title')" :subtitle="t('accounting.home.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('accounting.home.manual_journal') }}</UButton>
    </PageHeader>

    <div class="grid grid-cols-1 xl:grid-cols-2 gap-6">
      <UCard>
        <template #header>
          <div class="flex items-center justify-between">
            <p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('accounting.home.trial_balance.header') }}</p>
            <UBadge size="xs" :color="Math.abs(totals.debit - totals.credit) < 0.01 ? 'green' : 'red'" variant="subtle" class="num">
              {{ t('accounting.home.trial_balance.balance_badge', { debit: totals.debit.toLocaleString('en-IN'), credit: totals.credit.toLocaleString('en-IN') }) }}
            </UBadge>
          </div>
        </template>
        <UTable
          :rows="nonZero" :loading="loading"
          :columns="[
            { key: 'code', label: t('common.code') }, { key: 'name', label: t('accounting.home.trial_balance.columns.account') },
            { key: 'debit_balance', label: t('accounting.home.trial_balance.columns.debit') }, { key: 'credit_balance', label: t('accounting.home.trial_balance.columns.credit') }
          ]"
        >
          <template #code-data="{ row }"><span class="num text-gray-400 dark:text-zinc-500">{{ row.code }}</span></template>
          <template #debit_balance-data="{ row }">
            <span class="num font-medium dark:text-zinc-100">{{ Number(row.debit_balance) ? Number(row.debit_balance).toLocaleString('en-IN') : '' }}</span>
          </template>
          <template #credit_balance-data="{ row }">
            <span class="num font-medium dark:text-zinc-100">{{ Number(row.credit_balance) ? Number(row.credit_balance).toLocaleString('en-IN') : '' }}</span>
          </template>
          <template #empty-state><div class="text-center py-4 text-sm text-gray-400">{{ t('accounting.home.trial_balance.empty') }}</div></template>
        </UTable>
      </UCard>

      <UCard>
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('accounting.home.journal_register.header') }}</p></template>
        <div class="divide-y divide-gray-100 dark:divide-zinc-800/60">
          <div v-for="j in journals" :key="j.id" class="py-2">
            <button class="w-full flex items-center justify-between text-left cursor-pointer" @click="expanded = expanded === j.id ? null : j.id">
              <div>
                <NuxtLink :to="`/accounting/journal/${j.id}`" class="num text-sm font-medium text-amber-600 dark:text-amber-400 hover:underline" @click.stop>{{ j.journal_no }}</NuxtLink>
                <span class="num text-xs text-gray-500 dark:text-zinc-500 ml-2">{{ j.journal_date }}</span>
                <p class="text-xs text-gray-500">{{ j.memo }}</p>
              </div>
              <UIcon :name="expanded === j.id ? 'i-heroicons-chevron-up' : 'i-heroicons-chevron-down'" class="text-gray-400" />
            </button>
            <div v-if="expanded === j.id" class="mt-2 text-xs space-y-1">
              <div v-for="l in j.journal_lines" :key="l.id" class="flex justify-between px-2">
                <span :class="Number(l.credit) ? 'pl-6 text-gray-500 dark:text-zinc-500' : 'dark:text-zinc-300'">
                  <span class="num text-gray-400 dark:text-zinc-600">{{ l.accounts?.code }}</span> {{ l.accounts?.name }}
                </span>
                <span class="num">{{ Number(l.debit) ? `Dr ${Number(l.debit).toLocaleString('en-IN')}` : `Cr ${Number(l.credit).toLocaleString('en-IN')}` }}</span>
              </div>
            </div>
          </div>
          <div v-if="!journals.length" class="text-center py-4 text-sm text-gray-400">{{ t('accounting.home.journal_register.empty') }}</div>
        </div>
      </UCard>
    </div>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('accounting.home.journal_dialog.title') }}</p></template>
        <div class="grid grid-cols-2 gap-4 mb-4">
          <UFormGroup :label="t('common.date')"><UInput v-model="jdate" type="date" /></UFormGroup>
          <UFormGroup :label="t('accounting.home.journal_dialog.memo')"><UInput v-model="memo" :placeholder="t('accounting.home.journal_dialog.memo_placeholder')" /></UFormGroup>
        </div>
        <div class="space-y-2">
          <div v-for="(l, idx) in lines" :key="idx" class="grid grid-cols-7 gap-2 items-center">
            <USelect v-model="l.account" :options="accounts" option-attribute="label" value-attribute="code" :placeholder="t('accounting.home.journal_dialog.account_placeholder')" class="col-span-3" />
            <UInput v-model.number="l.debit" type="number" :placeholder="t('accounting.home.journal_dialog.debit_placeholder')" />
            <UInput v-model.number="l.credit" type="number" :placeholder="t('accounting.home.journal_dialog.credit_placeholder')" />
            <UInput v-model="l.note" :placeholder="t('accounting.home.journal_dialog.note_placeholder')" class="col-span-2" />
          </div>
          <div class="flex items-center justify-between">
            <UButton size="xs" variant="soft" icon="i-heroicons-plus" @click="lines.push(blankLine())">{{ t('accounting.home.journal_dialog.add_line') }}</UButton>
            <p class="num text-xs font-medium" :class="Math.abs(sums.d - sums.c) < 0.01 && sums.d > 0 ? 'text-emerald-600 dark:text-emerald-400' : 'text-red-500 dark:text-red-400'">
              {{ t('accounting.home.journal_dialog.balance_line', { debit: sums.d.toLocaleString('en-IN'), credit: sums.c.toLocaleString('en-IN') }) }}
            </p>
          </div>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" :disabled="Math.abs(sums.d - sums.c) > 0.005 || !sums.d" @click="save">{{ t('accounting.home.journal_dialog.post') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
