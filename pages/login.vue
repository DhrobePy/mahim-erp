<script setup lang="ts">
definePageMeta({ layout: 'auth' })

const client = useSupabaseClient()
const user = useSupabaseUser()
const toast = useToast()

const email = ref('')
const password = ref('')
const loading = ref(false)

// Already logged in? Skip the form.
watchEffect(() => {
  if (user.value) navigateTo('/')
})

const submit = async () => {
  loading.value = true
  try {
    const { error } = await client.auth.signInWithPassword({
      email: email.value,
      password: password.value
    })
    if (error) throw error
    await navigateTo('/')
  } catch (e: any) {
    toast.add({ title: 'Authentication failed', description: e.message, color: 'red' })
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <UCard class="w-full max-w-sm">
    <template #header>
      <div class="flex items-center gap-2">
        <UIcon name="i-heroicons-cube-transparent" class="text-primary-500 text-2xl" />
        <div>
          <p class="font-semibold">Mahim Packaging ERP</p>
          <p class="text-xs text-gray-500">Sign in to continue</p>
        </div>
      </div>
    </template>

    <form class="space-y-4" @submit.prevent="submit">
      <UFormGroup label="Email">
        <UInput v-model="email" type="email" placeholder="you@company.com" required />
      </UFormGroup>
      <UFormGroup label="Password">
        <UInput v-model="password" type="password" placeholder="••••••••" required />
      </UFormGroup>

      <UButton type="submit" block :loading="loading">Sign in</UButton>
    </form>

    <template #footer>
      <p class="text-xs text-gray-500">
        No account yet? Ask your admin to create one for you under Access &amp; roles.
      </p>
    </template>
  </UCard>
</template>
