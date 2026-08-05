<script setup lang="ts">
const client = useSupabaseClient()
const { profile } = useProfile()
const { t } = useI18n()

const rows = ref<any[]>([])
const users = ref<Map<string, string>>(new Map())
const loading = ref(true)
const tableFilter = ref<string | null>(null)
const actionFilter = ref<string | null>(null)

const tables = ref<string[]>([])

const load = async () => {
  loading.value = true
  let q = client.from('audit_log').select('*').order('id', { ascending: false }).limit(200)
  if (tableFilter.value) q = q.eq('table_name', tableFilter.value)
  if (actionFilter.value) q = q.eq('action', actionFilter.value)
  const [{ data }, { data: profiles }] = await Promise.all([
    q,
    client.from('profiles').select('id, full_name')
  ])
  rows.value = data ?? []
  users.value = new Map((profiles ?? []).map((p: any) => [p.id, p.full_name]))
  if (!tables.value.length) {
    tables.value = [...new Set((data ?? []).map((r: any) => r.table_name))].sort()
  }
  loading.value = false
}
onMounted(load)
watch([tableFilter, actionFilter], load)

// show only fields that actually changed on UPDATE
const changes = (row: any) => {
  if (row.action === 'INSERT') return summarize(row.new_data)
  if (row.action === 'DELETE') return summarize(row.old_data)
  const out: string[] = []
  for (const k of Object.keys(row.new_data ?? {})) {
    if (k === 'updated_at') continue
    const a = JSON.stringify(row.old_data?.[k])
    const b = JSON.stringify(row.new_data?.[k])
    if (a !== b) out.push(`${k}: ${trim(a)} → ${trim(b)}`)
  }
  return out.slice(0, 6).join(' · ') || '—'
}
const summarize = (d: any) => {
  if (!d) return '—'
  const keys = ['code', 'name', 'full_name', 'grn_no', 'so_no', 'lc_no', 'challan_no',
    'invoice_no', 'bill_no', 'order_no', 'run_no', 'role', 'status', 'quantity', 'total', 'amount']
  return keys.filter((k) => d[k] != null).map((k) => `${k}=${d[k]}`).slice(0, 5).join(' · ') || '—'
}
const trim = (s: any) => String(s ?? 'null').slice(0, 40)

const actionColor = (a: string) =>
  ({ INSERT: 'green', UPDATE: 'blue', DELETE: 'red' } as any)[a] || 'gray'
</script>

<template>
  <div>
    <PageHeader :kicker="t('nav.sections.admin')" :title="t('system.audit.title')" :subtitle="t('system.audit.subtitle')" />

    <UCard v-if="profile?.role !== 'admin'">
      <p class="text-sm text-gray-500 py-4 text-center">{{ t('system.audit.admin_only') }}</p>
    </UCard>

    <UCard v-else>
      <template #header>
        <div class="flex gap-2">
          <USelect v-model="tableFilter" :options="tables" :placeholder="t('system.audit.all_tables')" size="xs" class="w-44" clearable />
          <USelect v-model="actionFilter" :options="['INSERT', 'UPDATE', 'DELETE']" :placeholder="t('system.audit.all_actions')" size="xs" class="w-36" />
          <UButton size="xs" variant="ghost" icon="i-heroicons-x-mark" @click="tableFilter = null; actionFilter = null" />
        </div>
      </template>
      <UTable
        :rows="rows" :loading="loading"
        :columns="[
          { key: 'created_at', label: t('system.audit.columns.when') },
          { key: 'actor', label: t('system.audit.columns.who') },
          { key: 'action', label: t('system.audit.columns.action') },
          { key: 'table_name', label: t('system.audit.columns.table') },
          { key: 'what', label: t('system.audit.columns.what_changed') }
        ]"
      >
        <template #created_at-data="{ row }">
          <span class="num text-xs text-gray-500 dark:text-zinc-500">
            {{ new Date(row.created_at).toLocaleString() }}
          </span>
        </template>
        <template #actor-data="{ row }">
          {{ row.actor ? (users.get(row.actor) || row.actor.slice(0, 8)) : t('system.audit.system_actor') }}
        </template>
        <template #action-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="actionColor(row.action)">{{ row.action }}</UBadge>
        </template>
        <template #table_name-data="{ row }">
          <span class="num text-xs">{{ row.table_name }}</span>
        </template>
        <template #what-data="{ row }">
          <span class="text-xs text-gray-500 dark:text-zinc-400">{{ changes(row) }}</span>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('system.audit.no_entries') }}</div>
        </template>
      </UTable>
    </UCard>
  </div>
</template>
