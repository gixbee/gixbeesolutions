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
REM --split-per-abi: one APK per CPU architecture instead of a ~96MB "fat"
REM APK carrying all three. Share app-arm64-v8a-release.apk (~30-35MB) —
REM every Android phone from the last ~8 years is arm64. The armeabi-v7a
REM APK exists for very old budget devices; x86_64 is emulators only.
REM For Play Store uploads use build_appbundle instead — Play serves each
REM device only its own architecture automatically.
call "%FLUTTER%" build apk --release --split-per-abi %GX_DEFINES%
echo.
echo APKs: build\app\outputs\flutter-apk\
echo   app-arm64-v8a-release.apk    ^<-- send THIS one to testers/clients
echo   app-armeabi-v7a-release.apk  (very old devices)
echo   app-x86_64-release.apk       (emulators)
echo Install on a connected phone with:
echo   adb install -r build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
pause
