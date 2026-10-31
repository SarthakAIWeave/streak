param(
    [string]$OAuthJson = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$signingDir = Join-Path $env:USERPROFILE '.streak-signing'
$signingJson = Join-Path $signingDir 'github-actions-secrets.json'
$keystore = Join-Path $signingDir 'streak-release.jks'
$propertiesPath = Join-Path $projectRoot 'android\key.properties'

foreach ($path in @($signingJson, $keystore)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required signing file not found: $path"
    }
}

$signing = Get-Content -Raw -LiteralPath $signingJson | ConvertFrom-Json
foreach ($name in @('KEYSTORE_PASSWORD', 'KEY_PASSWORD', 'KEY_ALIAS')) {
    if ([string]::IsNullOrWhiteSpace($signing.$name)) {
        throw "Missing $name in signing JSON."
    }
}
if ($signing.KEYSTORE_BASE64 -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystore))) {
    throw 'Keystore does not match KEYSTORE_BASE64 in signing JSON.'
}

$clientId = $env:GOOGLE_WEB_CLIENT_ID
if ([string]::IsNullOrWhiteSpace($clientId)) {
    $clientIdFile = Join-Path $signingDir 'google-web-client-id.txt'
    if (-not [string]::IsNullOrWhiteSpace($OAuthJson)) {
        if (-not (Test-Path -LiteralPath $OAuthJson -PathType Leaf)) {
            throw "OAuth JSON file not found: $OAuthJson"
        }
        $clientId = (Get-Content -Raw -LiteralPath $OAuthJson | ConvertFrom-Json).web.client_id
    } elseif (Test-Path -LiteralPath $clientIdFile -PathType Leaf) {
        $clientId = (Get-Content -Raw -LiteralPath $clientIdFile).Trim()
    } else {
        throw 'Set GOOGLE_WEB_CLIENT_ID, save it in .streak-signing/google-web-client-id.txt, or provide -OAuthJson.'
    }
}
if ([string]::IsNullOrWhiteSpace($clientId)) {
    throw 'Google OAuth Web client ID is missing.'
}

$properties = @(
    "storePassword=$($signing.KEYSTORE_PASSWORD)"
    "keyPassword=$($signing.KEY_PASSWORD)"
    "keyAlias=$($signing.KEY_ALIAS)"
    "storeFile=$($keystore -replace '\\', '/')"
)
if (Test-Path -LiteralPath $propertiesPath) {
    $existing = Get-Content -LiteralPath $propertiesPath
    if (($existing -join "`n") -ne ($properties -join "`n")) {
        throw 'android/key.properties already exists with different settings; it was not overwritten.'
    }
} else {
    [IO.File]::WriteAllLines($propertiesPath, [string[]]$properties, [Text.UTF8Encoding]::new($false))
}

Push-Location $projectRoot
try {
    flutter build apk --release --split-debug-info=build/symbols "--dart-define=GOOGLE_WEB_CLIENT_ID=$clientId"
    if ($LASTEXITCODE -ne 0) { throw "Flutter build failed with exit code $LASTEXITCODE." }
    Write-Host "APK: $(Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk')"
} finally {
    Pop-Location
}
