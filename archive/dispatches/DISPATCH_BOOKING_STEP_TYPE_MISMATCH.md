# DISPATCH: BookingFlow StepIndicator type mismatch

**Date:** 2026-03-15
**Target:** surface-website

---

## Problem

`svelte-check` reports a type error in `BookingFlow.svelte` L55:

```
Type '((target: BookingStep) => void) | undefined' is not assignable to
type '((step: number) => void' | undefined'.
```

`StepIndicator.svelte` declares `onstep?: (step: number) => void` — it's a generic shared component that works with any numeric step. `BookingFlow.svelte` passes `vm.goToStep` which expects `BookingStep` (a narrower union extracted from `BOOKING_STEP` const object). TypeScript correctly rejects this: the component could call `onstep(999)` and the handler expects only valid `BookingStep` values.

## Fix Options

**Option A (minimal):** Cast at the callsite — `onstep={vm.goToStep as (step: number) => void}`. Quick but hides the type mismatch.

**Option B (correct):** Make `StepIndicator` generic over the step type. Add a type parameter or accept `onstep?: (step: number) => void` and have `goToStep` accept `number` with a runtime guard that ignores invalid values. The ViewModel's `goToStep` already has bounds-checking logic, so widening the parameter to `number` and guarding internally is safe.

## Files

- `surface-website/src/routes/(public)/book/_components/BookingFlow.svelte` L55
- `surface-website/src/lib/components/steps/StepIndicator.svelte` L5 (Props definition)
- `surface-website/src/routes/(public)/book/_components/bookingConstants.ts` (BookingStep type)

## Origin

Pre-existing compile error, surfaced during BFF error sanitization session.
