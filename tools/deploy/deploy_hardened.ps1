param(
  [string]$ProjectId = "teamcash-83a6e"
)

Push-Location "D:\teamcash\functions"
try {
  npm run build
} finally {
  Pop-Location
}

flutter analyze
flutter test
flutter build web
firebase deploy --only "firestore:rules,storage,functions" --project $ProjectId
