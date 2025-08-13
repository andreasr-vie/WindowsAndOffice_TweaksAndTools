# RESET OFFICE ACTIVATION STATE
# Setzt die Lizenzierung der Microsoft 365 Apps zurück.
# Nach dem Ausführen: Benutzer ab- und wieder anmelden.

# --- Settings ---------------------------------------------------------------
$Urls = @(
  "https://download.microsoft.com/download/e/1/b/e1bbdc16-fad4-4aa2-a309-2ba3cae8d424/OLicenseCleanup.zip",
  "https://download.microsoft.com/download/f/8/7/f8745d3b-49ad-4eac-b49a-2fa60b929e7d/signoutofwamaccounts.zip",
  "https://download.microsoft.com/download/8/e/f/8ef13ae0-6aa8-48a2-8697-5b1711134730/WPJCleanUp.zip"
)

$BaseExtractPath = "C:\TempPath\o365reset"
$DownloadPath    = Join-Path $BaseExtractPath "downloads"

# --- Admin-Check ------------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Error "Bitte PowerShell als Administrator ausführen."
  exit 1
}

# --- Prep -------------------------------------------------------------------
New-Item -Path $BaseExtractPath -ItemType Directory -Force | Out-Null
New-Item -Path $DownloadPath    -ItemType Directory -Force | Out-Null

# TLS (für ältere Systeme)
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

# --- Dateien robust finden --------------------------------------------------
function Find-File([string]$pattern) {
  Get-ChildItem -Path $BaseExtractPath -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ieq $pattern } |
    Select-Object -First 1
}

$OLicenseCleanup = Find-File "OLicenseCleanup.vbs"
$SignOutWam      = Find-File "signoutofwamaccounts.ps1"
$WPJCleanupCmd   = Find-File "WPJCleanUp.cmd"  # liegt oft in WPJCleanUp\WPJCleanUp\

Write-Host ("Test OLicenseCleanup.vbs:      {0}" -f ([bool]$OLicenseCleanup))
Write-Host ("Test signoutofwamaccounts.ps1: {0}" -f ([bool]$SignOutWam))
Write-Host ("Test WPJCleanUp.cmd:           {0}" -f ([bool]$WPJCleanupCmd))

if (-not $OLicenseCleanup -or -not $SignOutWam -or -not $WPJCleanupCmd) {
  Write-Error "Mindestens eine benötigte Datei wurde nicht gefunden. Abbruch."
  exit 2
}

# --- Ausführen --------------------------------------------------------------
Write-Host "Execute OLicenseCleanup.vbs ..."
Start-Process -FilePath "$env:SystemRoot\System32\cscript.exe" `
  -ArgumentList @("//nologo", "`"$($OLicenseCleanup.FullName)`"") `
  -Wait -NoNewWindow

Start-Sleep -Seconds 2

Write-Host "Execute signoutofwamaccounts.ps1 ..."
Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
  -ArgumentList @("-ExecutionPolicy","Bypass","-NoProfile","-File","`"$($SignOutWam.FullName)`"") `
  -Wait -NoNewWindow

Start-Sleep -Seconds 2

Write-Host "Execute WPJCleanUp.cmd ..."
Start-Process -FilePath "`"$($WPJCleanupCmd.FullName)`"" -Wait -NoNewWindow

Write-Host "`nFertig. Bitte jetzt vom Benutzerkonto abmelden und neu anmelden."
