<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite, activeCompanyId } = useProfile()
const { extractLc } = usePdfExtract()

const lcs = ref<any[]>([])
const parties = ref<any[]>([])
const banks = ref<any[]>([])
const loading = ref(true)

const columns = [
  { key: 'lc_no', label: 'LC no.' },
  { key: 'buyer', label: 'Buyer' },
  { key: 'bank', label: 'Issuing bank' },
  { key: 'terms', label: 'Active terms' },
  { key: 'lc_type', label: 'Type' },
  { key: 'status', label: 'Status' },
  { key: 'actions', label: '' }
]

const load = async () => {
  loading.value = true
  const [l, p, b] = await Promise.all([
    client.from('lcs')
      .select('*, buyer:buyer_party_id(name), bank:bank_party_id(name), lc_amendments(version, amount, quantity, tolerance_pct, expiry_date, bank_fee, note)')
      .order('created_at', { ascending: false }),
    client.from('parties').select('id, name').eq('is_customer', true).order('name'),
    client.from('parties').select('id, name').eq('is_bank', true).order('name')
  ])
  lcs.value = (l.data ?? []).map((row: any) => ({
    ...row,
    amendments: [...(row.lc_amendments ?? [])].sort((a: any, b: any) => b.version - a.version)
  }))
  parties.value = p.data ?? []
  banks.value = b.data ?? []
  loading.value = false
}
onMounted(load)

const active = (row: any) => row.amendments?.[0]

// --- New LC (creates v1 terms) ---
const open = ref(false)
const saving = ref(false)
const form = reactive({
  lc_no: '', buyer_party_id: null as string | null, bank_party_id: null as string | null,
  lc_type: 'usance', usance_days: 90, opened_at: new Date().toISOString().slice(0, 10),
  amount: 0, quantity: null as number | null, tolerance_pct: 5, expiry_date: null as string | null
})
const openNew = () => {
  Object.assign(form, {
    lc_no: '', buyer_party_id: null, bank_party_id: null, lc_type: 'usance',
    usance_days: 90, opened_at: new Date().toISOString().slice(0, 10),
    amount: 0, quantity: null, tolerance_pct: 5, expiry_date: null
  })
  open.value = true
}
// "Register from PDF": extract fields client-side, prefill the form for
// review, and attach the source document to the LC on save.
const pdfFile = ref<File | null>(null)
const extracting = ref(false)
const fromPdf = async (ev: Event) => {
  const file = (ev.target as HTMLInputElement).files?.[0]
  if (!file) return
  extracting.value = true
  try {
    const f = await extractLc(file)
    openNew()
    pdfFile.value = file
    if (f.lc_no) form.lc_no = f.lc_no
    if (f.amount) form.amount = f.amount
    if (f.expiry_date) form.expiry_date = f.expiry_date
    if (f.usance_days) { form.lc_type = 'usance'; form.usance_days = f.usance_days }
    if (f.tolerance_pct) form.tolerance_pct = f.tolerance_pct
    const found = Object.keys(f).filter((k) => k !== 'raw_text').length
    toast.add({
      title: found ? `Extracted ${found} field(s) — review before saving` : 'No fields recognised',
      description: f.applicant ? `Applicant on document: ${f.applicant}` : undefined,
      color: found ? 'green' : 'amber'
    })
  } catch (e: any) {
    toast.add({ title: 'Extraction failed', description: e.message, color: 'red' })
  } finally {
    extracting.value = false
    ;(ev.target as HTMLInputElement).value = ''
  }
}

