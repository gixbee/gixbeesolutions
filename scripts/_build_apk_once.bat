@echo off
cd /d C:\Users\gkv00\Music\gixbee
call "%~dp0..\gixbee_keys.bat"
set FLUTTER=C:\src\flutter_windows_3.32.1-stable\flutter\bin\flutter.bat
if not exist "%FLUTTER%" set FLUTTER=C:\Users\gkv00\flutter\bin\flutter.bat
call "%FLUTTER%" build apk --release --split-per-abi %GX_DEFINES%
