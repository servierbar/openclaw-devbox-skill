#!/bin/bash
# Stop a devbox and remove its Traefik config
# Usage: stop-devbox.sh <devbox-id> [container-name]
# If container-name is omitted, only removes Traefik config.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVBOX_ID="$1"
CONTAINER="$2"

if [ -z "$DEVBOX_ID" ]; then
    echo "Usage: $0 <devbox-id> [container-name]" >&2
    exit 1
fi

# Stop and remove container if provided
if [ -n "$CONTAINER" ]; then
    echo "Stopping ${CONTAINER}..."
    docker stop "$CONTAINER" 2>/dev/null || true
    docker rm "$CONTAINER" 2>/dev/null || true
fi

# Remove Traefik config
bash "${SCRIPT_DIR}/traefik-devbox.sh" remove "${DEVBOX_ID}"

echo "Devbox ${DEVBOX_ID} cleaned up."
