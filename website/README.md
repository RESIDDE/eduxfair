# EduXFair website

The public marketing site: the home page, plus the Privacy Policy, Terms of
Service and Community Guidelines at `/privacy/`, `/terms/` and `/guidelines/`.
App Store Connect links to `/privacy/`.

React 19, Vite and Tailwind 4, the same stack as `web/`. It has no backend and
builds to static files that any host can serve.

`/delete-account/` needs `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`
(see `.env.example`). Without them it says web deletion is unavailable and
points to the in-app path. To try it against the local devserver instead of
the hosted project, put the devserver's values in `.env.development.local`.

```bash
npm install
npm run dev      # http://localhost:5180
npm run build    # → dist/
```

## Where things live

| Path | What it is |
|---|---|
| `src/sections/` | One file per home-page section, in page order (see `src/pages/Home.jsx`) |
| `src/components/screens.jsx` | The app screens shown in phone frames. They are drawn in HTML, not screenshots, so they stay sharp at any size and can be updated in code. Labels and sample data match `student_app` and `devserver/seed.mjs` |
| `src/pages/DeleteAccount.jsx` | `/delete-account/`: web account deletion, the URL for Google Play's Data safety form. Same flow and same `delete-account` function as the app. The only page that talks to Supabase, and it is lazy-loaded so the others never download the client |
| `src/lib/site.js` | Support email, store links, nav. **Add the App Store and Play Store URLs here** when the apps go live; until then the badges say "Coming soon" |
| `src/content/policies.json` | Generated. Do not edit |
| `scripts/sync-policies.mjs` | Reads `student_app/lib/features/legal/models/policies.dart` and writes `policies.json`. Runs before every `dev` and `build`, so the hosted policies always match the text in the app |

## Deploying

Upload `dist/` to the host for `educationfair.com.ng`. Each policy is a real
`index.html` in its own folder, so no rewrite rules are needed.
