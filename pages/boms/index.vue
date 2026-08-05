<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite, activeCompanyId } = useProfile()
const { toMm, plyLayout, recipeSummary, costBreakdown } = useCartonMath()
const { money } = useFmt()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const boms = ref<any[]>([])
const items = ref<any[]>([])
const templates = ref<any[]>([])
const company = ref<any>(null)
const loading = ref(true)

const costOf = (itemId: string | null) => items.value.find((i) => i.id === itemId)?.standard_cost ?? 0
const suggestedOverheadPct = computed(() => {
  const mat = Number(company.value?.ref_material_cost) || 0
  const fac = Number(company.value?.ref_factory_cost) || 0
  return mat > 0 ? Math.round((fac / mat) * 1000) / 10 : 0
})

const finishedItems = computed(() =>
  items.value.filter((i) => ['finished_good', 'wip'].includes(i.item_type))
)
const rawItems = computed(() => items.value.filter((i) => i.item_type === 'raw_material'))
const templateOptions = computed(() => templates.value.map((t) => ({ value: t.id, label: `${t.name}` })))

const load = async () => {
  loading.value = true
  const [{ data: b }, { data: it }, { data: tpl }, { data: co }] = await Promise.all([
    client.from('boms')
      .select('*, items:finished_item_id(name, sku), bom_lines(id, qty_per, wastage_pct, note, component:component_item_id(name, sku))')
      .is('deleted_at', null)
      .order('created_at', { ascending: false }),
    client.from('items').select('id, sku, name, item_type, standard_cost').eq('is_active', true).is('deleted_at', null).order('name'),
    client.from('carton_recipe_templates').select('*').order('ply_count').order('name'),
    client.from('companies').select('ref_material_cost, ref_factory_cost, default_margin_pct').eq('id', activeCompanyId.value).single()
  ])
  boms.value = b ?? []
  items.value = it ?? []
  templates.value = tpl ?? []
  company.value = co
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

const removeBom = async (b: any) => {
  const ok = await deleteRecord('boms', b.id, b.name)
  if (ok) await load()
}
const addLine = () => form.lines.push({ component_item_id: null, qty_per: 1, wastage_pct: 0 })
const removeLine = (i: number) => form.lines.splice(i, 1)

const save = async () => {
  if (!form.finished_item_id || !form.name) {
    toast.add({ title: t('boms.validation.finished_item_name_required'), color: 'red' })
    return
  }
  const validLines = form.lines.filter((l) => l.component_item_id)
  if (!validLines.length) {
    toast.add({ title: t('boms.validation.at_least_one_component'), color: 'red' })
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

    toast.add({ title: t('boms.bom_created') })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('common.save_failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}

// --- Carton recipe wizard ---
const recipeOpen = ref(false)
const recipeSaving = ref(false)
const unitOptions = [{ value: 'cm', label: 'cm' }, { value: 'mm', label: 'mm' }, { value: 'inch', label: 'inch' }]
const fluteOptions = computed(() => [
  { value: 'A', label: t('boms.flutes.a') }, { value: 'B', label: t('boms.flutes.b') },
  { value: 'C', label: t('boms.flutes.c') }, { value: 'E', label: t('boms.flutes.e') },
  { value: 'F', label: t('boms.flutes.f') }
])
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
  other_materials_cost_per_box: 0,
  overhead_pct_override: null as number | null,
  margin_pct_override: null as number | null,
  layers: [] as Array<{ layer_no: number; role: 'liner' | 'medium'; flute_code: string | null; gsm: number; raw_item_id: string | null }>
})
const selectedTemplateId = ref<string | null>(null)

const roleLabel = (l: typeof recipe.layers[number], idx: number, total: number) => {
  if (l.role === 'medium') {
    const n = recipe.layers.slice(0, idx + 1).filter((x) => x.role === 'medium').length
    return t('boms.layers.medium', { n })
  }
  if (idx === 0) return t('boms.layers.outer_liner')
  if (idx === total - 1) return t('boms.layers.inner_liner')
  return t('boms.layers.middle_liner')
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
    unit: 'cm', length: 0, width: 0, height: 0, ply: 3, allowance_mm: 40, wastage_pct: 5,
    other_materials_cost_per_box: 0, overhead_pct_override: null, margin_pct_override: null
  })
  selectedTemplateId.value = null
  rebuildLayers()
  recipeOpen.value = true
}

