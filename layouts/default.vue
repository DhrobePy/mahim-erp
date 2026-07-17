<script setup lang="ts">
const client = useSupabaseClient()
const user = useSupabaseUser()
const { profile, load } = useProfile()

await load()

const sections = [
  {
    title: 'Executive',
    links: [
      { label: 'CEO overview', to: '/ceo', icon: 'i-heroicons-chart-bar-square' }
    ]
  },
  {
    title: 'Operations',
    links: [
      { label: 'Dashboard', to: '/', icon: 'i-heroicons-home' },
      { label: 'Items', to: '/items', icon: 'i-heroicons-cube' },
      { label: 'Stock', to: '/stock', icon: 'i-heroicons-archive-box' },
      { label: 'BOMs', to: '/boms', icon: 'i-heroicons-rectangle-stack' },
      { label: 'Production', to: '/production', icon: 'i-heroicons-cog-6-tooth' }
    ]
  },
  {
    title: 'Procurement',
    links: [
      { label: 'Parties', to: '/parties', icon: 'i-heroicons-users' },
      { label: 'GRNs', to: '/procurement', icon: 'i-heroicons-truck' }
    ]
  },
  {
    title: 'Sales & Local LC',
    links: [
      { label: 'Quotations / PI', to: '/quotations', icon: 'i-heroicons-clipboard-document-list' },
      { label: 'Sales orders', to: '/sales', icon: 'i-heroicons-shopping-cart' },
      { label: 'Challans', to: '/challans', icon: 'i-heroicons-document-duplicate' },
      { label: 'LCs', to: '/lcs', icon: 'i-heroicons-document-check' },
      { label: 'Invoices', to: '/invoices', icon: 'i-heroicons-document-text' }
    ]
  },
  {
    title: 'Finance',
    links: [
      { label: 'Banking / LBPD', to: '/banking', icon: 'i-heroicons-banknotes' },
      { label: 'Accounting', to: '/accounting', icon: 'i-heroicons-calculator' }
    ]
  },
  {
    title: 'HR',
    links: [
      { label: 'Employees', to: '/hr', icon: 'i-heroicons-identification' },
      { label: 'Attendance', to: '/hr/attendance', icon: 'i-heroicons-finger-print' },
      { label: 'Payroll', to: '/hr/payroll', icon: 'i-heroicons-currency-bangladeshi' }
    ]
  }
]

const adminSection = {
  title: 'Admin',
  links: [
    { label: 'Access & roles', to: '/access', icon: 'i-heroicons-key' },
    { label: 'Audit trail', to: '/audit', icon: 'i-heroicons-shield-check' },
    { label: 'Company & structure', to: '/admin/company', icon: 'i-heroicons-building-office-2' },
    { label: 'Directors & partners', to: '/admin/directors', icon: 'i-heroicons-user-group' },
    { label: 'Company documents', to: '/admin/documents', icon: 'i-heroicons-folder' },
    { label: 'Forwarding pad', to: '/admin/forwarding', icon: 'i-heroicons-paper-airplane' },
    { label: 'Tax — IT-10B', to: '/admin/tax', icon: 'i-heroicons-calculator' }
  ]
}
const visibleSections = computed(() =>
  profile.value?.role === 'admin' ? [...sections, adminSection] : sections
)

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
    <!-- Sidebar -->
    <aside class="w-56 shrink-0 border-r border-gray-200 dark:border-zinc-800/80 bg-white dark:bg-[#0c0c0f] flex flex-col">
      <div class="h-12 flex items-center gap-2.5 px-4 border-b border-gray-200 dark:border-zinc-800/80">
        <div class="w-6 h-6 rounded-sm bg-amber-500 flex items-center justify-center">
          <UIcon name="i-heroicons-cube-transparent" class="text-black text-sm" />
        </div>
        <div class="leading-none">
          <p class="font-semibold text-[13px] tracking-tight dark:text-zinc-100">MAHIM</p>
          <p class="microlabel text-gray-400 dark:text-zinc-600 mt-0.5">Packaging ERP</p>
        </div>
      </div>

      <nav class="py-2 flex-1 overflow-y-auto">
        <template v-for="section in visibleSections" :key="section.title">
          <button
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
          <template v-if="isOpen(section.title)">
            <ULink
              v-for="link in section.links"
              :key="link.to"
              :to="link.to"
              active-class="!border-amber-500 !text-amber-600 dark:!text-amber-400 bg-amber-50/60 dark:bg-amber-500/[0.06]"
              class="flex items-center gap-2.5 pl-[15px] pr-3 py-[7px] text-[13px] border-l-2 border-transparent text-gray-600 dark:text-zinc-400 hover:text-gray-900 dark:hover:text-zinc-200 hover:bg-gray-50 dark:hover:bg-zinc-900 transition-colors duration-150 cursor-pointer"
            >
              <UIcon :name="link.icon" class="text-base opacity-70" />
              {{ link.label }}
            </ULink>
          </template>
        </template>
      </nav>

      <div class="px-4 py-3 border-t border-gray-200 dark:border-zinc-800/80">
        <p class="microlabel text-gray-400 dark:text-zinc-600">Company</p>
        <p class="text-[12px] mt-0.5 dark:text-zinc-300 truncate">Mahim Packaging Ltd.</p>
      </div>
    </aside>

    <!-- Main -->
    <div class="flex-1 flex flex-col min-w-0">
      <header class="h-12 shrink-0 flex items-center justify-end gap-2.5 px-5 border-b border-gray-200 dark:border-zinc-800/80 bg-white dark:bg-[#0c0c0f]">
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
      </header>

      <main class="flex-1 overflow-auto p-5">
        <slot />
      </main>
    </div>
  </div>
</template>
