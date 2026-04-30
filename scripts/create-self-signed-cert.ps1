# Create a self-signed certificate for development/testing (Windows PowerShell)
# Usage: .\create-self-signed-cert.ps1 -Domain localhost -OutputDir .

param(
    [string]$Domain = "localhost",
    [string]$OutputDir = "."
)

Write-Host "Creating self-signed certificate for domain: $Domain"
Write-Host "Output directory: $OutputDir"

# Create certificate valid for 365 days
$cert = New-SelfSignedCertificate -DnsName $Domain -CertStoreLocation cert:\CurrentUser\My `
    -NotAfter (Get-Date).AddDays(365) -FriendlyName "ChatApp Dev Certificate"

# Export as PFX
$certPath = "cert:\CurrentUser\My\$($cert.Thumbprint)"
$pfxPath = Join-Path $OutputDir "chatapp.pfx"
Export-PfxCertificate -Cert $certPath -FilePath $pfxPath -Password (ConvertTo-SecureString -String "" -AsPlainText -Force)

Write-Host "Certificate created successfully!"
Write-Host "  - Thumbprint: $($cert.Thumbprint)"
Write-Host "  - PKCS#12: $pfxPath"
Write-Host ""
Write-Host "For production, deploy chatapp.pfx to your server at: C:\etc\ssl\certs\chatapp.pfx (Windows) or /etc/ssl/certs/chatapp.pfx (Linux)"
