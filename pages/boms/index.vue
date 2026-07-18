<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite, activeCompanyId } = useProfile()
const { toMm, plyLayout, recipeSummary } = useCartonMath()

const boms = ref<any[]>([])
const items = ref<any[]>([])
const templates = ref<any[]>([])
const loading = ref(true)

const finishedItems = computed(() =>
  items.value.filter((i) => ['finished_good', 'wip'].includes(i.item_type))
)
const rawItems = computed(() => items.value.filter((i) => i.item_type === 'raw_material'))
const templateOptions = computed(() => templates.value.map((t) => ({ value: t.id, label: `${t.name}` })))

const load = async () => {
  loading.value = true
  const [{ data: b }, { data: it }, { data: tpl }] = await Promise.all([
    client.from('boms')
      .select('*, items:finished_item_id(name, sku), bom_lines(id, qty_per, wastage_pct, note, component:component_item_id(name, sku))')
      .order('created_at', { ascending: false }),
    client.from('items').select('id, sku, name, item_type').eq('is_active', true).order('name'),
    client.from('carton_recipe_templates').select('*').order('ply_count').order('name')
  ])
  boms.value = b ?? []
  items.value = it ?? []
  templates.value = tpl ?? []
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

// --- Carton recipe wizard ---
const recipeOpen = ref(false)
const recipeSaving = ref(false)
const unitOptions = [{ value: 'cm', label: 'cm' }, { value: 'mm', label: 'mm' }, { value: 'inch', label: 'inch' }]
const fluteOptions = [
  { value: 'A', label: 'A — cushioning' }, { value: 'B', label: 'B — printable/die-cut' },
  { value: 'C', label: 'C — general purpose' }, { value: 'E', label: 'E — fine print' },
  { value: 'F', label: 'F — micro/premium' }
]
const plyOptions = [3, 5, 7]

const recipe = reactive({
  item_id: null as string | null,
  newItem: false,
  newSku: '', newName: '',
  unit: 'cm',
  length: 0, width: 0, height: 0,
  ply: 3,
  allowance_mm: 40,
  wastage_pct: 5,
  layers: [] as Array<{ layer_no: number; role: 'liner' | 'medium'; flute_code: string | null; gsm: number; raw_item_id: string | null }>
})
const selectedTemplateId = ref<string | null>(null)

const roleLabel = (l: typeof recipe.layers[number], idx: number, total: number) => {
  if (l.role === 'medium') {
    const n = recipe.layers.slice(0, idx + 1).filter((x) => x.role === 'medium').length
    return `Medium ${n} (flute)`
  }
  if (idx === 0) return 'Outer liner'
  if (idx === total - 1) return 'Inner liner'
  return 'Middle liner'
}

const rebuildLayers = () => {
  const roles = plyLayout(recipe.ply)
  const prev = recipe.layers
  recipe.layers = roles.map((role, i) => {
    const existing = prev[i]?.role === role ? prev[i] : null
    return existing ?? {
      layer_no: i + 1, role,
      flute_code: role === 'medium' ? 'C' : null,
      gsm: role === 'liner' ? 150 : 120,
      raw_item_id: null
    }
  })
}
watch(() => recipe.ply, rebuildLayers)

const applyTemplate = (id: string | null) => {
  const tpl = templates.value.find((t) => t.id === id)
  if (!tpl) return
  recipe.ply = tpl.ply_count
  recipe.layers = tpl.layers.map((l: any) => ({ ...l, raw_item_id: null }))
}

const openRecipeNew = () => {
  Object.assign(recipe, {
    item_id: null, newItem: false, newSku: '', newName: '',
    unit: 'cm', length: 0, width: 0, height: 0, ply: 3, allowance_mm: 40, wastage_pct: 5
  })
  selectedTemplateId.value = null
  rebuildLayers()
  recipeOpen.value = true
}

const openRecipeEdit = async (bom: any) => {
  const { data: spec } = await client.from('carton_specs')
    .select('*, carton_spec_layers(layer_no, role, flute_code, gsm, raw_item_id)')
    .eq('item_id', bom.finished_item_id).maybeSingle()
  if (!spec) { toast.add({ title: 'No recipe found for this item', color: 'amber' }); return }
  selectedTemplateId.value = null
  Object.assign(recipe, {
    item_id: bom.finished_item_id, newItem: false, newSku: '', newName: '',
    unit: 'mm', length: spec.length_mm, width: spec.width_mm, height: spec.height_mm,
    ply: spec.ply_count, allowance_mm: spec.manufacturing_allowance_mm, wastage_pct: spec.wastage_pct,
    layers: [...spec.carton_spec_layers].sort((a: any, b: any) => a.layer_no - b.layer_no)
  })
  recipeOpen.value = true
}

const recipeMm = computed(() => ({
  length: toMm(recipe.length, recipe.unit),
  width: toMm(recipe.width, recipe.unit),
  height: toMm(recipe.height, recipe.unit)
}))
const preview = computed(() =>
  recipeSummary(recipeMm.value.length, recipeMm.value.width, recipeMm.value.height, recipe.allowance_mm, recipe.layers as any))

const rawItemName = (id: string | null) => rawItems.value.find((i) => i.id === id)?.sku ?? '—'

const saveRecipe = async () => {
  if (recipe.newItem) {
    if (!recipe.newSku || !recipe.newName) {
      toast.add({ title: 'SKU and name are required for the new item', color: 'red' }); return
    }
  } else if (!recipe.item_id) {
    toast.add({ title: 'Pick a finished item', color: 'red' }); return
  }
  if (!recipeMm.value.length || !recipeMm.value.width || !recipeMm.value.height) {
    toast.add({ title: 'Enter length, width and height', color: 'red' }); return
  }
  if (recipe.layers.some((l) => !l.raw_item_id || !l.gsm)) {
    toast.add({ title: 'Every layer needs a GSM and a raw material', color: 'red' }); return
  }
  recipeSaving.value = true
  try {
    let itemId = recipe.item_id
    if (recipe.newItem) {
      const { data: newIt, error } = await client.from('items').insert({
        sku: recipe.newSku, name: recipe.newName, item_type: 'finished_good',
        size_spec: `${recipe.length}×${recipe.width}×${recipe.height} ${recipe.unit}`
      } as any).select('id').single()
      if (error) throw error
      itemId = (newIt as any).id
    }
    const { error } = await client.rpc('save_carton_recipe', {
      p_item_id: itemId,
      p_ply_count: recipe.ply,
      p_length_mm: recipeMm.value.length,
      p_width_mm: recipeMm.value.width,
      p_height_mm: recipeMm.value.height,
      p_allowance_mm: recipe.allowance_mm,
      p_wastage_pct: recipe.wastage_pct,
      p_layers: recipe.layers
    } as any)
    if (error) throw error
    toast.add({ title: 'Recipe saved — BOM generated', description: `${preview.value.totalKg.toFixed(4)} kg / box` })
    recipeOpen.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: 'Recipe failed', description: e.message, color: 'red' })
  } finally {
    recipeSaving.value = false
  }
}

