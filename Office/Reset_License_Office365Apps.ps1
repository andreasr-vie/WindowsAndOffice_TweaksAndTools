# RESET OFFICE 365 APPS LICENSING (Patched)
# -------------------------------------------------------------
# This script resets Microsoft 365 Apps licensing and related
# authentication state. It:
#   - Downloads & runs OLicenseCleanup.vbs
#   - Signs out WAM (Web Account Manager) accounts (user context)
#   - Runs WPJCleanUp (workplace join cleanup)
#
# Notes:
#   * Run this script as Administrator.
#   * The WAM sign-out step must run in a USER context (not SYSTEM).
#   * Requires PowerShell 5.1+ and internet connectivity to Microsoft download URLs.

# --- Settings ---------------------------------------------------------------
$BaseExtractPath = "C:\TempPath\o365reset"
$DownloadPath    = Join-Path $BaseExtractPath "downloads"

$Urls = @(
  "https://download.microsoft.com/download/e/1/b/e1bbdc16-fad4-4aa2-a309-2ba3cae8d424/OLicenseCleanup.zip",
  "https://download.microsoft.com/download/8/e/f/8ef13ae0-6aa8-48a2-8697-5b1711134730/WPJCleanUp.zip"
)

# --- Admin-Check ------------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Error "Bitte PowerShell als Administrator ausführen."
  exit 1
}

# --- Prep -------------------------------------------------------------------
New-Item -Path $BaseExtractPath -ItemType Directory -Force | Out-Null
New-Item -Path $DownloadPath    -ItemType Directory -Force | Out-Null

# TLS 1.2 (für ältere Systeme)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# --- Download & Entpacken ---------------------------------------------------
$zips = foreach ($url in $Urls) {
  $fileName = Split-Path $url -Leaf
  $dst      = Join-Path $DownloadPath $fileName
  Write-Host "Download: $url -> $dst"
  Invoke-WebRequest -Uri $url -OutFile $dst -UseBasicParsing
  $dst
}

foreach ($zip in $zips) {
  Write-Host "Entpacke: $zip"
  Expand-Archive -Path $zip -DestinationPath $BaseExtractPath -Force
}

# --- Robustes signoutofwamaccounts.ps1 ablegen ------------------------------
$SignOutPath = Join-Path $BaseExtractPath "signoutofwamaccounts.ps1"
@'
# signoutofwamaccounts.ps1 (robust, embedded)

# WinRT-Brücke laden (für AsTask)
Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null

function Await {
    param([Parameter(Mandatory=$true)]$AsyncOp)
    return [System.WindowsRuntimeSystemExtensions]::AsTask($AsyncOp).GetAwaiter().GetResult()
}

# Sanity checks
if ($env:USERNAME -eq 'SYSTEM') {
    Write-Warning "Dieses Skript muss im Benutzerkontext laufen (nicht als SYSTEM)."
}

# Konstanten (ASCII-Quotes!)
$providerId = "https://login.microsoft.com"
$clientId   = "d3590ed6-52b3-4102-aeff-aad2292ab01c"

# WinRT Namespaces abrufen
$WebAuthCoreMgr = [Windows.Security.Authentication.Web.Core.WebAuthenticationCoreManager]
$FindProvider   = {
    param($authority)
    try {
        if ($authority) {
            return Await ($WebAuthCoreMgr::FindAccountProviderAsync($providerId, $authority))
        } else {
            return Await ($WebAuthCoreMgr::FindAccountProviderAsync($providerId))
        }
    } catch {
        return $null
    }
}

# Provider-Varianten probieren
$provider = & $FindProvider "organizations"
if (-not $provider) { $provider = & $FindProvider "consumers" }
if (-not $provider) { $provider = & $FindProvider $null }

if (-not $provider) {
    Write-Warning "Kein WebAccountProvider gefunden. Mögliche Ursachen: Offline, alte Windows-Version, falscher Kontext."
    return
}

# Accounts holen
try {
    $accounts = Await ($WebAuthCoreMgr::FindAllAccountsAsync($provider, $clientId))
} catch {
    Write-Warning ("FindAllAccountsAsync schlug fehl: {0}" -f $_.Exception.Message)
    $accounts = $null
}

if (-not $accounts -or $accounts.Count -eq 0) {
    Write-Host "Keine WAM-Accounts gefunden – nichts zu tun."
    return
}

Write-Host ("{0} WAM-Account(s) gefunden. Melde ab ..." -f $accounts.Count)

# Abmelden
$errors = @()
foreach ($acct in $accounts) {
    try {
        $desc = ($acct.UserName) ? $acct.UserName : $acct.Id
        Write-Host ("SignOut: {0}" -f $desc)
        Await ($acct.SignOutAsync($clientId))
    } catch {
        $errors += $_.Exception.Message
        Write-Warning ("Fehler bei SignOut: {0}" -f $_.Exception.Message)
    }
}

if ($errors.Count -gt 0) {
    Write-Warning "Einige Abmeldungen schlugen fehl. Details siehe oben."
} else {
    Write-Host "WAM-Abmeldung abgeschlossen."
}
'@ | Set-Content -Path $SignOutPath -Encoding UTF8 -Force

# --- Dateien robust finden --------------------------------------------------
function Find-File([string]$pattern) {
  Get-ChildItem -Path $BaseExtractPath -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ieq $pattern } |
    Select-Object -First 1
}

$OLicenseCleanup = Find-File "OLicenseCleanup.vbs"
$WPJCleanupCmd   = Find-File "WPJCleanUp.cmd"  # liegt oft in WPJCleanUp\WPJCleanUp\

Write-Host ("Test OLicenseCleanup.vbs: {0}" -f ([bool]$OLicenseCleanup))
Write-Host ("Test WPJCleanUp.cmd:      {0}" -f ([bool]$WPJCleanupCmd))

if (-not $OLicenseCleanup -or -not $WPJCleanupCmd) {
  Write-Error "Mindestens eine benötigte Datei wurde nicht gefunden. Abbruch."
  exit 2
}

# --- Ausführen --------------------------------------------------------------
Write-Host "Execute OLicenseCleanup.vbs ..."
Start-Process -FilePath "$env:SystemRoot\System32\cscript.exe" \
  -ArgumentList @("//nologo", "`"$($OLicenseCleanup.FullName)`"") \
  -Wait -NoNewWindow

Start-Sleep -Seconds 2

# WAM Sign-Out nur im Benutzerkontext sinnvoll
if ($env:USERNAME -eq 'SYSTEM') {
  Write-Warning "Überspringe WAM-Abmeldung, da der Prozess im SYSTEM-Kontext läuft. Bitte als Benutzer ausführen, um WAM abzumelden."
} else {
  Write-Host "Execute signoutofwamaccounts.ps1 (User context) ..."
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList @("-ExecutionPolicy","Bypass","-NoProfile","-File","`"$SignOutPath`"") `
    -Wait -NoNewWindow
}

Start-Sleep -Seconds 2

Write-Host "Execute WPJCleanUp.cmd ..."
Start-Process -FilePath "`"$($WPJCleanupCmd.FullName)`"" -Wait -NoNewWindow

Write-Host "`nFertig. Bitte jetzt vom Benutzerkonto abmelden und neu anmelden."
