#!/usr/bin/env bash
# Runs terraform in a module with the R2 state credentials injected from Infisical (prod env, /terraform folder),
# so AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY never have to be exported by hand.
# Usage: scripts/terraform.sh <gcp|cloudflare> <terraform args...>   e.g. scripts/terraform.sh gcp plan
set -euo pipefail

module="${1:?usage: scripts/terraform.sh <gcp|cloudflare> <terraform args...>}"
shift

cd "$(dirname "$0")/../terraform/$module"
exec infisical run --projectId=b9071f19-b984-4138-a1e8-a15c67e02603 --env=prod --path=/terraform -- terraform "$@"
