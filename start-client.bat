@echo off
title SecureAttend - Client (Flutter Web)
echo ========================================================
echo Starting SecureAttend Flutter Client...
echo ========================================================
cd /d "%~dp0client"
set "PATH=%PATH%;C:\flutter\bin"
call flutter.bat run -d chrome
pause
