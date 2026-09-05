#!/usr/bin/env bash
# Runs the headless asset import for the project and fails on import errors.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT:-$("$ROOT/tools/ci/setup_godot.sh")}"
LOG="${KOTM_SCRATCH:-$ROOT/scratch}/logs/import.log"; mkdir -p "$(dirname "$LOG")"
"$GODOT" --headless --path "$ROOT" --import 2>&1 | tee "$LOG" | grep -vE "^$" | tail -30
if grep -E "Failed to import|ERROR: |SCRIPT ERROR|Parse Error" "$LOG" | grep -vqE "at exit|leaked"; then
  echo "IMPORT: errors found (see $LOG)"; exit 1
fi
echo "IMPORT: ok"
