# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Start

**Development (HTTP):**
```bash
dotnet run
# App runs on http://localhost:5100
```

**Development (HTTPS):**
```bash
dotnet run --launch-profile https
# App runs on https://localhost:7234 (and http://localhost:5100)
# First time: dotnet dev-certs https --trust
```

**Build for production:**
```bash
# Windows (x64)
dotnet publish -c Release -r win-x64 --self-contained -o ./publish/windows

# Linux x64
dotnet publish -c Release -r linux-x64 --self-contained -o ./publish/linux

# Raspberry Pi 5 (ARM64)
dotnet publish -c Release -r linux-arm64 --self-contained -o ./publish/pi
```

The project targets **.NET 9** and requires the .NET 9 SDK.

## Architecture Overview

ChatApp is a real-time multi-room chat application with three main layers:

### Backend Architecture

**SignalR Hub (Real-time Communication)**
- [Hubs/ChatHub.cs](Hubs/ChatHub.cs) — handles three client calls:
  - `JoinRoom(roomId)` — subscribes connection to a room's group
  - `LeaveRoom(roomId)` — unsubscribes from a room's group
  - `SendMessage(roomId, content)` — persists message and broadcasts to room group
- Uses SignalR groups for efficient room-based broadcasting
- Username is read server-side from the `ChatUsername` request cookie

**Database Layer (EF Core + SQLite)**
- [Data/AppDbContext.cs](Data/AppDbContext.cs) — EF Core context; manages two entities
- [Data/Models/Room.cs](Data/Models/Room.cs) — Room: Id, Name, CreatedAt
- [Data/Models/Message.cs](Data/Models/Message.cs) — Message: Id, RoomId, Username, Content, SentAt
- Database auto-created on first run via `EnsureCreated()` in [Program.cs](Program.cs)
- SQLite connection string controlled in [appsettings.json](appsettings.json)

**Request Pipeline**
- [Program.cs](Program.cs) — registers services (EF Core, SignalR, Razor Pages), configures middleware, maps routes
- SignalR hub mapped at `/chathub`
- Razor Pages and static assets mapped with `MapRazorPages().WithStaticAssets()`

### Frontend Architecture

**Razor Pages**
- [Pages/Index.cshtml](Pages/Index.cshtml) — room list view; shows username entry on first visit, room grid after
  - [Pages/Index.cshtml.cs](Pages/Index.cshtml.cs) — page model with:
    - `OnGet()` — loads rooms if username cookie exists
    - `OnPostSetUsername()` — validates and saves username to cookie (1-year expiry)
    - `OnPostCreateRoom()` — creates room or redirects to existing one
    - `OnGetClearUsername()` — deletes username cookie
- [Pages/Chat.cshtml](Pages/Chat.cshtml) — chat room view; renders last 100 messages, connects to SignalR hub for real-time updates
  - [Pages/Chat.cshtml.cs](Pages/Chat.cshtml.cs) — page model for chat room
    - `OnGetAsync(int id)` — GET handler; loads room by id and its message history; redirects to Index if no username cookie; returns 404 if room not found; populates RecentMessages list ordered by send time
    - `OnPostUploadPhotoAsync(int id, IFormFile photo)` — POST handler for image uploads; validates username cookie exists, room exists, file size (≤5 MB), and file type (JPG, PNG, GIF, WebP); saves file to `/wwwroot/uploads/` with GUID filename; returns JSON with `/uploads/` relative path
  - Client-side JavaScript methods in `<script>` section:
    - `escapeHtml(text)` — sanitizes user input by converting text to HTML entities, prevents XSS attacks
    - `clearImage()` — clears pending image upload state, revokes object URL, hides preview area, resets file input
    - `appendMessage(user, content, time, imagePath)` — dynamically adds a new message to the chat display; creates DOM element with metadata and content; handles both text and image messages; auto-scrolls to bottom; attaches image click handlers
    - `openImageModal(imagePath)` — opens Bootstrap modal displaying full-size image from given path
    - `attachImageClickHandlers()` — attaches click event listeners to all clickable chat images to open the image modal
    - `sendMessage()` — sends message to SignalR hub with optional text content and/or image; validates connection state; clears input and pending image state after send
    - `leaveRoom()` — invokes SignalR `LeaveRoom` method to unsubscribe connection from current room group

**Layout & Styling**
- [Pages/Shared/_Layout.cshtml](Pages/Shared/_Layout.cshtml) — shared HTML shell with navbar, Bootstrap, jQuery
- [wwwroot/css/site.css](wwwroot/css/site.css) — custom styles: username screen, room cards, chat layout, message bubbles
- Bootstrap 5 and jQuery in `wwwroot/lib/` for layout and client-side form validation

**SignalR Client**
- [wwwroot/lib/microsoft-signalr/](wwwroot/lib/microsoft-signalr/) — SignalR JavaScript client (connects to `/chathub`)
- Connection logic and message rendering embedded in Chat.cshtml `<script>` section

## Key Design Patterns

