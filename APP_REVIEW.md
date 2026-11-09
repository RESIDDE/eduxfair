# App Store submission — what is built, and what is left

Checked against the App Store Review Guidelines as published **16 October 2026**.
Re-read them before you submit; they change.

---

## 1.2 User-Generated Content — the four mandatory items

Apple states these as a list an app "must include". All four now exist.

| Requirement | Where it lives |
|---|---|
| A method for filtering objectionable material **from being posted** | `student_app/lib/core/moderation/content_filter.dart`, run in the composer before the upload starts |
| A mechanism to report offensive content, and timely responses | Report on a post, a comment and now an **account**; `reports` table with a pending queue and child-safety reports indexed ahead of the rest |
| The ability to block abusive users | Block and mute, plus **Settings → Blocked accounts** to review and undo |
| Published contact information | `support@educationfair.com.ng` in Settings → Contact support, in the Privacy Policy, and in the Terms |

**Filtering.** Two tiers. Sexualising a minor, threats of violence and sexual
solicitation are refused outright. Slurs, targeted abuse and admissions fraud
("guaranteed visa") warn and let the author continue, because context decides —
a student quoting the abuse they received is not the student sending it. Text
is normalised first (case, accents, leetspeak, stretched letters, separators),
so `k.y.s` and `kyyyys` are caught. 25 tests, including ten ordinary sentences
that must **not** trip it.

A wordlist is a blunt instrument and will not catch everything. It is the
first line, not the only one.

---

## 5.1.1(v) Account deletion

Apple's reference page is specific: deletion must be **initiated in the app**,
must remove the account record and its user-generated content, and may not be
routed through email or chat support.

- **Settings → Delete account**, two taps from the account screen.
- Lists exactly what goes and what stays before anything happens.
- Requires the password (re-authentication) and typing `DELETE`.
- `supabase/functions/delete-account` removes storage objects, then calls
  `purge_account`, then deletes the auth user.
- Everything cascades: `profiles.id` references `auth.users on delete cascade`,
  and 38 tables cascade from `profiles`.

**What is retained, and disclosed in-app:** records required by law, and
safety reports. A report you filed survives with your name removed — otherwise
deleting an account would be a way to withdraw a child-safety report about
someone else.

---

## 5.1.1(i) Privacy policy · Terms · Community Guidelines

Shipped **in the binary**, not behind a URL — guideline 2.1 rejects builds with
non-functional URLs, and a link to a marketing site fails if the site is down
or blocked on the reviewer's network.

- `student_app/lib/features/legal/models/policies.dart`
- Reachable signed out (the sign-up screen links to all three) and from
  Settings.
- The Terms carry the explicit zero-tolerance clause 1.2 expects.

---

## 5.1.4 Minors

Minimum age **16**, enforced in three places: the sign-up form, the edge
function, and a `CHECK` constraint on `profiles`. Sixteen rather than thirteen
puts COPPA's under-13 regime out of scope and matches the GDPR Article 8
ceiling, so one rule holds everywhere the fair recruits.

`date_of_birth` is collected for age verification only — never displayed,
never used for matching, never shared with institutions. That is the only
basis 5.1.4(a) allows for asking a minor their birthdate.

---

## Already in place before this pass

- **5.1.1(ii) purpose strings** — camera, microphone, photos and location in
  `ios/Runner/Info.plist`, each naming the actual use.
- **1.6 data security** — RLS on all 60 tables; the passport is unreadable
  without a live `passport_shares` row, enforced in the database rather than
  in the UI.
- **4.8** — not triggered: email and password only, no third-party login. If
  you add Google or Facebook sign-in later, this changes.
- **3.1.1** — not triggered: free, no in-app purchases.

---

## What only you can do

### Before submitting — App Store Connect

1. **Host the privacy policy.** App Store Connect requires a reachable URL in
   the listing metadata, separate from the in-app copy. Publish the same text
   at `https://educationfair.com.ng/privacy` and the Terms at `/terms`.
   Those two constants are still in `app_constants.dart` for this reason;
   nothing in the app links to them.
2. **Support URL** — guideline 1.5 wants an easy way to reach you, and says it
   matters especially for apps used in a classroom.
3. **Demo account** — guideline 2.1 requires one, with the backend live during
   review. Supply a student account whose passport is filled in, and a second
   account so the reviewer can test reporting, blocking and direct messages
   against someone. Say in the notes that deletion is under Settings → Delete
   account, and that the demo account **will be destroyed** if they use it.
4. **Age rating** — answer honestly (2.3.6). This app has unrestricted web-free
   UGC and user-to-user messaging; expect 12+ or 17+ depending on your answers.
   Do **not** pick the Kids Category.
5. **Screenshots** — 2.3.9 requires fictional account data, not a real
   student's profile or posts.
6. **Privacy "Nutrition Label"** — declare: contact info, user content,
   identifiers, and the sensitive education records in the passport. There is
   no tracking and no advertising to declare.

### Needs a lawyer, not a developer

**The Privacy Policy and Terms are drafts.** They describe what the code
actually does — I wrote them against the schema, not from a template — but
they have not been reviewed by anyone qualified, and Nigerian NDPA, GDPR and
any other regime you operate under will have requirements I have not checked.
Have them reviewed before you ship. In particular, confirm the data-retention
and international-transfer sections match your actual contracts with Supabase,
LiveKit and Resend.

### Known gaps, stated plainly

- **Ban evasion.** Terminating an account does not stop that person signing up
  again with another email. Apple does not require solving this, and the
  privacy policy does not claim it is solved.
- **Filtering is text-only.** Images are not scanned. Reports are the control
  for image abuse.
- **"Timely responses"** is an operational promise, not a code path. Someone
  has to work the `reports` queue. The child-safety index exists so that
  whoever does can see those first.
- **Institution side** (`/org/*`) was out of scope for the recent design work
  and has not been re-checked against these guidelines.
