-- Actors: villager + chicken (pinned every tick with set_pos, physical=false) and the TNT.
local C  = skit.cfg
local FX = skit.fx
local A  = {}

local PI = math.pi
local sin, cos, exp, abs = math.sin, math.cos, math.exp, math.abs

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
local function smooth(k) k = clamp(k, 0, 1); return k * k * (3 - 2 * k) end

local ZERO = { x = 0, y = 0, z = 0 }

-- ---------------------------------------------------------------- choreography
-- Villager (stands at x = -AX, facing the camera = -Z = yaw PI).
local function villager_pre(t)
  t = math.max(t, 0)
  local x, y = -C.AX, skit.YS
  local yaw = PI + 0.22 * sin(t * 1.7)                 -- bored, looking around
  if t >= C.T_NOTICE then                              -- notices the TNT, turns towards it
    local from = PI + 0.22 * sin(C.T_NOTICE * 1.7)
    local k = smooth((t - C.T_NOTICE) / 0.6)
    yaw = from + (PI + PI / 4 - from) * k
  end
  if t > C.T_PANIC then                                -- trembling
    local a = clamp((t - C.T_PANIC) / 1.2, 0, 1)
    yaw = yaw + 0.12 * a * sin(t * 36)
    x = x + 0.012 * a * sin(t * 51)
  end
  return x, y, yaw
end

local function villager_pose(t)
  if t < C.T_BOOM then return villager_pre(t) end
  local _, yb, yawb = villager_pre(C.T_BOOM - 0.001)
  local u = t - C.T_BOOM
  local x, y = -C.AX, yb
  if u < 0.4 then y = y + 0.18 * sin(PI * u / 0.4) end -- blast hop
  local k = smooth(u / 0.9)
  local yaw = PI + (yawb - PI) * (1 - k) + 0.35 * sin(u * 7) * exp(-u * 1.4) -- dizzy, then faces camera
  if t >= C.T_LAND then
    local v = t - C.T_LAND
    y = y - 0.05 * exp(-v * 8) * abs(sin(v * 14))      -- knees buckle under the chicken
    yaw = yaw + 0.10 * smooth(v / 1.0) * sin(v * 2.3)
  end
  return x, y, yaw
end

-- Chicken (stands at x = +AX, faces the villager = -X = yaw PI/2).
local function chicken_pre(t)
  t = math.max(t, 0)
  local x, y = C.AX, skit.YS
  local yaw = PI / 2 + 0.18 * sin(t * 2.1)
  if t >= 2.0 then                                     -- turns to camera and "lays" the TNT
    local from = PI / 2 + 0.18 * sin(2.0 * 2.1)
    yaw = from + (PI - from) * smooth((t - 2.0) / 0.4)
    if t >= 2.9 then                                   -- then watches it
      yaw = PI + (PI / 2 - PI) * smooth((t - 2.9) / 0.5)
    end
    if t >= 2.3 and t <= 2.6 then
      y = y + 0.12 * sin(PI * (t - 2.3) / 0.3)         -- little hop when it pops out
    end
  end
  if t > 4.5 then                                      -- panics
    local a = clamp((t - 4.5) / 0.9, 0, 1)
    yaw = yaw + 0.25 * a * sin(t * 30)
    y = y + 0.03 * a * abs(sin(t * 25))
  end
  return x, y, yaw
end

local function chicken_pose(t)
  if t < C.T_BOOM then return chicken_pre(t) end
  local xb, yb, yawb = chicken_pre(C.T_BOOM - 0.001)
  local u = t - (C.T_BOOM + C.FLIGHT_DELAY)
  if u <= 0 then return xb, yb, yawb end
  local YS = skit.YS
  if t < C.T_LAND then
    local k = clamp(u / C.FLIGHT_T, 0, 1)
    -- x arrives above the villager early, then the chicken drops straight onto the head
    local x = xb + (-C.AX - xb) * (1 - (1 - k) ^ 2.5)
    local y
    if u <= C.FLIGHT_RISE then
      local vy = math.sqrt(2 * C.FLIGHT_G * C.FLIGHT_PEAK)
      y = YS + vy * u - 0.5 * C.FLIGHT_G * u * u
    else
      local w = u - C.FLIGHT_RISE
      y = YS + C.FLIGHT_PEAK - 0.5 * C.FLIGHT_G * w * w
    end
    local yaw = yawb + (PI - yawb - 4 * PI) * k       -- two spins, ends facing the camera
    return x, y, yaw
  end
  local v = t - C.T_LAND
  local y = YS + C.VILLAGER_HEAD + 0.14 * exp(-v * 7) * abs(sin(v * 11)) -- squash/bounce on landing
  local yaw = PI + 0.2 * smooth(v / 0.8) * sin(t * 3)
  return -C.AX, y, yaw
