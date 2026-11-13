-- skit: silent comedy skit for vertical video, rendered headless in CI.
-- Flow: join -> emerge -> build stage -> spawn actors -> attach camera -> calibrate once
--       -> settle -> skit_ready -> pre-roll -> skit_t0 (marker) -> timeline -> shutdown.
skit = {}

local modpath   = core.get_modpath(core.get_current_modname())
local worldpath = core.get_worldpath()

skit.store = core.get_mod_storage()
skit.cfg   = dofile(modpath .. "/cfg.lua")
local C    = skit.cfg

function skit.log(msg)
  core.log("action", "[skit] " .. msg)
end

function skit.write_file(name, content, append)
  local f = io.open(worldpath .. "/" .. name, append and "a" or "w")
  if f then
    f:write(content)
    f:close()
  end
end

-- Timeline event log: actual time vs expected time (acceptance: within +-0.2 s).
function skit.event(name, expected, t, note)
  if t == nil and skit.t0_us then t = (core.get_us_time() - skit.t0_us) / 1e6 end
  local line
  if t then
    local delta = expected and string.format("%+.3f", t - expected) or "n/a"
    line = string.format("t=%7.3f expected=%s delta=%s event=%s%s", t,
      expected and string.format("%.2f", expected) or "-", delta, name, note and (" (" .. note .. ")") or "")
  else
    line = string.format("t=pre event=%s%s", name, note and (" (" .. note .. ")") or "")
  end
  skit.log(line)
  skit.write_file("skit_events.log", line .. "\n", true)
end

skit.stage   = dofile(modpath .. "/stage.lua")
skit.fx      = dofile(modpath .. "/fx.lua")
skit.camera  = dofile(modpath .. "/camera.lua")
skit.actors  = dofile(modpath .. "/actors.lua")

local stage, camera, actors = skit.stage, skit.camera, skit.actors

-- no "joined the game" chat line in the frame
core.send_join_message  = function() end
core.send_leave_message = function() end

-- stage + backdrop materials survive the blast (must happen before mods_loaded)
stage.protect()

-- invisible entity the player (= the camera) is attached to
core.register_entity("skit:cam", {
  initial_properties = {
    physical = false, collide_with_objects = false, pointable = false,
    visual = "sprite", textures = { "blank.png" }, is_visible = false,
    static_save = false, collisionbox = { 0, 0, 0, 0, 0, 0 },
  },
  _skit_keep = true,
})

-- ------------------------------------------------------------------ helpers
local HUD_OFF = {
  hotbar = false, healthbar = false, crosshair = false, wielditem = false,
  breathbar = false, minimap = false, minimap_radar = false, basic_debug = false,
  chat = false,
}

-- Strip every HUD element (VoxeLibre adds hunger/xp/armor bars...). No pcall here.
local function clean_hud(player)
  player:hud_set_flags(HUD_OFF)
  local removed = 0
  for id in pairs(player:hud_get_all()) do
    player:hud_remove(id)
    removed = removed + 1
  end
  return removed
end

local player_name
local function get_player()
  return player_name and core.get_player_by_name(player_name) or nil
end

local function gamerule(rule, value)
  local cmd = core.registered_chatcommands["gamerule"]
  if cmd and cmd.func then
    local ok, a = pcall(cmd.func, player_name, rule .. " " .. value)
    skit.log(string.format("gamerule %s %s -> ok=%s %s", rule, value, tostring(ok), tostring(a)))
  end
end

local S = { state = "wait_join", timer = 0 }

