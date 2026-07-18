@echo off
title Gixbee — Build release APK
set FLUTTER=C:\src\flutter_windows_3.32.1-stable\flutter\bin\flutter.bat
cd /d "C:\Users\gkv00\Music\gixbee"

REM Build secrets (Ola Maps key etc.) — sets %GX_DEFINES%
call "%~dp0gixbee_keys.bat"

echo ============================================
echo   Building Gixbee release APK
echo ============================================
echo.

if "%OLA_MAPS_API_KEY%"=="PASTE_YOUR_ROTATED_OLA_KEY_HERE" (
  echo [STOP] Set your Ola Maps key in gixbee_keys.bat before a release build,
  echo        otherwise the shipped app shows the "map unavailable" placeholder.
  pause
  exit /b 1
)

call "%FLUTTER%" pub get
echo.
call "%FLUTTER%" build apk --release %GX_DEFINES%
echo.
echo APK: build\app\outputs\flutter-apk\app-release.apk
echo Install on a connected phone with:
echo   adb install -r build\app\outputs\flutter-apk\app-release.apk
pause
