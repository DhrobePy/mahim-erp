<script setup lang="ts">
const props = defineProps<{
  label: string
  value: string | number
  sub?: string
  tone?: 'default' | 'amber' | 'green' | 'red'
}>()

const toneClass = computed(() => ({
  default: 'text-gray-900 dark:text-zinc-100',
  amber: 'text-amber-600 dark:text-amber-400',
  green: 'text-emerald-600 dark:text-emerald-400',
  red: 'text-red-600 dark:text-red-400'
})[props.tone ?? 'default'])
</script>

<template>
  <div class="rounded-md ring-1 ring-gray-200 dark:ring-zinc-800 bg-white dark:bg-zinc-900/60 px-4 py-3">
    <p class="microlabel text-gray-400 dark:text-zinc-500">{{ label }}</p>
    <p class="num text-[22px] leading-8 font-semibold" :class="toneClass">{{ value }}</p>
    <p v-if="sub" class="text-[11px] text-gray-400 dark:text-zinc-500">{{ sub }}</p>
  </div>
</template>
