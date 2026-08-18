<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { money } = useFmt()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const accounts = ref<any[]>([])
const banks = ref<any[]>([])
const branches = ref<any[]>([])
const loading = ref(true)

const load = async () => {
  loading.value = true
  const [a, bk, br, del] = await Promise.all([
    client.from('v_cash_bank_balances').select('*').order('kind'),
    client.from('parties').select('id, name').eq('is_bank', true).is('deleted_at', null).order('name'),
    client.from('bank_branches').select('id, branch_name, bank_party_id').order('branch_name'),
    // v_cash_bank_balances has no deleted_at column, so hide soft-deleted
    // cash_bank_accounts rows client-side instead
    client.from('cash_bank_accounts').select('id').not('deleted_at', 'is', null)
  ])
  const deletedIds = new Set((del.data ?? []).map((d: any) => d.id))
  accounts.value = (a.data ?? []).filter((x: any) => !deletedIds.has(x.id))
  banks.value = bk.data ?? []
  branches.value = br.data ?? []
  loading.value = false
}
onMounted(load)

const bankAccounts = computed(() => accounts.value.filter((a) => a.kind === 'bank'))
const cashAccounts = computed(() => accounts.value.filter((a) => a.kind === 'cash'))

const open = ref(false)
const saving = ref(false)
const form = reactive({
  id: null as string | null,
  kind: 'bank', name: '', bank_party_id: null as string | null, branch_id: null as string | null,
  account_no: '', opening_balance: 0, opening_date: new Date().toISOString().slice(0, 10),
  is_active: true
})
const branchesForBank = computed(() => branches.value.filter((b) => b.bank_party_id === form.bank_party_id))
const openNew = () => {
  Object.assign(form, {
    id: null, kind: 'bank', name: '', bank_party_id: null, branch_id: null,
    account_no: '', opening_balance: 0, opening_date: new Date().toISOString().slice(0, 10),
    is_active: true
  })
  open.value = true
}
const openEdit = async (row: any) => {
  const { data, error } = await client.from('cash_bank_accounts').select('*').eq('id', row.id).single()
  if (error) { toast.add({ title: t('common.save_failed'), description: error.message, color: 'red' }); return }
  Object.assign(form, {
    id: data.id, kind: data.kind, name: data.name, bank_party_id: data.bank_party_id, branch_id: data.branch_id,
    account_no: data.account_no, opening_balance: data.opening_balance, opening_date: data.opening_date,
    is_active: data.is_active
  })
  open.value = true
}

