# Brings the dataset and tables that already exist in prod (astro_bot) under terraform, data is not touched.
# After the first successful apply this file can be deleted.
import {
  id = "projects/${var.gcp_project_id}/datasets/${local.envs["prod"].dataset_id}"
  to = google_bigquery_dataset.analytics["prod"]
}

import {
  for_each = { for key, table in local.env_tables : key => table if table.env == "prod" }
  id       = "projects/${var.gcp_project_id}/datasets/${local.envs["prod"].dataset_id}/tables/${each.value.table}"
  to       = google_bigquery_table.analytics[each.key]
}
