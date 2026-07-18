@echo off
title Gixbee Launcher (Chrome web)
set FLUTTER=C:\src\flutter_windows_3.32.1-stable\flutter\bin\flutter.bat
cd /d "C:\Users\gkv00\Music\gixbee"
echo ============================================
echo   Launching Gixbee Flutter app on Chrome
echo ============================================
echo.
if not exist "%FLUTTER%" (
  echo [ERROR] flutter.bat not found at %FLUTTER%
  pause
  exit /b 1
)
REM Load build secrets (Ola Maps key etc.) — sets %GX_DEFINES%
call "%~dp0gixbee_keys.bat"
echo Fetching packages...
call "%FLUTTER%" pub get
echo.
echo Starting app on Chrome (first build can take 1-3 minutes)...
call "%FLUTTER%" run -d chrome --web-port=5005 %GX_DEFINES%
echo.
echo App process ended.
pause
