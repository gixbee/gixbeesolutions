---
name: gixbee_deploy
description: Deploy Gixbee to production on Azure VM (Rust backend) or verify container health. Do NOT use AWS EC2 unless explicitly requested.
---

# Gixbee Azure Production Deployment

**Production host:** Azure VM `20.106.171.188`  
**SSH user:** `azureuser`  
**SSH key:** `C:\Users\gkv00\.ssh\gixbee-ec2`  
**Remote app path:** `/home/azureuser/gixbeesolutions`  
**API (public):** `http://20.106.171.188:3000`  
**Admin (when deployed):** `http://20.106.171.188/`

Legacy AWS EC2 (`13.233.60.215`) is **deprecated** — do not deploy there by default.

## Step 1: Push to GitHub

```powershell
git push origin main
```

## Step 2: Pack and upload source

From repo root on Windows:

```powershell
cd C:\Users\gkv00\Music\gixbee
tar -czf "$env:TEMP\gixbee-azure.tgz" `
  --exclude=node_modules --exclude=.git --exclude=tmp `
  --exclude=super-admin-web/node_modules `
  --exclude=backend_rust/target --exclude=.dart_tool --exclude=build `
  --exclude=android --exclude=ios --exclude="*.apk" .

scp -i C:\Users\gkv00\.ssh\gixbee-ec2 -o StrictHostKeyChecking=no `
  "$env:TEMP\gixbee-azure.tgz" `
  C:\Users\gkv00\Music\gixbee\scripts\azure_sync_and_deploy.sh `
  azureuser@20.106.171.188:/tmp/
```

## Step 3: Migrate schema + build + restart (on VM)

Runs SQL bundles, builds `backend_rust` + `admin`, starts stack:

```powershell
ssh -i C:\Users\gkv00\.ssh\gixbee-ec2 -o StrictHostKeyChecking=no azureuser@20.106.171.188 `
  "sed -i 's/\r$//' /tmp/azure_sync_and_deploy.sh; nohup bash /tmp/azure_sync_and_deploy.sh > /tmp/deploy.log 2>&1 & echo DEPLOY_STARTED"
```

Rust Docker build can take **15–30+ minutes** on the VM. Monitor:

```powershell
ssh -i C:\Users\gkv00\.ssh\gixbee-ec2 -o StrictHostKeyChecking=no azureuser@20.106.171.188 "tail -30 /tmp/deploy.log; docker compose ps"
```

Success line: `DEPLOY_OK`

## Step 4: Verify

```powershell
Invoke-WebRequest -Uri "http://20.106.171.188:3000/" -UseBasicParsing
```

## Step 5: Flutter APK (optional)

Use project defines pointing at Azure (see `gixbee_keys.bat` or `--dart-define=API_BASE_URL=http://20.106.171.188:3000`).

## Notes

- Preserves `deploy/.env` and Firebase JSON on deploy (script backs up before replacing tree; legacy `backend/.env` is migrated if present).
- `docker image prune -f` runs after build — keep it.
- See `docs/MASTER_DATA_ADMIN.md` for optional catalogue/location imports after deploy.
