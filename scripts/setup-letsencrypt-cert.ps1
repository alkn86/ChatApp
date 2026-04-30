# Setup Let's Encrypt certificate using certbot on WSL or PowerShell
# Usage: .\setup-letsencrypt-cert.ps1 -Domain example.com -AppDir C:\opt\chatapp

param(
    [Parameter(Mandatory=$true)]
    [string]$Domain,

    [Parameter(Mandatory=$false)]
    [string]$AppDir = "C:\opt\chatapp",

    [Parameter(Mandatory=$false)]
    [string]$Email = "admin@$Domain"
)

$CertDir = "$AppDir\certs"
$PFXPath = "$CertDir\chatapp.pfx"

Write-Host "========================================"
Write-Host "Let's Encrypt Certificate Setup (Windows)"
Write-Host "========================================"
Write-Host "Domain: $Domain"
Write-Host "Email: $Email"
Write-Host "App Directory: $AppDir"
Write-Host "Certificate Path: $PFXPath"
Write-Host ""

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "WARNING: This script works best when run as Administrator" -ForegroundColor Yellow
    Write-Host "For full functionality, run in an elevated PowerShell prompt or WSL2"
    Write-Host ""
}

# Create certificate directory
New-Item -ItemType Directory -Path $CertDir -Force | Out-Null
Write-Host "✓ Created certificate directory: $CertDir"

# Check if certbot is available (via WSL or installed)
$certbotAvailable = $false
try {
    $certbotVersion = & wsl certbot --version 2>$null
    $certbotAvailable = $?
    if ($certbotAvailable) {
        Write-Host "✓ Found certbot in WSL: $certbotVersion"
    }
}
catch {
    $certbotAvailable = $false
}

if (-not $certbotAvailable) {
    Write-Host ""
    Write-Host "certbot not found in WSL. Options:"
    Write-Host "  1. Use WSL2 with Ubuntu and run this script with 'wsl bash setup-letsencrypt-cert.sh'"
    Write-Host "  2. Use IIS with URL Rewrite to front .NET app and configure HTTPS there"
    Write-Host "  3. Use nginx on WSL2 as reverse proxy"
    Write-Host ""
    Write-Host "For now, you can generate a self-signed certificate with:"
    Write-Host "  .\create-self-signed-cert.ps1 -Domain $Domain -OutputDir $CertDir"
    Write-Host ""
    exit 1
}

Write-Host ""
Write-Host "Running certbot to create certificate..."
Write-Host "NOTE: Ensure port 80 is open and $Domain resolves to this machine"
Write-Host ""

# Run certbot via WSL
$certbotCmd = "sudo certbot certonly --standalone --agree-tos --non-interactive -d $Domain -d www.$Domain --email $Email"
Write-Host "Executing: wsl $certbotCmd"
wsl bash -c $certbotCmd

# Check if certificate was created
$wslCertPath = "/etc/letsencrypt/live/$Domain/fullchain.pem"
$wslKeyPath = "/etc/letsencrypt/live/$Domain/privkey.pem"

$certExists = (wsl test -f $wslCertPath; $?) -and (wsl test -f $wslKeyPath; $?)

if ($certExists) {
    Write-Host ""
    Write-Host "✓ Certificate created in WSL at: $wslCertPath"
    Write-Host ""
    Write-Host "Converting to PKCS#12 format (.pfx)..."

    # Copy cert files from WSL to Windows temp location
    $tempDir = [System.IO.Path]::GetTempPath()
    Write-Host "Copying certificate files from WSL to $tempDir..."

    wsl bash -c "sudo cp /etc/letsencrypt/live/$Domain/fullchain.pem /tmp/fullchain.pem && sudo cp /etc/letsencrypt/live/$Domain/privkey.pem /tmp/privkey.pem && sudo chmod 644 /tmp/*.pem"

    $wsltempFullchain = "$env:LOCALAPPDATA\Temp\fullchain.pem"
    $wsltempKey = "$env:LOCALAPPDATA\Temp\privkey.pem"

    # Use openssl via WSL to convert
    $opensslCmd = "openssl pkcs12 -export -out /tmp/chatapp.pfx -inkey /tmp/privkey.pem -in /tmp/fullchain.pem -password pass: -nodes && chmod 644 /tmp/chatapp.pfx"
    Write-Host "Converting with openssl..."
    wsl bash -c $opensslCmd

    # Copy back to Windows
    Write-Host "Copying .pfx back to Windows..."
    wsl bash -c "cat /tmp/chatapp.pfx" | Set-Content -Path $PFXPath -Encoding Byte

    Write-Host "✓ Certificate created: $PFXPath"
    Write-Host ""
    Write-Host "Certificate Details:"
    Write-Host "  - Domain: $Domain"
    Write-Host "  - Path: $PFXPath"
    Write-Host "  - Password: (empty)"
    Write-Host ""
    Write-Host "Update appsettings.Production.json with:"
    Write-Host '  "Path": "' + $PFXPath.Replace('\', '\\') + '"'
    Write-Host ""
    Write-Host "✓ Setup Complete!"
}
else {
    Write-Host "ERROR: Certificate generation failed"
    Write-Host "Check that port 80 is open and $Domain resolves to this machine"
    exit 1
}
