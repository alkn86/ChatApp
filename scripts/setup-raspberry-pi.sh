#!/bin/bash

# Setup script for ChatApp on Raspberry Pi
# Run this after publishing and copying files to the Pi
# Usage: ./setup-raspberry-pi.sh /path/to/chatapp

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 /path/to/chatapp"
    echo "Example: $0 /opt/chatapp"
    exit 1
fi

CHATAPP_DIR="$1"

if [ ! -d "$CHATAPP_DIR" ]; then
    echo "Error: Directory $CHATAPP_DIR does not exist"
    exit 1
fi

echo "Setting up ChatApp at $CHATAPP_DIR..."

# Create uploads directory if it doesn't exist
echo "Creating uploads directory..."
mkdir -p "$CHATAPP_DIR/wwwroot/uploads"

# Set permissions on app directory
echo "Setting permissions on app directory..."
chmod 755 "$CHATAPP_DIR"
chmod 755 "$CHATAPP_DIR/wwwroot"

# Set executable permissions on the ChatApp binary
echo "Setting executable permissions on ChatApp binary..."
chmod +x "$CHATAPP_DIR/ChatApp"

# Set permissions on uploads directory (readable, writable, executable for owner)
echo "Setting permissions on uploads directory..."
chmod 755 "$CHATAPP_DIR/wwwroot/uploads"

# Set permissions on all config files
echo "Setting permissions on config files..."
chmod 644 "$CHATAPP_DIR/appsettings.json"
if [ -f "$CHATAPP_DIR/appsettings.Production.json" ]; then
    chmod 644 "$CHATAPP_DIR/appsettings.Production.json"
fi

# Create database directory if using non-local database
DB_DIR="$CHATAPP_DIR/data"
if [ ! -d "$DB_DIR" ]; then
    echo "Creating database directory..."
    mkdir -p "$DB_DIR"
    chmod 755 "$DB_DIR"
fi

# If certificate exists, set proper permissions
if [ -f "/etc/ssl/certs/chatapp.pfx" ]; then
    echo "Setting certificate permissions..."
    sudo chmod 600 /etc/ssl/certs/chatapp.pfx
    sudo chown root:root /etc/ssl/certs/chatapp.pfx
fi

echo ""
echo "✓ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Verify config: cat $CHATAPP_DIR/appsettings.Production.json"
echo "2. Start the app: cd $CHATAPP_DIR && ASPNETCORE_ENVIRONMENT=Production ./ChatApp"
echo "3. Or run with sudo if using ports 80/443: sudo ./ChatApp"
echo ""
echo "For systemd service, run: sudo $CHATAPP_DIR/../scripts/setup-systemd-service.sh"
