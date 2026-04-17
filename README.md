# TeamCash

Flutter + Firebase loyihasi. Owner, staff va client surface’lari bitta kodbazada ishlaydi. Backend pulga oid oqimlarni Cloud Functions orqali boshqaradi.

## Stack

- Flutter
- Riverpod
- GoRouter
- Firebase Auth
- Cloud Firestore
- Cloud Functions
- Firebase Storage

## Lokal Ishga Tushirish

1. `flutter pub get`
2. `npm ci --prefix functions`
3. Firebase project sozlangan bo‘lsa:
   `powershell -File tools/deploy/run_web_dev.ps1`

## Emulator Rejim

Java 17+ kerak.

1. `npm ci --prefix functions`
2. `firebase emulators:start --project demo-teamcash --only auth,firestore,functions,storage`
3. Boshqa terminalda:
   `powershell -File tools/emulators/run_web_local.ps1`

Emulator rejim `dart-define` orqali yoqiladi va app quyidagilarga ulanadi:

- Auth: `127.0.0.1:9099`
- Firestore: `127.0.0.1:8080`
- Functions: `127.0.0.1:5001`
- Storage: `127.0.0.1:9199`

## Testlar

Flutter:

- `flutter analyze`
- `flutter test`

Functions build:

- `npm run build --prefix functions`

Backend + Firestore rules testlari emulator ichida:

- `powershell -File tools/emulators/run_backend_tests.ps1`

## Deploy

Production deploy uchun:

- `powershell -File tools/deploy/deploy_hardened.ps1`

## Muhim `dart-define`

- `TEAMCASH_ENV=dev|staging|prod`
- `TEAMCASH_FUNCTIONS_REGION=us-central1`
- `TEAMCASH_APPCHECK_MODE=off|monitor|enforce`
- `TEAMCASH_USE_FIREBASE_EMULATORS=true|false`

## Tuzilish

- `lib/app`: bootstrap, router, theme
- `lib/core`: model, session, config, service
- `lib/data`: preview va Firestore repository
- `lib/features`: owner/staff/client/root UI
- `functions/src`: callable backend
- `tools`: seed, deploy, emulator helper scriptlar
