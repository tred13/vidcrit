-- skit: silent comedy skit between a villager and a chicken, driven entirely
-- by this mod so the CI recorder only has to capture the X display.
--
-- Handshake with scripts/run_skit.sh (all files live in the world dir):
--   skit_ready   written by the mod when scene + camera are ready
--   skit_go      written by the recorder once ffmpeg is capturing
--   skit_t0      written by the mod the very step it sees skit_go
--                (timeline T=0; its mtime is the sync reference)
--   skit_rotconv written once: the measured rotation convention
--   skit_events.log  every timeline event with target/actual time
--
-- Coordinates: the stage is centred on x=0,z=0. The camera sits on the
-- x=0 axis at negative z, looking at ONE point on that forward axis.

local WORLD = core.get_worldpath()

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------
local CFG = {
	strength    = 2.2,    -- TNT blast strength (hard cap 2.5)
	t_explosion = 5.42,   -- seconds after skit_t0
	duration    = 10.9,   -- seconds recorded after skit_t0
	warmup      = 6.0,    -- seconds between "scene built" and skit_ready
	fov_y_deg   = 50,     -- desired *vertical* field of view in degrees
	aspect_fb   = 720 / 1280,
	-- actors (screen-space x, relative to the forward axis)
	villager_x  = -0.9,
	chicken_x   =  0.9,
	tnt_z       =  1.0,   -- TNT sits behind and between the actors
	villager_h  =  1.94,  -- villager collisionbox top
	chicken_launch_s = 1.43, -- airtime of the chicken after the blast
	chicken_apex     = 1.5,  -- keeps the chicken inside the top of the frame
}
assert(CFG.strength <= 2.5, "skit: explosion strength must stay <= 2.5")

-- camera keyframes, relative to (x=0, stage surface, z=0). One look point.
local LOOK = { x = 0, y = 0.8, z = 0 }
local KEYS = {
	{ t = 0.0,  x = 0, y = 2.70, z = -6.60 },
	{ t = 5.0,  x = 0, y = 2.65, z = -6.45 },
	{ t = 7.0,  x = 0, y = 2.60, z = -6.30 },
	{ t = 10.9, x = 0, y = 2.60, z = -6.20 },
}

