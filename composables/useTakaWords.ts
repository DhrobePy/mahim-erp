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

export const useTakaWords = () => {
  const takaWords = (amount: number | string): string => {
    const n = Math.abs(Number(amount) || 0)
    const taka = Math.floor(n)
    const paisa = Math.round((n - taka) * 100)
    let out = 'Taka ' + intWords(taka)
    if (paisa) out += ' and Paisa ' + two(paisa)
    return out + ' Only'
  }
  return { takaWords }
}
