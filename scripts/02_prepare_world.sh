#!/usr/bin/env bash
# Creates the "skit" world (world.mt, map_meta.txt, worldmod) and the client/server config.
set -euo pipefail

WORLD="$HOME/.luanti/worlds/skit"

echo "== Lua syntax check (luac5.1 -p)"
for f in skit/worldmods/skit/*.lua; do
  luac5.1 -p "$f"
  echo "ok  $f"
done

rm -rf "$WORLD"
mkdir -p "$WORLD/worldmods"
cp -r skit/worldmods/skit "$WORLD/worldmods/skit"
cp skit/world/world.mt "$WORLD/world.mt"

# map_meta.txt must end with [end_of_params]
grep -v -e '^[[:space:]]*$' -e '^\[end_of_params\]' skit/world/map_meta.txt > "$WORLD/map_meta.txt"
echo '[end_of_params]' >> "$WORLD/map_meta.txt"
if [ "$(tail -n1 "$WORLD/map_meta.txt")" != "[end_of_params]" ]; then
  echo "::error::map_meta.txt does not end with [end_of_params]"
  exit 1
fi

cp skit/config/luanti.conf "$HOME/skit.conf"

echo "== world files"
ls -la "$WORLD" "$WORLD/worldmods/skit"
echo "== map_meta.txt"
cat "$WORLD/map_meta.txt"
