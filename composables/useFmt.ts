// Number formatting for the whole app. en-IN grouping = lakh/crore
// style used in Bangladesh (12,34,567.89).
export const useFmt = () => {
  const num = (n: any, dp = 2) =>
    Number(n || 0).toLocaleString('en-IN', { maximumFractionDigits: dp })
  const money = (n: any) => '৳' + num(n, 2)
  return { num, money }
}
