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

# Create systemd service file
echo "Creating systemd service file..."
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=ChatApp Service
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$CHATAPP_DIR
ExecStart=$CHATAPP_DIR/ChatApp
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

# Environment
Environment="ASPNETCORE_ENVIRONMENT=Production"

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
echo "Available commands:"
echo "  sudo systemctl start $SERVICE_NAME      # Start the service"
echo "  sudo systemctl stop $SERVICE_NAME       # Stop the service"
echo "  sudo systemctl restart $SERVICE_NAME    # Restart the service"
echo "  sudo systemctl status $SERVICE_NAME     # Check service status"
echo "  sudo journalctl -u $SERVICE_NAME -f     # Follow service logs"
echo ""
echo "Service will auto-start on boot."
