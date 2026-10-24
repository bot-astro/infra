terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    infisical = {
      source  = "Infisical/infisical"
      version = "~> 0.15"
    }
  }
  backend "s3" {
    key    = "gcp.tfstate"
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

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_location
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
  # prod is the dataset that already existed (astro_bot, holds the historical analytics): imports.tf brings it and its
  # tables under terraform without touching the data. Tables have deletion_protection and prevent_destroy.
  envs = {
    prod    = { infisical_env = "prod", dataset_id = "astro_bot" }
    staging = { infisical_env = "staging", dataset_id = "astro_staging" }
  }

  # Same schema as the tables in astro_bot (snake_case, the bot writes with the application JSON mapper)
  tables = {
    TEMPORARY_VC_GENERATION = [
      { name = "guild_id", type = "NUMERIC" },
      { name = "user_id", type = "NUMERIC" },
      { name = "generator_id", type = "NUMERIC" },
      { name = "timestamp", type = "TIMESTAMP" },
    ]
    SLASH_COMMAND_INVOCATION = [
      { name = "name", type = "STRING" },
      { name = "guild_id", type = "NUMERIC" },
      { name = "channel_id", type = "NUMERIC" },
      { name = "user_id", type = "NUMERIC" },
      { name = "main_option_name", type = "STRING", mode = "NULLABLE" },
      { name = "main_option_value", type = "STRING", mode = "NULLABLE" },
      { name = "raw_options", type = "STRING", mode = "NULLABLE" },
      { name = "timestamp", type = "TIMESTAMP" },
    ]
    CONNECTION_INVOCATION = [
      { name = "guild_id", type = "NUMERIC" },
      { name = "user_id", type = "NUMERIC" },
      { name = "connection_id", type = "NUMERIC" },
      { name = "timestamp", type = "TIMESTAMP" },
    ]
    GUILD_EVENT = [
      { name = "guild_id", type = "NUMERIC" },
      { name = "users_count", type = "INTEGER" },
      { name = "action", type = "STRING" }, # JOINED | KICKED
      { name = "timestamp", type = "TIMESTAMP" },
    ]
    # legacy table, the new bot does not write it, kept because prod has it (and its data)
    GUILD_SNAPSHOT = [
      { name = "guild_id", type = "NUMERIC" },
      { name = "guild_name", type = "STRING" },
      { name = "member_count", type = "INTEGER" },
      { name = "shard_id", type = "INTEGER" },
      { name = "timestamp", type = "TIMESTAMP" },
    ]
  }

  clustering = {
    GUILD_SNAPSHOT = ["guild_id"]
  }

  env_tables = merge([
    for env, cfg in local.envs : {
      for table, schema in local.tables : "${env}/${table}" => { env = env, table = table, schema = schema }
    }
  ]...)
}

resource "google_bigquery_dataset" "analytics" {
  for_each = local.envs

  dataset_id = each.value.dataset_id
  location   = var.gcp_location

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_bigquery_table" "analytics" {
  for_each = local.env_tables

  dataset_id          = google_bigquery_dataset.analytics[each.value.env].dataset_id
  table_id            = each.value.table
  deletion_protection = true
  clustering          = lookup(local.clustering, each.value.table, null)

  require_partition_filter = true
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }

  schema = jsonencode([
    for column in each.value.schema : {
      name = column.name
      type = column.type
      mode = lookup(column, "mode", "REQUIRED")
    }
  ])

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_service_account" "bot" {
  for_each = local.envs

  account_id   = "astro-bot-${each.key}"
  display_name = "Astro bot (${each.key})"
}

resource "google_bigquery_dataset_iam_member" "bot_data_editor" {
  for_each = local.envs

  dataset_id = each.value.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.bot[each.key].email}"
}

resource "google_project_iam_member" "bot_job_user" {
  for_each = local.envs

  project = var.gcp_project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.bot[each.key].email}"
}

resource "google_service_account_key" "bot" {
  for_each = local.envs

  service_account_id = google_service_account.bot[each.key].name
}

locals {
  secrets = merge([
    for env, cfg in local.envs : {
      "${env}/BOT__BIGQUERY_DATASET_NAME" = { env = cfg.infisical_env, name = "BOT__BIGQUERY_DATASET_NAME", value = cfg.dataset_id }
      # service account key, mounted as a file by the bot (GOOGLE_APPLICATION_CREDENTIALS)
      "${env}/BOT__GCP_CREDENTIALS_JSON" = { env = cfg.infisical_env, name = "BOT__GCP_CREDENTIALS_JSON", value = base64decode(google_service_account_key.bot[env].private_key) }
    }
  ]...)
}

resource "infisical_secret" "bot" {
  for_each = nonsensitive(toset(keys(local.secrets)))

  name         = local.secrets[each.key].name
  value        = local.secrets[each.key].value
  env_slug     = local.secrets[each.key].env
  workspace_id = var.infisical_project_id
  folder_path  = "/"
}
