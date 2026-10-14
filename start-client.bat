@echo off
title SecureAttend - Client (Flutter Web)
echo ========================================================
echo Starting SecureAttend Flutter Client on 0.0.0.0:3000...
echo Accessible locally on PC: http://localhost:3000
echo Accessible from Phone (Wi-Fi): http://192.168.70.209:3000
echo ========================================================
cd /d "%~dp0client"
set "PATH=%PATH%;C:\flutter\bin"
call flutter.bat run -d chrome --web-hostname localhost --web-port 3000
pause
