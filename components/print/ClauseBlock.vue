<script setup lang="ts">
const props = defineProps<{
  selectedKeys: string[]
  doc: 'boe' | 'ci' | 'pl' | 'challan'
}>()
const { forDoc } = useLcClauses()
const items = computed(() =>
  forDoc(props.doc).filter((c) => props.selectedKeys.includes(c.key)))
</script>

<template>
  <div v-if="items.length" class="clause-block">
    <div class="hdr">Declarations</div>
    <ol>
      <li v-for="c in items" :key="c.key">{{ c.text }}</li>
    </ol>
  </div>
</template>

<style scoped>
.clause-block { margin: 14px 0; font-size: 11px; color: #222; }
.hdr { font-size: 10px; text-transform: uppercase; letter-spacing: .08em; color: #555; margin-bottom: 3px; }
ol { margin: 0; padding-left: 16px; }
li { margin-bottom: 2px; }
</style>
