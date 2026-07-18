// Default subject/body text per forwarding-letter topic — a starting
// point the user edits freely, same "choosable or manual" pattern as the
// bank request and board agenda template libraries.
export interface ForwardingTopic {
  value: string
  label: string
  subject: string
  body: string
}

export const FORWARDING_TOPICS: ForwardingTopic[] = [
  {
    value: 'lc_docs_to_bank', label: 'LC documents to negotiating bank',
    subject: 'Forwarding of Documents under Local Letter of Credit',
    body: 'We forward herewith the full set of documents drawn under the captioned Letter of Credit for your negotiation. Kindly examine the same and arrange payment/acceptance as per the terms of the credit, crediting the proceeds to our account maintained with your branch.'
  },
  {
    value: 'boe_for_acceptance', label: 'Bill of Exchange for acceptance',
    subject: 'Forwarding of Bill of Exchange for Acceptance',
    body: 'We enclose herewith our Bill of Exchange drawn under the captioned Letter of Credit for your acceptance. Kindly accept the same and return one copy to us for our records, advising the maturity date.'
  },
  {
    value: 'collection_docs', label: 'Shipping documents for collection',
    subject: 'Forwarding of Shipping Documents for Collection',
    body: 'We enclose herewith the shipping documents referenced below for collection. Please arrange to present the same to the drawee and advise us of realization in due course.'
  },
  {
    value: 'amendment_support_docs', label: 'Supporting documents for LC amendment',
    subject: 'Forwarding of Supporting Documents for Letter of Credit Amendment',
    body: 'With reference to our request for amendment of the captioned Letter of Credit, we forward herewith the supporting documents required. Kindly process the amendment and advise us upon completion.'
  },
  {
    value: 'nonnegotiable_to_buyer', label: 'Non-negotiable documents to buyer',
    subject: 'Forwarding of Non-Negotiable Copy of Shipping Documents',
    body: 'In accordance with the terms of the Letter of Credit, we forward herewith one complete set of non-negotiable copies of the shipping documents directly to you for your record and onward customs clearance arrangements.'
  },
  {
    value: 'samples_to_buyer', label: 'Samples to buyer',
    subject: 'Forwarding of Approval / Reference Samples',
    body: 'We forward herewith the samples referenced below for your review and approval. Kindly confirm receipt and advise us of your comments at your earliest convenience.'
  },
  {
    value: 'import_docs_to_agent', label: 'Import documents to C&F/clearing agent',
    subject: 'Forwarding of Import Documents for Customs Clearance',
    body: 'We forward herewith the import documents received under the captioned Letter of Credit for onward customs clearance of the shipment. Kindly proceed with the Bill of Entry and clearance formalities and keep us informed of progress.'
  },
  {
    value: 'insurance_cover_docs', label: 'Documents to insurance company',
    subject: 'Forwarding of Documents for Insurance Cover',
    body: 'We forward herewith the documents required for arranging insurance cover for the shipment referenced below. Kindly issue the cover note/policy at your earliest convenience and forward the same to us.'
  },
  {
    value: 'chamber_coo_docs', label: 'Documents to Chamber of Commerce (Certificate of Origin)',
    subject: 'Forwarding of Documents for Certificate of Origin',
    body: 'We forward herewith the invoice, packing list and supporting documents for the shipment referenced below, and request you to kindly issue the Certificate of Origin at your earliest convenience.'
  },
  {
    value: 'govt_office_docs', label: 'Documents to government office / regulatory authority',
    subject: 'Forwarding of Documents for Necessary Action',
    body: 'We forward herewith the enclosed documents for your kind information and necessary action. Should you require any further information or clarification, please do not hesitate to contact us.'
  },
  {
    value: 'general', label: 'General forwarding',
    subject: 'Forwarding of Documents',
    body: 'We forward herewith the enclosed documents for your kind attention and necessary action.'
  },
  {
    value: 'manual', label: 'Manual / other',
    subject: '', body: ''
  }
]

export const useForwardingTopics = () => {
  const byValue = (v: string) => FORWARDING_TOPICS.find((t) => t.value === v)
  return { all: FORWARDING_TOPICS, byValue }
}
