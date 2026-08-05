<script setup lang="ts">
definePageMeta({ layout: 'auth' })

const client = useSupabaseClient()
const user = useSupabaseUser()
const toast = useToast()
const { t } = useI18n()

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
    toast.add({ title: t('system.login.auth_failed'), description: e.message, color: 'red' })
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
          <p class="text-xs text-gray-500">{{ t('system.login.tagline') }}</p>
        </div>
      </div>
    </template>

    <form class="space-y-4" @submit.prevent="submit">
      <UFormGroup :label="t('system.login.email')">
        <UInput v-model="email" type="email" :placeholder="t('system.login.email_placeholder')" required />
      </UFormGroup>
      <UFormGroup :label="t('system.login.password')">
        <UInput v-model="password" type="password" :placeholder="t('system.login.password_placeholder')" required />
      </UFormGroup>

      <UButton type="submit" block :loading="loading">{{ t('system.login.sign_in') }}</UButton>
    </form>

    <template #footer>
      <p class="text-xs text-gray-500">
        {{ t('system.login.no_account') }}
      </p>
    </template>
  </UCard>
</template>
