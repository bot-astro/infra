# Astro infra: implementation plan

Own repo (`bot-astro/infra`), modelled on `index-it/infra`. The cluster itself (Hetzner/k3s, ArgoCD, sealed-secrets, nginx, cert-manager) stays in `Giuliopime/gport`.
Terraform for Astro-specific resources (Cloudflare, BigQuery, Infisical) lives here, in `terraform/`.

## Target layout

```
infra/
  PLAN.md
  README.md
  root-argocd-app.yml            # app-of-apps -> appsets/
  appsets/appset.yml             # git dir generator on apps/*/envs/*
  apps/
    bot/                         # StatefulSet, headless svc (ports from chart on master)
    api-central/                 # Deployment, svc, ingress (api.astro-bot.space)
    support-bot/                 # StatefulSet, svc, ingress (support-bot.astro-bot.space)
    entitlements-expiration-job/ # CronJob "0 1 * * *"
      base/                      # workload manifests + kustomization.yml
      envs/<env>/                # astro, astro-staging: kustomization.yml, version.yml, resources.yml, replicas.yml, *-sealed.yml, secrets/
  terraform/
    cloudflare/                  # R2 bucket, custom domain, DNS records, R2 API token
    gcp/                         # BigQuery dataset + tables, service account + key
  scripts/seal-secrets.sh        # copy from index-it/infra
```

## Phases

### 1. Kubernetes manifests (Helm charts on `master` -> kustomize)
Source: `git show master:services/<svc>/chart/templates/*` (+ `services/api-central/chart/values.yaml` on this branch).
- One `apps/<svc>/base` per service. Inline the values (name, port, probes, nodeSelector `gport.giuliopime.dev/agent: as-cruiser`, preStop `/shutdown`).
- `envs/<env>` patches: `version.yml` (image tag, the only file CI touches), `replicas.yml`, `resources.yml`, `ingress.yml`.
- Ports: bot 9000, api-central 9001, support-bot 9002.
- Config: charts use `envFrom configMapRef` (`bot-config`, ...). Decide the source for config + secrets (see phase 4).
- Sealed secrets per app: `docker-registry` (ghcr pull), `gcp-bigquery-creds` (bot, mounted at `/etc/astro-bot/secrets`), plus whatever phase 4 doesn't cover.
- Fixes to carry over (old charts are buggy): ingress backend names are hardcoded (`support-api`, `central-api`) and support-bot's ingress lacks `ingressClassName: nginx`; derive from the service name.
- bot is a StatefulSet with shard ordinal logic (`POD_ORDINAL`, `BOT_SHARD_MANAGER_*`): keep as is, pod count must stay in sync with `TOTAL_PODS`.

