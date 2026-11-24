local ADDON_NAME, Addon = ...

local log = WoWF.Logger:New(ADDON_NAME, {
	minLevel = WoWF.DevMode and "DEBUG" or "INFO",
})

WoWF.OnDevModeChanged(function(enabled)
	log:SetLevel(enabled and "DEBUG" or "INFO")
end)

--- Rolling window (seconds) used for "current pace".
local SAMPLE_WINDOW = 10 * 60
--- Need at least this much elapsed sample time before showing an ETA.
local MIN_ELAPSED = 30
--- While idle, append a same-XP heartbeat so the rate decays with downtime.
local IDLE_HEARTBEAT = 15
--- No XP for this long → clear the pace session.
local IDLE_CLEAR = 5 * 60
--- After a quest turn-in, ignore XP deltas for pace (still refresh ETA from remaining).
local QUEST_PACE_IGNORE = 2.0
--- UI refresh interval while the frame is shown.
local UI_TICK = 1.0
--- Classic XP bar is divided into this many equal segments (19 ticks).
local XP_SEGMENTS = 20
local STATUS_BAR_TEX = "Interface\\TargetingFrame\\UI-StatusBar"

--- Rolling samples store cumulative XP gained (monotonic), not raw UnitXP,
--- so a level-up does not break the rate window.
local samples = {}
local lastAbsXP -- last seen UnitXP("player")
local lastAbsMax -- last seen UnitXPMax("player")
local cumulativeXP = 0
local lastXpGainAt -- GetTime() of last real XP increase (kills / non-quest)
local ignorePaceUntil -- GetTime(); quest XP is absorbed into baseline until then
local frame
local uiElapsed = 0
local isDragging = false
local expBarHider
local idleTickerElapsed = 0

local STYLE_NATIVE = "native"
local STYLE_WENDING = "wending"
local STYLE_CUSTOM = "custom"

--- Classic Blizzard XP purple.
local NATIVE_XP_COLOR = { r = 0.58, g = 0.0, b = 0.55 }
--- WenDing brand cyan (|cff33ccff).
local WENDING_XP_COLOR = { r = 0.2, g = 0.8, b = 1.0 }
local DEFAULT_XP_COLOR = { r = 1.0, g = 0.82, b = 0.0 }
local DEFAULT_BG_COLOR = { r = 0.0, g = 0.0, b = 0.0, a = 0.5 }
local DEFAULT_FONT_COLOR = { r = 1.0, g = 1.0, b = 1.0 }

Addon.DEFAULT_XP_COLOR = DEFAULT_XP_COLOR
Addon.DEFAULT_BG_COLOR = DEFAULT_BG_COLOR
Addon.DEFAULT_FONT_COLOR = DEFAULT_FONT_COLOR
-- Back-compat alias for older panel code during reload.
Addon.DEFAULT_CUSTOM_COLOR = DEFAULT_XP_COLOR

--- Permanently hide Blizzard's default bottom XP / status bar.
local function HideDefaultExpBar()
	if not expBarHider then
		expBarHider = CreateFrame("Frame")
		expBarHider:Hide()
	end

	local function swallow(bar)
		if not bar then
			return
		end
		bar:SetParent(expBarHider)
		bar:Hide()
	end

	swallow(StatusTrackingBarManager)
	swallow(MainMenuExpBar)
	swallow(ExhaustionTick)
	swallow(MainMenuBarMaxLevelBar)
end

