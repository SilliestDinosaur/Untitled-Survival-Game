#!/usr/bin/env bash
# Runs every headless test suite and prints one line per suite.
# Usage: tests/tools/run_tests.sh [suite ...]   (default: all suites)
# Set GODOT=/path/to/godot if the binary is not in the default place.
cd "$(dirname "$0")/../.." || exit 1
G="${GODOT:-/tmp/claude-0/-home-user/19c39f26-e94b-5cf8-b4f4-4d5d8499409a/scratchpad/godot/Godot_v4.5.1-stable_linux.x86_64}"
SUITES=("$@")
[ ${#SUITES[@]} -eq 0 ] && SUITES=(smoke_test gameplay_test terrain_test build_test cave_test river_test voxel_test map_test)
fail=0
for s in "${SUITES[@]}"; do
  log=$(mktemp)
  timeout 900 "$G" --headless --path . -s "tests/$s.gd" >"$log" 2>&1
  result=$(grep -a -E "^RESULT:|CLIENT RESULT|HOST RESULT" "$log" | tail -1)
  fails=$(grep -a -E "^\s+FAIL " "$log" | head -5)
  printf "%-16s %s\n" "$s" "${result:-NO RESULT (crashed or timed out)}"
  [ -n "$fails" ] && echo "$fails" | sed 's/^/    /'
  [ -z "$result" ] || echo "$result" | grep -q "PASS" || fail=1
  rm -f "$log"
done
exit $fail
