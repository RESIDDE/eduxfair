# Lekkside — Super Admin

The platform's administration console, and nothing else. One audience: Lekkside
staff with `profiles.role = 'admin'`.

- **Overview** — the four queues that are nobody else's job
- **Verification queue** — one inbox for every kind of badge
- **Reports** — moderation, child-safety first
- **People** — every account, role changes, restrictions
- **Institutions** — verification state, tiers and plans
- **Live Spaces** — oversight of every session, and the power to end one
- **Fairs** — exhibitors and booth scanning
- **Analytics** — demand by destination and origin

Anyone signing in who is not an admin is told so and offered a sign-out. There
is no sign-up: `handle_new_user()` clamps the role a signup can request, so an
account created here could never reach this console. Admins are made by admins,
from the People page.

## Students and institutions are not here

Both live in the Flutter app (`student_app/`) — students in the tab shell,
institution staff in the `/org` shell.

`src/routes/institution/` and `src/components/live/` are still on disk but are
**not routed**. They are kept rather than deleted because six of those pages
have no Flutter equivalent yet — Matched students, Appointments, Programs,
Team, Fairs and Settings are all still `OrgComingSoonScreen` stubs over there,
and `programs` is what the matching engine reads. Re-enabling them is restoring
the imports and the `isInstitution` block in `src/App.jsx`; deleting the files
would not be.

Unrouting the call room has one happy side effect: `livekit-client`, ~850 KB of
WebRTC machinery, no longer reaches this bundle at all.

Access is enforced by Postgres row-level security, not by which routes render —
a non-admin who somehow reached `/admin` would see empty tables, and
`admin_people` would return nothing at all.

## Running it

```bash
cp .env.example .env.local   # fill in VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
npm install
npm run dev                  # http://localhost:5174
npm run build
npm run lint
```

## Where things are

| Path | What it is |
|---|---|
| `src/components/ui/` | Shared kit, copied from `consult-app/admin_dashboard` and retuned |
| `src/components/VerifiedBadge.jsx` | Verification badges that explain what they attest to |
| `src/lib/supabase.js` | Client plus Postgres-error translation |
| `src/lib/vocab.js` | Labels for the Postgres enums, and what each badge claims |
| `src/lib/status.js` | Stage/status labels and badge tones |
| `src/lib/hooks.js` | `useQuery`, and the field-of-study vocabulary loader |
| `src/context/AuthContext.jsx` | Session, profile and institution membership |

## Two things to know before changing data code

**Field of study is a controlled vocabulary.** It is a foreign key to
`fields_of_study`, and matching compares a student's `target_fields` against
`programs.field_of_study`. A hand-typed subject makes a program unmatchable and
nothing visibly breaks — so always load the table (`useFieldsOfStudy`) rather
than hardcoding options.

**Students are pseudonymous until they share.** `matched_student_cards` exposes
country, level, field and bands, never a name or a document. The `student_id` is
a handle for shortlisting and inviting. Identity arrives only via a
`passport_shares` row, which is the student's decision.
