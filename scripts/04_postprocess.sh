#!/usr/bin/env bash
# CI ONLY: cut the exact window after the marker, build mp4/gif/stills and sanity-check.
set -euo pipefail

OUT="${OUT:-$PWD/out}"
RAW="${RAW:-/tmp/raw.mkv}"
DUR=10.9
mkdir -p "$OUT/stills" "$OUT/logs"

# shellcheck disable=SC1091
source "$OUT/logs/timing.env"

RS="$(ffprobe -v error -show_entries format=start_time -of csv=p=0 "$RAW" || true)"
read -r OFFSET SRC START < <(python3 - "${RS:-0}" "$FF_LAUNCH" "$T0" <<'PY'
import sys
rs = float(sys.argv[1] or 0)
launch = float(sys.argv[2])
t0 = float(sys.argv[3])
# x11grab stamps frames with wall-clock time and -copyts keeps it: exact first-frame time.
if rs > 1e9 and 0 <= rs - launch < 15:
    start, src = rs, "frame-pts"
else:
    start, src = launch + 0.25, "launch+0.25s(fallback)"
print(f"{t0 - start:.3f} {src} {start:.3f}")
PY
)
echo "raw start=$START ($SRC)  marker T0=$T0  -> cut offset = ${OFFSET}s"
python3 -c "import sys; sys.exit(0 if float('$OFFSET') >= 0 else 1)" || {
  echo "::error::recording started after the marker (offset $OFFSET < 0)"; exit 1; }

echo "== mp4 (720x1280, ${DUR}s)"
ffmpeg -nostdin -y -hide_banner -loglevel warning -i "$RAW" -ss "$OFFSET" -t "$DUR" \
  -vf "fps=30,format=yuv420p" -c:v libx264 -preset slow -crf 17 -movflags +faststart -an \
  "$OUT/skit.mp4"

W="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$OUT/skit.mp4")"
H="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$OUT/skit.mp4")"
D="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/skit.mp4")"
echo "result: ${W}x${H}, duration ${D}s"
[ "$W" = "720" ] && [ "$H" = "1280" ] || { echo "::error::unexpected video size ${W}x${H}"; exit 1; }
python3 -c "import sys; d=float('$D'); sys.exit(0 if abs(d-$DUR) < 0.15 else 1)" || {
  echo "::error::unexpected duration $D"; exit 1; }

echo "== gif"
ffmpeg -nostdin -y -hide_banner -loglevel warning -i "$OUT/skit.mp4" \
  -vf "fps=12,scale=360:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
  "$OUT/skit.gif"

echo "== stills"
for T in 0.5 2.0 2.6 4.0 5.30 5.46 5.70 6.00 6.60 8.00 10.50; do
  ffmpeg -nostdin -y -hide_banner -loglevel error -ss "$T" -i "$OUT/skit.mp4" -frames:v 1 \
    "$OUT/stills/t_${T}.png" || true
done

echo "== explosion timing (luma jump in the video)"
rm -f "$OUT/logs/yavg.txt"
ffmpeg -nostdin -y -hide_banner -loglevel error -ss 4.6 -t 2.0 -i "$OUT/skit.mp4" \
  -vf "signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=$OUT/logs/yavg.txt" -f null - || true
python3 - "$OUT/logs/yavg.txt" <<'PY' | tee "$OUT/logs/explosion_check.txt"
import re, sys
try:
    txt = open(sys.argv[1]).read()
except OSError:
    print("no yavg data"); sys.exit(0)
pts = [float(m) for m in re.findall(r"pts_time:([0-9.]+)", txt)]
yv  = [float(m) for m in re.findall(r"YAVG=([0-9.]+)", txt)]
best, bt = 0.0, None
for i in range(1, min(len(pts), len(yv))):
    d = abs(yv[i] - yv[i - 1])
    if d > best:
        best, bt = d, pts[i]
if bt is None:
    print("no frames analysed")
else:
    t = 4.6 + bt
    ok = abs(t - 5.42) <= 0.25
    print(f"largest luma jump {best:.1f} at video t={t:.2f}s (expected 5.42 +-0.2)  {'OK' if ok else 'CHECK'}")
PY

echo "== summary"
{
  echo "## vidcrit skit render"
  echo
  echo "- video: \`skit.mp4\` ${W}x${H}, ${D}s (cut offset ${OFFSET}s, start source: ${SRC})"
  echo
  echo "### mod timeline (actual vs expected, seconds after skit_t0)"
  echo '```'
  cat "$OUT/logs/skit_events.log" 2>/dev/null || echo "(missing)"
  echo '```'
  echo
  echo "### camera calibration (measured once)"
  echo '```'
  cat "$OUT/logs/skit_calibration.txt" 2>/dev/null || echo "(missing)"
  echo '```'
  echo
  echo "### explosion check"
  echo '```'
  cat "$OUT/logs/explosion_check.txt" 2>/dev/null || true
  echo '```'
} > "$OUT/summary.md"
cat "$OUT/summary.md"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then cat "$OUT/summary.md" >> "$GITHUB_STEP_SUMMARY"; fi
ls -la "$OUT" "$OUT/stills"
