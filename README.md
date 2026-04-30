# ChatApp

A real-time multi-room chat application built with ASP.NET Core 9, SignalR, Razor Pages, and SQLite. No accounts required — just pick a username and start chatting.

---

## Requirements

- [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9)

---

## Build & Run

### Windows

**Development (run directly):**
```powershell
dotnet run
```
The app starts on `http://localhost:5103` by default.

**Production build:**
```powershell
dotnet publish -c Release -r win-x64 --self-contained -o ./publish/windows
./publish/windows/ChatApp.exe
```

**Run on a custom port:**
```powershell
./publish/windows/ChatApp.exe --urls "http://0.0.0.0:8080"
```

---

### Linux (including Raspberry Pi 5)

**Development (run directly):**
```bash
dotnet run
```

**Production build for Raspberry Pi 5 (ARM64):**
```bash
dotnet publish -c Release -r linux-arm64 --self-contained -o ./publish/pi
```

Copy the `publish/pi` folder to your Pi, then:
```bash
chmod +x ./publish/pi/ChatApp
./publish/pi/ChatApp --urls "http://0.0.0.0:8080"
```

**Production build for standard 64-bit Linux (x64):**
```bash
dotnet publish -c Release -r linux-x64 --self-contained -o ./publish/linux
chmod +x ./publish/linux/ChatApp
./publish/linux/ChatApp --urls "http://0.0.0.0:8080"
```

**Run as a systemd service on the Pi:**

Create `/etc/systemd/system/chatapp.service`:
```ini
[Unit]
Description=ChatApp
After=network.target

[Service]
WorkingDirectory=/home/pi/ChatApp
ExecStart=/home/pi/ChatApp/ChatApp --urls "http://0.0.0.0:8080"
Restart=always
RestartSec=10
User=pi

[Install]
WantedBy=multi-user.target
```

Then enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable chatapp
sudo systemctl start chatapp
```

---

## HTTPS/TLS Setup

### Development with HTTPS

Trust the .NET development certificate (one-time setup):
```bash
dotnet dev-certs https --trust
```

Run with HTTPS enabled:
```bash
dotnet run --launch-profile https
```

The app will be available at `https://localhost:7234` and `http://localhost:5100`.

### Production with HTTPS (Let's Encrypt)

For production deployments, use Let's Encrypt for a free, automated SSL certificate:

**Quick setup with automated script (Linux):**
```bash
sudo ./scripts/setup-letsencrypt-cert.sh example.com /opt/chatapp
```

This script will:
- Install certbot and openssl if needed
- Generate a Let's Encrypt certificate for your domain
- Convert it to PKCS#12 format (.pfx) for .NET
- Set up automatic renewal hooks
- Certificate auto-renews every 60 days

See [CLAUDE.md](CLAUDE.md) for more certificate options and manual setup instructions.

---

## Configuration

### Database

`appsettings.json` controls the database path and logging. The SQLite database file (`chat.db`) is created automatically on first run in the working directory.

To change the database location, edit the connection string:
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Data Source=/data/chat.db"
  }
}
```

### HTTPS Certificate (Production)

For production HTTPS, configure the certificate path in `appsettings.Production.json`:
```json
{
  "Kestrel": {
    "Endpoints": {
      "Https": {
        "Url": "https://0.0.0.0:443"
      }
    },
    "Certificates": {
      "Default": {
        "Path": "/etc/ssl/certs/chatapp.pfx",
        "Password": ""
      }
    }
  }
}
```

See [CLAUDE.md - HTTPS/TLS Setup](CLAUDE.md#httpstls-setup) for detailed instructions.

---

## Production Deployment

### Step 1: Build for your platform

```bash
# Linux x64
dotnet publish -c Release -r linux-x64 --self-contained -o ./publish/linux

# Windows x64
dotnet publish -c Release -r win-x64 --self-contained -o ./publish/windows

# Raspberry Pi (ARM64)
dotnet publish -c Release -r linux-arm64 --self-contained -o ./publish/pi
```

### Step 2: Set up HTTPS certificate

**Option A: Let's Encrypt (Recommended for Linux)**
```bash
# Copy script to server
scp ./scripts/setup-letsencrypt-cert.sh user@example.com:~/

