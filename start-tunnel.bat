@echo off
title SecureAttend - Public HTTPS Tunnel
echo ============================================================
echo   SecureAttend - Starting Public HTTPS Tunnel...
echo ============================================================
echo.
echo Make sure backend (port 8080) and ML service (port 8000)
echo are already running before continuing!
echo.
pause

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-tunnel.ps1"
pause
