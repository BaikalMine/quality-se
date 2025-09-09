local recycling = require("prototypes.recycling")

-- Generating the recycle (reverse) recipes
for name, recipe in pairs(data.raw.recipe) do
  recycling.generate_recycling_recipe(recipe)
end

local generate_self_recycling_recipe = function(item)
  if item.auto_recycle == false then return end
  if item.parameter then return end

  if not data.raw.recipe[item.name .. "-recycling"] then
    if not string.find(item.name, "-barrel") then
      recycling.generate_self_recycling_recipe(item)
    end
  end
end

for type_name in pairs(defines.prototypes.item) do
  if data.raw[type_name] then
    for k, item in pairs(data.raw[type_name]) do
      generate_self_recycling_recipe(item)
    end
  end
end

data.raw.quality.normal.hidden = false

-- SE bridge: extend SE recyclers to accept Quality categories; allow recycler in space
if mods["space-exploration"] then
  local function add_category(entity, cat)
    if not entity then return end
    entity.crafting_categories = entity.crafting_categories or {}
    for _, c in pairs(entity.crafting_categories) do
      if c == cat then return end
    end
    table.insert(entity.crafting_categories, cat)
  end

  for _, am in pairs(data.raw["assembling-machine"]) do
    local cats = am.crafting_categories
    if cats then
      local has_se_recycling = false
      for _, c in pairs(cats) do
        if c == "hard-recycling" or c == "hand-hard-recycling" then
          has_se_recycling = true; break
        end
      end
      if has_se_recycling then
        add_category(am, "recycling")
        add_category(am, "recycling-or-hand-crafting")
      end
    end
  end

  if data.raw["furnace"] and data.raw["furnace"]["recycler"] then
    local rec = data.raw["furnace"]["recycler"]
    rec.se_allow_in_space = true
  end
end

-- Sanitizer: drop recycling recipes that reference items removed by other mods (e.g., SE removing Krastorio items)
do
  local item_types = {
    "item", "module", "tool", "armor", "gun", "ammo", "capsule",
    "item-with-entity-data", "item-with-label", "item-with-tags",
    "selection-tool", "blueprint", "deconstruction-planner", "upgrade-planner",
    "item-with-inventory", "rail-planner", "spidertron-remote",
    "repair-tool", "mining-tool", "armor", "fluid"
  }
  local function proto_exists(name)
    if not name then return false end
    for _, t in pairs(item_types) do
      if data.raw[t] and data.raw[t][name] then return true end
    end
    -- some equipment has matching item; if only equipment remains, skip
    return false
  end

  local function any_missing_in_ings(ings)
    if not ings then return false end
    for _, ing in pairs(ings) do
      if type(ing) == "table" then
        local n = ing.name or ing[1]
        if n and not proto_exists(n) then return true end
      end
    end
    return false
  end

  local function any_missing_in_results(results, main_name, result_name)
    if results then
      for _, r in pairs(results) do
        if type(r) == "table" then
          local n = r.name or r[1]
          if n and not proto_exists(n) then return true end
        end
      end
    else
      local n = main_name or result_name
      if n and not proto_exists(n) then return true end
    end
    return false
  end

  local removed = 0
  for name, r in pairs(data.raw.recipe) do
    local is_recycle = (name and string.find(name, "recycling", 1, true)) or
                       (r.category == "recycling") or (r.category == "recycling-or-hand-crafting") or
                       (r.category == "hard-recycling") or (r.category == "hand-hard-recycling")
    if is_recycle then
      local miss = any_missing_in_ings(r.ingredients) or any_missing_in_results(r.results, r.main_product, r.result)
      if not miss and r.normal then
        miss = any_missing_in_ings(r.normal.ingredients) or any_missing_in_results(r.normal.results, r.normal.main_product, r.normal.result)
      end
      if not miss and r.expensive then
        miss = any_missing_in_ings(r.expensive.ingredients) or any_missing_in_results(r.expensive.results, r.expensive.main_product, r.expensive.result)
      end
      if miss then
        data.raw.recipe[name] = nil
        removed = removed + 1
      end
    end
  end
  log("quality-se sanitizer removed "..removed.." invalid recycling recipes")
end
