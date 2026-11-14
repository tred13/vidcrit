#!/usr/bin/env python3
"""Builds the narration (Chatterbox TTS), aligns word timings (faster-whisper)
and resolves the whole storyboard into video/src/timing.json.

  python scripts/tts.py             -> real voice (needs chatterbox-tts)
  python scripts/tts.py --estimate  -> fake timings only (local previews)
"""
import json, os, re, subprocess, sys, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
FF = os.environ.get("FFMPEG", "ffmpeg")
SR = 48000
GAP = 0.07          # tiny breath between scenes (no dead air)
TEMPO = 1.07        # slightly snappier delivery for short-form
ESTIMATE = "--estimate" in sys.argv
PERSIST = {"hl", "pin", "arc", "ghost"}

story = json.load(open(os.path.join(ROOT, "story.json")))
os.makedirs(BUILD, exist_ok=True)


def norm(w):
    return re.sub(r"[^a-z0-9]", "", w.lower())


def parse_words(text):
    out, emph = [], False
    for tok in text.split():
        if tok.startswith("*"):
            emph = True
        shown = tok.replace("*", "")
        core = tok.rstrip(".,?!:;\"'")
        out.append({"w": shown, "emph": emph})
        if core.endswith("*"):
            emph = False
    return out


def spoken(text):
    return text.replace("*", "")


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def read_wav(path):
    with wave.open(path, "rb") as w:
        assert w.getframerate() == SR and w.getnchannels() == 1
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)


def write_wav(path, data):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.astype(np.int16).tobytes())


def median_f0(x):
    x = x.astype(np.float32) / 32768.0
    n = int(SR * 0.04)
    vals = []
    for i in range(0, len(x) - n, n):
        f = x[i:i + n]
        if np.sqrt(np.mean(f ** 2)) < 0.03:
            continue
        f = f - f.mean()
        ac = np.correlate(f, f, "full")[n - 1:]
        lo, hi = int(SR / 300), int(SR / 70)
        k = lo + int(np.argmax(ac[lo:hi]))
        if ac[k] > 0.4 * ac[0]:
            vals.append(SR / k)
    return float(np.median(vals)) if vals else 0.0


# ---------------------------------------------------------------- TTS
def synth_all(scenes):
    import torch
    import torchaudio as ta
    from chatterbox.tts import ChatterboxTTS

    model = ChatterboxTTS.from_pretrained(device="cpu")
    ref = os.environ.get("VOICE_REF", "")
    kw = {"audio_prompt_path": ref} if ref and os.path.exists(ref) else {}
    paths = []
    for i, sc in enumerate(scenes):
        torch.manual_seed(1234 + i)
        text = spoken(sc["text"])
        print(f"[tts] scene {i}: {text}", flush=True)
        wav = model.generate(text, exaggeration=0.55, cfg_weight=0.4, temperature=0.75, **kw)
        raw = os.path.join(BUILD, f"raw_{i}.wav")
        ta.save(raw, wav.cpu(), model.sr)
        out = os.path.join(BUILD, f"sc_{i}.wav")
        trim = ("silenceremove=start_periods=1:start_threshold=-48dB:start_silence=0.02,"
                "areverse,silenceremove=start_periods=1:start_threshold=-48dB:start_silence=0.03,areverse,"
                f"atempo={TEMPO},aresample={SR}")
        run([FF, "-y", "-i", raw, "-af", trim, "-ac", "1", "-c:a", "pcm_s16le", out])
        paths.append(out)
    return paths


def whisper_words(paths):
    try:
        from faster_whisper import WhisperModel
        m = WhisperModel("base.en", device="cpu", compute_type="int8")
    except Exception as e:  # pragma: no cover
        print("[align] whisper unavailable:", e)
        return [None] * len(paths)
    res = []
    for p in paths:
        try:
            segs, _ = m.transcribe(p, word_timestamps=True, language="en", beam_size=3)
            ws = [(w.start, w.end) for s in segs for w in (s.words or [])]
            res.append(ws or None)
        except Exception as e:
            print("[align] failed:", e)
            res.append(None)
    return res


