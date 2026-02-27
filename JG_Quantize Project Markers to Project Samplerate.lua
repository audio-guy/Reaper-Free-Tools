-- Quantize markers to exact sample boundaries of project sample rate
function main()
  -- Aktuelle Projekt-Samplerate auslesen
  local project = 0
  local samplerate = reaper.SNM_GetIntConfigVar("projsrate", 0)
  
  if samplerate <= 0 then
    reaper.ShowMessageBox("Konnte die Projekt-Samplerate nicht ermitteln.", "Fehler", 0)
    return
  end
  
  -- Samples pro Sekunde berechnen (für die Rundung)
  local samples_per_sec = samplerate
  
  -- Alle Marker im Projekt durchgehen
  local num_markers = reaper.CountProjectMarkers(project)
  local adjusted = 0
  
  -- Zuerst alle Marker sammeln
  local markers = {}
  for i = 0, num_markers - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber, color = reaper.EnumProjectMarkers3(project, i)
    if retval then -- Sowohl Marker als auch Regionen
      table.insert(markers, {
        index = markrgnindexnumber, 
        pos = pos, 
        rgnend = rgnend, 
        name = name, 
        isrgn = isrgn, 
        color = color
      })
    end
  end
  
  reaper.Undo_BeginBlock()
  
  -- Marker anpassen
  for _, marker in ipairs(markers) do
    -- Position in Samples umrechnen
    local pos_in_samples = marker.pos * samples_per_sec
    local nearest_sample_pos = math.floor(pos_in_samples + 0.5) / samples_per_sec
    
    local end_pos = marker.rgnend
    if marker.isrgn then
      -- Auch das Ende der Region auf Samples quantisieren
      local end_in_samples = end_pos * samples_per_sec
      end_pos = math.floor(end_in_samples + 0.5) / samples_per_sec
    end
    
    -- Marker/Region aktualisieren, nur wenn die Position sich ändert
    if nearest_sample_pos ~= marker.pos or (marker.isrgn and end_pos ~= marker.rgnend) then
      reaper.DeleteProjectMarker(project, marker.index, marker.isrgn)
      reaper.AddProjectMarker2(project, marker.isrgn, nearest_sample_pos, end_pos, marker.name, marker.index, marker.color)
      adjusted = adjusted + 1
    end
  end
  
  reaper.Undo_EndBlock("Quantize markers to sample boundaries", -1)
  
  -- Feedback mit aktueller Samplerate
  reaper.ShowConsoleMsg(adjusted .. " Marker/Regionen wurden auf Sample-Grenzen bei " .. samplerate .. "Hz quantisiert\n")
end

main()
