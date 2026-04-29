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

## Configuration

`appsettings.json` controls the database path and logging. The SQLite database file (`chat.db`) is created automatically on first run in the working directory.

To change the database location, edit the connection string:
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Data Source=/data/chat.db"
  }
}
```

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
