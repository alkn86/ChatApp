#!/bin/bash
# Create a self-signed certificate for development/testing
# Usage: ./create-self-signed-cert.sh [domain] [output-dir]

DOMAIN="${1:-localhost}"
OUTPUT_DIR="${2:-.}"

echo "Creating self-signed certificate for domain: $DOMAIN"
echo "Output directory: $OUTPUT_DIR"

# Create certificate valid for 365 days
openssl req -x509 -newkey rsa:4096 -keyout "$OUTPUT_DIR/chatapp.key" \
  -out "$OUTPUT_DIR/chatapp.crt" -days 365 -nodes \
  -subj "/CN=$DOMAIN"

# Convert to PKCS#12 format (.pfx) - required by .NET
openssl pkcs12 -export -out "$OUTPUT_DIR/chatapp.pfx" \
  -inkey "$OUTPUT_DIR/chatapp.key" -in "$OUTPUT_DIR/chatapp.crt" \
  -password pass:

echo "Certificate created successfully!"
echo "  - Private key: $OUTPUT_DIR/chatapp.key"
echo "  - Certificate: $OUTPUT_DIR/chatapp.crt"
echo "  - PKCS#12: $OUTPUT_DIR/chatapp.pfx"
echo ""
echo "For production, deploy chatapp.pfx to: /etc/ssl/certs/chatapp.pfx"
