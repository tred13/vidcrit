# vidcrit — Luanti vertical skit renderer

Silent comedy skit (villager + chicken + TNT) rendered **only in GitHub Actions**
with Luanti ≥ 5.10 (PPA `minetestdevs/stable`) and VoxeLibre 0.92.4.
Output: 720×1280 / 30 fps / 10.9 s after the `skit_t0` marker.

```
.github/workflows/render.yml   job `luanti` on ubuntu-24.04
scripts/setup.sh               PPA install, refuses Luanti < 5.10
scripts/install_game.sh        VoxeLibre -> ~/.luanti/games/voxelibre, world, mod
scripts/run_skit.sh            Xvfb :99 720x1280x24 + openbox + luanti + ffmpeg x11grab
scripts/verify.sh              acceptance checks (timing, strength, stage, framing, video)
mod/skit/init.lua              stage, actors, TNT, camera, timeline, HUD stripping
config/                        luanti.conf, world.mt, map_meta.txt ([end_of_params])
```

## Timeline (seconds after `skit_t0`)

| T | event |
|---|-------|
| 0.00 | marker written, actors idle facing the camera |
| 1.20 | both turn to the TNT |
| 2.60 | TNT starts flashing |
| **5.42** | **explosion, strength 2.2** (hard cap 2.5) |
| 6.36 | chicken apex |
| 6.85 | chicken lands on the villager's head |
| 10.90 | end |

## Design notes

* **Sync**: ffmpeg starts first; the mod only starts the clock when the recorder
  creates `skit_go`. The recorder derives ffmpeg's first-frame wall time from the
  progress file and trims `-ss (mtime(skit_t0) - first_frame)` so events land within ±0.2 s.
* **Camera**: keyframes + one look point on the forward axis (x=0,z=0). The rotation
  convention is measured **once** (`skit_rotconv`) and cached; never per frame.
* **FOV**: Luanti scales vertical FOV by `clamp(sqrt(1.6/aspect),1,1.4)`; for 9:16 the
  mod sets `fov = 50/1.4` so the vertical FOV is 50°. Distance 6.2–6.9 blocks, actors at ±0.9.
* **HUD**: all HUD elements removed every step via `hud_get_all` (no `pcall`) + all flags off.
* **Actors**: `add_entity` returns an ObjectRef; the luaentity is fetched from it. Mob AI is
  replaced by a no-op `on_step`; `set_pos` + `physical=false` every tick.
* **Explosion**: `mcl_explosions.explode(pos, 2.2, {griefing=false,...})` — the stage can't be
  destroyed; entities, particles and sound still behave like a real blast. The stage is also
  verified node-by-node afterwards.
