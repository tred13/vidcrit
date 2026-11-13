#!/usr/bin/env bash
# CI ONLY: Xvfb :99 (720x1280) + openbox + Luanti (VoxeLibre) + ffmpeg x11grab.
# Recording starts when the mod writes skit_ready and covers the marker (skit_t0) with
# margin; the exact 10.9 s window after the marker is cut in 04_postprocess.sh.
set -uo pipefail

OUT="${OUT:-$PWD/out}"
RAW="${RAW:-/tmp/raw.mkv}"
WORLD="$HOME/.luanti/worlds/skit"
LUANTI_BIN="${LUANTI_BIN:-$(command -v luanti || command -v minetest)}"
mkdir -p "$OUT/logs" "$OUT/stills"

export DISPLAY=:99
export LIBGL_ALWAYS_SOFTWARE=1
export SDL_VIDEODRIVER=x11
export MESA_GLTHREAD=false

PIDS=()
cleanup() {
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done
}
collect_logs() {
  cp -f "$WORLD"/skit_* "$OUT/logs/" 2>/dev/null || true
  cp -f "$HOME/.luanti/debug.txt" "$OUT/logs/luanti-user-debug.txt" 2>/dev/null || true
  cp -f "$HOME/skit.conf" "$OUT/logs/skit.conf" 2>/dev/null || true
}
on_exit() {
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "::error::render script failed (rc=$rc) - grabbing a failure screenshot"
    ffmpeg -nostdin -y -loglevel error -f x11grab -video_size 720x1280 -i :99.0 -frames:v 1 \
      "$OUT/stills/failure.png" 2>/dev/null || true
    tail -n 60 "$OUT/logs/luanti-stdout.log" 2>/dev/null || true
    tail -n 60 "$OUT/logs/luanti-debug.txt" 2>/dev/null || true
  fi
  collect_logs
  cleanup
  exit "$rc"
}
trap on_exit EXIT

echo "== Xvfb :99 720x1280x24"
Xvfb :99 -screen 0 720x1280x24 +extension GLX +render -noreset >"$OUT/logs/xvfb.log" 2>&1 &
PIDS+=($!)
for _ in $(seq 1 60); do xdpyinfo -display :99 >/dev/null 2>&1 && break; sleep 0.2; done
xdpyinfo -display :99 | grep -E 'dimensions|GLX' || true

echo "== openbox"
openbox >"$OUT/logs/openbox.log" 2>&1 &
PIDS+=($!)
sleep 1

echo "== luanti --go --gameid voxelibre --worldname skit --name Cam"
rm -f "$WORLD"/skit_ready "$WORLD"/skit_t0 "$WORLD"/skit_done "$WORLD"/skit_events.log
"$LUANTI_BIN" --config "$HOME/skit.conf" --go --gameid voxelibre --worldname skit --name Cam \
  --logfile "$OUT/logs/luanti-debug.txt" >"$OUT/logs/luanti-stdout.log" 2>&1 &
LPID=$!
PIDS+=("$LPID")

echo "== waiting for skit_ready (world generation + stage + camera)"
READY=0
for i in $(seq 1 4000); do
  if [ -f "$WORLD/skit_ready" ]; then READY=1; break; fi
  if ! kill -0 "$LPID" 2>/dev/null; then
    echo "::error::Luanti exited before skit_ready"
    exit 1
  fi
  if (( i % 200 == 0 )); then
    echo "  ...$((i / 10))s"
    tail -n 2 "$OUT/logs/luanti-debug.txt" 2>/dev/null || true
  fi
  sleep 0.1
done
if [ "$READY" != "1" ]; then
  echo "::error::timeout waiting for skit_ready"
  exit 1
fi
echo "skit_ready seen"

# make sure the game window is exactly the screen (fullscreen normally already is)
WID="$(xdotool search --onlyvisible --class -i 'luanti|minetest' 2>/dev/null | head -n1 || true)"
if [ -n "$WID" ]; then
  eval "$(xdotool getwindowgeometry --shell "$WID" 2>/dev/null || true)"
  echo "game window $WID geometry: ${X:-?},${Y:-?} ${WIDTH:-?}x${HEIGHT:-?}"
  if [ "${WIDTH:-0}" != "720" ] || [ "${HEIGHT:-0}" != "1280" ] || [ "${X:-0}" != "0" ] || [ "${Y:-0}" != "0" ]; then
    echo "window not 720x1280@0,0 -> fixing"
    wmctrl -i -r "$WID" -b add,fullscreen 2>/dev/null || true
    xdotool windowmove "$WID" 0 0 windowsize "$WID" 720 1280 2>/dev/null || true
  fi
else
  echo "WARNING: could not find the game window via xdotool"
fi
ffmpeg -nostdin -y -loglevel error -f x11grab -video_size 720x1280 -i :99.0 -frames:v 1 \
  "$OUT/stills/preroll.png" || true

echo "== ffmpeg x11grab 720x1280 @30"
FF_LAUNCH="$(date +%s.%N)"
ffmpeg -nostdin -y -hide_banner -f x11grab -video_size 720x1280 -framerate 30 -draw_mouse 0 \
  -i :99.0 -copyts -c:v libx264 -preset ultrafast -crf 14 -pix_fmt yuv420p "$RAW" \
  >"$OUT/logs/ffmpeg-record.log" 2>&1 &
FPID=$!
PIDS+=("$FPID")

echo "== waiting for the marker skit_t0"
FOUND=0
for _ in $(seq 1 1500); do
  if [ -f "$WORLD/skit_t0" ]; then FOUND=1; break; fi
  if ! kill -0 "$LPID" 2>/dev/null; then echo "::error::Luanti died before skit_t0"; exit 1; fi
  if ! kill -0 "$FPID" 2>/dev/null; then echo "::error::ffmpeg died"; tail -n 20 "$OUT/logs/ffmpeg-record.log"; exit 1; fi
  sleep 0.02
done
if [ "$FOUND" != "1" ]; then echo "::error::marker skit_t0 never appeared"; exit 1; fi

T0="$(date -r "$WORLD/skit_t0" +%s.%N)"
echo "marker skit_t0 mtime = $T0 (ffmpeg launched at $FF_LAUNCH, lead = $(python3 -c "print(round($T0-$FF_LAUNCH,3))") s)"
printf 'FF_LAUNCH=%s\nT0=%s\n' "$FF_LAUNCH" "$T0" > "$OUT/logs/timing.env"

# keep recording until marker + 11.6 s (10.9 s window + tail), then stop ffmpeg cleanly
python3 - "$T0" <<'PY'
import sys, time
t0 = float(sys.argv[1])
time.sleep(max(0.0, t0 + 11.6 - time.time()))
PY
kill -INT "$FPID" 2>/dev/null || true
wait "$FPID" 2>/dev/null || true
echo "recording stopped"

echo "== waiting for the mod to shut the server down"
for _ in $(seq 1 200); do
  [ -f "$WORLD/skit_done" ] && break
  sleep 0.1
done
sleep 1
echo "== skit events"
cat "$WORLD/skit_events.log" 2>/dev/null || echo "(no events log)"
ls -la "$RAW"
