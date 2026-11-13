-- Stage construction: 5x5 two-layer wooden stage + 3-block-high backdrop.
local C = skit.cfg
local S = {}

local INDESTRUCTIBLE = 1000000  -- mcl_explosions treats >= 1e6 as indestructible

local STAGE_LOWER = { "mcl_core:sprucewood", "mcl_core:wood", "default:wood" }
local STAGE_UPPER = { "mcl_core:wood", "mcl_core:sprucewood", "default:wood" }
local CURTAIN     = { "mcl_wool:red", "wool:red", "mcl_core:brick_block" }
local VALANCE     = { "mcl_wool:yellow", "wool:yellow", "mcl_core:goldblock" }
local GRASS       = { "mcl_core:dirt_with_grass", "default:dirt_with_grass" }
local DIRT        = { "mcl_core:dirt", "default:dirt" }

local function first_registered(list)
  for _, n in ipairs(list) do
    if core.registered_nodes[n] then return n end
  end
  return "mcl_core:stone"
end

-- Stage materials never get destroyed by the blast (brief: the stage stays standing).
-- Must run at load time, before mcl_explosions caches blast resistances.
function S.protect()
  local names = {
    first_registered(STAGE_LOWER), first_registered(STAGE_UPPER),
    first_registered(CURTAIN), first_registered(VALANCE),
  }
  S.materials = { lower = names[1], upper = names[2], curtain = names[3], valance = names[4] }
  for _, name in ipairs(names) do
    core.override_item(name, { _mcl_blast_resistance = INDESTRUCTIBLE })
  end
end

-- Topmost walkable node at the world origin column.
function S.find_ground()
  for y = 60, -16, -1 do
    local n = core.get_node_or_nil({ x = 0, y = y, z = 0 })
    if n then
      local def = core.registered_nodes[n.name]
      if def and def.walkable then return y end
    end
  end
  return nil
end

-- Builds everything. GY = y of the ground (grass) layer. Returns list of stage nodes.
function S.build(GY)
  local m = S.materials
  local x1, x2, z1, z2 = -16, 16, -14, 12
  local p1 = { x = x1, y = GY - 3, z = z1 }
  local p2 = { x = x2, y = GY + 16, z = z2 }

  local vm = core.get_voxel_manip()
  local emin, emax = vm:read_from_map(p1, p2)
  local area = VoxelArea:new({ MinEdge = emin, MaxEdge = emax })
  local data = vm:get_data()

  local c_air   = core.CONTENT_AIR
  local c_grass = core.get_content_id(first_registered(GRASS))
  local c_dirt  = core.get_content_id(first_registered(DIRT))
  local c_lower = core.get_content_id(m.lower)
  local c_upper = core.get_content_id(m.upper)
  local c_curt  = core.get_content_id(m.curtain)
  local c_valn  = core.get_content_id(m.valance)

  -- 1) clear the working volume and lay a flat grass floor (no trees, flowers, edges)
  for z = z1, z2 do
    for y = GY - 3, GY + 16 do
      for x = x1, x2 do
        local i = area:index(x, y, z)
        if y > GY then
          data[i] = c_air
        elseif y == GY then
          data[i] = c_grass
        elseif data[i] == c_air or data[i] == core.CONTENT_IGNORE then
          data[i] = c_dirt
        end
      end
    end
  end

  local nodes = {}
  local function put(x, y, z, cid, name)
    data[area:index(x, y, z)] = cid
    nodes[#nodes + 1] = { pos = { x = x, y = y, z = z }, name = name }
  end

  -- 2) stage: 5x5, two layers
  local h = C.STAGE_HALF
  for z = -h, h do
    for x = -h, h do
      put(x, GY + 1, z, c_lower, m.lower)
      put(x, GY + 2, z, c_upper, m.upper)
    end
  end

  -- 3) backdrop: 3 blocks tall, directly behind the stage (z = +3), wide enough that
  --    its side edges are never inside the portrait frame.
  for x = -7, 7 do
    for y = GY + 3, GY + 5 do
      if y == GY + 5 then
        put(x, y, h + 1, c_valn, m.valance)
      else
        put(x, y, h + 1, c_curt, m.curtain)
      end
    end
  end

  vm:set_data(data)
  vm:write_to_map(true)       -- true = recalculate lighting
  core.fix_light(p1, p2)

  S.nodes = nodes
  return nodes
end

-- Count (and optionally repair) missing stage nodes.
function S.verify(repair)
  local missing = 0
  for _, e in ipairs(S.nodes or {}) do
    local n = core.get_node(e.pos)
    if n.name ~= e.name then
      missing = missing + 1
      if repair then core.set_node(e.pos, { name = e.name }) end
    end
  end
  return missing
end

-- Remove stray objects (naturally spawned mobs, drops...) from the filming area.
function S.sweep()
  local centre = { x = 0, y = skit.YS or 10, z = 0 }
  for _, obj in ipairs(core.get_objects_inside_radius(centre, 80)) do
    if not obj:is_player() then
      local ent = obj:get_luaentity()
      if not (ent and (ent._skit_keep or ent.name == "skit:cam")) then
        obj:remove()
      end
    end
  end
end

return S