end

-- animation triggers { time, name, speed }
local VILLAGER_ANIMS = {
  { 3.45, "head_shake", 14 }, { 4.35, "stand" },
  { 6.85, "head_shake", 14 }, { 7.75, "stand" },
  { 8.45, "head_nod", 14 },   { 9.25, "stand" },
}
local CHICKEN_ANIMS = {
  { 2.00, "flap", 30 }, { 2.70, "stand" },
  { 4.50, "flap", 45 },
  { C.T_BOOM + 0.04, "flap", 70 },
  { C.T_LAND + 0.1, "stand" },
  { 9.00, "flap", 30 }, { 9.50, "stand" },
}

-- ---------------------------------------------------------------- helpers
local function freeze(obj)
  local ent = obj:get_luaentity()
  if not ent then error("skit: spawned object has no luaentity") end
  ent._skit_keep = true
  -- disable the mob AI completely: we drive position and yaw ourselves
  ent.on_step      = function() end
  ent.deal_damage  = function() end
  ent.damage_mob   = function() end
  ent.on_punch     = function() return true end
  ent.on_rightclick = function() end
  ent.health       = 1000
  ent.can_despawn  = false
  obj:set_armor_groups({ immortal = 1 })
  obj:set_properties({ physical = false, collide_with_objects = false, static_save = false })
  obj:set_velocity(ZERO)
  obj:set_acceleration(ZERO)
  return ent
end

local function play(obj, ent, name, speed)
  local a = ent.animation
  if not (a and a[name .. "_start"]) then return end
  local loop = a[name .. "_loop"] ~= false
  obj:set_animation({ x = a[name .. "_start"], y = a[name .. "_end"] },
    speed or a[name .. "_speed"] or 25, 0, loop)
end

-- ---------------------------------------------------------------- lifecycle
function A.spawn()
  local YS = skit.YS
  -- add_entity RETURNS AN ObjectRef (not the luaentity); get_luaentity() gives the table.
  local vobj = core.add_entity({ x = -C.AX, y = YS, z = 0 }, "mobs_mc:villager")
  local cobj = core.add_entity({ x =  C.AX, y = YS, z = 0 }, "mobs_mc:chicken")
  if not vobj then error("skit: could not spawn mobs_mc:villager") end
  if not cobj then error("skit: could not spawn mobs_mc:chicken") end
  A.vobj, A.cobj = vobj, cobj
  A.vent = freeze(vobj)
  A.cent = freeze(cobj)
  play(vobj, A.vent, "stand")
  play(cobj, A.cent, "stand")
  A.vi, A.ci, A.pi = 1, 1, 1
  A.tnt, A.exploded, A.landed = nil, false, false
  A.next_blink, A.blink_on = 0, false
  A.pulses = { C.T_BOOM - 0.55, C.T_BOOM - 0.30, C.T_BOOM - 0.16, C.T_BOOM - 0.07 }
  local vx, vy, vyaw = villager_pose(0)
  local cx, cy, cyaw = chicken_pose(0)
  vobj:set_pos({ x = vx, y = vy, z = 0 }); vobj:set_yaw(vyaw)
  cobj:set_pos({ x = cx, y = cy, z = 0 }); cobj:set_yaw(cyaw)
  skit.log(string.format("actors spawned: villager=%s chicken=%s", vobj:get_luaentity().name, cobj:get_luaentity().name))
end

local function tnt_pos() return { x = 0, y = skit.YS + C.TNT_Y, z = 0 } end

local function spawn_tnt(t)
  local obj = core.add_entity(tnt_pos(), "mcl_tnt:tnt")
  if not obj then error("skit: could not spawn mcl_tnt:tnt") end
  local ent = obj:get_luaentity()
  if ent then
    ent._skit_keep = true
    ent.on_step = function() end        -- no gravity/auto-boom (it would use strength 4)
  end
  obj:set_properties({ physical = false, static_save = false })
  obj:set_velocity(ZERO)
  obj:set_acceleration(ZERO)
  A.tnt = obj
  A.next_blink = t
  FX.poof(tnt_pos())
  FX.fuse(tnt_pos(), C.T_BOOM - t)
  skit.event("tnt_spawn", C.T_TNT, t)
