# TeamCash Production Hardening

## Current posture

- Cloud Functions now emit structured start/success/failure logs with latency and idempotency hints.
- Flutter bootstrap now supports environment-driven App Check setup and structured diagnostics.
- Firestore and Storage rules now validate safer payload shapes for owner-managed content paths.
- Edge-case integration coverage now includes:
  - duplicate group join idempotency
  - claim-by-phone rejection for non-phone sessions
  - notification read/update permissions

## Environment model

Flutter uses `--dart-define`:

- `TEAMCASH_ENV=dev|staging|prod`
- `TEAMCASH_FUNCTIONS_REGION=us-central1`
- `TEAMCASH_APPCHECK_MODE=off|monitor|enforce`
- `TEAMCASH_APPCHECK_WEB_SITE_KEY=...`
- `TEAMCASH_APPCHECK_WEB_DEBUG_TOKEN=...`
- `TEAMCASH_VERBOSE_DIAGNOSTICS=true|false`

Functions use dotenv values from `functions/.env.<project-id>` or `functions/.env`:

- `TEAMCASH_ENV`
- `TEAMCASH_FUNCTIONS_REGION`
- `TEAMCASH_APPCHECK_MODE`

## App Check rollout

Recommended rollout:

1. Configure App Check provider in Firebase Console for the web app.
2. Start local/dev with `TEAMCASH_APPCHECK_MODE=monitor`.
3. Register the web debug token if local Chrome uses debug provider.
4. Verify Chrome flows still pass.
5. Switch deploy env to `TEAMCASH_APPCHECK_MODE=enforce`.
6. Re-run owner/staff/client smoke coverage against live backend.

## Deploy order

1. `npm run build` inside `functions/`
2. `flutter analyze`
3. `flutter test`
4. `flutter build web`
5. `firebase deploy --only firestore:rules,storage,functions --project <project-id>`
6. Run Chrome smoke coverage on owner/staff/client and backend hardening tests

## Onboarding operators

For seed/admin onboarding, use the script in `tools/firebase_seed/onboard_operator.mjs`.

It prepares:

- `operatorAccounts/{uid}`
- `operatorUsernames/{usernameNormalized}`

It expects that the Auth user already exists, or that staff auth will be created by the live owner flow inside the app.
