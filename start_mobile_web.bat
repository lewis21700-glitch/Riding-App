@echo off
title RideApp Mobile Web
echo ========================================================
echo Starting RideApp Flutter Mobile Web on Microsoft Edge
echo ========================================================
cd /d "%~dp0MOBILE\mobile"
flutter run -d edge
pause
