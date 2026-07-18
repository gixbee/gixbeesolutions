@echo off
title Gixbee — Run on connected phone (adb)
set FLUTTER=C:\src\flutter_windows_3.32.1-stable\flutter\bin\flutter.bat
cd /d "C:\Users\gkv00\Music\gixbee"

REM Build secrets (Ola Maps key etc.) — sets %GX_DEFINES%
call "%~dp0gixbee_keys.bat"

echo ============================================
echo   Gixbee on a physical device
echo ============================================
echo.

if not exist "%FLUTTER%" (
  echo [ERROR] flutter.bat not found at %FLUTTER%
  pause
  exit /b 1
)

REM Locate adb: PATH first, then the usual Android SDK spots. (Bare "adb" fails
REM with "not recognized" unless platform-tools is on PATH.)
set ADB=adb
where adb >nul 2>nul
if errorlevel 1 (
  if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" (
    set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
  ) else if exist "%ANDROID_HOME%\platform-tools\adb.exe" (
    set "ADB=%ANDROID_HOME%\platform-tools\adb.exe"
  ) else if exist "%ANDROID_SDK_ROOT%\platform-tools\adb.exe" (
    set "ADB=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
  ) else (
    echo [ERROR] adb not found. Install Android SDK platform-tools, or add it to PATH:
    echo         %%LOCALAPPDATA%%\Android\Sdk\platform-tools
    pause
    exit /b 1
  )
)

echo Connected devices:
"%ADB%" devices
echo.

REM The app calls http://127.0.0.1:3000 — on a phone that means the PHONE
REM itself, so bridge the port back to this PC's backend. Re-run whenever
REM the cable is replugged.
echo Bridging backend port (adb reverse 3000)...
"%ADB%" reverse tcp:3000 tcp:3000
if errorlevel 1 (
  echo [WARN] adb reverse failed — is the phone connected with USB debugging on?
  echo        Without this the app cannot reach the backend.
  echo.
)

echo Fetching packages...
call "%FLUTTER%" pub get
echo.
echo Launching on device...
call "%FLUTTER%" run %GX_DEFINES%
echo.
pause
