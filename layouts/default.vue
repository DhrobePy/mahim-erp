<script setup lang="ts">
const client = useSupabaseClient()
const user = useSupabaseUser()
const { profile, load } = useProfile()
const { canView, load: loadPermissions } = usePermissions()

await load()
await loadPermissions()

const sections = [
  {
    title: 'Executive',
    links: [
      { label: 'CEO overview', to: '/ceo', icon: 'i-heroicons-chart-bar-square', module: 'ceo' }
    ]
  },
  {
    title: 'Operations',
    links: [
      { label: 'Dashboard', to: '/', icon: 'i-heroicons-home', module: 'dashboard' },
      { label: 'Items', to: '/items', icon: 'i-heroicons-cube', module: 'items' },
      { label: 'Stock', to: '/stock', icon: 'i-heroicons-archive-box', module: 'stock' },
      { label: 'BOMs', to: '/boms', icon: 'i-heroicons-rectangle-stack', module: 'boms' },
      { label: 'Production', to: '/production', icon: 'i-heroicons-cog-6-tooth', module: 'production' }
    ]
  },
  {
    title: 'Procurement',
    links: [
      { label: 'Parties', to: '/parties', icon: 'i-heroicons-users', module: 'parties' },
      { label: 'GRNs', to: '/procurement', icon: 'i-heroicons-truck', module: 'procurement' }
    ]
  },
  {
    title: 'Sales & Local LC',
    links: [
      { label: 'Quotations / PI', to: '/quotations', icon: 'i-heroicons-clipboard-document-list', module: 'quotations' },
      { label: 'Sales orders', to: '/sales', icon: 'i-heroicons-shopping-cart', module: 'sales_orders' },
      { label: 'Challans', to: '/challans', icon: 'i-heroicons-document-duplicate', module: 'challans' },
      { label: 'LCs', to: '/lcs', icon: 'i-heroicons-document-check', module: 'lcs' },
      { label: 'Invoices', to: '/invoices', icon: 'i-heroicons-document-text', module: 'invoices' }
    ]
  },
  {
    title: 'Finance',
    links: [
      { label: 'Banking / LBPD', to: '/banking', icon: 'i-heroicons-banknotes', module: 'banking' },
      { label: 'Accounting', to: '/accounting', icon: 'i-heroicons-calculator', module: 'accounting' },
      { label: 'Bank & cash accounts', to: '/accounting/accounts', icon: 'i-heroicons-credit-card', module: 'bank_accounts' },
      { label: 'Cash sales', to: '/accounting/cash-sales', icon: 'i-heroicons-shopping-bag', module: 'cash_sales' },
      { label: 'Transfers', to: '/accounting/transfers', icon: 'i-heroicons-arrows-right-left', module: 'transfers' },
      { label: 'Bank charges & fees', to: '/accounting/bank-charges', icon: 'i-heroicons-currency-dollar', module: 'bank_charges' },
      { label: 'Profit & Loss', to: '/accounting/pnl', icon: 'i-heroicons-chart-bar', module: 'pnl' },
      { label: 'VAT return', to: '/accounting/vat-return', icon: 'i-heroicons-receipt-percent', module: 'vat_return' },
      { label: 'AIT summary', to: '/accounting/ait-summary', icon: 'i-heroicons-document-chart-bar', module: 'ait_summary' }
    ]
  },
  {
    title: 'HR',
    links: [
      { label: 'Employees', to: '/hr', icon: 'i-heroicons-identification', module: 'hr' },
      { label: 'Attendance', to: '/hr/attendance', icon: 'i-heroicons-finger-print', module: 'attendance' },
      { label: 'Payroll', to: '/hr/payroll', icon: 'i-heroicons-currency-bangladeshi', module: 'payroll' },
      { label: 'Office stationery', to: '/hr/stationery', icon: 'i-heroicons-pencil-square', module: 'stationery' }
    ]
  },
  {
    title: 'Admin',
    links: [
      { label: 'Audit trail', to: '/audit', icon: 'i-heroicons-shield-check', module: 'audit' },
      { label: 'Company & structure', to: '/admin/company', icon: 'i-heroicons-building-office-2', module: 'company' },
      { label: 'Directors & partners', to: '/admin/directors', icon: 'i-heroicons-user-group', module: 'directors' },
      { label: 'Board resolutions', to: '/admin/resolutions', icon: 'i-heroicons-clipboard-document-check', module: 'resolutions' },
      { label: 'Company documents', to: '/admin/documents', icon: 'i-heroicons-folder', module: 'documents' },
      { label: 'Forwarding pad', to: '/admin/forwarding', icon: 'i-heroicons-paper-airplane', module: 'forwarding' },
      { label: 'Bank service requests', to: '/admin/bank-requests', icon: 'i-heroicons-building-library', module: 'bank_requests' },
      { label: 'Tax — IT-10B', to: '/admin/tax', icon: 'i-heroicons-calculator', module: 'tax_it10b' },
      { label: 'Corporate tax computation', to: '/admin/tax/corporate', icon: 'i-heroicons-scale', module: 'tax_corporate' }
    ]
  }
]

