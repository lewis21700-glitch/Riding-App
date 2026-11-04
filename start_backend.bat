@echo off
title RideApp FastAPI Backend (:3000)
echo ========================================================
echo Starting RideApp FastAPI Backend on http://127.0.0.1:3000
echo ========================================================
where node >nul 2>&1
if not errorlevel 1 (
    start "RideApp Map Tile Proxy" /D "%~dp0" node --use-system-ca "%~dp0BACKEND\map-tile-proxy.js"
) else (
    echo Node.js was not found; the mobile emulator map proxy will not start.
)
cd /d "%~dp0BACKEND\fastapi"
if exist ".venv\Scripts\python.exe" (
    ".venv\Scripts\python.exe" -m uvicorn app.main:app --host 0.0.0.0 --port 3000 --reload
) else (
    python -m uvicorn app.main:app --host 0.0.0.0 --port 3000 --reload
)
pause
