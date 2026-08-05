// Buckets rows into a fixed trailing window of calendar days (oldest → newest),
// summing valueOf(row) per day. cumulative=true turns the daily sums into a
// running total, which is what a balance/quantity trend sparkline wants.
export function bucketDaily(
  rows: any[],
  dateOf: (row: any) => string | null | undefined,
  valueOf: (row: any) => number,
  days = 14,
  cumulative = false
): number[] {
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const startTime = today.getTime() - (days - 1) * 86400000
  const buckets = Array.from({ length: days }, () => 0)

  for (const row of rows) {
    const raw = dateOf(row)
    if (!raw) continue
    const d = new Date(raw)
    d.setHours(0, 0, 0, 0)
    const idx = Math.round((d.getTime() - startTime) / 86400000)
    if (idx < 0 || idx >= days) continue
    buckets[idx] += valueOf(row)
  }

  if (!cumulative) return buckets
  let running = 0
  return buckets.map((v) => (running += v))
}