const openRecipeEdit = async (bom: any) => {
  const { data: spec } = await client.from('carton_specs')
    .select('*, carton_spec_layers(layer_no, role, flute_code, gsm, raw_item_id)')
    .eq('item_id', bom.finished_item_id).maybeSingle()
  if (!spec) { toast.add({ title: t('boms.recipe.no_recipe_found'), color: 'amber' }); return }
  selectedTemplateId.value = null
  Object.assign(recipe, {
    item_id: bom.finished_item_id, newItem: false, newSku: '', newName: '',
    unit: 'mm', length: spec.length_mm, width: spec.width_mm, height: spec.height_mm,
    ply: spec.ply_count, allowance_mm: spec.manufacturing_allowance_mm, wastage_pct: spec.wastage_pct,
    other_materials_cost_per_box: spec.other_materials_cost_per_box ?? 0,
    overhead_pct_override: spec.overhead_pct_override, margin_pct_override: spec.margin_pct_override,
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

const costPreview = computed(() => costBreakdown(
  preview.value.rows, costOf, recipe.wastage_pct, recipe.other_materials_cost_per_box,
  recipe.overhead_pct_override ?? suggestedOverheadPct.value,
  recipe.margin_pct_override ?? (Number(company.value?.default_margin_pct) || 0)
))

const rawItemName = (id: string | null) => rawItems.value.find((i) => i.id === id)?.sku ?? '—'

const saveRecipe = async () => {
  if (recipe.newItem) {
    if (!recipe.newSku || !recipe.newName) {
      toast.add({ title: t('boms.validation.new_item_required'), color: 'red' }); return
    }
  } else if (!recipe.item_id) {
    toast.add({ title: t('boms.validation.pick_finished_item'), color: 'red' }); return
  }
  if (!recipeMm.value.length || !recipeMm.value.width || !recipeMm.value.height) {
    toast.add({ title: t('boms.validation.enter_dimensions'), color: 'red' }); return
  }
  if (recipe.layers.some((l) => !l.raw_item_id || !l.gsm)) {
    toast.add({ title: t('boms.validation.layer_gsm_material'), color: 'red' }); return
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
      p_layers: recipe.layers,
      p_other_materials_cost_per_box: recipe.other_materials_cost_per_box,
      p_overhead_pct_override: recipe.overhead_pct_override,
      p_margin_pct_override: recipe.margin_pct_override
    } as any)
    if (error) throw error
    toast.add({ title: t('boms.recipe.saved_title'), description: t('boms.recipe.saved_description', { kg: preview.value.totalKg.toFixed(4) }) })
    recipeOpen.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('boms.recipe.failed'), description: e.message, color: 'red' })
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
    return t('boms.layers.medium', { n })
  }
  if (idx === 0) return t('boms.layers.outer_liner')
  if (idx === total - 1) return t('boms.layers.inner_liner')
  return t('boms.layers.middle_liner')
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
  if (!tplForm.name) { toast.add({ title: t('boms.validation.template_name_required'), color: 'red' }); return }
  if (tplForm.layers.some((l) => !l.gsm)) { toast.add({ title: t('boms.validation.layer_gsm_required'), color: 'red' }); return }
  tplSaving.value = true
  try {
    const payload = { name: tplForm.name, ply_count: tplForm.ply, layers: tplForm.layers }
    const { error } = tplForm.id
      ? await client.from('carton_recipe_templates').update(payload).eq('id', tplForm.id)
      : await client.from('carton_recipe_templates').insert(payload)
    if (error) throw error
    toast.add({ title: tplForm.id ? t('boms.template_manager.template_updated') : t('boms.template_manager.template_created') })
    tplEditorOpen.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('common.save_failed'), description: e.message, color: 'red' })
  } finally {
    tplSaving.value = false
  }
}
const deleteTemplate = async (tpl: any) => {
  if (!confirm(t('boms.template_manager.delete_confirm', { name: tpl.name }))) return
  const { error } = await client.from('carton_recipe_templates').delete().eq('id', tpl.id)
  if (error) { toast.add({ title: t('boms.template_manager.delete_failed'), description: error.message, color: 'red' }); return }
  toast.add({ title: t('boms.template_manager.template_deleted') })
  await load()
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('boms.kicker')" :title="t('boms.title')" :subtitle="t('boms.subtitle')">
      <UButton v-if="canWrite" variant="ghost" icon="i-heroicons-rectangle-stack" @click="tplMgrOpen = true">{{ t('boms.recipe_templates_btn') }}</UButton>
      <UButton v-if="canWrite" variant="soft" icon="i-heroicons-cube-transparent" @click="openRecipeNew">{{ t('boms.new_carton_recipe_btn') }}</UButton>
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('boms.new_bom_btn') }}</UButton>
    </PageHeader>

    <div v-if="loading" class="text-sm text-gray-400">{{ t('common.loading') }}</div>
    <div v-else-if="!boms.length" class="text-sm text-gray-400">{{ t('boms.no_boms') }}</div>

    <div class="grid gap-4 md:grid-cols-2">
      <UCard v-for="b in boms" :key="b.id">
        <template #header>
          <div class="flex items-center justify-between">
            <div>
              <p class="font-medium">{{ b.name }}</p>
              <p class="text-xs text-gray-500">
                {{ b.items?.name }} · {{ t('boms.card.yields', { qty: b.output_qty }) }}
              </p>
              <p v-if="b.carton_spec_snapshot" class="num text-[11px] text-amber-600 dark:text-amber-400 mt-0.5">
                {{ t('boms.card.spec_summary', {
                  ply: b.carton_spec_snapshot.ply_count,
                  flute: b.carton_spec_snapshot.flute_summary,
                  l: b.carton_spec_snapshot.length_mm,
                  w: b.carton_spec_snapshot.width_mm,
                  h: b.carton_spec_snapshot.height_mm,
                  kg: Number(b.carton_spec_snapshot.total_kg).toFixed(3)
                }) }}
              </p>
            </div>
            <div class="flex items-center gap-2 shrink-0">
              <UBadge size="xs" :color="b.is_active ? 'green' : 'gray'" variant="subtle">
                {{ b.is_active ? t('common.active') : t('common.inactive') }}
              </UBadge>
              <UButton
                v-if="canWrite && b.is_auto_generated"
                size="2xs" variant="soft" icon="i-heroicons-pencil-square" @click="openRecipeEdit(b)"
              >{{ t('boms.card.recipe_btn') }}</UButton>
              <UButton
                v-if="canWrite"
                size="2xs" variant="ghost" color="red" icon="i-heroicons-trash" @click="removeBom(b)"
              />
            </div>
          </div>
        </template>
        <ul class="text-sm divide-y divide-gray-100 dark:divide-zinc-800/60">
          <li v-for="l in b.bom_lines" :key="l.id" class="py-1.5">
            <div class="flex justify-between">
              <span>{{ l.component?.name }}</span>
              <span class="num text-gray-500">
                {{ Number(l.qty_per).toFixed(4) }}<span v-if="l.wastage_pct"> · +{{ l.wastage_pct }}% {{ t('boms.card.waste') }}</span>
              </span>
            </div>
            <p v-if="l.note" class="text-[11px] text-gray-400 dark:text-zinc-600">{{ l.note }}</p>
          </li>
        </ul>
      </UCard>
    </div>

    <USlideover v-model="open" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ t('boms.new_bom.title') }}</p></template>
        <div class="space-y-4">
          <div class="grid grid-cols-2 gap-4">
            <UFormGroup :label="t('boms.new_bom.finished_item')" required>
              <USelect
                v-model="form.finished_item_id" :options="finishedItems"
                option-attribute="name" value-attribute="id" :placeholder="t('boms.new_bom.select')"
              />
            </UFormGroup>
            <UFormGroup :label="t('boms.new_bom.output_qty')" required>
              <UInput v-model.number="form.output_qty" type="number" />
            </UFormGroup>
            <UFormGroup :label="t('boms.new_bom.name')" required class="col-span-2">
              <UInput v-model="form.name" :placeholder="t('boms.new_bom.name_placeholder')" />
            </UFormGroup>
          </div>

          <div>
            <div class="flex items-center justify-between mb-2">
              <p class="text-sm font-medium">{{ t('boms.new_bom.components') }}</p>
              <UButton size="xs" variant="soft" icon="i-heroicons-plus" @click="addLine">{{ t('boms.new_bom.add') }}</UButton>
            </div>
            <div v-for="(l, i) in form.lines" :key="i" class="grid grid-cols-12 gap-2 mb-2 items-center">
              <USelect
                v-model="l.component_item_id" :options="items"
                option-attribute="name" value-attribute="id" :placeholder="t('boms.new_bom.component_placeholder')"
                class="col-span-6"
              />
              <UInput v-model.number="l.qty_per" type="number" :placeholder="t('boms.new_bom.qty_placeholder')" class="col-span-3" />
              <UInput v-model.number="l.wastage_pct" type="number" :placeholder="t('boms.new_bom.waste_placeholder')" class="col-span-2" />
              <UButton
                icon="i-heroicons-trash" color="red" variant="ghost" size="xs" class="col-span-1"
                @click="removeLine(i)"
              />
            </div>
          </div>
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ t('boms.new_bom.save_bom') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>

    <USlideover v-model="recipeOpen" :ui="{ width: 'w-screen max-w-3xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header>
          <p class="font-medium">{{ t('boms.recipe.title') }}</p>
          <p class="text-xs text-gray-500">{{ t('boms.recipe.subtitle') }}</p>
        </template>

        <div class="space-y-5">
          <!-- Template -->
          <div>
            <p class="microlabel text-gray-400 dark:text-zinc-500 mb-1.5">{{ t('boms.recipe.start_from_template') }} <span class="text-gray-300 dark:text-zinc-700">{{ t('boms.recipe.optional') }}</span></p>
            <USelect
              v-model="selectedTemplateId" :options="templateOptions"
              option-attribute="label" value-attribute="value" :placeholder="t('boms.recipe.template_placeholder')"
              @update:model-value="applyTemplate"
            />
          </div>

          <!-- Item -->
          <div>
            <div class="flex items-center justify-between mb-1.5">
              <p class="microlabel text-gray-400 dark:text-zinc-500">{{ t('boms.recipe.finished_item') }}</p>
              <UCheckbox v-model="recipe.newItem" :label="t('boms.recipe.create_new_item')" />
            </div>
            <USelect
              v-if="!recipe.newItem"
              v-model="recipe.item_id" :options="finishedItems"
              option-attribute="name" value-attribute="id" :placeholder="t('boms.recipe.select_carton_placeholder')"
            />
            <div v-else class="grid grid-cols-2 gap-2">
              <UInput v-model="recipe.newSku" :placeholder="t('boms.recipe.new_sku_placeholder')" />
              <UInput v-model="recipe.newName" :placeholder="t('boms.recipe.new_name_placeholder')" />
            </div>
          </div>

          <!-- Dimensions -->
          <div>
            <p class="microlabel text-gray-400 dark:text-zinc-500 mb-1.5">{{ t('boms.recipe.dimensions') }}</p>
            <div class="grid grid-cols-4 gap-2">
              <UInput v-model.number="recipe.length" type="number" :placeholder="t('boms.recipe.length_placeholder')" />
              <UInput v-model.number="recipe.width" type="number" :placeholder="t('boms.recipe.width_placeholder')" />
              <UInput v-model.number="recipe.height" type="number" :placeholder="t('boms.recipe.height_placeholder')" />
              <USelect v-model="recipe.unit" :options="unitOptions" option-attribute="label" value-attribute="value" />
            </div>
          </div>

          <!-- Ply -->
          <div>
            <p class="microlabel text-gray-400 dark:text-zinc-500 mb-1.5">{{ t('boms.recipe.ply_construction') }}</p>
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
            <p class="microlabel text-gray-400 dark:text-zinc-500 mb-1.5">{{ t('boms.recipe.layers_heading') }}</p>
            <div class="space-y-2">
              <div
                v-for="(l, i) in recipe.layers" :key="i"
                class="grid grid-cols-12 gap-2 items-center rounded ring-1 ring-gray-100 dark:ring-zinc-800 p-2"
              >
                <span class="col-span-3 text-xs text-gray-500 dark:text-zinc-400">{{ roleLabel(l, i, recipe.layers.length) }}</span>
                <UInput v-model.number="l.gsm" type="number" :placeholder="t('boms.recipe.gsm_placeholder')" class="col-span-2" />
                <USelect
                  v-if="l.role === 'medium'"
                  v-model="l.flute_code" :options="fluteOptions"
                  option-attribute="label" value-attribute="value" class="col-span-3"
                />
                <span v-else class="col-span-3" />
                <USelect
                  v-model="l.raw_item_id" :options="rawItems"
                  option-attribute="sku" value-attribute="id" :placeholder="t('boms.recipe.paper_reel_placeholder')" class="col-span-4"
                />
              </div>
            </div>
          </div>

          <!-- Allowance & wastage -->
          <div class="grid grid-cols-2 gap-4">
            <UFormGroup :label="t('boms.recipe.allowance')" :hint="t('boms.recipe.allowance_hint')">
              <UInput v-model.number="recipe.allowance_mm" type="number" />
            </UFormGroup>
            <UFormGroup :label="t('boms.recipe.wastage_pct')" :hint="t('boms.recipe.wastage_hint')">
              <UInput v-model.number="recipe.wastage_pct" type="number" />
            </UFormGroup>
          </div>

          <!-- Live preview -->
          <div class="rounded ring-1 ring-amber-500/30 bg-amber-50/40 dark:bg-amber-500/[0.04] p-3">
            <p class="microlabel text-amber-600 dark:text-amber-400 mb-2">{{ t('boms.recipe.live_preview') }}</p>
            <div class="grid grid-cols-3 gap-3 text-[13px] mb-2">
              <div><span class="text-gray-500 dark:text-zinc-500">{{ t('boms.recipe.blank_size') }}</span><br>
                <span class="num font-medium">{{ preview.blankLengthMm.toFixed(0) }} × {{ preview.blankWidthMm.toFixed(0) }} mm</span>
              </div>
              <div><span class="text-gray-500 dark:text-zinc-500">{{ t('boms.recipe.blank_area') }}</span><br>
                <span class="num font-medium">{{ preview.blankAreaM2.toFixed(3) }} m²</span>
              </div>
              <div><span class="text-gray-500 dark:text-zinc-500">{{ t('boms.recipe.total_paper_per_box') }}</span><br>
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

          <!-- Costing & suggested price -->
          <div class="rounded ring-1 ring-emerald-500/30 bg-emerald-50/40 dark:bg-emerald-500/[0.04] p-3">
            <p class="microlabel text-emerald-600 dark:text-emerald-400 mb-2">{{ t('boms.costing.title') }}</p>

            <div class="space-y-0.5 text-[12px] mb-3">
              <div v-for="(r, i) in costPreview.paperLines" :key="i" class="flex justify-between text-gray-600 dark:text-zinc-400">
                <span>{{ rawItemName(r.raw_item_id) }} — {{ r.kg.toFixed(4) }} kg × {{ money(r.unitCost) }}</span>
                <span class="num">{{ money(r.cost) }}</span>
              </div>
              <div class="flex justify-between text-gray-600 dark:text-zinc-400">
                <span>{{ t('boms.costing.paper_subtotal', { pct: recipe.wastage_pct }) }}</span>
                <span class="num">{{ money(costPreview.paperCost) }}</span>
              </div>
            </div>

            <div class="grid grid-cols-2 gap-3 mb-3">
              <UFormGroup :label="t('boms.costing.other_materials')" :hint="t('boms.costing.other_materials_hint')">
                <UInput v-model.number="recipe.other_materials_cost_per_box" type="number" step="0.01" />
              </UFormGroup>
              <UFormGroup
                :label="t('boms.costing.overhead_pct')"
                :hint="t('boms.costing.overhead_hint', { pct: suggestedOverheadPct })"
              >
                <UInput v-model.number="recipe.overhead_pct_override" type="number" step="0.1" :placeholder="String(suggestedOverheadPct)" />
              </UFormGroup>
            </div>
            <UFormGroup :label="t('boms.costing.margin_pct')" class="mb-3" :hint="t('boms.costing.margin_hint', { pct: company?.default_margin_pct ?? 0 })">
              <UInput v-model.number="recipe.margin_pct_override" type="number" step="0.1" class="w-40" :placeholder="String(company?.default_margin_pct ?? 0)" />
            </UFormGroup>

            <div class="space-y-1 text-[13px] border-t border-emerald-500/20 pt-2">
              <div class="flex justify-between"><span class="text-gray-500 dark:text-zinc-500">{{ t('boms.costing.material_subtotal') }}</span><span class="num">{{ money(costPreview.materialSubtotal) }}</span></div>
              <div class="flex justify-between"><span class="text-gray-500 dark:text-zinc-500">{{ t('boms.costing.overhead_amount', { pct: recipe.overhead_pct_override ?? suggestedOverheadPct }) }}</span><span class="num">{{ money(costPreview.overheadAmount) }}</span></div>
              <div class="flex justify-between font-medium"><span>{{ t('boms.costing.total_cost') }}</span><span class="num">{{ money(costPreview.totalCost) }}</span></div>
              <div class="flex justify-between text-emerald-600 dark:text-emerald-400 font-semibold text-[15px] pt-1">
                <span>{{ t('boms.costing.suggested_price', { pct: recipe.margin_pct_override ?? (company?.default_margin_pct ?? 0) }) }}</span>
                <span class="num">{{ money(costPreview.suggestedPrice) }}</span>
              </div>
            </div>
          </div>
        </div>

        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="recipeOpen = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="recipeSaving" @click="saveRecipe">{{ t('boms.recipe.save_recipe_btn') }}</UButton>
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
              <p class="font-medium">{{ t('boms.template_manager.title') }}</p>
              <p class="text-xs text-gray-500">{{ t('boms.template_manager.subtitle') }}</p>
            </div>
            <UButton v-if="canWrite" size="xs" icon="i-heroicons-plus" @click="openTplNew">{{ t('boms.template_manager.new_template') }}</UButton>
          </div>
        </template>
        <div class="space-y-2">
          <div v-if="!templates.length" class="text-sm text-gray-400">{{ t('boms.template_manager.no_templates') }}</div>
          <div
            v-for="tpl in templates" :key="tpl.id"
            class="flex items-center justify-between rounded ring-1 ring-gray-100 dark:ring-zinc-800 p-3"
          >
            <div>
              <p class="text-sm font-medium">{{ tpl.name }}</p>
              <p class="text-xs text-gray-500 dark:text-zinc-500 num">{{ t('boms.template_manager.ply_layers', { ply: tpl.ply_count, n: tpl.layers.length }) }}</p>
            </div>
            <div v-if="canWrite" class="flex items-center gap-1 shrink-0">
              <UButton size="2xs" variant="ghost" icon="i-heroicons-pencil-square" @click="openTplEdit(tpl)" />
              <UButton size="2xs" variant="ghost" color="red" icon="i-heroicons-trash" @click="deleteTemplate(tpl)" />
            </div>
          </div>
        </div>
      </UCard>
    </USlideover>

    <!-- Template manager: create/edit editor -->
    <USlideover v-model="tplEditorOpen" :ui="{ width: 'w-screen max-w-2xl' }">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header><p class="font-medium">{{ tplForm.id ? t('boms.template_manager.edit_title') : t('boms.template_manager.new_title') }}</p></template>
        <div class="space-y-5">
          <UFormGroup :label="t('boms.template_manager.name')" required>
            <UInput v-model="tplForm.name" :placeholder="t('boms.template_manager.name_placeholder')" />
          </UFormGroup>

          <div>
            <p class="microlabel text-gray-400 dark:text-zinc-500 mb-1.5">{{ t('boms.recipe.ply_construction') }}</p>
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
            <p class="microlabel text-gray-400 dark:text-zinc-500 mb-1.5">{{ t('boms.recipe.layers_heading') }}</p>
            <div class="space-y-2">
              <div
                v-for="(l, i) in tplForm.layers" :key="i"
                class="grid grid-cols-12 gap-2 items-center rounded ring-1 ring-gray-100 dark:ring-zinc-800 p-2"
              >
                <span class="col-span-5 text-xs text-gray-500 dark:text-zinc-400">{{ tplRoleLabel(l, i, tplForm.layers.length) }}</span>
                <UInput v-model.number="l.gsm" type="number" :placeholder="t('boms.recipe.gsm_placeholder')" class="col-span-3" />
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
            <UButton color="gray" variant="ghost" @click="tplEditorOpen = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="tplSaving" @click="saveTemplate">{{ t('boms.template_manager.save_template') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
