# ==============================================================================
# Lab 3 — Splunk SIEM: Universal Forwarder Install + Config
# ==============================================================================
# Run this ON vm-actived (the Windows Server / AD VM from Lab 1), as Administrator.
# Silently installs the Universal Forwarder, writes inputs.conf, and restarts
# the service so Windows Security/System/Application logs start forwarding to
# Splunk over the peered private network.
#
# Prerequisite: download the Universal Forwarder .msi first from
# https://splunk.com/en_us/download/universal-forwarder.html (browser-based
# registration, same as Splunk Enterprise — can't be scripted).
#
# Usage (PowerShell, as Administrator):
#   .\03-configure-forwarder.ps1 -MsiPath "C:\Downloads\splunkforwarder.msi" -SplunkIndexerIp "10.1.1.4"
# ==============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$MsiPath,

    [Parameter(Mandatory=$true)]
    [string]$SplunkIndexerIp,

    [string]$ForwarderUser = "admin",
    [string]$ForwarderPassword = "ChangeMeImmediately123!"
)

if (-not (Test-Path $MsiPath)) {
    Write-Error "MSI not found at $MsiPath — download it from splunk.com first."
    exit 1
}

Write-Host "==> Installing Universal Forwarder silently..."
# DEPLOYMENT_SERVER and RECEIVING_INDEXER point the forwarder at the Splunk VM's
# PRIVATE IP. This only works because of the VNet peering set up in
# 01-provision-infra.sh — without peering, vm-actived can't route to that
# private IP at all, and you'd have to fall back to the Splunk VM's public IP
# instead (which is what happened on the first, unpeered manual attempt at this lab).
$msiArgs = @(
    "/i", "`"$MsiPath`"",
    "AGREETOLICENSE=Yes",
    "DEPLOYMENT_SERVER=$SplunkIndexerIp`:8089",
    "RECEIVING_INDEXER=$SplunkIndexerIp`:9997",
    "WINEVENTLOG_SEC_ENABLE=1",
    "WINEVENTLOG_SYS_ENABLE=1",
    "WINEVENTLOG_APP_ENABLE=1",
    "/quiet"
)
Start-Process msiexec.exe -ArgumentList $msiArgs -Wait

$inputsPath = "C:\Program Files\SplunkUniversalForwarder\etc\system\local"
if (-not (Test-Path $inputsPath)) {
    New-Item -ItemType Directory -Path $inputsPath -Force | Out-Null
}

Write-Host "==> Writing inputs.conf..."
$inputsConf = @"
[WinEventLog://Security]
disabled = 0
start_from = oldest
current_only = 0
evt_resolve_ad_obj = 1

[WinEventLog://System]
disabled = 0

[WinEventLog://Application]
disabled = 0
"@
Set-Content -Path "$inputsPath\inputs.conf" -Value $inputsConf -Encoding ASCII

Write-Host "==> Restarting SplunkForwarder service..."
# Restart-Service has thrown a CloseError against this service in testing —
# stopping and starting separately avoids that.
Stop-Service SplunkForwarder -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Start-Service SplunkForwarder

Start-Sleep -Seconds 2
$status = Get-Service SplunkForwarder
Write-Host "==> SplunkForwarder service status: $($status.Status)"

Write-Host ""
Write-Host "==> Verify audit policy is capturing logon events (don't assume it already is):"
Write-Host "    Local Security Policy -> Security Settings -> Local Policies -> Audit Policy"
Write-Host "    -> 'Audit logon events' should have Success and Failure both checked"
Write-Host ""
Write-Host "==> Give it 1-2 minutes, then verify on the Splunk side with:"
Write-Host "    index=windows_logs | head 100"
