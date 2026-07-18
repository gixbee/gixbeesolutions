@echo off
title Gixbee dart analyze
set DART=C:\src\flutter_windows_3.32.1-stable\flutter\bin\dart.bat
cd /d "C:\Users\gkv00\Music\gixbee"
echo Running dart analyze on lib + backend check...
call "%DART%" analyze lib 1> verify_dart.txt 2>&1
echo ===EXITCODE=%errorlevel%=== 1>> verify_dart.txt
echo Done. Wrote verify_dart.txt
type verify_dart.txt
pause
