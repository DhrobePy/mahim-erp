<script setup lang="ts">
defineProps<{
  kicker?: string
  title: string
  subtitle?: string
}>()
</script>

<template>
  <div class="flex items-end justify-between mb-5 gap-4">
    <div class="min-w-0">
      <p v-if="kicker" class="microlabel text-amber-600 dark:text-amber-500 mb-1">{{ kicker }}</p>
      <h1 class="text-lg font-semibold tracking-tight text-gray-900 dark:text-zinc-100">{{ title }}</h1>
      <p v-if="subtitle" class="text-[13px] text-gray-500 dark:text-zinc-500 mt-0.5 truncate">{{ subtitle }}</p>
    </div>
    <div class="flex gap-2 shrink-0">
      <slot />
    </div>
  </div>
</template>
