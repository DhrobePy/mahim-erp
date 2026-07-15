// Dark industrial theme: amber accent on near-black zinc surfaces,
// dense tables, hairline rings instead of shadows.
export default defineAppConfig({
  ui: {
    primary: 'amber',
    gray: 'zinc',
    table: {
      divide: 'divide-y divide-gray-200 dark:divide-zinc-800/80',
      tbody: 'divide-y divide-gray-100 dark:divide-zinc-800/60',
      th: {
        padding: 'px-3 py-2',
        font: 'font-medium uppercase tracking-wider',
        size: 'text-[10.5px]',
        color: 'text-gray-500 dark:text-zinc-500'
      },
      td: {
        padding: 'px-3 py-[7px]',
        size: 'text-[13px]',
        color: 'text-gray-700 dark:text-zinc-300'
      }
    },
    card: {
      background: 'bg-white dark:bg-zinc-900/60',
      ring: 'ring-1 ring-gray-200 dark:ring-zinc-800',
      rounded: 'rounded-md',
      shadow: '',
      divide: 'divide-y divide-gray-200 dark:divide-zinc-800',
      header: { padding: 'px-4 py-2.5' },
      body: { padding: 'px-4 py-3' },
      footer: { padding: 'px-4 py-2.5' }
    },
    slideover: {
      background: 'bg-white dark:bg-zinc-900',
      width: 'w-screen max-w-xl'
    },
    modal: {
      background: 'bg-white dark:bg-zinc-900'
    },
    badge: {
      rounded: 'rounded'
    },
    button: {
      rounded: 'rounded',
      default: { size: 'sm' }
    },
    input: {
      rounded: 'rounded',
      default: { size: 'sm' }
    },
    select: {
      rounded: 'rounded',
      default: { size: 'sm' }
    },
    formGroup: {
      label: { base: 'text-[11px] uppercase tracking-wider font-medium text-gray-500 dark:text-zinc-500' }
    }
  }
})
