#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POSTIZ_DIR="$ROOT/backend/vendor/postiz-app"
COMPOSE_FILE="$POSTIZ_DIR/docker-compose.yaml"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required. Install Docker Desktop/Engine first." >&2
  exit 1
fi
if [ ! -f "$COMPOSE_FILE" ]; then
  echo "Postiz source is missing. Run: git submodule update --init --recursive" >&2
  exit 1
fi

echo "Starting the pinned open-source Postiz stack from: $POSTIZ_DIR"
echo "Review Postiz's env/config requirements and license before exposing it publicly."
docker compose -f "$COMPOSE_FILE" up -d --build
docker compose -f "$COMPOSE_FILE" ps
