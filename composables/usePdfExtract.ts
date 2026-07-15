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
  tolerance_pct?: number
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

    const applicant = t.match(/(?::?50:?\s*(?:applicant)?|applicant)\s*[:\-]?\s*([A-Z][A-Za-z0-9 .,&()\-]{4,60})/i)
    if (applicant) out.applicant = applicant[1].trim().replace(/\s{2,}/g, ' ')

    return out
  }

  const extractLc = async (file: File): Promise<LcExtract> => {
    const text = await extractText(file)
    const fields = parseLcFields(text)
    fields.raw_text = text.slice(0, 4000)
    return fields
  }

  return { extractLc }
}
