#!/usr/bin/env bash
# Installs the system packages, Luanti (PPA minetestdevs/stable) and VoxeLibre.
set -euo pipefail

VOXELIBRE_URL="https://cdn.content.luanti.org/uploads/3e11bd7181.zip"

echo "::group::apt packages"
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
  software-properties-common ca-certificates curl unzip python3 \
  xvfb openbox xdotool wmctrl x11-utils x11-xserver-utils \
  ffmpeg mesa-utils libgl1-mesa-dri libglx-mesa0 libegl1 \
  lua5.1 fonts-dejavu-core
echo "::endgroup::"

echo "::group::Luanti from ppa:minetestdevs/stable"
sudo add-apt-repository -y ppa:minetestdevs/stable
sudo apt-get update -y
sudo apt-get install -y luanti || sudo apt-get install -y minetest
echo "::endgroup::"

LUANTI_BIN="$(command -v luanti || command -v minetest || true)"
if [ -z "$LUANTI_BIN" ]; then
  echo "::error::neither luanti nor minetest binary found after install"
  exit 1
fi

VER_LINE="$("$LUANTI_BIN" --version 2>&1 | head -n1 || true)"
VER="$(printf '%s' "$VER_LINE" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)"
echo "engine: $LUANTI_BIN -> '$VER_LINE' (parsed '$VER')"
if [ -z "$VER" ]; then
  echo "::error::could not parse engine version from '$VER_LINE'"
  exit 1
fi
MAJOR="${VER%%.*}"
REST="${VER#*.}"
MINOR="${REST%%.*}"
if (( MAJOR < 5 || (MAJOR == 5 && MINOR < 10) )); then
  echo "::error::Luanti $VER is older than 5.10 - refusing to continue"
  exit 1
fi
echo "LUANTI_BIN=$LUANTI_BIN" >> "$GITHUB_ENV"

echo "::group::VoxeLibre"
mkdir -p "$HOME/.luanti/games" "$HOME/.luanti/worlds"
# the PPA build may look into ~/.minetest: keep both paths pointing to the same data dir
if [ ! -e "$HOME/.minetest" ]; then ln -s "$HOME/.luanti" "$HOME/.minetest"; fi

curl -fL --retry 5 --retry-delay 3 -o /tmp/voxelibre.zip "$VOXELIBRE_URL"
rm -rf /tmp/voxelibre_unzip
unzip -q /tmp/voxelibre.zip -d /tmp/voxelibre_unzip
if [ ! -f /tmp/voxelibre_unzip/mineclone2/game.conf ]; then
  echo "::error::zip does not contain mineclone2/game.conf"
  ls -la /tmp/voxelibre_unzip
  exit 1
fi
rm -rf "$HOME/.luanti/games/voxelibre"
mv /tmp/voxelibre_unzip/mineclone2 "$HOME/.luanti/games/voxelibre"
echo "VoxeLibre: $(grep -E '^(title|version)' "$HOME/.luanti/games/voxelibre/game.conf" | tr '\n' ' ')"
echo "::endgroup::"
