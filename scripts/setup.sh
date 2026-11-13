#!/usr/bin/env bash
# Install Luanti (>= 5.10) from ppa:minetestdevs/stable plus capture tooling.
set -euo pipefail

sudo apt-get update -y
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y ppa:minetestdevs/stable
sudo apt-get update -y

if apt-cache show luanti >/dev/null 2>&1; then PKG=luanti; else PKG=minetest; fi
echo "Installing package: $PKG"
sudo apt-get install -y "$PKG"
sudo apt-get install -y xvfb openbox xdotool wmctrl x11-utils ffmpeg \
  libgl1-mesa-dri libglx-mesa0 libegl1 mesa-utils imagemagick unzip curl python3 python3-numpy lua5.1

apt-cache policy "$PKG" | head -n 6 || true

BIN="$(command -v luanti || command -v minetest || true)"
if [ -z "$BIN" ]; then echo "::error::no luanti/minetest binary found"; exit 1; fi

VERSION_LINE="$("$BIN" --version 2>&1 | head -n 1)"
echo "Engine: $VERSION_LINE"
VER="$(echo "$VERSION_LINE" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)"
MAJOR="${VER%%.*}"; REST="${VER#*.}"; MINOR="${REST%%.*}"
if [ -z "$VER" ] || [ $((MAJOR * 100 + MINOR)) -lt 510 ]; then
  echo "::error::Luanti $VER is older than 5.10 - refusing to continue"
  exit 1
fi
echo "Luanti $VER accepted"

echo "LUANTI_BIN=$BIN" >> "${GITHUB_ENV:-/dev/null}"
