#!/usr/bin/env bash
# Runs the multiplayer test pair: a host and a guest on this machine.
# Usage: tests/tools/run_net_test.sh                 (direct)
#        LAG=150 JITTER=40 LOSS=2 tests/tools/run_net_test.sh   (through a relay that delays and drops packets)
# Set GODOT=/path/to/godot if the binary is not in the default place.
cd "$(dirname "$0")/../.." || exit 1
G="${GODOT:-/tmp/claude-0/-home-user/19c39f26-e94b-5cf8-b4f4-4d5d8499409a/scratchpad/godot/Godot_v4.5.1-stable_linux.x86_64}"
host_log=$(mktemp); client_log=$(mktemp); relay_log=$(mktemp)
timeout 900 "$G" --headless --path . -s tests/net_host_test.gd >"$host_log" 2>&1 &
host_pid=$!
join=""
if [ -n "$LAG" ]; then
  python3 tests/tools/lag_relay.py 24690 24680 "$LAG" "${JITTER:-0}" "${LOSS:-0}" >"$relay_log" 2>&1 &
  relay_pid=$!
  join="127.0.0.1:24690"
fi
sleep 8
NET_JOIN="$join" timeout 900 "$G" --headless --path . -s tests/net_client_test.gd >"$client_log" 2>&1
wait "$host_pid"
[ -n "$relay_pid" ] && kill "$relay_pid" 2>/dev/null
grep -a -E "^\s+(ok|FAIL) " "$client_log" | sed 's/^/  guest /'
grep -a -E "^\s+(ok|FAIL) " "$host_log" | sed 's/^/  host  /'
[ -n "$LAG" ] && grep -a "RELAY" "$relay_log" | tail -2
grep -a -E "CLIENT RESULT" "$client_log"
grep -a -E "HOST RESULT" "$host_log"
ok=0
grep -aq "CLIENT RESULT: PASS" "$client_log" && grep -aq "HOST RESULT: PASS" "$host_log" && ok=1
rm -f "$host_log" "$client_log" "$relay_log"
[ "$ok" = 1 ]
