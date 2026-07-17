<script setup lang="ts">
const props = defineProps<{
  modelValue: string[]
  docs: ClauseDoc[]
}>()
const emit = defineEmits<{ 'update:modelValue': [string[]] }>()

const { grouped } = useLcClauses()
const open = ref(false)

const relevantGroups = computed(() => {
  const out: Record<string, any[]> = {}
  for (const [cat, clauses] of Object.entries(grouped.value)) {
    const list = clauses.filter((c) => c.appliesTo.some((d: string) => props.docs.includes(d as any)))
    if (list.length) out[cat] = list
  }
  return out
})

const isOn = (key: string) => props.modelValue.includes(key)
const toggle = (key: string) => {
  const next = isOn(key) ? props.modelValue.filter((k) => k !== key) : [...props.modelValue, key]
  emit('update:modelValue', next)
}
</script>

<template>
  <div class="picker">
    <button class="pill" @click="open = !open">Clauses ({{ modelValue.length }}) ▾</button>
    <div v-if="open" class="panel">
      <div class="panel-head">
        <span>Standard LC / trade clauses — printed as numbered declarations</span>
        <button class="x" aria-label="Close" @click="open = false">✕</button>
      </div>
      <div v-for="(clauses, cat) in relevantGroups" :key="cat" class="group">
        <div class="cat">{{ cat }}</div>
        <label v-for="c in clauses" :key="c.key" class="clause-row">
          <input type="checkbox" :checked="isOn(c.key)" @change="toggle(c.key)">
          <span>{{ c.text }}</span>
        </label>
      </div>
    </div>
  </div>
</template>

<style scoped>
.picker { position: relative; }
.pill {
  background: #27272a; color: #e4e4e7; border: 1px solid #3f3f46; border-radius: 4px;
  padding: 6px 12px; font-size: 13px; cursor: pointer; font-family: Inter, sans-serif;
}
.pill:hover { background: #3f3f46; }
.panel {
  position: absolute; top: 36px; right: 0; z-index: 20; width: 460px; max-height: 60vh; overflow-y: auto;
  background: #18181b; border: 1px solid #3f3f46; border-radius: 6px; padding: 12px;
  font-family: Inter, sans-serif; text-align: left; box-shadow: 0 8px 24px rgba(0,0,0,.5);
}
.panel-head {
  display: flex; justify-content: space-between; align-items: center; gap: 8px;
  font-size: 11px; color: #a1a1aa; margin-bottom: 10px; padding-bottom: 8px; border-bottom: 1px solid #3f3f46;
}
.x { background: none; border: 0; color: #a1a1aa; cursor: pointer; font-size: 13px; }
.group { margin-bottom: 10px; }
.cat { font-size: 10px; text-transform: uppercase; letter-spacing: .08em; color: #f59e0b; margin-bottom: 4px; }
.clause-row { display: flex; gap: 8px; align-items: flex-start; padding: 4px 0; cursor: pointer; font-size: 12.5px; color: #d4d4d8; line-height: 1.4; }
.clause-row input { margin-top: 3px; shrink: 0; }
</style>
