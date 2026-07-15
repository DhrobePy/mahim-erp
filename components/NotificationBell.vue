<script setup lang="ts">
const client = useSupabaseClient()
const { activeCompanyId } = useProfile()

const notifications = ref<any[]>([])
const alerts = ref<any[]>([])
let timer: any = null

const unread = computed(() => notifications.value.filter((n) => !n.is_read).length)
const badge = computed(() => unread.value + alerts.value.length)

const load = async () => {
  const [n, a] = await Promise.all([
    client.from('notifications').select('*').order('created_at', { ascending: false }).limit(15),
    client.from('v_lc_alerts').select('*')
  ])
  notifications.value = n.data ?? []
  alerts.value = a.data ?? []
}

onMounted(() => {
  load()
  // flag overdue bills once per app load, then refresh periodically
  if (activeCompanyId.value) {
    client.rpc('flag_overdue_bills', { p_company: activeCompanyId.value } as any).then(() => load())
  }
  timer = setInterval(load, 60000)
})
onBeforeUnmount(() => clearInterval(timer))

const markAllRead = async () => {
  await client.from('notifications').update({ is_read: true } as any).eq('is_read', false)
  await load()
}

const alertLabel = (a: any) =>
  a.alert_type === 'overdue'
    ? `OVERDUE: bill ${a.bill_no} of ${a.lc_no} matured ${a.maturity_date}`
    : a.alert_type === 'maturity_soon'
      ? `Maturity in ${a.days}d: bill ${a.bill_no} (${a.lc_no})`
      : `Open discrepancy on ${a.lc_no}`
const alertColor = (a: any) =>
  a.alert_type === 'overdue' ? 'text-red-500 dark:text-red-400'
    : a.alert_type === 'maturity_soon' ? 'text-amber-600 dark:text-amber-400'
      : 'text-purple-500 dark:text-purple-400'
</script>

<template>
  <UPopover :popper="{ placement: 'bottom-end' }">
    <button class="relative p-1.5 rounded hover:bg-gray-100 dark:hover:bg-zinc-800 cursor-pointer" aria-label="Notifications">
      <UIcon name="i-heroicons-bell" class="text-lg text-gray-500 dark:text-zinc-400" />
      <span
        v-if="badge"
        class="num absolute -top-0.5 -right-0.5 min-w-[16px] h-4 px-0.5 rounded-full bg-amber-500 text-black text-[10px] font-semibold flex items-center justify-center"
      >{{ badge }}</span>
    </button>

    <template #panel>
      <div class="w-96 max-h-[70vh] overflow-y-auto">
        <div v-if="alerts.length" class="p-3 border-b border-gray-200 dark:border-zinc-800">
          <p class="microlabel text-gray-400 dark:text-zinc-500 mb-2">Live alerts</p>
          <NuxtLink
            v-for="(a, i) in alerts" :key="i" :to="`/lcs/${a.lc_id}`"
            class="block py-1 text-[12.5px] font-medium cursor-pointer hover:underline"
            :class="alertColor(a)"
          >{{ alertLabel(a) }}</NuxtLink>
        </div>
        <div class="p-3">
          <div class="flex items-center justify-between mb-2">
            <p class="microlabel text-gray-400 dark:text-zinc-500">Notifications</p>
            <UButton v-if="unread" size="2xs" variant="ghost" @click="markAllRead">Mark all read</UButton>
          </div>
          <div v-if="!notifications.length" class="text-sm text-gray-400 py-3 text-center">Nothing yet.</div>
          <div
            v-for="n in notifications" :key="n.id"
            class="py-1.5 border-b border-gray-100 dark:border-zinc-800/60 last:border-0"
            :class="n.is_read ? 'opacity-50' : ''"
          >
            <div class="flex items-start justify-between gap-2">
              <NuxtLink
                :to="n.ref_table === 'lcs' && n.ref_id ? `/lcs/${n.ref_id}` : '#'"
                class="text-[12.5px] font-medium dark:text-zinc-200 hover:underline"
              >{{ n.title }}</NuxtLink>
              <span class="num text-[10px] text-gray-400 dark:text-zinc-600 shrink-0">
                {{ new Date(n.created_at).toLocaleDateString() }}
              </span>
            </div>
            <p v-if="n.body" class="text-[11.5px] text-gray-500 dark:text-zinc-500">{{ n.body }}</p>
          </div>
        </div>
      </div>
    </template>
  </UPopover>
</template>
