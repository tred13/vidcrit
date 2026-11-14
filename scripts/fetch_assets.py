#!/usr/bin/env python3
"""Downloads real (recorded) music + sound effects from Mixkit and Twemoji SVGs."""
import json, os, sys, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, "assets")
os.makedirs(os.path.join(A, "sfx"), exist_ok=True)
EMOJI = os.path.join(ROOT, "video", "public", "emoji")
os.makedirs(EMOJI, exist_ok=True)

MUSIC = "https://assets.mixkit.co/music/679/679.mp3"   # Epical Drums 04
SFX = {
    "whoosh1": 1490, "whoosh2": 1492, "whoosh3": 1489,   # whooshes / transitions
    "pop1": 2357, "pop2": 2364,                           # sticker pops
    "impact": 772, "bigimpact": 1143, "zoomimpact": 2900, # impacts
    "zoom": 2617, "reveal": 235, "success": 2039, "ping": 2354,
    "beep": 2868, "coins": 1993,
}


def get(url, dst, tries=4):
    if os.path.exists(dst) and os.path.getsize(dst) > 500:
        return True
    for k in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=60) as r, open(dst, "wb") as f:
                f.write(r.read())
            return True
        except Exception as e:
            print("retry", url, e)
            time.sleep(2 + k)
    return False


ok = get(MUSIC, os.path.join(A, "music.mp3"))
if not ok:
    sys.exit("music download failed")
for name, i in SFX.items():
    if not get(f"https://assets.mixkit.co/active_storage/sfx/{i}/{i}-preview.mp3", os.path.join(A, "sfx", name + ".mp3")):
        sys.exit("sfx failed: " + name)

story = json.load(open(os.path.join(ROOT, "story.json")))
codes = {ev["emoji"] for sc in story["scenes"] for ev in sc["events"] if ev["t"] == "sticker"}
bad = []
for c in sorted(codes):
    done = False
    for base in ("https://cdn.jsdelivr.net/gh/jdecked/twemoji@latest/assets/svg/",
                 "https://raw.githubusercontent.com/jdecked/twemoji/main/assets/svg/"):
        if get(base + c + ".svg", os.path.join(EMOJI, c + ".svg"), tries=2):
            done = True
            break
    if not done:
        bad.append(c)
if bad:
    sys.exit("emoji missing: " + ", ".join(bad))
print("assets ok:", len(SFX), "sfx,", len(codes), "emoji")
