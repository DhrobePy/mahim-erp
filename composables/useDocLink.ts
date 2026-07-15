// One place that knows where every document type lives, so any
// ref_table/ref_id pair (journals, audit rows, notifications) can be
// turned into a clickable route.
const routes: Record<string, (id: string) => string> = {
  parties: (id) => `/parties/${id}`,
  sales_orders: (id) => `/sales/${id}`,
  lcs: (id) => `/lcs/${id}`,
  invoices: (id) => `/invoices/${id}`,
  journals: (id) => `/accounting/journal/${id}`,
  employees: (id) => `/hr/${id}`,
  lc_amendments: () => '/lcs',
  delivery_challans: () => '/challans',
  grns: () => '/procurement',
  debit_notes: () => '/procurement',
  credit_notes: () => '/invoices',
  bills: () => '/banking',
  lbpd_disbursements: () => '/banking',
  production_orders: () => '/production',
  payroll_runs: () => '/hr/payroll',
  employee_loans: () => '/hr',
  stock_movements: () => '/stock'
}

export const useDocLink = () => {
  const docLink = (table?: string | null, id?: string | null): string | null => {
    if (!table) return null
    const fn = routes[table]
    return fn ? fn(id ?? '') : null
  }
  return { docLink }
}
