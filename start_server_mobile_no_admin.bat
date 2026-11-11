@echo off
title "AVH Staff Occupational Health - Zero-Admin Mobile and iPad Access"
cd /d "%~dp0"
echo ==========================================================================
echo   AUGUSTA VICTORIA HOSPITAL - ZERO-ADMIN MOBILE ^& IPAD ACCESS
echo ==========================================================================
echo.
echo Starting server for iPhone, iPad, and Android access...
echo (No Administrator privileges required - standard user mode)
echo.
powershell -ExecutionPolicy Bypass -NoProfile -File .\serve_mobile_no_admin.ps1
pause
