# Lekkside Connect

A year-round international student recruitment network that begins at the
Lekkside education fair and continues until a student actually connects with an
institution.

A student builds one verified **Education Passport**. Institutions discover and
approach students who already match their programs (**reverse admission**).
Meetings, messaging and the admission pipeline all carry on after the event
ends, and the **Fair Passport** QR ties the physical Lagos fairs back into it.

## Layout

| Path | What it is |
|---|---|
| `supabase/` | 35 migrations, 5 Edge Functions, seed — the source of truth |
| `supabase/tests/` | 280 migration + RLS assertions (runs without Docker) |
| `devserver/` | A local stand-in for Supabase, so both apps run with no cloud project |
| `student_app/` | Flutter — **students and institution staff** → iOS, Android, Web |
| `web/` | React 19 + Vite + Tailwind — **the super admin console, and only that** |

Students and institutions both live in the Flutter app. `web/` serves one
audience — Lekkside staff with `profiles.role = 'admin'` — and anyone else who
signs in there is told so and offered a sign-out. The institution console still
exists under `web/src/routes/institution/` but is not routed; see
[web/README.md](web/README.md) for what has to be ported to Flutter before
those pages can be retired for good.

The student app is light-themed and the console is dark. That is deliberate,
not an oversight: a student fills in forms and reads documents on a phone,
often in daylight, while the console is a dense desktop tool for people who
sit in them all day. Both draw from the same widget vocabulary, so they still
read as one product.

## Running it locally, with no Supabase project

```bash
cd devserver && npm install && npm start
```

It prints the env blocks to paste into `student_app/.env` and `web/.env.local`,
then:

```bash
cd web && npm run dev                    # http://localhost:5174
cd student_app && flutter run -d chrome   # or -d ios
```

Sign in with **`Lekkside123!`** as `chidi.okeke@example.com` (student),
`admissions@maplecrest.ca` (institution) or `admin@lekkside.com` (admin).

This is not a mock. The dev server runs the project's **real migrations** on
Postgres compiled to WebAssembly, so RLS, the guard triggers and the matching
engine are the production ones — see [devserver/README.md](devserver/README.md),
including the handful of ways it differs from hosted Supabase.

## Authorization, in one paragraph

This is a Supabase-first build, which means Postgres row-level security **is**
the authorization layer — there is no server in front of it to catch a mistake.
`supabase/migrations/20251009000009_rls_policies.sql` is therefore the
authorization spec for the whole platform, and
`supabase/tests/rls_test.mjs` is the gate that proves it. Run it before
shipping anything that touches the schema.

A student's identity is gated on exactly one condition: a live row in
`passport_shares`. Applying, requesting a meeting and connecting at a booth all
*write* such a row rather than being special cases in the access rules, so the
student's "who can see me" screen is complete by construction and every grant
is revocable in one place. Institutions discover students through
`matched_student_cards`, which is pseudonymous by design.

## Running the schema tests

No Docker or hosted project needed — the suite runs the real migrations on
Postgres 17 compiled to WASM.

```bash
cd supabase/tests
npm install
npm test              # migrations + 87 RLS assertions
npm run test:schema   # migrations only
```

With the dev server running, three more suites cover the wire itself:

```bash
cd devserver     && npm run verify      # every request shape, and the console's own queries
cd student_app   && flutter test        # domain logic, plus the providers end to end
```

The suite covers cross-tenant denial, the consent gate (grant → read → revoke →
no read), privilege escalation (self-promotion to admin, self-verification,
self-upgrading a subscription tier, a student awarding themselves an offer), the
append-only decision history, the fair-scan authorization path, storage path
prefixes, and the k-anonymity floor on demand statistics in both directions.

## Applying the schema to a project

```bash
npx supabase@2.120.0 link --project-ref YOUR-PROJECT-REF
npx supabase@2.120.0 db push
npx supabase@2.120.0 db reset   # local only: also applies seed.sql
```

Edge Functions:

```bash
npx supabase@2.120.0 functions deploy compute-matches
npx supabase@2.120.0 functions deploy verify-institution-domain
npx supabase@2.120.0 functions deploy send-notification

npx supabase@2.120.0 secrets set RESEND_API_KEY=... APP_URL=...
```

## Running the apps

**Student app** (Flutter 3.47 — this machine has the SDK at `/Users/mac/flutter`,
not on `PATH`):

```bash
export PATH="$PATH:/Users/mac/flutter/bin"
cd student_app
cp .env.example .env        # then fill in SUPABASE_URL and SUPABASE_ANON_KEY
flutter pub get
flutter analyze && flutter test
flutter run -d chrome       # or -d ios / -d android
```

Verified building on **web** and **iOS simulator**. The **Android** build is
untested: there is no Android SDK installed on this machine (`flutter doctor`
reports it missing). Every dependency is cross-platform and the project
scaffolding exists, but that build has not actually been run.

