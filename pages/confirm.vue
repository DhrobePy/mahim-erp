<script setup lang="ts">
definePageMeta({ layout: 'auth' })

// Supabase auth callback lands here; the module handles the session,
// then we forward to the dashboard.
const user = useSupabaseUser()
watchEffect(() => {
  if (user.value) navigateTo('/')
})
</script>

<template>
  <div class="text-center text-gray-500">
    <UIcon name="i-heroicons-arrow-path" class="animate-spin text-2xl" />
    <p class="mt-2 text-sm">Signing you in…</p>
  </div>
</template>
