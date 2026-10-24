# Terraform

Two independent root modules, each with its own state in the R2 bucket `astro-terraform-state`:

| Module | Manages |
|---|---|
| `cloudflare/` | R2 buckets + custom domains + per-env API tokens, DNS records for the apps. Writes `R2_*` secrets to Infisical |
| `gcp/` | BigQuery datasets + tables, service accounts. Writes `BOT__BIGQUERY_DATASET_NAME` and `BOT__GCP_CREDENTIALS_JSON` to Infisical |

## Usage
1. Once, by hand: create the R2 bucket `astro-terraform-state` and an R2 API token (object read/write on it).
2. `cp backend.hcl.template backend.hcl`, fill in the account id. `export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...` with the token's S3 credentials.
3. In each module (`cloudflare` and `gcp`): create `terraform.tfvars` from `variables.tf` (gitignored), then
   ```shell
   terraform init -backend-config=../backend.hcl
   terraform plan
   terraform apply
   ```
`infisical_client_id/secret` are a universal-auth machine identity with write access to the project. The Infisical environments `staging` and `prod` already exist and hold the `R2_*` secrets set by hand: import them (`terraform import 'infisical_secret.r2["prod/R2_BUCKET_NAME"]' ...`) or delete them before the first apply of `cloudflare/`.
`ingress_ipv4` comes from gport (`module.kube-hetzner.ingress_public_ipv4`).
