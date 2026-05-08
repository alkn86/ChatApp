#!/bin/bash

# Setup systemd service for ChatApp on Raspberry Pi
# Run this with sudo to install ChatApp as a system service
# Usage: sudo ./setup-systemd-service.sh /path/to/chatapp

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: sudo $0 /path/to/chatapp"
    echo "Example: sudo ./setup-systemd-service.sh /opt/chatapp"
    exit 1
fi

CHATAPP_DIR="$1"
SERVICE_NAME="chatapp"
SERVICE_USER="chatapp"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

if [ ! -f "$CHATAPP_DIR/ChatApp" ]; then
    echo "Error: ChatApp executable not found at $CHATAPP_DIR/ChatApp"
    exit 1
fi

echo "Setting up systemd service for ChatApp..."

# Create system user if it doesn't exist
if ! id "$SERVICE_USER" &>/dev/null; then
    echo "Creating system user: $SERVICE_USER"
    useradd -r -s /bin/false "$SERVICE_USER"
else
    echo "User $SERVICE_USER already exists"
fi

# Set ownership of chatapp directory to the service user
echo "Setting directory ownership..."
chown -R "$SERVICE_USER:$SERVICE_USER" "$CHATAPP_DIR"
chmod 755 "$CHATAPP_DIR"
chmod +x "$CHATAPP_DIR/ChatApp"

# Verify config files exist
echo "Checking configuration files..."
if [ ! -f "$CHATAPP_DIR/appsettings.json" ]; then
    echo "Warning: appsettings.json not found in $CHATAPP_DIR"
    echo "The app may fail to start without this file."
fi

if [ ! -f "$CHATAPP_DIR/appsettings.Production.json" ]; then
    echo "Info: Creating appsettings.Production.json with Production environment..."
    cat > "$CHATAPP_DIR/appsettings.Production.json" << 'PRODEOF'
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft": "Warning",
      "Microsoft.AspNetCore": "Information"
    }
  },
  "AllowedHosts": "*"
}
PRODEOF
    chmod 644 "$CHATAPP_DIR/appsettings.Production.json"
    chown "$SERVICE_USER:$SERVICE_USER" "$CHATAPP_DIR/appsettings.Production.json"
fi

# Ensure database directory is writable
echo "Setting up database directory..."
mkdir -p "$CHATAPP_DIR/data"
chown "$SERVICE_USER:$SERVICE_USER" "$CHATAPP_DIR/data"
chmod 755 "$CHATAPP_DIR/data"

# Update connection string to use data directory if not already using absolute path
if [ -f "$CHATAPP_DIR/appsettings.json" ]; then
    if ! grep -q '"DefaultConnection"' "$CHATAPP_DIR/appsettings.json"; then
        echo "Info: No connection string found in appsettings.json"
        echo "Using default: Data Source=$CHATAPP_DIR/chat.db"
    fi
fi

# Create systemd service file
echo "Creating systemd service file..."
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=ChatApp Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$CHATAPP_DIR
ExecStart=$CHATAPP_DIR/ChatApp
Restart=on-failure
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3

StandardOutput=journal
StandardError=journal
SyslogIdentifier=chatapp

# Environment
Environment="ASPNETCORE_ENVIRONMENT=Production"
Environment="DOTNET_SYSTEM_NET_HTTP_USESOCKETSHTTPHANDLER=0"

# Ensure sufficient file descriptors and processes
LimitNOFILE=65536
LimitNPROC=65536

# Give service time to start
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$SERVICE_FILE"

# Reload systemd and enable the service
echo "Reloading systemd daemon..."
systemctl daemon-reload

echo "Enabling $SERVICE_NAME service..."
systemctl enable "$SERVICE_NAME"

echo ""
echo "✓ Systemd service setup complete!"
echo ""
echo "Setup summary:"
echo "  ChatApp directory: $CHATAPP_DIR"
echo "  Service user: $SERVICE_USER"
echo "  Config file: $CHATAPP_DIR/appsettings.Production.json"
echo "  Database dir: $CHATAPP_DIR/data"
echo "  Service file: $SERVICE_FILE"
echo ""
echo "Available commands:"
echo "  sudo systemctl start $SERVICE_NAME      # Start the service"
echo "  sudo systemctl stop $SERVICE_NAME       # Stop the service"
echo "  sudo systemctl restart $SERVICE_NAME    # Restart the service"
echo "  sudo systemctl status $SERVICE_NAME     # Check service status"
echo "  sudo journalctl -u $SERVICE_NAME -f     # Follow service logs in real-time"
echo "  sudo journalctl -u $SERVICE_NAME -n 50  # Show last 50 log lines"
echo ""
echo "Troubleshooting:"
echo "  1. Check logs: sudo journalctl -u $SERVICE_NAME -n 100 --no-pager"
echo "  2. Verify permissions: ls -la $CHATAPP_DIR"
echo "  3. Test manually: sudo -u $SERVICE_USER $CHATAPP_DIR/ChatApp"
echo ""
echo "Service will auto-start on boot."
