# Terraform

Two independent root modules, each with its own state in the R2 bucket `astro-terraform-state`:

| Module | Manages |
|---|---|
| `cloudflare/` | R2 buckets (`astro-media-prod`, `astro-media-staging`) + custom domains + per-env API tokens, DNS records for the apps. Writes `R2_*` secrets to Infisical |
| `gcp/` | BigQuery datasets + tables, service accounts. Prod is the pre-existing `astro_bot` dataset (project `astro-405113`), the data was adopted in place (tables have `deletion_protection` + `prevent_destroy`). Writes `BOT__BIGQUERY_DATASET_NAME` and `BOT__GCP_CREDENTIALS_JSON` to Infisical |

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
