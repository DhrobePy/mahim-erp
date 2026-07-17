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

  return { toMm, plyLayout, blankDims, layerKg, recipeSummary, TAKE_UP }
}
