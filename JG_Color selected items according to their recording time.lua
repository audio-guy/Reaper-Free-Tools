--[[
ReaScript Name: Color selected items by group (contrasting palette with min/max control)
Author: ChatGPT (Reaper DAW Ultimate Assistant)
Description:
  Dieses Script färbt ausgewählte Items nach Startzeit-Gruppen ein.
  Die Farben kommen aus einer kontrastreichen Palette.
  Zusätzlich kannst du min/max Werte definieren, damit nichts zu dunkel
  oder zu grell wird.
--]]

-- SETTINGS ------------------------------
local tolerance   = 0.05   -- Sekunden Toleranz für gleiche Startzeit
local hue_step    = 0.12   -- Schrittweite im Farbkreis (kleiner = mehr Farben, größer = weniger ähnliche Nachbarn)

-- Grenzen für RGB-Werte (0–255)
local min_val     = 18     -- keine dunkleren Farben
local max_val     = 230    -- keine helleren Farben
------------------------------------------

-- Hilfsfunktion: clamp (Wert begrenzen)
local function clamp(x, lo, hi)
  if x < lo then return lo elseif x > hi then return hi else return x end
end

-- HSL → RGB (Hue 0..1, Sat 0..1, Light 0..1)
local function hsl_to_rgb(h, s, l)
  local function hue_to_rgb(p, q, t)
    if t < 0 then t = t + 1 end
    if t > 1 then t = t - 1 end
    if t < 1/6 then return p + (q - p) * 6 * t end
    if t < 1/2 then return q end
    if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
    return p
  end

  local r, g, b
  if s == 0 then
    r, g, b = l, l, l
  else
    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q
    r = hue_to_rgb(p, q, h + 1/3)
    g = hue_to_rgb(p, q, h)
    b = hue_to_rgb(p, q, h - 1/3)
  end

  r = clamp(math.floor(r * 255), min_val, max_val)
  g = clamp(math.floor(g * 255), min_val, max_val)
  b = clamp(math.floor(b * 255), min_val, max_val)
  return r, g, b
end

-- Palette-Generator mit Kontrasten
local hue_index = 0
local function next_color()
  local h = (hue_index * hue_step) % 1.0
  -- Abwechselnd Sättigung und Helligkeit für Kontrast
  local sat = (hue_index % 2 == 0) and 0.75 or 0.45
  local lit = (hue_index % 3 == 0) and 0.55 or 0.70
  hue_index = hue_index + 1
  local r, g, b = hsl_to_rgb(h, sat, lit)
  return reaper.ColorToNative(r, g, b) | 0x1000000
end

-- Gruppen sammeln
local groups = {}
local num_sel = reaper.CountSelectedMediaItems(0)
if num_sel == 0 then return end

for i = 0, num_sel-1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")

  local found_group = nil
  for gpos, group in pairs(groups) do
    if math.abs(pos - gpos) <= tolerance then
      found_group = group
      break
    end
  end

  if not found_group then
    local new_group = { items = {}, color = next_color() }
    groups[pos] = new_group
    found_group = new_group
  end

  table.insert(found_group.items, item)
end

-- Farben anwenden
reaper.Undo_BeginBlock()
for _, group in pairs(groups) do
  for _, item in ipairs(group.items) do
    reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", group.color)
  end
end
reaper.UpdateArrange()
reaper.Undo_EndBlock("Color selected items by start position groups (contrasting palette)", -1)
