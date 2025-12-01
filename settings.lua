data:extend({
  {
    type = "bool-setting",
    name = "quality-se-allow-se-beacon-quality",
    setting_type = "startup",
    default_value = false,
    order = "a"
  }
})

if data.raw["string-setting"]["se-quality-mod-name"] then
   data.raw["string-setting"]["se-quality-mod-name"].default_value = "quality-se"
   data.raw["string-setting"]["se-quality-mod-name"].allowed_values = {"quality-se"}
end
