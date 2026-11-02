# Lekkside Connect — student app

One Flutter codebase shipping to iOS, Android and web. A student builds their
Education Passport once, gets discovered by institutions, meets them, and
tracks their applications — all from here.

## Running it

```bash
export PATH="$PATH:/Users/mac/flutter/bin"   # SDK is not on PATH on this machine
cp .env.example .env                         # fill in SUPABASE_URL and SUPABASE_ANON_KEY
flutter pub get
flutter analyze && flutter test
flutter run -d chrome        # or -d ios / -d android
```

Verified on web and the iOS simulator. The Android build is untested — there is
no Android SDK on this machine.

## Structure

Feature-first, mirroring `consult-app/consult_client`:

```
lib/
├── main.dart          dotenv → Supabase.initialize → MultiProvider
├── app.dart           GoRouter + StatefulShellRoute.indexedStack
├── core/              constants, theme, supabase service, utils, widgets
└── features/<name>/   {models, providers, screens, widgets}
```

Features: `auth`, `passport`, `discover`, `matches`, `meet`, `messages`,
`applications`, `fairs`, `notifications`, `profile`, `home`, `shell`.

## Things worth knowing before changing this

**Three passport fields are computed by the database** and will be rejected if
written: `completeness`, `normalized_grade` and `english_band`. `save()` reads
the row back rather than trusting the local copy.

**Matching is maintained by database triggers.** Saving the passport is enough —
nothing in the app needs to ask for a recompute. `MatchesProvider.recompute()`
exists only for the unusual case.

**Uploads take bytes, not paths.** This ships to web, where `file_picker` and
`image_picker` return no filesystem path at all. `Uint8List` is the one
signature that works on all three platforms, and any `dart:io` import needs a
`kIsWeb` guard.

**Storage paths are built through `SupabaseService`.** The policies authorize on
the first path segment and there is a CHECK constraint enforcing it, so a
hand-built path is a policy violation waiting to happen.

**The student is the authority on their own consent.** Every screen that grants
an institution access says so before it happens, and `sharing_screen.dart` is a
complete, revocable record — complete by construction, because every grant is a
`passport_shares` row.
