@echo off
title AVH Occupational Health - Configure Mobile & iPad Access
cd /d "%~dp0"
echo ==========================================================================
echo   AUGUSTA VICTORIA HOSPITAL - CONFIGURE MOBILE ^& IPAD ACCESS (PORT 8085)
echo ==========================================================================
echo.
echo This one-time setup allows your phone, iPad, or tablet to access the
echo Occupational Health Dashboard across your Wi-Fi or hospital network.
echo.

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Requesting Administrator privileges to configure Windows Firewall and URL permissions...
    powershell -ExecutionPolicy Bypass -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

echo [1/3] Adding HTTP URL reservation for Port 8085 (All users)...
netsh http add urlacl url=http://+:8085/ user=Everyone >nul 2>&1
if %errorLevel% neq 0 (
    netsh http add urlacl url=http://+:8085/ user=Users >nul 2>&1
)

echo [2/3] Adding Windows Defender Firewall Rule for Port 8085...
netsh advfirewall firewall delete rule name="AVH Occupational Health Port 8085" >nul 2>&1
netsh advfirewall firewall add rule name="AVH Occupational Health Port 8085" dir=in action=allow protocol=TCP localport=8085 profile=private,domain >nul 2>&1

echo [3/3] Detecting local IP address for Mobile / iPad connection...
for /f "tokens=*" %%i in ('powershell -ExecutionPolicy Bypass -NoProfile -Command "@(Get-NetIPAddress -AddressFamily IPv4 -Type Unicast -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne '127.0.0.1' -and -not $_.IPAddress.StartsWith('169.254.') } | Select-Object -ExpandProperty IPAddress)[0]"') do set LOCAL_IP=%%i

echo.
echo ==========================================================================
echo   [SUCCESS] SETUP COMPLETED SUCCESSFULLY!
echo ==========================================================================
echo.
echo  Your Mobile / iPad URL is:
echo  --^> http://%LOCAL_IP%:8085/
echo.
echo  How to connect from your iPhone, iPad, or Android:
echo  1. Connect your device to the same Wi-Fi network.
echo  2. Open Safari (iOS / iPad) or Chrome (Android).
echo  3. Navigate to: http://%LOCAL_IP%:8085/
echo  4. In Safari, tap Share -^> "Add to Home Screen" to install it as an App!
echo.
echo ==========================================================================
pause
