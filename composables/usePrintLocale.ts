// Print documents default to English regardless of the app-wide locale
// cookie — bank/customer-facing paperwork should stay in a predictable
// language by default. Each print page gets its own toggle instead.
//
// @nuxtjs/i18n lazy-loads each locale's message bundle only when the
// global locale actually switches to it. Since we never switch the
// global locale here (only this page's own `locale` ref), a locale
// that hasn't been visited yet in this browser session has no messages
// loaded — so we briefly flip the global locale to force-load them,
// then flip it straight back, leaving the app-wide locale untouched.
export const usePrintLocale = () => {
  const locale = ref<'en' | 'bn'>('en')
  const { t: baseT, locale: globalLocale, setLocale } = useI18n()
  const loaded = new Set<string>([globalLocale.value])

  const ensureLoaded = async (target: 'en' | 'bn') => {
    if (loaded.has(target)) return
    const original = globalLocale.value
    await setLocale(target)
    await setLocale(original)
    loaded.add(target)
  }

  const t = (key: string, named?: Record<string, unknown>) =>
    baseT(key, named ?? {}, { locale: locale.value }) as string

  const toggle = async () => {
    const next = locale.value === 'en' ? 'bn' : 'en'
    await ensureLoaded(next)
    locale.value = next
  }

  return { locale, t, toggle }
}
