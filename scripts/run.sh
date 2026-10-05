#!/bin/bash
# Build e abre o .app local.
# Uso: scripts/run.sh [workspace]   (default: o diretório atual)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="${1:-$PWD}"

"$ROOT/scripts/make-app.sh" debug

# O binário lê a workspace do primeiro argumento quando não for interativo;
# sem argumento ele abre no diretório atual.
if [ -n "${IDE_SWIFT_WORKSPACE:-}" ]; then
    WORKSPACE="$IDE_SWIFT_WORKSPACE"
fi

echo "==> abrindo workspace $WORKSPACE"
open -n "$ROOT/dist/ide-swift.app" --args --workspace "$WORKSPACE"
