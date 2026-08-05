<script setup lang="ts">
const client = useSupabaseClient()
const toast = useToast()
const { canWrite } = useProfile()
const { deleteRecord } = useRecycleBin()
const { t } = useI18n()

const items = ref<any[]>([])
const uoms = ref<any[]>([])
const categories = ref<any[]>([])
const loading = ref(true)
const search = ref('')

const typeOptions = computed(() => [
  { value: 'raw_material', label: t('items.types.raw_material') },
  { value: 'wip', label: t('items.types.wip') },
  { value: 'finished_good', label: t('items.types.finished_good') },
  { value: 'consumable', label: t('items.types.consumable') },
  { value: 'packaging', label: t('items.types.packaging') }
])

const columns = computed(() => [
  { key: 'sku', label: t('items.columns.sku') },
  { key: 'name', label: t('common.name') },
  { key: 'item_type', label: t('common.type') },
  { key: 'category', label: t('items.columns.category') },
  { key: 'uom', label: t('items.columns.uom') },
  { key: 'reorder_level', label: t('items.columns.reorder') },
  { key: 'actions', label: '' }
])

const load = async () => {
  loading.value = true
  const [{ data: it }, { data: u }, { data: c }] = await Promise.all([
    client.from('items')
      .select('*, uoms(code), item_categories(name)')
      .is('deleted_at', null)
      .order('created_at', { ascending: false }),
    client.from('uoms').select('id, code, name').is('deleted_at', null).order('code'),
    client.from('item_categories').select('id, name').is('deleted_at', null).order('name')
  ])
  items.value = it ?? []
  uoms.value = u ?? []
  categories.value = c ?? []
  loading.value = false
}
onMounted(load)

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  if (!q) return items.value
  return items.value.filter((i) =>
    i.sku.toLowerCase().includes(q) || i.name.toLowerCase().includes(q)
  )
})

// --- Create / edit ---
const open = ref(false)
const saving = ref(false)
const blank = () => ({
  id: null as string | null,
  sku: '',
  name: '',
  item_type: 'raw_material',
  category_id: null,
  uom_id: null,
  gsm: null,
  size_spec: '',
  color: '',
  reorder_level: 0,
  standard_cost: 0,
  is_active: true,
  notes: ''
})
const form = reactive(blank())

const openNew = () => { Object.assign(form, blank()); open.value = true }
const openEdit = (row: any) => {
  Object.assign(form, {
    id: row.id, sku: row.sku, name: row.name, item_type: row.item_type,
    category_id: row.category_id, uom_id: row.uom_id, gsm: row.gsm,
    size_spec: row.size_spec, color: row.color, reorder_level: row.reorder_level,
    standard_cost: row.standard_cost, is_active: row.is_active, notes: row.notes
  })
  open.value = true
}

const removeItem = async (row: any) => {
  const ok = await deleteRecord('items', row.id, `${row.sku} — ${row.name}`)
  if (ok) await load()
}

const save = async () => {
  saving.value = true
  const payload = { ...form }
  delete (payload as any).id
  try {
    const res = form.id
      ? await client.from('items').update(payload).eq('id', form.id)
      : await client.from('items').insert(payload)
    if (res.error) throw res.error
    toast.add({ title: form.id ? t('items.item_updated') : t('items.item_created') })
    open.value = false
    await load()
  } catch (e: any) {
    toast.add({ title: t('common.save_failed'), description: e.message, color: 'red' })
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div>
    <PageHeader :kicker="t('items.kicker')" :title="t('items.title')" :subtitle="t('items.subtitle')">
      <UButton v-if="canWrite" icon="i-heroicons-plus" @click="openNew">{{ t('items.new_item') }}</UButton>
    </PageHeader>

    <UCard>
      <template #header>
        <UInput v-model="search" icon="i-heroicons-magnifying-glass" :placeholder="t('items.search_placeholder')" />
      </template>

      <UTable :rows="filtered" :columns="columns" :loading="loading">
        <template #item_type-data="{ row }">
          <UBadge size="xs" variant="subtle" color="gray">{{ row.item_type }}</UBadge>
        </template>
        <template #category-data="{ row }">{{ row.item_categories?.name || '—' }}</template>
        <template #uom-data="{ row }">{{ row.uoms?.code || '—' }}</template>
        <template #actions-data="{ row }">
          <UButton
            v-if="canWrite"
            icon="i-heroicons-pencil-square" color="gray" variant="ghost" size="xs"
            @click="openEdit(row)"
          />
          <UButton
            v-if="canWrite"
            icon="i-heroicons-trash" color="red" variant="ghost" size="xs"
            @click="removeItem(row)"
          />
        </template>
        <template #empty-state>
          <div class="text-center py-6 text-sm text-gray-400">{{ t('items.no_items') }}</div>
        </template>
      </UTable>
    </UCard>

    <USlideover v-model="open">
      <UCard class="flex flex-col h-full" :ui="{ ring: '', rounded: 'rounded-none', shadow: '', body: { base: 'flex-1 overflow-y-auto' } }">
        <template #header>
          <p class="font-medium">{{ form.id ? t('items.edit_item') : t('items.new_item') }}</p>
        </template>

        <div class="grid grid-cols-2 gap-4">
          <UFormGroup :label="t('items.fields.sku')" required>
            <UInput v-model="form.sku" />
          </UFormGroup>
          <UFormGroup :label="t('common.type')">
            <USelect v-model="form.item_type" :options="typeOptions" option-attribute="label" value-attribute="value" />
          </UFormGroup>
          <UFormGroup :label="t('common.name')" required class="col-span-2">
            <UInput v-model="form.name" />
          </UFormGroup>
          <UFormGroup :label="t('items.columns.category')">
            <USelect
              v-model="form.category_id" :options="categories"
              option-attribute="name" value-attribute="id"
              placeholder="—"
            />
          </UFormGroup>
          <UFormGroup :label="t('items.fields.uom')">
            <USelect
              v-model="form.uom_id" :options="uoms"
              option-attribute="code" value-attribute="id"
              placeholder="—"
            />
          </UFormGroup>
          <UFormGroup :label="t('items.fields.gsm')">
            <UInput v-model.number="form.gsm" type="number" />
          </UFormGroup>
          <UFormGroup :label="t('items.fields.size_spec')">
            <UInput v-model="form.size_spec" />
          </UFormGroup>
          <UFormGroup :label="t('items.fields.reorder_level')">
            <UInput v-model.number="form.reorder_level" type="number" />
          </UFormGroup>
          <UFormGroup :label="t('items.fields.standard_cost')">
            <UInput v-model.number="form.standard_cost" type="number" />
          </UFormGroup>
        </div>

        <template #footer>
          <div class="flex justify-end gap-2">
            <UButton color="gray" variant="ghost" @click="open = false">{{ t('common.cancel') }}</UButton>
            <UButton :loading="saving" @click="save">{{ t('common.save') }}</UButton>
          </div>
        </template>
      </UCard>
    </USlideover>
  </div>
</template>
