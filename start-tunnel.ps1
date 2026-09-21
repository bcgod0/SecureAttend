# SecureAttend - Public HTTPS Tunnel Launcher
# This script:
#   1. Installs cloudflared (if not installed)
#   2. Opens a tunnel for the backend (port 8080), captures the URL
#   3. Builds the Flutter web app baked with that backend URL
#   4. Serves the web build on port 3000 via Python
#   5. Opens a tunnel for the frontend (port 3000)
#   6. Shows you a public HTTPS link to share with anyone!

param (
    [switch]$SkipInstall   # Pass -SkipInstall if cloudflared is already installed
)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$clientDir   = Join-Path $projectRoot "client"
$webBuildDir = Join-Path $clientDir   "build\web"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   SecureAttend - Public HTTPS Tunnel Setup                 " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: Ensure cloudflared is installed ---
function Find-Cloudflared {
    $cf = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($cf) { return $cf.Source }

    $candidates = @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links\cloudflared.exe",
        "$env:ProgramFiles\cloudflared\cloudflared.exe",
        "${env:ProgramFiles(x86)}\cloudflared\cloudflared.exe",
        "C:\Program Files (x86)\cloudflared\cloudflared.exe",
        "$env:LOCALAPPDATA\Programs\cloudflared\cloudflared.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }

    $wingetPkgs = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
    if (Test-Path $wingetPkgs) {
        $found = Get-ChildItem $wingetPkgs -Recurse -Filter "cloudflared.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    return $null
}

$cloudflaredExe = Find-Cloudflared

if (-not $cloudflaredExe) {
    if ($SkipInstall) {
        Write-Host "[ERROR] cloudflared not found. Run without -SkipInstall to auto-install." -ForegroundColor Red
        exit 1
    }

    Write-Host "[1/5] Installing cloudflared via winget..." -ForegroundColor Yellow
    winget install --id Cloudflare.cloudflared -e --accept-source-agreements --accept-package-agreements --silent
    Start-Sleep -Seconds 3

    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")

    $cloudflaredExe = Find-Cloudflared
    if (-not $cloudflaredExe) {
        Write-Host "[ERROR] Could not find cloudflared after installation." -ForegroundColor Red
        Write-Host "Please close and reopen this window, then run again." -ForegroundColor Yellow
        Pause
        exit 1
    }
    Write-Host "[1/5] cloudflared installed at: $cloudflaredExe" -ForegroundColor Green
} else {
    Write-Host "[1/5] cloudflared found: $cloudflaredExe" -ForegroundColor Green
}

# --- Step 2: Start backend tunnel, capture URL ---
Write-Host ""
Write-Host "[2/5] Starting backend tunnel (port 8080)..." -ForegroundColor Yellow

$backendLogFile = Join-Path $projectRoot "tunnel-backend.log"
if (Test-Path $backendLogFile) { Remove-Item $backendLogFile -Force }

$backendTunnel = Start-Process -FilePath $cloudflaredExe `
    -ArgumentList "tunnel", "--url", "http://localhost:8080", "--no-autoupdate" `
    -RedirectStandardError $backendLogFile `
    -PassThru -NoNewWindow

$backendUrl = $null
$waited = 0
Write-Host "   Waiting for Cloudflare to assign backend URL..." -ForegroundColor DarkGray
while (-not $backendUrl -and $waited -lt 45) {
    Start-Sleep -Seconds 1
    $waited++
    if (Test-Path $backendLogFile) {
        $logContent = Get-Content $backendLogFile -Raw -ErrorAction SilentlyContinue
        if ($logContent -match "https://[a-z0-9\-]+\.trycloudflare\.com") {
            $backendUrl = $matches[0]
        }
    }
}

if (-not $backendUrl) {
    Write-Host "[ERROR] Could not detect backend tunnel URL after 45 seconds." -ForegroundColor Red
    Write-Host "Check '$backendLogFile' for details." -ForegroundColor Yellow
    $backendTunnel | Stop-Process -Force -ErrorAction SilentlyContinue
    Pause
    exit 1
}

Write-Host "[2/5] Backend tunnel LIVE: $backendUrl" -ForegroundColor Green

$wsHost = $backendUrl -replace "^https://", ""
$wsUrl  = "wss://$wsHost/ws"
$apiUrl = "$backendUrl/api"

Write-Host "   API URL : $apiUrl" -ForegroundColor DarkGray
Write-Host "   WS URL  : $wsUrl"  -ForegroundColor DarkGray

# --- Step 3: Build Flutter web with baked-in URLs ---
Write-Host ""
Write-Host "[3/5] Building Flutter web (this takes ~2-4 minutes)..." -ForegroundColor Yellow

Set-Location $clientDir
$env:PATH = "$env:PATH;C:\flutter\bin"

$flutterBuild = Start-Process -FilePath "flutter.bat" `
    -ArgumentList "build", "web", "--release", "--dart-define=API_BASE_URL=$apiUrl", "--dart-define=WS_URL=$wsUrl" `
    -Wait -PassThru -NoNewWindow

if ($flutterBuild.ExitCode -ne 0) {
    Write-Host "[ERROR] Flutter build failed! Check output above." -ForegroundColor Red
    $backendTunnel | Stop-Process -Force -ErrorAction SilentlyContinue
    Set-Location $projectRoot
    Pause
    exit 1
}

Set-Location $projectRoot
Write-Host "[3/5] Flutter web build complete." -ForegroundColor Green

# --- Step 4: Serve Flutter web build on port 3000 via Python ---
Write-Host ""
Write-Host "[4/5] Starting local web server (port 3000)..." -ForegroundColor Yellow
$serveProcess = Start-Process -FilePath "python" `
    -ArgumentList "-m", "http.server", "3000", "--directory", $webBuildDir `
    -PassThru -NoNewWindow

Start-Sleep -Seconds 2
Write-Host "[4/5] Web server started." -ForegroundColor Green

# --- Step 5: Start frontend tunnel ---
Write-Host ""
Write-Host "[5/5] Starting frontend tunnel (port 3000)..." -ForegroundColor Yellow

$frontendLogFile = Join-Path $projectRoot "tunnel-frontend.log"
if (Test-Path $frontendLogFile) { Remove-Item $frontendLogFile -Force }

$frontendTunnel = Start-Process -FilePath $cloudflaredExe `
    -ArgumentList "tunnel", "--url", "http://localhost:3000", "--no-autoupdate" `
    -RedirectStandardError $frontendLogFile `
    -PassThru -NoNewWindow

$frontendUrl = $null
$waited = 0
Write-Host "   Waiting for Cloudflare to assign frontend URL..." -ForegroundColor DarkGray
while (-not $frontendUrl -and $waited -lt 45) {
    Start-Sleep -Seconds 1
    $waited++
    if (Test-Path $frontendLogFile) {
        $logContent = Get-Content $frontendLogFile -Raw -ErrorAction SilentlyContinue
        if ($logContent -match "https://[a-z0-9\-]+\.trycloudflare\.com") {
            $frontendUrl = $matches[0]
        }
    }
}

if (-not $frontendUrl) {
    Write-Host "[ERROR] Could not detect frontend tunnel URL after 45 seconds." -ForegroundColor Red
    $backendTunnel  | Stop-Process -Force -ErrorAction SilentlyContinue
    $serveProcess   | Stop-Process -Force -ErrorAction SilentlyContinue
    $frontendTunnel | Stop-Process -Force -ErrorAction SilentlyContinue
    Set-Location $projectRoot
    Pause
    exit 1
}

# --- Done! Print summary ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "   SecureAttend is LIVE on the Internet!                    " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Share this URL with ANYONE (phone, laptop, anywhere):    " -ForegroundColor White
Write-Host ""
Write-Host "      $frontendUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Camera, Face Scan, GPS work automatically               " -ForegroundColor Green
Write-Host "  (HTTPS = all browser permissions granted natively)       " -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Backend API URL: $apiUrl" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Keep this window open while sharing.                     " -ForegroundColor Yellow
Write-Host "  Press Ctrl+C to stop all tunnels and shut down.          " -ForegroundColor Red
Write-Host "============================================================" -ForegroundColor Green

$summary = @"
SecureAttend Public URLs - $(Get-Date)
=====================================
App URL (Share this!): $frontendUrl
Backend API URL      : $apiUrl
WebSocket URL        : $wsUrl
"@
$summary | Set-Content (Join-Path $projectRoot "tunnel-urls.txt")
Write-Host ""
Write-Host "  URLs also saved to: tunnel-urls.txt" -ForegroundColor DarkGray
Write-Host ""

try {
    while ($true) { Start-Sleep -Seconds 10 }
}
finally {
    Write-Host "`nShutting down tunnels..." -ForegroundColor Yellow
    $backendTunnel  | Stop-Process -Force -ErrorAction SilentlyContinue
    $serveProcess   | Stop-Process -Force -ErrorAction SilentlyContinue
    $frontendTunnel | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "All tunnels stopped. Goodbye!" -ForegroundColor Green
}
