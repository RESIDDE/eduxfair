# Dev server — a local stand-in for Supabase

Run both apps with nothing to sign up for. No Docker, no cloud project, no keys
to obtain.

```bash
cd devserver
npm install
npm start
```

It prints the two env blocks to paste into `student_app/.env` and
`web/.env.local`, and the demo accounts. Then:

```bash
cd web && npm run dev                      # http://localhost:5174
cd student_app && flutter run -d chrome     # or -d ios
```

Demo accounts, all with the password **`Lekkside123!`**:

| Role | Email | What they see |
|---|---|---|
| Student | `chidi.okeke@example.com` | A complete passport, 1 invitation, 1 application mid-pipeline, a Fair Passport |
| Institution | `admissions@maplecrest.ca` | Enterprise plan, 3 programs, matched students, a fair booth |
| Institution | `admissions@northgate.ac.uk` | Professional plan, 3 programs |
| Admin | `admin@lekkside.com` | Verification queue, all institutions, fairs, analytics |

`npm run empty` starts with no demo data, so you can register from scratch.

## What makes this worth having

It runs **the project's real migrations** on PGlite — Postgres 17 compiled to
WebAssembly. So row-level security, the guard triggers, the matching engine and
the consent gate are all the production ones. A bug you hit here is a real bug,
and three were found this way:

- `numeric` columns arrive from Postgres as strings; the Dart models cast them
  to `num`, which throws. PostgREST serialises them as JSON numbers, so the
  server does too.
- an array of a user-defined enum (`study_level[]`) has no OID PGlite knows, so
  it came through as the literal `{undergraduate}` and the passport failed to
  decode.
- `appointments`, `applications` and `booth_visits` each reference `profiles`
  twice, so the console's embeds were ambiguous — PostgREST refuses those, and
  they needed explicit foreign-key hints. **That one would have failed against
  hosted Supabase too.**

## Verifying it

```bash
npm run verify           # both of the below
npm run smoke            # every request shape the apps make
npm run verify:console   # the console's queries, read out of web/src
```

`verify:console` extracts the select strings from `web/src` rather than
duplicating them, so the two cannot drift apart.

From the Flutter side, the same ground is covered through the real providers:

```bash
cd ../student_app
flutter test test/devserver_integration_test.dart
```

That suite skips itself with a message when the dev server is not running, so
`flutter test` stays green either way.

## How it works

| File | What it does |
|---|---|
| `db.mjs` | PGlite + the real migrations; `asRole()` runs each request as the signed-in user with RLS on |
| `auth.mjs` | GoTrue subset. Real HS256 JWTs — the claims are what RLS reads |
| `postgrest.mjs` | PostgREST subset: embeds, filters, order, paging, counts, writes, RPC |
| `storage.mjs` | Upload, signed URLs, public buckets, delete |
| `realtime.mjs` | Phoenix channels, so live messages and notifications arrive |
| `coerce.mjs` | Type fidelity with real PostgREST (the numeric and enum-array cases above) |
| `introspect.mjs` | Foreign keys and column types, read from the catalog |
| `seed.mjs` | Demo data, including a cohort large enough to clear the k-anonymity floor |
| `shim_extra.sql` | Passwords and object bytes, on top of `supabase/tests/00_supabase_shim.sql` |

Authorization is genuinely enforced: each request runs inside a transaction
with `set local role authenticated` and the verified claims in
`request.jwt.claims`, which is exactly how hosted Supabase does it. The smoke
test confirms a student cannot read another student's passport and cannot
promote themselves to admin — through the wire, not just in SQL.

## Where it differs from the real thing

Worth knowing before you trust it for something it cannot tell you:

- **Realtime does not re-check RLS per subscriber.** Every write passes through
  this process, so it simply announces what it inserted, filtered by the
  subscription's own `column=eq.value`. Hosted Realtime applies RLS to each
  subscriber. Both apps only ever subscribe scoped to their own conversation or
  profile, so the behaviour matches — but it is not the same mechanism.
- **No email.** Password reset, OTP and `verify-institution-domain` accept the
  request and log that nothing was sent. To verify an institution, approve it in
  the admin console's queue instead.
- **PGlite is a single connection**, so requests are serialised. Fine for
  development; it tells you nothing about concurrency.
- **Data is in memory.** Restarting resets everything to the seed.
- **One schema cache, built at boot.** Changing a migration needs a restart.
- Unimplemented PostgREST features, because neither app uses them: `or=`,
  full-text search, ordering within an embed, range types.
- **No media ever flows.** `livekit-token` runs its grant function for real —
  the authorization, the consent write and the audit row are SQL, and this
  server runs the real schema — but it signs a token only when `LIVEKIT_URL`,
  `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` are in its environment. Without
  them it returns the grant plus a sentence saying what is missing, because
  seeing the decision the schema reached is most of the point of running this
  locally. `livekit-room` behaves the same way and reports `livekit: false`.
- **A change made inside an RPC is not broadcast.** RPC calls go through
  `buildRpcQuery`, so this server never learns which rows they touched —
  `join_space` and `space_moderate` therefore produce no `postgres_changes`
  event. That is why a waiting participant polls `livekit-token` every three
  seconds instead of subscribing: one code path that behaves identically here
  and in production beats one that works only against hosted Supabase.

## Android

The emulator cannot reach `localhost`. Use `http://10.0.2.2:54321` in
`student_app/.env` for Android, or run the server on your LAN address.
