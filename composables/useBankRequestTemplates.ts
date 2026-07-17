// Default subject/body text per bank service type — a starting point
// the user edits freely, same "choosable or manual" pattern as the
// board agenda and LC clause libraries.
export interface BankRequestTemplate {
  value: string
  label: string
  subject: string
  body: string
}

export const BANK_SERVICE_TEMPLATES: BankRequestTemplate[] = [
  {
    value: 'lc_issue', label: 'Issue LC',
    subject: 'Application for Opening of Local Letter of Credit',
    body: 'We request you to open a Local Letter of Credit in favour of the beneficiary named below, on the terms and conditions stated in our application enclosed herewith. Kindly complete the necessary formalities and advise us of the LC number upon issuance.'
  },
  {
    value: 'document_collection', label: 'Document collection',
    subject: 'Submission of Documents for Collection',
    body: 'We enclose herewith the following documents drawn against our bill for collection. Please arrange to present the same to the drawee/issuing bank and advise us of realization in due course.'
  },
  {
    value: 'discrepancy', label: 'Discrepancy',
    subject: 'Regarding Discrepancy Notice on Documents',
    body: 'With reference to the discrepancy notice issued by you on the documents submitted under the captioned LC, we request you to take up the matter with the issuing bank for acceptance/waiver of the discrepancy noted, and to negotiate the documents accordingly.'
  },
  {
    value: 'bank_statement', label: 'Bank statement',
    subject: 'Request for Statement of Account',
    body: 'We request you to kindly provide us with the statement of account for our account maintained with your branch, for the period mentioned below, at your earliest convenience.'
  },
  {
    value: 'lbpd_issue', label: 'LBPD issue',
    subject: 'Request for Local Bill Purchase and Discounting (LBPD)',
    body: 'We request you to purchase/discount the accepted bill referenced below under our approved LBPD facility, and to credit the net proceeds to our current account maintained with your branch.'
  },
  {
    value: 'fdr', label: 'FDR',
    subject: 'Instruction for Placement of Fixed Deposit Receipt (FDR)',
    body: 'We request you to place a Fixed Deposit Receipt of the amount and tenor mentioned below, debiting our current account maintained with your branch, at the prevailing rate of interest.'
  },
  {
    value: 'dps', label: 'DPS issue',
    subject: 'Application for Opening of Deposit Pension Scheme (DPS)',
    body: 'We request you to open a Deposit Pension Scheme (DPS) account in the name of the Company with the monthly installment and tenor mentioned below, debiting our current account maintained with your branch.'
  },
  {
    value: 'manual', label: 'Manual / other service',
    subject: '', body: ''
  }
]

export const useBankRequestTemplates = () => {
  const byValue = (v: string) => BANK_SERVICE_TEMPLATES.find((t) => t.value === v)
  return { all: BANK_SERVICE_TEMPLATES, byValue }
}
