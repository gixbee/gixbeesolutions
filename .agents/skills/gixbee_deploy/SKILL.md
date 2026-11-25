---
name: gixbee_deploy
description: Deploy Gixbee to production on the MilesWeb VPS (Rust backend) or verify container health. Do not deploy to Azure or AWS.
---

# Gixbee MilesWeb Production Deployment

**Production host:** MilesWeb VPS `103.102.234.152`  
**SSH user:** `root`  
**SSH key:** `C:\Users\gkv00\.ssh\gixbee-ec2`  
**Remote app path:** `/root/gixbeesolutions`  
**API (public):** `http://103.102.234.152:3000`  
**Admin:** `http://103.102.234.152/`

Do not deploy to Azure or AWS. Those hosts are not production.

## Step 1: Push to GitHub

```powershell
git push origin main
```

## Step 2: Pack and upload source

From repo root on Windows:

```powershell
cd C:\Users\gkv00\Music\gixbee
tar -czf "$env:TEMP\gixbee-milesweb.tgz" `
  --exclude=node_modules --exclude=.git --exclude=tmp `
  --exclude=super-admin-web/node_modules `
  --exclude=backend_rust/target --exclude=.dart_tool --exclude=build `
  --exclude=android --exclude=ios --exclude="*.apk" .

scp -i C:\Users\gkv00\.ssh\gixbee-ec2 -o StrictHostKeyChecking=no `
  "$env:TEMP\gixbee-milesweb.tgz" `
  C:\Users\gkv00\Music\gixbee\scripts\milesweb_sync_and_deploy.sh `
  root@103.102.234.152:/tmp/
```

## Step 3: Migrate schema + build + restart (on the VPS)

Runs SQL bundles, builds `backend_rust` + `admin`, starts the stack:

```powershell
ssh -i C:\Users\gkv00\.ssh\gixbee-ec2 -o StrictHostKeyChecking=no root@103.102.234.152 `
  "sed -i 's/\r$//' /tmp/milesweb_sync_and_deploy.sh; nohup bash /tmp/milesweb_sync_and_deploy.sh > /tmp/deploy.log 2>&1 & echo DEPLOY_STARTED"
```

Rust Docker build can take **15–30+ minutes** on the VPS. Monitor:

```powershell
ssh -i C:\Users\gkv00\.ssh\gixbee-ec2 -o StrictHostKeyChecking=no root@103.102.234.152 "tail -30 /tmp/deploy.log; docker compose ps"
```

Success line: `DEPLOY_OK`

## Step 4: Verify

```powershell
Invoke-WebRequest -Uri "http://103.102.234.152:3000/" -UseBasicParsing
```

## Step 5: Flutter APK (optional)

Use project defines pointing at MilesWeb (see `gixbee_keys.bat` or `--dart-define=API_BASE_URL=http://103.102.234.152:3000`).

## Notes

- Preserves `deploy/.env`, the repo-root `.env`, and Firebase JSON on deploy (the script backs them up before replacing the tree).
- `docker image prune -f` runs after build. Keep it.
- See `docs/MASTER_DATA_ADMIN.md` for optional catalogue and location imports after deploy.
