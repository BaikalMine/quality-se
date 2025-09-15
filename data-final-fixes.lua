-- Final fixes: keep SE progression & clamp edge-case energies
if mods["space-exploration"] then
  local deny = {
    "arcosphere",
    "basic-matter-conversion","basic-matter-deconversion",
    "kr-matter-conversion","kr-matter-deconversion",
    "antimatter",
    "core-fragment-processing",
    "rocket","rocket-building","rocket-deploying",
    "space-accelerator","space-astrometrics","space-biochemical","space-collider","space-crafting",
    "space-electromagnetics","space-electromagnetics-laser","space-electromagnetics-particle",
    "space-entropy","space-gravimetrics","space-hypercooling","space-laser","space-lifesupport",
    "space-materials","space-mechanical","space-neural",
    "space-observation-acoustic","space-observation-astronomic","space-observation-deep",
    "space-observation-gammaray","space-observation-infrared","space-observation-microwave",
    "space-observation-neutrino","space-observation-uv","space-observation-visible","space-observation-xray",
    "space-plasma","space-radiation","space-radiator","space-spectrometry",
    "space-supercomputing-1","space-supercomputing-2","space-supercomputing-3","space-supercomputing-4",
    "space-thermodynamics",
    "spaceship-antimatter-engine","spaceship-ion-engine","spaceship-rocket-engine"
  }

  local function in_deny(cat)
    for _, d in pairs(deny) do
      if cat == d then return true end
    end
    return false
  end

  -- Disable quality only on denylisted categories
  for _, r in pairs(data.raw.recipe) do
    local cat = r.category or "crafting"
    if in_deny(cat) then
      r.allow_quality = false
      if r.normal then r.normal.allow_quality = false end
      if r.expensive then r.expensive.allow_quality = false end
    end
  end

  -- Clamp tiny energy for recycling-ish recipes to avoid engine error <= 0.001
  local function clamp_energy(recipe)
    if not recipe then return end
    local er = recipe.energy_required
    if er and er <= 0.001 then recipe.energy_required = 0.002 end
  end
  for _, r in pairs(data.raw.recipe) do
    local cat = r.category
    if (cat == "hard-recycling") or (cat == "hand-hard-recycling") or
       (cat == "recycling") or (cat == "recycling-or-hand-crafting") or
       (type(r.name)=="string" and string.find(r.name, "recycling", 1, true)) then
      clamp_energy(r)
      if r.normal then clamp_energy(r.normal) end
      if r.expensive then clamp_energy(r.expensive) end
    end
  end
end

-- Sanitizer (final stage): remove recycling recipes that reference items removed by other mods (SE, K2, etc.)
do
  local item_types = {
    "item", "module", "tool", "armor", "gun", "ammo", "capsule",
    "item-with-entity-data", "item-with-label", "item-with-tags",
    "selection-tool", "blueprint", "deconstruction-planner", "upgrade-planner",
    "item-with-inventory", "rail-planner", "spidertron-remote",
    "repair-tool", "mining-tool", "armor", "fluid"
  }
  local function item_exists(name)
    if not name then return false end
    for _, t in pairs(item_types) do
      if data.raw[t] and data.raw[t][name] then return true end
    end
    return false
  end
  local function ingredient_or_result_missing(proto_list, main_name, result_name)
    if proto_list then
      for _, pr in pairs(proto_list) do
        if type(pr) == "table" then
          local n = pr.name or pr[1]
          if n and not item_exists(n) then return true end
        end
      end
      return false
    else
      local n = main_name or result_name
      if n and not item_exists(n) then return true end
      return false
    end
  end

  local removed = 0
  for name, r in pairs(data.raw.recipe) do
    local cat = r.category
    local is_recycle = (name and string.find(name, "recycling", 1, true)) or
                       (cat == "recycling") or (cat == "recycling-or-hand-crafting") or
                       (cat == "hard-recycling") or (cat == "hand-hard-recycling")
    if is_recycle then
      local miss = ingredient_or_result_missing(r.ingredients, r.main_product, r.result)
                or ingredient_or_result_missing(r.results)
      if not miss and r.normal then
        miss = ingredient_or_result_missing(r.normal.ingredients, r.normal.main_product, r.normal.result)
            or ingredient_or_result_missing(r.normal.results)
      end
      if not miss and r.expensive then
        miss = ingredient_or_result_missing(r.expensive.ingredients, r.expensive.main_product, r.expensive.result)
            or ingredient_or_result_missing(r.expensive.results)
      end
      if miss then
        data.raw.recipe[name] = nil
        removed = removed + 1
      end
    end
  end
  log("quality-se final sanitizer removed "..removed.." invalid recycling recipes")
