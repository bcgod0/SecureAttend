@echo off
title SecureAttend - Launch All
echo ========================================================
echo Starting all SecureAttend services in separate windows...
echo ========================================================

echo [1/3] Starting Backend (Spring Boot)...
start "SecureAttend - Backend" cmd /c "%~dp0start-backend.bat"

timeout /t 5 /nobreak >nul

echo [2/3] Starting ML Service (FastAPI)...
start "SecureAttend - ML Service" cmd /c "%~dp0start-ml.bat"

timeout /t 5 /nobreak >nul

echo [3/3] Starting Flutter Client (Web)...
start "SecureAttend - Client" cmd /c "%~dp0start-client.bat"

echo ========================================================
echo All 3 services have been launched!
echo - Backend:    http://localhost:8080
echo - ML Service: http://localhost:8000
echo - Client:     Opening in Chrome...
echo ========================================================
