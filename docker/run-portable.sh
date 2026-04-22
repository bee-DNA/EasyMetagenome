#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.portable.yml"
IMAGE_NAME="easymetagenome/allinone:portable"

usage() {
  cat <<'EOF'
Usage:
  docker/run-portable.sh build
  docker/run-portable.sh run
  docker/run-portable.sh stage main|checkm2|humann|lefse|visualization|eggnog
  docker/run-portable.sh shell
  docker/run-portable.sh save [output_tar]
  docker/run-portable.sh load <input_tar>

Examples:
  docker/run-portable.sh build
  docker/run-portable.sh run
  docker/run-portable.sh stage lefse
  docker/run-portable.sh save easymetagenome_allinone_portable.tar
  docker/run-portable.sh load easymetagenome_allinone_portable.tar
EOF
}

ACTION="${1:-}"

if [[ -z "$ACTION" ]]; then
  usage
  exit 1
fi

run_stage() {
  local stage="$1"
  local script=""
  case "$stage" in
    main) script="1_main_analysis.sh" ;;
    checkm2) script="1.5_checkm2_analysis.sh" ;;
    humann) script="2_humann_analysis.sh" ;;
    lefse) script="3_lefse_analysis.sh" ;;
    visualization) script="4_visualization.sh" ;;
    eggnog) script="5_eggnog_analysis.sh" ;;
    *)
      echo "Unknown stage: $stage"
      usage
      exit 1
      ;;
  esac

  docker compose -f "$COMPOSE_FILE" run --rm pipeline \
    bash -lc "cd /workspace/app/easymetagenome && bash ./$script"
}

case "$ACTION" in
  build)
    docker compose -f "$COMPOSE_FILE" build pipeline
    ;;
  run|all)
    docker compose -f "$COMPOSE_FILE" run --rm pipeline
    ;;
  stage)
    if [[ -z "${2:-}" ]]; then
      echo "Missing stage name"
      usage
      exit 1
    fi
    run_stage "$2"
    ;;
  shell)
    docker compose -f "$COMPOSE_FILE" run --rm pipeline \
      bash -lc "cd /workspace/app/easymetagenome && exec bash"
    ;;
  save)
    OUTPUT_TAR="${2:-easymetagenome_allinone_portable.tar}"
    if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
      echo "Image not found: $IMAGE_NAME"
      echo "Run: docker/run-portable.sh build"
      exit 1
    fi
    docker save -o "$OUTPUT_TAR" "$IMAGE_NAME"
    echo "Saved image to: $(cd "$(dirname "$OUTPUT_TAR")" && pwd)/$(basename "$OUTPUT_TAR")"
    ;;
  load)
    INPUT_TAR="${2:-}"
    if [[ -z "$INPUT_TAR" ]]; then
      echo "Missing input tar path"
      usage
      exit 1
    fi
    if [[ ! -f "$INPUT_TAR" ]]; then
      echo "Tar file not found: $INPUT_TAR"
      exit 1
    fi
    docker load -i "$INPUT_TAR"
    ;;
  *)
    usage
    exit 1
    ;;
esac
