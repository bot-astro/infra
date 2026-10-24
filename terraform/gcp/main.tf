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
  envs = {
    prod    = { infisical_env = "prod", dataset_id = "astro_prod" }
    staging = { infisical_env = "staging", dataset_id = "astro_staging" }
  }

  # Column names are the field names of the events in services/bot/.../models/analytics
  # (the BigQuery client writes them as they are, camelCase)
  tables = {
    TEMPORARY_VC_GENERATION = [
      { name = "guildId", type = "INTEGER" },
      { name = "userId", type = "INTEGER" },
      { name = "generatorId", type = "INTEGER" },
      { name = "timestamp", type = "TIMESTAMP" },
    ]
    SLASH_COMMAND_INVOCATION = [
      { name = "name", type = "STRING" },
      { name = "guildId", type = "INTEGER" },
      { name = "channelId", type = "INTEGER" },
      { name = "userId", type = "INTEGER" },
      { name = "mainOptionName", type = "STRING", mode = "NULLABLE" },
      { name = "mainOptionValue", type = "STRING", mode = "NULLABLE" },
      { name = "rawOptions", type = "STRING", mode = "NULLABLE" },
      { name = "timestamp", type = "TIMESTAMP" },
    ]
    CONNECTION_INVOCATION = [
      { name = "guildId", type = "INTEGER" },
      { name = "userId", type = "INTEGER" },
      { name = "connectionId", type = "INTEGER" },
      { name = "timestamp", type = "TIMESTAMP" },
    ]
    GUILD_EVENT = [
      { name = "guildId", type = "INTEGER" },
      { name = "usersCount", type = "INTEGER" },
      { name = "action", type = "STRING" }, # JOINED | KICKED
      { name = "timestamp", type = "TIMESTAMP" },
    ]
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
}

resource "google_bigquery_table" "analytics" {
  for_each = local.env_tables

  dataset_id          = google_bigquery_dataset.analytics[each.value.env].dataset_id
  table_id            = each.value.table
  deletion_protection = true

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
}

resource "google_service_account" "bot" {
  for_each = local.envs

  account_id   = "astro-bot-${each.key}"
  display_name = "Astro bot (${each.key})"
}

resource "google_bigquery_dataset_iam_member" "bot_data_editor" {
  for_each = local.envs

  dataset_id = google_bigquery_dataset.analytics[each.key].dataset_id
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
      "${env}/BOT__BIGQUERY_DATASET_NAME" = { env = cfg.infisical_env, name = "BOT__BIGQUERY_DATASET_NAME", value = google_bigquery_dataset.analytics[env].dataset_id }
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
