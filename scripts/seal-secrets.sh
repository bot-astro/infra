#!/bin/bash

BASE_DIR="apps"

# Optional first argument: app folder name
TARGET_APP="$1"

if [ -n "$TARGET_APP" ]; then
    SEARCH_DIR="$BASE_DIR/$TARGET_APP/envs"
    if [ ! -d "$SEARCH_DIR" ]; then
        echo "Folder $SEARCH_DIR does not exist."
        exit 1
    fi
else
    read -p "No app folder specified. This will run on all apps under $BASE_DIR. Continue? (y/N) " CONFIRM
    case "$CONFIRM" in
        [yY][eE][sS]|[yY]) ;;
        *) echo "Aborted."; exit 0 ;;
    esac
    SEARCH_DIR="$BASE_DIR"
fi

# Check for kubeseal dependency
if ! command -v kubeseal &>/dev/null; then
    echo "Error: 'kubeseal' is required but not installed."
    exit 1
fi

# Loop through all env folders and find 'secrets' directories
find "$SEARCH_DIR" -type d -path "*/envs/*/secrets" | while read -r SECRETS_DIR; do
    ENV_DIR="$(dirname "$SECRETS_DIR")"        # e.g. apps/{app}/envs/{env}

    # Process each *-secret.yml file
    for SECRET_FILE in "$SECRETS_DIR"/*-secret.yml; do
        [ -e "$SECRET_FILE" ] || continue

        FILE_BASENAME="$(basename "${SECRET_FILE%-secret.yml}")"
        ENV_OUT="$ENV_DIR/${FILE_BASENAME}-secret-sealed.yml"

        # Produce full sealed secret directly into env folder
        kubeseal -f "$SECRET_FILE" -o yaml > "$ENV_OUT"
        echo "Sealed secret written: $ENV_OUT"
    done
done