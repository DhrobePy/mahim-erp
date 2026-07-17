<script setup lang="ts">
definePageMeta({ layout: false })

const route = useRoute()
const client = useSupabaseClient()
const { logoUrl } = useCompanyLogo()

const id = route.params.id as string
const resolution = ref<any>(null)
const company = ref<any>(null)
const loading = ref(true)

const meetingTypeLabel: Record<string, string> = {
  board_meeting: 'Board of Directors', agm: 'Annual General Meeting',
  egm: 'Extraordinary General Meeting', circular_resolution: 'Circular Resolution'
}

const load = async () => {
  loading.value = true
  const { data } = await client.from('board_resolutions')
    .select(`*, board_resolution_agendas(agenda_no, title, resolution_text),
      board_resolution_attendees(company_directors(full_name, designation))`)
    .eq('id', id).single()
  resolution.value = data
  if (data) {
    const { data: c } = await client.from('companies').select('*').eq('id', (data as any).company_id).single()
    company.value = c
  }
  loading.value = false
  if (route.query.auto) setTimeout(() => window.print(), 600)
}
onMounted(load)

const agendasSorted = computed(() =>
  [...(resolution.value?.board_resolution_agendas ?? [])].sort((a: any, b: any) => a.agenda_no - b.agenda_no))
const fmtDate = (d?: string) => d
  ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' })
  : '—'
</script>

<template>
  <div class="print-root">
    <div class="no-print toolbar">
      <NuxtLink to="/admin/resolutions" class="back">← back</NuxtLink>
      <button class="print-btn" @click="() => window.print()">🖨 Print</button>
    </div>

    <div v-if="loading" class="no-print" style="padding: 40px; text-align: center;">Loading…</div>

    <div v-else-if="resolution && company" class="sheet">
      <div class="letterhead">
        <img v-if="logoUrl(company)" :src="logoUrl(company)" class="co-logo" alt="Company logo">
        <div class="co-name">{{ company.legal_name || company.name }}</div>
        <div class="small">{{ company.address || '' }}</div>
      </div>

      <div class="doc-title">
        MINUTES OF THE {{ (resolution.meeting_no || '').toUpperCase() || 'MEETING' }} OF THE
        {{ meetingTypeLabel[resolution.meeting_type]?.toUpperCase() }}
      </div>
      <p class="small center">
        held on {{ fmtDate(resolution.meeting_date) }}{{ resolution.venue ? ' at ' + resolution.venue : '' }}
      </p>

      <p class="small"><b>Ref:</b> {{ resolution.resolution_no }}</p>
      <p v-if="resolution.chairperson" class="small"><b>In the Chair:</b> {{ resolution.chairperson }}</p>

      <div v-if="resolution.board_resolution_attendees?.length" class="attendees">
        <p class="section-hdr">PRESENT</p>
        <ol>
          <li v-for="(a, i) in resolution.board_resolution_attendees" :key="i">
            {{ a.company_directors?.full_name }} — {{ a.company_directors?.designation?.replace(/_/g, ' ') }}
          </li>
        </ol>
      </div>

      <p class="section-hdr">RESOLUTIONS</p>
      <div v-for="a in agendasSorted" :key="a.agenda_no" class="agenda">
        <p class="agenda-title">{{ a.agenda_no }}. {{ a.title }}</p>
        <p class="agenda-text">{{ a.resolution_text }}</p>
      </div>
      <p v-if="!agendasSorted.length" class="small center">No agenda items recorded.</p>

      <p class="closing">There being no other business, the meeting concluded with a vote of thanks to the Chair.</p>

      <div class="row spread sig-block">
        <div class="sig"><div class="sig-line" /><div class="small">Chairperson</div></div>
        <div class="sig"><div class="sig-line" /><div class="small">Company Secretary</div></div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.print-root { min-height: 100vh; background: #3f3f46; padding: 16px 0 48px; font-family: Georgia, 'Times New Roman', serif; }
.toolbar {
  position: sticky; top: 0; z-index: 5; display: flex; gap: 18px; align-items: center; justify-content: center;
  background: #18181b; color: #e4e4e7; padding: 10px; margin: -16px 0 16px; font-family: Inter, sans-serif; font-size: 13px;
}
.toolbar .back { color: #fbbf24; text-decoration: none; }
.print-btn { background: #f59e0b; color: #000; border: 0; border-radius: 4px; padding: 6px 16px; font-weight: 600; cursor: pointer; }
.sheet {
  width: 210mm; min-height: 280mm; margin: 0 auto 20px; background: #fff; color: #111;
  padding: 18mm 16mm; box-shadow: 0 2px 12px rgba(0,0,0,.4); font-size: 13px; line-height: 1.6;
}
.letterhead { text-align: center; border-bottom: 2px solid #111; padding-bottom: 8px; margin-bottom: 12px; }
.co-logo { max-height: 48px; max-width: 220px; margin: 0 auto 6px; display: block; object-fit: contain; }
.co-name { font-size: 20px; font-weight: 700; letter-spacing: 1px; }
.doc-title { text-align: center; font-size: 14px; font-weight: 700; margin: 8px 0 4px; line-height: 1.4; }
.small { font-size: 11.5px; color: #333; }
.center { text-align: center; }
.row { display: flex; }
.spread { justify-content: space-between; }
.section-hdr { font-weight: 700; font-size: 12px; margin: 16px 0 6px; text-transform: uppercase; letter-spacing: .5px; border-bottom: 1px solid #111; padding-bottom: 2px; }
.attendees ol { margin: 4px 0 0 18px; padding: 0; font-size: 12.5px; }
.agenda { margin-bottom: 12px; }
.agenda-title { font-weight: 700; margin-bottom: 2px; }
.agenda-text { text-align: justify; margin: 0; }
.closing { margin-top: 20px; font-style: italic; font-size: 12px; }
.sig { text-align: center; }
.sig-line { border-top: 1px solid #111; width: 200px; margin: 46px auto 4px; }
.sig-block { margin-top: 30px; }
@media print {
  .no-print { display: none !important; }
  .print-root { background: #fff; padding: 0; }
  .sheet { box-shadow: none; margin: 0; min-height: auto; }
}
</style>
