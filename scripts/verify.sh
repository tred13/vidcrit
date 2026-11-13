#!/usr/bin/env bash
# Acceptance checks, run in CI after rendering. Exits non-zero on failure.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/out}"
export ROOT

python3 - "$OUT" <<'EOF'
import re, sys, subprocess, json, os
out = sys.argv[1]
fails = []
def need(cond, msg):
    print(("PASS  " if cond else "FAIL  ") + msg)
    if not cond: fails.append(msg)

ev = open(os.path.join(out, "skit_events.log")).read().splitlines()

# 1. every event within +-0.2 s of its target
events = {}
for l in ev:
    m = re.match(r"EVENT\|(\w+)\|target=([\d.]+)\|actual=([\d.]+)", l)
    if m: events[m.group(1)] = (float(m.group(2)), float(m.group(3)))
need("explosion" in events, "explosion event logged")
for name, (t, a) in events.items():
    need(abs(a - t) <= 0.2, f"event {name}: target {t:.2f} actual {a:.3f}")
if "explosion" in events:
    need(abs(events["explosion"][0] - 5.42) < 1e-6, "explosion scheduled at 5.42")

# 2. explosion strength never above 2.5
m = [re.search(r"EXPLOSION\|strength=([\d.]+)", l) for l in ev]
m = [x for x in m if x]
need(len(m) == 1 and float(m[0].group(1)) <= 2.5, "single explosion, strength <= 2.5 (" + (m[0].group(1) if m else "?") + ")")

# 3. stage stays standing
chk = [l for l in ev if l.startswith("STAGE_CHECK|after_explosion")]
need(len(chk) == 1 and "damaged=0" in chk[0], "stage intact after explosion")

# 4. rotation convention measured once and sane
rc = [l for l in ev if l.startswith("ROTCONV|")]
need(len(rc) == 1 and "ok=true" in rc[0], "rotation convention measured once: " + (rc[0] if rc else "missing"))

# 5. framing report (vertical frame, actors inside, head in top third, 6-7 blocks)
fr = [l for l in ev if l.startswith("FRAME|")]
need(len(fr) == 8, f"8 framing reports (got {len(fr)})")
for l in fr:
    need("ok=true" in l, l)

# 6. video properties
p = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                    "stream=width,height,r_frame_rate:format=duration", "-of", "json",
                    os.path.join(out, "skit.mp4")], capture_output=True, text=True)
j = json.loads(p.stdout)
s = j["streams"][0]
need((s["width"], s["height"]) == (720, 1280), f"video is 720x1280 ({s['width']}x{s['height']})")
need(abs(float(j["format"]["duration"]) - 10.9) < 0.15, f"duration ~10.9 s ({j['format']['duration']})")

bad_ev = [l for l in ev if l.startswith("STEP_ERROR")]
need(not bad_ev, "no STEP_ERROR events" + ("" if not bad_ev else ": " + bad_ev[0]))

# 7. no Lua errors from our mod
log = open(os.path.join(out, "luanti.log"), errors="replace").read()
bad = [l for l in log.splitlines() if re.search(r"ERROR\[.*\].*(skit|runtime error)", l)]
need(not bad, "no skit/runtime errors in luanti.log" + ("" if not bad else ": " + bad[0]))

# 7b. the explosion must be visible on screen at 5.42 +-0.2 s in the FINAL video
r = subprocess.run(["python3", os.path.join(os.environ["ROOT"], "scripts", "detect_lag.py"),
                    os.path.join(out, "skit.mp4"), "0", "5.42"], capture_output=True, text=True)
print(r.stderr.strip())
vis = r.stdout.strip()
need(vis != "NA" and abs(float(vis)) <= 0.2, f"explosion visible at 5.42 on screen (residual {vis} s)")

# 8. images: not black, explosion visibly changes the frame
def mean(path):
    r = subprocess.run(["convert", path, "-format", "%[fx:mean]", "info:"], capture_output=True, text=True)
    return float(r.stdout)
def diff(a, b):
    r = subprocess.run(["compare", "-metric", "RMSE", a, b, "null:"], capture_output=True, text=True)
    return float(re.search(r"\(([\d.eE+-]+)\)", r.stderr).group(1))
st = lambda t: os.path.join(out, "stills", f"t_{t}.png")
for t in ("0.3", "5.30", "10.50"):
    mv = mean(st(t)); need(0.03 < mv < 0.97, f"still t={t} not blank (mean {mv:.3f})")
d = diff(st("5.30"), st("5.60")); need(d > 0.01, f"explosion visible: RMSE(5.30 vs 5.60) = {d:.4f}")

print("\nRESULT:", "ALL CHECKS PASSED" if not fails else f"{len(fails)} FAILED")
sys.exit(1 if fails else 0)
EOF