1. **No Authentication** — Username stored in browser cookie, no accounts or passwords
2. **SignalR Groups** — Each room maps to a group (`room_{roomId}`) for efficient broadcasting
3. **Last N Messages** — Chat.cshtml loads last 100 messages on page load, then receives new ones via SignalR
4. **Auto-reconnect** — SignalR automatically reconnects on disconnect; falls back to long-polling if WebSocket unavailable
5. **Simple Data Model** — Only two entities (Room, Message); EF Core DbSet auto-tracked

## Configuration

- **Connection String** — controlled by [appsettings.json](appsettings.json) → `ConnectionStrings.DefaultConnection`
  - Default: `Data Source=chat.db` (file in working directory)
  - Can be overridden in [appsettings.Development.json](appsettings.Development.json) for local dev
- **Logging** — controlled in [appsettings.json](appsettings.json) → `Logging` section
- **Launch Settings** — local dev profiles in [Properties/launchSettings.json](Properties/launchSettings.json) (not used in production)

## HTTPS/TLS Setup

### Development with HTTPS

The app is pre-configured to support HTTPS in development using the .NET development certificate:

**First time setup (trust the dev certificate):**
```bash
dotnet dev-certs https --trust
```

**Run with HTTPS:**
```bash
dotnet run --launch-profile https
# App runs on https://localhost:7234 and http://localhost:5100
```

The HTTPS profile is configured in [Properties/launchSettings.json](Properties/launchSettings.json) and [appsettings.Development.json](appsettings.Development.json).

### Production with HTTPS

For production, you need to obtain or generate a certificate and configure it in [appsettings.Production.json](appsettings.Production.json).

**Option 1: Let's Encrypt (Recommended)**

Use the automated Let's Encrypt setup script:

```bash
# Linux x64 (requires sudo)
sudo ./scripts/setup-letsencrypt-cert.sh example.com /opt/chatapp
```

This script will:
- Install certbot and openssl if needed
- Generate a Let's Encrypt certificate for your domain
- Convert it to PKCS#12 format (.pfx) for .NET
- Set up automatic renewal hooks
- Certificate auto-renews every 60 days

**Windows users:** Let's Encrypt works best on Linux servers. For Windows development/testing, use self-signed certificates instead.

**Option 2: Self-signed Certificate (testing/internal only)**

```bash
# Linux/macOS using OpenSSL
./scripts/create-self-signed-cert.sh example.com ./certs

# Windows using PowerShell
.\scripts\create-self-signed-cert.ps1 -Domain example.com -OutputDir .\certs
```

This generates `chatapp.pfx` which is the certificate file needed for .NET.

**Option 3: Certificate from Certificate Authority**

