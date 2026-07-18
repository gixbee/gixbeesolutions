@echo off
title Gixbee Backend (dev)
cd /d "C:\Users\gkv00\Music\gixbee"
echo ============================================
echo   Starting Gixbee backend (Postgres+Redis+API)
echo ============================================
echo.
echo Checking Docker is running...
docker info >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Docker daemon not reachable. Make sure Docker Desktop is running, then re-run.
  pause
  exit /b 1
)
echo Docker OK. Building and starting services (first run: 3-5 min)...
echo.
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build postgres redis backend
echo.
echo === Container status ===
docker-compose -f docker-compose.yml -f docker-compose.dev.yml ps
echo.
echo Backend should be at http://localhost:3000
echo Tailing backend logs (close this window to stop following; containers keep running)...
echo.
docker logs -f gixbee_backend
pause
