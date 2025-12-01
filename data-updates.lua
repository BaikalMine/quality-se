-- data-updates.lua (Quality-SE)
-- Генерируем рециклы как в Quality, но НИКОГДА не трогаем Space Exploration:
--  • не генерим reverse для SE-рецептов
--  • не генерим self-recycle для SE-предметов
--  • разрешаем only Quality recycler в космосе

local recycling = require("prototypes.recycling")

if mods["space-exploration"] then
  local quality_setting = data.raw["string-setting"] and data.raw["string-setting"]["se-quality-mod-name"]
  if quality_setting then
    local allowed = {}
    local seen = {}
    local function add(value)
      if type(value) ~= "string" then return end
      if not seen[value] then
        seen[value] = true
        table.insert(allowed, value)
      end
    end
    if quality_setting.allow_blank then add("") end
    add("quality-se")
    for _, value in ipairs(quality_setting.allowed_values or {}) do
      add(value)
    end
    quality_setting.allowed_values = allowed
    quality_setting.default_value = "quality-se"
  end
end

local function is_se_recipe(r)
  if not r then return false end
  local n = r.name or ""
  if string.find(n, "^se%-") then return true end
  local cat = r.category
  return (cat == "hard-recycling") or (cat == "hand-hard-recycling")
end

-- 1) Генерация обратных (reverse) рецептов Quality: пропускаем SE
for _, recipe in pairs(data.raw.recipe) do
  if not is_se_recipe(recipe) then
    recycling.generate_recycling_recipe(recipe)
  end
end

-- 2) Генерация self-recycling для предметов: пропускаем SE-предметы
local function is_se_item_name(name)
  return type(name) == "string" and string.find(name, "^se%-")
end

local function generate_self_recycling_recipe(item)
  if item.auto_recycle == false then return end
  if item.parameter then return end
  if is_se_item_name(item.name) then return end
  if not data.raw.recipe[item.name .. "-recycling"] then
    if not string.find(item.name, "-barrel") then
      recycling.generate_self_recycling_recipe(item)
    end
  end
end

for type_name in pairs(defines.prototypes.item) do
  if data.raw[type_name] then
    for _, item in pairs(data.raw[type_name]) do
      generate_self_recycling_recipe(item)
    end
  end
end

-- 3) Сделать качество "normal" видимым (как в оригинале)
if data.raw.quality and data.raw.quality.normal then
  data.raw.quality.normal.hidden = false
end

if mods["Krastorio2"] then
  local function set_quality_recipe(name, energy_required, ingredients)
    local recipe = data.raw.recipe[name]
    if not recipe then return end
    recipe.energy_required = energy_required
    recipe.ingredients = ingredients
    if recipe.normal then
      recipe.normal.energy_required = energy_required
      recipe.normal.ingredients = ingredients
    end
    if recipe.expensive then
      recipe.expensive.energy_required = energy_required
      recipe.expensive.ingredients = ingredients
    end
  end

  set_quality_recipe("quality-module", 15, {
    {type = "item", name = "electronic-circuit", amount = 5},
    {type = "item", name = "kr-electronic-components", amount = 10},
  })
  set_quality_recipe("quality-module-2", 15, {
    {type = "item", name = "advanced-circuit", amount = 5},
    {type = "item", name = "electronic-circuit", amount = 5},
    {type = "item", name = "quality-module", amount = 5},
  })
  set_quality_recipe("quality-module-3", 15, {
    {type = "item", name = "processing-unit", amount = 5},
    {type = "item", name = "advanced-circuit", amount = 5},
    {type = "item", name = "quality-module-2", amount = 5},
  })

  local function replace_ingredient(recipe_name, old_name, new_name)
    local function replace(ingredient_list)
      if not ingredient_list then return end
      for _, ingredient in ipairs(ingredient_list) do
        local ingredient_name = ingredient.name or ingredient[1]
        if ingredient_name == old_name then
          ingredient.name = new_name
          ingredient[1] = nil
        end
      end
    end
    local recipe = data.raw.recipe[recipe_name]
    if not recipe then return end
    replace(recipe.ingredients)
    replace(recipe.normal and recipe.normal.ingredients)
    replace(recipe.expensive and recipe.expensive.ingredients)
  end

  replace_ingredient("recycler", "steel-plate", "kr-rare-metals")

  local recycling_tech = data.raw.technology["recycling"]
  if recycling_tech and recycling_tech.unit then
    recycling_tech.unit.count = 500
  end

  local blocked_recipe_subgroups = {
    ["kr-smelting-crafting"] = true,
  }
  for _, recipe in pairs(data.raw.recipe) do
    if blocked_recipe_subgroups[recipe.subgroup] then
      recipe.auto_recycle = false
    end
  end
end
