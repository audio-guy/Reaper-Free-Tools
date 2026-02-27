-- Per-Track Loudness Normalize  (v2 – Bugfix: Accessor-Zeitbasis)
-- ─────────────────────────────────────────────────────────────────────
-- Alle selektierten Items werden nach Track gruppiert.
-- Pro Track werden ALLE Items gemeinsam als ein Stream analysiert
-- und erhalten anschließend exakt denselben Item-Gain (D_VOL),
-- sodass die gemessene Integrated Loudness dem Zielwert entspricht.
--
-- Änderungen v2:
--  • Accessor-Zeitbasis korrekt: Start = GetAudioAccessorStartTime(),
--    Ende = GetAudioAccessorEndTime() (capped auf Item-Länge).
--    Der Take-Accessor berücksichtigt D_STARTOFFS intern – eigene
--    Offset-Berechnung war falsch und las teilweise falschen/leeren Bereich.
--  • nch wird pro Item ermittelt (nicht einmalig für den ganzen Track)
--  • Stereo-Leistung: (L² + R²) × 0.5  (BS.1770: Kanalzahl-Mittelung)
--  • Fallback-Block greift nur wenn rcnt > 0
--
-- Standard: BS.1770-4 (Integrated Loudness, 400 ms / 75 % Overlap, gated)
-- Analyse-SR intern: 16 kHz (REAPER resampelt on-the-fly; Abweichung
-- gegenüber 48 kHz typisch < 0.1 LU)
--
-- Julius Gaß  •  2025
-- ─────────────────────────────────────────────────────────────────────

local r = reaper

local ANALYSIS_SR = 16000

-- ─── Ziel-LUFS abfragen ───────────────────────────────────────────────
local ok, raw = r.GetUserInputs(
  "Per-Track Loudness Normalize", 1, "Ziel-LUFS:", "-23")
if not ok then return end

local TARGET = tonumber(raw)
if not TARGET then
  r.MB("Ungültiger Wert – bitte eine Zahl eingeben (z.B. -23).", "Fehler", 0)
  return
end

-- ─── Selektierte Items nach Track gruppieren ──────────────────────────
if r.CountSelectedMediaItems(0) == 0 then
  r.MB("Keine Items ausgewählt.", "Info", 0)
  return
end

local groups = {}
local gmap   = {}

for i = 0, r.CountSelectedMediaItems(0) - 1 do
  local item  = r.GetSelectedMediaItem(0, i)
  local track = r.GetMediaItem_Track(item)
  local guid  = r.GetTrackGUID(track)
  if not gmap[guid] then
    table.insert(groups, {track = track, items = {}})
    gmap[guid] = #groups
  end
  table.insert(groups[gmap[guid]].items, item)
end

-- ─── K-Weighting Filter (BS.1770-4, Bilinear Transform) ───────────────
local function kweight_coeffs(sr)
  local pi = math.pi

  -- Stufe 1: High-Shelf +4 dB bei 1681.97 Hz, Q 0.7072
  local A   = 10 ^ (4 / 40)          -- sqrt(10^(4/20))
  local sqA = math.sqrt(A)
  local f0  = 1681.974450955533
  local Q   = 0.7071752369554196
  local w0  = 2 * pi * f0 / sr
  local c0, s0 = math.cos(w0), math.sin(w0)
  local al  = s0 / (2 * Q)
  local b0  =  A * ((A+1) + (A-1)*c0 + 2*sqA*al)
  local b1  = -2 * A * ((A-1) + (A+1)*c0)
  local b2  =  A * ((A+1) + (A-1)*c0 - 2*sqA*al)
  local a0  = (A+1) - (A-1)*c0 + 2*sqA*al
  local a1  =  2 * ((A-1) - (A+1)*c0)
  local a2  = (A+1) - (A-1)*c0 - 2*sqA*al
  local hs  = {b0/a0, b1/a0, b2/a0, a1/a0, a2/a0}

  -- Stufe 2: Butterworth HP 2. Ord. bei 38.14 Hz
  local f1  = 38.13547087602444
  local w1  = 2 * pi * f1 / sr
  local c1, s1 = math.cos(w1), math.sin(w1)
  local al1 = s1 / math.sqrt(2)      -- Q = 1/√2
  local d0  = (1 + c1) / 2;  local d1 = -(1 + c1);  local d2 = (1 + c1) / 2
  local e0  = 1 + al1;       local e1 = -2 * c1;     local e2 = 1 - al1
  local hp  = {d0/e0, d1/e0, d2/e0, e1/e0, e2/e0}

  return hs, hp
