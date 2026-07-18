// Standard clause library for Bangladeshi LC documentation — originally
// written for back-to-back Local LC / deemed export trade, extended to
// cover genuine foreign export (direct shipment, real export VAT) and
// import (Mahim as applicant) scenarios. Not legal advice; the user
// selects what applies to each contract.
export type ClauseDoc = 'boe' | 'ci' | 'pl' | 'challan' | 'quotation' | 'pi' | 'contract'

export interface LcClause {
  key: string
  category: string
  appliesTo: ClauseDoc[]
  text: string
  defaultOn: boolean
}

const CLAUSES: LcClause[] = [
  {
    key: 'ucp600',
    category: 'General / UCP',
    appliesTo: ['boe', 'ci'],
    text: 'Drawn under and negotiable subject to Uniform Customs and Practice for Documentary Credits, ICC Publication No. 600 (UCP 600).',
    defaultOn: true
  },
  {
    key: 'eoe',
    category: 'General / UCP',
    appliesTo: ['ci', 'pl', 'challan'],
    text: 'Errors and Omissions Excepted (E. & O.E.).',
    defaultOn: true
  },
  {
    key: 'jurisdiction',
    category: 'General / UCP',
    appliesTo: ['boe', 'ci', 'challan'],
    text: 'This transaction and all documents relating thereto are subject to the exclusive jurisdiction of the courts at Dhaka, Bangladesh.',
    defaultOn: false
  },
  {
    key: 'origin',
    category: 'Origin & VAT',
    appliesTo: ['ci'],
    text: 'Certified that the goods described herein are of Bangladeshi origin and manufactured by the beneficiary.',
    defaultOn: true
  },
  {
    key: 'deemed_export_vat',
    category: 'Origin & VAT',
    appliesTo: ['ci'],
    text: 'This being a deemed export transaction, VAT has been accounted for at zero rate under Mushak 6.3 issued against the covering Delivery Challan.',
    defaultOn: true
  },
  {
    key: 'import_policy',
    category: 'Origin & VAT',
    appliesTo: ['ci'],
    text: "Certified that the shipment does not include any item restricted under the current Import Policy Order of the People's Republic of Bangladesh.",
    defaultOn: false
  },
  {
    key: 'invoice_true',
    category: 'Invoice certainty',
    appliesTo: ['ci'],
    text: 'We certify that this invoice shows the actual price of the goods described, that no other invoice has been or will be issued differing therefrom, and that all particulars are true and correct.',
    defaultOn: true
  },
  {
    key: 'single_drawing',
    category: 'Invoice certainty',
    appliesTo: ['boe', 'ci'],
    text: 'This Bill of Exchange and the accompanying Commercial Invoice relate solely to the goods described in, and are drawn strictly under, the Letter of Credit quoted above; no other draft has been or will be drawn against the same shipment.',
    defaultOn: false
  },
  {
    key: 'boe_payable',
    category: 'Bank / payment',
    appliesTo: ['boe'],
    text: 'Payable through the accepting/negotiating bank strictly in accordance with the terms of the covering Letter of Credit.',
    defaultOn: true
  },
  {
    key: 'beneficiary_cert',
    category: 'Bank / payment',
    appliesTo: ['boe', 'ci'],
    text: 'Beneficiary’s Certificate: we certify that one complete set of non-negotiable documents has been forwarded directly to the Applicant within seven (7) days of the date of this invoice.',
    defaultOn: false
  },
  {
    key: 'packing_adequate',
    category: 'Packing',
    appliesTo: ['pl'],
    text: 'Packing is roadworthy and adequate for safe inland transit; country of origin is marked on each package.',
    defaultOn: true
  },
  {
    key: 'challan_condition',
    category: 'Delivery challan',
    appliesTo: ['challan'],
    text: 'Goods received in apparent good order and condition, subject to final verification at the buyer’s godown.',
    defaultOn: true
  },
  {
    key: 'challan_shortage',
    category: 'Delivery challan',
    appliesTo: ['challan'],
    text: 'Any shortage, damage or discrepancy must be reported in writing within twenty-four (24) hours of receipt, failing which the delivery shall be deemed accepted in full.',
    defaultOn: true
  },
  {
    key: 'challan_not_tax_invoice',
    category: 'Delivery challan',
    appliesTo: ['challan'],
    text: 'This Delivery Challan is issued for the purpose of transport of goods only and does not constitute a tax invoice.',
    defaultOn: true
  },
  {
    key: 'offer_not_binding',
    category: 'Quotation / PI terms',
    appliesTo: ['quotation', 'pi'],
    text: 'This document is issued for reference only and does not constitute a binding contract until confirmed in writing by the Buyer and/or a Local Letter of Credit is opened in favour of the Beneficiary on these terms.',
    defaultOn: true
  },
  {
    key: 'lc_opening_deadline',
    category: 'Quotation / PI terms',
    appliesTo: ['pi', 'contract'],
    text: 'The covering Letter of Credit must be opened within the validity period stated above, failing which this offer may be treated as lapsed and prices subject to revision.',
    defaultOn: true
  },
  {
    key: 'price_basis',
    category: 'Quotation / PI terms',
    appliesTo: ['quotation', 'pi', 'contract'],
    text: 'Prices quoted are Ex-Factory, Dhaka, exclusive of VAT, and based on the specifications and quantities stated herein; any change shall be subject to re-quotation.',
    defaultOn: true
  },
  {
    key: 'delivery_schedule',
    category: 'Contract terms',
    appliesTo: ['contract'],
    text: "Delivery shall be effected in accordance with the Buyer's shipment plan, subject to production lead time counted from the date of L/C acceptance or advance received, whichever is later.",
    defaultOn: true
  },
  {
    key: 'inspection_rights',
    category: 'Contract terms',
    appliesTo: ['contract'],
    text: "The Buyer or the Buyer's nominated inspection agency may inspect the goods prior to dispatch upon reasonable prior notice to the Seller.",
    defaultOn: true
  },
  {
    key: 'force_majeure',
    category: 'Contract terms',
    appliesTo: ['contract'],
    text: 'Neither party shall be liable for delay or failure to perform any obligation hereunder due to causes beyond its reasonable control, including but not limited to natural disaster, strike, fire, or governmental action.',
    defaultOn: true
  },
  {
    key: 'arbitration',
    category: 'Contract terms',
    appliesTo: ['contract'],
    text: 'Any dispute arising out of or in connection with this contract shall first be settled amicably between the parties; failing which it shall be referred to arbitration in Dhaka, Bangladesh.',
    defaultOn: false
  },

  // ---- Foreign direct export (real shipment, not deemed export) ----
  {
    key: 'actual_export_vat',
    category: 'Foreign Export / Shipment',
    appliesTo: ['ci'],
    text: 'This being an actual export shipment out of Bangladesh, the supply is zero-rated for VAT purposes and no VAT has been charged on this invoice.',
    defaultOn: true
  },
  {
    key: 'incoterm_reference',
    category: 'Foreign Export / Shipment',
    appliesTo: ['ci', 'pl', 'boe'],
    text: 'Shipment is made on the Incoterm(s) 2020 basis stated on the covering Letter of Credit; risk and cost allocation between the parties shall be governed accordingly.',
    defaultOn: true
  },
  {
    key: 'marine_insurance',
    category: 'Foreign Export / Shipment',
    appliesTo: ['ci', 'pl'],
    text: 'Marine/transit insurance has been arranged as per the terms of the covering Letter of Credit and the Incoterm quoted; the relevant cover note/certificate accompanies the shipping documents.',
    defaultOn: false
  },
  {
    key: 'shipping_marks',
    category: 'Foreign Export / Shipment',
    appliesTo: ['pl'],
    text: 'Shipping marks, package numbers and country of origin (Bangladesh) are clearly marked on each package as required under the covering Letter of Credit.',
    defaultOn: true
  },
  {
    key: 'export_origin_bd',
    category: 'Foreign Export / Shipment',
    appliesTo: ['ci'],
    text: 'Certified that the goods described herein are of Bangladeshi origin, manufactured by the Beneficiary, and comply with the export policy of the People’s Republic of Bangladesh currently in force.',
    defaultOn: true
  },

  // ---- Import (Mahim as Applicant) ----
  {
    key: 'import_own_use',
    category: 'Import (Applicant)',
    appliesTo: ['contract'],
    text: 'The imported goods covered under this Letter of Credit are for the Applicant’s own manufacturing/business use and are not intended for resale in an unaltered state, except as otherwise permitted under the relevant Import Policy Order.',
    defaultOn: true
  },
  {
    key: 'import_policy_compliance',
    category: 'Import (Applicant)',
    appliesTo: ['contract'],
    text: 'The Applicant confirms that the goods covered under this Letter of Credit are not restricted or prohibited under the current Import Policy Order of the People’s Republic of Bangladesh, and that all applicable IRC, TIN and BIN details have been correctly furnished to the Issuing Bank.',
    defaultOn: true
  },
  {
    key: 'import_lc_over_po',
    category: 'Import (Applicant)',
    appliesTo: ['contract'],
    text: 'In the event of any conflict between the terms of this document and the terms of the Letter of Credit issued in respect of this purchase, the terms of the Letter of Credit shall prevail.',
    defaultOn: false
  },
  {
    key: 'import_origin_cert',
    category: 'Import (Applicant)',
    appliesTo: ['contract'],
    text: 'The Beneficiary/Supplier shall furnish a Certificate of Origin, issued by the relevant government authority or Chamber of Commerce of the exporting country, certifying the country of origin of the goods, along with the shipping documents.',
    defaultOn: false
  }
]

export const useLcClauses = () => {
  const all = CLAUSES
  const forDoc = (doc: ClauseDoc) => CLAUSES.filter((c) => c.appliesTo.includes(doc))
  const defaultsFor = (doc: ClauseDoc) =>
    forDoc(doc).filter((c) => c.defaultOn).map((c) => c.key)
  const defaultKeys = () => CLAUSES.filter((c) => c.defaultOn).map((c) => c.key)
  const byKey = (key: string) => CLAUSES.find((c) => c.key === key)
  const grouped = computed(() => {
    const out: Record<string, LcClause[]> = {}
    for (const c of CLAUSES) (out[c.category] ??= []).push(c)
    return out
  })
  return { all, forDoc, defaultsFor, defaultKeys, byKey, grouped }
}
