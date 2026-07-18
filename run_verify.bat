@echo off
title Gixbee Verify (analyze + tsc)
set FLUTTER=C:\src\flutter_windows_3.32.1-stable\flutter\bin\flutter.bat
cd /d "C:\Users\gkv00\Music\gixbee"
echo ============================================
echo   Verifying P0 build
echo ============================================
echo.
echo [1/2] flutter analyze ...
call "%FLUTTER%" analyze > verify_flutter.txt 2>&1
echo flutter analyze exit code: %errorlevel% >> verify_flutter.txt
echo   -> wrote verify_flutter.txt
echo.
echo [2/2] backend tsc --noEmit ...
cd backend
call npx tsc --noEmit -p tsconfig.json > ..\verify_backend.txt 2>&1
echo backend tsc exit code: %errorlevel% >> ..\verify_backend.txt
cd ..
echo   -> wrote verify_backend.txt
echo.
echo Done.
pause
