#!/usr/bin/env python3
"""Mixes narration + real music (ducked under the voice) + real SFX -> build/mix.wav"""
import json, os, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
B = os.path.join(ROOT, "build")
A = os.path.join(ROOT, "assets")
FF = os.environ.get("FFMPEG", "ffmpeg")
timing = json.load(open(os.path.join(ROOT, "video", "src", "timing.json")))
T = timing["total"]
MUSIC_SKIP = 14.0   # the track builds up for ~14s; skip straight to the full groove

inputs = ["-i", os.path.join(B, "voice.wav"), "-ss", str(MUSIC_SKIP), "-i", os.path.join(A, "music.mp3")]
cues = [(s["time"], s["s"], s["v"]) for sc in timing["scenes"] for s in sc["sfx"]]
cues.sort()
for _, name, _ in cues:
    inputs += ["-i", os.path.join(A, "sfx", name + ".mp3")]

f = []
f.append("[0:a]aresample=48000,apad=whole_dur=%.3f,volume=1.15,asplit=2[v1][v2]" % T)
f.append("[1:a]aresample=48000,aformat=channel_layouts=stereo,atrim=0:%.3f,asetpts=PTS-STARTPTS,volume=0.42,"
         "afade=t=in:d=1.2,afade=t=out:st=%.3f:d=3.0[m]" % (T, T - 3.0))
f.append("[v2]aformat=channel_layouts=mono[sc]")
f.append("[m][sc]sidechaincompress=threshold=0.03:ratio=7:attack=12:release=380:makeup=1[md]")
f.append("[v1]aformat=channel_layouts=stereo[vs]")
labels = ["[vs]", "[md]"]
for k, (t, name, v) in enumerate(cues):
    ms = max(0, int(t * 1000))
    f.append("[%d:a]aresample=48000,aformat=channel_layouts=stereo,volume=%.2f,adelay=%d|%d[s%d]" % (k + 2, v * 0.9, ms, ms, k))
    labels.append("[s%d]" % k)
f.append("%samix=inputs=%d:normalize=0:duration=longest,atrim=0:%.3f,"
         "loudnorm=I=-14:TP=-1.5:LRA=9,aresample=48000[out]" % ("".join(labels), len(labels), T))
fs = os.path.join(B, "mix_filter.txt")
open(fs, "w").write(";\n".join(f))
subprocess.run([FF, "-y", *inputs, "-filter_complex_script", fs, "-map", "[out]", "-ar", "48000",
                "-c:a", "pcm_s16le", os.path.join(B, "mix.wav")], check=True)
print("mix ok,", len(cues), "sfx cues, total", T)
