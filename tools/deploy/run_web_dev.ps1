param(
  [string]$WebPort = "9200",
  [string]$EnvName = "dev",
  [string]$FunctionsRegion = "us-central1",
  [string]$AppCheckMode = "monitor",
  [string]$WebSiteKey = "",
  [string]$WebDebugToken = ""
)

$args = @(
  "run",
  "-d",
  "chrome",
  "--web-port",
  $WebPort,
  "--dart-define=TEAMCASH_ENV=$EnvName",
  "--dart-define=TEAMCASH_FUNCTIONS_REGION=$FunctionsRegion",
  "--dart-define=TEAMCASH_APPCHECK_MODE=$AppCheckMode"
)

if ($WebSiteKey -ne "") {
  $args += "--dart-define=TEAMCASH_APPCHECK_WEB_SITE_KEY=$WebSiteKey"
}

if ($WebDebugToken -ne "") {
  $args += "--dart-define=TEAMCASH_APPCHECK_WEB_DEBUG_TOKEN=$WebDebugToken"
}

flutter @args
