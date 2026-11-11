@echo off
title AVH Staff Occupational Health & Vaccination Server (LAN / iPad Access - Port 8085)
cd /d "%~dp0"
echo ==========================================================================
echo   AUGUSTA VICTORIA HOSPITAL - STAFF OCCUPATIONAL HEALTH SYSTEM (LAN ACCESS)
echo ==========================================================================
echo Starting server for Hospital LAN, Mobile & iPad access on Port 8085 ...
echo.
echo Tip: If opening from an iPad/phone for the first time, run 'Setup_Mobile_Access.bat'
echo once as Administrator to ensure Windows Defender allows incoming connections.
echo.
powershell -ExecutionPolicy Bypass -NoProfile -File .\serve.ps1 -Port 8085 -AllowNetworkAccess
pause
