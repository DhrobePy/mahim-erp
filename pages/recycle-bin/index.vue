<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { activeCompanyId } = useProfile()
const { modules, load: loadPermissions, canWriteModule } = usePermissions()

const rows = ref<any[]>([])
const loading = ref(true)
const moduleFilter = ref<string | null>(null)
const restoringId = ref<string | null>(null)

const moduleLabel = (key: string) => modules.value.find((m) => m.key === key)?.label ?? key

const load = async () => {
  if (!activeCompanyId.value) return
  loading.value = true
  await loadPermissions()
  const { data, error } = await client.rpc('list_deleted_records', { p_company: activeCompanyId.value } as any)
  if (error) toast.add({ title: 'Failed to load recycle bin', description: error.message, color: 'red' })
  rows.value = (data ?? []).sort((a: any, b: any) => new Date(b.deleted_at).getTime() - new Date(a.deleted_at).getTime())
  loading.value = false
}
onMounted(load)

const filtered = computed(() =>
  moduleFilter.value ? rows.value.filter((r) => r.module_key === moduleFilter.value) : rows.value
)
const moduleOptions = computed(() => [...new Set(rows.value.map((r) => r.module_key))].map((k) => ({ label: moduleLabel(k), value: k })))

const restore = async (row: any) => {
  restoringId.value = row.record_id
  try {
    const { error } = await client.rpc('restore_record', { p_table: row.table_name, p_id: row.record_id } as any)
    if (error) throw error
    toast.add({ title: `Restored "${row.display_label}"` })
    await load()
  } catch (e: any) {
    toast.add({ title: 'Restore failed', description: e.message, color: 'red' })
  } finally {
    restoringId.value = null
  }
}
</script>

<template>
  <div>
    <PageHeader
      kicker="Admin" title="Recycle bin"
      subtitle="Deleted records across every module — master data is restored as-is; posted documents are un-reversed (a new offsetting entry restores the original ledger effect)"
    />

    <UCard>
      <template #header>
        <div class="flex gap-2 items-center">
          <USelect
            v-model="moduleFilter" :options="moduleOptions" option-attribute="label" value-attribute="value"
            placeholder="All modules" size="xs" class="w-56"
          />
          <UButton v-if="moduleFilter" size="xs" variant="ghost" icon="i-heroicons-x-mark" @click="moduleFilter = null" />
          <span class="ml-auto text-xs text-gray-400 dark:text-zinc-500">{{ filtered.length }} deleted record(s)</span>
        </div>
      </template>

      <UTable
        :rows="filtered" :loading="loading"
        :columns="[
          { key: 'display_label', label: 'Record' },
          { key: 'module_key', label: 'Module' },
          { key: 'deleted_at', label: 'Deleted' },
          { key: 'deleted_by_name', label: 'Deleted by' },
          { key: 'actions', label: '' }
        ]"
      >
        <template #display_label-data="{ row }">
          <span class="font-medium dark:text-zinc-100">{{ row.display_label }}</span>
          <span class="text-xs text-gray-400 dark:text-zinc-500 num ml-1.5">{{ row.table_name }}</span>
        </template>
        <template #module_key-data="{ row }">
          <UBadge size="xs" variant="subtle" color="gray">{{ moduleLabel(row.module_key) }}</UBadge>
        </template>
        <template #deleted_at-data="{ row }">
          <span class="num text-xs text-gray-500 dark:text-zinc-500">{{ new Date(row.deleted_at).toLocaleString() }}</span>
        </template>
        <template #deleted_by_name-data="{ row }">
          <span class="text-xs text-gray-500 dark:text-zinc-400">{{ row.deleted_by_name }}</span>
        </template>
        <template #actions-data="{ row }">
          <UButton
            v-if="canWriteModule(row.module_key)"
            size="xs" variant="soft" icon="i-heroicons-arrow-uturn-left"
            :loading="restoringId === row.record_id" @click="restore(row)"
          >Restore</UButton>
        </template>
        <template #empty-state>
          <div class="text-center py-8 text-sm text-gray-400">Nothing in the recycle bin.</div>
        </template>
      </UTable>
    </UCard>
  </div>
</template>