end

-- Fixup: forbid SE core fragments as recycling targets; fallback to self-recycle with chance
if mods["space-exploration"] then
  local function has_core_fragment_result(recipe)
    local function any_frag(list)
      if not list then return false end
      for _, r in pairs(list) do
        local n = (type(r)=="table") and (r.name or r[1]) or nil
        if n and string.find(n, "^se%-core%-fragment") then
          return true
        end
      end
      return false
    end
    return any_frag(recipe.results)
  end

  -- Correct self-recycle writer (with required 'type' field for Factorio 2.0)
  local function rewrite_to_self_recycle(r, prob)
    -- determine input item/fluid name
    local function get_name(list)
      if not list then return nil end
      for _, ing in pairs(list) do
        local n = (type(ing)=="table") and (ing.name or ing[1]) or nil
        if n then return n end
      end
      return nil
    end
    local in_name = get_name(r.ingredients)
      or (r.normal and get_name(r.normal.ingredients))
      or (r.expensive and get_name(r.expensive.ingredients))
    if not in_name then return end

    local out_type = (data.raw.fluid and data.raw.fluid[in_name]) and "fluid" or "item"
    local function mk_res()
      return { type = out_type, name = in_name, amount = 1, probability = prob }
    end

    r.results = { mk_res() }
    r.result = nil; r.result_count = nil; r.main_product = in_name
    if r.normal then
      r.normal.results = { mk_res() }
      r.normal.result = nil; r.normal.result_count = nil; r.normal.main_product = in_name
    end
    if r.expensive then
      r.expensive.results = { mk_res() }
      r.expensive.result = nil; r.expensive.result_count = nil; r.expensive.main_product = in_name
    end
  end

  local SELF_RECYCLE_PROB = 0.5  -- можно настроить (0.35–0.6)

  for _, r in pairs(data.raw.recipe) do
    local is_recycling_cat =
      (r.category == "recycling") or (r.category == "recycling-or-hand-crafting") or
      (r.category == "hard-recycling") or (r.category == "hand-hard-recycling") or
      (type(r.name)=="string" and string.find(r.name, "recycling", 1, true))

    if is_recycling_cat then
      local got_frag = has_core_fragment_result(r)
      if (not got_frag) and r.normal then got_frag = has_core_fragment_result(r.normal) end
      if (not got_frag) and r.expensive then got_frag = has_core_fragment_result(r.expensive) end
      if got_frag then
        rewrite_to_self_recycle(r, SELF_RECYCLE_PROB)
      end
    end
  end
end

