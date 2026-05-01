# Implementation Details

This document provides detailed information about key implementation aspects of the ChatApp application.

## Table of Contents

1. [Page Model Methods (Chat.cshtml.cs)](#page-model-methods-chatcstmlcs)
2. [Photo Upload Process](#photo-upload-process)
3. [SignalR Hub Methods](#signalr-hub-methods)
4. [File Storage Locations](#file-storage-locations)
5. [HTTPS Configuration](#https-configuration)

---

## Page Model Methods (Chat.cshtml.cs)

The [Pages/Chat.cshtml.cs](Pages/Chat.cshtml.cs) file contains two public page model methods that handle HTTP requests for the chat room view.

### OnGetAsync(int id)

**Method signature:** `public async Task<IActionResult> OnGetAsync(int id)`

**Called by:** Razor Pages framework when a GET request is made to `/Chat/{id}`

**Entry points:**
- Browser navigation (user clicks a room link from the Index page)
- Direct URL entry: `http://localhost:5100/Chat/1`
- Link from [Pages/Index.cshtml](Pages/Index.cshtml)

**What it does:**
1. Reads the `ChatUsername` cookie from the request
2. Redirects to `/Index` if no username cookie exists (user not logged in)
3. Loads the room by ID from the database
4. Returns 404 if room not found
5. Loads the last 100 messages for the room ordered by send time
6. Returns the page with `Room` and `RecentMessages` populated for display

**Data passed to view:**
- `Room` — Room entity with Id and Name
- `RecentMessages` — List of Message entities to display in chat history
- `Username` — Current logged-in user from cookie

### OnPostUploadPhotoAsync(int id, IFormFile photo)

**Method signature:** `public async Task<IActionResult> OnPostUploadPhotoAsync(int id, IFormFile photo)`

**Called by:** Client-side JavaScript fetch request to `/Chat/{id}?handler=UploadPhoto` (POST)

**Entry point:** [Chat.cshtml:174](Pages/Chat.cshtml#L174)
```javascript
const response = await fetch(`/Chat/${roomId}?handler=UploadPhoto`, {
    method: "POST",
    body: formData
});
```

**Triggered by:** File input change event ([Chat.cshtml:149](Pages/Chat.cshtml#L149)) when user selects an image

**What it does:**
1. Validates username cookie exists (returns 401 Unauthorized if missing)
2. Validates room exists (returns 404 Not Found if missing)
3. Validates file is provided and not empty
4. Validates file size does not exceed 5 MB
5. Validates file extension is in allowed list: `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`
6. Validates MIME type matches allowed types: `image/jpeg`, `image/png`, `image/gif`, `image/webp`
7. Creates `/wwwroot/uploads/` directory if it doesn't exist
8. Generates a unique filename using GUID: `{Guid}{extension}`
9. Saves the file to disk
10. Returns JSON response with the file path: `{ imagePath: "/uploads/{GUID}.ext" }`

**Return values:**
- `200 OK` with JSON: `{ imagePath: "/uploads/..." }`
- `400 Bad Request` — invalid file or no file provided
- `401 Unauthorized` — no username cookie
- `404 Not Found` — room doesn't exist

---

## Photo Upload Process

Photo uploading is a multi-step process involving client-side validation, server-side file handling, and SignalR message broadcasting.

### Stage 1: Client-side File Selection and Upload

**Code location:** [Chat.cshtml:149-190](Pages/Chat.cshtml#L149-L190)

**User flow:**
1. User clicks the 📷 button (file input label) or selects a file from the file picker
2. JavaScript file change event handler is triggered

**Validation and preview:**
```javascript
photoInput.addEventListener("change", async () => {
    const file = photoInput.files[0];
    
    // Validate file type
    const allowedTypes = ["image/jpeg", "image/png", "image/gif", "image/webp"];
    if (!allowedTypes.includes(file.type)) {
        alert("Only JPG, PNG, GIF, and WebP images are supported.");
        return;
    }
    
    // Validate file size (5 MB = 5,242,880 bytes)
    if (file.size > 5 * 1024 * 1024) {
        alert("Image must be 5 MB or smaller.");
        return;
    }
    
    // Display preview immediately
    pendingObjectUrl = URL.createObjectURL(file);
    imagePreview.src = pendingObjectUrl;
    imagePreviewArea.style.display = "flex";
    
    // Upload file to server
    const formData = new FormData();
    formData.append("photo", file);
    
    const response = await fetch(`/Chat/${roomId}?handler=UploadPhoto`, {
        method: "POST",
        body: formData
    });
    
    // Store returned image path for later use
    const data = await response.json();
    pendingImagePath = data.imagePath;
});
```

**Key variables:**
- `pendingImagePath` — path returned from server, used when sending the message
- `pendingObjectUrl` — blob URL for preview image, revoked after message send

**Remove image button:**
- User can click the ✕ button to clear the pending image
- Calls `clearImage()` which revokes the object URL and resets state ([Chat.cshtml:192](Pages/Chat.cshtml#L192))

### Stage 2: Server-side File Handling

**Code location:** [Pages/Chat.cshtml.cs:36-71](Pages/Chat.cshtml.cs#L36-L71)

**Validation steps:**
1. Username cookie must exist
2. Room must exist in database
3. File must be provided and not empty
4. File size must not exceed 5 MB
5. File extension must be `.jpg`, `.jpeg`, `.png`, `.gif`, or `.webp`
6. MIME type must match: `image/jpeg`, `image/png`, `image/gif`, or `image/webp`

**File storage:**
1. Directory created: `{WebRootPath}/uploads/` (creates if doesn't exist)
2. Filename generated: `{Guid}.{extension}` (random unique name)
3. File saved: `{uploadsDir}/{fileName}`
4. Path returned: `/uploads/{fileName}`

**Response:**
```json
{
  "imagePath": "/uploads/550e8400-e29b-41d4-a716-446655440000.jpg"
}
```

### Stage 3: Send Message with Image

**Code location:** [Chat.cshtml:194-208](Pages/Chat.cshtml#L194-L208)

**User flow:**
1. User types optional message text
2. User clicks Send button OR presses Enter (without Shift)
3. `sendMessage()` function is invoked

**Message sending:**
```javascript
async function sendMessage() {
    const content = input.value.trim();
    
    // Require either text content or image
    if (!content && !pendingImagePath) return;
    
    // Check SignalR connection is active
    if (connection.state !== signalR.HubConnectionState.Connected) return;
    
    // Prepare for send
    const imagePathToSend = pendingImagePath;
    input.value = "";
    clearImage(); // Reset file input and preview
    
    // Send to hub
    try {
        await connection.invoke("SendMessage", roomId, content || null, imagePathToSend);
    } catch (e) {
        console.error(e);
    }
}
```

**Hub invocation:**
- Calls `SendMessage` hub method with:
  - `roomId` — current room
  - `content` — text message (can be null)
  - `imagePathToSend` — file path from upload (can be null)

### Summary Flow

```
┌─ User selects file
│
├─ Client validates file (type, size)
│
├─ Client uploads to /Chat/{id}?handler=UploadPhoto (POST)
│
├─ Server validates file and saves to wwwroot/uploads/
│
├─ Server returns imagePath: "/uploads/{GUID}.ext"
│
├─ Client displays preview
│
├─ User clicks Send
│
├─ Client invokes SendMessage hub method with imagePath
│
├─ Hub validates imagePath (must start with /uploads/, no ..)
│
├─ Hub saves Message to database with imagePath
│
├─ Hub broadcasts message to room group
│
└─ All clients receive ReceiveMessage event and display message
```

---

## SignalR Hub Methods

The [Hubs/ChatHub.cs](Hubs/ChatHub.cs) file contains three public methods that handle real-time communication between clients.

### Hub Connection Setup

**Code location:** [Chat.cshtml:72-75](Pages/Chat.cshtml#L72-L75)

```javascript
const connection = new signalR.HubConnectionBuilder()
    .withUrl("/chathub")
    .withAutomaticReconnect()
    .build();
```

**Configuration:**
- Hub URL: `/chathub` (mapped in [Program.cs](Program.cs))
- Auto-reconnect: Enabled with exponential backoff
- Transport: WebSocket primary, with long-polling fallback

### JoinRoom(int roomId)

**Hub method:** `public async Task JoinRoom(int roomId)`

**Called from:** [Chat.cshtml:228](Pages/Chat.cshtml#L228)
```javascript
connection.invoke("JoinRoom", roomId)
```

**When:** Automatically when SignalR connection is established

**What it does:**
1. Adds the connection to a SignalR group named `room_{roomId}`
2. Enables the hub to broadcast messages to all connections in that room

**Used by:** Server-side broadcasting in `SendMessage` method

### LeaveRoom(int roomId)

**Hub method:** `public async Task LeaveRoom(int roomId)`

**Called from:** [Chat.cshtml:212](Pages/Chat.cshtml#L212)
```javascript
await connection.invoke("LeaveRoom", roomId);
```

**Triggered by:** Click event on "← Rooms" button ([Chat.cshtml:218](Pages/Chat.cshtml#L218))

**When:** User clicks the back button to leave the chat room

**What it does:**
1. Removes the connection from the `room_{roomId}` group
2. Prevents the connection from receiving future messages for that room

### SendMessage(int roomId, string? content, string? imagePath = null)

**Hub method:** `public async Task SendMessage(int roomId, string? content, string? imagePath = null)`

**Called from:** [Chat.cshtml:204](Pages/Chat.cshtml#L204)
```javascript
await connection.invoke("SendMessage", roomId, content || null, imagePathToSend);
```

**Triggered by:** Send button click or Enter key press ([Chat.cshtml:219-225](Pages/Chat.cshtml#L219-L225))

**What it does:**

1. **Validation:**
   - At least one of `content` or `imagePath` must be provided
   - If imagePath provided, must be valid (starts with `/uploads/`, no `..`, has filename)

2. **Message creation:**
   - Reads username from `ChatUsername` cookie
   - Creates new Message entity with:
     - `RoomId` — current room
     - `Username` — from cookie (defaults to "Anonymous")
     - `Content` — text message (can be null)
     - `ImagePath` — file path (can be null)
     - `SentAt` — DateTime.UtcNow

3. **Database persistence:**
   - Adds message to `db.Messages`
   - Saves to database

4. **Broadcasting:**
   - Sends `ReceiveMessage` event to all clients in `room_{roomId}` group
   - Broadcasts:
     - `message.Username` — sender name
     - `message.Content` — text (can be null)
     - `message.SentAt.ToString("HH:mm")` — formatted time
     - `message.ImagePath` — file path (can be null)

**Client-side handler:** [Chat.cshtml:147](Pages/Chat.cshtml#L147)
```javascript
connection.on("ReceiveMessage", appendMessage);
```

Calls the `appendMessage(user, content, time, imagePath)` function which:
- Creates a new message DOM element
- Adds text content if provided
- Adds image element if imagePath provided
- Attaches click handler to open image in modal
- Auto-scrolls chat to bottom

---

## File Storage Locations

Photos are stored in the `wwwroot/uploads/` directory within the published application. The exact location depends on the deployment platform and where the app is deployed.

### Development Environment

```
c:\Users\{username}\Documents\workspace\claude\ChatApp\wwwroot\uploads\{GUID}.jpg
```

### Published Locations

#### Windows (x64)

**During development (build output):**
```
.\publish\windows\wwwroot\uploads\
```

**After deployment:**
```
C:\path\to\deployment\ChatApp\wwwroot\uploads\{GUID}.jpg
```

**Example paths:**
- `C:\Program Files\ChatApp\wwwroot\uploads\550e8400-e29b-41d4-a716-446655440000.jpg`
- `C:\opt\chatapp\wwwroot\uploads\550e8400-e29b-41d4-a716-446655440000.png`

#### Linux x64

**During build:**
```
./publish/linux/wwwroot/uploads/
```

**After deployment (if deployed to `/opt/chatapp`):**
```
/opt/chatapp/wwwroot/uploads/{GUID}.jpg
```

**Example paths:**
- `/opt/chatapp/wwwroot/uploads/550e8400-e29b-41d4-a716-446655440000.jpg`
- `/var/www/chatapp/wwwroot/uploads/550e8400-e29b-41d4-a716-446655440000.png`

#### Raspberry Pi (ARM64)

**During build:**
```
./publish/pi/wwwroot/uploads/
```

**After deployment (if deployed to `/opt/chatapp`):**
```
/opt/chatapp/wwwroot/uploads/{GUID}.jpg
```

**Note:** Raspberry Pi storage is typically limited (SD card); consider implementing photo cleanup or archival for long-running instances.

### Storage Considerations

**Directory creation:** The `uploads` directory is created automatically at runtime if it doesn't exist ([Chat.cshtml.cs:60](Pages/Chat.cshtml.cs#L60))

**File naming:** Files use GUID-based names to ensure uniqueness:
```
{Guid}.{extension}
```

Example: `550e8400-e29b-41d4-a716-446655440000.jpg`

**Disk space:** 
- Each photo upload uses the file size (up to 5 MB)
- No automatic cleanup; old photos remain on disk indefinitely
- Consider implementing periodic cleanup or archival for production deployments

**Permissions:**
- The user running the application must have read/write access to the `uploads` directory
- Typical setup: application user owns the directory with 755 permissions

**Access:** Files are served as static assets via the `/uploads/` URL path

---

## HTTPS Configuration

The application supports both development and production HTTPS configurations.

### Development HTTPS Setup

**First-time setup (trust the development certificate):**

```bash
dotnet dev-certs https --trust
```

This creates and trusts the .NET development certificate on your machine.

**Run with HTTPS:**

```bash
dotnet run --launch-profile https
```

**Result:**
- App runs on `https://localhost:7234` (HTTPS)
- Also accessible on `http://localhost:5100` (HTTP)

**Configuration files:**
- Profile: [Properties/launchSettings.json](Properties/launchSettings.json)
- Settings: [appsettings.Development.json](appsettings.Development.json)

### Production HTTPS Setup

For production, you need to obtain or generate a certificate and configure it in [appsettings.Production.json](appsettings.Production.json).

#### Option 1: Let's Encrypt (Recommended for Linux)

**Setup automated certificate:**

```bash
# Linux x64 (requires sudo)
sudo ./scripts/setup-letsencrypt-cert.sh example.com /opt/chatapp
```

**What the script does:**
- Installs certbot and openssl if needed
- Generates a Let's Encrypt certificate for your domain
- Converts it to PKCS#12 format (.pfx) for .NET
- Sets up automatic renewal hooks
- Certificate auto-renews every 60 days

**Configuration:**
The script outputs the certificate path to use in `appsettings.Production.json`.

#### Option 2: Self-signed Certificate (Testing/Internal)

**Linux/macOS using OpenSSL:**

```bash
./scripts/create-self-signed-cert.sh example.com ./certs
```

**Windows using PowerShell:**

```powershell
.\scripts\create-self-signed-cert.ps1 -Domain example.com -OutputDir .\certs
```

**Result:** Generates `chatapp.pfx` file

**Note:** Self-signed certificates work for internal testing but browsers will show security warnings. Use only for development or internal deployments.

#### Option 3: Certificate from Certificate Authority

For production, you can also use a certificate from a trusted CA:
- DigiCert
- Your organization's internal CA
- CloudFlare Origin Certificates
- GoDaddy, Sectigo, etc.

**Export your CA-issued certificate as PKCS#12 (.pfx) file.**

### Configure Certificate in appsettings.Production.json

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

**Configuration options:**
- **Path:** Absolute path where the `.pfx` file is stored
- **Password:** Certificate password (leave empty if no password set during export)
- **Http URL:** Listening address and port for HTTP (typically 80)
- **Https URL:** Listening address and port for HTTPS (typically 443)

### Deployment with HTTPS (Let's Encrypt on Linux)

```bash
# 1. Build and publish
dotnet publish -c Release -r linux-x64 --self-contained -o ./publish/linux

# 2. Copy app to server
scp -r ./publish/linux/* user@example.com:/opt/chatapp/

# 3. Copy certificate setup script
scp ./scripts/setup-letsencrypt-cert.sh user@example.com:~/

# 4. SSH to server and setup certificate
ssh user@example.com
sudo ~/setup-letsencrypt-cert.sh example.com /opt/chatapp

# 5. The script outputs the certificate path — update appsettings.Production.json with it

# 6. Set permissions and run
chmod +x /opt/chatapp/ChatApp
cd /opt/chatapp && ASPNETCORE_ENVIRONMENT=Production ./ChatApp
```

### Deployment with Manual Certificate (Windows/Linux)

```bash
# 1. Copy certificate to the server
scp ./certs/chatapp.pfx user@example.com:/etc/ssl/certs/

# 2. Copy app and configuration
scp -r ./publish/linux/* user@example.com:/opt/chatapp/

# 3. Set file permissions
ssh user@example.com "chmod 600 /etc/ssl/certs/chatapp.pfx"
ssh user@example.com "chmod +x /opt/chatapp/ChatApp"

# 4. Run the app (picks up appsettings.Production.json automatically)
ssh user@example.com "cd /opt/chatapp && ASPNETCORE_ENVIRONMENT=Production ./ChatApp"
```

### Nginx Reverse Proxy with HTTPS (Recommended)

Use Nginx to handle HTTPS/TLS termination while the app runs on HTTP internally.

**Nginx configuration:**

```nginx
# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name example.com;
    return 301 https://$server_name$request_uri;
}

# HTTPS server with TLS termination
server {
    listen 443 ssl http2;
    server_name example.com;

    # Certificate paths
    ssl_certificate /etc/ssl/certs/example.crt;
    ssl_certificate_key /etc/ssl/private/example.key;
    
    # TLS configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Proxy to internal HTTP app
    location / {
        proxy_pass http://localhost:5103;
        proxy_http_version 1.1;
        
        # Required for WebSocket (SignalR)
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Pass original request info
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**App configuration:**

In this setup, configure the app to listen on HTTP only:

```json
{
  "Kestrel": {
    "Endpoints": {
      "Http": {
        "Url": "http://localhost:5103"
      }
    }
  }
}
```

**Benefits:**
- TLS termination handled by Nginx (lighter load on app)
- Easier certificate rotation
- Better security isolation
- Better performance and caching options

### Certificate Renewal

**Let's Encrypt (automatic):**
- Script sets up renewal hooks
- Certificate auto-renews every 60 days
- No manual action required

**Manual certificates:**
- Monitor expiration date
- Renew before expiration
- Restart application after replacing certificate file

**Check certificate expiration:**

```bash
# Linux/macOS
openssl pkcs12 -in chatapp.pfx -noout -info | grep -A1 "Issuer\|Subject"

# Or use ASP.NET CLI
dotnet user-secrets show
```

---

## Summary

This implementation provides a secure, scalable chat application with:

- **Real-time messaging** via SignalR
- **Photo sharing** with client and server validation
- **Persistent storage** using SQLite
- **HTTPS support** for both development and production
- **Cross-platform deployment** (Windows, Linux, Raspberry Pi)
- **File uploads** with security validation and unique naming

For more information, see [CLAUDE.md](CLAUDE.md) for architecture overview and deployment instructions.
