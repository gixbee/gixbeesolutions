@echo off
title Gixbee backend tsc
cd /d "C:\Users\gkv00\Music\gixbee\backend"
echo Running backend TypeScript compile check... > "C:\Users\gkv00\Music\gixbee\verify_backend.txt"
call npx tsc --noEmit -p tsconfig.json >> "C:\Users\gkv00\Music\gixbee\verify_backend.txt" 2>&1
echo ===TSC_EXITCODE=%errorlevel%=== >> "C:\Users\gkv00\Music\gixbee\verify_backend.txt"
echo DONE
type "C:\Users\gkv00\Music\gixbee\verify_backend.txt"
pause
