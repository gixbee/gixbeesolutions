@echo off
title Gixbee Flutter (web)
cd /d "C:\Users\gkv00\Music\gixbee"
echo ============================================
echo   Starting Gixbee Flutter app in Chrome
echo ============================================
echo.
echo Checking Flutter is installed...
where flutter >nul 2>nul
if errorlevel 1 (
  echo [ERROR] 'flutter' not found on PATH. Install Flutter and add it to PATH, then re-run.
  echo         https://docs.flutter.dev/get-started/install/windows
  pause
  exit /b 1
)
echo Flutter OK.
echo.
echo Enabling web support...
call flutter config --enable-web
echo.
echo Fetching packages (first run can take a minute)...
call flutter pub get
echo.
echo NOTE: razorpay_flutter, google_maps_flutter, geocoding and
echo       flutter_local_notifications have no web support - those
echo       features will throw at runtime. The UI itself will render.
echo.
echo Launching in Chrome at a local dev-server URL...
echo (Close this window or press Ctrl+C to stop.)
echo.
flutter run -d chrome
pause
