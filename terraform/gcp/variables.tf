variable "gcp_project_id" {
  type = string
}

variable "gcp_location" {
  description = "Location of the BigQuery datasets"
  type        = string
  default     = "EU"
}

variable "infisical_host" {
  type    = string
  default = "https://app.infisical.com"
}

variable "infisical_client_id" {
  description = "Universal auth client id of the machine identity used by terraform"
  type        = string
}

variable "infisical_client_secret" {
  type      = string
  sensitive = true
}

variable "infisical_project_id" {
  description = "Id of the Astro Infisical project"
  type        = string
}