-- Always allow "quality" on SE space machines
if mods["space-exploration"] then
  local function add_effect(entity_type, name, effect)
    local proto = data.raw[entity_type] and data.raw[entity_type][name]
    if not proto then return end

    local effs = proto.allowed_effects
    if not effs then
      effs = {}
      proto.allowed_effects = effs
    end

    for _, e in pairs(effs) do
      if e == effect then return end
    end
    table.insert(effs, effect)
  end

  local prefix = "se-"
  local gr = "-grounded"

  add_effect("assembling-machine", prefix .. "space-assembling-machine", "quality")
  add_effect("assembling-machine", prefix .. "space-manufactory",       "quality")
  add_effect("assembling-machine", prefix .. "space-telescope-microwave", "quality")
  add_effect("assembling-machine", prefix .. "space-telescope-radio",       "quality")
  add_effect("assembling-machine", prefix .. "space-telescope-xray", "quality")
  add_effect("assembling-machine", prefix .. "space-telescope-gammaray",       "quality")
  add_effect("assembling-machine", prefix .. "space-telescope", "quality")
  add_effect("assembling-machine", prefix .. "pulveriser",       "quality")
  add_effect("assembling-machine", prefix .. "pulveriser" .. gr, "quality")
  add_effect("assembling-machine", prefix .. "space-mechanical-laboratory", "quality")
  add_effect("assembling-machine", prefix .. "recycling-facility",       "quality")
  add_effect("assembling-machine", prefix .. "recycling-facility" .. gr, "quality")
  add_effect("assembling-machine", prefix .. "space-thermodynamics-laboratory", "quality")
  add_effect("assembling-machine", prefix .. "space-thermodynamics-laboratory" .. gr, "quality")
  add_effect("assembling-machine", prefix .. "space-radiation-laboratory",       "quality")
  add_effect("assembling-machine", prefix .. "space-laser-laboratory", "quality")
  add_effect("assembling-machine", prefix .. "fuel-refinery",       "quality")
  add_effect("assembling-machine", prefix .. "fuel-refinery" .. gr, "quality") 
  add_effect("assembling-machine", prefix .. "space-electromagnetics-laboratory",       "quality")
  add_effect("assembling-machine", prefix .. "space-plasma-generator", "quality")
  add_effect("assembling-machine", prefix .. "space-biochemical-laboratory",       "quality")
  add_effect("assembling-machine", prefix .. "space-growth-facility",       "quality")
  add_effect("assembling-machine", prefix .. "space-material-fabricator", "quality")
  add_effect("assembling-machine", prefix .. "space-particle-collider",       "quality")
  add_effect("assembling-machine", prefix .. "space-genetics-laboratory",       "quality")
  add_effect("assembling-machine", prefix .. "space-spectrometry-facility",       "quality") 
  add_effect("assembling-machine", prefix .. "lifesupport-facility",       "quality") 
  add_effect("assembling-machine", prefix .. "lifesupport-facility" .. gr, "quality") 
  add_effect("assembling-machine", prefix .. "space-decontamination-facility",       "quality")  
  add_effect("assembling-machine", prefix .. "space-supercomputer-1",       "quality")  
  add_effect("assembling-machine", prefix .. "space-supercomputer-2",       "quality")    
  add_effect("assembling-machine", prefix .. "space-supercomputer-3",       "quality")    
  add_effect("assembling-machine", prefix .. "space-supercomputer-4",       "quality")   
  add_effect("assembling-machine", prefix .. "space-assembling-machine" .. gr, "quality")
  add_effect("assembling-machine", prefix .. "space-manufactory"       .. gr, "quality")
  
--"space-telescope-microwave"
--"space-telescope-radio"
--"space-telescope-xray"
--"space-telescope-gammaray"
--"space-telescope"
--"space-manufactory"
--"pulveriser"
--"space-mechanical-laboratory"
--"recycling-facility"
--"space-thermodynamics-laboratory"
 --"space-radiation-laboratory"
--"space-laser-laboratory"
--"fuel-refinery"
--"space-electromagnetics-laboratory"
--"space-plasma-generator"
--"space-biochemical-laboratory"
--"space-growth-facility"
--"space-material-fabricator"
--"space-particle-collider"
--"space-genetics-laboratory"

--space-supercomputer-1  space-supercomputer-2 space-supercomputer-3 space-supercomputer-4
--space-spectrometry-facility
--lifesupport-facility
--space-decontamination-facility


end
