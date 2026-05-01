# Raspberry Pi Deployment Guide

Quick reference for deploying ChatApp to Raspberry Pi 5.

## Prerequisites

- Raspberry Pi 5 with Linux (Debian/Ubuntu-based)
- SSH access to the Pi
- .NET 9 SDK on your development machine

## Deployment Steps

### 1. Publish the App

From your development machine:

```bash
dotnet publish -c Release -r linux-arm64 --self-contained -o ./publish/pi
```

### 2. Copy to Raspberry Pi

```bash
scp -r ./publish/pi/* user@<pi-ip>:/opt/chatapp/
scp ./scripts/setup-raspberry-pi.sh user@<pi-ip>:~/
```

Replace `<pi-ip>` with your Pi's IP address (e.g., `10.10.10.107`).

### 3. Run Setup Script

SSH into your Pi and run:

```bash
chmod +x ~/setup-raspberry-pi.sh
~/setup-raspberry-pi.sh /opt/chatapp
```

This automatically:
- Creates and configures the `wwwroot/uploads/` directory
- Sets executable permissions on the ChatApp binary
- Sets proper permissions on config files
- Creates database directory

### 4. Start the App

**Option A: Run directly (for testing)**

```bash
cd /opt/chatapp
ASPNETCORE_ENVIRONMENT=Production ./ChatApp
```

App runs on `http://localhost:5103`

**Option B: Run as systemd service (recommended for production)**

```bash
sudo ./setup-systemd-service.sh /opt/chatapp
sudo systemctl start chatapp
```

Then manage with:
```bash
sudo systemctl status chatapp       # Check status
sudo systemctl stop chatapp         # Stop service
sudo systemctl restart chatapp      # Restart
sudo journalctl -u chatapp -f       # View live logs
```

## Configuration

Edit `/opt/chatapp/appsettings.Production.json` to customize:

- **Port**: Change `Kestrel.Endpoints.Http.Url` (default: 5103)
- **Database**: Change `ConnectionStrings.DefaultConnection` (default: `chat.db` in app directory)
- **HTTPS**: Uncomment and configure in `Kestrel.Endpoints.Https` with certificate path

## Accessing the App

- **HTTP**: `http://<pi-ip>:5103`
- **Service status**: `sudo systemctl status chatapp`
- **Logs**: `sudo journalctl -u chatapp -f`

## Troubleshooting

**Port in use / Permission denied error**
- Use port 5103+ (requires no privileges)
- If using ports 80/443, run with `sudo`

**Images not showing (404 errors)**
- Ensure `wwwroot/uploads/` exists with proper permissions
- Run the setup script to fix permissions

**App won't start**
- Check logs: `sudo journalctl -u chatapp -f`
- Verify `appsettings.Production.json` exists
- Ensure database directory is writable

**Database locked**
- Only one instance can use the SQLite database
- Stop any running instances: `sudo systemctl stop chatapp`

## Reverse Proxy (Optional)

For production with domain name and HTTPS, use nginx as a reverse proxy. See [CLAUDE.md](CLAUDE.md) → Nginx Configuration section.
