@echo off
cd /d "%~dp0"
call "%~dp0gixbee_keys.bat"
set PATH=C:\src\flutter_windows_3.32.1-stable\flutter\bin;%PATH%
flutter build apk --release --split-per-abi %GX_DEFINES%
exit /b %ERRORLEVEL%