const save = async () => {
  if (!form.name) { toast.add({ title: t('accounting.accounts.toasts.name_required'), color: 'red' }); return }
  if (form.kind === 'bank' && !form.bank_party_id) { toast.add({ title: t('accounting.accounts.toasts.pick_bank'), color: 'red' }); return }
  saving.value = true
  try {
    if (form.id) {
      const payload: any = { name: form.name, account_no: form.account_no, is_active: form.is_active, bank_party_id: form.bank_party_id, branch_id: form.branch_id }
      if (form.kind === 'cash') { payload.bank_party_id = null; payload.branch_id = null }
      const { error } = await client.from('cash_bank_accounts').update(payload).eq('id', form.id)
      if (error) throw error
      toast.add({ title: t('accounting.accounts.toasts.updated') })
    } else {
      const payload: any = { kind: form.kind, name: form.name, bank_party_id: form.bank_party_id, branch_id: form.branch_id, account_no: form.account_no, opening_balance: form.opening_balance, opening_date: form.opening_date }
      if (form.kind === 'cash') { payload.bank_party_id = null; payload.branch_id = null }
      const { error } = await client.from('cash_bank_accounts').insert(payload)
      if (error) throw error
      toast.add({ title: t('accounting.accounts.toasts.created') })
    }
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('common.save_failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

const removeAccount = async (a: any) => {
  const ok = await deleteRecord('cash_bank_accounts', a.id, a.name)
  if (ok) await load()
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('accounting.kicker')" :title="t('accounting.accounts.title')" :subtitle="t('accounting.accounts.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('accounting.accounts.new_account') }}</UButton>
    </PageHeader>

    <div class="grid grid-cols-1 xl:grid-cols-2 gap-4">
      <UCard>
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('accounting.accounts.bank_accounts') }}</p></template>
        <div v-if="!bankAccounts.length" class="text-sm text-gray-400 py-3 text-center">{{ t('accounting.accounts.none_yet') }}</div>
        <div
          v-for="a in bankAccounts" :key="a.id"
          class="flex justify-between items-center py-2 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0 -mx-1 px-1 rounded"
        >
          <NuxtLink :to="`/accounting/reconcile/${a.id}`" class="flex-1 hover:underline dark:text-zinc-200">
            {{ a.name }} <span class="num text-[11px] text-gray-400 dark:text-zinc-600">{{ a.gl_code }}</span>
            <UBadge v-if="!a.is_active" size="xs" variant="subtle" color="gray" class="ml-1">{{ t('accounting.accounts.inactive') }}</UBadge>
          </NuxtLink>
          <span class="num font-medium">{{ money(a.balance) }}</span>
          <UButton v-if="canWrite" icon="i-heroicons-pencil-square" variant="ghost" size="xs" class="ml-2" @click="openEdit(a)" />
          <UButton v-if="canWrite" icon="i-heroicons-trash" color="red" variant="ghost" size="xs" class="ml-1" @click="removeAccount(a)" />
        </div>
      </UCard>

      <UCard>
        <template #header><p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('accounting.accounts.cash_points') }}</p></template>
        <div v-if="!cashAccounts.length" class="text-sm text-gray-400 py-3 text-center">{{ t('accounting.accounts.none_yet') }}</div>
        <div v-for="a in cashAccounts" :key="a.id" class="flex justify-between items-center py-2 text-[13px] border-b border-gray-100 dark:border-zinc-800/60 last:border-0">
          <span class="dark:text-zinc-200">
            {{ a.name }} <span class="num text-[11px] text-gray-400 dark:text-zinc-600">{{ a.gl_code }}</span>
          </span>
          <span class="num font-medium">{{ money(a.balance) }}</span>
          <UButton v-if="canWrite" icon="i-heroicons-pencil-square" variant="ghost" size="xs" class="ml-2" @click="openEdit(a)" />
          <UButton v-if="canWrite" icon="i-heroicons-trash" color="red" variant="ghost" size="xs" class="ml-1" @click="removeAccount(a)" />
        </div>
      </UCard>
    </div>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ form.id ? t('accounting.accounts.dialog.edit_title') : t('accounting.accounts.dialog.title') }}</p></template>
        <div class="space-y-3">
          <UFormGroup :label="t('accounting.accounts.dialog.kind')">
            <div class="flex gap-2">
              <button
                :disabled="!!form.id"
                class="px-4 py-1.5 rounded text-sm border"
                :class="[form.kind === 'bank' ? 'border-amber-500 text-amber-600 dark:text-amber-400 bg-amber-50/60 dark:bg-amber-500/10' : 'border-gray-200 dark:border-zinc-700 text-gray-500', form.id ? 'opacity-60 cursor-not-allowed' : 'cursor-pointer']"
                @click="!form.id && (form.kind = 'bank')"
              >{{ t('accounting.accounts.dialog.bank_account_option') }}</button>
              <button
                :disabled="!!form.id"
                class="px-4 py-1.5 rounded text-sm border"
                :class="[form.kind === 'cash' ? 'border-amber-500 text-amber-600 dark:text-amber-400 bg-amber-50/60 dark:bg-amber-500/10' : 'border-gray-200 dark:border-zinc-700 text-gray-500', form.id ? 'opacity-60 cursor-not-allowed' : 'cursor-pointer']"
                @click="!form.id && (form.kind = 'cash')"
              >{{ t('accounting.accounts.dialog.cash_point_option') }}</button>
            </div>
          </UFormGroup>
          <UFormGroup :label="t('common.name')" required><UInput v-model="form.name" :placeholder="t('accounting.accounts.dialog.name_placeholder')" /></UFormGroup>
          <template v-if="form.kind === 'bank'">
            <UFormGroup :label="t('accounting.accounts.dialog.bank')" required>
              <USelect v-model="form.bank_party_id" :options="banks" option-attribute="name" value-attribute="id" placeholder="—" />
            </UFormGroup>
            <UFormGroup :label="t('accounting.accounts.dialog.branch')" :hint="t('accounting.accounts.dialog.branch_hint')">
              <USelect v-model="form.branch_id" :options="branchesForBank" option-attribute="branch_name" value-attribute="id" placeholder="—" />
            </UFormGroup>
            <UFormGroup :label="t('accounting.accounts.dialog.account_no')"><UInput v-model="form.account_no" /></UFormGroup>
          </template>
          <div class="grid grid-cols-2 gap-3">
            <UFormGroup :label="t('accounting.accounts.dialog.opening_balance')" :hint="form.id ? t('accounting.accounts.dialog.opening_locked_hint') : undefined">
              <UInput v-model.number="form.opening_balance" type="number" :disabled="!!form.id" />
            </UFormGroup>
            <UFormGroup :label="t('accounting.accounts.dialog.as_of')">
              <UInput v-model="form.opening_date" type="date" :disabled="!!form.id" />
            </UFormGroup>
          </div>
          <UCheckbox v-if="form.id" v-model="form.is_active" :label="t('accounting.accounts.dialog.is_active')" />
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ form.id ? t('common.save') : t('common.create') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
