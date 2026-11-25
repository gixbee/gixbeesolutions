#!/bin/bash
set -euo pipefail
GEO=/tmp/geonames-in
mkdir -p "$GEO"
cd "$GEO"
if [[ ! -f IN.txt ]]; then
  curl -fsSL -o IN.zip https://download.geonames.org/export/dump/IN.zip
  python3 -m zipfile -e IN.zip .
  curl -fsSL -o admin1CodesASCII.txt https://download.geonames.org/export/dump/admin1CodesASCII.txt
  curl -fsSL -o admin2Codes.txt https://download.geonames.org/export/dump/admin2Codes.txt
fi
NET=$(docker inspect gixbee_postgres --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')
docker run --rm --network "$NET" \
  -v /root/gixbeesolutions/scripts/import-hiring-locations.py:/import.py:ro \
  -v "$GEO":/data:ro \
  python:3.12-slim bash -c \
  'pip install -q psycopg[binary] && python /import.py --dir /data --database-url postgresql://postgres:gixbee123@postgres:5432/gixbee_db'
echo LOCATIONS_IMPORTED
