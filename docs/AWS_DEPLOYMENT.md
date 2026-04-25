# Gixbee — AWS Deployment Guide

> Full Docker Compose stack on AWS.
> Free for 12 months (t2.micro) → ~$10–15/month after free tier.

---

## AWS Free Tier — What you get for 12 months

| Service | Free Tier | Gixbee usage |
|---|---|---|
| EC2 t2.micro | 750 hrs/month | ✅ Run all 4 containers |
| RDS PostgreSQL | 750 hrs/month (db.t3.micro) | ✅ Or use Docker PostgreSQL |
| ElastiCache | 750 hrs/month (cache.t3.micro) | ✅ Or use Docker Redis |
| S3 | 5 GB storage | ✅ File uploads |
| Data transfer | 15 GB/month outbound | ✅ Enough for early users |
| Route 53 | $0.50/hosted zone | Domain DNS |
| ACM (SSL) | Free | ✅ HTTPS certificates |

**Recommended approach:** Run PostgreSQL and Redis inside Docker on the same EC2 instance
during free tier. Switch to RDS + ElastiCache only when you scale.

---

## Architecture

```
Internet
    │
    ▼
Route 53 (DNS)
    │
    ▼
ACM Certificate (SSL)
    │
    ▼
Application Load Balancer  ← optional, use Nginx for now
    │
    ▼
EC2 t2.micro (Ubuntu 22.04)
    │
    └── Docker Compose
          ├── Nginx      :80 / :443
          ├── NestJS     :3000
          ├── PostgreSQL :5432
          └── Redis      :6379

S3 Bucket ← file uploads (replaces local uploads/ folder)
ECR       ← Docker image registry (optional, use DockerHub for now)
```

---

## Step 1 — Create AWS Account & Set Region