One exception now that the app has a call screen: **video publishing does not
work on the iOS simulator**, so a black self-view there is the simulator rather
than a bug. The call screen needs a physical device. `livekit_client` also
brought in native code for the first time — `minSdk` is pinned to 24 and
`ios/Podfile` now sets `platform :ios, '15.0'`, which it previously left
commented out.

**Consoles:**

```bash
cd web
cp .env.example .env.local  # then fill in VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
npm install
npm run dev                 # http://localhost:5174
```

## Live Spaces and in-app video

Shipped, on LiveKit at `wss://meet.lekksideexpo.com`. It was the additive change
20251009000004 promised it would be: `appointments` gained exactly one column.

Two kinds of room, one mechanism:

- **A Space** — one institution, many students. An admissions hour, a
  scholarship Q&A, a country briefing. Students see it on their Spaces tab and
  drop in.
- **An appointment** — the existing 1:1 meeting, now held here instead of on a
  pasted Meet/Zoom link. `appointments.meeting_mode` keeps an external link
  available for an institution whose process depends on one.

Room names are derived and never stored (`space_<id>`, `appt_<id>`), and the
LiveKit identity is a `space_participants.id` — never a `profiles.id`, not even
in a 1:1 where a share already exists. The private account id does not leave the
server, and a LiveKit identity leaves the server.

**Listening is pseudonymous; participating identifies.** A student who joins to
watch is their handle and nothing else, with a token that can publish nothing.
Raising a hand, unmuting, turning on a camera or writing in the chat goes through
`identify_in_space()`, which writes an ordinary revocable `passport_shares` row —
the same single gate as applying, booking and a booth scan. So the student's
Passport → Sharing screen stays complete without knowing Spaces exist, and one
revocation still covers everything. The consent sheet says so before they tap.

Moderation is SQL first, LiveKit second: `space_moderate()` decides whether the
caller may act and records that they did, in one transaction, and only then does
the Edge Function carry it through. A kick LiveKit performed and the database did
not record is a kick that did not happen. No client token carries `roomAdmin`,
hosts included.

### Messaging

Threads are `conversations` + `messages`, two-party by design (a student and an
institution), with no UPDATE or DELETE policy on `messages` for anyone — a log a
student may later need to point back to is not one an institution can rewrite.

**A message knows what it is.** `messages.kind` is `text | file | image | voice`,
written by the sender and never inferred from the file extension: an `.m4a`
somebody attached deliberately is a file, an `.m4a` the recorder produced is a
voice note, and the storage path cannot tell them apart. `attachment_name` is
stored for the same reason — both clients used to rebuild it by splitting the
path on its first dash, which mangled every filename that already contained one.
Voice notes carry `duration_ms` so a bubble can show its length before any audio
has been fetched.

**Reactions, replies and forwarding.** One reaction per person per message,
from six emoji fixed by a CHECK — the same argument `RoomProtocol` makes for a
live room: an open emoji field is an open text field, and these threads can have
minors in them. A reply's `reply_to_id` is fenced by a trigger to the same
conversation, because the quoted snippet is rendered from the row that id points
at, so an id from elsewhere would be a way to display a message the reader is
not entitled to. Forwarding copies the attachment in storage rather than
referencing it — object paths are keyed on the conversation and the policy
authorizes on that first segment — and `is_forwarded` carries no pointer home,
because naming the source would name a conversation the reader is not on.

Gestures on mobile: swipe right to reply, swipe left to open the actions, hold
for the full sheet. Neither swipe acts on its own — it asks.

**Deleting a message is two different things.** `delete_message(id, 'me')`
writes a row to `message_hides` — a reading preference, the message untouched,
the other side never told, so there is nothing to mark. `delete_message(id,
'everyone')` is the sender's own only; it copies the original into
`message_redactions` and clears the row, and both clients render *"This message
was deleted"*. That tombstone is the point: a gap with no explanation reads as a
bug.

`messages` still has no UPDATE and no DELETE policy for anyone, so that function
is the only path, and the guarantee 20251009000009 wrote down — "a message log
that can be rewritten is useless when a student disputes what an institution
told them" — survives where it matters: `message_redactions` is readable by
admins and by neither party, so the deletion is real to the people in the room
and the record is still there for whoever has to settle an argument about it.

**Pinning and archiving are per person**, on `conversation_participants` rather
than on `conversations`, for the same reason `last_read_at` lives there: an
institution thread can have several officers working it, and one of them
archiving it must not take it off a colleague's list. Pinning un-archives, and
that rule is in `set_conversation_state()` so no client has to remember it.

**Search is `ilike`**, for the reason `search_posts` gives — tsvector needs an
index, a language configuration and a decision about stemming across the
languages these students write in, none of which is worth committing to yet.
`search_conversations()` is deliberately NOT `security definer`: invoker rights
mean `messages_select_party` decides what is searchable, so it cannot become a
way to read a thread the caller is not on. Matching the other party by name is
left to the clients, which already hold that list and can filter it without a
round trip.

