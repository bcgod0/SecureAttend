@echo off
title SecureAttend - ML Service (FastAPI)
echo ========================================================
echo Starting SecureAttend ML Service (FastAPI)...
echo Running on: http://localhost:8000
echo ========================================================
cd /d "%~dp0ml-service"
call venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
pause
