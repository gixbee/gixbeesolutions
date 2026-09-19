#!/bin/bash
set -euo pipefail
cd /home/azureuser/gixbeesolutions
python3 <<'PY'
from pathlib import Path
p = Path("docker-compose.yml")
t = p.read_text()
old = "AAAAC3NzaC1lZDI1NTE5AAAAIC17mUbLsNFJB9szC7LwFWEIfUBCNAJFNbkb2DzWW9Ja"
new = "AAAAC3NzaC1lZDI1NTE5AAAAIPMLp6vOhwcc/NgIDeklkLtrSlhlIvKKV5Tg+dn+hhAc"
if old not in t:
    raise SystemExit("old key not found")
p.write_text(t.replace(old, new, 1))
print("key updated")
PY
grep KEY docker-compose.yml
COMPOSE_PROFILES=rust docker compose up -d --force-recreate beszel-agent
docker compose ps beszel-agent
