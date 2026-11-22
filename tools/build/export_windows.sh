#!/usr/bin/env bash
# Exports the Windows build as one exe named with the game's version,
# e.g. build/windows/ThePopo-v0.1.0.exe. The version lives in project.godot
# (application/config/version); bump it for every build you hand out.
# Also writes build/windows/ThePopo-v<version>.zip with How to play.txt.
set -euo pipefail
cd "$(dirname "$0")/../.."
VERSION=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
[ -n "$VERSION" ] || { echo "no config/version in project.godot"; exit 1; }
OUT="build/windows/ThePopo-v${VERSION}.exe"
mkdir -p build/windows
godot --headless --import >/dev/null 2>&1 || true
godot --headless --export-release "Windows" "$OUT"
# The zip handed out: the exe plus the how-to-play note for this version.
sed "s/VERSION/${VERSION}/g" "tools/build/How to play.txt" | sed 's/$/\r/' > "build/windows/How to play.txt"
(cd build/windows && rm -f "ThePopo-v${VERSION}.zip" && zip -q -9 "ThePopo-v${VERSION}.zip" "ThePopo-v${VERSION}.exe" "How to play.txt")
echo "$OUT"
echo "build/windows/ThePopo-v${VERSION}.zip"
