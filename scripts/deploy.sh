#!/bin/bash
# Usage: scripts/deploy.sh <app> <env> <tag>
# Bumps the image tag, commits and pushes so ArgoCD deploys it. Run from the root of the infra repo.
set -euo pipefail

APP="${1:?app required}"
ENV="${2:?env required (astro | astro-staging)}"
TAG="${3:?tag required}"

git config user.name "astro-ci"
git config user.email "ci@astro-bot.space"

for attempt in 1 2 3 4 5; do
    ./scripts/bump-version.sh "$APP" "$ENV" "$TAG"

    if git diff --quiet; then
        echo "$APP is already on $TAG in $ENV, nothing to deploy."
        exit 0
    fi

    git commit -am "deploy($APP): $ENV $TAG"

    if git push; then
        exit 0
    fi

    # another service pushed in the meantime
    echo "Push rejected (attempt $attempt), rebasing."
    git reset --hard HEAD~1
    git pull --rebase
done

echo "Error: could not push after 5 attempts."
exit 1
