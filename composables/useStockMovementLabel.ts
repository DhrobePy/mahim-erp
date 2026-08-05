// Shared label lookup for the stock_movement_type enum (supabase/migrations/0001_init.sql),
// so raw DB values like "grn_in" never leak into the UI unlocalized.
export const useStockMovementLabel = () => {
  const { t } = useI18n()
  const movementTypeLabel = (type: string) => {
    const key = `stock.adj_types.${type}`
    const label = t(key)
    return label === key ? type : label
  }
  return { movementTypeLabel }
}
