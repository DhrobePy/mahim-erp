---
target: dashboard (pages/index.vue)
total_score: 21
max_score: 40
na_heuristics: 
p0_count: 1
p1_count: 2
timestamp: 2026-08-05T05-55-22Z
slug: pages-index-vue
---
Method: dual-agent (A: a0f85f5f8a34fc3e5 · B: a278f8fd60dd875a8), plus a manual bug-repro pass by the orchestrator.

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 2/4 | Stock-movements panel has a loading guard, stat cards and journals panel don't — they render stale/false-empty content while fetching |
| 2 | Match System / Real World | 3/4 | Correct BD trade-finance vocabulary (LBPD/PAD, AR+LC+GDNI), zero glossary for non-finance staff |
| 3 | User Control and Freedom | 2/4 | Hardcoded limits (9/6 rows), no "view all," no filters, no manual refresh |
| 4 | Consistency and Standards | 4/4 | Consistent reuse of StatCard/PageHeader/UCard and .num/.microlabel tokens |
| 5 | Error Prevention | 1/4 | Zero try/catch around the data-fetch; one failing/hanging query blanks the whole page |
| 6 | Recognition Rather Than Recall | 3/4 | Self-labeled cards, no memory burden |
| 7 | Flexibility and Efficiency | 1/4 | No stat card is a link, no keyboard shortcuts, no drill-down anywhere |
| 8 | Aesthetic and Minimalist Design | 4/4 | Dense but clean, consistent dark industrial styling |
| 9 | Error Recovery | 0/4 | No error state exists anywhere in the fetch path |
| 10 | Help and Documentation | 1/4 | No tooltips for jargon like "LBPD / PAD exposure" |
| **Total** | | **21/40** | **Acceptable — significant improvements needed** |

## Design Specificity Verdict

**LLM assessment**: The data model is genuinely domain-specific (BD chart-of-accounts aggregation for bank/receivables/LBPD-PAD exposure) — this could not be dropped into a generic SaaS template unchanged. But the layout is the exact generic admin-dashboard skeleton: a flat stat-card grid plus two read-only lists, no drill-downs, no domain visualization (no LC-maturity timeline despite that data existing via `v_lc_alerts`). Specificity lives in the copy, not the composition.

**Deterministic scan**: `detect.mjs --json pages/index.vue` → exit 0, zero findings. Clean on the mechanical anti-slop checks.

**Manual bug repro** (orchestrator, not part of either assessment): confirmed reproducible in a fresh browser session — the "Stock Movements" panel is stuck on "Loading…" permanently. Traced it past the database (raw SQL fine), past RLS (raw REST calls with the anon key succeed in <50ms for all 7 queries `load()` fires), narrowing it to something in how `useSupabaseClient()`'s wrapped client handles this specific query set client-side — the three `{ count: 'exact', head: true }` HEAD-mode count queries are the likely culprit. Root cause aside, the fix is the same either way: `load()` has zero error handling, so whatever the cause, one query never resolving takes the whole dashboard down silently and permanently.

## Overall Impression

The visual system is solid — dense, consistent, on-brand. The real problem is structural: this page has no failure mode. Every number and panel assumes every query always succeeds instantly, and there's a live, reproducible bug proving that assumption false today, in front of you, on every fresh page load.

## What's Working

- Real chart-of-accounts-aware aggregation (bank = 1100+1150, receivables = 1200/1210/1220, LBPD/PAD sign-flipped) — reflects actual BD trade-finance instruments.
- Stock-movement rows handle edge cases well: truncated long names, `'—'` fallback, sign shown via both `+`/`-` prefix *and* color (not color alone).
- Consistent component/token reuse keeps this visually integrated with the rest of the app.

## Priority Issues

**[P0] No error handling in `load()`, and it's live-broken right now** — What: the whole fetch is one unguarded `Promise.all`, no try/catch, no error ref. Confirmed today: the Stock Movements panel is permanently stuck on "Loading…" in the actual running app. Why it matters: a page showing live bank/receivables/LC exposure that can silently freeze with zero user-facing signal is a trust failure, not a cosmetic bug. Fix: `Promise.allSettled`, try/catch, a visible error/retry state. — Suggested command: `/impeccable harden`

**[P1] False empty-state flash on "Latest journals"** — the journals list lacks the loading guard the stock-movements panel has, so it shows "Nothing posted yet." before (or, per the live bug, forever instead of) the fetch resolves. Fix: mirror the existing `v-if="loading"` pattern. — Suggested command: `/impeccable polish`

**[P1] Unlocalized DB enum leaking into UI** — `{{ m.movement_type }}` renders raw values like `grn_in` straight from the database, bypassing `t()`, even though `pages/stock/index.vue` already defines the exact label map needed (`t('stock.adj_types.*')`) — it's just not reused here. Fix: extract to a shared composable. — Suggested command: `/impeccable clarify`

**[P2] No visual priority among 8 stat cards, none are clickable** — all render at identical weight with no drill-down link to the module behind each number. Fix: link each card, give flagged (red/amber) cards more visual weight. — Suggested command: `/impeccable layout`

**[P3] No staleness indicator or refresh control** — data fetches once on mount with no polling (unlike `NotificationBell.vue`, which polls every 60s) and no manual refresh. — Suggested command: `/impeccable delight`

## Persona Red Flags

**Alex (power user, checks this dashboard multiple times a day)**: Hits the false "Nothing posted yet." on every visit. None of the 8 stat cards are clickable — sees "Low stock: 12" in red with no path to act. Hard-capped lists (9/6 rows) with no "view all." No way to tell if numbers are from this second or this morning.

**Sam (screen reader / keyboard-only)**: Zero heading elements below the page title — "Stock movements," "Latest journals," and every stat label render as styled `<p>`, not `<h2>/<h3>`, so heading-navigation finds nothing. Severity (red/amber tones) is color-only with no icon or `aria-label`. KPI pairs are plain divs in a CSS grid, not `<dl>/<dt>/<dd>`.

## Minor Observations

- Reference numbers (`ref_no`) render at 11px gray — likely audit-trail data staff need to read quickly; borderline size.
- The same un-`t()`-routed hardcoded-string pattern recurs in `layouts/default.vue` (role badge fallback) — not on this page, but the same defect class nearby.
- Zero-state and broken-state are visually indistinguishable: a brand-new company with genuinely ৳0 everywhere looks identical to every query failing.

## Questions to Consider

1. If a query silently errors, the page currently renders exactly like "everything is calm and zero" — acceptable for a page showing live bank/LC exposure?
2. Every one of these 8 numbers summarizes a table the user almost certainly wants to open next — why is none of them a link?
3. For a page checked multiple times a day, what's the plan for showing *what changed since last visit*, given the current design only ever shows an absolute snapshot?
