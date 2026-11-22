#!/usr/bin/env bash
# Phase 0.4: input-to-motion delay for the driver under each driving authority
# option at a fake round trip (default 100 ms).
set -euo pipefail
cd "$(dirname "$0")/../.."
RTT=${1:-100}
LOSS=${2:-0.02}
PORT=$((28200 + RANDOM % 500))
GODOT=${GODOT:-godot}
"$GODOT" --headless --path . -s res://tests/net/car_probe.gd -- host $PORT $RTT $LOSS > /tmp/popo_car_host.log 2>&1 &
HOST=$!
sleep 1
"$GODOT" --headless --path . -s res://tests/net/car_probe.gd -- client $PORT $RTT $LOSS > /tmp/popo_car_client.log 2>&1 || true
wait $HOST || true
grep LATENCY /tmp/popo_car_client.log || {
  echo "FAIL: no results. Client log tail:"; tail -n 20 /tmp/popo_car_client.log
  echo "Host log tail:"; tail -n 20 /tmp/popo_car_host.log
  exit 1
}