// --- Template manager (create/edit/delete reusable ply recipes) ---
const tplMgrOpen = ref(false)
const tplEditorOpen = ref(false)
const tplSaving = ref(false)
const tplForm = reactive({
  id: null as string | null,
  name: '',
  ply: 3,
  layers: [] as Array<{ layer_no: number; role: 'liner' | 'medium'; flute_code: string | null; gsm: number }>
})

const tplRoleLabel = (l: typeof tplForm.layers[number], idx: number, total: number) => {
  if (l.role === 'medium') {
    const n = tplForm.layers.slice(0, idx + 1).filter((x) => x.role === 'medium').length
    return `Medium ${n} (flute)`
  }
  if (idx === 0) return 'Outer liner'
  if (idx === total - 1) return 'Inner liner'
  return 'Middle liner'
}

const tplRebuildLayers = () => {
  const roles = plyLayout(tplForm.ply)
  const prev = tplForm.layers
  tplForm.layers = roles.map((role, i) => {
    const existing = prev[i]?.role === role ? prev[i] : null
    return existing ?? { layer_no: i + 1, role, flute_code: role === 'medium' ? 'C' : null, gsm: role === 'liner' ? 150 : 120 }
  })
}
watch(() => tplForm.ply, tplRebuildLayers)

const openTplNew = () => {
  Object.assign(tplForm, { id: null, name: '', ply: 3 })
  tplRebuildLayers()
  tplEditorOpen.value = true
}
const openTplEdit = (t: any) => {
  Object.assign(tplForm, { id: t.id, name: t.name, ply: t.ply_count, layers: [...t.layers] })
  tplEditorOpen.value = true
}
const saveTemplate = async () => {
  if (!tplForm.name) { toast.add({ title: 'Template name is required', color: 'red' }); return }
  if (tplForm.layers.some((l) => !l.gsm)) { toast.add({ title: 'Every layer needs a GSM', color: 'red' }); return }
  tplSaving.value = true
  try {
    const payload = { name: tplForm.name, ply_count: tplForm.ply, layers: tplForm.layers }
    const { error } = tplForm.id
      ? await client.from('carton_recipe_templates').update(payload).eq('id', tplForm.id)
      : await client.from('carton_recipe_templates').insert(payload)
    if (error) throw error
    toast.add({ title: tplForm.id ? 'Template updated' : 'Template created' })
    tplEditorOpen.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: 'Save failed', description: e.message, color: 'red' })
  } finally {
    tplSaving.value = false
  }
}
const deleteTemplate = async (t: any) => {
  if (!confirm(`Delete template "${t.name}"?`)) return
  const { error } = await client.from('carton_recipe_templates').delete().eq('id', t.id)
  if (error) { toast.add({ title: 'Delete failed', description: error.message, color: 'red' }); return }
  toast.add({ title: 'Template deleted' })
  await load()
}
</script>