### Profiles from a thread

Tapping the other party in a chat opens their profile, X-style: avatar, bio,
follower counts and a timeline of what they have posted. A university handle
used to bounce straight to its prospectus, which meant a university had no
profile at all — the prospectus answers "what can I study here", and nothing
answered "what has this university been saying". `/u/:handle` now renders that
for every kind of account, with a button in the app bar through to the full
university page.

**The link runs one way, deliberately.** A student can open the institution; an
institution cannot open the student. `social_profiles` has no policy letting
staff read a student's row, and `public_profiles` exposes no `profile_id`, so
a thread cannot be joined to a handle. That is the point of the match token: a
share grants the student's PASSPORT identity — a name, an avatar, documents —
and says nothing about their social presence. Linking the two would hand an
institution the public account behind an anonymous thread, which no student
consented to when they shared a passport.

### Bios

A student has two, and they are not the same column. `passports.bio` is passport
data an institution sees only after a share. `social_profiles.bio` is public —
it renders on the handle profile and as the subtitle in follower lists — and
until `set_social_bio()` nothing could write it: `claim_handle()` accepts a bio
but coalesces a null onto the existing value, which is right for a rename and
wrong for an editor, where clearing the field has to mean clearing the bio.

**A host can appoint moderators, and a moderator is not staff.** `moderator` is
its own `space_role`, deliberately not `cohost`: the schema already spells
"staff of the hosting institution" as `role in ('host', 'cohost')`, and two of
those places publish the person's real full name. So an appointed attendee gets
the mute, camera, hand and remove buttons, a microphone and a camera — and stays
`@handle` on their own tile, reads `space_roster` with every `shared_name`
blanked out, gets no screen share, and cannot appoint or act on another
moderator. Appointing one requires the same `identify_in_space()` consent that
giving somebody the floor does, one size up: a moderator can silence the room.
Platform admins hold everything staff hold, through `is_admin()` in
`space_is_staff()`.

**Taking the floor back means it.** Demoting a speaker used to be undone by the
speaker: the app offers any listener the consent sheet, and accepting called
`identify_in_space()`, which promoted them again without knowing a host had
just acted. `space_floor_withheld()` now compares the newest `demoted` event
against the newest `promoted` one, and `identify_in_space()` refuses while a
demotion stands — so the only way back is the host's own "Give them the floor".
A demoted listener cannot raise a hand either, because hand-raise is an
attribute write gated on `can_publish`; returning the floor is the host's call
and nobody else's.

`space_mute_all()` is the room-wide version, with or without cameras. It skips
the hosts, the moderators and whoever pressed it, and that exemption list lives
in SQL — a client choosing its own exemptions would be a client that can mute a
host. It records one audit event, not one per person.

In-room chat lives in Postgres (`space_messages`, or the existing
`conversations`/`messages` thread for an appointment) and travels over Supabase
Realtime. LiveKit text streams are not persisted and reach only whoever is
connected when the stream opens, which would leave a student arriving ten minutes
late looking at an empty panel.

Deploying it needs three secrets — `LIVEKIT_URL`, `LIVEKIT_API_KEY` and
`LIVEKIT_API_SECRET` — on the Edge Functions. The clients hold none of them:
`livekit-token` returns the URL alongside the token it signs.

**The protocol exists twice.** `web/src/lib/livekit.js` and
`student_app/lib/features/meet/models/room_protocol.dart` are the same wire
contract in two languages, and LiveKit validates none of it — a value that
differs does not error, it silently fails to arrive. `npm run test:protocol`
compares them.

## Phase 2, still out of scope

Recording (LiveKit Egress), live captions, breakout rooms, polls and Q&A;
premium student services, subscription billing (Paystack in-region, Stripe
international), the enterprise CRM/API, and splitting out a standalone tech
brand.

`institution_subscriptions` and `guard_institution_tier()` are already in place
for the billing, so gating video to paid tiers stays an additive change.

## What "verified" means

Each badge is a trust claim, so each one is deliberately narrow:

- **Verified institution** — someone controlling an email address on the
  institution's own domain vouched for the listing. *Not* a claim about
  accreditation or programme quality.
- **Verified student** — an admin checked the uploaded documents against the
  stated qualifications. *Not* a claim about the documents' issuer.
- **Verified educator** — the institution affiliation was confirmed.

`verifications.evidence` records the basis of every decision, so a badge can be
justified after the fact.

## Development accounts

`supabase/seed.sql` creates demo accounts, all with the password
`Lekkside123!` — development only.

| Role | Email |
|---|---|
| Admin | `admin@lekkside.com` |
| Institution (Enterprise) | `admissions@maplecrest.ca` |
| Institution (Professional) | `admissions@northgate.ac.uk` |
| Student (mid-pipeline) | `chidi.okeke@example.com` |
