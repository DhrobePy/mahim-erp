<script setup lang="ts">
import { manualEn } from '~/data/manual/en'
import { manualBn } from '~/data/manual/bn'
import type { ManualSection } from '~/data/manual/types'

const { t, locale } = useI18n()

// The manual has its own language toggle, independent of the app's UI
// language — someone reading the UI in English may still want the manual
// in Bangla, or vice versa. Defaults to whatever the UI is currently set to.
const manualLang = ref<'en' | 'bn'>(locale.value === 'bn' ? 'bn' : 'en')
const sections = computed<ManualSection[]>(() => (manualLang.value === 'bn' ? manualBn : manualEn))

// The toolbar sits directly against the manual content, so it follows the
// manual's own language toggle rather than the app-wide locale — only the
// page header above stays tied to the app's UI language, like every other page.
const chrome = computed(() => (manualLang.value === 'bn'
  ? {
      search: 'নির্দেশিকায় খুঁজুন...',
      expandAll: 'সব খুলুন',
      collapseAll: 'সব বন্ধ করুন',
      openPage: 'এই পাতাটি খুলুন',
      noResults: 'আপনার খোঁজার সাথে কোনো সেকশন মেলেনি।'
    }
  : {
      search: 'Search the manual...',
      expandAll: 'Expand all',
      collapseAll: 'Collapse all',
      openPage: 'Open this page',
      noResults: 'No sections match your search.'
    }))

const query = ref('')
const filteredSections = computed(() => {
  const q = query.value.trim().toLowerCase()
  if (!q) return sections.value
  return sections.value
    .map((section) => ({
      ...section,
      modules: section.modules.filter((m) =>
        m.title.toLowerCase().includes(q) ||
        m.purpose.toLowerCase().includes(q) ||
        m.tasks.some((task) => task.heading.toLowerCase().includes(q) || task.steps.some((s) => s.toLowerCase().includes(q)))
      )
    }))
    .filter((section) => section.modules.length)
})

// Native <details> elements — each module keeps its own open/closed state
// keyed by section+module so switching language doesn't reset it.
const openKeys = ref<Set<string>>(new Set())
const isOpen = (sectionKey: string, moduleKey: string) => openKeys.value.has(`${sectionKey}.${moduleKey}`)
const toggle = (sectionKey: string, moduleKey: string, open: boolean) => {
  const k = `${sectionKey}.${moduleKey}`
  if (open) openKeys.value.add(k)
  else openKeys.value.delete(k)
}
const expandAll = () => {
  const next = new Set<string>()
  for (const s of sections.value) for (const m of s.modules) next.add(`${s.key}.${m.key}`)
  openKeys.value = next
}
const collapseAll = () => { openKeys.value = new Set() }
</script>

