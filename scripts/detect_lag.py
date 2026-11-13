#!/usr/bin/env python3
"""Measure when the explosion first becomes visible in a video.

usage: detect_lag.py VIDEO OFFSET EXPECTED_T

VIDEO is decoded at 30 fps; OFFSET is the time inside VIDEO that corresponds
to skit_t0 (0 for the final cut). Flame particles are orange, saturated and
very bright, which nothing else in the scene is, so the first frame whose
count of such pixels jumps above the baseline marks the explosion on screen.

Prints the signed lag in seconds: (visible time) - (OFFSET + EXPECTED_T).
Prints NA if nothing was detected.
"""
import subprocess
import sys

import numpy as np

video, offset, expected = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
W, H, FPS = 360, 640, 30

proc = subprocess.Popen(
    ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", video,
     "-vf", f"fps={FPS},scale={W}:{H}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
    stdout=subprocess.PIPE)

size = W * H * 3
counts = []
while True:
    buf = proc.stdout.read(size)
    if len(buf) < size:
        break
    f = np.frombuffer(buf, dtype=np.uint8).reshape(H, W, 3).astype(np.int16)
    r, g, b = f[..., 0], f[..., 1], f[..., 2]
    mask = (r > 225) & (g > 90) & (g < 215) & (b < 70)
    counts.append(int(mask.sum()))
proc.wait()

counts = np.array(counts)
start = int((offset + expected) * FPS)
pre_lo = max(0, start - 60)
base = float(np.median(counts[pre_lo:max(pre_lo + 1, start - 5)])) if len(counts) else 0.0
thr = base + 120
hit = None
for i in range(max(0, start - 20), len(counts)):
    if counts[i] > thr:
        hit = i
        break

sys.stderr.write(f"baseline={base:.0f} threshold={thr:.0f} frames={len(counts)} hit={hit}\n")
if hit is None:
    print("NA")
else:
    print(f"{hit / FPS - (offset + expected):.3f}")
