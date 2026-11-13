# vidcrit

Silent two-actor comedy skit (villager vs. chicken + TNT) rendered inside a real
**VoxeLibre 0.92.4** world on **Luanti ≥ 5.10**, as a vertical **720×1280** video.

> Rendering happens **only** in GitHub Actions (`.github/workflows/render.yml`).
> Locally you may only edit files and syntax-check Lua (`luac5.1 -p`).

## Pipeline (job `luanti`, ubuntu-24.04)

| script | what it does |
| --- | --- |
| `scripts/01_install.sh` | PPA `ppa:minetestdevs/stable`, rejects engine `< 5.10`, downloads VoxeLibre (`mineclone2` → `~/.luanti/games/voxelibre`) |
| `scripts/02_prepare_world.sh` | `luac5.1 -p`, creates world `skit` (`map_meta.txt` ends with `[end_of_params]`), config |
| `scripts/03_render.sh` | Xvfb `:99 720x1280x24` + openbox, `luanti --go --gameid voxelibre --worldname skit --name Cam`, ffmpeg x11grab 30 fps |
| `scripts/04_postprocess.sh` | cuts exactly 10.9 s after the `skit_t0` marker, makes mp4 / gif / stills, checks size, duration and explosion timing |

Artifact `vidcrit-skit`: `skit.mp4`, `skit.gif`, `stills/`, `logs/` (+ `summary.md`).

## Mod (`skit/worldmods/skit`)

* Stage: 5×5 wooden stage, two layers, plus a 3-block backdrop (red curtain, gold valance).
  Their blast resistance is raised so the stage stays standing.
* Actors `mobs_mc:villager` / `mobs_mc:chicken`: AI disabled, pinned every tick with
  `set_pos` + `physical=false` (`add_entity` returns an **ObjectRef**, `get_luaentity()` gives the table).
* TNT (`mcl_tnt:tnt` entity used for the blink) explodes at **5.42 s** with strength **2.2**
  (hard cap 2.5 asserted in `cfg.lua`); then the chicken is launched and lands on the villager's head.
* Camera: keyframes on the forward axis, **one** look-at point on that axis. The yaw/pitch convention of
  `set_look_*` is **measured once** (`get_look_dir`) and cached; it is never repeated per frame.
  Distance 6.3–6.9 blocks, actors within ±1.2 blocks of the axis, villager head in the upper third,
  stage floor at the bottom. Vertical FOV 42° (Luanti multiplies the `fov` by 1.4 on narrow windows).
* No HUD: `hud_set_flags` + removal of every element returned by `hud_get_all()` (no `pcall` in that loop).
* Events are logged to `skit_events.log` with actual vs expected time (tolerance ±0.2 s).

## Timeline

| t (s) | event |
| --- | --- |
| 0.00 | marker `skit_t0` |
| 2.40 | TNT appears |
| 2.90 | villager notices |
| 5.42 | explosion |
| ≈6.30 | chicken lands on the villager's head |
| 10.90 | end of video |