<template>
  <div>
    <PageHeader kicker="Operations" title="Bills of material" subtitle="Recipes that drive material consumption during production">
      <UButton v-if="canWrite" variant="ghost" icon="i-heroicons-rectangle-stack" @click="tplMgrOpen = true">Recipe templates</UButton>
      <UButton v-if="canWrite" variant="soft" icon="i-heroicons-cube-transparent" @click="openRecipeNew">New carton recipe</UButton>
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
              <p v-if="b.carton_spec_snapshot" class="num text-[11px] text-amber-600 dark:text-amber-400 mt-0.5">
                {{ b.carton_spec_snapshot.ply_count }}-ply · {{ b.carton_spec_snapshot.flute_summary }}-flute ·
                {{ b.carton_spec_snapshot.length_mm }}×{{ b.carton_spec_snapshot.width_mm }}×{{ b.carton_spec_snapshot.height_mm }}mm ·
                {{ Number(b.carton_spec_snapshot.total_kg).toFixed(3) }} kg/box
              </p>
            </div>
            <div class="flex items-center gap-2 shrink-0">
              <UBadge size="xs" :color="b.is_active ? 'green' : 'gray'" variant="subtle">
                {{ b.is_active ? 'active' : 'inactive' }}
              </UBadge>
              <UButton
                v-if="canWrite && b.is_auto_generated"
                size="2xs" variant="soft" icon="i-heroicons-pencil-square" @click="openRecipeEdit(b)"
              >Recipe</UButton>
            </div>
          </div>
        </template>
        <ul class="text-sm divide-y divide-gray-100 dark:divide-zinc-800/60">
          <li v-for="l in b.bom_lines" :key="l.id" class="py-1.5">
            <div class="flex justify-between">
              <span>{{ l.component?.name }}</span>
              <span class="num text-gray-500">
                {{ Number(l.qty_per).toFixed(4) }}<span v-if="l.wastage_pct"> · +{{ l.wastage_pct }}% waste</span>
              </span>
            </div>
            <p v-if="l.note" class="text-[11px] text-gray-400 dark:text-zinc-600">{{ l.note }}</p>
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

    <USlideover v-model="recipeOpen" :ui="{ width: 'w-screen max-w-3xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header>
          <p class="font-medium">Carton recipe</p>
          <p class="text-xs text-gray-500">Standard RSC formula — sheet size and paper weight computed from ply, flute and dimensions</p>
        </template>

        <div class="space-y-5">
          <!-- Template -->
          <div>
            <p class="microlabel text-gray-400 dark:text-zinc-500 mb-1.5">Start from template <span class="text-gray-300 dark:text-zinc-700">(optional)</span></p>
            <USelect
              v-model="selectedTemplateId" :options="templateOptions"
              option-attribute="label" value-attribute="value" placeholder="Pick a 3/5/7-ply starting point…"
              @update:model-value="applyTemplate"
            />
          </div>

          <!-- Item -->
          <div>
            <div class="flex items-center justify-between mb-1.5">
              <p class="microlabel text-gray-400 dark:text-zinc-500">Finished item</p>
              <UCheckbox v-model="recipe.newItem" label="Create new item" />
            </div>
            <USelect
              v-if="!recipe.newItem"
              v-model="recipe.item_id" :options="finishedItems"
              option-attribute="name" value-attribute="id" placeholder="Select a carton…"
            />
            <div v-else class="grid grid-cols-2 gap-2">
              <UInput v-model="recipe.newSku" placeholder="SKU e.g. FG-CARTON-B" />
              <UInput v-model="recipe.newName" placeholder="Name e.g. Printed Carton — Model B" />
            </div>
          </div>

          <!-- Dimensions -->
          <div>
            <p class="microlabel text-gray-400 dark:text-zinc-500 mb-1.5">Internal dimensions (L × W × H)</p>
            <div class="grid grid-cols-4 gap-2">
              <UInput v-model.number="recipe.length" type="number" placeholder="Length" />
              <UInput v-model.number="recipe.width" type="number" placeholder="Width" />
              <UInput v-model.number="recipe.height" type="number" placeholder="Height" />
              <USelect v-model="recipe.unit" :options="unitOptions" option-attribute="label" value-attribute="value" />
            </div>
          </div>

          <!-- Ply -->
          <div>
            <p class="microlabel text-gray-400 dark:text-zinc-500 mb-1.5">Ply (wall construction)</p>
            <div class="flex gap-2">
              <button
                v-for="p in plyOptions" :key="p"
                class="px-4 py-1.5 rounded text-sm border cursor-pointer"
                :class="recipe.ply === p
                  ? 'border-amber-500 text-amber-600 dark:text-amber-400 bg-amber-50/60 dark:bg-amber-500/10'
                  : 'border-gray-200 dark:border-zinc-700 text-gray-500 dark:text-zinc-400'"
                @click="recipe.ply = p"
              >{{ p }}-ply</button>
            </div>
          </div>

          <!-- Layers -->
          <div>
            <p class="microlabel text-gray-400 dark:text-zinc-500 mb-1.5">Layers (outer → inner)</p>
            <div class="space-y-2">
              <div
                v-for="(l, i) in recipe.layers" :key="i"
                class="grid grid-cols-12 gap-2 items-center rounded ring-1 ring-gray-100 dark:ring-zinc-800 p-2"
              >
                <span class="col-span-3 text-xs text-gray-500 dark:text-zinc-400">{{ roleLabel(l, i, recipe.layers.length) }}</span>
                <UInput v-model.number="l.gsm" type="number" placeholder="GSM" class="col-span-2" />
                <USelect
                  v-if="l.role === 'medium'"
                  v-model="l.flute_code" :options="fluteOptions"
                  option-attribute="label" value-attribute="value" class="col-span-3"
                />
                <span v-else class="col-span-3" />
                <USelect
                  v-model="l.raw_item_id" :options="rawItems"
                  option-attribute="sku" value-attribute="id" placeholder="Paper reel…" class="col-span-4"
                />
              </div>
            </div>
          </div>

          <!-- Allowance & wastage -->
          <div class="grid grid-cols-2 gap-4">
            <UFormGroup label="Manufacturing allowance (mm)" hint="glue flap">
              <UInput v-model.number="recipe.allowance_mm" type="number" />
            </UFormGroup>
            <UFormGroup label="Wastage %" hint="applied to every layer">
              <UInput v-model.number="recipe.wastage_pct" type="number" />
            </UFormGroup>
          </div>

          <!-- Live preview -->
          <div class="rounded ring-1 ring-amber-500/30 bg-amber-50/40 dark:bg-amber-500/[0.04] p-3">
            <p class="microlabel text-amber-600 dark:text-amber-400 mb-2">Live preview</p>
            <div class="grid grid-cols-3 gap-3 text-[13px] mb-2">
              <div><span class="text-gray-500 dark:text-zinc-500">Blank size</span><br>
                <span class="num font-medium">{{ preview.blankLengthMm.toFixed(0) }} × {{ preview.blankWidthMm.toFixed(0) }} mm</span>
              </div>
              <div><span class="text-gray-500 dark:text-zinc-500">Blank area</span><br>
                <span class="num font-medium">{{ preview.blankAreaM2.toFixed(3) }} m²</span>
              </div>
              <div><span class="text-gray-500 dark:text-zinc-500">Total paper / box</span><br>
                <span class="num font-semibold text-amber-600 dark:text-amber-400">{{ preview.totalKg.toFixed(4) }} kg</span>
              </div>
            </div>
            <div class="space-y-0.5">
              <div v-for="(r, i) in preview.rows" :key="i" class="flex justify-between text-[12px] text-gray-600 dark:text-zinc-400">
                <span>{{ roleLabel(recipe.layers[i], i, recipe.layers.length) }} — {{ rawItemName(r.raw_item_id) }}</span>
                <span class="num">{{ r.kg.toFixed(4) }} kg</span>
              </div>
            </div>
          </div>
        </div>

        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="recipeOpen = false">Cancel</UButton>
            <UButton :loading="recipeSaving" @click="saveRecipe">Save recipe &amp; generate BOM</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <!-- Template manager: list -->
    <USlideover v-model="tplMgrOpen" :ui="{ width: 'w-screen max-w-xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header>
          <div class="flex items-center justify-between">
            <div>
              <p class="font-medium">Carton recipe templates</p>
              <p class="text-xs text-gray-500">Reusable ply/flute/GSM starting points for the recipe wizard</p>
            </div>
            <UButton v-if="canWrite" size="xs" icon="i-heroicons-plus" @click="openTplNew">New template</UButton>
          </div>
        </template>
        <div class="space-y-2">
          <div v-if="!templates.length" class="text-sm text-gray-400">No templates yet.</div>
          <div
            v-for="t in templates" :key="t.id"
            class="flex items-center justify-between rounded ring-1 ring-gray-100 dark:ring-zinc-800 p-3"
          >
            <div>
              <p class="text-sm font-medium">{{ t.name }}</p>
              <p class="text-xs text-gray-500 dark:text-zinc-500 num">{{ t.ply_count }}-ply · {{ t.layers.length }} layers</p>
            </div>
            <div v-if="canWrite" class="flex items-center gap-1 shrink-0">
              <UButton size="2xs" variant="ghost" icon="i-heroicons-pencil-square" @click="openTplEdit(t)" />
              <UButton size="2xs" variant="ghost" color="red" icon="i-heroicons-trash" @click="deleteTemplate(t)" />
            </div>
          </div>
        </div>
      </UCard>
    </USlideover>

    <!-- Template manager: create/edit editor -->
    <USlideover v-model="tplEditorOpen" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ tplForm.id ? 'Edit template' : 'New template' }}</p></template>
        <div class="space-y-5">
          <UFormGroup label="Name" required>
            <UInput v-model="tplForm.name" placeholder="e.g. 5-Ply — Double Wall (BC-flute)" />
          </UFormGroup>

          <div>
            <p class="microlabel text-gray-400 dark:text-zinc-500 mb-1.5">Ply (wall construction)</p>
            <div class="flex gap-2">
              <button
                v-for="p in plyOptions" :key="p"
                class="px-4 py-1.5 rounded text-sm border cursor-pointer"
                :class="tplForm.ply === p
                  ? 'border-amber-500 text-amber-600 dark:text-amber-400 bg-amber-50/60 dark:bg-amber-500/10'
                  : 'border-gray-200 dark:border-zinc-700 text-gray-500 dark:text-zinc-400'"
                @click="tplForm.ply = p"
              >{{ p }}-ply</button>
            </div>
          </div>

          <div>
            <p class="microlabel text-gray-400 dark:text-zinc-500 mb-1.5">Layers (outer → inner)</p>
            <div class="space-y-2">
              <div
                v-for="(l, i) in tplForm.layers" :key="i"
                class="grid grid-cols-12 gap-2 items-center rounded ring-1 ring-gray-100 dark:ring-zinc-800 p-2"
              >
                <span class="col-span-5 text-xs text-gray-500 dark:text-zinc-400">{{ tplRoleLabel(l, i, tplForm.layers.length) }}</span>
                <UInput v-model.number="l.gsm" type="number" placeholder="GSM" class="col-span-3" />
                <USelect
                  v-if="l.role === 'medium'"
                  v-model="l.flute_code" :options="fluteOptions"
                  option-attribute="label" value-attribute="value" class="col-span-4"
                />
                <span v-else class="col-span-4" />
              </div>
            </div>
          </div>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="tplEditorOpen = false">Cancel</UButton>
            <UButton :loading="tplSaving" @click="saveTemplate">Save template</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
