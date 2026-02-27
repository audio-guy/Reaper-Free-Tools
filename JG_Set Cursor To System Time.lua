-- REAPER Script: Set timeline to timecode and move cursor to current system time
-- Author: Julius
-- Version: 1.3

function Main()
    -- Aktuelle Systemzeit abrufen
    local current_time = os.date("*t")
    local hours = current_time.hour
    local minutes = current_time.min
    local seconds = current_time.sec
    
    -- Umrechnung in Sekunden seit Tagesbeginn (00:00:00)
    local time_in_seconds = hours * 3600 + minutes * 60 + seconds
    
    -- Timeline auf Timecode-Modus umschalten (hh:mm:ss:ff)
    reaper.Main_OnCommand(40370, 0) -- Time unit for ruler: Hours:Minutes:Seconds:Frames
    
    -- Projekt-Start auf 00:00:00 setzen
    reaper.GetSetProjectInfo(0, "PROJ_START", 0, true)
    
    -- Edit Cursor an die aktuelle Tageszeit setzen
    reaper.SetEditCurPos(time_in_seconds, true, true)
    
    -- Statusmeldung
    local time_string = string.format("%02d:%02d:%02d", hours, minutes, seconds)
    reaper.ShowConsoleMsg("Timeline auf Timecode umgestellt\n")
    reaper.ShowConsoleMsg("Cursor gesetzt auf: " .. time_string .. "\n")
    
    -- Timeline zum Cursor scrollen
    reaper.Main_OnCommand(40913, 0)
    
    -- Update der Ansicht
    reaper.UpdateArrange()
end

-- Undo-Block
reaper.Undo_BeginBlock()
Main()
reaper.Undo_EndBlock("Set timeline to timecode and cursor to system time", -1)
