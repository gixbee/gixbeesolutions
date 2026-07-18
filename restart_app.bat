@echo off
title Gixbee Restart (fresh build)
set FLUTTER=C:\src\flutter_windows_3.32.1-stable\flutter\bin\flutter.bat
echo Stopping any running Flutter web build (dart.exe)...
taskkill /F /IM dart.exe >nul 2>nul
timeout /t 2 >nul
cd /d "C:\Users\gkv00\Music\gixbee"
REM Load build secrets (Ola Maps key etc.) — sets %GX_DEFINES%
call "%~dp0gixbee_keys.bat"
echo Rebuilding and launching with the latest changes...
echo (first build after a stop can take 1-2 minutes)
call "%FLUTTER%" run -d chrome --web-port=5005 %GX_DEFINES%
pause
