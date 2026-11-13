-- Camera: keyframes on the forward axis + a single look-at point on that axis.
-- The yaw/pitch convention of set_look_* is MEASURED once (never assumed) and cached.
local C = skit.cfg
local M = {}

local PI = math.pi
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function wrap(a)
  while a > PI do a = a - 2 * PI end
  while a <= -PI do a = a + 2 * PI end
  return a
end

-- angle of a horizontal direction, measured from +Z towards -X
local function theta(dx, dz) return atan2(-dx, dz) end

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
local function smooth(k) k = clamp(k, 0, 1); return k * k * (3 - 2 * k) end

-- ------------------------------------------------------------ calibration
-- One-shot experiment. Called exactly once; result is cached in M.cal and stored
-- in mod storage + a file in the world dir. It is never repeated per frame
-- (repeating it would make the camera flash).
function M.calibrate(player)
  if M.cal then return M.cal end

  local test_pitch = 0.5
  player:set_look_vertical(0)
  player:set_look_horizontal(0)
  local d0 = player:get_look_dir()
  player:set_look_horizontal(PI / 2)
  local d1 = player:get_look_dir()
  player:set_look_horizontal(0)
  player:set_look_vertical(test_pitch)
  local dp = player:get_look_dir()
  player:set_look_vertical(0)
  player:set_look_horizontal(0)

  local cal = { measured = true }

  local h0 = math.sqrt(d0.x * d0.x + d0.z * d0.z)
  local h1 = math.sqrt(d1.x * d1.x + d1.z * d1.z)
  if h0 > 0.5 and h1 > 0.5 then
    local t0 = theta(d0.x, d0.z)
    local t1 = theta(d1.x, d1.z)
    local diff = wrap(t1 - t0)
    cal.yaw_base  = t0
    cal.yaw_sign  = (diff >= 0) and 1 or -1
    cal.yaw_scale = math.max(1e-3, math.abs(diff) / (PI / 2))
  else
    cal.measured  = false
    cal.yaw_base, cal.yaw_sign, cal.yaw_scale = 0, 1, 1
  end

  local elev = math.asin(clamp(dp.y, -1, 1))
  cal.pitch_scale = elev / test_pitch
  if math.abs(cal.pitch_scale) < 0.2 then
    cal.measured = false
    cal.pitch_scale = -1
  end

  M.cal = cal
  local line = string.format(
    "yaw_base=%.4f yaw_sign=%d yaw_scale=%.4f pitch_scale=%.4f measured=%s | d0=(%.3f,%.3f,%.3f) d1=(%.3f,%.3f,%.3f) dp=(%.3f,%.3f,%.3f)",
    cal.yaw_base, cal.yaw_sign, cal.yaw_scale, cal.pitch_scale, tostring(cal.measured),
    d0.x, d0.y, d0.z, d1.x, d1.y, d1.z, dp.x, dp.y, dp.z)
  skit.log("calibration: " .. line)
  skit.store:set_string("calibration", line)
  skit.write_file("skit_calibration.txt", line .. "\n")
  return cal
end

-- yaw / pitch arguments for set_look_* so that the camera looks from `from` to `to`
local function look_args(from, to)
  local cal = M.cal
  local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
  local hlen = math.sqrt(dx * dx + dz * dz)
  local a = theta(dx, dz)
  local yaw = cal.yaw_sign * wrap(a - cal.yaw_base) / cal.yaw_scale
  local elev = atan2(dy, hlen)
  local pitch = elev / cal.pitch_scale
  return yaw, pitch
end

-- ---------------------------------------------------------------- keyframes
function M.pose_at(t)
  local keys = C.KEYS
  if t <= keys[1].t then return keys[1].d, keys[1].h end
  for i = 2, #keys do
    local a, b = keys[i - 1], keys[i]
    if t <= b.t then
      local k = smooth((t - a.t) / (b.t - a.t))
      return a.d + (b.d - a.d) * k, a.h + (b.h - a.h) * k
    end
  end
  local last = keys[#keys]
  return last.d, last.h
end

-- short, decaying camera shake when the TNT blows
local function shake(t)
  local u = t - C.T_BOOM
  if u < 0 or u > 0.8 then return 0, 0 end
  local amp = 0.06 * math.exp(-u * 6)
  return amp * math.sin(u * 63), amp * math.cos(u * 51)
end

-- the single look-at point, on the forward axis
function M.target()
  return { x = 0, y = skit.YS + C.TY, z = 0 }
end

-- Resting camera position (without shake) at time t
function M.position(t)
  local d, h = M.pose_at(t)
  return { x = 0, y = skit.YS + h, z = -d }
end

local last_yaw, last_pitch, last_sent = nil, nil, 0

-- Place the camera for time t. cam_obj is the invisible entity the player is attached to.
function M.update(player, cam_obj, t, now)
  local base = M.position(t)
  local sx, sy = shake(t)
  local eye = player:get_properties().eye_height or 1.625
  -- camera = parent position + eye height (client uses the parent's position when attached)
  cam_obj:set_pos({ x = base.x + sx, y = base.y + sy - eye, z = base.z })

  local yaw, pitch = look_args(base, M.target())
  if (not last_yaw) or math.abs(yaw - last_yaw) > 1e-4 or math.abs(pitch - last_pitch) > 1e-4
      or (now - last_sent) > 0.5 then
    player:set_look_horizontal(yaw)
    player:set_look_vertical(pitch)
    last_yaw, last_pitch, last_sent = yaw, pitch, now
  end
end

-- vertical fov bookkeeping: Luanti multiplies the fov setting on narrow aspect ratios
function M.fov_setting()
  local mult = clamp(math.sqrt((16 / 10) / C.ASPECT), 1.0, 1.4)
  return C.FOV_Y / mult, mult
end

return M