// "Access & roles" is the tool that grants everyone else's permissions —
// deliberately kept admin-only outright, never toggleable via the same
// system it manages.
const visibleSections = computed(() => {
  const out = sections
    .map((s) => ({ ...s, links: s.links.filter((l) => canView(l.module)) }))
    .filter((s) => s.links.length)
  if (profile.value?.role === 'admin') {
    const admin = out.find((s) => s.title === 'Admin')
    const accessLink = { label: 'Access & roles', to: '/access', icon: 'i-heroicons-key', module: 'access' }
    if (admin) admin.links.unshift(accessLink)
    else out.push({ title: 'Admin', links: [accessLink] })
  }
  return out
})

// Collapsible sections: user's choices persist; the section holding the
// current route always opens so you never lose your place.
const route = useRoute()
const openSections = ref<Record<string, boolean>>({})
onMounted(() => {
  try {
    openSections.value = JSON.parse(localStorage.getItem('erp-nav-open') || '{}')
  } catch { openSections.value = {} }
  expandActive()
})
const sectionOf = (path: string) =>
  visibleSections.value.find((s) => s.links.some((l) =>
    l.to === '/' ? path === '/' : path.startsWith(l.to)))?.title
const expandActive = () => {
  const t = sectionOf(route.path)
  if (t) openSections.value[t] = true
}
watch(() => route.path, expandActive)
const isOpen = (title: string) => openSections.value[title] !== false
const toggle = (title: string) => {
  openSections.value[title] = !isOpen(title)
  try { localStorage.setItem('erp-nav-open', JSON.stringify(openSections.value)) } catch {}
}

// Sidebar: desktop collapses to an icon-only rail; mobile slides in as an
// overlay drawer over the content instead of permanently eating viewport width.
const sidebarCollapsed = ref(false)
const mobileNavOpen = ref(false)
onMounted(() => {
  try { sidebarCollapsed.value = localStorage.getItem('erp-nav-collapsed') === '1' } catch {}
})
const toggleCollapsed = () => {
  sidebarCollapsed.value = !sidebarCollapsed.value
  try { localStorage.setItem('erp-nav-collapsed', sidebarCollapsed.value ? '1' : '0') } catch {}
}
watch(() => route.path, () => { mobileNavOpen.value = false })

const signOut = async () => {
  await client.auth.signOut()
  await navigateTo('/login')
}

const displayName = computed(() => profile.value?.full_name || user.value?.email || 'User')
const profileMenu = computed(() => [
  [{ label: displayName.value, disabled: true, icon: 'i-heroicons-user-circle' }],
  [{ label: 'Sign out', icon: 'i-heroicons-arrow-right-on-rectangle', click: signOut }]
])
</script>