local function EnsureDB()
	if type(WenDingDB) ~= "table" then
		WenDingDB = {}
	end
	local prev = WenDingDB.version or 0
	WenDingDB.version = WenDingDB.version or 18
	-- v2: XP bar lives at the bottom like Blizzard's; drop old panel coords.
	if prev < 2 then
		WenDingDB.version = math.max(WenDingDB.version or 0, 2)
		WenDingDB.point = nil
		WenDingDB.relativePoint = nil
		WenDingDB.x = nil
		WenDingDB.y = nil
	end
	-- v3: style + overlay toggles for the /wd panel.
	if prev < 3 then
		WenDingDB.version = math.max(WenDingDB.version or 0, 3)
	end
	-- v4: split custom color into experience / background / font.
	if prev < 4 then
		WenDingDB.version = math.max(WenDingDB.version or 0, 4)
		if type(WenDingDB.customColor) == "table" and type(WenDingDB.xpColor) ~= "table" then
			WenDingDB.xpColor = {
				r = WenDingDB.customColor.r or DEFAULT_XP_COLOR.r,
				g = WenDingDB.customColor.g or DEFAULT_XP_COLOR.g,
				b = WenDingDB.customColor.b or DEFAULT_XP_COLOR.b,
			}
		end
	end
	-- v5: wider default bar + sit on MainActionBar; reset old position/width.
	if prev < 5 then
		WenDingDB.version = math.max(WenDingDB.version or 0, 5)
		WenDingDB.point = nil
		WenDingDB.relativePoint = nil
		WenDingDB.x = nil
		WenDingDB.y = nil
		WenDingDB.barWidth = nil
	end
	-- v6/v7: wipe position/width when default anchoring strategy changes.
	if prev < 7 then
		WenDingDB.version = math.max(WenDingDB.version or 0, 7)
		WenDingDB.point = nil
		WenDingDB.relativePoint = nil
		WenDingDB.x = nil
		WenDingDB.y = nil
		WenDingDB.barWidth = nil
	end
	-- v8: default width from Forever's XP bar (not MainActionBar).
	if prev < 8 then
		WenDingDB.version = math.max(WenDingDB.version or 0, 8)
		WenDingDB.barWidth = nil
	end
	-- v9: center-BOTTOM anchoring + tighter default width; clear old layout.
	if prev < 9 then
		WenDingDB.version = math.max(WenDingDB.version or 0, 9)
		WenDingDB.point = nil
		WenDingDB.relativePoint = nil
		WenDingDB.x = nil
		WenDingDB.y = nil
		WenDingDB.barWidth = nil
	end
	-- v10: reject bad Y=0 snapshot; taller bar for readable text.
	if prev < 10 then
		WenDingDB.version = math.max(WenDingDB.version or 0, 10)
		WenDingDB.point = nil
		WenDingDB.relativePoint = nil
		WenDingDB.x = nil
		WenDingDB.y = nil
	end
	-- v11: center on ActionButton1–12 (MainActionBar gryphons skewed X).
	if prev < 11 then
		WenDingDB.version = math.max(WenDingDB.version or 0, 11)
		WenDingDB.point = nil
		WenDingDB.relativePoint = nil
		WenDingDB.x = nil
		WenDingDB.y = nil
	end
	-- v12: db.x is offset from action-bar center (0 = aligned), not screen center.
	if prev < 12 then
		WenDingDB.version = math.max(WenDingDB.version or 0, 12)
		WenDingDB.point = nil
		WenDingDB.relativePoint = nil
		WenDingDB.x = nil
		WenDingDB.y = nil
	end
	-- v13: ignore left-anchored MainMenuBar chrome; center on ActionButton1–12.
	if prev < 13 then
		WenDingDB.version = math.max(WenDingDB.version or 0, 13)
		WenDingDB.point = nil
		WenDingDB.relativePoint = nil
		WenDingDB.x = nil
		WenDingDB.y = nil
	end
	-- v14: X is offset from visible UI center only (UIParent width / 2). No bar-relative math.
	if prev < 14 then
		WenDingDB.version = math.max(WenDingDB.version or 0, 14)
		WenDingDB.point = nil
		WenDingDB.relativePoint = nil
		WenDingDB.x = nil
		WenDingDB.y = nil
	end
	-- v15: default size 1000×10; clear saved width/height so Reset/new picks it up.
	if prev < 15 then
		WenDingDB.version = math.max(WenDingDB.version or 0, 15)
		WenDingDB.barWidth = nil
		WenDingDB.barHeight = nil
	end
	-- v16: default height 13.
	if prev < 16 then
		WenDingDB.version = math.max(WenDingDB.version or 0, 16)
		WenDingDB.barHeight = nil
	end
	-- v17: layout lock + snap-to-default.
	if prev < 17 then
		WenDingDB.version = math.max(WenDingDB.version or 0, 17)
	end
	-- v18: per-level 10% milestone timestamps.
	if prev < 18 then
		WenDingDB.version = 18
	end
	if WenDingDB.shown == nil then
		WenDingDB.shown = true
	end
	if WenDingDB.locked == nil then
		WenDingDB.locked = false
	end
	if type(WenDingDB.levelMarks) ~= "table" then
		WenDingDB.levelMarks = {}
	end
	if WenDingDB.styleType ~= STYLE_NATIVE
		and WenDingDB.styleType ~= STYLE_WENDING
		and WenDingDB.styleType ~= STYLE_CUSTOM
	then
		WenDingDB.styleType = STYLE_NATIVE
	end
	if type(WenDingDB.xpColor) ~= "table" then
		WenDingDB.xpColor = {
			r = DEFAULT_XP_COLOR.r,
			g = DEFAULT_XP_COLOR.g,
			b = DEFAULT_XP_COLOR.b,
		}
	end
	if type(WenDingDB.bgColor) ~= "table" then
		WenDingDB.bgColor = {
			r = DEFAULT_BG_COLOR.r,
			g = DEFAULT_BG_COLOR.g,
			b = DEFAULT_BG_COLOR.b,
			a = DEFAULT_BG_COLOR.a,
		}
	elseif WenDingDB.bgColor.a == nil then
		WenDingDB.bgColor.a = DEFAULT_BG_COLOR.a
	end
	if type(WenDingDB.fontColor) ~= "table" then
		WenDingDB.fontColor = {
			r = DEFAULT_FONT_COLOR.r,
			g = DEFAULT_FONT_COLOR.g,
			b = DEFAULT_FONT_COLOR.b,
		}
	end
	if WenDingDB.showLevel == nil then
		WenDingDB.showLevel = true
	end
	if WenDingDB.showXP == nil then
		WenDingDB.showXP = true
	end
	if WenDingDB.showPct == nil then
		WenDingDB.showPct = true
	end
	if WenDingDB.showXPPerHour == nil then
		WenDingDB.showXPPerHour = true
	end
	if WenDingDB.showETA == nil then
		WenDingDB.showETA = true
	end
	return WenDingDB
end

Addon.EnsureDB = EnsureDB

local function CopyColor(src, fallback)
	src = src or fallback
	return {
		r = src.r or fallback.r,
		g = src.g or fallback.g,
		b = src.b or fallback.b,
		a = src.a ~= nil and src.a or fallback.a,
	}
end

local function GetResolvedColors()
	local db = EnsureDB()
	if db.styleType == STYLE_WENDING then
		return CopyColor(WENDING_XP_COLOR, WENDING_XP_COLOR),
			CopyColor(DEFAULT_BG_COLOR, DEFAULT_BG_COLOR),
			CopyColor(DEFAULT_FONT_COLOR, DEFAULT_FONT_COLOR)
	end
	if db.styleType == STYLE_CUSTOM then
		return CopyColor(db.xpColor, DEFAULT_XP_COLOR),
			CopyColor(db.bgColor, DEFAULT_BG_COLOR),
			CopyColor(db.fontColor, DEFAULT_FONT_COLOR)
	end
	return CopyColor(NATIVE_XP_COLOR, NATIVE_XP_COLOR),
		CopyColor(DEFAULT_BG_COLOR, DEFAULT_BG_COLOR),
		CopyColor(DEFAULT_FONT_COLOR, DEFAULT_FONT_COLOR)
end

--- Solid-color fill that works on Classic-style clients without SetColorTexture.
local function SetSolidColor(texture, r, g, b, a)
	a = a or 1
	if texture.SetColorTexture then
		texture:SetColorTexture(r, g, b, a)
		return
	end
	texture:SetTexture("Interface\\Buttons\\WHITE8X8")
	texture:SetVertexColor(r, g, b, a)
end

local function ApplyBarStyle()
	if not frame or not frame.bar then
		return
	end
	local xp, bg, font = GetResolvedColors()
	frame.bar:SetStatusBarColor(xp.r, xp.g, xp.b, 1)
	if frame.barBg then
		SetSolidColor(frame.barBg, bg.r, bg.g, bg.b, bg.a or 0.5)
	end
	if frame.labels then
		for _, label in ipairs(frame.labels) do
			label:SetTextColor(font.r, font.g, font.b, 1)
		end
	end
end

Addon.ApplyBarStyle = ApplyBarStyle

--- Optional XP override for Dev tab simulations (nil = live UnitXP).
local xpOverride
local xpMaxOverride

local function GetPlayerXP()
	if xpOverride ~= nil then
		return xpOverride
	end
	return UnitXP("player") or 0
end

local function GetPlayerXPMax()
	if xpMaxOverride ~= nil then
		return xpMaxOverride
	end
	return UnitXPMax("player") or 0
end

local function GetRemainingXP()
	local maxXP = GetPlayerXPMax()
	if maxXP <= 0 then
		return 0
	end
	return math.max(0, maxXP - GetPlayerXP())
end

