// Resolves a company's uploaded authorized-signatory image to a public
// storage URL for print letterheads — mirrors useCompanyLogo.ts exactly,
// same public "company-assets" bucket, just a different column.
export const useCompanySignature = () => {
  const client = useSupabaseClient()
  const signatureUrl = (company: any): string | null =>
    company?.signature_path
      ? client.storage.from('company-assets').getPublicUrl(company.signature_path).data.publicUrl
      : null
  return { signatureUrl }
}