def map_times(n_script, wh, dur):
    """Return n_script (start,end) pairs spanning exactly [0, dur]."""
    if wh and len(wh) >= 2:
        N = len(wh)
        starts = []
        for i in range(n_script):
            j = min(N - 1, int(round(i * N / n_script))) if N != n_script else i
            starts.append(max(0.0, wh[j][0]))
        starts[0] = 0.0
    else:
        starts = [dur * i / n_script for i in range(n_script)]
    starts = [min(s, dur - 0.05 * (n_script - i)) for i, s in enumerate(starts)]
    for i in range(1, n_script):  # monotonic
        starts[i] = max(starts[i], starts[i - 1] + 0.04)
    ends = starts[1:] + [dur]
    return list(zip(starts, ends))


def main():
    scenes = story["scenes"]
    n = len(scenes)
    parsed = [parse_words(s["text"]) for s in scenes]

    if ESTIMATE:
        durs = [len(p) * 0.34 for p in parsed]
        wh_list = [None] * n
        voice = None
    else:
        paths = synth_all(scenes)
        wh_list = whisper_words(paths)
        chunks = [read_wav(p) for p in paths]
        durs = [len(c) / SR for c in chunks]
        voice = []
        for c in chunks:
            voice.append(c)
            voice.append(np.zeros(int(GAP * SR), dtype=np.int16))
        voice = np.concatenate(voice)
        write_wav(os.path.join(BUILD, "voice.wav"), voice)
        print(f"[voice] median F0 = {median_f0(voice):.0f} Hz (male ~85-155, female ~165-255)")

    t = 0.0
    out_scenes = []
    for i, sc in enumerate(scenes):
        start = t
        end = t + durs[i] + GAP
        pw = parsed[i]
        times = map_times(len(pw), wh_list[i], durs[i])
        words = [{"w": w["w"], "emph": w["emph"], "start": round(start + a, 3), "end": round(start + b, 3)}
                 for w, (a, b) in zip(pw, times)]
        out_scenes.append({"id": sc["id"], "text": sc["text"], "mode": sc["mode"], "view": sc["view"],
                           "keep": bool(sc.get("keep")), "start": round(start, 3), "end": round(end, 3),
                           "words": words, "events": [], "sfx": []})
        t = end
    voice_end = t
    total = voice_end + story["endCard"]

    def resolve(i, at):
        words = out_scenes[i]["words"]
        if isinstance(at, (int, float)):
            idx = int(at)
        else:
            idx = next((k for k, w in enumerate(words) if norm(w["w"]) == norm(at)), None)
            if idx is None:
                print(f"[warn] scene {i}: word '{at}' not found")
                idx = 0
        idx = max(0, min(idx, len(words) - 1))
        return max(out_scenes[i]["start"], words[idx]["start"] - 0.06)

    def chain_end(i):
        k = i
        while k + 1 < n and out_scenes[k + 1]["keep"]:
            k += 1
        return out_scenes[k]["end"]

    for i, sc in enumerate(scenes):
        o = out_scenes[i]
        for ev in sc.get("events", []):
            e = dict(ev)
            e["time"] = round(resolve(i, ev["at"]), 3)
            if "dur" in ev and ev["t"] not in ("arc", "ghost"):
                e["end"] = round(e["time"] + ev["dur"], 3)
            elif ev["t"] in PERSIST:
                e["end"] = round(chain_end(i), 3)
            else:
                e["end"] = round(o["end"], 3)
            o["events"].append(e)
        for s in sc.get("sfx", []):
            o["sfx"].append({"time": round(resolve(i, s["at"]), 3), "s": s["s"], "v": s.get("v", 0.8)})
        if i > 0:
            switch = out_scenes[i - 1]["mode"] != o["mode"]
            o["sfx"].append({"time": round(o["start"] - 0.08, 3),
                             "s": "zoom" if switch else ["whoosh1", "whoosh2", "whoosh3"][i % 3],
                             "v": 0.55 if switch else 0.5})
    out_scenes[-1]["sfx"].append({"time": round(voice_end - 0.05, 3), "s": "reveal", "v": 0.5})

    timing = {"fps": story["fps"], "total": round(total, 3), "voiceEnd": round(voice_end, 3),
              "channel": story["channel"], "credits": story["credits"], "scenes": out_scenes}
    dst = os.path.join(ROOT, "video", "src", "timing.json")
    json.dump(timing, open(dst, "w"), indent=1)
    print(f"[timing] scenes={n} voiceEnd={voice_end:.2f}s total={total:.2f}s -> {dst}")


if __name__ == "__main__":
    main()
