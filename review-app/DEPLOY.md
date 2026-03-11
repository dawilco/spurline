# Deploying Spurline Review App

Target: `review.spurline.dev` on Debian server at 172.16.0.140

## Prerequisites

- Docker 28+ with compose
- Traefik v2.11 on ports 80/443 (already running)
- Postgres 15 (already running as `opt-postgres-1`)
- DNS: `review.spurline.dev` A record pointing to server IP

## 1. Create the Postgres database

```bash
ssh root@172.16.0.140

# Create the spurline database
docker exec -i opt-postgres-1 psql -U postgres -c "CREATE DATABASE spurline;"

# Apply the schema
docker exec -i opt-postgres-1 psql -U postgres -d spurline < /tmp/init.sql
```

Copy `review-app/db/init.sql` to the server first:
```bash
scp review-app/db/init.sql root@172.16.0.140:/tmp/init.sql
```

## 2. Set environment variables

Create `/opt/.env` on the server (or add to existing):

```bash
ANTHROPIC_API_KEY=sk-ant-your-key-here
GITHUB_TOKEN=ghp_your-token-here
GITHUB_WEBHOOK_SECRET=your-webhook-secret-here
```

Generate a webhook secret:
```bash
openssl rand -hex 32
```

## 3. Build and push the Docker image

From the repo root on your local machine:
```bash
docker build -f review-app/Dockerfile -t localhost:5000/spurline-review:latest .
docker push localhost:5000/spurline-review:latest
```

Or build directly on the server:
```bash
cd /path/to/spurline
docker build -f review-app/Dockerfile -t localhost:5000/spurline-review:latest .
docker push localhost:5000/spurline-review:latest
```

## 4. Add service to compose

Add the following to `/opt/compose.yml` under `services:`:

```yaml
  spurline-review:
    image: localhost:5000/spurline-review:latest
    container_name: spurline-review
    restart: unless-stopped
    networks:
      - proxy
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - GITHUB_TOKEN=${GITHUB_TOKEN}
      - GITHUB_WEBHOOK_SECRET=${GITHUB_WEBHOOK_SECRET}
      - DATABASE_URL=postgresql://postgres:murphy-mwah-horde2%40@postgres:5432/spurline
      - RACK_ENV=production
      - RUBY_YJIT_ENABLE=1
    depends_on:
      - postgres
    labels:
      - traefik.enable=true
      - traefik.http.routers.spurline.rule=Host(`review.spurline.dev`)
      - traefik.http.routers.spurline.entrypoints=websecure
      - traefik.http.routers.spurline.tls.certresolver=le
      - traefik.http.services.spurline.loadbalancer.server.port=9292
      - traefik.http.routers.spurline-http.rule=Host(`review.spurline.dev`)
      - traefik.http.routers.spurline-http.entrypoints=web
      - traefik.http.routers.spurline-http.middlewares=redirect-to-https
```

## 5. Start the service

```bash
cd /opt && docker compose up -d spurline-review
```

## 6. Verify

```bash
# Health check
curl https://review.spurline.dev/health

# Dashboard
curl https://review.spurline.dev/dashboard/sessions

# Check logs
docker logs spurline-review
```

## 7. Configure GitHub webhook

1. Go to https://github.com/dawilco/spurline/settings/hooks/new
2. Payload URL: `https://review.spurline.dev/webhooks/github`
3. Content type: `application/json`
4. Secret: same value as `GITHUB_WEBHOOK_SECRET`
5. Events: select "Issue comments", "Pull request review comments", "Pull request reviews"
6. Check "Active" and save

## Updating

```bash
# Rebuild and restart
cd /path/to/spurline
docker build -f review-app/Dockerfile -t localhost:5000/spurline-review:latest .
docker push localhost:5000/spurline-review:latest
cd /opt && docker compose up -d --force-recreate spurline-review
```
