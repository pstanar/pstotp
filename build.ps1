$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot
$Project   = "$ScriptDir\src\Server.Api\PsTotp.Server.Api.csproj"
$SpaDir    = "$ScriptDir\client\web"
$OutDir    = "$ScriptDir\publish"
$Config    = 'Release'

$Rids = @('win-x64', 'linux-x64', 'osx-arm64')

# Version from nearest git tag (fallback 0.0.0) + commits since tag + short SHA
$Version = git describe --tags --abbrev=0 2>$null
if ($LASTEXITCODE -ne 0 -or -not $Version) { $Version = '0.0.0' }
$Version = $Version -replace '^v', ''
$Long = git describe --tags --long 2>$null
if ($Long -match '-(\d+)-g') { $Build = $Matches[1] } else { $Build = '0' }
$Sha = git rev-parse --short HEAD
Write-Host "Version: $Version.$Build+$Sha"

if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force }
New-Item $OutDir -ItemType Directory | Out-Null

# OpenAPI export stale-check.
#
# Regenerate docs/openapi.json from the live endpoint metadata and fail
# the build if it differs from what's committed — keeps integrators
# from reading a stale schema. PSTOTP_OPENAPI_EXPORT=1 short-circuits
# DB-touching startup so the dotnet-getdocument child process can boot
# the host without a reachable database (see App.cs).
Write-Host "=== Checking OpenAPI schema (docs/openapi.json) ==="
$env:PSTOTP_OPENAPI_EXPORT = '1'
try {
    dotnet build $Project -c $Config -p:GenerateOpenApi=true -p:SkipSpa=true --nologo -v q
} finally {
    Remove-Item Env:\PSTOTP_OPENAPI_EXPORT -ErrorAction SilentlyContinue
}
if ($LASTEXITCODE -ne 0) { throw "OpenAPI regeneration failed" }
git diff --quiet --exit-code "$ScriptDir\docs\openapi.json"
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: docs/openapi.json is out of date."
    Write-Host "       Regenerated schema differs from the committed copy."
    Write-Host "       Review the diff and commit the new openapi.json."
    exit 1
}
Write-Host "    docs/openapi.json up to date."

# Build SPA once — all publishes reuse wwwroot
Write-Host "`n=== Building SPA ==="
Push-Location $SpaDir
try {
    npm ci
    $env:VITE_APP_VERSION = "$Version+$Sha"
    npm run build:deploy
} finally {
    Remove-Item Env:\VITE_APP_VERSION -ErrorAction SilentlyContinue
    Pop-Location
}

# Third-party licenses — machine-readable manifests for all dependencies
# bundled into release artifacts. Shipping these satisfies the attribution
# clauses most of our transitive dependencies (MIT / BSD / Apache / MPL / …)
# require when you redistribute binaries.
Write-Host "`n=== Generating third-party license manifests ==="
$LicensesDir = "$OutDir\licenses"
New-Item "$LicensesDir\nuget" -ItemType Directory -Force | Out-Null
New-Item "$LicensesDir\npm"   -ItemType Directory -Force | Out-Null

# NuGet dependencies, transitive included, via the local tool manifest.
# dotnet-project-licenses doesn't parse .slnx yet, so we point it at the
# src folder; it walks project files from there. It also writes one
# format per invocation, so we call it twice.
dotnet tool restore
dotnet restore "$ScriptDir\PsTotp.slnx"
$LicenseCommon = @(
    '--input', "$ScriptDir\src",
    '--include-transitive',
    '--unique',
    '--output-directory', "$LicensesDir\nuget"
)
dotnet dotnet-project-licenses @LicenseCommon --json
dotnet dotnet-project-licenses @LicenseCommon --md

# npm dependencies (production only — devDependencies aren't shipped).
Push-Location $SpaDir
try {
    npx --yes license-checker --production --json `
        --out "$LicensesDir\npm\licenses.json"
    npx --yes license-checker --production --markdown `
        --out "$LicensesDir\npm\licenses.md"
} finally {
    Pop-Location
}

$Today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
$ReadmeContent = @"
# Third-party licenses

This directory lists every third-party dependency baked into the shipped
artifact and the license each one is distributed under. It is machine-
generated at release time and exists to satisfy the attribution
requirements of MIT / BSD / Apache / MPL / etc. dependencies.

- ``nuget/licenses.md`` / ``nuget/licenses.json`` — NuGet packages
  (transitive included, deduped) pulled in by the .NET server.