### 2. ArgoCD
- `root-argocd-app.yml` + `appsets/appset.yml` copied from index-it, repoURL -> `bot-astro/infra`, namespace per app. The appset names apps `<svc>-<env>` and uses the env folder (`astro` / `astro-staging`) as the destination namespace, so all services of an env share one namespace.
- Register the repo in ArgoCD (private repo -> deploy key / credentials secret, in gport's `argocd-installation`).
- Mark the CronJob so a version bump doesn't trigger an immediate run (CronJob is fine, just a spec change).

### 3. CI deploy step
Index has no automation (`version.yml` is edited by hand); this adds it on top of the same layout.
- Jib already pushes `<sha>`, `<version>`, `latest` (`service-conventions.gradle.kts`). Both envs reference the **git SHA** for now.
- `scripts/bump-version.sh <app> <env> <tag>` (done) edits `apps/<app>/envs/<env>/version.yml` with `yq`.
- Semaphore, per service after the Jib push:
  - **astro-staging**: automatic block on every push to the branch. Clones `bot-astro/infra` with a write deploy key (Semaphore secret), runs the script, commits `deploy(<app>): astro-staging <sha>`, `git pull --rebase`, pushes (retry once, services run in parallel).
  - **astro (prod)**: Semaphore promotion with manual approval, same job with env `astro`.
- Later option: switch to the version tag for prod once you bump versions per release.

### 4. Terraform
Location: `infra/terraform/*` (not gport). gport owns cluster-level things only; Astro DNS, buckets, datasets belong with the app. Remote state: Cloudflare R2 backend or GCS bucket (decide; avoid local state like gport's committed `terraform.tfstate`).
- **cloudflare/**: from `infra-notes.md`: R2 bucket `astro-media-{env}` (staging + prod), custom domain `cdn.astro-bot.space`, API token `astro-r2-{env}` (R2 read/write on that bucket) -> output access key id/secret into Infisical. DNS A records for `api`, `support-bot` -> cluster ingress IP (variable `ingress_ipv4`, from gport's `module.kube-hetzner.ingress_public_ipv4`).
- **gcp/**: dataset (`BOT__BIGQUERY_DATASET_NAME`), tables `TEMPORARY_VC_GENERATION`, `SLASH_COMMAND_INVOCATION`, `CONNECTION_INVOCATION`, `GUILD_EVENT` (schemas from `astro-overview` skill; `DAY` partition on `timestamp`, `require_partition_filter = true`), service account with `bigquery.dataEditor` on the dataset + `bigquery.jobUser`, key written to Infisical (replaces committed `gcp-bigquery-creds.json`).
- **Infisical**: reuses the existing project environments `staging` and `prod` (flat secret list per environment, service-prefixed names). Terraform (cloudflare, gcp) only writes the generated secrets (R2, BigQuery); hand-entered ones (Discord tokens, Chargebee, Mongo URI) stay manual in the UI.
- Secrets -> cluster: use the Infisical Kubernetes Operator (`InfisicalStaticSecret` -> Secret/ConfigMap, `auto-reload` annotation) instead of sealed secrets for app config. Sealed secrets only for bootstrap items (ghcr pull secret, operator machine identity credentials, ArgoCD repo key). Requires installing the operator in gport.

### 5. Docs
- README: bootstrap order (gport cluster -> ArgoCD -> sealed-secrets/Infisical operator -> `kubectl apply -f root-argocd-app.yml`), how to seal secrets, how deploys work, rollback via `git revert`.

## Decisions
- Environments: `astro` (prod) and `astro-staging`; folder name = namespace = Infisical env, derived by the appset from the path.
- Secrets: Infisical Kubernetes Operator for app config (`<app>-config` Secrets, `gcp-bigquery-creds`); sealed secrets only for bootstrap (`docker-registry` per namespace).
- Image tag: git SHA in both envs for now.
- Deploys: staging on every push, prod via manual approval.
- Terraform state: Cloudflare R2 bucket (S3 backend), created by hand once.

## Status
- [x] Phase 1: base + both envs for the 4 apps (all 8 overlays pass `kustomize build`)
- [x] Phase 2: `appsets/appset.yml`, `root-argocd-app.yml`, `.gitignore`, `scripts/{seal-secrets,bump-version}.sh`
- [x] Probes use a separate unauthenticated management port (not exposed by Services/Ingresses): bot 9100, api-central 9101, support-bot 9102 (`management.server.port`, env `BOT__/CA__/SB__MANAGEMENT_PORT`). `KUBE_LIFECYCLE_AUTH_KEY` / `KubeProperties` / `KubeAuthFilter` removed from the services, custom `/ready` and `/shutdown` preStop hooks dropped (SIGTERM + `@PreDestroy` instead). App ports to set in Infisical: `BOT_API_PORT=9000`, `CA__PORT=9001`, `SB__PORT=9002`.
- [x] Phase 3: Semaphore (astro repo): staging auto-promoted on every passing build of a changed service, production manual; `scripts/deploy.sh` here. Needs the `infra-deploy-key` Semaphore secret.
- [x] Phase 4: Terraform modules written and `terraform validate`d (not planned/applied); Infisical operator CRs per env (`apps/infisical`, `infisical-secret.yml` per app)
- [x] Phase 5: README
- [ ] Not done yet: create R2 state bucket, run terraform, fill the remaining Infisical secrets in `staging`/`prod`, install the operator + ArgoCD repo, seal bootstrap secrets
- Assumed staging hosts: `api-staging.astro-bot.space`, `support-bot-staging.astro-bot.space`

## Heads-up
`services/api-central/chart/values.yaml` on this branch is committed with a real-looking `auth` token. Rotate `KUBE_LIFECYCLE_AUTH_KEY` once it moves to a secret.

## Infisical: values you still have to set
Prod values were copied from the old `astro` namespace ConfigMaps; staging has no ConfigMaps, so everything environment specific is missing.
`BOT__POD_HOSTNAME` / `BOT__POD_ORDINAL` are only in `dev` (the StatefulSet sets them in the cluster). `KUBE_LIFECYCLE_AUTH_KEY` was deleted (unused).

**`prod` (`astro`)**
- All keys set (`FRONTEND_BASE_URL`, `CA__SESSION_COOKIE_DOMAIN`, `SB__DISCORD_APPLICATION_ACTIVITY_*`).
- Check: `DISCORD_OAUTH_REDIRECT_URI` is set to `https://api.astro-bot.space/v2/auth/discord/callback` (new API), and that URL must be registered in the Discord developer portal.
- Check: `BOT__BIGQUERY_DATASET_NAME` is `astro_bot` (the existing dataset). `terraform/gcp` would create `astro_prod` and overwrite this secret: either set `dataset_id = "astro_bot"` for prod and import the dataset, or accept a new dataset.
- Check: `MONGODB_URI` is the Atlas string from the old config, `REDIS_*` points to `redis-master.databases.svc.cluster.local` (password taken from the old URI).

**`staging` (`astro-staging`)**: everything below is missing.
`BOT__DISCORD_APPLICATION_ID`, `BOT__DISCORD_APPLICATION_TOKEN`, `EEJ__DISCORD_APPLICATION_ID`, `EEJ__DISCORD_APPLICATION_TOKEN`, `DISCORD_OAUTH_ID`, `DISCORD_OAUTH_SECRET`, `CA__AUTH`, `CA__SESSION_COOKIE_ALLOW_ORIGIN`, `CHARGEBEE_API_KEY` (site name is set to `astro-bot-test`), `MONGODB_URI`, `REDIS_HOST`, `REDIS_PASSWORD`, `BOT__BIGQUERY_DATASET_NAME` (terraform: `astro_staging`), `SB__API_AUTH`, `SB__DISCORD_APPLICATION_TOKEN`, `SB__SERVER_GUILD_ID`, `SB__SERVER_PREMIUM_ROLE_ID`, `SB__SERVER_PREMIUM_SKU_ID`, `SB__SERVER_ENTITLEMENTS_APPLICATION_ID`, `SB__SERVER_ENTITLEMENTS_APPLICATION_TOKEN`.
Staging shard settings are `1` pod / `1` shard (prod is 11 / 176).