local function FormatNumber(n)
	n = math.floor(tonumber(n) or 0)
	local formatted = tostring(n)
	while true do
		local k
		formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return formatted
end

local function FormatDuration(seconds)
	seconds = tonumber(seconds)
	if not seconds or seconds < 0 or seconds ~= seconds then
		return "—"
	end
	seconds = math.floor(seconds + 0.5)
	if seconds < 60 then
		return string.format("%ds", seconds)
	end
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %dm", h, m)
	end
	if m >= 10 then
		return string.format("%dm", m)
	end
	return string.format("%dm %ds", m, s)
end

--- Wall-clock stamp for milestones (survives /reload; GetTime does not).
local function NowStamp()
	if GetServerTime then
		return GetServerTime()
	end
	return time()
end

local function CharacterMarksKey()
	local name = UnitName("player") or "?"
	local realm = (GetRealmName and GetRealmName()) or "Realm"
	return name .. "-" .. realm
end

local function CharacterMarksRoot()
	local db = EnsureDB()
	if type(db.levelMarks) ~= "table" then
		db.levelMarks = {}
	end
	local key = CharacterMarksKey()
	if type(db.levelMarks[key]) ~= "table" then
		db.levelMarks[key] = {}
	end
	return db.levelMarks[key]
end

local function LevelMarksTable(level)
	local root = CharacterMarksRoot()
	local key = tostring(level)
	if type(root[key]) ~= "table" then
		root[key] = {}
	end
	return root[key]
end

local function GetMarkTime(marks, mark)
	if not marks then
		return nil
	end
	return marks[tostring(mark)] or marks[mark]
end

--- Stamp a 10% milestone once (0, 10, …, 100). Never overwrites.
local function StampMark(level, mark, when)
	level = tonumber(level)
	mark = tonumber(mark)
	if not level or mark == nil then
		return
	end
	local marks = LevelMarksTable(level)
	local key = tostring(mark)
	if marks[key] == nil then
		marks[key] = when or NowStamp()
		log:Debug("milestone Lv", level, mark .. "%")
	end
end

--- Record any newly reached 10% marks for the current level (not retroactive).
local function RecordMilestones()
	local level = UnitLevel("player")
	if not level or level < 1 then
		return
	end
	local maxXP = GetPlayerXPMax()
	if not maxXP or maxXP <= 0 then
		return
	end
	local pct = (GetPlayerXP() / maxXP) * 100
	-- Only stamp 0% when actually at the start of the level.
	if pct < 0.5 then
		StampMark(level, 0)
	end
	local reached = math.floor(pct / 10 + 1e-9) * 10
	if reached > 90 then
		reached = 90
	end
	for mark = 10, reached, 10 do
		StampMark(level, mark)
	end
end

local function OnLevelUpMilestones(newLevel)
	newLevel = tonumber(newLevel)
	if not newLevel or newLevel < 2 then
		return
	end
	StampMark(newLevel - 1, 100)
	StampMark(newLevel, 0)
end

local function ClearLevelMarks()
	local db = EnsureDB()
	if type(db.levelMarks) ~= "table" then
		db.levelMarks = {}
		return
	end
	db.levelMarks[CharacterMarksKey()] = {}
end

