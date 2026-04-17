Push-Location "D:\teamcash"
try {
  if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    throw "Java 17+ is required for Firebase emulators. Install Java and add it to PATH."
  }

  npm ci --prefix functions
  npx firebase-tools emulators:exec --project demo-teamcash --only auth,firestore,functions,storage "npm --prefix functions test"
} finally {
  Pop-Location
}
