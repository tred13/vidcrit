-- Central configuration + timeline for the skit. Every other file reads from here.
local C = {}

C.PLAYER = "Cam"

-- ---------------------------------------------------------------- timeline
-- All times are seconds after the skit_t0 marker.
C.DURATION   = 10.9    -- length of the final video
C.T_TNT      = 2.40    -- chicken "lays" the TNT
C.T_NOTICE   = 2.90    -- villager notices it
C.T_PANIC    = 4.20    -- villager starts trembling
C.T_BOOM     = 5.42    -- explosion (spec)
C.T_SHUTDOWN = 12.8    -- ask the server to quit after everything was filmed

-- Explosion strength is hard-capped by the brief (never above 2.5).
C.STRENGTH = 2.2
assert(C.STRENGTH <= 2.5, "skit: explosion strength must stay <= 2.5")

-- Pre-roll before the marker: world has to reach the client first.
C.SETTLE   = 6.0   -- seconds between "camera in place" and skit_ready
C.PRE_ROLL = 3.0   -- seconds between skit_ready and skit_t0 (ffmpeg start-up room)

-- ----------------------------------------------------------------- layout
-- Stage surface height is YS (computed at runtime from the terrain).
C.STAGE_HALF = 2          -- 5x5 stage
C.AX         = 0.85       -- actors stand at x = -AX (villager) / +AX (chicken)
C.TNT_Y      = 0.5        -- TNT centre above stage surface
C.VILLAGER_HEAD = 1.96    -- landing height (just above villager's head box)

-- ------------------------------------------------------------------ camera
-- Camera lives on the forward axis (x = 0, looking +Z) and ALWAYS looks at ONE
-- point on that axis: (0, YS + TY, 0).
C.TY      = 0.98
C.FOV_Y   = 42            -- wanted rendered VERTICAL fov (degrees)
C.ASPECT  = 720 / 1280
-- d = distance in blocks (kept inside 6..7), h = camera height above stage surface
C.KEYS = {
  { t =  0.0, d = 6.90, h = 2.10 },
  { t =  2.0, d = 6.80, h = 1.95 },
  { t =  4.8, d = 6.55, h = 1.75 },
  { t =  5.4, d = 6.50, h = 1.72 },
  { t =  6.6, d = 6.40, h = 1.70 },
  { t =  8.6, d = 6.32, h = 1.62 },
  { t = 10.9, d = 6.30, h = 1.55 },
}

-- ----------------------------------------------------------- chicken flight
C.FLIGHT_G     = 14.0
C.FLIGHT_PEAK  = 2.4      -- apex above stage surface (keeps the chicken in frame)
C.FLIGHT_DELAY = 0.04     -- blast "kick" before the chicken leaves the floor
do
  local rise = math.sqrt(2 * C.FLIGHT_PEAK / C.FLIGHT_G)
  local fall = math.sqrt(2 * (C.FLIGHT_PEAK - C.VILLAGER_HEAD) / C.FLIGHT_G)
  C.FLIGHT_RISE = rise
  C.FLIGHT_FALL = fall
  C.FLIGHT_T    = rise + fall
  C.T_LAND      = C.T_BOOM + C.FLIGHT_DELAY + rise + fall
end

return C