--- Lines for chat and the Information panel (level→level + per-10% splits).
local function GetLevelTimesLines()
	local root = CharacterMarksRoot()
	local levels = {}
	for k in pairs(root) do
		local n = tonumber(k)
		if n then
			levels[#levels + 1] = n
		end
	end
	table.sort(levels)
	local lines = {}
	if #levels == 0 then
		lines[1] = "No milestone data yet — play to record 10% marks."
		return lines
	end
	lines[#lines + 1] = CharacterMarksKey()
	for _, level in ipairs(levels) do
		local marks = root[tostring(level)]
		local t0 = GetMarkTime(marks, 0)
		local t100 = GetMarkTime(marks, 100)
		if t0 and t100 then
			lines[#lines + 1] = string.format(
				"Lv %d → %d: %s",
				level,
				level + 1,
				FormatDuration(t100 - t0)
			)
		elseif t0 then
			lines[#lines + 1] = string.format(
				"Lv %d: in progress · %s so far",
				level,
				FormatDuration(NowStamp() - t0)
			)
		else
			lines[#lines + 1] = string.format("Lv %d: partial (joined mid-level)", level)
		end
		for mark = 0, 90, 10 do
			local a = GetMarkTime(marks, mark)
			local b = GetMarkTime(marks, mark + 10)
			if a and b then
				lines[#lines + 1] = string.format(
					"  %d–%d%%: %s",
					mark,
					mark + 10,
					FormatDuration(b - a)
				)
			end
		end
	end
	return lines
end

local function PrintLevelTimes()
	local lines = GetLevelTimesLines()
	print("|cff33ccff[WenDing]|r Level times")
	for i = 1, #lines do
		print("  " .. lines[i])
	end
end

Addon.GetLevelTimesLines = GetLevelTimesLines
Addon.PrintLevelTimes = PrintLevelTimes
Addon.ClearLevelMarks = ClearLevelMarks
Addon.RecordMilestones = RecordMilestones

local function TrimOldSamples(now)
	local cutoff = now - SAMPLE_WINDOW
	while #samples > 1 and samples[1].t < cutoff do
		-- Keep at least one sample at or before the window edge so rate
		-- still covers the full window when activity is continuous.
		if samples[2] and samples[2].t <= cutoff then
			table.remove(samples, 1)
		else
			break
		end
	end
end

local function ClearSamples()
	for i = #samples, 1, -1 do
		samples[i] = nil
	end
	lastAbsXP = nil
	lastAbsMax = nil
	cumulativeXP = 0
	lastXpGainAt = nil
	ignorePaceUntil = nil
end

--- Remember current UnitXP without creating a pace sample.
--- Avoids login→first-kill looking like a real rate (idle time in the denominator).
local function SeedBaseline()
	lastAbsXP = GetPlayerXP()
	lastAbsMax = GetPlayerXPMax()
	cumulativeXP = 0
	lastXpGainAt = nil
end

--- Move abs XP baseline to current UnitXP without adding to cumulative pace.
--- Used for quest turn-ins: remaining/ETA refresh, XP/hr stays kill-based.
local function AbsorbXpIntoBaseline()
	lastAbsXP = GetPlayerXP()
	lastAbsMax = GetPlayerXPMax()
end

--- Advance the monotonic XP counter, bridging level-ups.
--- When UnitXP drops (new level), credit the remainder of the old level + current XP.
local function AccumulatePlayerXP()
	local xp = GetPlayerXP()
	local maxXP = GetPlayerXPMax()
	if lastAbsXP ~= nil and lastAbsMax ~= nil then
		if maxXP == lastAbsMax and xp >= lastAbsXP then
			cumulativeXP = cumulativeXP + (xp - lastAbsXP)
		else
			-- Level-up (or max changed): old remainder + XP already into the new level.
			cumulativeXP = cumulativeXP + math.max(0, lastAbsMax - lastAbsXP) + math.max(0, xp)
		end
	end
	lastAbsXP = xp
	lastAbsMax = maxXP
	return cumulativeXP
end

local function RecordSample()
	local now = GetTime()
	-- Quest XP: sync baseline only — do not feed XP/hr samples.
	if ignorePaceUntil and now < ignorePaceUntil then
		AbsorbXpIntoBaseline()
		return
	end
	local prevTotal = cumulativeXP
	local total = AccumulatePlayerXP()
	-- No XP change → not a pace sample (ignore spurious XP events).
	if total == prevTotal and #samples > 0 then
		return
	end
	-- First ever gain: start the window here (not at login).
	local last = samples[#samples]
	if last and last.xp == total and (now - last.t) < 0.05 then
		return
	end
	samples[#samples + 1] = { t = now, xp = total }
	if total > prevTotal then
		lastXpGainAt = now
	end
	TrimOldSamples(now)
	log:Debug("sample cumXP=", total, "abs=", lastAbsXP, "n=", #samples)
end

--- Same cumulative XP, newer timestamp — lets idle time dilute XP/hr.
local function RecordIdleHeartbeat()
	if #samples == 0 then
		return
	end
	local now = GetTime()
	local last = samples[#samples]
	if last and (now - last.t) < (IDLE_HEARTBEAT - 0.5) then
		return
	end
	samples[#samples + 1] = { t = now, xp = cumulativeXP }
	TrimOldSamples(now)
	log:Debug("idle heartbeat n=", #samples, "idle=", lastXpGainAt and (now - lastXpGainAt) or "?")
end

local function TickIdlePace(elapsed)
	idleTickerElapsed = idleTickerElapsed + elapsed
	if idleTickerElapsed < 1 then
		return
	end
	idleTickerElapsed = 0

	if not lastXpGainAt or #samples == 0 then
		return
	end

	local now = GetTime()
	local idleFor = now - lastXpGainAt
	if idleFor >= IDLE_CLEAR then
		ClearSamples()
		SeedBaseline()
		UpdateUI()
		if Addon.RefreshPanel then
			Addon.RefreshPanel()
		end
		log:Info("pace cleared — idle ", IDLE_CLEAR, "s")
		return
	end

	if idleFor >= IDLE_HEARTBEAT then
		RecordIdleHeartbeat()
		UpdateUI()
	end
end

--- XP per second from the rolling window, or nil if not enough data.
--- Uses cumulative XP so the rate survives level-ups; ETA then applies that
--- rate to the new level's remaining XP.
local function GetXPPerSecond()
	-- Need at least two XP-gain samples (e.g. two kills), not login+one kill.
	if #samples < 2 then
		return nil
	end
	local first = samples[1]
	local last = samples[#samples]
	local elapsed = last.t - first.t
	if elapsed < MIN_ELAPSED then
		return nil
	end
	local gained = last.xp - first.xp
	if gained <= 0 then
		return nil
	end
	return gained / elapsed
end

local function GetPaceSnapshot()
	local remaining = GetRemainingXP()
	local maxXP = GetPlayerXPMax()
	local current = GetPlayerXP()
	local level = UnitLevel("player") or 0
	local pct = 0
	if maxXP > 0 then
		pct = (current / maxXP) * 100
	end

	local xps = GetXPPerSecond()
	local xpPerHour = xps and (xps * 3600) or nil
	local eta = (xps and xps > 0) and (remaining / xps) or nil

	return {
		level = level,
		pct = pct,
		remaining = remaining,
		xpPerHour = xpPerHour,
		eta = eta,
		sampleCount = #samples,
	}
end

local function FormatStatusLine(snap)
	snap = snap or GetPaceSnapshot()
	local pace
	if snap.xpPerHour then
		pace = string.format(
			"%s XP/hr · ETA %s",
			FormatNumber(snap.xpPerHour),
			FormatDuration(snap.eta)
		)
	else
		pace = ""
	end
	if pace ~= "" then
		return string.format(
			"Lv %d (%.1f%%) · %s XP left · %s",
			snap.level,
			snap.pct,
			FormatNumber(snap.remaining),
			pace
		)
	end
	return string.format(
		"Lv %d (%.1f%%) · %s XP left",
		snap.level,
		snap.pct,
		FormatNumber(snap.remaining)
	)
end

--- Visible UI width (UIParent). Center X is width/2 — no other frames involved.
local function GetVisibleUIWidth()
	return UIParent:GetWidth() or 800
end

--- Horizontal center of a frame as an offset from visible-UI center.
local function GetScreenCenterOffset(region)
	if not region then
		return nil
	end
	local left, right = region:GetLeft(), region:GetRight()
	if not (left and right) then
		return nil
	end
	return ((left + right) / 2) - (GetVisibleUIWidth() / 2)
end

--- db.x = offset from visible UI center (0 = dead center of the screen).
--- db.y = offset from UIParent bottom (gutter).
--- SetPoint BOTTOM/BOTTOM so the bar's midpoint sits on that X.
local function SetCenterBottom(x, y)
	if not frame then
		return
	end
	x = tonumber(x) or 0
	y = tonumber(y) or 0
	local db = EnsureDB()
	db.point = "BOTTOM"
	db.relativePoint = "BOTTOM"
	db.x = x
	db.y = y
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOM", UIParent, "BOTTOM", x, y)
end

--- Snap distance (px) to default X/Y when dropping the bar.
local SNAP_PX = 12

--- 1px sharp border around the fill (no stretched Blizzard border art).
local BORDER_SIZE = 1
--- Default XP fill size; adjustable via Layout / Edit Mode.
local DEFAULT_BAR_HEIGHT = 13
local DEFAULT_BAR_WIDTH = 1000
local MIN_BAR_HEIGHT = 8
local MAX_BAR_HEIGHT = 28
local MIN_BAR_WIDTH = 400
local MAX_BAR_WIDTH = 1400
--- Major tick every N segments (thicker divider).
local XP_MAJOR_EVERY = 5
local BORDER_COLOR = { r = 0.15, g = 0.15, b = 0.15, a = 1 }
-- Mutable UIParent-relative default (LibEditMode reset reads this table by ref).
local defaultPos = {
	point = "BOTTOM",
	x = 0,
	y = 36,
}
local originalPos -- { x, y } center-BOTTOM offsets; Reset restores these
local widthSetting
local heightSetting

-- Forward decls used by width + Edit Mode helpers defined below LayoutXpDivs.
local LayoutXpDivs
local ApplyBarSize

local function ClampBarWidth(width)
	width = math.floor((tonumber(width) or 0) + 0.5)
	return math.max(MIN_BAR_WIDTH, math.min(MAX_BAR_WIDTH, width))
end

local function ClampBarHeight(height)
	height = math.floor((tonumber(height) or 0) + 0.5)
	return math.max(MIN_BAR_HEIGHT, math.min(MAX_BAR_HEIGHT, height))
end

local function GetDefaultBarWidth()
	return ClampBarWidth(DEFAULT_BAR_WIDTH)
end

local function GetBarWidth()
	local db = EnsureDB()
	local w = tonumber(db.barWidth)
	if w then
		return ClampBarWidth(w)
	end
	return GetDefaultBarWidth()
end

local function GetBarHeight()
	local db = EnsureDB()
	local h = tonumber(db.barHeight)
	if h then
		return ClampBarHeight(h)
	end
	return DEFAULT_BAR_HEIGHT
end

Addon.GetBarWidth = GetBarWidth
Addon.GetBarHeight = GetBarHeight
Addon.DEFAULT_BAR_HEIGHT = DEFAULT_BAR_HEIGHT
Addon.MIN_BAR_HEIGHT = MIN_BAR_HEIGHT
Addon.MAX_BAR_HEIGHT = MAX_BAR_HEIGHT
Addon.MIN_BAR_WIDTH = MIN_BAR_WIDTH
Addon.MAX_BAR_WIDTH = MAX_BAR_WIDTH

local function SetBarWidth(width)
	width = ClampBarWidth(width)
	EnsureDB().barWidth = width
	ApplyBarSize(width, GetBarHeight())
	if Addon.RefreshPanel then
		Addon.RefreshPanel()
	end
	return width
end

local function SetBarHeight(height)
	height = ClampBarHeight(height)
	EnsureDB().barHeight = height
	ApplyBarSize(GetBarWidth(), height)
	if Addon.RefreshPanel then
		Addon.RefreshPanel()
	end
	return height
end

Addon.SetBarWidth = SetBarWidth
Addon.SetBarHeight = SetBarHeight

--- Extra lift above MicroMenuContainer:GetTop() so the bar sits in Forever's XP gutter.
--- (Flush GetTop() is typically ~5px too low once border/padding are accounted for.)
local GUTTER_Y_OFFSET = 5

--- Y for the Forever XP gutter: MicroMenu/Bags top + offset.
--- Used as SetPoint("BOTTOM", UIParent, "BOTTOM", x, y) → frame bottom at that Y.
local function GetGutterY()
	local below = MicroMenuContainer or BagsBar
	if below and below.GetTop and below:GetTop() then
		local top = below:GetTop()
		if top and top > 1 then
			return top + GUTTER_Y_OFFSET
		end
	end
	local action = MainActionBar
	if action and action.GetBottom and action:GetBottom() then
		local y = action:GetBottom() - 16
		if y and y > 1 then
			return y + GUTTER_Y_OFFSET
		end
	end
	return 36 + GUTTER_Y_OFFSET
end

--- Snapshot gutter Y once (call before HideDefaultExpBar).
--- Default X is always 0 = center of visible UI (UIParent width / 2).
local function CaptureNativeLayout()
	local y = GetGutterY()

	originalPos = { x = 0, y = y }
	defaultPos.point = "BOTTOM"
	defaultPos.x = 0
	defaultPos.y = y
	log:Debug(
		"captured XP layout x=0 (uiW=",
		GetVisibleUIWidth(),
		") y=",
		y,
		"defaultSize=",
		DEFAULT_BAR_WIDTH,
		"x",
		DEFAULT_BAR_HEIGHT
	)
	return true
end

--- Keep defaultPos in sync. Prefer the one-time gutter snapshot for Reset.
local function RefreshDefaults()
	defaultPos.point = "BOTTOM"
	defaultPos.x = 0

	-- Repair a bad sticky Y=0 from an earlier login capture.
	if originalPos and (tonumber(originalPos.y) or 0) <= 1 then
		originalPos.y = GetGutterY()
	end

	if originalPos then
		defaultPos.y = originalPos.y
	else
		defaultPos.y = GetGutterY()
		originalPos = { x = 0, y = defaultPos.y }
	end

	if widthSetting then
		widthSetting.default = GetDefaultBarWidth()
	end
	if heightSetting then
		heightSetting.default = DEFAULT_BAR_HEIGHT
	end
end

local function ApplyDefaultPosition()
	if not frame then
		return
	end
	RefreshDefaults()
	SetCenterBottom(defaultPos.x, defaultPos.y)
end

local function GetFramePosition()
	local db = EnsureDB()
	if db.x ~= nil and db.y ~= nil then
		return db.x, db.y
	end
	RefreshDefaults()
	return defaultPos.x, defaultPos.y
end

local function ResetFramePosition()
	RefreshDefaults()
	local y = GetGutterY()
	originalPos = { x = 0, y = y }
	defaultPos.x = 0
	defaultPos.y = y
	SetCenterBottom(0, y)
	-- Restore original width/height so Reset lands on the true stock layout.
	local db = EnsureDB()
	db.barWidth = nil
	db.barHeight = nil
	ApplyBarSize(GetDefaultBarWidth(), GetBarHeight())
	log:Info("position reset to UI center", 0, y, "uiW=", GetVisibleUIWidth())
	if Addon.RefreshPanel then
		Addon.RefreshPanel()
	end
end

Addon.GetFramePosition = GetFramePosition
Addon.ResetFramePosition = ResetFramePosition
Addon.SetFramePosition = SetCenterBottom

local function ApplyDefaultsIfUnsaved()
	local db = EnsureDB()
	RefreshDefaults()
	if not (db.point and db.x ~= nil and db.y ~= nil) then
		ApplyDefaultPosition()
	end
	if db.barWidth == nil or db.barHeight == nil then
		ApplyBarSize(GetBarWidth(), GetBarHeight())
	end
end

local function ApplySavedPosition()
	if not frame then
		return
	end
	local db = EnsureDB()
	if db.x ~= nil and db.y ~= nil then
		local point = db.point or "BOTTOM"
		local relative = db.relativePoint or point
		if point == "BOTTOM" and relative == "BOTTOM" then
			SetCenterBottom(db.x, db.y)
		else
			-- Legacy corner/edge save: place, then normalize to center-BOTTOM.
			frame:ClearAllPoints()
			frame:SetPoint(point, UIParent, relative, db.x, db.y)
			SaveFramePosition()
		end
	else
		ApplyDefaultPosition()
	end
end

--- Overlay zones: left = %, center = current/max XP, right = pace/ETA.
local function FormatOverlayZones(snap)
	local db = EnsureDB()
	local current = GetPlayerXP()
	local maxXP = GetPlayerXPMax()

	local left = ""
	if db.showPct ~= false then
		left = string.format("%.1f%%", snap.pct)
	end

	local center = ""
	if db.showXP ~= false then
		center = string.format("%s / %s", FormatNumber(current), FormatNumber(maxXP))
	end

	local rightParts = {}
	if db.showXPPerHour ~= false and snap.xpPerHour then
		rightParts[#rightParts + 1] = string.format("%s XP/hr", FormatNumber(snap.xpPerHour))
	end
	if db.showETA ~= false and snap.xpPerHour then
		rightParts[#rightParts + 1] = string.format("ETA %s", FormatDuration(snap.eta))
	end
	local right = #rightParts > 0 and table.concat(rightParts, "  ·  ") or ""

	return left, center, right
end

local function LayoutSharpBorder()
	if not frame or not frame.bar or not frame.borderEdges then
		return
	end
	local bar = frame.bar
	local e = frame.borderEdges
	local s = BORDER_SIZE
	e.top:ClearAllPoints()
	e.top:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", -s, 0)
	e.top:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", s, 0)
	e.top:SetHeight(s)

	e.bottom:ClearAllPoints()
	e.bottom:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -s, 0)
	e.bottom:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", s, 0)
	e.bottom:SetHeight(s)

	e.left:ClearAllPoints()
	e.left:SetPoint("TOPLEFT", bar, "TOPLEFT", -s, 0)
	e.left:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -s, 0)
	e.left:SetWidth(s)

	e.right:ClearAllPoints()
	e.right:SetPoint("TOPRIGHT", bar, "TOPRIGHT", s, 0)
	e.right:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", s, 0)
	e.right:SetWidth(s)
end

--- Place the 19 tick marks that create 20 equal XP segments.
--- Every XP_MAJOR_EVERY-th boundary gets a thicker divider.
LayoutXpDivs = function()
	local bar = frame and frame.bar
	if not bar or not bar.divs then
		return
	end
	local width = bar:GetWidth()
	if not width or width <= 0 then
		return
	end
	local divWidth = width / XP_SEGMENTS
	local xpos = divWidth
	for i = 1, XP_SEGMENTS - 1 do
		local tick = bar.divs[i]
		local major = (i % XP_MAJOR_EVERY) == 0
		local tickW = major and 2 or 1
		local x = math.floor(xpos + 0.5)
		tick:SetWidth(tickW)
		tick:ClearAllPoints()
		-- Center the thicker tick on the segment boundary.
		tick:SetPoint("TOP", bar, "TOPLEFT", x, 0)
		tick:SetPoint("BOTTOM", bar, "BOTTOMLEFT", x, 0)
		xpos = xpos + divWidth
	end
end

ApplyBarSize = function(width, height)
	if not frame or not frame.bar then
		return
	end
	width = ClampBarWidth(width or GetBarWidth())
	height = ClampBarHeight(height or GetBarHeight())
	local frameH = height + BORDER_SIZE * 2

	-- Keep the visual center fixed so size changes don't slide the bar.
	local x, bottom
	local db = EnsureDB()
	if db.x ~= nil and db.y ~= nil then
		x, bottom = db.x, db.y
	else
		x = GetScreenCenterOffset(frame)
		bottom = frame:GetBottom()
	end

	frame:SetSize(width + BORDER_SIZE * 2, frameH)
	frame.bar:SetSize(width, height)
	LayoutSharpBorder()
	if frame.labels then
		local fontSize = height >= 16 and 12 or (height >= 13 and 11 or 10)
		for _, label in ipairs(frame.labels) do
			if label.SetFont then
				local fontPath, _, fontFlags = label:GetFont()
				if fontPath then
					label:SetFont(fontPath, fontSize, fontFlags)
				end
			end
		end
	end
	LayoutXpDivs()

	if x ~= nil and bottom ~= nil then
		SetCenterBottom(x, bottom)
	end
end

-- Back-compat alias used by older call sites.
local function ApplyBarWidth(width)
	ApplyBarSize(width, GetBarHeight())
end

--- Register with Forever Edit Mode via vendored LibEditMode.
local function RegisterEditMode(target)
	if not LibStub then
		log:Warn("LibStub missing — Edit Mode registration skipped")
		return
	end
	local lem = LibStub("LibEditMode", true)
	if not lem then
		log:Warn("LibEditMode missing — Edit Mode registration skipped")
		return
	end

	RefreshDefaults()

	lem:AddFrame(target, function(f, _layoutName, point, x, y)
		-- Normalize whatever Edit Mode passes into center-BOTTOM + UI-center X.
		f:ClearAllPoints()
		f:SetPoint(point, UIParent, point, x, y)
		SaveFramePosition()
	end, defaultPos, "WenDing")

	lem:RegisterCallback("enter", function()
		RefreshDefaults()
	end)

	widthSetting = {
		name = "Width",
		kind = lem.SettingType.Slider,
		default = GetDefaultBarWidth(),
		minValue = MIN_BAR_WIDTH,
		maxValue = MAX_BAR_WIDTH,
		valueStep = 10,
		formatter = function(value)
			return math.floor((tonumber(value) or 0) + 0.5)
		end,
		get = function()
			return GetBarWidth()
		end,
		set = function(_layoutName, value)
			EnsureDB().barWidth = value
			ApplyBarSize(value, GetBarHeight())
		end,
	}
	heightSetting = {
		name = "Height",
		kind = lem.SettingType.Slider,
		default = DEFAULT_BAR_HEIGHT,
		minValue = MIN_BAR_HEIGHT,
		maxValue = MAX_BAR_HEIGHT,
		valueStep = 1,
		formatter = function(value)
			return math.floor((tonumber(value) or 0) + 0.5)
		end,
		get = function()
			return GetBarHeight()
		end,
		set = function(_layoutName, value)
			EnsureDB().barHeight = value
			ApplyBarSize(GetBarWidth(), value)
		end,
	}
	lem:AddFrameSettings(target, { widthSetting, heightSetting })
end

local function UpdateUI()
	RecordMilestones()
	if not frame or not frame:IsShown() then
		return
	end
	local snap = GetPaceSnapshot()
	local current = GetPlayerXP()
	local maxXP = GetPlayerXPMax()
	if maxXP <= 0 then
		maxXP = 1
	end
	frame.bar:SetMinMaxValues(0, maxXP)
	frame.bar:SetValue(math.min(current, maxXP))
	LayoutXpDivs()
	local left, center, right = FormatOverlayZones(snap)
	if frame.labelLeft then
		frame.labelLeft:SetText(left)
	end
	if frame.labelCenter then
		frame.labelCenter:SetText(center)
	end
	if frame.labelRight then
		frame.labelRight:SetText(right)
	end
end

local function RefreshBarOverlay()
	UpdateUI()
	if Addon.RefreshPanel then
		Addon.RefreshPanel()
	end
end

Addon.RefreshBarOverlay = RefreshBarOverlay

local function EnsureXPOverride()
	if xpOverride == nil then
		xpOverride = UnitXP("player") or 0
		xpMaxOverride = UnitXPMax("player") or 1
	end
	if not xpMaxOverride or xpMaxOverride <= 0 then
		xpMaxOverride = 1
	end
end

local function SetXPOverride(current, maxXP)
	current = math.max(0, math.floor(tonumber(current) or 0))
	maxXP = math.max(1, math.floor(tonumber(maxXP) or (UnitXPMax("player") or 1)))
	if current > maxXP then
		current = maxXP
	end
	xpOverride = current
	xpMaxOverride = maxXP
	-- Align pace baseline so the next kill/sim gain is measured from here.
	AbsorbXpIntoBaseline()
	UpdateUI()
	if Addon.RefreshPanel then
		Addon.RefreshPanel()
	end
end

local function ClearXPOverride()
	xpOverride = nil
	xpMaxOverride = nil
	AbsorbXpIntoBaseline()
	UpdateUI()
	if Addon.RefreshPanel then
		Addon.RefreshPanel()
	end
end

--- Dev: fake a kill — feeds XP/hr pace samples.
local function SimulateKill(amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then
		return false
	end
	EnsureXPOverride()
	xpOverride = math.min(xpMaxOverride, xpOverride + amount)
	ignorePaceUntil = nil
	RecordSample()
	UpdateUI()
	if Addon.RefreshPanel then
		Addon.RefreshPanel()
	end
	log:Info("sim kill +", amount, "xp=", xpOverride, "/", xpMaxOverride)
	return true
end

--- Dev: fake a quest turn-in — refreshes ETA/remaining, does not feed XP/hr.
local function SimulateQuestTurnIn(amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then
		return false
	end
	EnsureXPOverride()
	xpOverride = math.min(xpMaxOverride, xpOverride + amount)
	ignorePaceUntil = GetTime() + QUEST_PACE_IGNORE
	AbsorbXpIntoBaseline()
	UpdateUI()
	if Addon.RefreshPanel then
		Addon.RefreshPanel()
	end
	log:Info("sim quest +", amount, "xp=", xpOverride, "/", xpMaxOverride, "(pace unchanged)")
	return true
end

Addon.SetXPOverride = SetXPOverride
Addon.ClearXPOverride = ClearXPOverride
Addon.SimulateKill = SimulateKill
Addon.SimulateQuestTurnIn = SimulateQuestTurnIn
Addon.IsXPOverrideActive = function()
	return xpOverride ~= nil
end
Addon.GetXPOverride = function()
	return xpOverride, xpMaxOverride
end
Addon.GetLivePlayerXP = function()
	return UnitXP("player") or 0, UnitXPMax("player") or 0
end

local function SetFrameShown(shown)
	local db = EnsureDB()
	db.shown = shown and true or false
	if not frame then
		return
	end
	if shown then
		frame:Show()
		uiElapsed = 0
		UpdateUI()
	else
		frame:Hide()
	end
end

local function CreateUI()
	if frame then
		return frame
	end

	local barWidth = GetBarWidth()
	local barHeight = GetBarHeight()

	frame = CreateFrame("Frame", "WenDingFrame", UIParent)
	frame:SetSize(barWidth + BORDER_SIZE * 2, barHeight + BORDER_SIZE * 2)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		-- Ctrl+click opens settings; don't start a drag while Ctrl is held.
		if IsControlKeyDown and IsControlKeyDown() then
			return
		end
		isDragging = true
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		isDragging = false
		self:StopMovingOrSizing()
		SaveFramePosition()
		SyncPanelPositionFields()
		if Addon.RefreshPanel then
			Addon.RefreshPanel()
		end
	end)
	frame:SetScript("OnMouseUp", function(_, button)
		if button ~= "LeftButton" then
			return
		end
		if IsControlKeyDown and IsControlKeyDown() and Addon.TogglePanel then
			Addon.TogglePanel()
		end
	end)
	frame:SetScript("OnUpdate", function(_, elapsed)
		if isDragging then
			SyncPanelPositionFields()
		end
		uiElapsed = uiElapsed + elapsed
		if uiElapsed < UI_TICK then
			return
		end
		uiElapsed = 0
		UpdateUI()
	end)
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata("MEDIUM")
	frame:SetFrameLevel(10)

	local bar = CreateFrame("StatusBar", nil, frame)
	bar:SetSize(barWidth, barHeight)
	bar:SetPoint("CENTER", frame, "CENTER", 0, 0)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar:SetStatusBarTexture(STATUS_BAR_TEX)
	frame.bar = bar

	-- Empty track underlay (color + opacity come from style settings).
	local barBg = bar:CreateTexture(nil, "BACKGROUND")
	barBg:SetAllPoints()
	frame.barBg = barBg

	-- Sharp 1px border (4 edges). Stretched UI-StatusBar-Border was causing blurry bevels.
	local function MakeEdge()
		local edge = frame:CreateTexture(nil, "OVERLAY", nil, 7)
		SetSolidColor(edge, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, BORDER_COLOR.a)
		return edge
	end
	frame.borderEdges = {
		top = MakeEdge(),
		bottom = MakeEdge(),
		left = MakeEdge(),
		right = MakeEdge(),
	}
	LayoutSharpBorder()

	-- 19 crisp tick marks → 20 equal segments (no XP-Bar rivet art).
	bar.divs = {}
	for i = 1, XP_SEGMENTS - 1 do
		local tick = bar:CreateTexture(nil, "OVERLAY", nil, 0)
		tick:SetWidth(1)
		SetSolidColor(tick, 0.0, 0.0, 0.0, 0.85)
		bar.divs[i] = tick
	end
	LayoutXpDivs()

	local LABEL_PAD = 6
	local function MakeBarLabel(justify)
		local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetJustifyH(justify)
		if justify == "LEFT" then
			label:SetPoint("LEFT", bar, "LEFT", LABEL_PAD, 0)
		elseif justify == "RIGHT" then
			label:SetPoint("RIGHT", bar, "RIGHT", -LABEL_PAD, 0)
		else
			label:SetPoint("CENTER", bar, "CENTER", 0, 0)
		end
		if label.SetShadowColor then
			label:SetShadowColor(0, 0, 0, 1)
			label:SetShadowOffset(1, -1)
		end
		return label
	end
	frame.labelLeft = MakeBarLabel("LEFT")
	frame.labelCenter = MakeBarLabel("CENTER")
	frame.labelRight = MakeBarLabel("RIGHT")
	frame.labels = { frame.labelLeft, frame.labelCenter, frame.labelRight }

	ApplyBarStyle()
	ApplyBarSize(barWidth, barHeight)
	ApplySavedPosition()
	RegisterEditMode(frame)
	return frame
end

local function ResetPace(reason)
	ClearSamples()
	SeedBaseline()
	UpdateUI()
	if Addon.RefreshPanel then
		Addon.RefreshPanel()
	end
	log:Info("pace reset", reason or "")
end

local function PrintHelp()
	print("|cff33ccff[WenDing]|r /wd — open settings panel")
	print("|cff33ccff[WenDing]|r Ctrl+click XP bar — open settings panel")
	print("|cff33ccff[WenDing]|r /wd status — print pace status")
	print("|cff33ccff[WenDing]|r /wd times — level→level and per-10% durations")
	print("|cff33ccff[WenDing]|r /wd times clear — wipe milestone times for this character")
	print("|cff33ccff[WenDing]|r /wd show|hide|toggle — HUD visibility")
	print("|cff33ccff[WenDing]|r /wd reset — restart pace sampling")
end

local function OnSlash(msg)
	msg = (msg and msg:match("^%s*(.-)%s*$")) or ""
	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	cmd = cmd and string.lower(cmd) or ""
	rest = rest and string.lower(rest) or ""

	if cmd == "dev" then
		WoWF.ToggleDevMode(ADDON_NAME, rest)
		return
	end

	if cmd == "times" or cmd == "levels" then
		if rest == "clear" then
			ClearLevelMarks()
			print("|cff33ccff[WenDing]|r Cleared level milestone times for this character.")
		else
			PrintLevelTimes()
		end
		return
	end

	if cmd == "help" or cmd == "?" then
		PrintHelp()
		return
	end

	if cmd == "show" then
		SetFrameShown(true)
		print("|cff33ccff[WenDing]|r HUD shown.")
		return
	end

	if cmd == "hide" then
		SetFrameShown(false)
		print("|cff33ccff[WenDing]|r HUD hidden.")
		return
	end

	if cmd == "toggle" then
		local db = EnsureDB()
		SetFrameShown(not db.shown)
		print("|cff33ccff[WenDing]|r HUD " .. (EnsureDB().shown and "shown." or "hidden."))
		return
	end

	if cmd == "reset" then
		ResetPace("slash")
		print("|cff33ccff[WenDing]|r Pace sampling restarted.")
		print("|cff33ccff[WenDing]|r " .. FormatStatusLine())
		return
	end

	if cmd == "status" then
		print("|cff33ccff[WenDing]|r " .. FormatStatusLine())
		return
	end

	-- Bare /wd opens the settings panel.
	if Addon.TogglePanel then
		Addon.TogglePanel()
	else
		print("|cff33ccff[WenDing]|r " .. FormatStatusLine())
	end
end

--- Coalesce XP events into one sample next frame so UnitXP has settled.
local samplePending = false
local questAbsorbPending = false

local function RequestSample(reason)
	if samplePending then
		return
	end
	samplePending = true
	local defer = CreateFrame("Frame")
	defer:SetScript("OnUpdate", function(self)
		self:SetScript("OnUpdate", nil)
		samplePending = false
		RecordSample()
		UpdateUI()
		if reason == "level-up" then
			log:Info("level up — pace carried forward", "cumXP=", cumulativeXP)
		end
	end)
end

--- Quest turn-in: refresh bar/ETA from new remaining XP, but keep XP/hr kill-based.
local function RequestQuestAbsorb()
	ignorePaceUntil = GetTime() + QUEST_PACE_IGNORE
	if questAbsorbPending then
		return
	end
	questAbsorbPending = true
	local defer = CreateFrame("Frame")
	defer:SetScript("OnUpdate", function(self)
		self:SetScript("OnUpdate", nil)
		questAbsorbPending = false
		AbsorbXpIntoBaseline()
		UpdateUI()
		log:Debug("quest XP absorbed into baseline (pace unchanged)")
	end)
end

local eventFrame = CreateFrame("Frame")
-- Must be shown for OnUpdate (idle heartbeats / session clear).
eventFrame:Show()
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_XP_UPDATE")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
eventFrame:SetScript("OnUpdate", function(_, elapsed)
	TickIdlePace(elapsed)
end)
eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		EnsureDB()
		return
	end

	if event == "PLAYER_LOGIN" then
		-- Snapshot Forever's XP bar before we hide it — Reset restores this.
		if not CaptureNativeLayout() then
			RefreshDefaults()
		end
		HideDefaultExpBar()
		RefreshDefaults()
		CreateUI()
		SetFrameShown(EnsureDB().shown)
		SeedBaseline()
		UpdateUI()
		-- Action/micro bars may finish layout a frame later — re-center then.
		local defer = CreateFrame("Frame")
		defer:SetScript("OnUpdate", function(self)
			self:SetScript("OnUpdate", nil)
			CaptureNativeLayout()
			RefreshDefaults()
			ApplyDefaultsIfUnsaved()
			UpdateUI()
		end)
		log:Info("tracking XP pace — /wd for settings, /wd help for commands")
		return
	end

	if event == "PLAYER_LEVEL_UP" then
		OnLevelUpMilestones(arg1)
		RequestSample("level-up")
		return
	end

	-- Quest turn-ins change remaining XP (ETA) but must not inflate XP/hr.
	if event == "QUEST_TURNED_IN" then
		RequestQuestAbsorb()
		return
	end

	-- Kills / other XP: feed the pace window (skipped while quest ignore is active).
	if event == "PLAYER_XP_UPDATE" or event == "CHAT_MSG_COMBAT_XP_GAIN" then
		RequestSample(event)
	end
end)

SLASH_WENDING1 = "/wending"
SLASH_WENDING2 = "/wd"
SlashCmdList["WENDING"] = OnSlash

Addon.GetPaceSnapshot = GetPaceSnapshot
Addon.FormatStatusLine = FormatStatusLine
Addon.ResetPace = ResetPace