- ``npm/licenses.md`` / ``npm/licenses.json`` — npm production
  dependencies pulled in by the web client.

PsTotp itself is licensed under Apache 2.0 — see ``/LICENSE``.

Generated from commit $Sha on $Today.
"@
Set-Content -Path "$LicensesDir\README.md" -Value $ReadmeContent

# Docker image.
#
# Skipped when SKIP_DOCKER_IMAGE is set — the usual case when build.sh
# runs inside a container (Dockerfile.build) and the server image is
# produced separately by the host.
if ($env:SKIP_DOCKER_IMAGE) {
    Write-Host "`n=== Skipping server Docker image (SKIP_DOCKER_IMAGE set) ==="
} else {
    Write-Host "`n=== Building Docker image ==="
    docker build --build-arg "APP_VERSION=$Version+$Sha" -t pstotp -t "pstotp:$Version" $ScriptDir
}

# Platform publishes
foreach ($Rid in $Rids) {
    foreach ($SelfContained in @($true, $false)) {
        if ($SelfContained) { $Label = 'self-contained' } else { $Label = 'framework-dependent' }

        $Name = "pstotp-$Version-$Rid-$Label"
        Write-Host "`n=== Publishing $Name ==="

        dotnet publish $Project `
            -c $Config `
            -r $Rid `
            --self-contained $SelfContained `
            -p:SkipSpa=true `
            "-p:Version=$Version" `
            "-p:FileVersion=$Version.$Build" `
            "-p:SourceRevisionId=$Sha" `
            -o "$OutDir\$Name"

        # Ship the third-party license manifests inside each archive so
        # redistribution satisfies attribution requirements out of the box.
        Copy-Item -Recurse $LicensesDir "$OutDir\$Name\licenses"

        # Archive: zip for Windows, tar.gz for Linux/macOS
        Write-Host "    Archiving $Name..."
        if ($Rid.StartsWith('win-')) {
            Compress-Archive -Path "$OutDir\$Name" -DestinationPath "$OutDir\$Name.zip"
        } else {
            tar -czf "$OutDir\$Name.tar.gz" -C $OutDir $Name
        }

        Remove-Item "$OutDir\$Name" -Recurse -Force
    }
}

# Android APK (debug build).
#
# Requires an Android SDK plus a JDK 17+. We only ship the debug-signed
# artifact for now — it's enough to smoke-test the build pipeline and
# hand out to known testers. A release-signed APK will be wired in later
# once a real upload keystore exists. If the SDK isn't configured we
# skip the step rather than fail, so server-only build hosts still work.
if ($env:ANDROID_HOME -or $env:ANDROID_SDK_ROOT) {
    Write-Host "`n=== Building Android APK (debug) ==="
    $AndroidDir = "$ScriptDir\client\android"

    # Gradle 9 + AGP 8.13 need JDK 17+. If the user hasn't set JAVA_HOME
    # we fall back to Android Studio's bundled JBR on the usual paths —
    # the common case for Android devs.
    if (-not $env:JAVA_HOME) {
        $studioJbr = 'C:\Program Files\Android\Android Studio\jbr'
        if (Test-Path $studioJbr) {
            $env:JAVA_HOME = $studioJbr
            Write-Host "    Using Android Studio JBR: $env:JAVA_HOME"
        }
    }

    Push-Location $AndroidDir
    try {
        & "$AndroidDir\gradlew.bat" --no-daemon :app:assembleDebug
        if ($LASTEXITCODE -ne 0) { throw "Gradle assembleDebug failed" }
    } finally {
        Pop-Location
    }
    $ApkSrc = "$AndroidDir\app\build\outputs\apk\debug\app-debug.apk"
    $ApkDst = "$OutDir\pstotp-$Version-android-debug.apk"
    Copy-Item $ApkSrc $ApkDst
    Write-Host "    $ApkDst"
} else {
    Write-Host "`n=== Skipping Android APK (ANDROID_HOME / ANDROID_SDK_ROOT not set) ==="
}

# SHA-256 checksums
Write-Host "`n=== Generating checksums ==="
$archives = Get-ChildItem "$OutDir\pstotp-*"
$checksums = foreach ($file in $archives) {
    $hash = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
    "$hash  $($file.Name)"
}
$checksums | Set-Content "$OutDir\SHA256SUMS"
$checksums | Write-Host

Write-Host "`n=== Done ==="
if (-not $env:SKIP_DOCKER_IMAGE) {
    Write-Host "Docker image: pstotp:latest"
}
Write-Host "Archives + checksums in $OutDir\"
