// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  compatibilityDate: '2025-01-01',
  // SPA mode: the app deploys as static files on cPanel (no Node there);
  // all data flows client → Supabase directly, secured by RLS.
  ssr: false,
  devtools: { enabled: true },

  modules: ['@nuxt/ui', '@nuxtjs/supabase', '@pinia/nuxt'],

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
