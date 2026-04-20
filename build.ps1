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

# Docker image
Write-Host "`n=== Building Docker image ==="
docker build --build-arg "APP_VERSION=$Version+$Sha" -t pstotp -t "pstotp:$Version" $ScriptDir

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
Write-Host "Docker image: pstotp:latest"
Write-Host "Archives + checksums in $OutDir\"