For production, you can also use a certificate from a trusted CA such as:
- [DigiCert](https://www.digicert.com/)
- Your organization's internal CA
- [CloudFlare Origin Certificates](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)

Export your CA-issued certificate as a PKCS#12 (.pfx) file.

**Configure the certificate path:**

Edit [appsettings.Production.json](appsettings.Production.json):
```json
{
  "Kestrel": {
    "Endpoints": {
      "Http": {
        "Url": "http://0.0.0.0:80"
      },
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

- **Path**: Absolute path where the `.pfx` file is stored
- **Password**: Certificate password (leave empty if no password was set during export)

**Deployment with HTTPS (Let's Encrypt):**

```bash
# 1. Publish the app
dotnet publish -c Release -r linux-x64 --self-contained -o ./publish/linux

# 2. Copy app to server
scp -r ./publish/linux/* user@example.com:/opt/chatapp/

# 3. Copy certificate setup script
scp ./scripts/setup-letsencrypt-cert.sh user@example.com:~/

# 4. SSH to server and setup certificate
ssh user@example.com
sudo ~/setup-letsencrypt-cert.sh example.com /opt/chatapp

# 5. Update appsettings.Production.json with certificate path
# The script outputs the path to use

# 6. Set permissions and run
chmod +x /opt/chatapp/ChatApp
cd /opt/chatapp && ASPNETCORE_ENVIRONMENT=Production ./ChatApp
```

**Manual deployment (if you already have a certificate):**

```bash
# Copy certificate to the server
scp ./certs/chatapp.pfx user@example.com:/etc/ssl/certs/

# Copy app and appsettings.Production.json
scp -r ./publish/linux/* user@example.com:/opt/chatapp/

# Set permissions
ssh user@example.com "chmod 600 /etc/ssl/certs/chatapp.pfx"
ssh user@example.com "chmod +x /opt/chatapp/ChatApp"

# Run the app (picks up appsettings.Production.json automatically)
ssh user@example.com "cd /opt/chatapp && ASPNETCORE_ENVIRONMENT=Production ./ChatApp"
```

**Nginx reverse proxy with HTTPS (recommended):**

```nginx
server {
    listen 80;
    server_name example.com;
    return 301 https://$server_name$request_uri;  # Redirect HTTP to HTTPS
}

server {
    listen 443 ssl http2;
    server_name example.com;

    ssl_certificate /etc/ssl/certs/example.crt;
    ssl_certificate_key /etc/ssl/private/example.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://localhost:5103;
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

In this setup, app runs on HTTP internally (port 5103) and nginx handles the HTTPS/TLS termination.

## Deployment

### Prerequisites

- Target system must have the matching runtime or .NET 9 SDK installed (not needed for self-contained builds)
- For SQLite database, ensure the directory where `chat.db` will be stored is writable
- Port 5103 (or configured port) must be available and accessible

### Platform-Specific Deployment

**Windows (x64):**
```bash
# Publish self-contained (includes .NET runtime)
dotnet publish -c Release -r win-x64 --self-contained -o ./publish/windows

# Run the app
./publish/windows/ChatApp.exe
# App runs on http://localhost:5103
```

**Linux (x64):**
```bash
# Publish self-contained
dotnet publish -c Release -r linux-x64 --self-contained -o ./publish/linux

# Copy to server and run
chmod +x ./ChatApp
./ChatApp
# App runs on http://localhost:5103
```

**Raspberry Pi (ARM64):**
```bash
# Publish from development machine with cross-compilation
dotnet publish -c Release -r linux-arm64 --self-contained -o ./publish/pi

# Copy to Pi and run
chmod +x ./ChatApp
./ChatApp
# App runs on http://localhost:5103
```

### Production Configuration

1. **Environment Setup**
   - Create `appsettings.Production.json` in the same directory as the executable
   - Override connection string, logging, HTTPS certificate, and other settings as needed:
   ```json
   {
     "ConnectionStrings": {
       "DefaultConnection": "Data Source=/var/lib/chatapp/chat.db"
     },
     "Logging": {
       "LogLevel": {
         "Default": "Information"
       }
     },
     "Kestrel": {
       "Endpoints": {
         "Http": {
           "Url": "http://0.0.0.0:80"
         },
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
   - See [HTTPS/TLS Setup](#httpstls-setup) section above for certificate configuration

2. **Database Preparation**
   - On first run, the app automatically creates the database if it doesn't exist
   - Ensure the directory where `chat.db` will be stored has proper permissions (user running the app must be able to write)
   - For persistent storage, use an absolute path in the connection string

3. **Port Configuration**
   - Default port is 5103; configure via environment variables or `appsettings.json`:
   ```json
   {
     "Kestrel": {
       "Endpoints": {
         "Http": {
           "Url": "http://0.0.0.0:8080"
         }
       }
     }
   }
   ```

4. **Reverse Proxy Setup (Recommended)**
   - Use nginx, Apache, or IIS as a reverse proxy for better security and performance
   - Example nginx configuration:
   ```nginx
   server {
       listen 80;
       server_name example.com;

       location / {
           proxy_pass http://localhost:5103;
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

5. **Running as a Service (Linux/systemd)**
   - Create `/etc/systemd/system/chatapp.service`:
   ```ini
   [Unit]
   Description=ChatApp Service
   After=network.target

   [Service]
   Type=simple
   User=chatapp
   WorkingDirectory=/opt/chatapp
   ExecStart=/opt/chatapp/ChatApp
   Restart=on-failure
   RestartSec=10

   [Install]
   WantedBy=multi-user.target
   ```
   - Enable and start:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable chatapp
   sudo systemctl start chatapp
   ```

6. **Windows Service (Optional)**
   - Use tools like `sc.exe` or NSSM (Non-Sucking Service Manager) to run as a Windows service
   - Example with NSSM:
   ```bash
   nssm install ChatApp "C:\path\to\ChatApp.exe"
   nssm start ChatApp
   ```

### Troubleshooting

- **Port already in use:** Change the port in `appsettings.json` or kill the process using the port
- **Database locked:** Ensure only one instance is running; multiple instances sharing the same SQLite file can cause locking issues
- **SignalR connection failures:** Check firewall rules, ensure WebSocket support is enabled in reverse proxy, verify CORS settings if needed
- **Database file permissions:** Ensure the user running the app has read/write access to the database directory

## Common Tasks

**Add a new SignalR method:**
1. Add method to [ChatHub.cs](Hubs/ChatHub.cs)
2. Call from Chat.cshtml using `connection.invoke("MethodName", args)`

**Modify the data model:**
1. Update entity in [Data/Models/](Data/Models/)
2. If adding a migration (optional — `EnsureCreated()` handles schema on first run), run `dotnet ef migrations add YourMigrationName`
3. Apply with `dotnet ef database update`

**Style changes:**
1. Edit [wwwroot/css/site.css](wwwroot/css/site.css) for custom styles
2. Bootstrap classes used in Razor views can be customized via CSS overrides

**Change database location:**
Edit the connection string in [appsettings.json](appsettings.json):
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Data Source=/path/to/chat.db"
  }
}
```

## Technology Stack

- **Runtime:** .NET 9
- **Web Framework:** ASP.NET Core (Razor Pages)
- **Real-time Communication:** SignalR (WebSockets with long-polling fallback)
- **Data Access:** Entity Framework Core 9
- **Database:** SQLite
- **Frontend CSS:** Bootstrap 5
- **Client-side JS:** jQuery, SignalR JavaScript client
