import { useTransition, TransitionPresets } from '@vueuse/core'

// House default for animated stat values: fast enough to never feel
// sluggish on repeat glances, eased so it settles rather than snapping.
// Takes a getter (not a ref) — more reliably tracked by useTransition's
// internal watcher than a toRef() off a reactive object.
export const useAnimatedNumber = (source: () => number, durationMs = 600) =>
  useTransition(source, { duration: durationMs, transition: TransitionPresets.easeOutExpo })
