#!/usr/bin/env bash
# Run Luanti on Xvfb :99 (720x1280) + openbox, record the skit with ffmpeg,
# and produce mp4 / gif / stills / logs in ./out.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/out}"
WORLD="$HOME/.luanti/worlds/skit"
BIN="${LUANTI_BIN:-$(command -v luanti || command -v minetest)}"
DUR=10.9
export DISPLAY=:99
export LIBGL_ALWAYS_SOFTWARE=1
export SDL_VIDEODRIVER=x11
export SDL_AUDIODRIVER=dummy

mkdir -p "$OUT/stills"
rm -f "$WORLD"/skit_ready "$WORLD"/skit_go "$WORLD"/skit_t0 "$WORLD"/skit_done \
      "$WORLD"/skit_rotconv "$WORLD"/skit_events.log

PIDS=()
cleanup() {
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done
}
trap cleanup EXIT

fail() {
  echo "::error::$*"
  cp "$WORLD/skit_events.log" "$OUT/skit_events.log" 2>/dev/null || true
  tail -n 60 "$OUT/luanti.log" 2>/dev/null || true
  exit 1
}

# ---- display -------------------------------------------------------------
Xvfb :99 -screen 0 720x1280x24 +extension GLX +render -noreset >"$OUT/xvfb.log" 2>&1 &
PIDS+=($!)
for _ in $(seq 1 40); do xdpyinfo -display :99 >/dev/null 2>&1 && break; sleep 0.25; done
xdpyinfo -display :99 | grep -E 'dimensions|GLX' | head -n 3
openbox >"$OUT/openbox.log" 2>&1 &
PIDS+=($!)
sleep 1

# ---- engine --------------------------------------------------------------
"$BIN" --go --gameid voxelibre --worldname skit --name Cam \
  --config "$HOME/.luanti/luanti.conf" --logfile "$OUT/luanti.log" \
  >"$OUT/luanti.stdout" 2>&1 &
LPID=$!
PIDS+=($LPID)

echo "Waiting for skit_ready ..."
for i in $(seq 1 480); do
  [ -f "$WORLD/skit_ready" ] && break
  kill -0 "$LPID" 2>/dev/null || fail "Luanti exited before the scene was ready"
  sleep 0.5
done
[ -f "$WORLD/skit_ready" ] || fail "timeout waiting for skit_ready"
echo "Scene ready."

# ---- make sure the window fills the screen exactly -------------------------
WID="$(xdotool search --onlyvisible --class 'luanti|minetest' 2>/dev/null | tail -n 1 || true)"
if [ -n "$WID" ]; then
  xdotool windowmove "$WID" 0 0 2>/dev/null || true
  wmctrl -i -r "$WID" -b add,fullscreen 2>/dev/null || true
  sleep 1
  GEO="$(xdotool getwindowgeometry "$WID" 2>/dev/null | tr '\n' ' ')"
  echo "Window $WID: $GEO"
  echo "$GEO" > "$OUT/window_geometry.txt"
  echo "$GEO" | grep -q '720x1280' || echo "::warning::window geometry is not 720x1280: $GEO"
else
  echo "warning: could not find the game window via xdotool"
fi
xwininfo -root -tree > "$OUT/xwininfo.txt" 2>&1 || true
sleep 2

# ---- record ----------------------------------------------------------------
RAW="$OUT/raw.mkv"
PROG="$OUT/ffmpeg.progress"
: > "$PROG"
ffmpeg -nostdin -y -hide_banner -f x11grab -video_size 720x1280 -framerate 30 \
  -draw_mouse 0 -thread_queue_size 512 -i :99.0 -t 20 \
  -c:v libx264 -preset ultrafast -crf 12 -pix_fmt yuv420p \
  -progress "$PROG" -stats_period 0.05 "$RAW" >"$OUT/ffmpeg.log" 2>&1 &
FPID=$!
PIDS+=($FPID)

