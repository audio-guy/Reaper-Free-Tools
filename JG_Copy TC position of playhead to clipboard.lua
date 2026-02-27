-- Copy timecode to clipboard
-- During playback: playhead position
-- When stopped: edit cursor position

local state = reaper.GetPlayState() -- 1=play, 2=pause, 4=record

local pos
if state == 0 then
  pos = reaper.GetCursorPosition()
else
  pos = reaper.GetPlayPosition()
end

local tc = reaper.format_timestr_pos(pos, "", -1)

reaper.CF_SetClipboard(tc)
