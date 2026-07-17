// Resolves a company's uploaded logo to a public storage URL for use
// in print letterheads. The company-assets bucket is public (logos
// aren't sensitive), so no signed-URL refresh logic is needed.
export const useCompanyLogo = () => {
  const client = useSupabaseClient()
  const logoUrl = (company: any): string | null =>
    company?.logo_path
      ? client.storage.from('company-assets').getPublicUrl(company.logo_path).data.publicUrl
      : null
  return { logoUrl }
}