# SSH and run setup
ssh user@example.com
sudo ~/setup-letsencrypt-cert.sh example.com /opt/chatapp
```

**Option B: Self-signed certificate**
```bash
./scripts/create-self-signed-cert.sh example.com ./certs
scp ./certs/chatapp.pfx user@example.com:/etc/ssl/certs/
```

### Step 3: Deploy the application

```bash
# Copy published app to server
scp -r ./publish/linux/* user@example.com:/opt/chatapp/

# SSH and setup
ssh user@example.com

# Set permissions
chmod +x /opt/chatapp/ChatApp
chmod 600 /etc/ssl/certs/chatapp.pfx

# Run the app
cd /opt/chatapp
ASPNETCORE_ENVIRONMENT=Production ./ChatApp
```

### Step 4: Configure as a system service (recommended)

Create `/etc/systemd/system/chatapp.service`:
```ini
[Unit]
Description=ChatApp - Real-time Chat Application
After=network.target

[Service]
Type=simple
User=chatapp
WorkingDirectory=/opt/chatapp
ExecStart=/opt/chatapp/ChatApp
Restart=on-failure
RestartSec=10
Environment="ASPNETCORE_ENVIRONMENT=Production"

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable chatapp
sudo systemctl start chatapp

# Check status
sudo systemctl status chatapp
sudo journalctl -u chatapp -f
```

### Step 5: Use a reverse proxy (recommended for security)

Configure nginx to handle TLS termination and proxy requests to the app:

```nginx
# /etc/nginx/sites-available/chatapp
server {
    listen 80;
    server_name example.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name example.com;

    # Use Let's Encrypt certificates
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://127.0.0.1:5103;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Enable the site:
```bash
sudo ln -s /etc/nginx/sites-available/chatapp /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

With this setup, the app runs on HTTP internally and nginx handles HTTPS/TLS, improving security and making certificate rotation easier.

---

## Project Structure

```
ChatApp/
├── Program.cs                          Entry point. Registers services (EF Core, SignalR,
│                                       Razor Pages), auto-creates the database, and maps routes.
│
├── appsettings.json                    App configuration: database connection string and log levels.
├── appsettings.Development.json        Overrides for local development (more verbose logging).
│
├── ChatApp.csproj                      Project file. Declares .NET 9 target and NuGet packages:
│                                       EF Core + SQLite driver.
│
├── Data/
│   ├── AppDbContext.cs                 EF Core database context. Exposes Rooms and Messages
│   │                                   tables and wires up the SQLite connection.
│   └── Models/
│       ├── Room.cs                     Room entity: Id, Name, CreatedAt.
│       └── Message.cs                  Message entity: Id, RoomId, Username, Content, SentAt.
│
├── Hubs/
│   └── ChatHub.cs                      SignalR hub. Handles three client calls:
│                                       JoinRoom — subscribes a connection to a room's group.
│                                       LeaveRoom — unsubscribes a connection from a room's group.
│                                       SendMessage — saves the message to SQLite, then broadcasts
│                                       it to everyone in the room. Username is read from the
│                                       request cookie server-side.
│
├── Pages/
│   ├── Index.cshtml                    Room list view. Shows a username entry form on first visit;
│   │                                   shows the room grid and "Create room" form once a username
│   │                                   cookie is set.
│   ├── Index.cshtml.cs                 Page model for Index. Handles three actions:
│   │                                   OnGet — loads rooms if username cookie exists.
│   │                                   OnPostSetUsername — validates and saves username to cookie.
│   │                                   OnPostCreateRoom — creates a room if it doesn't exist,
│   │                                   then redirects into it.
│   │                                   OnGetClearUsername — deletes the username cookie.
│   │
│   ├── Chat.cshtml                     Chat room view. Renders the last 100 messages on load,
│   │                                   then connects to the SignalR hub to send and receive
│   │                                   messages in real time. Own messages appear right-aligned
│   │                                   in blue; others appear left-aligned in white.
│   ├── Chat.cshtml.cs                  Page model for Chat. Redirects to Index if no username
│   │                                   cookie, returns 404 if the room doesn't exist, otherwise
│   │                                   loads the room and its recent messages.
│   │
│   ├── _ViewImports.cshtml             Imports tag helpers and sets the default namespace for
│   │                                   all Razor pages.
│   ├── _ViewStart.cshtml               Sets _Layout as the default layout for all pages.
│   │
│   └── Shared/
│       ├── _Layout.cshtml              Shared HTML shell: navbar with app title, Bootstrap CSS/JS,
│       │                               jQuery, and the Scripts section placeholder used by Chat.
│       └── _ValidationScriptsPartial.cshtml  jQuery validation scripts, included on form pages.
│
├── wwwroot/
│   ├── css/
│   │   └── site.css                   All custom styles: username screen, room cards, full-height
│   │                                   chat layout, message bubbles (own vs others).
│   ├── js/
│   │   └── site.js                    Global JS stub (empty by default).
│   └── lib/
│       ├── bootstrap/                 Bootstrap 5 — CSS framework for layout and components.
│       ├── jquery/                    jQuery — required by Bootstrap and validation scripts.
│       ├── jquery-validation/         Client-side form validation library.
│       ├── jquery-validation-unobtrusive/  ASP.NET integration for unobtrusive validation.
│       └── microsoft-signalr/         SignalR browser client used by Chat.cshtml to connect
│                                       to the hub over WebSockets.
│
└── Properties/
    └── launchSettings.json            Local dev launch profiles (ports, environment variables).
                                        Not used in production builds.
```

---

## How it works

1. **Username** is stored in a browser cookie (1-year expiry). No passwords or accounts.
2. **Rooms** are created on demand from the Index page. Creating a room with a name that already exists redirects into the existing room.
3. **Messages** are saved to SQLite on the server by the SignalR hub, then broadcast to all connections in that room's group. The last 100 messages are loaded from the database when you open a room.
4. **Real-time** delivery uses SignalR WebSockets with automatic reconnect. If the WebSocket connection is unavailable, SignalR falls back to long-polling automatically.
