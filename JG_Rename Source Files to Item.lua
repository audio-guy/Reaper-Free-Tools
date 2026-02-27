-- @description Rename Source Files to Item Names
-- @author Julius Gass
-- @version 1.2

-- Prüfe ob SWS Extension installiert ist
if not reaper.BR_SetTakeSourceFromFile then
  reaper.ShowMessageBox("Dieses Script benötigt die SWS Extension!", "Error", 0)
  return
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local item_count = reaper.CountSelectedMediaItems(0)
if item_count == 0 then
  reaper.ShowMessageBox("Bitte Items auswählen!", "Error", 0)
  return
end

local renamed = 0
local errors = {}

-- Erst alle Items offline setzen
reaper.Main_OnCommand(40440, 0) -- Set selected media offline

for i = 0, item_count - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  local take = reaper.GetActiveTake(item)
  
  if take and not reaper.TakeIsMIDI(take) then
    -- Item-Namen holen
    local _, item_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    
    -- Source-Datei Info
    local source = reaper.GetMediaItemTake_Source(take)
    local old_path = reaper.GetMediaSourceFileName(source, "")
    
    if old_path ~= "" and item_name ~= "" then
      -- Pfad und Dateiendung extrahieren
      local dir = old_path:match("^(.*[\\/])") or ""
      local ext = old_path:match("(%.[^%.]+)$") or ".wav"
      
      -- Neuer Pfad
      local new_path = dir .. item_name .. ext
      
      -- Prüfe ob Zieldatei schon existiert
      local file_exists = io.open(new_path, "r")
      if file_exists then
        file_exists:close()
        table.insert(errors, item_name .. ": Datei existiert bereits!")
      else
        -- Datei umbenennen
        local success, err = os.rename(old_path, new_path)
        
        if success then
          -- REAPER-Referenz aktualisieren
          reaper.BR_SetTakeSourceFromFile(take, new_path, false)
          renamed = renamed + 1
        else
          table.insert(errors, item_name .. ": " .. (err or "Konnte Datei nicht umbenennen"))
        end
      end
    end
  end
end

-- Alle wieder online setzen
reaper.Main_OnCommand(40439, 0) -- Set selected media online

-- Peaks neu aufbauen
if renamed > 0 then
  reaper.Main_OnCommand(40441, 0)
end

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Rename Source Files to Item Names", -1)
reaper.UpdateArrange()

-- Ergebnis anzeigen
local msg = string.format("Erfolgreich umbenannt: %d\nFehler: %d", renamed, #errors)
if #errors > 0 then
  msg = msg .. "\n\nFehler:\n" .. table.concat(errors, "\n")
end
reaper.ShowMessageBox(msg, "Fertig", 0)
