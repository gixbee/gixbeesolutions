@echo off
title Gixbee — Flutter App
set FLUTTER=C:\src\flutter_windows_3.32.1-stable\flutter\bin\flutter.bat
cd /d C:\Users\gkv00\Music\gixbee
echo.
REM Load build secrets (Ola Maps key etc.) — sets %GX_DEFINES%
call "%~dp0gixbee_keys.bat"
echo  Getting Flutter packages...
call "%FLUTTER%" pub get
echo.
echo  Available devices:
call "%FLUTTER%" devices
echo.
REM Physical device? The app talks to 127.0.0.1:3000 — bridge it first:
adb reverse tcp:3000 tcp:3000 >nul 2>nul
echo  Launching Flutter app...
call "%FLUTTER%" run %GX_DEFINES%
pause
