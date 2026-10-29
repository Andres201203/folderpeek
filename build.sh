#!/bin/zsh
# Builds FolderPeek.app next to this script. Pass --install to also start it
# now and at every login (LaunchAgent). Pass --uninstall to remove that.
set -euo pipefail
cd "${0:A:h}"

APP="FolderPeek.app"
LABEL="com.andres.folderpeek"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
IDENTITY="FolderPeek Local"

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$AGENT"
  echo "Removed login item. The app itself is still in $(pwd)/$APP"
  exit 0
fi

./test.sh

# A stable self-signed identity keeps the Accessibility grant across rebuilds
# (ad-hoc signatures change every build and macOS forgets the grant).
if ! security find-identity -p codesigning | command grep -q "\"$IDENTITY\""; then
  echo "Creating local signing identity \"$IDENTITY\" (one time)…"
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT   # never leave the private key behind
  cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
  /usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout pass:folderpeek 2>/dev/null
  security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P folderpeek -T /usr/bin/codesign >/dev/null
fi

mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -target arm64-apple-macos26.0 \
  -o "$APP/Contents/MacOS/FolderPeek" Sources/*.swift

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>FolderPeek</string>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleExecutable</key><string>FolderPeek</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign "$IDENTITY" --identifier "$LABEL" "$APP"
echo "Built $(pwd)/$APP"

if [[ "${1:-}" == "--install" ]]; then
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$(pwd)/$APP/Contents/MacOS/FolderPeek</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null && sleep 1 || true
  launchctl bootstrap "gui/$(id -u)" "$AGENT"
  echo "Running, and set to start at login."
fi
