#!/usr/bin/env bash
# Phase 0.3 gate check: host and client watch the same building collapse and
# must agree on where the big chunks landed.
# Usage: tests/net/run_collapse_test.sh [rtt_ms] [loss 0..1] [tolerance_m]
set -euo pipefail
cd "$(dirname "$0")/../.."
RTT=${1:-100}
LOSS=${2:-0.05}
TOL=${3:-0.05}
PORT=$((27700 + RANDOM % 500))
GODOT=${GODOT:-godot}
"$GODOT" --headless --path . -s res://tests/net/collapse_probe.gd -- host $PORT $RTT $LOSS > /tmp/popo_chost.log 2>&1 &
HOST=$!
sleep 1
"$GODOT" --headless --path . -s res://tests/net/collapse_probe.gd -- client $PORT $RTT $LOSS > /tmp/popo_cclient.log 2>&1 || true
wait $HOST || true
python3 - "$TOL" <<'PY'
import sys
tol = float(sys.argv[1])
def read(path):
    for line in open(path):
        if line.startswith("BODIES"):
            out = {}
            for item in line.split()[1:]:
                k, v = item.split(":")
                out[int(k)] = tuple(map(float, v.split(",")))
            return out
    return None
h, c = read("/tmp/popo_chost.log"), read("/tmp/popo_cclient.log")
if not h or not c:
    print("FAIL: missing results"); sys.exit(1)
common = set(h) & set(c)
errs = sorted((sum((a - b) ** 2 for a, b in zip(h[k], c[k])) ** 0.5, k) for k in common)
worst = errs[-1][0] if errs else 0
print(f"synced bodies: host {len(h)}, client {len(c)}, compared {len(common)}")
print(f"worst disagreement {worst:.3f} m, median {errs[len(errs)//2][0]:.3f} m")
ok = len(common) == len(h) == len(c) and len(h) > 5 and worst <= tol
print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
PY