-- --------------------------------------------------------------- build stage
local function on_emerged()
  if S.state ~= "emerging" then return end
  S.state = "building"
  local player = get_player()
  if not player then
    skit.log("player vanished before build")
    S.state = "emerging"
    core.after(1, on_emerged)
    return
  end

  local GY = stage.find_ground()
  if not GY then
    GY = 8
    skit.log("WARNING: no ground found at origin, using y=8 and forcing a floor")
  end
  skit.GY = GY
  skit.YS = GY + 2.5            -- stage top surface (upper layer node centre = GY+2)
  skit.log(string.format("ground y=%d, stage surface y=%.1f", GY, skit.YS))

  local nodes = stage.build(GY)
  skit.log("stage built: " .. #nodes .. " nodes (" .. stage.materials.lower .. " / " .. stage.materials.upper
    .. " / " .. stage.materials.curtain .. ")")

  gamerule("doWeatherCycle", "false")
  gamerule("doMobSpawning", "false")
  gamerule("doDaylightCycle", "false")
  core.set_timeofday(0.5)
  stage.sweep()

  -- camera rig: player attached to an invisible entity that we move smoothly
  local cam = core.add_entity({ x = 0, y = skit.YS + 0.5, z = -C.KEYS[1].d }, "skit:cam")
  if not cam then error("skit: could not spawn camera entity") end
  skit.cam = cam
  player:set_attach(cam, "", { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
  if player.set_camera then player:set_camera({ mode = "first" }) end

  local fov, mult = camera.fov_setting()
  player:set_fov(fov, false, 0)
  skit.log(string.format("fov setting=%.3f (engine multiplier %.3f -> vertical %.1f deg)", fov, mult, fov * mult))
  local eo = player:get_eye_offset()
  skit.log(string.format("eye_height=%s eye_offset_first=(%.2f,%.2f,%.2f)",
    tostring(player:get_properties().eye_height), eo.x, eo.y, eo.z))
  player:set_clouds({ density = 0 })

  camera.calibrate(player)            -- once, never again
  actors.spawn()
  actors.update(0, false)
  camera.update(player, cam, 0, core.get_us_time() / 1e6)

  local removed = clean_hud(player)
  skit.log("hud elements removed: " .. removed)

  S.state, S.timer = "settle", 0
  skit.event("camera_ready")
end

local function start_emerge()
  local p1 = { x = -48, y = 0, z = -48 }
  local p2 = { x = 48, y = 47, z = 48 }
  skit.log("emerging area...")
  core.emerge_area(p1, p2, function(_, _, remaining)
    if remaining == 0 then core.after(0.3, on_emerged) end
  end)
  core.after(150, on_emerged)    -- safety net (guarded by S.state)
end

core.register_on_joinplayer(function(player)
  if S.state ~= "wait_join" then return end
  player_name = player:get_player_name()
  skit.log("player joined: " .. player_name)
  player:set_armor_groups({ immortal = 1 })
  S.state = "emerging"
  core.after(1.0, start_emerge)
end)

-- ---------------------------------------------------------------- main loop
local acc_sweep, acc_hud, acc_tod = 0, 0, 0

core.register_globalstep(function(dtime)
  local st = S.state
  if st == "wait_join" or st == "emerging" or st == "building" then return end
  local player = get_player()
  if not player or not skit.cam then return end
  local now = core.get_us_time() / 1e6

  acc_sweep, acc_hud, acc_tod = acc_sweep + dtime, acc_hud + dtime, acc_tod + dtime
  if acc_sweep > 0.5 then acc_sweep = 0; stage.sweep() end
  if acc_hud > 1.0 then acc_hud = 0; clean_hud(player) end
  if acc_tod > 3.0 then
    acc_tod = 0
    core.set_timeofday(0.5)
    player:set_clouds({ density = 0 })
  end

  if st == "settle" or st == "preroll" then
    camera.update(player, skit.cam, 0, now)
    actors.update(0, false)
    S.timer = S.timer + dtime
    if st == "settle" and S.timer >= C.SETTLE then
      skit.write_file("skit_ready", string.format("%d\n", os.time()))
      skit.event("skit_ready")
      S.state, S.timer = "preroll", 0
    elseif st == "preroll" and S.timer >= C.PRE_ROLL then
      -- marker file first, then the clock: file mtime == t0
      skit.write_file("skit_t0", string.format("%d\n", os.time()))
      skit.t0_us = core.get_us_time()
      skit.event("skit_t0", 0, 0)
      S.state = "run"
    end
    return
  end

  if st == "run" then
    local t = (core.get_us_time() - skit.t0_us) / 1e6
    camera.update(player, skit.cam, t, now)
    actors.update(t, true)
    if t >= C.DURATION and not S.end_logged then
      S.end_logged = true
      skit.event("video_end", C.DURATION, t)
    end
    if t >= C.T_SHUTDOWN then
      S.state = "done"
      skit.write_file("skit_done", string.format("%d\n", os.time()))
      skit.event("shutdown", C.T_SHUTDOWN, t)
      core.request_shutdown("skit finished", false, 0)
    end
  end
end)
