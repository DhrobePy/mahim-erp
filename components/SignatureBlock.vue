<script setup lang="ts">
// Company's own "authorized signatory" slot on a print letterhead — a
// blank line for physical signing, or (when the company has uploaded one
// and the print toolbar's toggle is on) that signature image blended in
// just above the line. Other people's signature lines on the same
// document (buyer, employee, reporting officer, chairperson, ...) stay
// plain <div class="sig">/.sig-line blocks in each page, unchanged — this
// component is only for the company's own signatory.
const props = withDefaults(defineProps<{
  company: any
  showSignature: boolean
  label: string
  forLabel?: string
  width?: number
}>(), { width: 200 })

const { signatureUrl } = useCompanySignature()
const url = computed(() => (props.showSignature ? signatureUrl(props.company) : null))
</script>

<template>
  <div class="sig">
    <div class="sig-line-wrap" :style="{ width: width + 'px' }">
      <img v-if="url" :src="url" class="sig-img" alt="">
      <div class="sig-line" />
    </div>
    <div v-if="forLabel"><b>{{ forLabel }}</b></div>
    <div class="small">{{ label }}</div>
  </div>
</template>

<style scoped>
.sig { text-align: center; }
.sig-line-wrap { position: relative; height: 52px; margin: 0 auto; }
.sig-img {
  position: absolute;
  bottom: 4px;
  left: 50%;
  transform: translateX(-50%);
  max-height: 42px;
  max-width: 92%;
  object-fit: contain;
  /* Sits on a white sheet, so multiply blends the signature's own
     background out instead of showing a white box over the ruled line. */
  mix-blend-mode: multiply;
}
.sig-line { position: absolute; bottom: 0; left: 0; right: 0; border-top: 1px solid #111; }
</style>
