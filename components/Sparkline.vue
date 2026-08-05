<script setup lang="ts">
import { useId } from 'vue'

const props = withDefaults(defineProps<{
  points: number[]
  color: string
  height?: number
}>(), { height: 28 })

const width = 100
const gradientId = `spark-${useId()}`

const path = computed(() => {
  const pts = props.points
  if (pts.length < 2) return { line: '', area: '' }
  const min = Math.min(...pts)
  const max = Math.max(...pts)
  const range = max - min || 1
  const stepX = width / (pts.length - 1)
  const coords = pts.map((v, i) => {
    const x = i * stepX
    const y = props.height - ((v - min) / range) * (props.height - 4) - 2
    return [x, y] as const
  })
  const line = coords.map(([x, y], i) => `${i === 0 ? 'M' : 'L'}${x.toFixed(2)},${y.toFixed(2)}`).join(' ')
  const [lastX] = coords[coords.length - 1]
  const area = `${line} L${lastX.toFixed(2)},${props.height} L0,${props.height} Z`
  return { line, area }
})
</script>

<template>
  <svg
    v-if="points.length > 1"
    :viewBox="`0 0 ${width} ${height}`"
    preserveAspectRatio="none"
    class="block w-full"
    :style="{ height: height + 'px' }"
    aria-hidden="true"
  >
    <defs>
      <linearGradient :id="gradientId" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" :stop-color="color" stop-opacity="0.35" />
        <stop offset="100%" :stop-color="color" stop-opacity="0" />
      </linearGradient>
    </defs>
    <path :d="path.area" :fill="`url(#${gradientId})`" stroke="none" />
    <path
      :d="path.line" fill="none" :stroke="color" stroke-width="1.5"
      stroke-linecap="round" stroke-linejoin="round" class="spark-line"
    />
  </svg>
</template>

<style scoped>
.spark-line {
  stroke-dasharray: 400;
  stroke-dashoffset: 400;
  animation: spark-draw 900ms cubic-bezier(0.16, 1, 0.3, 1) 250ms both;
}
@keyframes spark-draw {
  to { stroke-dashoffset: 0; }
}
</style>
