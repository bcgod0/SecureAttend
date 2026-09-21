@echo off
title SecureAttend - Phone Port Forwarding (USB)
echo ========================================================
echo Setting up USB reverse port forwarding for SecureAttend...
echo ========================================================
adb reverse tcp:3000 tcp:3000
adb reverse tcp:8080 tcp:8080
if %errorlevel% equ 0 (
    echo ========================================================
    echo [SUCCESS] USB reverse port forwarding active!
    echo Open Chrome on your phone and browse to:
    echo     http://localhost:3000
    echo Camera and Geolocation work natively without any flags!
    echo ========================================================
) else (
    echo ========================================================
    echo No USB Android device found or USB debugging not enabled.
    echo To test over Wi-Fi instead:
    echo 1. Connect phone to the same Wi-Fi network.
    echo 2. Open Chrome on your phone and go to:
    echo    http://192.168.70.209:3000
    echo ========================================================
)
pause
