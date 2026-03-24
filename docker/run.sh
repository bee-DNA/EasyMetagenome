#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage:
  docker/run.sh all
  docker/run.sh main|checkm2|humann|lefse|visualization|eggnog
  docker/run.sh logs [service]

Examples:
  docker/run.sh all
  docker/run.sh humann
  docker/run.sh logs main
EOF
}

SERVICE="${1:-all}"

case "$SERVICE" in
  all)
    docker compose up -d
    ;;
  main|checkm2|humann|lefse|visualization|eggnog)
    docker compose run --rm "$SERVICE"
    ;;
  logs)
    if [[ -n "${2:-}" ]]; then
      docker compose logs -f "$2"
    else
      docker compose logs -f
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
