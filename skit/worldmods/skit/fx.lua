-- Particle effects: fuse sparks, appear-poof, explosion fireball/smoke/debris.
local C = skit.cfg
local F = {}

local TEX_FLAME = "mcl_particles_flame.png"
local TEX_SMOKE  = "[fill:2x2:#8d8d8d"   -- blocky grey puffs (the stock smoke texture is a huge ring)
local TEX_SMOKE2 = "[fill:2x2:#3c3c3c"
local TEX_FLASH = "[fill:2x2:#fff3c4"
local TEX_WOOD  = "default_wood.png"

local function v(x, y, z) return { x = x, y = y, z = z } end

function F.fuse(pos, duration)
  local top = v(pos.x, pos.y + 0.55, pos.z)
  core.add_particlespawner({
    amount = math.floor(duration * 45), time = duration,
    minpos = v(top.x - 0.05, top.y, top.z - 0.05), maxpos = v(top.x + 0.05, top.y + 0.05, top.z + 0.05),
    minvel = v(-0.7, 1.2, -0.7), maxvel = v(0.7, 2.6, 0.7),
    minacc = v(0, -1, 0), maxacc = v(0, -1, 0),
    minexptime = 0.25, maxexptime = 0.6,
    minsize = 0.5, maxsize = 1.1,
    texture = TEX_FLAME, glow = 14,
  })
  core.add_particlespawner({
    amount = math.floor(duration * 14), time = duration,
    minpos = top, maxpos = v(top.x, top.y + 0.1, top.z),
    minvel = v(-0.3, 0.6, -0.3), maxvel = v(0.3, 1.2, 0.3),
    minexptime = 0.6, maxexptime = 1.3,
    minsize = 0.25, maxsize = 0.5,
    texture = TEX_SMOKE,
  })
end

function F.poof(pos)
  core.add_particlespawner({
    amount = 18, time = 0.1,
    minpos = v(pos.x - 0.5, pos.y - 0.45, pos.z - 0.5), maxpos = v(pos.x + 0.5, pos.y - 0.3, pos.z + 0.5),
    minvel = v(-1.2, 0.2, -1.2), maxvel = v(1.2, 1.0, 1.2),
    minexptime = 0.4, maxexptime = 0.9,
    minsize = 0.5, maxsize = 1.0,
    texture = TEX_SMOKE,
  })
end

-- Short bright pulses just before the blast (TNT "about to blow").
function F.pulse(pos)
  core.add_particle({
    pos = pos, velocity = v(0, 0, 0), expirationtime = 0.09,
    size = 2.4, texture = TEX_FLASH, glow = 14,
  })
end

function F.boom(pos)
  -- white-hot core flash
  core.add_particle({
    pos = pos, velocity = v(0, 0, 0), expirationtime = 0.16,
    size = 3.6, texture = TEX_FLASH, glow = 14,
  })
  -- fireball
  core.add_particlespawner({
    amount = 80, time = 0.12,
    minpos = v(pos.x - 0.4, pos.y - 0.3, pos.z - 0.4), maxpos = v(pos.x + 0.4, pos.y + 0.4, pos.z + 0.4),
    minvel = v(-5, 0.5, -5), maxvel = v(5, 6, 5),
    minacc = v(0, -2, 0), maxacc = v(0, -2, 0),
    minexptime = 0.25, maxexptime = 0.7,
    minsize = 2.2, maxsize = 4.6,
    texture = TEX_FLAME, glow = 14,
  })
  -- lingering smoke: blocky grey + dark puffs (kept small so the actors stay readable)
  for i, tex in ipairs({ TEX_SMOKE, TEX_SMOKE2 }) do
    core.add_particlespawner({
      amount = 34, time = 0.6,
      minpos = v(pos.x - 0.6, pos.y - 0.2, pos.z - 0.6), maxpos = v(pos.x + 0.6, pos.y + 0.6, pos.z + 0.6),
      minvel = v(-2.0, 0.4, -2.0), maxvel = v(2.0, 3.0, 2.0),
      minacc = v(0, 0.3, 0), maxacc = v(0, 0.6, 0),
      minexptime = 1.0, maxexptime = 2.4,
      minsize = 0.6 + 0.1 * i, maxsize = 1.5,
      texture = tex,
    })
  end
  -- splinters of the "set" flying around (stage itself stays intact)
  core.add_particlespawner({
    amount = 26, time = 0.08,
    minpos = pos, maxpos = pos,
    minvel = v(-4, 3, -4), maxvel = v(4, 8, 4),
    minacc = v(0, -14, 0), maxacc = v(0, -14, 0),
    minexptime = 0.7, maxexptime = 1.3,
    minsize = 0.35, maxsize = 0.8,
    texture = TEX_WOOD,
  })
end

return F
