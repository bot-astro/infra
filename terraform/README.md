# Terraform

Two independent root modules, each with its own state in the R2 bucket `astro-terraform-state`:

| Module | Manages |
|---|---|
| `cloudflare/` | R2 buckets (`astro-media-prod`, `astro-media-staging`) + custom domains + per-env API tokens, DNS records for the apps. Writes `R2_*` secrets to Infisical |
| `gcp/` | BigQuery datasets + tables, service accounts. Prod is the pre-existing `astro_bot` dataset (project `astro-405113`), the data was adopted in place (tables have `deletion_protection` + `prevent_destroy`). Writes `BOT__BIGQUERY_DATASET_NAME`, `BOT__GCP_CREDENTIALS_JSON` and the api-central equivalents (`CA__BIGQUERY_ENABLED`, `CA__BIGQUERY_DATASET_NAME`, `CA__GCP_CREDENTIALS_JSON`, its own service account) to Infisical |

## Usage
1. Once, by hand: create the R2 bucket `astro-terraform-state` and an R2 API token (object read/write on it).
2. `cp backend.hcl.template backend.hcl`, fill in the account id. Store the token's S3 credentials in Infisical, once: `infisical secrets folders create --env=prod --path=/ --name=terraform`, then `infisical secrets set --env=prod --path=/terraform AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...`.
3. In each module (`cloudflare` and `gcp`): create `terraform.tfvars` from `variables.tf` (gitignored), then
   ```shell
   ../../scripts/terraform.sh <module> init -backend-config=../backend.hcl
   ../../scripts/terraform.sh <module> plan
   ../../scripts/terraform.sh <module> apply
   ```
   The script injects the credentials from Infisical, so nothing has to be exported. `backend.hcl` and `terraform.tfvars` are gitignored: run it from the main checkout, or copy them into a worktree.
`infisical_client_id/secret` are a universal-auth machine identity with write access to the project. The Infisical environments `staging` and `prod` already exist.