<template>
  <div class="min-h-screen flex bg-gray-50 dark:bg-[#09090b]">
    <!-- Mobile backdrop -->
    <div
      v-if="mobileNavOpen" class="fixed inset-0 bg-black/50 z-30 lg:hidden"
      @click="mobileNavOpen = false"
    />

    <!-- Sidebar -->
    <aside
      class="shrink-0 border-r border-gray-200 dark:border-zinc-800/80 bg-white dark:bg-[#0c0c0f] flex flex-col
             fixed inset-y-0 left-0 z-40 transition-[transform,width] duration-200 lg:static lg:translate-x-0"
      :class="[
        mobileNavOpen ? 'translate-x-0' : '-translate-x-full',
        sidebarCollapsed ? 'w-16' : 'w-56'
      ]"
    >
      <div
        class="h-12 flex items-center gap-2.5 border-b border-gray-200 dark:border-zinc-800/80 shrink-0"
        :class="sidebarCollapsed ? 'justify-center px-0' : 'px-4'"
      >
        <div class="w-6 h-6 rounded-sm bg-amber-500 flex items-center justify-center shrink-0">
          <UIcon name="i-heroicons-cube-transparent" class="text-black text-sm" />
        </div>
        <div v-if="!sidebarCollapsed" class="leading-none">
          <p class="font-semibold text-[13px] tracking-tight dark:text-zinc-100">MAHIM</p>
          <p class="microlabel text-gray-400 dark:text-zinc-600 mt-0.5">Packaging ERP</p>
        </div>
      </div>

      <nav class="py-2 flex-1 overflow-y-auto overflow-x-hidden">
        <template v-for="section in visibleSections" :key="section.title">
          <button
            v-if="!sidebarCollapsed"
            class="w-full flex items-center justify-between px-4 pt-3.5 pb-1 cursor-pointer group"
            @click="toggle(section.title)"
          >
            <span class="microlabel text-gray-400 dark:text-zinc-600 group-hover:text-gray-600 dark:group-hover:text-zinc-400">
              {{ section.title }}
            </span>
            <UIcon
              :name="isOpen(section.title) ? 'i-heroicons-chevron-down' : 'i-heroicons-chevron-right'"
              class="text-xs text-gray-300 dark:text-zinc-700 group-hover:text-gray-500 dark:group-hover:text-zinc-500"
            />
          </button>
          <template v-if="sidebarCollapsed || isOpen(section.title)">
            <ULink
              v-for="link in section.links"
              :key="link.to"
              :to="link.to"
              :title="sidebarCollapsed ? link.label : undefined"
              active-class="!border-amber-500 !text-amber-600 dark:!text-amber-400 bg-amber-50/60 dark:bg-amber-500/[0.06]"
              class="flex items-center gap-2.5 py-[7px] text-[13px] border-l-2 border-transparent text-gray-600 dark:text-zinc-400 hover:text-gray-900 dark:hover:text-zinc-200 hover:bg-gray-50 dark:hover:bg-zinc-900 transition-colors duration-150 cursor-pointer"
              :class="sidebarCollapsed ? 'justify-center px-0' : 'pl-[15px] pr-3'"
              @click="mobileNavOpen = false"
            >
              <UIcon :name="link.icon" class="text-base opacity-70 shrink-0" />
              <span v-if="!sidebarCollapsed">{{ link.label }}</span>
            </ULink>
          </template>
        </template>
      </nav>

      <div v-if="!sidebarCollapsed" class="px-4 py-3 border-t border-gray-200 dark:border-zinc-800/80 shrink-0">
        <p class="microlabel text-gray-400 dark:text-zinc-600">Company</p>
        <p class="text-[12px] mt-0.5 dark:text-zinc-300 truncate">Mahim Packaging Ltd.</p>
      </div>

      <button
        class="hidden lg:flex items-center justify-center h-9 shrink-0 border-t border-gray-200 dark:border-zinc-800/80 text-gray-400 dark:text-zinc-600 hover:text-gray-700 dark:hover:text-zinc-300 hover:bg-gray-50 dark:hover:bg-zinc-900 cursor-pointer"
        :aria-label="sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar'"
        @click="toggleCollapsed"
      >
        <UIcon :name="sidebarCollapsed ? 'i-heroicons-chevron-double-right' : 'i-heroicons-chevron-double-left'" class="text-sm" />
      </button>
    </aside>

    <!-- Main -->
    <div class="flex-1 flex flex-col min-w-0">
      <header class="h-12 shrink-0 flex items-center justify-between gap-2.5 px-3 lg:px-5 border-b border-gray-200 dark:border-zinc-800/80 bg-white dark:bg-[#0c0c0f]">
        <button
          class="lg:hidden flex items-center justify-center cursor-pointer text-gray-500 dark:text-zinc-400"
          aria-label="Open menu" @click="mobileNavOpen = true"
        >
          <UIcon name="i-heroicons-bars-3" class="text-xl" />
        </button>
        <div class="flex-1" />
        <div class="flex items-center gap-2.5">
          <NotificationBell />
          <span class="microlabel px-1.5 py-0.5 rounded border border-amber-500/40 text-amber-600 dark:text-amber-400">
            {{ profile?.role || 'viewer' }}
          </span>
          <UDropdown :items="profileMenu" :popper="{ placement: 'bottom-end' }">
            <button class="flex items-center gap-2 rounded-full cursor-pointer hover:opacity-80" aria-label="Profile menu">
              <UAvatar
                :alt="displayName"
                size="sm"
                :ui="{ background: 'bg-amber-500 dark:bg-amber-500', text: 'text-black font-semibold' }"
              />
            </button>
          </UDropdown>
        </div>
      </header>

      <main class="flex-1 overflow-auto p-3 sm:p-5">
        <slot />
      </main>
    </div>
  </div>
</template>
