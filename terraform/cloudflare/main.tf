terraform {
  required_version = ">= 1.6"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    infisical = {
      source  = "Infisical/infisical"
      version = "~> 0.15"
    }
  }

  backend "s3" {
    key    = "cloudflare.tfstate"
    region = "auto"

    # R2 is S3 compatible but has no AWS accounts, regions or metadata service
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "infisical" {
  host = var.infisical_host
  auth = {
    universal = {
      client_id     = var.infisical_client_id
      client_secret = var.infisical_client_secret
    }
  }
}

locals {
  envs = {
    prod = {
      infisical_env = "prod"
      cdn_domain    = "cdn.astro-bot.space"
      hosts         = ["api", "support-bot"]
    }
    staging = {
      infisical_env = "staging"
      cdn_domain    = "cdn-staging.astro-bot.space"
      hosts         = ["api-staging", "support-bot-staging"]
    }
  }

  r2_endpoint = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"

  dns_records = merge([
    for env, cfg in local.envs : {
      for host in cfg.hosts : host => host
    }
  ]...)
}

############
### R2 ###
############
resource "cloudflare_r2_bucket" "media" {
  for_each = local.envs

  account_id = var.cloudflare_account_id
  name       = "astro-media-${each.key}"
}

resource "cloudflare_r2_custom_domain" "media" {
  for_each = local.envs

  account_id  = var.cloudflare_account_id
  bucket_name = cloudflare_r2_bucket.media[each.key].name
  domain      = each.value.cdn_domain
  zone_id     = var.cloudflare_zone_id
  enabled     = true
}

# One token per environment, scoped to its bucket
resource "cloudflare_api_token" "r2" {
  for_each = local.envs

  name = "astro-r2-${each.key}"

  policies = [{
    effect = "allow"
    permission_groups = [
      { id = var.r2_bucket_item_write_permission_group_id },
    ]
    resources = {
      "com.cloudflare.edge.r2.bucket.${var.cloudflare_account_id}_default_${cloudflare_r2_bucket.media[each.key].name}" = "*"
    }
  }]
}

# R2 S3 credentials derive from the token: access key id = token id, secret access key = sha256(token value)
locals {
  r2_secrets = merge([
    for env, cfg in local.envs : {
      "${env}/R2_ACCESS_KEY_ID"     = { env = cfg.infisical_env, name = "R2_ACCESS_KEY_ID", value = cloudflare_api_token.r2[env].id }
      "${env}/R2_SECRET_ACCESS_KEY" = { env = cfg.infisical_env, name = "R2_SECRET_ACCESS_KEY", value = sha256(cloudflare_api_token.r2[env].value) }
      "${env}/R2_BUCKET_NAME"       = { env = cfg.infisical_env, name = "R2_BUCKET_NAME", value = cloudflare_r2_bucket.media[env].name }
      "${env}/R2_ENDPOINT_URL"      = { env = cfg.infisical_env, name = "R2_ENDPOINT_URL", value = local.r2_endpoint }
    }
  ]...)
}

resource "infisical_secret" "r2" {
  for_each = nonsensitive(toset(keys(local.r2_secrets)))

  name         = local.r2_secrets[each.key].name
  value        = local.r2_secrets[each.key].value
  env_slug     = local.r2_secrets[each.key].env
  workspace_id = var.infisical_project_id
  folder_path  = "/"
}

###########
### DNS ###
###########
resource "cloudflare_dns_record" "app" {
  for_each = local.dns_records

  zone_id = var.cloudflare_zone_id
  name    = each.value
  type    = "A"
  ttl     = 1
  proxied = true
  content = var.ingress_ipv4
}
