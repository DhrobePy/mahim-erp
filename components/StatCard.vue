<script setup lang="ts">
const props = defineProps<{
  label: string
  value: string | number
  sub?: string
  tone?: 'default' | 'amber' | 'green' | 'red'
  to?: string
  delay?: number
}>()

const toneClass = computed(() => ({
  default: 'text-gray-900 dark:text-zinc-100',
  amber: 'text-amber-600 dark:text-amber-400',
  green: 'text-emerald-600 dark:text-emerald-400',
  red: 'text-red-600 dark:text-red-400'
})[props.tone ?? 'default'])

// Flagged (amber/red) cards carry a matching ring so the one number that
// needs attention doesn't sit at the same visual weight as the other seven.
const ringClass = computed(() => ({
  default: 'ring-gray-200 dark:ring-zinc-800',
  amber: 'ring-amber-300/70 dark:ring-amber-700/50',
  green: 'ring-gray-200 dark:ring-zinc-800',
  red: 'ring-red-300/70 dark:ring-red-800/60'
})[props.tone ?? 'default'])

const cardClass = 'animate-fade-in-up block rounded-md ring-1 bg-white dark:bg-zinc-900/60 px-4 py-3 transition-[color,background-color,border-color,box-shadow,transform] duration-200 ease-out will-change-transform'
const cardStyle = computed(() => ({ animationDelay: `${props.delay ?? 0}ms` }))
</script>

<template>
  <NuxtLink
    v-if="to" :to="to" :style="cardStyle"
    :class="[cardClass, ringClass, 'hover:ring-amber-400/70 dark:hover:ring-amber-500/50 hover:-translate-y-0.5 hover:shadow-md dark:hover:shadow-black/30 cursor-pointer']"
  >
    <dl>
      <dt class="microlabel text-gray-400 dark:text-zinc-500">{{ label }}</dt>
      <dd class="num text-[22px] leading-8 font-semibold" :class="toneClass">{{ value }}</dd>
      <dd v-if="sub" class="text-[11px] text-gray-400 dark:text-zinc-500">{{ sub }}</dd>
    </dl>
  </NuxtLink>
  <dl v-else :class="[cardClass, ringClass]" :style="cardStyle">
    <dt class="microlabel text-gray-400 dark:text-zinc-500">{{ label }}</dt>
    <dd class="num text-[22px] leading-8 font-semibold" :class="toneClass">{{ value }}</dd>
    <dd v-if="sub" class="text-[11px] text-gray-400 dark:text-zinc-500">{{ sub }}</dd>
  </dl>
</template>
