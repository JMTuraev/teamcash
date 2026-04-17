param(
  [string]$WebPort = "9200",
  [string]$FunctionsRegion = "us-central1"
)

flutter run `
  -d chrome `
  --web-port $WebPort `
  --dart-define=TEAMCASH_ENV=dev `
  --dart-define=TEAMCASH_FUNCTIONS_REGION=$FunctionsRegion `
  --dart-define=TEAMCASH_APPCHECK_MODE=off `
  --dart-define=TEAMCASH_USE_FIREBASE_EMULATORS=true `
  --dart-define=TEAMCASH_AUTH_EMULATOR_HOST=127.0.0.1 `
  --dart-define=TEAMCASH_AUTH_EMULATOR_PORT=9099 `
  --dart-define=TEAMCASH_FIRESTORE_EMULATOR_HOST=127.0.0.1 `
  --dart-define=TEAMCASH_FIRESTORE_EMULATOR_PORT=8080 `
  --dart-define=TEAMCASH_FUNCTIONS_EMULATOR_HOST=127.0.0.1 `
  --dart-define=TEAMCASH_FUNCTIONS_EMULATOR_PORT=5001 `
  --dart-define=TEAMCASH_STORAGE_EMULATOR_HOST=127.0.0.1 `
  --dart-define=TEAMCASH_STORAGE_EMULATOR_PORT=9199
