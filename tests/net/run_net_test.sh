#!/usr/bin/env bash
# Runs a host and a client on this machine with fake latency and loss, and
# checks the client's predicted position matches the host's authoritative one.
# Usage: tests/net/run_net_test.sh [rtt_ms] [loss 0..1]
set -euo pipefail
cd "$(dirname "$0")/../.."
RTT=${1:-100}
LOSS=${2:-0.05}
PORT=$((27100 + RANDOM % 500))
GODOT=${GODOT:-godot}
"$GODOT" --headless --path . -s res://tests/net/net_probe.gd -- host $PORT $RTT $LOSS > /tmp/popo_host.log 2>&1 &
HOST=$!
sleep 1
"$GODOT" --headless --path . -s res://tests/net/net_probe.gd -- client $PORT $RTT $LOSS > /tmp/popo_client.log 2>&1 || true
wait $HOST || true
H=$(grep RESULT /tmp/popo_host.log || true)
C=$(grep RESULT /tmp/popo_client.log || true)
echo "host:   $H"
echo "client: $C"
python3 - "$H" "$C" <<'PY'
import sys
h, c = sys.argv[1].split(), sys.argv[2].split()
if len(h) < 4 or len(c) < 4:
    print("FAIL: missing result"); sys.exit(1)
hx, hz, cx, cz = float(h[1]), float(h[2]), float(c[1]), float(c[2])
d = ((hx - cx) ** 2 + (hz - cz) ** 2) ** 0.5
# The client measures its own walk: it records its start before it moves,
# while the host may only start watching after the client has set off.
moved = abs(float(c[3])) > 1.5
print(f"distance between host and client views: {d:.3f} m, client walked {float(c[3]):.2f} m")
sys.exit(0 if d < 0.05 and moved else 1)
PY