-- animation frame ranges (from mobs_mc villager.lua / chicken.lua)
local ANIMS = {
	villager = {
		stand = { 0, 0, 1, true }, shake = { 60, 70, 16, true }, walk = { 0, 40, 25, true },
	},
	chicken = {
		stand = { 0, 0, 1, true }, flap = { 20, 26, 30, true }, walk = { 0, 20, 25, true },
	},
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local V = vector.new
local pi = math.pi

local function now_s() return core.get_us_time() / 1e6 end

local function wrap(a)
	while a > pi do a = a - 2 * pi end
	while a < -pi do a = a + 2 * pi end
	return a
end

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function smooth(x) x = clamp(x, 0, 1); return x * x * (3 - 2 * x) end
local function lerp(a, b, t) return a + (b - a) * t end
local function lerp_angle(a, b, t) return a + wrap(b - a) * t end
local function face(dx, dz) return -math.atan2(dx, dz) end -- entity yaw (0 = +Z)

local function write_file(name, text)
	local f = io.open(WORLD .. "/" .. name, "wb")
	if not f then return false end
	f:write(text)
	f:close()
	return true
end

local function append_file(name, text)
	local f = io.open(WORLD .. "/" .. name, "ab")
	if not f then return end
	f:write(text)
	f:close()
end

local function file_exists(name)
	local f = io.open(WORLD .. "/" .. name, "rb")
	if f then f:close() return true end
	return false
end

local function slog(fmt, ...)
	local line = string.format(fmt, ...)
	core.log("action", "SKIT|" .. line)
	append_file("skit_events.log", line .. "\n")
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local S = {
	state = "boot",       -- boot > emerging > warm > ready > run > done
	join_s = nil,
	ground = nil,         -- y of top grass node
	surface = nil,        -- y of stage top surface
	t0_s = nil,
	built_s = nil,
	stage_nodes = {},
	tnt_pos = nil,
	tnt_center = nil,
	tnt_flash_on = false,
	actors = {},
	rot = nil,            -- measured rotation convention (cached once)
	fov_aspect = nil,
	last_slow = 0,
	frames_logged = {},
	events_fired = {},
	stage_checked = {},
	hud_removed = 0,
}

---------------------------------------------------------------------------
-- Rotation convention: measured ONCE, then cached (never per frame).
-- We set a few known angles, read back get_look_dir(), and derive
--   yaw_cmd   = yaw_dir * wrap(heading - a0)      heading = atan2(dx, dz)
--   pitch_cmd = (elevation - el0) * pitch_scale   elevation = asin(dy)
---------------------------------------------------------------------------
local function measure_rotation(player)
	local function dir_at(yaw, pitch)
		player:set_look_horizontal(yaw)
		player:set_look_vertical(pitch)
		return player:get_look_dir()
	end
	local d0 = dir_at(0, 0)
	local d1 = dir_at(pi / 2, 0)
	local d2 = dir_at(0, 0.5)
	local a0 = math.atan2(d0.x, d0.z)
	local a1 = math.atan2(d1.x, d1.z)
	local dA = wrap(a1 - a0)
	local el0 = math.asin(clamp(d0.y, -1, 1))
	local el2 = math.asin(clamp(d2.y, -1, 1))
	local rot = {
		a0 = a0,
		yaw_dir = (dA >= 0) and 1 or -1,
		el0 = el0,
		pitch_scale = 0.5 / (el2 - el0),
	}
	local ok_yaw = math.abs(math.abs(dA) - pi / 2) < 0.05
	local ok_pitch = math.abs(el2 - el0) > 0.1

	-- self-check with an arbitrary target direction
	local th, te = 0.7, -0.3
	player:set_look_horizontal(rot.yaw_dir * wrap(th - rot.a0))
	player:set_look_vertical((te - rot.el0) * rot.pitch_scale)
	local dv = player:get_look_dir()
	local eh = math.atan2(dv.x, dv.z)
	local ee = math.asin(clamp(dv.y, -1, 1))
	local err = math.max(math.abs(wrap(eh - th)), math.abs(ee - te))

	player:set_look_horizontal(0)
	player:set_look_vertical(0)

	local text = string.format(
		"yaw_dir=%d a0=%.5f el0=%.5f pitch_scale=%.5f self_check_err=%.5f ok=%s",
		rot.yaw_dir, rot.a0, rot.el0, rot.pitch_scale, err,
		tostring(ok_yaw and ok_pitch and err < 0.02))
	write_file("skit_rotconv", text .. "\n")
	slog("ROTCONV|%s", text)
	return rot
end

local function aim(player, c, l)
	local dx, dy, dz = l.x - c.x, l.y - c.y, l.z - c.z
	local n = math.sqrt(dx * dx + dy * dy + dz * dz)
	local h = math.atan2(dx, dz)
	local e = math.asin(dy / n)
	local r = S.rot
	player:set_look_horizontal(r.yaw_dir * wrap(h - r.a0))
	player:set_look_vertical((e - r.el0) * r.pitch_scale)
end

---------------------------------------------------------------------------
-- Camera
---------------------------------------------------------------------------
local function cam_rel(T)
	if T <= KEYS[1].t then return KEYS[1] end
	for i = 1, #KEYS - 1 do
		local a, b = KEYS[i], KEYS[i + 1]
		if T <= b.t then
			local k = smooth((T - a.t) / (b.t - a.t))
			return { x = lerp(a.x, b.x, k), y = lerp(a.y, b.y, k), z = lerp(a.z, b.z, k) }
		end
	end
	return KEYS[#KEYS]
end

-- camera world position (without shake) for timeline time T
local function cam_world(T)
	local k = cam_rel(T)
	local c = V(k.x, S.surface + k.y, k.z)
	-- explosion shake: decaying, deterministic, applied to position only
	local dt = T - CFG.t_explosion
	if dt >= 0 then
		local amp = 0.10 * math.exp(-dt * 3.2)
		c.x = c.x + amp * math.sin(dt * 53)
		c.y = c.y + amp * 0.7 * math.sin(dt * 67 + 1.3)
	end
	return c
end

local function look_world() return V(LOOK.x, S.surface + LOOK.y, LOOK.z) end

-- projection of world point p to screen: returns u in [-1,1] (right),
-- v_from_top in [0,1]
local function project(c, l, p, aspect)
	local ty = math.tan(math.rad(CFG.fov_y_deg) / 2)
	local tx = ty * aspect
	local fx, fy, fz = l.x - c.x, l.y - c.y, l.z - c.z
	local fn = math.sqrt(fx * fx + fy * fy + fz * fz)
	fx, fy, fz = fx / fn, fy / fn, fz / fn
	local rx, rz = fz, -fx
	local rn = math.sqrt(rx * rx + rz * rz)
	rx, rz = rx / rn, rz / rn
	local ux = fy * rz
	local uy = fz * rx - fx * rz
	local uz = -fy * rx
	if uy < 0 then ux, uy, uz = -ux, -uy, -uz end
	local dx, dy, dz = p.x - c.x, p.y - c.y, p.z - c.z
	local z = dx * fx + dy * fy + dz * fz
	local x = dx * rx + dz * rz
	local y = dx * ux + dy * uy + dz * uz
	return x / z / tx, (1 - (y / z / ty)) / 2, z
end

local function window_aspect(player)
	local info = core.get_player_window_information(player:get_player_name())
	if info and info.size and info.size.x and info.size.y and info.size.y > 0 then
		return info.size.x / info.size.y, info.size.x, info.size.y
	end
	return CFG.aspect_fb
end

-- Luanti scales the vertical FOV for narrow windows:
--   fov_y = fov * clamp(sqrt(1.6 / aspect), 1.0, 1.4)   (camera.cpp, >= 5.9)
local function ensure_fov(player)
	local aspect, w, h = window_aspect(player)
	if S.fov_aspect and math.abs(S.fov_aspect - aspect) < 1e-4 then return end
	local scale = clamp(math.sqrt(1.6 / aspect), 1.0, 1.4)
	local fov = CFG.fov_y_deg / scale
	player:set_fov(fov, false, 0)
	S.fov_aspect = aspect
	slog("FOV|aspect=%.4f window=%s fov_setting=%.3f fov_y=%.2f",
		aspect, w and (w .. "x" .. h) or "unknown(fallback)", fov, CFG.fov_y_deg)
end

---------------------------------------------------------------------------
-- HUD: remove everything, every step, without pcall.
---------------------------------------------------------------------------
local HUD_OFF = {
	hotbar = false, healthbar = false, crosshair = false, wielditem = false,
	breathbar = false, minimap = false, minimap_radar = false,
	basic_debug = false, chat = false,
}

-- VoxeLibre's vl_hudbars keeps its own hud ids and calls hud_get() on them,
-- so ripping its elements out with hud_remove crashes the server. Remove the
-- hudbars through their own API first (guarded, outside any hud_get_all loop).
-- vl_hudbars owns its hud ids and calls hud_get() on them, so those ids must
-- never be hud_remove()d (that crashes the server). We collect them, hide the
-- bars through the mod's own API, and leave the layers alone.
local function collect_hudbar_ids(player, owned)
	local name = player:get_player_name()
	if not (vl_hudbars and vl_hudbars.players and vl_hudbars.players[name]
			and vl_hudbars.hudbar_defs) then
		return
	end
	local states = vl_hudbars.players[name].hudbar_states or {}
	for identifier, def in pairs(vl_hudbars.hudbar_defs) do
		local st = states[identifier]
		if st then
			if def.is_compound then
				for _, part in pairs(st.parts or {}) do
					for _, id in pairs(part.layer_ids or {}) do owned[id] = true end
				end
			else
				for _, id in pairs(st.layer_ids or {}) do owned[id] = true end
			end
		end
	end
end

local function hide_hudbar(player, identifier)
	if vl_hudbars.has_hudbar(player, identifier) then
		vl_hudbars.hide(player, identifier)
	end
end

local hudbar_skip = {}
local function hide_hudbars(player)
	local name = player:get_player_name()
	if not (vl_hudbars and vl_hudbars.players and vl_hudbars.players[name]
			and vl_hudbars.hudbar_defs) then
		return
	end
	for identifier, _ in pairs(vl_hudbars.hudbar_defs) do
		if not hudbar_skip[identifier] then
			local ok, err = pcall(hide_hudbar, player, identifier)
			if not ok then
				hudbar_skip[identifier] = true
				slog("HUDBAR_WARN|%s|%s", identifier, tostring(err))
			end
		end
	end
end

local function strip_hud(player)
	local owned = {}
	collect_hudbar_ids(player, owned)
	hide_hudbars(player)
	-- everything else: plain loop, no pcall inside it
	local all = player:hud_get_all()
	for id, _ in pairs(all) do
		if not owned[id] then
			player:hud_remove(id)
			S.hud_removed = S.hud_removed + 1
		end
	end
end

local function enforce_hud_flags(player)
	local f = player:hud_get_flags()
	local dirty = false
	for k, v in pairs(HUD_OFF) do
		if f[k] ~= nil and f[k] ~= v then dirty = true end
	end
	if dirty then player:hud_set_flags(HUD_OFF) end
end

---------------------------------------------------------------------------
-- Stage
---------------------------------------------------------------------------
local function put(pos, name)
	core.set_node(pos, { name = name })
	S.stage_nodes[#S.stage_nodes + 1] = { pos = pos, name = name }
end

local function find_ground()
	for y = 30, -10, -1 do
		local n = core.get_node(V(0, y, 0)).name
		if n ~= "air" and n ~= "ignore" then return y end
	end
	return 8
end

local function build_stage()
	local G = find_ground()
	S.ground = G
	S.surface = G + 2.5
	-- two layers of 5x5 planks
	for x = -2, 2 do
		for z = -2, 2 do
			put(V(x, G + 1, z), "mcl_core:darkwood")
			put(V(x, G + 2, z), "mcl_core:wood")
		end
	end
	-- backdrop: three blocks tall above the stage surface, standing on the ground
	for x = -4, 4 do
		for y = G + 1, G + 5 do
			put(V(x, y, 3), (y <= G + 2) and "mcl_core:darkwood" or "mcl_wool:blue")
		end
	end
	-- TNT (not part of the "must stay standing" list)
	S.tnt_pos = V(0, G + 3, CFG.tnt_z)
	S.tnt_center = V(0, G + 3, CFG.tnt_z)
	core.set_node(S.tnt_pos, { name = "mcl_tnt:tnt" })
	slog("STAGE|ground=%d surface=%.1f nodes=%d tnt=%s",
		G, S.surface, #S.stage_nodes, core.pos_to_string(S.tnt_pos))
end

local function check_stage(label)
	local bad = 0
	for _, e in ipairs(S.stage_nodes) do
		if core.get_node(e.pos).name ~= e.name then
			bad = bad + 1
			core.set_node(e.pos, { name = e.name }) -- repair so the shot stays intact
		end
	end
	slog("STAGE_CHECK|%s|total=%d damaged=%d %s", label, #S.stage_nodes, bad,
		bad == 0 and "STAGE_OK" or "STAGE_DAMAGED_REPAIRED")
end

---------------------------------------------------------------------------
-- Actors
---------------------------------------------------------------------------
local function spawn_actor(kind, mobname, pos)
	local obj = core.add_entity(pos, mobname) -- returns an ObjectRef, not the entity table
	assert(obj, "skit: add_entity failed for " .. mobname)
	local ent = obj:get_luaentity()
	assert(ent, "skit: no luaentity for " .. mobname)
	obj:set_properties({
		physical = false, collide_with_objects = false,
		automatic_face_movement_dir = false, pointable = false,
		static_save = false,
	})
	obj:set_armor_groups({ immortal = 1 })
	obj:set_velocity(V(0, 0, 0))
	obj:set_acceleration(V(0, 0, 0))
	ent._skit = true
	-- freeze the whole mob AI: our own on_step replaces it
	ent.on_step = function() end
	ent.damage_mob = function() end
	ent.deal_damage = function() end
	ent.on_punch = function() return true end
	ent.on_rightclick = function() end
	ent.state = "stand"
	local a = { kind = kind, obj = obj, cur_anim = nil }
	slog("ACTOR|%s spawned at %s", mobname, core.pos_to_string(pos))
	return a
end

local function set_anim(a, key)
	if a.cur_anim == key then return end
	a.cur_anim = key
	local r = ANIMS[a.kind][key]
	a.obj:set_animation({ x = r[1], y = r[2] }, r[3], 0, r[4])
end

local function place(a, x, y, z, yaw)
	a.obj:set_pos(V(x, S.surface + y, z))
	a.obj:set_yaw(yaw)
end

-- Timeline poses ----------------------------------------------------------
local FACE_CAM = pi
local function villager_pose(T)
	local vx = CFG.villager_x
	local to_tnt = face(0 - vx, CFG.tnt_z)
	local yaw, y, x, anim = FACE_CAM, 0, vx, "stand"
	if T >= 1.2 and T < 1.9 then
		yaw = lerp_angle(FACE_CAM, to_tnt, smooth((T - 1.2) / 0.7))
	elseif T >= 1.9 and T < CFG.t_explosion then
		yaw = to_tnt
	elseif T >= CFG.t_explosion then
		yaw = lerp_angle(to_tnt, FACE_CAM, smooth((T - CFG.t_explosion) / 0.6))
	end
	if T >= 2.4 and T < 4.4 then anim = "shake" end
	if T >= 4.4 and T < CFG.t_explosion then x = vx + 0.015 * math.sin(T * 60) end
	local u = T - CFG.t_explosion
	if u >= 0 and u < 0.48 then y = 0.45 * math.sin(pi * u / 0.48) end
	local land = CFG.t_explosion + CFG.chicken_launch_s
	local w = T - land
	if w >= 0 and w < 0.30 then y = -0.16 * math.sin(pi * w / 0.30) end
	if T >= land + 0.5 then anim = "shake" end
	return x, y, 0, yaw, anim
end

local function chicken_pose(T, vill_y)
	local cx = CFG.chicken_x
	local to_tnt = face(0 - cx, CFG.tnt_z)
	local yaw, y, x, anim = FACE_CAM, 0, cx, "stand"
	local land = CFG.t_explosion + CFG.chicken_launch_s
	if T >= 1.2 and T < 1.9 then
		yaw = lerp_angle(FACE_CAM, to_tnt, smooth((T - 1.2) / 0.7))
	elseif T >= 1.9 and T < CFG.t_explosion then
		yaw = to_tnt
	end
	if T >= 3.0 and T < CFG.t_explosion then
		y = 0.10 * math.abs(math.sin(T * 7))
		if y > 0.01 then anim = "flap" end
	end
	if T >= CFG.t_explosion and T < land then
		local s = (T - CFG.t_explosion) / CFG.chicken_launch_s
		x = lerp(cx, CFG.villager_x, s)
		y = CFG.villager_h * s + 4 * CFG.chicken_apex * s * (1 - s)
		yaw = lerp(to_tnt, FACE_CAM + 4 * pi, s)
		anim = "flap"
	elseif T >= land then
		x = CFG.villager_x
		y = vill_y + CFG.villager_h
		yaw = FACE_CAM
		anim = (T < land + 0.6) and "flap" or "stand"
	end
	return x, y, 0, yaw, anim
end

local function update_actors(T)
	local v, c = S.actors.villager, S.actors.chicken
	if not (v and c) then return end
	local vx, vy, vz, vyaw, vanim = villager_pose(T)
	place(v, vx, vy, vz, vyaw)
	set_anim(v, vanim)
	local cx, cy, cz, cyaw, canim = chicken_pose(T, vy)
	place(c, cx, cy, cz, cyaw)
	set_anim(c, canim)
	return { vx = vx, vy = vy, cx = cx, cy = cy }
end

---------------------------------------------------------------------------
-- TNT flashing + explosion
---------------------------------------------------------------------------
local FLASH_START = 2.6
local function update_tnt_flash(T)
	if T < FLASH_START or T >= CFG.t_explosion then return end
	local d = T - FLASH_START
	local phase = 2 * d + 0.8 * d * d
	local on = (math.floor(phase * 2) % 2) == 1
	if on ~= S.tnt_flash_on then
		S.tnt_flash_on = on
		core.swap_node(S.tnt_pos, { name = on and "mcl_wool:white" or "mcl_tnt:tnt" })
	end
end

local function explode()
	local p = S.tnt_center
	core.remove_node(S.tnt_pos)
	-- griefing=false: block-safe, so the stage is guaranteed to stay standing,
	-- but entities/particles/sound still behave like a real explosion.
	mcl_explosions.explode(p, CFG.strength, {
		griefing = false, drop_chance = 0, fire = false,
		particles = true, sound = true,
	})
	core.add_particlespawner({
		amount = 70, time = 0.12, minpos = p, maxpos = p,
		minvel = V(-3.5, 0.5, -3.5), maxvel = V(3.5, 4.5, 3.5),
		minacc = V(0, 0, 0), maxacc = V(0, 0, 0),
		minexptime = 0.4, maxexptime = 0.9, minsize = 2.0, maxsize = 4.5,
		texture = "mcl_particles_flame.png", glow = 14,
	})
	core.add_particlespawner({
		amount = 40, time = 0.1, minpos = p, maxpos = p,
		minvel = V(-5, 1, -5), maxvel = V(5, 6, 5),
		minacc = V(0, -9, 0), maxacc = V(0, -9, 0),
		minexptime = 0.7, maxexptime = 1.3, minsize = 0.5, maxsize = 0.9,
		node = { name = "mcl_core:wood" }, texture = "mcl_particles_smoke.png",
	})
	slog("EXPLOSION|strength=%.2f pos=%s", CFG.strength, core.pos_to_string(p))
end

---------------------------------------------------------------------------
-- Framing report (logged; CI asserts on it)
---------------------------------------------------------------------------
local FRAME_TIMES = { 0.0, 3.0, 5.0, 5.6, 6.36, 6.85, 7.5, 10.5 }

local function report_frame(player, T, poses)
	local aspect = S.fov_aspect or CFG.aspect_fb
	local c, l = cam_world(T), look_world()
	local vh, vhv = project(c, l, V(poses.vx, S.surface + poses.vy + CFG.villager_h, 0), aspect)
	local cu, cv = project(c, l, V(poses.cx, S.surface + poses.cy + 0.7, 0), aspect)
	local _, fv = project(c, l, V(0, S.surface, -2.5), aspect) -- stage front edge
	local dist = math.sqrt((l.x - c.x) ^ 2 + (l.y - c.y) ^ 2 + (l.z - c.z) ^ 2)
	local d = player:get_look_dir()
	local want = vector.normalize(vector.subtract(l, c))
	local err = math.acos(clamp(d.x * want.x + d.y * want.y + d.z * want.z, -1, 1))
	local ok = (vhv <= 0.36) and (math.abs(vh) < 0.95) and (math.abs(cu) < 0.95)
		and (cv > 0.01) and (fv > 0.6) and (dist >= 6.0 and dist <= 7.0)
	slog("FRAME|T=%.2f|vill_head_u=%.2f vill_head_v=%.2f|chick_u=%.2f chick_v=%.2f|stage_edge_v=%.2f|dist=%.2f|look_err=%.4f|ok=%s",
		T, vh, vhv, cu, cv, fv, dist, err, tostring(ok))
end

---------------------------------------------------------------------------
-- Timeline events
---------------------------------------------------------------------------
local EVENTS = {
	{ t = 1.2,  name = "actors_turn_to_tnt" },
	{ t = FLASH_START, name = "tnt_flash_start" },
	{ t = CFG.t_explosion, name = "explosion", fn = explode },
	{ t = CFG.t_explosion + CFG.chicken_launch_s * 0.66, name = "chicken_apex" },
	{ t = CFG.t_explosion + CFG.chicken_launch_s, name = "chicken_lands_on_villager" },
	{ t = CFG.t_explosion + CFG.chicken_launch_s + 0.5, name = "villager_dismay" },
	{ t = CFG.duration, name = "skit_end" },
}

local function run_events(T)
	for i, e in ipairs(EVENTS) do
		if not S.events_fired[i] and T >= e.t then
			S.events_fired[i] = true
			if e.fn then e.fn() end
			slog("EVENT|%s|target=%.3f|actual=%.3f", e.name, e.t, T)
		end
	end
	if T >= CFG.t_explosion + 0.5 and not S.stage_checked.after then
		S.stage_checked.after = true
		check_stage("after_explosion")
	end
end

---------------------------------------------------------------------------
-- Boot sequence
---------------------------------------------------------------------------
local function cleanup_foreign()
	local c = V(0, S.surface or 10, 0)
	for _, obj in ipairs(core.get_objects_inside_radius(c, 90)) do
		if not obj:is_player() then
			local ent = obj:get_luaentity()
			if ent and not ent._skit and (ent.is_mob or ent.name == "__builtin:item") then
				obj:remove()
			end
		end
	end
end

local function begin_emerge()
	S.state = "emerging"
	local done = false
	core.emerge_area(V(-72, -8, -72), V(72, 40, 72), function(_, _, remaining)
		if remaining == 0 then done = true end
	end)
	S.emerge_done = function() return done end
	S.emerge_start = now_s()
end

core.register_on_joinplayer(function(player)
	S.join_s = now_s()
	player:set_armor_groups({ immortal = 1 })
	player:set_nametag_attributes({ text = " ", color = { a = 0, r = 0, g = 0, b = 0 } })
	player:set_physics_override({ gravity = 0, speed = 0, jump = 0 })
	player:set_pos(V(0, 30, -6.6))
	player:set_hp(20)
	core.set_timeofday(0.5)
	begin_emerge()
	slog("JOIN|%s", player:get_player_name())
end)

local step_errors = {}
local function step(player, dtime)
	local t = now_s()

	-- slow housekeeping (twice a second)
	if t - S.last_slow >= 0.5 then
		S.last_slow = t
		enforce_hud_flags(player)
		ensure_fov(player)
		if S.surface then cleanup_foreign() end
		core.set_timeofday(0.5)
		if mcl_weather and mcl_weather.state and mcl_weather.state ~= "none" then
			mcl_weather.change_weather("none")
		end
	end

	-- state machine
	if S.state == "emerging" then
		if S.emerge_done() or (t - S.emerge_start) > 25 then
			build_stage()
			cleanup_foreign()
			S.actors.villager = spawn_actor("villager", "mobs_mc:villager",
				V(CFG.villager_x, S.surface, 0))
			S.actors.chicken = spawn_actor("chicken", "mobs_mc:chicken",
				V(CFG.chicken_x, S.surface, 0))
			ensure_fov(player)
			S.rot = measure_rotation(player) -- once
			S.built_s = t
			S.state = "warm"
			check_stage("before")
		end
		return
	end

	if not S.rot then return end

	-- timeline time
	local T = 0
	if S.state == "run" or S.state == "done" then
		T = t - S.t0_s
	end
	if S.state == "done" then T = CFG.duration end

	-- scene + camera (every step)
	local poses = update_actors(T)
	update_tnt_flash(T)
	local c, l = cam_world(T), look_world()
	local eye = (player:get_properties().eye_height or 1.625)
	local eo = player:get_eye_offset()
	local feet = V(c.x - eo.x / 10, c.y - eye - eo.y / 10, c.z - eo.z / 10)
	player:set_pos(feet)
	aim(player, c, l)

	if S.state == "warm" then
		if t - S.built_s >= CFG.warmup then
			write_file("skit_ready", string.format("ready %.3f\n", t))
			slog("READY|waiting for skit_go")
			S.state = "ready"
		end
	elseif S.state == "ready" then
		if file_exists("skit_go") then
			S.t0_s = now_s()
			write_file("skit_t0", string.format("t0 os_time=%d us=%d\n", os.time(), core.get_us_time()))
			slog("T0|marker written; hud_removed_total=%d", S.hud_removed)
			S.state = "run"
		end
	elseif S.state == "run" then
		run_events(T)
		for i, ft in ipairs(FRAME_TIMES) do
			if not S.frames_logged[i] and T >= ft then
				S.frames_logged[i] = true
				report_frame(player, T, poses)
			end
		end
		if T >= CFG.duration then
			S.state = "done"
			check_stage("end")
			write_file("skit_done", string.format("done T=%.3f hud_removed=%d\n", T, S.hud_removed))
		end
	end
end

core.register_globalstep(function(dtime)
	local player = core.get_connected_players()[1]
	if not player then return end
	strip_hud(player) -- HUD: every step
	local ok, err = pcall(step, player, dtime)
	if not ok then
		local msg = tostring(err)
		if not step_errors[msg] then
			step_errors[msg] = true
			slog("STEP_ERROR|%s", msg)
		end
	end
end)

slog("LOADED|skit mod, strength=%.2f t_explosion=%.2f", CFG.strength, CFG.t_explosion)
