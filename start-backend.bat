@echo off
title SecureAttend - Backend (Spring Boot)
echo ========================================================
echo Starting SecureAttend Backend (Spring Boot)...
echo Running on: http://localhost:8080
echo ========================================================
cd /d "%~dp0backend"
call gradlew.bat bootRun
pause
