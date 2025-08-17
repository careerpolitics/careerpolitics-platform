# Forem Helm Chart

Production-ready Helm chart for deploying Forem (Rails) with optional Sidekiq worker.

## Install

```bash
helm upgrade --install forem charts/forem \
  --namespace forem --create-namespace \
  --set image.repository=ghcr.io/forem/forem \
  --set rails.env.APP_DOMAIN=example.com \
  --set rails.env.APP_PROTOCOL=https:// \
  --set rails.secretEnv.SECRET_KEY_BASE=changeme \
  --set rails.secretEnv.DATABASE_URL="postgres://user:pass@postgres:5432/db" \
  --set rails.secretEnv.REDIS_URL="redis://redis:6379/0"
```

## Ingress

Enable and set host:

```bash
helm upgrade --install forem charts/forem \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host=example.com \
  --set ingress.hosts[0].paths[0].path=/ \
  --set ingress.hosts[0].paths[0].pathType=Prefix
```

## Persistence

```bash
helm upgrade --install forem charts/forem \
  --set persistence.enabled=true \
  --set persistence.storageClass=standard \
  --set persistence.size=10Gi
```

## Scaling

- Web HPA via values at `web.autoscaling.*`
- Sidekiq horizontal scaling set `worker.replicas`

## Migrations

A Helm hook job runs `./release-tasks.sh` on install/upgrade by default. Disable with `hooks.migrate.enabled=false`.