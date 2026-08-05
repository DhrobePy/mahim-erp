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
}>(), { accent: '#f59e0b' })

const toneClass = computed(() => ({
  default: 'text-gray-900 dark:text-zinc-100',
  amber: 'text-amber-600 dark:text-amber-400',
  green: 'text-emerald-600 dark:text-emerald-400',
  red: 'text-red-600 dark:text-red-400'
})[props.tone ?? 'default'])

// Flagged (amber/red) cards carry a matching edge so the one number that
// needs attention doesn't sit at the same visual weight as the other seven;
// unflagged cards get a plain glass edge and lean on their own accent glow
// instead (see .stat-card box-shadow below).
const edgeColor = computed(() => ({
  default: null,
  amber: '#f59e0b',
  green: null,
  red: '#ef4444'
})[props.tone ?? 'default'])

const cardClass = 'stat-card animate-fade-in-up block rounded-xl border-t-2 bg-white/80 dark:bg-zinc-900/40 backdrop-blur-xl px-4 py-3 transition-[color,background-color,box-shadow,transform] duration-300 ease-out will-change-transform'
const cardStyle = computed(() => ({
  animationDelay: `${props.delay ?? 0}ms`,
  borderTopColor: props.accent,
  '--accent': props.accent,
  '--edge': edgeColor.value ?? 'rgba(255,255,255,0.1)'
}))
const chipStyle = computed(() => ({ backgroundColor: `${props.accent}1a`, color: props.accent, boxShadow: `0 0 12px -2px ${props.accent}80` }))
</script>

<template>
  <component :is="to ? 'NuxtLink' : 'div'" :to="to" :style="cardStyle" :class="[cardClass, to && 'hover:-translate-y-1 cursor-pointer']">
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
.stat-card {
  box-shadow:
    inset 0 0 0 1px var(--edge),
    0 12px 28px -18px color-mix(in srgb, var(--accent) 55%, transparent);
}
.stat-card:hover {
  box-shadow:
    inset 0 0 0 1px color-mix(in srgb, var(--accent) 65%, var(--edge)),
    0 18px 44px -14px color-mix(in srgb, var(--accent) 70%, transparent);
}
</style>
