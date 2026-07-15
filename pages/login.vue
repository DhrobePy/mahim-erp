<script setup lang="ts">
definePageMeta({ layout: 'auth' })

const client = useSupabaseClient()
const user = useSupabaseUser()
const toast = useToast()

const mode = ref<'signin' | 'signup'>('signin')
const email = ref('')
const password = ref('')
const fullName = ref('')
const loading = ref(false)

// Already logged in? Skip the form.
watchEffect(() => {
  if (user.value) navigateTo('/')
})

const submit = async () => {
  loading.value = true
  try {
    if (mode.value === 'signin') {
      const { error } = await client.auth.signInWithPassword({
        email: email.value,
        password: password.value
      })
      if (error) throw error
      await navigateTo('/')
    } else {
      const { error } = await client.auth.signUp({
        email: email.value,
        password: password.value,
        options: { data: { full_name: fullName.value } }
      })
      if (error) throw error
      toast.add({ title: 'Account created', description: 'You can now sign in. Ask an admin to grant your role.' })
      mode.value = 'signin'
    }
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
          <p class="text-xs text-gray-500">{{ mode === 'signin' ? 'Sign in to continue' : 'Create your account' }}</p>
        </div>
      </div>
    </template>

    <form class="space-y-4" @submit.prevent="submit">
      <UFormGroup v-if="mode === 'signup'" label="Full name">
        <UInput v-model="fullName" placeholder="Your name" />
      </UFormGroup>
      <UFormGroup label="Email">
        <UInput v-model="email" type="email" placeholder="you@company.com" required />
      </UFormGroup>
      <UFormGroup label="Password">
        <UInput v-model="password" type="password" placeholder="••••••••" required />
      </UFormGroup>

      <UButton type="submit" block :loading="loading">
        {{ mode === 'signin' ? 'Sign in' : 'Sign up' }}
      </UButton>
    </form>

    <template #footer>
      <button
        class="text-sm text-primary-600 hover:underline"
        @click="mode = mode === 'signin' ? 'signup' : 'signin'"
      >
        {{ mode === 'signin' ? "Don't have an account? Sign up" : 'Already have an account? Sign in' }}
      </button>
    </template>
  </UCard>
</template>
