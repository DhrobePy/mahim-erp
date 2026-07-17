// Standard Board of Directors resolution templates for a Bangladeshi
// Ltd company. Pick one to prefill title + "RESOLVED THAT..." wording,
// then edit freely — or skip the library entirely and write a fully
// manual agenda item. Not legal advice; wording should be reviewed
// per the company's actual Articles of Association before adoption.
export interface BoardAgendaTemplate {
  key: string
  category: string
  title: string
  text: string
}

const TEMPLATES: BoardAgendaTemplate[] = [
  {
    key: 'confirm_minutes',
    category: 'Procedural',
    title: 'Confirmation of previous minutes',
    text: 'RESOLVED THAT the minutes of the previous meeting of the Board of Directors, having been circulated, be and are hereby confirmed.'
  },
  {
    key: 'approve_financials',
    category: 'Procedural',
    title: 'Approval of financial statements',
    text: 'RESOLVED THAT the audited financial statements of the Company for the year ended [date] be and are hereby approved and adopted.'
  },
  {
    key: 'appoint_auditor',
    category: 'Procedural',
    title: 'Appointment of auditor',
    text: 'RESOLVED THAT M/s. [Audit Firm], Chartered Accountants, be and are hereby appointed as the statutory auditor of the Company for the ensuing year, subject to their consent and eligibility under Section 210 of the Companies Act, 1994.'
  },
  {
    key: 'declare_dividend',
    category: 'Finance',
    title: 'Declaration of dividend',
    text: 'RESOLVED THAT a dividend of [rate]% be and is hereby declared on the paid-up share capital of the Company for the year ended [date], subject to deduction of tax at source as applicable.'
  },
  {
    key: 'share_capital_increase',
    category: 'Finance',
    title: 'Increase of authorized / paid-up share capital',
    text: 'RESOLVED THAT the [authorized/paid-up] share capital of the Company be increased from Tk. [amount] to Tk. [amount], subject to compliance with the Companies Act, 1994 and filing of the requisite RJSC returns.'
  },
  {
    key: 'share_allotment',
    category: 'Finance',
    title: 'Allotment of shares',
    text: 'RESOLVED THAT [number] ordinary shares of Tk. [face value] each be and are hereby allotted to [allottee(s)], and that the Company Secretary be authorized to file Form III (Return of Allotment) with the RJSC.'
  },
  {
    key: 'director_appointment',
    category: 'Governance',
    title: 'Appointment of director',
    text: 'RESOLVED THAT Mr./Ms. [name] be and is hereby appointed as a Director of the Company with effect from [date], subject to filing of Form XII with the RJSC.'
  },
  {
    key: 'director_resignation',
    category: 'Governance',
    title: 'Resignation of director',
    text: 'RESOLVED THAT the resignation of Mr./Ms. [name] from the office of Director, effective [date], be and is hereby accepted and noted, and that Form XII be filed with the RJSC accordingly.'
  },
  {
    key: 'registered_office_change',
    category: 'Governance',
    title: 'Change of registered office',
    text: 'RESOLVED THAT the registered office of the Company be shifted from [old address] to [new address] with effect from [date], and that Form 15 be filed with the RJSC within the prescribed time.'
  },
  {
    key: 'related_party_txn',
    category: 'Governance',
    title: 'Approval of related-party transaction',
    text: 'RESOLVED THAT the Board approves the transaction between the Company and [related party], being a related party by virtue of [relationship], on the terms disclosed to the Board.'
  },
  {
    key: 'bank_account_open',
    category: 'Banking',
    title: 'Opening of bank account / authorized signatories',
    text: 'RESOLVED THAT a [current/savings] account be opened with [Bank Name], [Branch] Branch, in the name of the Company, and that Mr./Ms. [name(s)], [designation], be authorized to operate the said account singly/jointly on behalf of the Company.'
  },
  {
    key: 'lc_authorization',
    category: 'Banking',
    title: 'Authorization to open Local LC',
    text: 'RESOLVED THAT the Managing Director / [designation] be and is hereby authorized to apply for, negotiate and open Local Letter(s) of Credit on behalf of the Company with [Bank Name] up to an aggregate limit of Tk. [amount], and to execute all documents necessary in that behalf.'
  },
  {
    key: 'lbpd_authorization',
    category: 'Banking',
    title: 'Authorization to avail LBPD / bank loan facility',
    text: 'RESOLVED THAT the Company be and is hereby authorized to avail Local Bill Purchase and Discounting (LBPD) / loan facilities from [Bank Name] up to Tk. [amount], and that the Managing Director be authorized to execute all facility documents, demand promissory notes and letters of hypothecation/mortgage required by the Bank.'
  },
  {
    key: 'fdr_dps_authorization',
    category: 'Banking',
    title: 'Authorization for FDR / DPS placement',
    text: 'RESOLVED THAT the Company be and is hereby authorized to place Fixed Deposit Receipt(s) / open Deposit Pension Scheme account(s) with [Bank Name] up to an aggregate amount of Tk. [amount], and that the Managing Director be authorized to give instructions in that behalf.'
  },
  {
    key: 'aob',
    category: 'Procedural',
    title: 'Any other business',
    text: 'RESOLVED THAT [matter], as tabled by [name], be and is hereby approved by the Board.'
  }
]

export const useBoardAgendas = () => {
  const all = TEMPLATES
  const grouped = computed(() => {
    const out: Record<string, BoardAgendaTemplate[]> = {}
    for (const t of TEMPLATES) (out[t.category] ??= []).push(t)
    return out
  })
  const byKey = (key: string) => TEMPLATES.find((t) => t.key === key)
  return { all, grouped, byKey }
}
