<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()

const boms = ref<any[]>([])
const items = ref<any[]>([])
const loading = ref(true)

const finishedItems = computed(() =>
  items.value.filter((i) => ['finished_good', 'wip'].includes(i.item_type))
)

const load = async () => {
  loading.value = true
  const [{ data: b }, { data: it }] = await Promise.all([
    client.from('boms')
      .select('*, items:finished_item_id(name, sku), bom_lines(id, qty_per, wastage_pct, component:component_item_id(name, sku))')
      .order('created_at', { ascending: false }),
    client.from('items').select('id, sku, name, item_type').eq('is_active', true).order('name')
  ])
  boms.value = b ?? []
  items.value = it ?? []
  loading.value = false
}
onMounted(load)

// --- Create BOM with lines ---
const open = ref(false)
const saving = ref(false)
const form = reactive({
  finished_item_id: null as string | null,
  name: '',
  output_qty: 1,
  lines: [] as { component_item_id: string | null; qty_per: number; wastage_pct: number }[]
})

const openNew = () => {
  form.finished_item_id = null
  form.name = ''
  form.output_qty = 1
  form.lines = [{ component_item_id: null, qty_per: 1, wastage_pct: 0 }]
  open.value = true
}
const addLine = () => form.lines.push({ component_item_id: null, qty_per: 1, wastage_pct: 0 })
const removeLine = (i: number) => form.lines.splice(i, 1)

const save = async () => {
  if (!form.finished_item_id || !form.name) {
    toast.add({ title: 'Finished item and name are required', color: 'red' })
    return
  }
  const validLines = form.lines.filter((l) => l.component_item_id)
  if (!validLines.length) {
    toast.add({ title: 'Add at least one component', color: 'red' })
    return
  }
  saving.value = true
  try {
    const { data: bom, error } = await client.from('boms').insert({
      finished_item_id: form.finished_item_id,
      name: form.name,
      output_qty: Number(form.output_qty)
    }).select('id').single()
    if (error) throw error

    const { error: lErr } = await client.from('bom_lines').insert(
      validLines.map((l) => ({
        bom_id: bom.id,
        component_item_id: l.component_item_id,
        qty_per: Number(l.qty_per),
        wastage_pct: Number(l.wastage_pct)
      }))
    )
    if (lErr) throw lErr

    toast.add({ title: 'BOM created' })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: 'Save failed', description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div>
    <PageHeader kicker="Operations" title="Bills of material" subtitle="Recipes that drive material consumption during production">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">New BOM</UButton>
    </PageHeader>

    <div v-if="loading" class="text-sm text-gray-400">Loading…</div>
    <div v-else-if="!boms.length" class="text-sm text-gray-400">No BOMs yet.</div>

    <div class="grid gap-4 md:grid-cols-2">
      <UCard v-for="b in boms" :key="b.id">
        <template #header>
          <div class="flex items-center justify-between">
            <div>
              <p class="font-medium">{{ b.name }}</p>
              <p class="text-xs text-gray-500">
                {{ b.items?.name }} · yields {{ b.output_qty }}
              </p>
            </div>
            <UBadge size="xs" :color="b.is_active ? 'green' : 'gray'" variant="subtle">
              {{ b.is_active ? 'active' : 'inactive' }}
            </UBadge>
          </div>
        </template>
        <ul class="text-sm divide-y divide-gray-100 dark:divide-zinc-800/60">
          <li v-for="l in b.bom_lines" :key="l.id" class="py-1.5 flex justify-between">
            <span>{{ l.component?.name }}</span>
            <span class="text-gray-500">
              {{ l.qty_per }}<span v-if="l.wastage_pct"> · +{{ l.wastage_pct }}% waste</span>
            </span>
          </li>
        </ul>
      </UCard>
    </div>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">New BOM</p></template>
        <div class="space-y-4">
          <div class="grid grid-cols-2 gap-4">
            <UFormGroup label="Finished item" required>
              <USelect
                v-model="form.finished_item_id" :options="finishedItems"
                option-attribute="name" value-attribute="id" placeholder="Select"
              />
            </UFormGroup>
            <UFormGroup label="Output qty per run" required>
              <UInput v-model.number="form.output_qty" type="number" />
            </UFormGroup>
            <UFormGroup label="BOM name" required class="col-span-2">
              <UInput v-model="form.name" placeholder="e.g. Carton A — standard recipe" />
            </UFormGroup>
          </div>

          <div>
            <div class="flex items-center justify-between mb-2">
              <p class="text-sm font-medium">Components</p>
              <UButton size="xs" variant="soft" icon="i-heroicons-plus" @click="addLine">Add</UButton>
            </div>
            <div v-for="(l, i) in form.lines" :key="i" class="grid grid-cols-12 gap-2 mb-2 items-center">
              <USelect
                v-model="l.component_item_id" :options="items"
                option-attribute="name" value-attribute="id" placeholder="Component"
                class="col-span-6"
              />
              <UInput v-model.number="l.qty_per" type="number" placeholder="Qty" class="col-span-3" />
              <UInput v-model.number="l.wastage_pct" type="number" placeholder="% waste" class="col-span-2" />
              <UButton
                icon="i-heroicons-trash" color="red" variant="ghost" size="xs" class="col-span-1"
                @click="removeLine(i)"
              />
            </div>
          </div>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">Cancel</UButton>
            <UButton :loading="saving" @click="save">Save BOM</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
