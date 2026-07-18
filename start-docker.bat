@echo off
title Gixbee Docker Stack (building...)
cd /d C:\Users\gkv00\Music\gixbee
echo.
echo  Building and starting Gixbee Docker stack...
echo  This takes 3-5 minutes on first run.
echo  DO NOT CLOSE THIS WINDOW.
echo.
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
echo.
echo  === Container status ===
docker-compose -f docker-compose.yml -f docker-compose.dev.yml ps
echo.
echo  Done! Containers are running in background.
echo  Press any key to close this window.
pause
