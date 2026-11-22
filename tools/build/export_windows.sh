#!/usr/bin/env bash
# Exports the Windows build as one exe named with the game's version,
# e.g. build/windows/ThePopo-v0.1.0.exe. The version lives in project.godot
# (application/config/version); bump it for every build you hand out.
set -euo pipefail
cd "$(dirname "$0")/../.."
VERSION=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
[ -n "$VERSION" ] || { echo "no config/version in project.godot"; exit 1; }
OUT="build/windows/ThePopo-v${VERSION}.exe"
mkdir -p build/windows
godot --headless --import >/dev/null 2>&1 || true
godot --headless --export-release "Windows" "$OUT"
echo "$OUT"
