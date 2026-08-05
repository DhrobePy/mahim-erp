<script setup lang="ts">
const props = withDefaults(defineProps<{
  label: string
  value: string | number
  sub?: string
  tone?: 'default' | 'amber' | 'green' | 'red'
  to?: string
  delay?: number
  accent?: string
  icon?: string
  points?: number[]
}>(), { accent: '#71717a' })

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

const cardClass = 'stat-card animate-fade-in-up block rounded-md border-t-2 ring-1 bg-white dark:bg-zinc-900/60 px-4 py-3 transition-[color,background-color,border-color,box-shadow,transform] duration-200 ease-out will-change-transform'
const cardStyle = computed(() => ({
  animationDelay: `${props.delay ?? 0}ms`,
  borderTopColor: props.accent,
  '--accent': props.accent
}))
const chipStyle = computed(() => ({ backgroundColor: `${props.accent}1a`, color: props.accent }))
</script>

<template>
  <component :is="to ? 'NuxtLink' : 'div'" :to="to" :style="cardStyle" :class="[cardClass, ringClass, to && 'hover:-translate-y-0.5 hover:shadow-md dark:hover:shadow-black/30 cursor-pointer']">
    <dl>
      <div class="mb-1.5 flex items-center gap-1.5">
        <span v-if="icon" class="flex h-5 w-5 shrink-0 items-center justify-center rounded" :style="chipStyle">
          <UIcon :name="icon" class="text-[12px]" />
        </span>
        <dt class="microlabel text-gray-400 dark:text-zinc-500">{{ label }}</dt>
      </div>
      <dd class="num text-[22px] leading-8 font-semibold" :class="toneClass">{{ value }}</dd>
      <dd v-if="sub" class="text-[11px] text-gray-400 dark:text-zinc-500">{{ sub }}</dd>
      <dd v-if="points && points.length > 1" class="mt-2">
        <Sparkline :points="points" :color="accent" :height="26" />
      </dd>
    </dl>
  </component>
</template>

<style scoped>
.stat-card:hover {
  box-shadow: 0 0 0 1px var(--accent);
}
</style>