end

local function update_tnt(t)
  local u = t - C.T_TNT
  local p = tnt_pos()
  local sc = 1
  if u < 0.25 then
    p.y = p.y + 0.35 * sin(PI * u / 0.25)
    sc = 0.4 + 0.6 * smooth(u / 0.2)
  end
  local frac = clamp(u / (C.T_BOOM - C.T_TNT), 0, 1)
  sc = sc * (1 + 0.10 * frac * frac * (0.5 + 0.5 * sin(t * 28)))
  A.tnt:set_pos(p)
  A.tnt:set_velocity(ZERO)
  A.tnt:set_properties({ visual_size = { x = sc, y = sc, z = sc } })
  if t >= A.next_blink then
    A.blink_on = not A.blink_on
    A.tnt:set_texture_mod(A.blink_on and "^mcl_tnt_blink.png" or "")
    A.next_blink = t + (0.35 - 0.26 * frac * frac)
  end
end

local function explode(t)
  local pos = tnt_pos()
  if A.tnt then A.tnt:remove(); A.tnt = nil end
  A.exploded = true
  skit.event("explosion", C.T_BOOM, t)
  if mcl_explosions and mcl_explosions.explode then
    local ok, err = pcall(mcl_explosions.explode, pos, C.STRENGTH,
      { drop_chance = 0, fire = false, griefing = true })
    skit.log(string.format("mcl_explosions.explode strength=%.2f ok=%s %s", C.STRENGTH, tostring(ok), ok and "" or tostring(err)))
  else
    skit.log("WARNING: mcl_explosions missing, only particles are shown")
  end
  FX.boom(pos)
  -- soot on both actors
  core.after(0.08, function()
    if A.vobj then A.vobj:set_texture_mod("^[colorize:#101010:135") end
    if A.cobj then A.cobj:set_texture_mod("^[colorize:#101010:135") end
  end)
  -- the stage must still be standing
  core.after(0.7, function()
    local missing = skit.stage.verify(true)
    skit.log("stage check after explosion: missing nodes = " .. missing)
    skit.event("stage_standing", nil, nil, missing == 0 and "yes" or ("repaired " .. missing))
  end)
end

-- t = seconds after the marker (0 while waiting); running = timeline is live
function A.update(t, running)
  if not A.vobj then return end

  if running then
    while VILLAGER_ANIMS[A.vi] and VILLAGER_ANIMS[A.vi][1] <= t do
      local a = VILLAGER_ANIMS[A.vi]; play(A.vobj, A.vent, a[2], a[3]); A.vi = A.vi + 1
    end
    while CHICKEN_ANIMS[A.ci] and CHICKEN_ANIMS[A.ci][1] <= t do
      local a = CHICKEN_ANIMS[A.ci]; play(A.cobj, A.cent, a[2], a[3]); A.ci = A.ci + 1
    end
    if (not A.tnt) and (not A.exploded) and t >= C.T_TNT then spawn_tnt(t) end
    if A.tnt then
      while A.pulses[A.pi] and A.pulses[A.pi] <= t do
        FX.pulse(tnt_pos()); A.pi = A.pi + 1
      end
      if t >= C.T_BOOM then explode(t) else update_tnt(t) end
    end
    if t >= C.T_NOTICE and not A.noticed then
      A.noticed = true; skit.event("villager_notices", C.T_NOTICE, t)
    end
    if t >= C.T_LAND and not A.landed then
      A.landed = true; skit.event("chicken_lands_on_head", C.T_LAND, t)
    end
  end

  local vx, vy, vyaw = villager_pose(t)
  local cx, cy, cyaw = chicken_pose(t)
  A.vobj:set_pos({ x = vx, y = vy, z = 0 }); A.vobj:set_yaw(vyaw); A.vobj:set_velocity(ZERO)
  A.cobj:set_pos({ x = cx, y = cy, z = 0 }); A.cobj:set_yaw(cyaw); A.cobj:set_velocity(ZERO)
end

return A
