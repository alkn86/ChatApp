#!/bin/bash
# Setup Let's Encrypt certificate and convert to PKCS#12 format for .NET
# Usage: sudo ./setup-letsencrypt-cert.sh example.com /opt/chatapp

set -e

DOMAIN="${1:-example.com}"
APP_DIR="${2:-/opt/chatapp}"
CERT_DIR="${APP_DIR}/certs"
LETSENCRYPT_DIR="/etc/letsencrypt/live/$DOMAIN"
PFX_PATH="$CERT_DIR/chatapp.pfx"

echo "========================================"
echo "Let's Encrypt Certificate Setup"
echo "========================================"
echo "Domain: $DOMAIN"
echo "App Directory: $APP_DIR"
echo "Certificate Directory: $CERT_DIR"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (use: sudo)"
   exit 1
fi

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    echo "Installing certbot..."
    apt-get update
    apt-get install -y certbot
fi

# Check if openssl is installed
if ! command -v openssl &> /dev/null; then
    echo "Installing openssl..."
    apt-get install -y openssl
fi

# Create certificate directory
mkdir -p "$CERT_DIR"

# Check if certificate already exists
if [ -d "$LETSENCRYPT_DIR" ]; then
    echo "Certificate already exists at: $LETSENCRYPT_DIR"
    echo "Renewing certificate..."
    certbot renew --non-interactive
else
    echo "Creating new Let's Encrypt certificate for: $DOMAIN"
    echo ""
    echo "NOTE: Make sure port 80 is accessible and $DOMAIN points to this server"
    echo "Proceeding with standalone authentication..."
    echo ""

    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email admin@$DOMAIN \
        -d $DOMAIN \
        -d www.$DOMAIN 2>&1 || true
fi

# Convert certificate to PKCS#12 (.pfx) format if cert exists
if [ -f "$LETSENCRYPT_DIR/fullchain.pem" ] && [ -f "$LETSENCRYPT_DIR/privkey.pem" ]; then
    echo ""
    echo "Converting certificate to PKCS#12 format..."

    openssl pkcs12 -export \
        -out "$PFX_PATH" \
        -inkey "$LETSENCRYPT_DIR/privkey.pem" \
        -in "$LETSENCRYPT_DIR/fullchain.pem" \
        -password pass: \
        -nodes

    # Set proper permissions
    chmod 600 "$PFX_PATH"

    echo "✓ Certificate created: $PFX_PATH"
    echo ""
    echo "Certificate Details:"
    echo "  - Domain: $DOMAIN"
    echo "  - Path: $PFX_PATH"
    echo "  - Auto-renewal: Let's Encrypt (certbot handles this)"
    echo ""
    echo "Update appsettings.Production.json with:"
    echo "  \"Path\": \"$PFX_PATH\""
    echo ""
else
    echo "ERROR: Certificate files not found at: $LETSENCRYPT_DIR"
    exit 1
fi

# Setup auto-renewal hook to regenerate .pfx when certificate renews
echo ""
echo "Setting up certificate renewal hook..."

RENEWAL_HOOK_DIR="/etc/letsencrypt/renewal-hooks/post"
mkdir -p "$RENEWAL_HOOK_DIR"

cat > "$RENEWAL_HOOK_DIR/chatapp-pfx-renew.sh" << 'EOF'
#!/bin/bash
# Auto-regenerate PKCS#12 certificate when Let's Encrypt renews

DOMAIN="$1"
LETSENCRYPT_DIR="/etc/letsencrypt/live/$DOMAIN"
PFX_PATH="/opt/chatapp/certs/chatapp.pfx"

if [ -f "$LETSENCRYPT_DIR/fullchain.pem" ] && [ -f "$LETSENCRYPT_DIR/privkey.pem" ]; then
    openssl pkcs12 -export \
        -out "$PFX_PATH" \
        -inkey "$LETSENCRYPT_DIR/privkey.pem" \
        -in "$LETSENCRYPT_DIR/fullchain.pem" \
        -password pass: \
        -nodes

    chmod 600 "$PFX_PATH"
    echo "[$(date)] Certificate renewed and converted to PFX format" >> /var/log/chatapp-cert-renew.log

    # Optional: Restart the application
    # systemctl restart chatapp
fi
EOF

chmod +x "$RENEWAL_HOOK_DIR/chatapp-pfx-renew.sh"
echo "✓ Renewal hook installed at: $RENEWAL_HOOK_DIR/chatapp-pfx-renew.sh"

echo ""
echo "========================================"
echo "Setup Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Update appsettings.Production.json with the certificate path"
echo "2. Restart your ChatApp application"
echo "3. Verify HTTPS works: https://$DOMAIN"
echo ""
echo "Certificate will auto-renew via certbot (checks daily)"
echo "Renewed certificate is automatically converted to .pfx format"
