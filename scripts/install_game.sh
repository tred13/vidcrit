#!/usr/bin/env bash
# Download VoxeLibre 0.92.4, create the "skit" world and install the mod + config.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
URL="https://cdn.content.luanti.org/uploads/3e11bd7181.zip"
USERDIR="$HOME/.luanti"

mkdir -p "$USERDIR/games" "$USERDIR/worlds/skit/worldmods"
# Older engines look in ~/.minetest - make both resolve to the same place.
[ -e "$HOME/.minetest" ] || ln -s "$USERDIR" "$HOME/.minetest"

TMP="$(mktemp -d)"
curl -fL --retry 4 --retry-delay 3 -o "$TMP/voxelibre.zip" "$URL"
unzip -q "$TMP/voxelibre.zip" -d "$TMP/vl"
[ -d "$TMP/vl/mineclone2" ] || { echo "::error::top folder mineclone2 missing"; ls "$TMP/vl"; exit 1; }
rm -rf "$USERDIR/games/voxelibre"
mv "$TMP/vl/mineclone2" "$USERDIR/games/voxelibre"
grep -E '^(title|version)' "$USERDIR/games/voxelibre/game.conf" || true

# World + mod + engine config
cp "$ROOT/config/world.mt"     "$USERDIR/worlds/skit/world.mt"
cp "$ROOT/config/map_meta.txt" "$USERDIR/worlds/skit/map_meta.txt"
rm -rf "$USERDIR/worlds/skit/worldmods/skit"
cp -r "$ROOT/mod/skit"         "$USERDIR/worlds/skit/worldmods/skit"
cp "$ROOT/config/luanti.conf"  "$USERDIR/luanti.conf"
cp "$ROOT/config/luanti.conf"  "$USERDIR/minetest.conf"

# map_meta.txt must terminate its parameter block
if [ "$(tail -n 1 "$USERDIR/worlds/skit/map_meta.txt")" != "[end_of_params]" ]; then
  echo "::error::map_meta.txt does not end with [end_of_params]"; exit 1
fi
echo "Installed. World files:"; ls -la "$USERDIR/worlds/skit"