<template>
  <div>
    <PageHeader :kicker="t('admin.manual.kicker')" :title="t('admin.manual.title')" :subtitle="t('admin.manual.subtitle')" />

    <div class="flex flex-wrap items-center gap-3 mb-4">
      <div class="inline-flex rounded-md ring-1 ring-gray-200 dark:ring-zinc-800 overflow-hidden shrink-0" role="tablist" :aria-label="t('admin.manual.language_label')">
        <button
          type="button" role="tab" :aria-selected="manualLang === 'en'"
          class="px-3 py-1.5 text-[13px] font-medium transition-colors"
          :class="manualLang === 'en' ? 'bg-amber-500 text-black' : 'bg-white dark:bg-zinc-900/60 text-gray-600 dark:text-zinc-400 hover:text-gray-900 dark:hover:text-zinc-100'"
          @click="manualLang = 'en'"
        >
          English
        </button>
        <button
          type="button" role="tab" :aria-selected="manualLang === 'bn'"
          class="px-3 py-1.5 text-[13px] font-medium transition-colors"
          :class="manualLang === 'bn' ? 'bg-amber-500 text-black' : 'bg-white dark:bg-zinc-900/60 text-gray-600 dark:text-zinc-400 hover:text-gray-900 dark:hover:text-zinc-100'"
          @click="manualLang = 'bn'"
        >
          বাংলা
        </button>
      </div>

      <UInput v-model="query" icon="i-heroicons-magnifying-glass" :placeholder="chrome.search" size="sm" class="w-64" />

      <div class="flex gap-2 ml-auto">
        <UButton size="xs" variant="soft" color="gray" @click="expandAll">{{ chrome.expandAll }}</UButton>
        <UButton size="xs" variant="soft" color="gray" @click="collapseAll">{{ chrome.collapseAll }}</UButton>
      </div>
    </div>

    <div v-if="!filteredSections.length" class="text-sm text-gray-400 py-10 text-center">{{ chrome.noResults }}</div>

    <div v-for="section in filteredSections" :key="section.key" class="mb-6">
      <p class="microlabel text-gray-400 dark:text-zinc-500 mb-2">{{ section.title }}</p>
      <div class="space-y-2">
        <details
          v-for="mod in section.modules" :key="mod.key"
          class="group rounded-md ring-1 ring-gray-200 dark:ring-zinc-800 bg-white dark:bg-zinc-900/60 overflow-hidden"
          :open="isOpen(section.key, mod.key)"
          @toggle="(e) => toggle(section.key, mod.key, (e.target as HTMLDetailsElement).open)"
        >
          <summary class="flex items-center gap-2.5 px-4 py-3 cursor-pointer select-none list-none">
            <UIcon :name="mod.icon" class="text-[15px] text-amber-600 dark:text-amber-400 shrink-0" />
            <span class="text-[13.5px] font-medium text-gray-900 dark:text-zinc-100 flex-1">{{ mod.title }}</span>
            <NuxtLink
              v-if="mod.route" :to="mod.route"
              class="text-[11px] text-amber-600 dark:text-amber-400 hover:underline shrink-0"
              @click.stop
            >
              {{ chrome.openPage }} →
            </NuxtLink>
            <UIcon name="i-heroicons-chevron-down" class="text-[13px] text-gray-400 dark:text-zinc-600 shrink-0 transition-transform group-open:rotate-180" />
          </summary>

          <div class="px-4 pb-4 pt-0.5 border-t border-gray-100 dark:border-zinc-800/60 space-y-3.5">
            <p class="text-[13px] text-gray-600 dark:text-zinc-400 leading-relaxed pt-3">{{ mod.purpose }}</p>

            <p v-if="mod.statuses" class="text-[11.5px] font-mono text-gray-500 dark:text-zinc-500 bg-gray-50 dark:bg-zinc-800/50 rounded px-2.5 py-1.5 inline-block">
              {{ mod.statuses }}
            </p>

            <div v-for="(task, i) in mod.tasks" :key="i">
              <p class="text-[12px] font-semibold text-gray-800 dark:text-zinc-200 mb-1">{{ task.heading }}</p>
              <ol class="list-decimal list-outside pl-4 space-y-0.5">
                <li v-for="(step, j) in task.steps" :key="j" class="text-[13px] text-gray-600 dark:text-zinc-400 leading-relaxed">{{ step }}</li>
              </ol>
            </div>

            <div v-if="mod.tips?.length" class="rounded bg-amber-50 dark:bg-amber-500/10 ring-1 ring-amber-200 dark:ring-amber-800/40 px-3 py-2.5 space-y-1.5">
              <div v-for="(tip, i) in mod.tips" :key="i" class="flex gap-2 text-[12.5px] text-amber-800 dark:text-amber-300 leading-relaxed">
                <UIcon name="i-heroicons-light-bulb" class="text-[13px] shrink-0 mt-0.5" />
                <span>{{ tip }}</span>
              </div>
            </div>
          </div>
        </details>
      </div>
    </div>
  </div>
</template>
