variable "cloudflare_api_token" {
  description = "Token with: Account R2 edit, Account API Tokens edit, Zone DNS edit and Zone edit (custom domains) on astro-bot.space"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  type = string
}

variable "cloudflare_zone_id" {
  description = "Zone id of astro-bot.space"
  type        = string
}

variable "ingress_ipv4" {
  description = "Public IPv4 of the cluster ingress (gport output: module.kube-hetzner.ingress_public_ipv4)"
  type        = string
}

variable "r2_bucket_item_write_permission_group_id" {
  description = "Id of the \"Workers R2 Storage Bucket Item Write\" permission group, see https://developers.cloudflare.com/api/resources/user/subresources/tokens/subresources/permission_groups/"
  type        = string
  default     = "2efd5506f9c8494dacb1fa10a3e7d5b6"
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

