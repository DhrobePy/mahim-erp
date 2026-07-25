// Client-side mirror of the save_carton_recipe() Postgres math, for
// instant preview while the user is still typing. The server is the
// source of truth — this only drives the UI preview panel.
export interface CartonLayer {
  layer_no: number
  role: 'liner' | 'medium'
  flute_code: string | null
  gsm: number
  raw_item_id: string | null
}

const TAKE_UP: Record<string, number> = { A: 1.53, B: 1.36, C: 1.42, E: 1.24, F: 1.18 }

const UNIT_TO_MM: Record<string, number> = { mm: 1, cm: 10, inch: 25.4 }

export const useCartonMath = () => {
  const toMm = (value: number, unit: string) => (Number(value) || 0) * (UNIT_TO_MM[unit] ?? 1)

  const plyLayout = (plyCount: number): Array<'liner' | 'medium'> => {
    const liners = (plyCount + 1) / 2
    const mediums = (plyCount - 1) / 2
    const out: Array<'liner' | 'medium'> = []
    for (let i = 0; i < liners + mediums; i++) out.push(i % 2 === 0 ? 'liner' : 'medium')
    return out
  }

  const blankDims = (lengthMm: number, widthMm: number, heightMm: number, allowanceMm: number) => ({
    blankLengthMm: 2 * (lengthMm + widthMm) + (allowanceMm || 40),
    blankWidthMm: heightMm + widthMm
  })

  const layerKg = (blankLengthMm: number, blankWidthMm: number, layer: CartonLayer) => {
    const takeUp = layer.role === 'medium' ? (TAKE_UP[layer.flute_code ?? ''] ?? 1) : 1
    return (blankLengthMm / 1000) * (blankWidthMm / 1000) * takeUp * (Number(layer.gsm) || 0) / 1000
  }

  const recipeSummary = (
    lengthMm: number, widthMm: number, heightMm: number, allowanceMm: number, layers: CartonLayer[]
  ) => {
    const { blankLengthMm, blankWidthMm } = blankDims(lengthMm, widthMm, heightMm, allowanceMm)
    const rows = layers.map((l) => ({ ...l, kg: layerKg(blankLengthMm, blankWidthMm, l) }))
    const totalKg = rows.reduce((s, r) => s + r.kg, 0)
    return { blankLengthMm, blankWidthMm, blankAreaM2: (blankLengthMm / 1000) * (blankWidthMm / 1000), rows, totalKg }
  }

  // Phase 1 costing: paper cost (from the recipe, at today's standard_cost)
  // + a flat other-direct-materials rate + overhead % + margin % = a
  // suggested selling price per box. Nothing here is persisted — it's
  // recomputed live so it always reflects current item costs, not
  // whatever they were when the recipe was last saved.
  const costBreakdown = (
    rows: Array<{ raw_item_id: string | null; kg: number }>,
    costOf: (itemId: string | null) => number,
    wastagePct: number,
    otherMaterialsCostPerBox: number,
    overheadPct: number,
    marginPct: number
  ) => {
    const paperLines = rows.map((r) => {
      const kgWithWastage = r.kg * (1 + (Number(wastagePct) || 0) / 100)
      const unitCost = costOf(r.raw_item_id)
      return { raw_item_id: r.raw_item_id, kg: kgWithWastage, unitCost, cost: kgWithWastage * unitCost }
    })
    const paperCost = paperLines.reduce((s, r) => s + r.cost, 0)
    const otherCost = Number(otherMaterialsCostPerBox) || 0
    const materialSubtotal = paperCost + otherCost
    const overheadAmount = materialSubtotal * ((Number(overheadPct) || 0) / 100)
    const totalCost = materialSubtotal + overheadAmount
    const suggestedPrice = totalCost * (1 + (Number(marginPct) || 0) / 100)
    return { paperLines, paperCost, otherCost, materialSubtotal, overheadAmount, totalCost, suggestedPrice }
  }

  return { toMm, plyLayout, blankDims, layerKg, recipeSummary, costBreakdown, TAKE_UP }
}
