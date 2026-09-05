#!/usr/bin/env bash
# Import + unit/scene tests + Python/GDScript damage model parity.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT:-$("$ROOT/tools/ci/setup_godot.sh")}"
export GODOT
"$ROOT/tools/ci/import.sh"
"$GODOT" --headless --path "$ROOT" --script res://tools/godot/run_tests.gd "$@"
if [ -f "$ROOT/tests/unit/expected_ttk.txt" ]; then
  python3 "$ROOT/tools/ttk.py" | diff -u "$ROOT/tests/unit/expected_ttk.txt" - && echo "TTK parity: ok"
fi
