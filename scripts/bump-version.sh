#!/bin/bash
# Usage: scripts/bump-version.sh <app> <env> <tag>
# Updates the image tag in apps/<app>/envs/<env>/version.yml, then commit + push to let ArgoCD deploy.
set -euo pipefail

APP="${1:?app required}"
ENV="${2:?env required (astro | astro-staging)}"
TAG="${3:?tag required}"

FILE="apps/$APP/envs/$ENV/version.yml"
[ -f "$FILE" ] || { echo "Error: $FILE does not exist."; exit 1; }
command -v yq &>/dev/null || { echo "Error: 'yq' is required but not installed."; exit 1; }

IMAGE="ghcr.io/bot-astro/$APP:$TAG" \
  yq -i '(.. | select(tag == "!!map" and has("image")) | .image) = strenv(IMAGE)' "$FILE"

echo "$FILE -> $TAG"