end

-- ─── BS.1770-4 Integrated Loudness ────────────────────────────────────
local function measure_lufs(items)
  local sr       = ANALYSIS_SR
  local hs, hp   = kweight_coeffs(sr)
  local hop      = math.floor(0.1 * sr)   -- 100 ms Hop
  local blk_samp = 4 * hop                -- 400 ms Block

  -- Koeffizienten als Locals für Innerloop-Performance
  local hs0,hs1,hs2,ha1,ha2 = hs[1],hs[2],hs[3],hs[4],hs[5]
  local hp0,hp1,hp2,pa1,pa2 = hp[1],hp[2],hp[3],hp[4],hp[5]

  -- Filterzustände (bleiben über Item-Grenzen erhalten → korrekter Stream)
  local ax1,ax2,ay1,ay2 = 0,0,0,0   -- Ch1 Stufe 1
  local ap1,ap2,aq1,aq2 = 0,0,0,0   -- Ch1 Stufe 2
  local bx1,bx2,by1,by2 = 0,0,0,0   -- Ch2 Stufe 1
  local bp1,bp2,bq1,bq2 = 0,0,0,0   -- Ch2 Stufe 2

  -- Ringpuffer: 4 Slots à 100 ms (bilden 400-ms-Blöcke mit 75 % Overlap)
  local ring  = {0, 0, 0, 0}
  local rslot = 1
  local rcnt  = 0
  local nhops = 0
  local blocks = {}

  local function close_slot()
    nhops       = nhops + 1
    if nhops >= 4 then
      local z = (ring[1]+ring[2]+ring[3]+ring[4]) / blk_samp
      blocks[#blocks+1] = z
    end
    rslot       = rslot % 4 + 1
    ring[rslot] = 0
    rcnt        = 0
  end

  local CHUNK = 4096
  local buf   = r.new_array(CHUNK * 2)

  for _, item in ipairs(items) do
    local tk = r.GetActiveTake(item)
    if not tk or r.TakeIsMIDI(tk) then goto next_item end

    -- Kanalzahl pro Item
    local src = r.GetMediaItemTake_Source(tk)
    local nch = math.min(r.GetMediaSourceNumChannels(src), 2)

    local acc   = r.CreateTakeAudioAccessor(tk)

    -- ► Bugfix v2: Zeitbasis direkt vom Accessor holen.
    --   GetAudioAccessorStartTime gibt 0.0, End = Quelldauer ab Startoffset.
    --   Wir cappen zusätzlich auf die Item-Länge (= was tatsächlich abgespielt wird).
    local t     = r.GetAudioAccessorStartTime(acc)
    local t_end = math.min(
      r.GetAudioAccessorEndTime(acc),
      t + r.GetMediaItemInfo_Value(item, "D_LENGTH")
    )

    while t < t_end - 1e-9 do
      local want = math.min(CHUNK, math.floor((t_end - t) * sr) + 1)
      if want <= 0 then break end

      local got = r.GetAudioAccessorSamples(acc, sr, nch, t, want, buf)
      if got <= 0 then break end

      -- ── Inner Loop: K-Gewichtung + Leistungsakkumulation ──────────
      if nch == 1 then
        for i = 1, want do
          local x  = buf[i]
          local yA = hs0*x  + hs1*ax1 + hs2*ax2 - ha1*ay1 - ha2*ay2
          ax2=ax1; ax1=x;  ay2=ay1; ay1=yA
          local yB = hp0*yA + hp1*ap1 + hp2*ap2 - pa1*aq1 - pa2*aq2
          ap2=ap1; ap1=yA; aq2=aq1; aq1=yB

          ring[rslot] = ring[rslot] + yB * yB
          rcnt = rcnt + 1
          if rcnt >= hop then close_slot() end
        end

      else  -- Stereo: Kanalleistung mitteln (BS.1770-4)
        for i = 0, want - 1 do
          local x1 = buf[i*2+1];  local x2 = buf[i*2+2]
          local yA = hs0*x1 + hs1*ax1 + hs2*ax2 - ha1*ay1 - ha2*ay2
          ax2=ax1; ax1=x1; ay2=ay1; ay1=yA
          local yB = hp0*yA + hp1*ap1 + hp2*ap2 - pa1*aq1 - pa2*aq2
          ap2=ap1; ap1=yA; aq2=aq1; aq1=yB

          local yC = hs0*x2 + hs1*bx1 + hs2*bx2 - ha1*by1 - ha2*by2
          bx2=bx1; bx1=x2; by2=by1; by1=yC
          local yD = hp0*yC + hp1*bp1 + hp2*bp2 - pa1*bq1 - pa2*bq2
          bp2=bp1; bp1=yC; bq2=bq1; bq1=yD

          ring[rslot] = ring[rslot] + (yB*yB + yD*yD) * 0.5
          rcnt = rcnt + 1
          if rcnt >= hop then close_slot() end
        end
      end
      -- ──────────────────────────────────────────────────────────────

      t = t + want / sr
    end

    r.DestroyAudioAccessor(acc)
    ::next_item::
  end

  -- Letzten unvollständigen Slot als Fallback (wichtig bei sehr kurzen Takes)
  if #blocks == 0 and rcnt > 0 then
    local total = nhops * hop + rcnt
    local z = (ring[1]+ring[2]+ring[3]+ring[4]) / total
    if z > 1e-30 then blocks[1] = z end
  end

  if #blocks == 0 then return nil end

  -- ── Gating (BS.1770-4) ────────────────────────────────────────────
  local LOG10 = 0.4342944819032518

  -- Absolute Gate –70 LKFS
  local abs_z = 10 ^ ((-70 + 0.691) / 10)
  local g1 = {}
  for _, z in ipairs(blocks) do
    if z > abs_z then g1[#g1+1] = z end
  end
  if #g1 == 0 then return -math.huge end

  -- Relative Gate J_g – 10 dB
  local s1 = 0; for _, z in ipairs(g1) do s1 = s1 + z end
  local Jg    = -0.691 + 10 * math.log(s1 / #g1) * LOG10
  local rel_z = 10 ^ ((Jg - 10 + 0.691) / 10)
  local g2 = {}
  for _, z in ipairs(g1) do
    if z > rel_z then g2[#g2+1] = z end
  end
  if #g2 == 0 then return -math.huge end

  local s2 = 0; for _, z in ipairs(g2) do s2 = s2 + z end
  return -0.691 + 10 * math.log(s2 / #g2) * LOG10
end

-- ─── Hauptverarbeitung ────────────────────────────────────────────────
r.Undo_BeginBlock()

for _, grp in ipairs(groups) do
  local _, tname = r.GetTrackName(grp.track)
  local lufs = measure_lufs(grp.items)

  if not lufs or lufs < -90 then
    r.ShowConsoleMsg("    → zu leise / kein Audio – übersprungen.\n")
  else
    local gain_db  = TARGET - lufs
    local gain_lin = 10 ^ (gain_db / 20)
    for _, item in ipairs(grp.items) do
      r.SetMediaItemInfo_Value(item, "D_VOL", gain_lin)
      r.UpdateItemInProject(item)
    end

  end
end

r.Undo_EndBlock("Per-Track Loudness Normalize", -1)
r.UpdateArrange()

