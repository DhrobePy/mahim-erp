// Client-side PDF text extraction + best-effort LC field parsing.
// Handles both bank PDFs that follow SWIFT MT700 field tags (20, 31D,
// 32B, 50, 42C) and free-form advice letters. Extraction is a draft —
// the user always reviews before anything is saved.
export interface LcExtract {
  lc_no?: string
  amount?: number
  currency?: string
  expiry_date?: string
  usance_days?: number
  applicant?: string
  beneficiary?: string
  tolerance_pct?: number
  incoterm?: string
  port_of_loading?: string
  port_of_discharge?: string
  latest_shipment_date?: string
  presentation_period_days?: number
  available_with_by?: string
  lc_role?: 'export_local' | 'export_direct' | 'import'
  raw_text?: string
}

export const usePdfExtract = () => {
  const extractText = async (file: File): Promise<string> => {
    const pdfjs: any = await import('pdfjs-dist')
    const worker = await import('pdfjs-dist/build/pdf.worker.min.mjs?url')
    pdfjs.GlobalWorkerOptions.workerSrc = worker.default
    const buf = await file.arrayBuffer()
    const doc = await pdfjs.getDocument({ data: buf }).promise
    let text = ''
    const pages = Math.min(doc.numPages, 5)
    for (let i = 1; i <= pages; i++) {
      const page = await doc.getPage(i)
      const content = await page.getTextContent()
      text += content.items.map((it: any) => it.str).join(' ') + '\n'
    }
    return text
  }

  const toIsoDate = (s: string): string | undefined => {
    // SWIFT dates are YYMMDD; also accept dd/mm/yyyy and yyyy-mm-dd
    if (/^\d{6}$/.test(s)) {
      const yy = Number(s.slice(0, 2))
      return `${yy > 50 ? 1900 + yy : 2000 + yy}-${s.slice(2, 4)}-${s.slice(4, 6)}`
    }
    const dmy = s.match(/^(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})$/)
    if (dmy) return `${dmy[3]}-${dmy[2].padStart(2, '0')}-${dmy[1].padStart(2, '0')}`
    const iso = s.match(/^(\d{4})-(\d{2})-(\d{2})$/)
    if (iso) return s
    return undefined
  }

  const parseLcFields = (text: string): LcExtract => {
    const t = text.replace(/\s+/g, ' ')
    const out: LcExtract = {}

    const lcNo = t.match(/(?::?20:?\s*(?:documentary credit number)?|l\/?c\s*(?:no|number)\.?|credit\s*(?:no|number)\.?)\s*[:\-]?\s*([A-Z0-9][A-Z0-9\/\-]{5,24})/i)
    if (lcNo) out.lc_no = lcNo[1].replace(/[.,;]$/, '')

    const amt = t.match(/(?::?32B:?|credit amount|amount)\s*[:\-]?\s*(BDT|USD|EUR)?\s*([\d,]+(?:\.\d{1,2})?)/i)
    if (amt) {
      out.currency = amt[1]?.toUpperCase()
      const v = Number(amt[2].replace(/,/g, ''))
      if (!Number.isNaN(v) && v > 0) out.amount = v
    }

    const exp = t.match(/(?::?31D:?|date and place of expiry|expiry(?:\s*date)?)\s*[:\-]?\s*(\d{6}|\d{1,2}[\/-]\d{1,2}[\/-]\d{4}|\d{4}-\d{2}-\d{2})/i)
    if (exp) out.expiry_date = toIsoDate(exp[1])

    const usance = t.match(/(\d{2,3})\s*days(?:\s*(?:from|after|sight|usance))?/i)
    if (usance) out.usance_days = Number(usance[1])

    const tol = t.match(/(?:tolerance|39A)[:\s]*(?:\+\/?-?\s*)?(\d{1,2})\s*(?:%|percent)/i)
    if (tol) out.tolerance_pct = Number(tol[1])

    const applicant = t.match(/:50:\s*(?:applicant)?\s*([A-Z][A-Za-z0-9 .,&()\-]{4,80}?)(?=\s*:5[09]:|\s*:32B:)/i)
      ?? t.match(/applicant\s*[:\-]?\s*([A-Z][A-Za-z0-9 .,&()\-]{4,60})/i)
    if (applicant) out.applicant = applicant[1].trim().replace(/\s{2,}/g, ' ')

    const beneficiary = t.match(/:59:\s*(?:beneficiary)?\s*([A-Z][A-Za-z0-9 .,&()\-]{4,80}?)(?=\s*:32B:|\s*:41[AD]:)/i)
      ?? t.match(/beneficiary\s*[:\-]?\s*([A-Z][A-Za-z0-9 .,&()\-]{4,60})/i)
    if (beneficiary) out.beneficiary = beneficiary[1].trim().replace(/\s{2,}/g, ' ')

    const loadPort = t.match(/(?:44E:?\s*(?:port of loading\/airport of departure)?|port of loading)\s*[:\-]?\s*([A-Za-z][A-Za-z0-9 ,.\-]{2,50}?)(?=\s*:?44F:|\s*port of discharge)/i)
    if (loadPort) out.port_of_loading = loadPort[1].trim().replace(/\s{2,}/g, ' ')

    const dischargePort = t.match(/(?:44F:?\s*(?:port of discharge\/airport of destination)?|port of discharge)\s*[:\-]?\s*([A-Za-z][A-Za-z0-9 ,.\-]{2,50}?)(?=\s*:?44C:|\s*latest date of shipment)/i)
    if (dischargePort) out.port_of_discharge = dischargePort[1].trim().replace(/\s{2,}/g, ' ')

    const shipDate = t.match(/(?:44C:?\s*(?:latest date of shipment)?|latest date of shipment)\s*[:\-]?\s*(\d{6}|\d{1,2}[\/-]\d{1,2}[\/-]\d{4}|\d{4}-\d{2}-\d{2})/i)
    if (shipDate) out.latest_shipment_date = toIsoDate(shipDate[1])

    const incoterm = t.match(/\b(EXW|FCA|FAS|FOB|CFR|CIF|CPT|CIP|DAP|DPU|DDP)\b\s+[A-Za-z][A-Za-z0-9 ,.\-]{2,40}/)
    if (incoterm) out.incoterm = incoterm[1].toUpperCase()

    const presentation = t.match(/period for presentation[^\d]{0,20}(\d{1,3})\s*\/?\s*days/i) ?? t.match(/(\d{1,3})\s*\/\s*days from/i)
    if (presentation) out.presentation_period_days = Number(presentation[1])

    const availWithBy = t.match(/(?:41[AD]:?\s*(?:available with\s*\.\.\.\s*by\s*\.\.\.)?)\s*([A-Za-z][A-Za-z0-9 ,.\-]{4,60}?)(?=\s*:4[23][ACP]:)/i)
    if (availWithBy) out.available_with_by = availWithBy[1].trim().replace(/\s{2,}/g, ' ')

    return out
  }

  // Best-effort direction detection: compare the extracted applicant/
  // beneficiary names against the user's own company name. Falls back to
  // 'export_local' (the original/majority flow) when neither side matches
  // or shipment fields are absent — the user always reviews before saving.
  const inferRole = (f: LcExtract, ownCompanyName?: string): 'export_local' | 'export_direct' | 'import' => {
    const norm = (s?: string) => (s ?? '').toLowerCase().replace(/[^a-z0-9]/g, '')
    const own = norm(ownCompanyName)
    if (own) {
      if (norm(f.applicant).includes(own) || own.includes(norm(f.applicant)) && f.applicant) {
        return 'import'
      }
      if (norm(f.beneficiary).includes(own) || (own && own.includes(norm(f.beneficiary)) && f.beneficiary)) {
        return (f.port_of_loading || f.port_of_discharge) ? 'export_direct' : 'export_local'
      }
    }
    return 'export_local'
  }

  const extractLc = async (file: File, ownCompanyName?: string): Promise<LcExtract> => {
    const text = await extractText(file)
    const fields = parseLcFields(text)
    fields.lc_role = inferRole(fields, ownCompanyName)
    fields.raw_text = text.slice(0, 4000)
    return fields
  }

  return { extractLc }
}
