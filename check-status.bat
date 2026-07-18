@echo off
powershell -NoProfile -Command "docker ps --format 'table {{.Names}}`t{{.Status}}`t{{.Ports}}' | Out-File -FilePath 'C:\Users\gkv00\Music\gixbee\docker-status.txt'"
