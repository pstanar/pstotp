#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$SCRIPT_DIR/src/Server.Api/PsTotp.Server.Api.csproj"
SPA_DIR="$SCRIPT_DIR/client/web"
OUT_DIR="$SCRIPT_DIR/publish"
CONFIG="Release"

RIDS=("win-x64" "linux-x64" "osx-arm64")

# Version from nearest git tag (fallback 0.0.0) + commits since tag + short SHA
VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")
BUILD=$(git describe --tags --long 2>/dev/null | sed 's/.*-\([0-9]*\)-g.*/\1/' || echo "0")
SHA=$(git rev-parse --short HEAD)
echo "Version: $VERSION.$BUILD+$SHA"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# Build SPA once — all publishes reuse wwwroot
echo "=== Building SPA ==="
(cd "$SPA_DIR" && npm ci && VITE_APP_VERSION="$VERSION+$SHA" npm run build:deploy)

# Third-party licenses — machine-readable manifests for all dependencies
# bundled into release artifacts. Shipping these satisfies the attribution
# clauses most of our transitive dependencies (MIT / BSD / Apache / MPL / …)
# require when you redistribute binaries.
echo ""
echo "=== Generating third-party license manifests ==="
LICENSES_DIR="$OUT_DIR/licenses"
mkdir -p "$LICENSES_DIR/nuget" "$LICENSES_DIR/npm"

# NuGet dependencies, transitive included, via the local tool manifest.
# dotnet-project-licenses doesn't parse .slnx yet, so we point it at the
# src folder; it walks project files from there. It also writes one
# format per invocation, so we call it twice.
dotnet tool restore
dotnet restore "$SCRIPT_DIR/PsTotp.slnx"
LICENSE_COMMON=(--input "$SCRIPT_DIR/src" --include-transitive --unique \
    --output-directory "$LICENSES_DIR/nuget")
dotnet dotnet-project-licenses "${LICENSE_COMMON[@]}" --json
dotnet dotnet-project-licenses "${LICENSE_COMMON[@]}" --md

# npm dependencies (production only — devDependencies aren't shipped).
(cd "$SPA_DIR" && npx --yes license-checker --production --json \
    --out "$LICENSES_DIR/npm/licenses.json")
(cd "$SPA_DIR" && npx --yes license-checker --production --markdown \
    --out "$LICENSES_DIR/npm/licenses.md")

cat > "$LICENSES_DIR/README.md" <<EOF
# Third-party licenses

This directory lists every third-party dependency baked into the shipped
artifact and the license each one is distributed under. It is machine-
generated at release time and exists to satisfy the attribution
requirements of MIT / BSD / Apache / MPL / etc. dependencies.

- \`nuget/licenses.md\` / \`nuget/licenses.json\` — NuGet packages
  (transitive included, deduped) pulled in by the .NET server.
- \`npm/licenses.md\` / \`npm/licenses.json\` — npm production
  dependencies pulled in by the web client.

PsTotp itself is licensed under Apache 2.0 — see \`/LICENSE\`.

Generated from commit $SHA on $(date -u +%Y-%m-%d).
EOF

# Docker image
echo ""
echo "=== Building Docker image ==="
docker build --build-arg APP_VERSION="$VERSION+$SHA" -t pstotp -t "pstotp:$VERSION" "$SCRIPT_DIR"

# Platform publishes
for RID in "${RIDS[@]}"; do
    for SELF_CONTAINED in true false; do
        if [ "$SELF_CONTAINED" = "true" ]; then
            LABEL="self-contained"
        else
            LABEL="framework-dependent"
        fi

        NAME="pstotp-${VERSION}-${RID}-${LABEL}"
        echo ""
        echo "=== Publishing $NAME ==="

        dotnet publish "$PROJECT" \
            -c "$CONFIG" \
            -r "$RID" \
            --self-contained "$SELF_CONTAINED" \
            -p:SkipSpa=true \
            -p:Version="$VERSION" \
            -p:FileVersion="$VERSION.$BUILD" \
            -p:SourceRevisionId="$SHA" \
            -o "$OUT_DIR/$NAME"

        # Ship the third-party license manifests inside each archive so
        # redistribution satisfies attribution requirements out of the box.
        cp -R "$LICENSES_DIR" "$OUT_DIR/$NAME/licenses"

        # Archive: zip for Windows, tar.gz for Linux/macOS
        echo "    Archiving $NAME..."
        if [[ "$RID" == win-* ]] && command -v zip &>/dev/null; then
            (cd "$OUT_DIR" && zip -qr "$NAME.zip" "$NAME")
        else
            tar -czf "$OUT_DIR/$NAME.tar.gz" -C "$OUT_DIR" "$NAME"
        fi

        rm -rf "$OUT_DIR/$NAME"
    done
done

# SHA-256 checksums
echo ""
echo "=== Generating checksums ==="
(cd "$OUT_DIR" && sha256sum pstotp-* > SHA256SUMS)
cat "$OUT_DIR/SHA256SUMS"

echo ""
echo "=== Done ==="
echo "Docker image: pstotp:latest"
echo "Archives + checksums in $OUT_DIR/"