# wait until ffmpeg really delivers frames
for i in $(seq 1 200); do
  FR="$(grep -E '^frame=' "$PROG" | tail -n 1 | cut -d= -f2 || true)"
  [ -n "${FR:-}" ] && [ "$FR" != "N/A" ] && [ "$FR" -ge 20 ] 2>/dev/null && break
  kill -0 "$FPID" 2>/dev/null || fail "ffmpeg died: $(tail -n 5 "$OUT/ffmpeg.log")"
  sleep 0.1
done

# F = wall-clock time of ffmpeg's first captured frame = now - out_time
XUS="$(grep -E '^out_time_us=' "$PROG" | tail -n 1 | cut -d= -f2)"
NOW="$(date +%s.%N)"
FIRST="$(python3 -c "print($NOW - $XUS/1e6)")"

touch "$WORLD/skit_go"
for i in $(seq 1 100); do [ -f "$WORLD/skit_t0" ] && break; sleep 0.05; done
[ -f "$WORLD/skit_t0" ] || fail "mod never wrote skit_t0"
T0="$(stat -c %.9Y "$WORLD/skit_t0")"
OFFSET="$(python3 -c "print(round($T0 - $FIRST, 3))")"
echo "first_frame=$FIRST t0=$T0 offset=$OFFSET"
echo "offset=$OFFSET" > "$OUT/sync.txt"
python3 - <<EOF || fail "implausible sync offset $OFFSET"
o = $OFFSET
assert 0.2 <= o <= 5.0, o
EOF

# ---- wait for end of the skit ----------------------------------------------
for i in $(seq 1 400); do
  [ -f "$WORLD/skit_done" ] && break
  sleep 0.1
done
sleep 2.5
kill -INT "$FPID" 2>/dev/null || true
wait "$FPID" 2>/dev/null || true
cp "$WORLD/skit_events.log" "$OUT/skit_events.log" 2>/dev/null || true
cp "$WORLD/skit_rotconv"    "$OUT/skit_rotconv.txt" 2>/dev/null || true
cp "$WORLD/skit_t0"         "$OUT/skit_t0.txt"      2>/dev/null || true
[ -s "$RAW" ] || fail "empty raw capture"

# ---- compensate render latency ----------------------------------------------
# The engine shows the world a few hundred ms after the mod's clock. Find the
# frame where the explosion's flames first appear and shift the cut by that lag
# so the explosion lands on 5.42 s in the final video.
LAG="$(python3 "$ROOT/scripts/detect_lag.py" "$RAW" "$OFFSET" 5.42 2>"$OUT/lag_detect.log" || echo NA)"
cat "$OUT/lag_detect.log"
echo "measured render lag: $LAG"
if [ "$LAG" = "NA" ]; then
  echo "::warning::explosion not detected in raw capture, using lag 0.45"
  LAG=0.45
fi
OFFSET="$(python3 -c "
lag=max(-0.3,min(1.5,$LAG))
print(round($OFFSET+lag,3))")"
echo "offset=$OFFSET lag=$LAG" > "$OUT/sync.txt"
echo "final cut offset: $OFFSET"

# ---- cut exactly 10.9 s after the marker -----------------------------------
ffmpeg -y -hide_banner -loglevel warning -i "$RAW" -ss "$OFFSET" -t "$DUR" \
  -vf "fps=30,format=yuv420p" -c:v libx264 -preset slow -crf 17 \
  -movflags +faststart "$OUT/skit.mp4"

ffmpeg -y -hide_banner -loglevel warning -i "$OUT/skit.mp4" \
  -vf "fps=12,scale=360:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer" \
  "$OUT/skit.gif"

for T in 0.3 2.0 4.5 5.30 5.50 5.60 5.80 6.36 6.60 6.95 7.50 10.50; do
  ffmpeg -y -hide_banner -loglevel error -i "$OUT/skit.mp4" -ss "$T" -frames:v 1 \
    "$OUT/stills/t_${T}.png"
done

cp "$HOME/.luanti/debug.txt" "$OUT/debug.txt" 2>/dev/null || true
ls -la "$OUT" "$OUT/stills"
