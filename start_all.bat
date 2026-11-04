@echo off
title RideApp Full Stack Launcher
echo ========================================================
echo Starting RideApp FastAPI Backend and Admin Web Portal
echo ========================================================
start "RideApp Backend" "%~dp0start_backend.bat"
start "RideApp Admin Web" "%~dp0start_admin.bat"
echo System launching... Backend on port 3000, Admin on port 5173.
