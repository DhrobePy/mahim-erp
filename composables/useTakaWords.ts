// Amount in words, Bangladesh convention (lakh/crore grouping):
// 1234567.89 → "Taka Twelve Lakh Thirty Four Thousand Five Hundred
// Sixty Seven and Paisa Eighty Nine Only"
const ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
  'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
  'Seventeen', 'Eighteen', 'Nineteen']
const tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety']

const two = (n: number): string =>
  n < 20 ? ones[n] : tens[Math.floor(n / 10)] + (n % 10 ? ' ' + ones[n % 10] : '')

const three = (n: number): string => {
  const h = Math.floor(n / 100)
  const rest = n % 100
  return (h ? ones[h] + ' Hundred' + (rest ? ' ' : '') : '') + (rest ? two(rest) : '')
}

// Bangladesh convention: lakh/crore grouping.
const intWords = (n: number): string => {
  if (n === 0) return 'Zero'
  const crore = Math.floor(n / 1e7)
  const lakh = Math.floor((n % 1e7) / 1e5)
  const thousand = Math.floor((n % 1e5) / 1000)
  const rest = n % 1000
  const parts: string[] = []
  if (crore) parts.push(intWords(crore) + ' Crore')
  if (lakh) parts.push(two(lakh) + ' Lakh')
  if (thousand) parts.push(two(thousand) + ' Thousand')
  if (rest) parts.push(three(rest))
  return parts.join(' ')
}

// International convention: thousand/million/billion grouping, used for
// foreign-currency (USD/EUR) trade documents where lakh/crore wording
// would look wrong to a foreign bank.
const intWordsIntl = (n: number): string => {
  if (n === 0) return 'Zero'
  const billion = Math.floor(n / 1e9)
  const million = Math.floor((n % 1e9) / 1e6)
  const thousand = Math.floor((n % 1e6) / 1000)
  const rest = n % 1000
  const parts: string[] = []
  if (billion) parts.push(intWordsIntl(billion) + ' Billion')
  if (million) parts.push(three(million) + ' Million')
  if (thousand) parts.push(three(thousand) + ' Thousand')
  if (rest) parts.push(three(rest))
  return parts.join(' ')
}

const CURRENCY_WORDS: Record<string, { major: string; minor: string }> = {
  BDT: { major: 'Taka', minor: 'Paisa' },
  USD: { major: 'US Dollar', minor: 'Cent' },
  EUR: { major: 'Euro', minor: 'Cent' },
  GBP: { major: 'Pound Sterling', minor: 'Pence' }
}

export const useTakaWords = () => {
  // Kept for existing BDT-only callers (payroll, tax, HR docs) — unchanged.
  const takaWords = (amount: number | string): string => {
    const n = Math.abs(Number(amount) || 0)
    const taka = Math.floor(n)
    const paisa = Math.round((n - taka) * 100)
    let out = 'Taka ' + intWords(taka)
    if (paisa) out += ' and Paisa ' + two(paisa)
    return out + ' Only'
  }

  // Currency-aware version for trade documents (invoices, quotations)
  // that may be denominated in a foreign LC currency.
  const amountWords = (amount: number | string, currency = 'BDT'): string => {
    const code = (currency || 'BDT').toUpperCase()
    if (code === 'BDT') return takaWords(amount)
    const words = CURRENCY_WORDS[code] ?? { major: code, minor: 'Cent' }
    const n = Math.abs(Number(amount) || 0)
    const major = Math.floor(n)
    const minor = Math.round((n - major) * 100)
    let out = words.major + ' ' + intWordsIntl(major)
    if (minor) out += ' and ' + words.minor + ' ' + two(minor)
    return out + ' Only'
  }

  return { takaWords, amountWords }
}
