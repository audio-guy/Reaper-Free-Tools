-- @description Symmetrisches Panning mit definierbarer Weite
-- @version 1.0
-- @author Gemini

function main()
    -- Anzahl der selektierten Tracks ermitteln
    local count_sel_tracks = reaper.CountSelectedTracks(0)
    
    -- Fehlerabfang: Wir brauchen mindestens 2 Tracks für einen Spread
    if count_sel_tracks < 2 then
        reaper.ShowMessageBox("Bitte wählen Sie mindestens 2 Tracks aus, um sie zu verteilen.", "Info", 0)
        return
    end

    -- Popup für User Input (Titel, Anzahl Felder, Feld-Beschriftung, Standardwert)
    local retval, user_input = reaper.GetUserInputs("Symmetrisches Panning", 1, "Weite (0-100):", "100")

    -- Wenn User "Cancel" drückt, abbrechen
    if not retval then return end

    -- Input in eine Nummer umwandeln
    local width = tonumber(user_input)

    -- Wenn keine gültige Nummer eingegeben wurde, abbrechen
    if not width then return end

    -- Sicherheit: Werte auf 0 bis 100 begrenzen (Clamping)
    if width > 100 then width = 100 end
    if width < 0 then width = 0 end

    -- Reaper rechnet Pan von -1.0 (L) bis +1.0 (R).
    -- Wir rechnen die User-Eingabe (z.B. 80) in diesen Faktor um (0.8)
    local max_pan_factor = width / 100

    -- Undo Block starten (damit man es mit Strg+Z rückgängig machen kann)
    reaper.Undo_BeginBlock()

    -- Schleife durch alle selektierten Tracks
    for i = 0, count_sel_tracks - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        
        -- Berechnung der Position:
        -- i / (count - 1) ergibt einen Wert zwischen 0.0 (erster Track) und 1.0 (letzter Track)
        local progress = i / (count_sel_tracks - 1)
        
        -- Mapping: Wir wollen von -max_pan bis +max_pan
        -- Formel: Startwert + (Fortschritt * Gesamtstrecke)
        -- Gesamtstrecke ist (max_pan * 2)
        local new_pan = -max_pan_factor + (progress * (max_pan_factor * 2))

        -- Pan setzen
        reaper.SetMediaTrackInfo_Value(track, "D_PAN", new_pan)
    end

    -- Undo Block beenden und GUI aktualisieren
    reaper.Undo_EndBlock("Symmetrisches Panning (" .. width .. "%)", -1)
    reaper.UpdateArrange()
end

reaper.PreventUIRefresh(1)
main()
reaper.PreventUIRefresh(-1)
