# scripts/

One-off maintenance scripts that need elevated privilege (admin SDK / service
account) and shouldn't ship in the Flutter app.

## Skipped: int → double normalization of monetary fields

The 2026-05-23 audit flagged schema drift on `financials.amount` and
`plans.monthlyValue` / `periodValue` — some docs store integers, others
doubles. The original concern was that a Dart `as int` cast would crash.

After grep-verification of the codebase, **every read path already uses
`(value as num).toDouble()` or `(value ?? 0).toDouble()`**, so there is no
runtime crash risk. The drift is cosmetic only.

A migration script was prototyped but cannot solve the underlying issue
from a JavaScript runtime: Node.js does not distinguish `100` (int) from
`100.0` (double), and the Firestore Admin SDK serializes based on
`Number.isInteger()`. The only ways to actually convert are:

1. **Refactor to use cents as integers everywhere** (Stripe-style). Pure
   integer math, no precision loss, no drift possible. Largest blast
   radius (touches every money calculation in the app).
2. **Migrate from Dart**, where `int` and `double` are distinct types. A
   Dart CLI using `cloud_firestore` could read each doc and write back
   with explicit `double` typing. Lower blast radius but requires a Dart
   runtime with credentials.
3. **Accept the drift**, since reads are defensive.

Decision: option 3 for now. Revisit if/when the web side or a Cloud
Function starts treating these as `int`.
