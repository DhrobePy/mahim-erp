// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  compatibilityDate: '2025-01-01',
  // Dev runs with SSR (the nuxi dev server needs it); production builds
  // (`nuxi generate`) ship as a static SPA for cPanel — no Node on the
  // server, all data flows client → Supabase directly, secured by RLS.
  ssr: true,
  $production: {
    ssr: false
  },
  devtools: { enabled: true },

  modules: ['@nuxt/ui', '@nuxtjs/supabase', '@pinia/nuxt', '@nuxtjs/i18n'],

  // English/Bengali switcher. no_prefix keeps URLs unchanged (/items stays
  // /items in either language) — this is an internal app, not something
  // that needs per-locale SEO routes. Preference persists in a cookie.
  i18n: {
    locales: [
      {
        code: 'en',
        name: 'English',
        files: [
          'en/common.json', 'en/nav.json', 'en/accounting.json', 'en/banking.json', 'en/boms.json',
          'en/ceo.json', 'en/challans.json', 'en/dashboard.json', 'en/hr.json', 'en/invoices.json',
          'en/items.json', 'en/lcs.json', 'en/parties.json', 'en/procurement.json', 'en/production.json',
          'en/quotations.json', 'en/sales.json', 'en/stock.json', 'en/print.json', 'en/admin.json',
          'en/system.json', 'en/print_trade.json', 'en/print_hr.json', 'en/print_gov.json', 'en/lc_tracker.json'
        ]
      },
      {
        code: 'bn',
        name: 'বাংলা',
        files: [
          'bn/common.json', 'bn/nav.json', 'bn/accounting.json', 'bn/banking.json', 'bn/boms.json',
          'bn/ceo.json', 'bn/challans.json', 'bn/dashboard.json', 'bn/hr.json', 'bn/invoices.json',
          'bn/items.json', 'bn/lcs.json', 'bn/parties.json', 'bn/procurement.json', 'bn/production.json',
          'bn/quotations.json', 'bn/sales.json', 'bn/stock.json', 'bn/print.json', 'bn/admin.json',
          'bn/system.json', 'bn/print_trade.json', 'bn/print_hr.json', 'bn/print_gov.json', 'bn/lc_tracker.json'
        ]
      }
    ],
    langDir: 'locales',
    defaultLocale: 'en',
    strategy: 'no_prefix',
    // Remember an explicit switch-language click via cookie, but don't
    // auto-redirect based on the browser's own Accept-Language header —
    // staff share devices and the default should stay predictable.
    detectBrowserLanguage: {
      useCookie: true,
      cookieKey: 'erp_locale',
      redirectOn: 'no prefix',
      alwaysRedirect: false
    }
  },

  // @nuxtjs/supabase: guards every route by default and redirects
  // unauthenticated users to /login. Public routes are excluded below.
  supabase: {
    redirectOptions: {
      login: '/login',
      callback: '/confirm',
      exclude: ['/login', '/confirm']
    }
  },

  ui: {
    global: true
  },

  // Dark-first industrial theme
  colorMode: {
    preference: 'dark',
    fallback: 'dark'
  },

  css: ['~/assets/css/main.css'],

  app: {
    head: {
      title: 'Mahim Packaging ERP',
      meta: [{ name: 'viewport', content: 'width=device-width, initial-scale=1' }],
      link: [
        { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
        { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
        {
          rel: 'stylesheet',
          href: 'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600;700&display=swap'
        }
      ]
    }
  }
})
