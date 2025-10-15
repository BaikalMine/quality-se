-- data-updates.lua (Quality-SE)
-- Генерируем рециклы как в Quality, но НИКОГДА не трогаем Space Exploration:
--  • не генерим reverse для SE-рецептов
--  • не генерим self-recycle для SE-предметов
--  • разрешаем only Quality recycler в космосе

local recycling = require("prototypes.recycling")

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

-- 4) Мини-бридж для SE: только разрешаем ресайклер Quality в космосе
if mods["space-exploration"] then
  data.raw.technology["recycling"].enabled = true
end
