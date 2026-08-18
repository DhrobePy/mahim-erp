export const useLineReconcile = () => {
  const client = useSupabaseClient()

  const replaceLines = async (table: string, parentCol: string, parentId: string, rows: any[]) => {
    const del = await client.from(table).delete().eq(parentCol, parentId)
    if (del.error) throw del.error
    if (rows.length) {
      const ins = await client.from(table).insert(rows)
      if (ins.error) throw ins.error
    }
  }

  return { replaceLines }
}