const save = async () => {
  if (!form.lc_no || !form.buyer_party_id) {
    toast.add({ title: 'LC number and buyer are required', color: 'red' }); return
  }
  saving.value = true
  try {
    const { data: lc, error } = await client.from('lcs').insert({
      lc_no: form.lc_no, buyer_party_id: form.buyer_party_id, bank_party_id: form.bank_party_id,
      lc_type: form.lc_type, usance_days: form.usance_days, opened_at: form.opened_at
    } as any).select('id').single()
    if (error) throw error
    const res = await client.from('lc_amendments').insert({
      lc_id: (lc as any).id, version: 1, amount: form.amount, quantity: form.quantity,
      tolerance_pct: form.tolerance_pct, expiry_date: form.expiry_date
    } as any)
    if (res.error) throw res.error

    if (pdfFile.value) {
      const path = `${activeCompanyId.value}/${(lc as any).id}/${Date.now()}-${pdfFile.value.name}`
      const up = await client.storage.from('lc-docs').upload(path, pdfFile.value)
      if (!up.error) {
        await client.from('lc_documents').insert({
          lc_id: (lc as any).id, doc_type: 'lc',
          original_name: pdfFile.value.name, file_path: path,
          extracted: { source: 'register-from-pdf' }
        } as any)
      }
      pdfFile.value = null
    }

    toast.add({ title: 'LC registered (v1 terms)' })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: 'LC failed', description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

// --- Amendment (next version) ---
const amendOpen = ref(false)
const amendTarget = ref<any>(null)
const amendForm = reactive({ amount: 0, quantity: null as number | null, tolerance_pct: 5, expiry_date: null as string | null, bank_fee: 0, note: '' })
const openAmend = (row: any) => {
  amendTarget.value = row
  const a = active(row)
  Object.assign(amendForm, {
    amount: a?.amount ?? 0, quantity: a?.quantity, tolerance_pct: a?.tolerance_pct ?? 5,
    expiry_date: a?.expiry_date, bank_fee: 0, note: ''
  })
  amendOpen.value = true
}
const saveAmend = async () => {
  const next = (active(amendTarget.value)?.version ?? 0) + 1
  const { error } = await client.from('lc_amendments').insert({
    lc_id: amendTarget.value.id, version: next, ...amendForm
  } as any)
  if (error) toast.add({ title: 'Amendment failed', description: error.message, color: 'red' })
  else {
    toast.add({ title: `Amendment v${next} recorded${amendForm.bank_fee > 0 ? ' — MT707 fee posted' : ''}` })
    amendOpen.value = false
    await load()
  }
}
</script>

<template>
  <div>
    <PageHeader kicker="Sales &amp; Local LC" title="Local LCs" subtitle="Master-child versioning — documents validate against the latest amendment">
      <label v-if="canWrite" class="cursor-pointer">
        <span class="inline-flex items-center gap-1.5 text-sm px-2.5 py-1.5 rounded bg-gray-100 dark:bg-zinc-800 text-gray-700 dark:text-zinc-300 hover:bg-gray-200 dark:hover:bg-zinc-700 font-medium">
          <UIcon name="i-heroicons-document-arrow-up" class="text-base" />
          {{ extracting ? 'Extracting…' : 'Register from PDF' }}
        </span>
        <input type="file" accept="application/pdf" class="hidden" :disabled="extracting" @change="fromPdf">
      </label>
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">Register LC</UButton>
    </PageHeader>

    <UCard>
      <UTable :rows="lcs" :columns="columns" :loading="loading">
        <template #buyer-data="{ row }">{{ row.buyer?.name }}</template>
        <template #bank-data="{ row }">{{ row.bank?.name || '—' }}</template>
        <template #lc_no-data="{ row }">
          <NuxtLink :to="`/lcs/${row.id}`" class="num font-medium text-amber-600 dark:text-amber-400 hover:underline">
            {{ row.lc_no }}
          </NuxtLink>
        </template>
        <template #terms-data="{ row }">
          <div v-if="active(row)" class="text-xs num">
            <UBadge size="xs" variant="subtle" color="purple">v{{ active(row).version }}</UBadge>
            <span class="text-amber-600 dark:text-amber-400">৳{{ active(row).amount }}</span> · {{ active(row).quantity ?? '—' }} pcs ±{{ active(row).tolerance_pct }}%
            <span v-if="active(row).expiry_date"> · exp {{ active(row).expiry_date }}</span>
          </div>
        </template>
        <template #lc_type-data="{ row }">
          {{ row.lc_type }}<span v-if="row.lc_type === 'usance'"> {{ row.usance_days }}d</span>
        </template>
        <template #status-data="{ row }">
          <UBadge size="xs" variant="subtle" :color="row.status === 'active' ? 'green' : 'gray'">{{ row.status }}</UBadge>
        </template>
        <template #actions-data="{ row }">
          <UButton v-if="canWrite && row.status === 'active'" size="xs" variant="soft" @click="openAmend(row)">Amend</UButton>
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">No LCs registered.</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">Register LC (v1 terms)</p></template>
        <div class="grid grid-cols-2 gap-4">
          <UFormGroup label="LC number" required><UInput v-model="form.lc_no" /></UFormGroup>
          <UFormGroup label="Buyer" required>
            <USelect v-model="form.buyer_party_id" :options="parties" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup label="Issuing bank">
            <USelect v-model="form.bank_party_id" :options="banks" option-attribute="name" value-attribute="id" placeholder="—" />
          </UFormGroup>
          <UFormGroup label="Type">
            <USelect v-model="form.lc_type" :options="[{ value: 'sight', label: 'Sight' }, { value: 'usance', label: 'Usance' }]" option-attribute="label" value-attribute="value" />
          </UFormGroup>
          <UFormGroup v-if="form.lc_type === 'usance'" label="Usance days">
            <UInput v-model.number="form.usance_days" type="number" />
          </UFormGroup>
          <UFormGroup label="Opened"><UInput v-model="form.opened_at" type="date" /></UFormGroup>
          <UFormGroup label="Amount (৳)"><UInput v-model.number="form.amount" type="number" /></UFormGroup>
          <UFormGroup label="Quantity"><UInput v-model.number="form.quantity" type="number" /></UFormGroup>
          <UFormGroup label="Tolerance %"><UInput v-model.number="form.tolerance_pct" type="number" /></UFormGroup>
          <UFormGroup label="Expiry"><UInput v-model="form.expiry_date" type="date" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">Cancel</UButton>
            <UButton :loading="saving" @click="save">Register</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="amendOpen">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header>
          <p class="font-medium">Amend {{ amendTarget?.lc_no }} → v{{ (active(amendTarget)?.version ?? 0) + 1 }}</p>
        </template>
        <div class="grid grid-cols-2 gap-4">
          <UFormGroup label="Amount (৳)"><UInput v-model.number="amendForm.amount" type="number" /></UFormGroup>
          <UFormGroup label="Quantity"><UInput v-model.number="amendForm.quantity" type="number" /></UFormGroup>
          <UFormGroup label="Tolerance %"><UInput v-model.number="amendForm.tolerance_pct" type="number" /></UFormGroup>
          <UFormGroup label="Expiry"><UInput v-model="amendForm.expiry_date" type="date" /></UFormGroup>
          <UFormGroup label="MT707 fee on us (৳)" hint="posts to 5400 if > 0">
            <UInput v-model.number="amendForm.bank_fee" type="number" />
          </UFormGroup>
          <UFormGroup label="Note"><UInput v-model="amendForm.note" /></UFormGroup>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="amendOpen = false">Cancel</UButton>
            <UButton @click="saveAmend">Record amendment</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
