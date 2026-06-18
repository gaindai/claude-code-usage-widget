#!/bin/bash
# Claude Code Usage — one-command install.
# Builds the app locally from source and installs it to /Applications
# (or ~/Applications for non-admin accounts).
set -euo pipefail
cd "$(dirname "$0")"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }

# Remediation for a broken / not-yet-initialised Xcode toolchain. Shows up as a
# plugin-load failure pointing at a missing CoreSimulator.framework or a request
# to run 'runFirstLaunch' — the build never even starts. It's the Mac's Xcode
# install, not the app.
xcode_repair_hint() {
  bold "❌ Xcode couldn't load its build components."
  echo "   This is a broken or not-yet-initialised Xcode install on this Mac —"
  echo "   not a problem with the app. Run these, then re-run ./install.sh:"
  echo ""
  echo "     sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo "     sudo xcodebuild -runFirstLaunch"
  echo "     sudo xcodebuild -license accept"
  echo ""
  echo "   If it still fails, reinstall Xcode from the App Store, then run"
  echo "   'sudo xcodebuild -runFirstLaunch' again."
}

# 1. macOS 14+ (Sonoma) required — desktop widgets don't exist before that.
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MAJOR" -lt 14 ]; then
  bold "❌ Claude Code Usage requires macOS 14 (Sonoma) or newer — found $(sw_vers -productVersion)."
  exit 1
fi

# 2. Full Xcode required (Command Line Tools are not enough).
if ! /usr/bin/xcrun xcodebuild -version >/dev/null 2>&1; then
  bold "❌ Xcode is required."
  echo "   1. Install Xcode from the App Store (free)"
  echo "   2. Open it once and accept the license"
  echo "   3. Then: sudo xcode-select -s /Applications/Xcode.app"
  echo "   4. Re-run ./install.sh"
  exit 1
fi

# 3. The Xcode project is always generated from project.yml — the reviewable
#    source of truth. No pre-generated project file is shipped in the repo.
if ! command -v xcodegen >/dev/null 2>&1; then
  bold "❌ XcodeGen is required to generate the project file."
  echo "   brew install xcodegen   — then re-run ./install.sh"
  exit 1
fi
xcodegen generate >/dev/null

# 4. Stable local code-signing identity.
#    Ad-hoc signing (CODE_SIGN_IDENTITY="-") binds the keychain authorization to
#    the exact code hash, which changes on every build — so macOS re-prompts for
#    your password after each update. A self-signed certificate binds the
#    authorization to a stable identity instead, so "Always Allow" sticks across
#    updates. No Apple Developer account required; created once per Mac.
CERT_NAME="Claude Usage Local Signing"
# find-identity (deliberately WITHOUT -v): the self-signed cert is untrusted
# (CSSMERR_TP_NOT_TRUSTED), so the -v "valid identities" listing would never show
# it — guarding on that would recreate the cert on every install, changing the
# signing identity each time and re-triggering the keychain prompt. The plain
# listing requires a usable cert+private-key identity, not just a certificate, so
# a stray cert without its key is correctly re-created instead of failing the build.
if ! security find-identity -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
  bold "🔐 Creating a one-time local signing certificate (no Apple account needed) …"
  CWORK=$(mktemp -d)
  cat > "$CWORK/cert.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = Claude Usage Local Signing
[v3]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
  openssl req -x509 -newkey rsa:2048 -keyout "$CWORK/key.pem" -out "$CWORK/cert.pem" \
    -days 3650 -nodes -config "$CWORK/cert.cnf" 2>/dev/null
  # SHA1 MAC + 3DES PBE so the macOS `security` importer accepts the PKCS#12.
  openssl pkcs12 -export -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -inkey "$CWORK/key.pem" -in "$CWORK/cert.pem" -out "$CWORK/id.p12" \
    -passout pass:claude-usage -name "$CERT_NAME" 2>/dev/null
  security import "$CWORK/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P claude-usage -T /usr/bin/codesign >/dev/null 2>&1
  rm -rf "$CWORK"
fi

bold "🔨 Building Claude Code Usage (Release) — first build takes 1-2 minutes …"
# Capture the build output so we can recognise a broken-Xcode failure and print
# actionable steps instead of a raw plugin stack trace. `tee` keeps it live too.
BUILD_LOG=$(mktemp)
if ! /usr/bin/xcrun xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage \
  -configuration Release -derivedDataPath build -quiet \
  CODE_SIGN_IDENTITY="$CERT_NAME" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  OTHER_CODE_SIGN_FLAGS="--keychain $HOME/Library/Keychains/login.keychain-db" build \
  2>&1 | tee "$BUILD_LOG"; then
  if grep -qE 'runFirstLaunch|CoreSimulator|DVTPlugInLoading' "$BUILD_LOG"; then
    echo ""
    xcode_repair_hint
  elif grep -qE 'errSecInternalComponent|Could not sign|User interaction is not allowed|errSecInteractionNotAllowed' "$BUILD_LOG"; then
    echo ""
    bold "❌ Code signing failed."
    echo "   macOS couldn't use the local signing key. If a keychain password"
    echo "   dialog appeared and was dismissed, re-run ./install.sh and choose"
    echo "   \"Always Allow\". Running from a headless/SSH session? Run the install"
    echo "   from a logged-in graphical session so the keychain can be unlocked."
  fi
  rm -f "$BUILD_LOG"
  exit 1
fi
rm -f "$BUILD_LOG"

APP="build/Build/Products/Release/Claude Usage.app"
if [ ! -d "$APP" ]; then
  bold "❌ Build product not found — check the build log above."
  exit 1
fi

# 5. Install target: /Applications, falling back to ~/Applications for
#    non-admin users (login items work from there too).
APP_DIR="/Applications"
if [ ! -w "$APP_DIR" ]; then
  APP_DIR="$HOME/Applications"
  mkdir -p "$APP_DIR"
  bold "ℹ️  No write access to /Applications — installing to $APP_DIR instead."
fi

bold "📦 Installing to $APP_DIR …"
# Stop a running instance so the binary can be replaced (SIGTERM, no
# Apple-Events permission prompt).
pkill -x "Claude Usage" 2>/dev/null || true
sleep 1
rm -rf "$APP_DIR/Claude Usage.app"
ditto "$APP" "$APP_DIR/Claude Usage.app"

bold "🚀 Launching — the onboarding window will guide you through the rest."
open "$APP_DIR/Claude Usage.app"

echo ""
bold "✅ Done."
echo "   Add the widget: right-click the desktop → \"Edit Widgets\" → Claude Code Usage"
