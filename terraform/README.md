# Terraform

Two independent root modules, each with its own state in the R2 bucket `astro-terraform-state`:

| Module | Manages |
|---|---|
| `cloudflare/` | R2 buckets (`astro-media-prod`, `astro-media-staging`) + custom domains + per-env API tokens, DNS records for the apps. Writes `R2_*` secrets to Infisical |
| `gcp/` | BigQuery datasets + tables, service accounts. Prod is the pre-existing `astro_bot` dataset (project `astro-405113`), adopted through `imports.tf` (data untouched, tables have `deletion_protection` + `prevent_destroy`). Writes `BOT__BIGQUERY_DATASET_NAME` and `BOT__GCP_CREDENTIALS_JSON` to Infisical |

## Usage
1. Once, by hand: create the R2 bucket `astro-terraform-state` and an R2 API token (object read/write on it).
2. `cp backend.hcl.template backend.hcl`, fill in the account id. `export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...` with the token's S3 credentials.
3. In each module (`cloudflare` and `gcp`): create `terraform.tfvars` from `variables.tf` (gitignored), then
   ```shell
   terraform init -backend-config=../backend.hcl
   terraform plan
   terraform apply
   ```
`infisical_client_id/secret` are a universal-auth machine identity with write access to the project. The Infisical environments `staging` and `prod` already exist.

## Adopting what already exists in prod (first apply only)
- **Infisical secrets**: terraform creates `R2_*`, `BOT__BIGQUERY_DATASET_NAME` and `BOT__GCP_CREDENTIALS_JSON` in both envs and fails with "already exists" if they are there. Delete those keys in the Infisical `prod` (and `staging`) environment before the first apply, the values are regenerated.
- **R2 bucket**: prod used a hand-made bucket `astro-media` (empty). Check it is empty, delete it (this also frees the `cdn.astro-bot.space` custom domain, which can be attached to one bucket only), delete the old R2 API token, then terraform creates `astro-media-prod`.
- **DNS**: the prod records `api` and `support-bot` exist, import them instead of recreating:
  ```shell
  # record ids: Cloudflare dashboard -> DNS, or  curl -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "https://api.cloudflare.com/client/v4/zones/<zone_id>/dns_records?name=api.astro-bot.space"
  terraform import 'cloudflare_dns_record.app["api"]' <zone_id>/<record_id>
  terraform import 'cloudflare_dns_record.app["support-bot"]' <zone_id>/<record_id>
  ```
- **BigQuery**: `gcp/imports.tf` imports the existing `astro_bot` dataset and its 5 tables. Read the plan: tables may only show no change, and there must be no `destroy`/`replace` of a table or dataset.
