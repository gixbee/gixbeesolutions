---
name: gixbee_deploy
description: Automated workflow for deploying Gixbee backend changes to AWS EC2 or checking live server Docker container health.
---

# Gixbee Automated EC2 Deployment Skill

Use this skill whenever asked to deploy backend code, publish changes to the live server, or verify production container health on AWS EC2.

## Target Environment Constants
- **AWS Instance ID**: `i-0263e6862a2e32e59` (ap-south-1)
- **Public IP**: `13.233.60.215`
- **OS User**: `ec2-user` (Amazon Linux 2023)
- **Local SSH Public Key**: `C:\Users\gkv00\.ssh\gixbee-ec2.pub`
- **Local SSH Private Key**: `C:\Users\gkv00\.ssh\gixbee-ec2`
- **Remote Repository Path**: `/home/ec2-user/gixbeesolutions`

## Step 1: Ensure Local Code is Pushed
Before deploying, make sure all local backend changes are committed and pushed to `main`:
```powershell
git push origin main
```

## Step 2: Execute Automated Deployment via EC2 Instance Connect
Do NOT attempt standard SSH without pushing the public key first, as EC2 Instance Connect manages ephemeral key authorization. Execute this one-line command in PowerShell:

**Note:** Since ADR-009, `backend` (Nest) and `backend_rust` (Rust) are Compose profiles. Set `BACKEND_IMPL` in root `.env` and export `COMPOSE_PROFILES`. Default rollback path is **nest** until Rust is signed off for prod.

```powershell
aws ec2-instance-connect send-ssh-public-key --instance-id i-0263e6862a2e32e59 --instance-os-user ec2-user --ssh-public-key file://C:\Users\gkv00\.ssh\gixbee-ec2.pub ; ssh -i C:\Users\gkv00\.ssh\gixbee-ec2 -o StrictHostKeyChecking=no ec2-user@13.233.60.215 "cd /home/ec2-user/gixbeesolutions && git pull origin main && echo 'BACKEND_IMPL=nest' > .env && COMPOSE_PROFILES=nest docker compose up --build -d && docker image prune -f && docker compose ps"
```

The `docker image prune -f` is not optional. Each `--build` retags `gixbee-backend`
and orphans the previous ~443MB image; on an 8GB root volume roughly six deploys
fill the disk. Pruning only removes untagged images no container references, so it
never touches anything running. A `docker-prune.timer` on the host runs the same
cleanup weekly as a backstop.

## Step 3: Verify Container Health
After `docker compose up --build -d backend` completes, wait 5–10 seconds and verify that the `gixbee_backend` container transitions from `(health: starting)` to `(healthy)`:

```powershell
aws ec2-instance-connect send-ssh-public-key --instance-id i-0263e6862a2e32e59 --instance-os-user ec2-user --ssh-public-key file://C:\Users\gkv00\.ssh\gixbee-ec2.pub ; ssh -i C:\Users\gkv00\.ssh\gixbee-ec2 -o StrictHostKeyChecking=no ec2-user@13.233.60.215 "cd /home/ec2-user/gixbeesolutions && docker compose ps"
```

## Step 4: Check Free Disk
The root volume is only 8GB and a full disk breaks both Postgres writes and the
next build. Confirm usage stays under ~85%:

```powershell
aws ec2-instance-connect send-ssh-public-key --instance-id i-0263e6862a2e32e59 --instance-os-user ec2-user --ssh-public-key file://C:\Users\gkv00\.ssh\gixbee-ec2.pub ; ssh -i C:\Users\gkv00\.ssh\gixbee-ec2 -o StrictHostKeyChecking=no ec2-user@13.233.60.215 "df -h / && docker system df"
```

If it is still tight after pruning, the durable fix is growing the EBS volume
(`aws ec2 modify-volume --size 16`) followed by `sudo growpart /dev/nvme0n1 1`
and `sudo xfs_growfs /`.
