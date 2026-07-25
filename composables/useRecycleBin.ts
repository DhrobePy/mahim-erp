// Shared delete action for every list/detail page — routes through the
// generic soft_delete_record() RPC (migration 0022), which reverses any
// GL/stock effects first when the record is a posted document, then
// hides it. Restoring happens from /recycle-bin.
export const useRecycleBin = () => {
  const client = useSupabaseClient()
  const toast = useToast()

  const deleteRecord = async (table: string, id: string, label: string, confirmText?: string): Promise<boolean> => {
    if (!confirm(confirmText ?? `Delete "${label}"? This can be undone from the recycle bin.`)) return false
    const { error } = await client.rpc('soft_delete_record', { p_table: table, p_id: id } as any)
    if (error) {
      toast.add({ title: 'Delete failed', description: error.message, color: 'red' })
      return false
    }
    toast.add({ title: `Deleted "${label}"` })
    return true
  }

  return { deleteRecord }
}
