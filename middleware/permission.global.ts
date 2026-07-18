// Enforces "module disappears fully if off" for direct URL navigation,
// not just hidden nav links (which alone wouldn't stop someone typing
// the path in). RLS is the real backstop (migration 0019); this just
// keeps the app from rendering a page whose data will come back empty
// or error, with a clear reason instead.
const ROUTE_MODULES: Array<[string, string]> = [
  ['/accounting/accounts', 'bank_accounts'],
  ['/accounting/cash-sales', 'cash_sales'],
  ['/accounting/transfers', 'transfers'],
  ['/accounting/bank-charges', 'bank_charges'],
  ['/accounting/pnl', 'pnl'],
  ['/accounting/vat-return', 'vat_return'],
  ['/accounting/ait-summary', 'ait_summary'],
  ['/accounting', 'accounting'],
  ['/hr/attendance', 'attendance'],
  ['/hr/payroll', 'payroll'],
  ['/hr/stationery', 'stationery'],
  ['/hr', 'hr'],
  ['/admin/company', 'company'],
  ['/admin/directors', 'directors'],
  ['/admin/resolutions', 'resolutions'],
  ['/admin/documents', 'documents'],
  ['/admin/forwarding', 'forwarding'],
  ['/admin/bank-requests', 'bank_requests'],
  ['/admin/tax/corporate', 'tax_corporate'],
  ['/admin/tax', 'tax_it10b'],
  ['/ceo', 'ceo'],
  ['/items', 'items'],
  ['/stock', 'stock'],
  ['/boms', 'boms'],
  ['/production', 'production'],
  ['/parties', 'parties'],
  ['/procurement/purchase-orders', 'purchase_orders'],
  ['/procurement', 'procurement'],
  ['/quotations', 'quotations'],
  ['/sales', 'sales_orders'],
  ['/challans', 'challans'],
  ['/lcs', 'lcs'],
  ['/invoices', 'invoices'],
  ['/banking', 'banking'],
  ['/audit', 'audit']
]
const UNGATED = ['/login', '/confirm', '/access']

export default defineNuxtRouteMiddleware(async (to) => {
  if (import.meta.server) return
  if (UNGATED.some((p) => to.path === p || to.path.startsWith(p + '/'))) return
  if (to.path.startsWith('/print/')) return
  if (to.path === '/') return // dashboard — granted to everyone by default

  const match = ROUTE_MODULES.find(([prefix]) => to.path === prefix || to.path.startsWith(prefix + '/'))
  if (!match) return

  const { profile, load } = useProfile()
  const { canView, load: loadPermissions } = usePermissions()
  if (!profile.value) await load()
  await loadPermissions()

  if (!canView(match[1])) {
    return navigateTo('/')
  }
})
