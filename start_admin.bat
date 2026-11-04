@echo off
title RideApp Admin Portal (:5173)
echo ========================================================
echo Starting RideApp Admin Dashboard on http://localhost:5173
echo ========================================================
cd /d "%~dp0admin"
where npm >nul 2>nul
if errorlevel 1 (
    echo Node.js and npm were not found in PATH. Install Node.js, reopen this window, and try again.
    pause
    exit /b 1
)
if not exist "node_modules\.bin\vite.cmd" (
    echo Admin dependencies are not installed yet. Run: npm install
    pause
    exit /b 1
)
call npm run dev
pause