1. Go to [aws.amazon.com](https://aws.amazon.com) → Create account
2. Set region to **ap-south-1 (Mumbai)** — closest to your users in India
3. Enable MFA on root account (security requirement)
4. Create an IAM user with programmatic access — never use root credentials

---

## Step 2 — Launch EC2 Instance (Free Tier)

### In AWS Console → EC2 → Launch Instance

```
Name:           gixbee-server
AMI:            Ubuntu Server 22.04 LTS (HVM), SSD Volume Type
Architecture:   x86_64
Instance type:  t2.micro  ← FREE TIER eligible
Key pair:       Create new → gixbee-key → Download .pem file
Storage:        20 GB gp3 (free tier gives 30 GB)
```

### Security Group — open these ports

| Type | Protocol | Port | Source | Purpose |
|---|---|---|---|---|
| SSH | TCP | 22 | Your IP only | Server access |
| HTTP | TCP | 80 | 0.0.0.0/0 | Web traffic |
| HTTPS | TCP | 443 | 0.0.0.0/0 | Secure web traffic |
| Custom TCP | TCP | 3000 | 0.0.0.0/0 | Temp: direct NestJS access for testing |

> Remove port 3000 from public access once Nginx is configured.

### Allocate an Elastic IP (static IP address)

EC2 → Elastic IPs → Allocate → Associate to your instance.
This gives you a permanent IP that doesn't change on restart. Free while associated.

---

## Step 3 — Connect to EC2 & Install Docker

```bash
# Set permissions on your key
chmod 400 ~/Downloads/gixbee-key.pem

# SSH into the server
ssh -i ~/Downloads/gixbee-key.pem ubuntu@<your-elastic-ip>

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker ubuntu
newgrp docker

# Install Docker Compose plugin
sudo apt install docker-compose-plugin -y

# Verify
docker --version
docker compose version
```

---

## Step 4 — Set Up S3 for File Uploads

Your current setup saves uploads to the local filesystem (`uploads/` folder).
On EC2 this works but files are lost if the instance is replaced.
S3 gives you durable, scalable, cheap storage.

### Create S3 Bucket

```bash
# In AWS CLI (or use the console)
aws s3 mb s3://gixbee-uploads --region ap-south-1

# Block all public access (serve files via signed URLs or through NestJS)
aws s3api put-public-access-block \
  --bucket gixbee-uploads \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,\
    BlockPublicPolicy=true,RestrictPublicBuckets=true
```

### Create IAM User for S3 access

```
IAM → Users → Create user → gixbee-s3-user
Attach policy: AmazonS3FullAccess (or create a scoped policy below)
Generate access keys → save Access Key ID and Secret
```

Scoped S3 policy (recommended over full access):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::gixbee-uploads/*"
    }
  ]
}
```

### Install AWS SDK in NestJS

```bash
npm install @aws-sdk/client-s3 @aws-sdk/s3-request-presigner
```

### Create `src/uploads/s3.service.ts`

```typescript
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  S3Client,
  PutObjectCommand,
  DeleteObjectCommand,
  GetObjectCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { v4 as uuid } from 'uuid';

@Injectable()
export class S3Service {
  private readonly client: S3Client;
  private readonly bucket: string;

  constructor(private readonly config: ConfigService) {
    this.client = new S3Client({
      region: config.get('AWS_REGION', 'ap-south-1'),
      credentials: {
        accessKeyId: config.get('AWS_ACCESS_KEY_ID')!,
        secretAccessKey: config.get('AWS_SECRET_ACCESS_KEY')!,
      },
    });
    this.bucket = config.get('AWS_S3_BUCKET', 'gixbee-uploads');
  }

  // Upload a file buffer to S3
  async uploadFile(
    buffer: Buffer,
    mimetype: string,
    folder: 'avatars' | 'documents' | 'reels' = 'avatars',
  ): Promise<string> {
    const key = `${folder}/${uuid()}-${Date.now()}`;

    await this.client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Body: buffer,
        ContentType: mimetype,
      }),
    );

    return key;   // store this key in your database
  }

  // Generate a signed URL to serve private files
  async getSignedUrl(key: string, expiresInSeconds = 3600): Promise<string> {
    const command = new GetObjectCommand({ Bucket: this.bucket, Key: key });
    return getSignedUrl(this.client, command, { expiresIn: expiresInSeconds });
  }

  // Delete a file
  async deleteFile(key: string): Promise<void> {
    await this.client.send(
      new DeleteObjectCommand({ Bucket: this.bucket, Key: key }),
    );
  }
}
```

Add to `.env`:
```
AWS_REGION=ap-south-1
AWS_ACCESS_KEY_ID=your-access-key-id
AWS_SECRET_ACCESS_KEY=your-secret-access-key
AWS_S3_BUCKET=gixbee-uploads
```

---

## Step 5 — Deploy Gixbee to EC2

```bash
# On the EC2 instance:

# 1. Clone your repo
git clone https://github.com/your-username/gixbee.git
cd gixbee

# 2. Create .env from template
cp .env.example .env
nano .env      # fill in all values

# 3. Build and start all containers
docker compose up --build -d

# 4. Check status
docker compose ps
docker compose logs -f backend
```

---

## Step 6 — SSL Certificate with AWS ACM + Certbot

### Option A — Certbot (free, simplest for single EC2)

```bash
# Install Certbot on the EC2 instance
sudo apt install certbot -y

# Stop Nginx temporarily
docker compose stop nginx

# Generate certificate
sudo certbot certonly --standalone -d your-domain.com

# Certificates are saved to:
# /etc/letsencrypt/live/your-domain.com/fullchain.pem
# /etc/letsencrypt/live/your-domain.com/privkey.pem

# Update docker-compose.yml nginx volumes to mount these:
# - /etc/letsencrypt:/etc/nginx/ssl:ro

# Start Nginx again
docker compose start nginx

# Auto-renew (add to crontab):
# 0 12 * * * certbot renew --quiet && docker compose restart nginx
```

Update `nginx/nginx.conf`:
```nginx
ssl_certificate     /etc/nginx/ssl/live/your-domain.com/fullchain.pem;
ssl_certificate_key /etc/nginx/ssl/live/your-domain.com/privkey.pem;
```

Update `docker-compose.yml` nginx volumes:
```yaml
nginx:
  volumes:
    - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    - /etc/letsencrypt:/etc/nginx/ssl:ro       # ← Certbot certs
    - uploads_data:/app/uploads:ro
```

### Option B — AWS ACM + ALB (when you add a load balancer)

1. ACM → Request certificate → enter your domain → DNS validation
2. Add the CNAME record to Route 53 → auto-validates
3. Create an Application Load Balancer → attach ACM cert → forward to EC2 port 80
4. ALB handles HTTPS, EC2 runs HTTP only

---

## Step 7 — Domain Setup with Route 53

```
Route 53 → Hosted Zones → Create hosted zone → your-domain.com

Add A record:
  Name:  @ (or your-domain.com)
  Type:  A
  Value: <your-elastic-ip>

Add A record:
  Name:  api
  Type:  A
  Value: <your-elastic-ip>
```

Update your Flutter `dart-define` for production:
```bash
flutter build apk \
  --dart-define=API_BASE_URL=https://api.your-domain.com \
  --dart-define=SOCKET_URL=https://api.your-domain.com \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=RAZORPAY_KEY=rzp_live_xxx \
  --dart-define=BUILD_VERSION=1.0.0 \
  --release
```

---

## Step 8 — GitHub Actions CI/CD (auto-deploy on push)

Create `.github/workflows/deploy.yml` in your repo:

```yaml
name: Deploy to AWS EC2

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Deploy to EC2 via SSH
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.EC2_HOST }}
          username: ubuntu
          key: ${{ secrets.EC2_SSH_KEY }}
          script: |
            cd /home/ubuntu/gixbee
            git pull origin main
            docker compose up --build -d --remove-orphans
            docker image prune -f
```

### Add these GitHub Secrets

```
EC2_HOST         → your Elastic IP
EC2_SSH_KEY      → contents of gixbee-key.pem
```

Now every push to `main` automatically deploys to your EC2 instance.

---

## Cost breakdown — AWS ap-south-1 (Mumbai)

### Free tier (first 12 months)

| Service | Cost |
|---|---|
| EC2 t2.micro | $0 (750 hrs free) |
| EBS 20 GB gp3 | $0 (30 GB free) |
| Elastic IP | $0 (free when associated) |
| S3 5 GB | $0 |
| Data transfer 15 GB | $0 |
| ACM SSL | $0 |
| **Total** | **$0/month** |

### After free tier (~month 13+)

| Service | Cost |
|---|---|
| EC2 t3.micro (upgrade) | ~$7.50/mo |
| EBS 20 GB gp3 | ~$1.60/mo |
| Elastic IP | $0 (associated) |
| S3 (10 GB + requests) | ~$0.25/mo |
| Data transfer (20 GB) | ~$1.70/mo |
| Route 53 hosted zone | $0.50/mo |
| **Total** | **~$11–12/month** |

---

## Upgrade path as you scale

```
Now (free tier):
  EC2 t2.micro → all 4 containers on one instance

~50 users:
  EC2 t3.small ($13/mo) → more RAM for containers

~500 users:
  EC2 t3.medium ($26/mo)
  Move PostgreSQL → RDS db.t3.micro ($15/mo, managed backups)
  Move Redis → ElastiCache cache.t3.micro ($12/mo, managed)

~5000 users:
  EC2 Auto Scaling Group behind ALB
  RDS Multi-AZ
  ElastiCache cluster
  CloudFront CDN for uploads
```

---

## Monitoring (free)

### CloudWatch (built into AWS — free tier)

```bash
# Install CloudWatch agent on EC2
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i amazon-cloudwatch-agent.deb
```

Set up alerts for:
- CPU > 80%
- Memory > 85%
- Disk > 80%

### Docker container health

```bash
# On the EC2 instance — check all container status
docker compose ps

# Watch logs in real time
docker compose logs -f

# Check resource usage
docker stats
```

---

## Security checklist for AWS

- [ ] Root account has MFA enabled
- [ ] IAM user created — never use root for deployments
- [ ] Security group allows SSH only from your IP (not 0.0.0.0/0)
- [ ] Port 3000 removed from public security group after Nginx is set up
- [ ] S3 bucket has public access blocked
- [ ] `.env` file is NOT in git (confirmed in `.gitignore`)
- [ ] `firebase-service-account.json` NOT in git
- [ ] All secrets in `.env` on the server — not hardcoded anywhere
- [ ] Elastic IP associated (so IP doesn't change)
- [ ] SSL certificate installed and HTTP → HTTPS redirect active
- [ ] GitHub Actions secret `EC2_SSH_KEY` set correctly
- [ ] Docker containers restart automatically (`restart: unless-stopped`)
- [ ] CloudWatch alerts set for CPU and disk

---

## Quick reference commands (on EC2)

```bash
# Start everything
docker compose up -d

# Stop everything
docker compose down

# Rebuild after code change
docker compose up --build -d

# View logs
docker compose logs -f backend
docker compose logs -f nginx

# Open PostgreSQL shell
docker exec -it gixbee_postgres psql -U postgres -d gixbee

# Open Redis shell
docker exec -it gixbee_redis redis-cli -a your-redis-password

# Restart just one service
docker compose restart backend

# Check disk usage
df -h
docker system df

# Free up disk (remove old images)
docker image prune -f
```
