#!/bin/bash
# Creates a stable self-signed code signing identity named "ValVoice Developer".
# Once installed and Accessibility is granted, future rebuilds signed with this
# identity keep the same TCC Designated Requirement — so permissions persist.
set -euo pipefail

IDENTITY_NAME="ValVoice Developer"
PASS="valvoice"  # throwaway pkcs12 password, local only

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY_NAME"; then
    echo "✓ Signing identity '$IDENTITY_NAME' already exists"
    exit 0
fi

echo "→ Creating self-signed code signing identity '$IDENTITY_NAME'..."

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

cat > "$TMP/cert.conf" <<CFG
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3_req
[dn]
CN = $IDENTITY_NAME
[v3_req]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CFG

openssl genrsa -out "$TMP/key.pem" 2048 2>/dev/null
openssl req -new -x509 -days 36500 \
    -key "$TMP/key.pem" \
    -out "$TMP/cert.pem" \
    -config "$TMP/cert.conf" \
    -extensions v3_req 2>/dev/null

openssl pkcs12 -export -legacy \
    -out "$TMP/cert.p12" \
    -inkey "$TMP/key.pem" \
    -in "$TMP/cert.pem" \
    -passout "pass:$PASS" 2>/dev/null

security import "$TMP/cert.p12" \
    -k ~/Library/Keychains/login.keychain-db \
    -P "$PASS" \
    -T /usr/bin/codesign \
    -T /usr/bin/security 2>&1

security add-trusted-cert \
    -d -r trustRoot \
    -k ~/Library/Keychains/login.keychain-db \
    -p codeSign \
    "$TMP/cert.pem" 2>/dev/null || true

echo ""
echo "✓ Identity created. Future rebuilds will use this cert → Accessibility grant persists."
