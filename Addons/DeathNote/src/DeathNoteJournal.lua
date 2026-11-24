local FRAME_WIDTH = 780
local FRAME_HEIGHT = 640
local LIST_WIDTH = 220
local ROW_HEIGHT = 36
local LOG_ROW_HEIGHT = 32
local VISIBLE_LIST_ROWS = 9
local VISIBLE_LOG_ROWS = 6
local PAD = 16
local HEADER_H = 60
--- Obsidian panels, blood accents, bone-white ink.
local C = {
	void = { 0.035, 0.03, 0.032, 1 },
	bg = { 0.07, 0.06, 0.064, 0.98 },
	panel = { 0.105, 0.09, 0.095, 0.98 },
	panelHi = { 0.15, 0.125, 0.13, 1 },
	edge = { 0.3, 0.1, 0.12, 1 },
	blood = { 0.8, 0.12, 0.16, 1 },
	bloodDim = { 0.46, 0.07, 0.1, 1 },
	bone = { 0.96, 0.93, 0.87, 1 },
	ink = { 0.92, 0.9, 0.88, 1 },
	muted = { 0.64, 0.6, 0.58, 1 },
	faint = { 0.44, 0.41, 0.4, 1 },
	kill = { 0.45, 0.95, 0.55, 1 },
	death = { 1, 0.4, 0.4, 1 },
	combat = { 0.5, 0.78, 1, 1 },
	select = { 0.3, 0.06, 0.09, 1 },
	hover = { 0.85, 0.2, 0.25, 0.16 },
	rowA = { 1, 1, 1, 0.025 },
	rowB = { 1, 1, 1, 0.055 },
}

local RESULT_COLORS = {
	Kill = C.kill,
	Death = C.death,
	Combat = C.combat,
}

local LOG_FILTERS = { "All", "Kill", "Death", "Combat" }
local LOG_FILTER_LABELS = { All = "All", Kill = "Kills", Death = "Deaths", Combat = "Combat" }

local journal
local selectedName
local listOffset = 0
local logOffset = 0
local logFilter = "All"
local searchText = ""
local listButtons = {}
local logButtons = {}

-- Palette keys the shared UI expects (WoWF.UI, Common/UI).
C.accent = C.blood
C.accentDim = C.bloodDim

local UI = WoWF.UI
local SetSolidColor = UI.SetSolidColor
local Paint = UI.Paint
local Tint = UI.Tint
local MakeFont = UI.MakeFont
local MakeRule = UI.MakeRule

local function MakePanel(parent)
	return UI.MakePanel(parent, C)
end

local function MakeCenteredCross(btn, length, thickness)
	UI.MakeCenteredCross(btn, C.muted, length, thickness)
end

local function ClassColor(classFile)
	if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
		local c = RAID_CLASS_COLORS[classFile]
		return { c.r, c.g, c.b, 1 }
	end
	return C.bone
end

local CLASS_ICON_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

local function SetClassIcon(tex, classFile)
	local coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
	if coords then
		tex:SetTexture(CLASS_ICON_TEXTURE)
		tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	else
		tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
end

local function FormatAgo(t)
	if type(t) ~= "number" or not time then
		return "—"
	end
	local d = math.max(0, time() - t)
	if d < 60 then
		return "just now"
	end
	if d < 3600 then
		return math.floor(d / 60) .. "m ago"
	end
	if d < 86400 then
		return math.floor(d / 3600) .. "h ago"
	end
	if d < 86400 * 7 then
		return math.floor(d / 86400) .. "d ago"
	end
	return date("%b %d", t)
end

local function FormatRatio(kills, deaths)
	if kills == 0 and deaths == 0 then
		return "—"
	end
	if deaths == 0 then
		return string.format("%.1f", kills)
	end
	return string.format("%.2f", kills / deaths)
end

local BUTTON_STYLES = {
	primary = { fill = C.bloodDim, hover = C.blood, edge = C.blood, text = C.bone },
	ghost = { fill = C.panelHi, hover = { 0.22, 0.17, 0.18, 1 }, edge = C.edge, text = C.ink },
	danger = { fill = { 0.18, 0.05, 0.06, 1 }, hover = { 0.38, 0.08, 0.1, 1 }, edge = C.bloodDim, text = C.death },
}

local function MakeButton(parent, label, width, height, styleName)
	local style = BUTTON_STYLES[styleName or "ghost"]
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(width or 90, height or 24)
	btn:RegisterForClicks("LeftButtonUp")

	btn.edge = btn:CreateTexture(nil, "BACKGROUND")
	btn.edge:SetAllPoints()
	Paint(btn.edge, style.edge)
	btn.fill = btn:CreateTexture(nil, "BACKGROUND")
	btn.fill:SetDrawLayer("BACKGROUND", 1)
	btn.fill:SetPoint("TOPLEFT", 1, -1)
	btn.fill:SetPoint("BOTTOMRIGHT", -1, 1)
	Paint(btn.fill, style.fill)

	btn.label = MakeFont(btn, "GameFontNormalSmall", 11)
	btn.label:SetPoint("CENTER", 0, 0)
	btn.label:SetText(label)
	Tint(btn.label, style.text)

	btn:SetScript("OnEnter", function(self)
		if self:IsEnabled() then
			Paint(self.fill, style.hover)
		end
	end)
	btn:SetScript("OnLeave", function(self)
		if self:IsEnabled() then
			Paint(self.fill, style.fill)
		end
	end)
	btn:SetScript("OnDisable", function(self)
		Paint(self.fill, C.panel)
		Paint(self.edge, C.edge, 0.5)
		Tint(self.label, C.faint)
	end)
	btn:SetScript("OnEnable", function(self)
		Paint(self.fill, style.fill)
		Paint(self.edge, style.edge)
		Tint(self.label, style.text)
	end)

	function btn:SetLabel(text)
		self.label:SetText(text)
	end

	return btn
end

local function MakeTab(parent, label, width)
	local tab = CreateFrame("Button", nil, parent)
	tab:SetSize(width or 56, 18)
	tab.fill = tab:CreateTexture(nil, "BACKGROUND")
	tab.fill:SetAllPoints()
	tab.underline = tab:CreateTexture(nil, "ARTWORK")
	tab.underline:SetHeight(2)
	tab.underline:SetPoint("BOTTOMLEFT", 0, 0)
	tab.underline:SetPoint("BOTTOMRIGHT", 0, 0)
	Paint(tab.underline, C.blood)
	tab.label = MakeFont(tab, "GameFontNormalSmall", 10)
	tab.label:SetPoint("CENTER", 0, 1)
	tab.label:SetText(label)

	function tab:SetActive(active)
		self.active = active
		if active then
			Paint(self.fill, C.select)
			Tint(self.label, C.bone)
			self.underline:Show()
		else
			Paint(self.fill, C.panelHi, 0.6)
			Tint(self.label, C.muted)
			self.underline:Hide()
		end
	end

	tab:SetScript("OnEnter", function(self)
		if not self.active then
			Tint(self.label, C.ink)
		end
	end)
	tab:SetScript("OnLeave", function(self)
		if not self.active then
			Tint(self.label, C.muted)
		end
	end)

	tab:SetActive(false)
	return tab
end

--- Bright custom chrome so DevMode sim actions never look like normal UI.
local function CreateDevButton(parent, label, width, color)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetWidth(width or 90)
	btn:SetHeight(22)
	btn:EnableMouse(true)
	btn:RegisterForClicks("LeftButtonUp")

	btn.bg = btn:CreateTexture(nil, "BACKGROUND")
	btn.bg:SetAllPoints()
	SetSolidColor(btn.bg, color.r, color.g, color.b, color.a or 0.85)

	btn.border = btn:CreateTexture(nil, "BORDER")
	btn.border:SetPoint("TOPLEFT", -1, 1)
	btn.border:SetPoint("BOTTOMRIGHT", 1, -1)
	SetSolidColor(btn.border, color.br or 1, color.bg or 1, color.bb or 1, 0.9)
	btn.border:SetDrawLayer("BACKGROUND", -1)

	btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	btn.label:SetAllPoints()
	btn.label:SetJustifyH("CENTER")
	btn.label:SetText(label)
	btn.label:SetTextColor(color.tr or 1, color.tg or 1, color.tb or 1)

	btn:SetScript("OnEnter", function(self)
		SetSolidColor(self.bg, color.hr or color.r, color.hg or color.g, color.hb or color.b, 1)
	end)
	btn:SetScript("OnLeave", function(self)
		if self:IsEnabled() then
			SetSolidColor(self.bg, color.r, color.g, color.b, color.a or 0.85)
		else
			SetSolidColor(self.bg, 0.25, 0.25, 0.25, 0.6)
		end
	end)
	btn:SetScript("OnDisable", function(self)
		SetSolidColor(self.bg, 0.25, 0.25, 0.25, 0.6)
		self.label:SetTextColor(0.55, 0.55, 0.55)
	end)
	btn:SetScript("OnEnable", function(self)
		SetSolidColor(self.bg, color.r, color.g, color.b, color.a or 0.85)
		self.label:SetTextColor(color.tr or 1, color.tg or 1, color.tb or 1)
	end)

	return btn
end

-- Electric magenta (kill) / toxic lime (death) / ice cyan (combat).
local DEV_KILL_COLOR = {
	r = 0.95, g = 0.05, b = 0.75, a = 0.9,
	hr = 1.0, hg = 0.25, hb = 0.9,
	br = 1.0, bg = 0.7, bb = 1.0,
	tr = 1, tg = 1, tb = 1,
}
local DEV_DEATH_COLOR = {
	r = 0.55, g = 1.0, b = 0.05, a = 0.9,
	hr = 0.75, hg = 1.0, hb = 0.3,
	br = 0.9, bg = 1.0, bb = 0.4,
	tr = 0.05, tg = 0.12, tb = 0.02,
}
local DEV_COMBAT_COLOR = {
	r = 0.05, g = 0.85, b = 1.0, a = 0.9,
	hr = 0.35, hg = 0.95, hb = 1.0,
	br = 0.6, bg = 1.0, bb = 1.0,
	tr = 0.02, tg = 0.08, tb = 0.12,
}

local function SetSelected(name)
	selectedName = name
	logOffset = 0
	if journal then
		journal:HideRemoveMenu()
		journal:Refresh()
	end
end

local function FilteredNames()
	local all = DeathNote_GetNames()
	local q = string.lower((searchText or ""):match("^%s*(.-)%s*$") or "")
	if q == "" then
		return all, #all
	end
	local out = {}
	for _, name in ipairs(all) do
		local entry = DeathNote_GetEntry(name)
		local note = entry and type(entry.note) == "string" and string.lower(entry.note) or ""
		if string.find(string.lower(name), q, 1, true) or (note ~= "" and string.find(note, q, 1, true)) then
			out[#out + 1] = name
		end
	end
	return out, #all
end

local function FilteredLog(name)
	local rows = DeathNote_GetCombatLog(name)
	local out = {}
	for i = #rows, 1, -1 do
		local row = rows[i]
		if logFilter == "All" or row.result == logFilter then
			out[#out + 1] = row
		end
	end
	return out
end

local function CreateListRow(parent, index)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetHeight(ROW_HEIGHT - 3)
	btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
	btn:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	btn.rowIndex = index

	btn.bg = btn:CreateTexture(nil, "BACKGROUND")
	btn.bg:SetAllPoints()

	btn.stripe = btn:CreateTexture(nil, "ARTWORK")
	btn.stripe:SetWidth(3)
	btn.stripe:SetPoint("TOPLEFT", 0, 0)
	btn.stripe:SetPoint("BOTTOMLEFT", 0, 0)

	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetSize(22, 22)
	btn.icon:SetPoint("LEFT", 10, 0)

	btn.name = MakeFont(btn, "GameFontNormal", 12)
	btn.name:SetPoint("TOPLEFT", btn.icon, "TOPRIGHT", 8, 1)
	btn.name:SetPoint("RIGHT", btn, "RIGHT", -86, 0)
	btn.name:SetJustifyH("LEFT")

	btn.sub = MakeFont(btn, "GameFontDisableSmall", 10)
	btn.sub:SetPoint("TOPLEFT", btn.name, "BOTTOMLEFT", 0, -2)
	btn.sub:SetPoint("RIGHT", btn, "RIGHT", -86, 0)
	btn.sub:SetJustifyH("LEFT")

	btn.kd = MakeFont(btn, "GameFontHighlightSmall", 11)
	btn.kd:SetPoint("RIGHT", -6, 0)
	btn.kd:SetWidth(46)
	btn.kd:SetJustifyH("RIGHT")

	btn.level = MakeFont(btn, "GameFontNormal", 13)
	btn.level:SetPoint("RIGHT", btn.kd, "LEFT", -2, 0)
	btn.level:SetWidth(24)
	btn.level:SetJustifyH("RIGHT")

	function btn:Paint()
		if self.entryName and self.entryName == selectedName then
			Paint(self.bg, C.select)
			Paint(self.stripe, C.blood)
		elseif self.hovered then
			Paint(self.bg, C.hover)
			Paint(self.stripe, C.bloodDim)
		else
			Paint(self.bg, self.rowIndex % 2 == 0 and C.rowB or C.rowA)
			Paint(self.stripe, self.classColor or C.faint, 0.55)
		end
	end

	btn:SetScript("OnEnter", function(self)
		self.hovered = true
		self:Paint()
		local entry = self.entryName and DeathNote_GetEntry(self.entryName)
		if entry and GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local cc = ClassColor(entry.classFile)
			GameTooltip:AddLine(entry.name or self.entryName, cc[1], cc[2], cc[3])
			GameTooltip:AddLine("Level " .. DeathNote_FormatLevel(entry.level), 0.96, 0.93, 0.87)
			GameTooltip:AddLine(DeathNote_FormatLocation(entry.lastSeen), 0.8, 0.78, 0.75, true)
			if entry.lastSeen and entry.lastSeen.time then
				GameTooltip:AddLine("Seen " .. FormatAgo(entry.lastSeen.time), 0.55, 0.52, 0.5)
			end
			GameTooltip:Show()
		end
	end)
	btn:SetScript("OnLeave", function(self)
		self.hovered = false
		self:Paint()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:SetScript("OnClick", function(self, button)
		if not self.entryName then
			return
		end
		if button == "RightButton" then
			if GameTooltip then
				GameTooltip:Hide()
			end
			SetSelected(self.entryName)
			if journal then
				journal:ShowRemoveMenu(self.entryName)
			end
			return
		end
		SetSelected(self.entryName)
	end)

	return btn
end

local function CreateLogRow(parent, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(LOG_ROW_HEIGHT)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * LOG_ROW_HEIGHT))
	row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	Paint(row.bg, index % 2 == 0 and C.rowB or C.rowA)

	row.pill = row:CreateTexture(nil, "ARTWORK")
	row.pill:SetSize(52, 16)
	row.pill:SetPoint("LEFT", 4, 0)

	row.result = MakeFont(row, "GameFontNormalSmall", 10)
	row.result:SetPoint("CENTER", row.pill, "CENTER", 0, 0)

	row.levels = MakeFont(row, "GameFontHighlightSmall", 10)
	row.levels:SetPoint("LEFT", row.pill, "RIGHT", 8, 0)
	row.levels:SetWidth(52)
	row.levels:SetJustifyH("LEFT")

	row.when = MakeFont(row, "GameFontDisableSmall", 10)
	row.when:SetPoint("RIGHT", -6, 0)
	row.when:SetWidth(52)
	row.when:SetJustifyH("RIGHT")

	row.coords = MakeFont(row, "GameFontHighlightSmall", 10)
	row.coords:SetPoint("RIGHT", row.when, "LEFT", -6, 0)
	row.coords:SetWidth(64)
	row.coords:SetJustifyH("RIGHT")

	row.region = MakeFont(row, "GameFontHighlightSmall", 11)
	row.region:SetPoint("LEFT", row.levels, "RIGHT", 6, 7)
	row.region:SetPoint("RIGHT", row.coords, "LEFT", -6, 0)
	row.region:SetJustifyH("LEFT")
	row.region:SetWordWrap(false)

	row.subzone = MakeFont(row, "GameFontDisableSmall", 10)
	row.subzone:SetPoint("TOPLEFT", row.region, "BOTTOMLEFT", 0, -1)
	row.subzone:SetPoint("TOPRIGHT", row.region, "BOTTOMRIGHT", 0, -1)
	row.subzone:SetJustifyH("LEFT")
	row.subzone:SetWordWrap(false)
	Tint(row.subzone, C.muted)

	return row
end

local function CreateStatTile(parent, caption, color)
	local tile = MakePanel(parent)
	local rightWidth = FRAME_WIDTH - PAD * 2 - (LIST_WIDTH + 16) - 10
	tile:SetSize(math.floor((rightWidth - 28 - 24) / 4), 52)
	tile.value = MakeFont(tile, "GameFontNormalLarge", 20)
	tile.value:SetPoint("TOP", 0, -8)
	Tint(tile.value, color)
	tile.caption = MakeFont(tile, "GameFontDisableSmall", 9)
	tile.caption:SetPoint("BOTTOM", 0, 8)
	tile.caption:SetText(caption)
	Tint(tile.caption, C.muted)
	return tile
end

local function CreateJournal()
	local frame = CreateFrame("Frame", "DeathNoteJournalFrame", UIParent)
	frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:Hide()
	if UISpecialFrames then
		tinsert(UISpecialFrames, "DeathNoteJournalFrame")
	end

	UI.CreateFrameBorders(frame, C, 2)

	-- Header
	local header = UI.CreateHeader(frame, C, HEADER_H, 2)

	frame.mark = WoWF.CreateCircleIcon(header, 40, "Interface\\AddOns\\DeathNote\\icon.tga", C.blood)
	frame.mark:SetPoint("LEFT", 16, 1)

	frame.brand = MakeFont(header, "GameFontNormalLarge", 18)
	frame.brand:SetPoint("TOPLEFT", frame.mark, "TOPRIGHT", 14, -4)
	frame.brand:SetText("DEATH NOTE")
	Tint(frame.brand, C.bone)

	frame.brandSub = MakeFont(header, "GameFontDisableSmall", 10)
	frame.brandSub:SetPoint("TOPLEFT", frame.brand, "BOTTOMLEFT", 0, -2)
	frame.brandSub:SetText("TO BE WRITTEN HERE IS TO BE MARKED FOR DEATH")
	Tint(frame.brandSub, C.bloodDim)

	frame.close = UI.CreateHeaderButton(header, C, {
		cross = true,
		onClick = function()
			frame:Hide()
		end,
	})
	frame.close:SetPoint("RIGHT", -14, 0)

	frame.devBtn = UI.CreateHeaderButton(header, C, {
		edge = { 0.85, 0.08, 0.72, 1 },
		fill = { 0.22, 0.04, 0.2, 1 },
		hoverEdge = { 0.85, 0.08, 0.72, 1 },
		hoverFill = { 0.85, 0.08, 0.72, 1 },
		icon = "Interface\\Icons\\INV_Misc_Wrench_01",
		onClick = function()
			if frame.devPanel:IsShown() then
				frame.devPanel:Hide()
				return
			end
			frame.devPanel:ClearAllPoints()
			frame.devPanel:SetPoint("TOPLEFT", frame, "TOPRIGHT", 8, 0)
			frame.devPanel:Show()
		end,
	})
	frame.devBtn:SetPoint("RIGHT", frame.close, "LEFT", -8, 0)

	-- Left column: search/add + names
	local left = MakePanel(frame)
	frame.left = left
	left:SetPoint("TOPLEFT", PAD, -(HEADER_H + 12))
	left:SetPoint("BOTTOMLEFT", PAD, 10)
	left:SetWidth(LIST_WIDTH + 16)

	local searchShell = MakePanel(left)
	searchShell:SetPoint("TOPLEFT", 8, -8)
	searchShell:SetPoint("TOPRIGHT", -40, -8)
	searchShell:SetHeight(26)
	Paint(searchShell.fill, C.void)

	frame.search = CreateFrame("EditBox", nil, searchShell)
	frame.search:SetPoint("TOPLEFT", 1, -1)
	frame.search:SetPoint("BOTTOMRIGHT", -1, 1)
	frame.search:SetAutoFocus(false)
	frame.search:SetFontObject(ChatFontNormal or GameFontHighlight)
	frame.search:SetTextInsets(8, 8, 0, 0)
	frame.search:SetMaxLetters(48)

	frame.searchHint = MakeFont(searchShell, "GameFontDisableSmall", 11)
	frame.searchHint:SetPoint("LEFT", 9, 0)
	frame.searchHint:SetText("Search or add a name…")
	Tint(frame.searchHint, C.faint)

	local function UpdateSearchHint()
		local hasText = (frame.search:GetText() or "") ~= ""
		if hasText or frame.search:HasFocus() then
			frame.searchHint:Hide()
		else
			frame.searchHint:Show()
		end
	end

	local function AddFromInput()
		local text = (frame.search:GetText() or ""):match("^%s*(.-)%s*$")
		local entry, key
		if text and text ~= "" then
			entry, key = DeathNote_Add(text)
		else
			entry, key = DeathNote_Add(nil)
		end
		if key then
			frame.search:SetText("")
			searchText = ""
			frame.search:ClearFocus()
			SetSelected(key)
		end
	end

	frame.search:SetScript("OnEditFocusGained", UpdateSearchHint)
	frame.search:SetScript("OnEditFocusLost", UpdateSearchHint)
	frame.search:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	frame.search:SetScript("OnEnterPressed", AddFromInput)
	frame.search:SetScript("OnTextChanged", function(self)
		searchText = self:GetText() or ""
		listOffset = 0
		UpdateSearchHint()
		frame:Refresh()
	end)

	frame.addNameBtn = MakeButton(left, "+", 26, 26, "primary")
	frame.addNameBtn:SetPoint("LEFT", searchShell, "RIGHT", 6, 0)
	frame.addNameBtn.label:SetFont(frame.addNameBtn.label:GetFont(), 16, "")
	frame.addNameBtn:SetScript("OnClick", AddFromInput)

	frame.addTargetBtn = MakeButton(left, "Add Current Target", 1, 26, "ghost")
	frame.addTargetBtn:SetPoint("TOPLEFT", searchShell, "BOTTOMLEFT", 0, -6)
	frame.addTargetBtn:SetPoint("RIGHT", left, "RIGHT", -8, 0)
	frame.addTargetBtn:SetScript("OnClick", function()
		local _, key = DeathNote_Add(nil)
		if key then
			SetSelected(key)
		end
	end)

	frame.listLabel = MakeFont(left, "GameFontDisableSmall", 10)
	frame.listLabel:SetPoint("TOPLEFT", frame.addTargetBtn, "BOTTOMLEFT", 2, -10)
	frame.listLabel:SetText("NAMES")
	Tint(frame.listLabel, C.bloodDim)

	frame.listCount = MakeFont(left, "GameFontDisableSmall", 10)
	frame.listCount:SetPoint("RIGHT", left, "RIGHT", -10, 0)
	frame.listCount:SetPoint("TOP", frame.listLabel, "TOP", 0, 0)
	Tint(frame.listCount, C.faint)

	-- Plain frame, not a ScrollFrame. The rows are swapped in place, so a scroll
	-- child wider than this hole was making the game draw a scrollbar of its own.
	frame.listScroll = CreateFrame("Frame", nil, left)
	frame.listScroll:SetPoint("TOPLEFT", frame.listLabel, "BOTTOMLEFT", -2, -6)
	frame.listScroll:SetPoint("BOTTOMRIGHT", -8, 8)
	if frame.listScroll.SetClipsChildren then
		frame.listScroll:SetClipsChildren(true)
	end

	frame.listChild = CreateFrame("Frame", nil, frame.listScroll)
	frame.listChild:SetPoint("TOPLEFT", 0, 0)
	frame.listChild:SetPoint("TOPRIGHT", 0, 0)
	frame.listChild:SetHeight(VISIBLE_LIST_ROWS * ROW_HEIGHT)

	frame.listScroll:EnableMouseWheel(true)
	frame.listScroll:SetScript("OnMouseWheel", function(_, delta)
		local names = FilteredNames()
		local maxOffset = math.max(0, #names - VISIBLE_LIST_ROWS)
		listOffset = math.min(maxOffset, math.max(0, listOffset - delta))
		frame:Refresh()
	end)

	for i = 1, VISIBLE_LIST_ROWS do
		listButtons[i] = CreateListRow(frame.listChild, i)
	end

	frame.listEmpty = MakeFont(left, "GameFontDisableSmall", 11)
	frame.listEmpty:SetPoint("TOP", frame.listScroll, "TOP", 0, -30)
	frame.listEmpty:SetWidth(LIST_WIDTH - 20)
	Tint(frame.listEmpty, C.faint)

	-- Right column: detail
	local right = MakePanel(frame)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
	right:SetPoint("BOTTOMRIGHT", -PAD, 10)
	frame.right = right

	frame.emptyState = CreateFrame("Frame", nil, right)
	frame.emptyState:SetAllPoints()
	local emptyTitle = MakeFont(frame.emptyState, "GameFontNormalLarge", 16)
	emptyTitle:SetPoint("CENTER", 0, 10)
	emptyTitle:SetText("No names written yet")
	Tint(emptyTitle, C.bone)
	local emptySub = MakeFont(frame.emptyState, "GameFontDisableSmall", 11)
	emptySub:SetPoint("TOP", emptyTitle, "BOTTOM", 0, -8)
	emptySub:SetWidth(320)
	emptySub:SetText("Target a player and press Add Current Target,\nor type a name on the left and press Enter.")
	Tint(emptySub, C.muted)

	local detail = CreateFrame("Frame", nil, right)
	detail:SetAllPoints()
	frame.detail = detail

	-- Identity card
	frame.portraitShell = MakePanel(detail)
	frame.portraitShell:SetSize(56, 56)
	frame.portraitShell:SetPoint("TOPLEFT", 14, -14)
	Paint(frame.portraitShell.fill, C.void)
	frame.portrait = frame.portraitShell:CreateTexture(nil, "ARTWORK")
	frame.portrait:SetPoint("TOPLEFT", 4, -4)
	frame.portrait:SetPoint("BOTTOMRIGHT", -4, 4)

	frame.detailName = MakeFont(detail, "GameFontNormalLarge", 20)
	frame.detailName:SetPoint("TOPLEFT", frame.portraitShell, "TOPRIGHT", 14, -6)
	frame.detailName:SetJustifyH("LEFT")
	frame.detailName:SetWordWrap(false)

	frame.nameRemove = CreateFrame("Button", nil, detail)
	frame.nameRemove:SetSize(12, 12)
	frame.nameRemove:SetPoint("LEFT", frame.detailName, "RIGHT", 6, 0)
	frame.nameRemove:RegisterForClicks("LeftButtonUp")
	local function TrashPart(w, h, point, rel, relPoint, x, y)
		local tex = frame.nameRemove:CreateTexture(nil, "ARTWORK")
		tex:SetSize(w, h)
		tex:SetPoint(point, rel, relPoint, x, y)
		return tex
	end
	-- Handle, a wider lid, then a narrower bin with a gap under the lid.
	local handle = TrashPart(3, 1, "TOP", frame.nameRemove, "TOP", 0, -1)
	local lid = TrashPart(10, 1, "TOP", handle, "BOTTOM", 0, 0)
	local body = TrashPart(7, 6, "TOP", lid, "BOTTOM", 0, -1)
	frame.nameRemove.parts = { lid, handle, body }
	local function PaintTrash(color)
		for _, tex in ipairs(frame.nameRemove.parts) do
			Paint(tex, color)
		end
	end
	PaintTrash(C.muted)
	frame.nameRemove:SetScript("OnEnter", function(self)
		PaintTrash(C.death)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Remove")
			GameTooltip:Show()
		end
	end)
	frame.nameRemove:SetScript("OnLeave", function()
		PaintTrash(C.muted)
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	frame.nameRemove:SetScript("OnClick", function()
		if selectedName then
			DeathNote_Remove(selectedName)
		end
	end)

	frame.detailSub = MakeFont(detail, "GameFontHighlight", 12)
	frame.detailSub:SetPoint("TOPLEFT", frame.detailName, "BOTTOMLEFT", 0, -6)
	frame.detailSub:SetJustifyH("LEFT")
	Tint(frame.detailSub, C.muted)

	frame.detailNoted = MakeFont(detail, "GameFontDisableSmall", 10)
	frame.detailNoted:SetPoint("TOPRIGHT", -14, -18)
	frame.detailNoted:SetJustifyH("RIGHT")
	Tint(frame.detailNoted, C.faint)

	local idRule = MakeRule(detail, C.edge)
	idRule:SetPoint("TOPLEFT", 14, -82)
	idRule:SetPoint("TOPRIGHT", -14, -82)

	-- Stat tiles
	frame.tiles = {}
	local tileSpecs = {
		{ key = "kills", caption = "KILLS", color = C.kill },
		{ key = "deaths", caption = "DEATHS TO THEM", color = C.death },
		{ key = "ratio", caption = "K / D", color = C.bone },
		{ key = "encounters", caption = "ENCOUNTERS", color = C.combat },
	}
	local prevTile
	for _, spec in ipairs(tileSpecs) do
		local tile = CreateStatTile(detail, spec.caption, spec.color)
		if prevTile then
			tile:SetPoint("TOPLEFT", prevTile, "TOPRIGHT", 8, 0)
		else
			tile:SetPoint("TOPLEFT", 14, -94)
		end
		frame.tiles[spec.key] = tile
		prevTile = tile
	end

	-- Last seen card
	local seen = MakePanel(detail)
	seen:SetPoint("TOPLEFT", 14, -158)
	seen:SetPoint("TOPRIGHT", -14, -158)
	seen:SetHeight(50)
	frame.seen = seen

	local seenLabel = MakeFont(seen, "GameFontDisableSmall", 9)
	seenLabel:SetPoint("TOPLEFT", 10, -8)
	seenLabel:SetText("LAST SEEN")
	Tint(seenLabel, C.blood)

	frame.seenZone = MakeFont(seen, "GameFontHighlight", 13)
	frame.seenZone:SetPoint("TOPLEFT", seenLabel, "BOTTOMLEFT", 0, -5)
	frame.seenZone:SetPoint("RIGHT", seen, "RIGHT", -150, 0)
	frame.seenZone:SetJustifyH("LEFT")
	Tint(frame.seenZone, C.bone)

	frame.seenCoords = MakeFont(seen, "GameFontNormalLarge", 15)
	frame.seenCoords:SetPoint("TOPRIGHT", -12, -9)
	frame.seenCoords:SetJustifyH("RIGHT")
	Tint(frame.seenCoords, C.ink)

	frame.seenAgo = MakeFont(seen, "GameFontDisableSmall", 10)
	frame.seenAgo:SetPoint("TOPRIGHT", frame.seenCoords, "BOTTOMRIGHT", 0, -3)
	frame.seenAgo:SetJustifyH("RIGHT")
	Tint(frame.seenAgo, C.faint)

	-- Freeform note. Writes into the entry as you type.
	local note = MakePanel(detail)
	note:SetPoint("TOPLEFT", 14, -216)
	note:SetPoint("TOPRIGHT", -14, -216)
	note:SetHeight(78)
	frame.note = note
	Paint(note.fill, C.void)

	local noteLabel = MakeFont(note, "GameFontDisableSmall", 9)
	noteLabel:SetPoint("TOPLEFT", 10, -6)
	noteLabel:SetText("NOTE")
	Tint(noteLabel, C.blood)

	frame.noteScroll = CreateFrame("ScrollFrame", nil, note)
	frame.noteScroll:SetPoint("TOPLEFT", 6, -18)
	frame.noteScroll:SetPoint("BOTTOMRIGHT", -6, 4)

	frame.noteBox = CreateFrame("EditBox", nil, frame.noteScroll)
	frame.noteBox:SetMultiLine(true)
	frame.noteBox:SetAutoFocus(false)
	frame.noteBox:SetFontObject(ChatFontNormal or GameFontHighlight)
	frame.noteBox:SetWidth(360)
	frame.noteBox:SetHeight(52)
	frame.noteBox:SetMaxLetters(2000)
	frame.noteBox:SetTextInsets(4, 4, 2, 2)
	frame.noteBox:SetJustifyH("LEFT")
	frame.noteBox:SetJustifyV("TOP")
	frame.noteScroll:SetScrollChild(frame.noteBox)

	frame.notePlaceholder = MakeFont(note, "GameFontDisableSmall", 11)
	frame.notePlaceholder:SetPoint("TOPLEFT", frame.noteScroll, "TOPLEFT", 6, -2)
	frame.notePlaceholder:SetText("Anything you want to remember…")
	Tint(frame.notePlaceholder, C.faint)

	local function SyncNotePlaceholder()
		local hasText = (frame.noteBox:GetText() or "") ~= ""
		if hasText or frame.noteBox:HasFocus() then
			frame.notePlaceholder:Hide()
		else
			frame.notePlaceholder:Show()
		end
	end

	frame.noteBox:SetScript("OnEditFocusGained", SyncNotePlaceholder)
	frame.noteBox:SetScript("OnEditFocusLost", SyncNotePlaceholder)
	frame.noteBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	frame.noteBox:SetScript("OnTextChanged", function(self)
		SyncNotePlaceholder()
		if frame.noteSyncing or not selectedName then
			return
		end
		DeathNote_SetNote(selectedName, self:GetText() or "")
	end)
	frame.noteBox:SetScript("OnCursorChanged", function(self, _, y, _, cursorHeight)
		local scroll = frame.noteScroll
		if not scroll then
			return
		end
		y = -y
		local height = scroll:GetHeight() or 0
		local offset = scroll:GetVerticalScroll() or 0
		if y < offset then
			scroll:SetVerticalScroll(y)
		elseif y + (cursorHeight or 0) > offset + height then
			scroll:SetVerticalScroll(y + (cursorHeight or 0) - height)
		end
	end)

	-- Combat log
	local logTitle = MakeFont(detail, "GameFontNormal", 12)
	logTitle:SetPoint("TOPLEFT", 16, -306)
	logTitle:SetText("COMBAT LOG")
	Tint(logTitle, C.bone)

	frame.logTabs = {}
	local prevTab
	for i = #LOG_FILTERS, 1, -1 do
		local key = LOG_FILTERS[i]
		local tab = MakeTab(detail, LOG_FILTER_LABELS[key], 58)
		if prevTab then
			tab:SetPoint("RIGHT", prevTab, "LEFT", -4, 0)
		else
			tab:SetPoint("TOPRIGHT", -14, -303)
		end
		tab:SetScript("OnClick", function()
			logFilter = key
			logOffset = 0
			frame:Refresh()
		end)
		frame.logTabs[key] = tab
		prevTab = tab
	end

	local colY = -330
	local colResult = MakeFont(detail, "GameFontDisableSmall", 9)
	colResult:SetPoint("TOPLEFT", 18, colY)
	colResult:SetText("RESULT")
	local colLevels = MakeFont(detail, "GameFontDisableSmall", 9)
	colLevels:SetPoint("TOPLEFT", 78, colY)
	colLevels:SetText("ME / THEM")
	local colRegion = MakeFont(detail, "GameFontDisableSmall", 9)
	colRegion:SetPoint("TOPLEFT", 136, colY)
	colRegion:SetText("REGION")
	local colWhen = MakeFont(detail, "GameFontDisableSmall", 9)
	colWhen:SetPoint("TOPRIGHT", -28, colY)
	colWhen:SetText("WHEN")
	local colCoords = MakeFont(detail, "GameFontDisableSmall", 9)
	colCoords:SetPoint("TOPRIGHT", -86, colY)
	colCoords:SetText("COORDS")
	for _, fs in ipairs({ colResult, colLevels, colRegion, colWhen, colCoords }) do
		Tint(fs, C.faint)
	end

	local logRule = MakeRule(detail, C.edge)
	logRule:SetPoint("TOPLEFT", 14, colY - 14)
	logRule:SetPoint("TOPRIGHT", -22, colY - 14)

	frame.logScroll = CreateFrame("ScrollFrame", nil, detail)
	frame.logScroll:SetPoint("TOPLEFT", 14, colY - 18)
	frame.logScroll:SetPoint("BOTTOMRIGHT", -22, 10)

	frame.logChild = CreateFrame("Frame", nil, frame.logScroll)
	frame.logChild:SetSize(FRAME_WIDTH - PAD * 2 - LIST_WIDTH - 16 - 10 - 36, VISIBLE_LOG_ROWS * LOG_ROW_HEIGHT)
	frame.logScroll:SetScrollChild(frame.logChild)

	frame.logBar = CreateFrame("Frame", nil, detail)
	frame.logBar:SetWidth(5)
	frame.logBar:SetPoint("TOPLEFT", frame.logScroll, "TOPRIGHT", 5, 0)
	frame.logBar:SetPoint("BOTTOMLEFT", frame.logScroll, "BOTTOMRIGHT", 5, 0)
	frame.logBar:EnableMouse(true)
	frame.logBar:EnableMouseWheel(true)
	frame.logBar.track = frame.logBar:CreateTexture(nil, "BACKGROUND")
	frame.logBar.track:SetAllPoints()
	Paint(frame.logBar.track, C.edge, 0.45)
	frame.logBar.thumb = frame.logBar:CreateTexture(nil, "ARTWORK")
	frame.logBar.thumb:SetWidth(5)
	Paint(frame.logBar.thumb, C.bloodDim)

	local function LogFractionFromCursor()
		local bar = frame.logBar
		local height = bar:GetHeight() or 0
		local thumbH = bar.thumb:GetHeight() or 18
		local travel = height - thumbH
		if travel <= 0 then
			return 0
		end
		local _, cursorY = GetCursorPosition()
		local scale = bar:GetEffectiveScale()
		if scale and scale > 0 then
			cursorY = cursorY / scale
		end
		local top = bar:GetTop() or cursorY
		local rel = (top - cursorY) - (thumbH / 2)
		if rel < 0 then
			return 0
		end
		if rel > travel then
			return 1
		end
		return rel / travel
	end

	local function ScrollLogToFraction(fraction)
		if not selectedName then
			return
		end
		local rows = FilteredLog(selectedName)
		local maxOffset = math.max(0, #rows - VISIBLE_LOG_ROWS)
		local nextOffset = math.floor((fraction or 0) * maxOffset + 0.5)
		if nextOffset == logOffset then
			return
		end
		logOffset = nextOffset
		frame:Refresh()
	end

	frame.logBar:SetScript("OnMouseDown", function()
		ScrollLogToFraction(LogFractionFromCursor())
		frame.logBar.dragging = true
	end)
	frame.logBar:SetScript("OnMouseUp", function()
		frame.logBar.dragging = false
	end)
	frame.logBar:SetScript("OnUpdate", function(self)
		if self.dragging and IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
			self.dragging = false
		end
		if self.dragging then
			ScrollLogToFraction(LogFractionFromCursor())
		end
	end)
	frame.logBar:SetScript("OnMouseWheel", function(_, delta)
		if not selectedName then
			return
		end
		local rows = FilteredLog(selectedName)
		local maxOffset = math.max(0, #rows - VISIBLE_LOG_ROWS)
		logOffset = math.min(maxOffset, math.max(0, logOffset - delta))
		frame:Refresh()
	end)

	frame.logScroll:EnableMouseWheel(true)
	frame.logScroll:SetScript("OnMouseWheel", function(_, delta)
		if not selectedName then
			return
		end
		local rows = FilteredLog(selectedName)
		local maxOffset = math.max(0, #rows - VISIBLE_LOG_ROWS)
		logOffset = math.min(maxOffset, math.max(0, logOffset - delta))
		frame:Refresh()
	end)

	for i = 1, VISIBLE_LOG_ROWS do
		logButtons[i] = CreateLogRow(frame.logChild, i)
	end

	frame.logEmpty = MakeFont(detail, "GameFontDisableSmall", 11)
	frame.logEmpty:SetPoint("TOP", frame.logScroll, "TOP", 0, -40)
	Tint(frame.logEmpty, C.faint)

	-- Right-click a name: a small prompt, then Remove.
	local removeCatcher = CreateFrame("Button", nil, UIParent)
	removeCatcher:SetAllPoints(UIParent)
	removeCatcher:SetFrameStrata("DIALOG")
	removeCatcher:EnableMouse(true)
	removeCatcher:RegisterForClicks("AnyUp")
	removeCatcher:Hide()

	local removeMenu = MakePanel(UIParent)
	removeMenu:SetFrameStrata("TOOLTIP")
	removeMenu:SetSize(180, 68)
	removeMenu:EnableMouse(true)
	removeMenu:SetClampedToScreen(true)
	removeMenu:Hide()
	removeMenu.prompt = MakeFont(removeMenu, "GameFontHighlight", 12)
	removeMenu.prompt:SetPoint("TOPLEFT", 14, -12)
	removeMenu.prompt:SetPoint("TOPRIGHT", -14, -12)
	removeMenu.prompt:SetJustifyH("CENTER")
	Tint(removeMenu.prompt, C.bone)
	removeMenu.removeBtn = MakeButton(removeMenu, "Remove", 88, 22, "danger")
	removeMenu.removeBtn:SetPoint("BOTTOM", 0, 12)

	function frame:HideRemoveMenu()
		removeMenu:Hide()
		removeCatcher:Hide()
	end

	function frame:ShowRemoveMenu(name)
		if not name then
			return
		end
		removeMenu.targetName = name
		removeMenu.prompt:SetText("Remove " .. name .. "?")
		removeMenu:Show()
		local textW = removeMenu.prompt:GetStringWidth() or 0
		local width = math.max(168, textW + 36)
		removeMenu:SetWidth(width)
		local scale = UIParent:GetEffectiveScale()
		local x, y = GetCursorPosition()
		removeMenu:ClearAllPoints()
		removeMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x / scale) + 8, (y / scale) - 8)
		removeCatcher:Show()
		removeCatcher:SetFrameLevel(self:GetFrameLevel() + 20)
		removeMenu:SetFrameLevel(removeCatcher:GetFrameLevel() + 5)
	end

	removeMenu.removeBtn:SetScript("OnClick", function()
		local name = removeMenu.targetName
		frame:HideRemoveMenu()
		if name then
			DeathNote_Remove(name)
		end
	end)
	removeCatcher:SetScript("OnClick", function()
		frame:HideRemoveMenu()
	end)

	-- Dev actions sit in their own window, to the right of the journal.
	local devPanel = CreateFrame("Frame", "DeathNoteDevPanel", UIParent)
	devPanel:SetSize(156, 248)
	devPanel:SetFrameStrata("DIALOG")
	devPanel:SetClampedToScreen(true)
	devPanel:EnableMouse(true)
	devPanel:SetMovable(true)
	devPanel:Hide()
	frame.devPanel = devPanel

	local devOuter = devPanel:CreateTexture(nil, "BACKGROUND")
	devOuter:SetAllPoints()
	SetSolidColor(devOuter, 0.85, 0.08, 0.72, 1)
	local devInner = devPanel:CreateTexture(nil, "BACKGROUND")
	devInner:SetDrawLayer("BACKGROUND", 1)
	devInner:SetPoint("TOPLEFT", 2, -2)
	devInner:SetPoint("BOTTOMRIGHT", -2, 2)
	Paint(devInner, C.void)

	local devHeader = CreateFrame("Frame", nil, devPanel)
	devHeader:SetPoint("TOPLEFT", 2, -2)
	devHeader:SetPoint("TOPRIGHT", -2, -2)
	devHeader:SetHeight(28)
	devHeader:EnableMouse(true)
	devHeader:RegisterForDrag("LeftButton")
	devHeader:SetScript("OnDragStart", function()
		devPanel:StartMoving()
	end)
	devHeader:SetScript("OnDragStop", function()
		devPanel:StopMovingOrSizing()
	end)
	local devHeaderFill = devHeader:CreateTexture(nil, "BACKGROUND")
	devHeaderFill:SetAllPoints()
	SetSolidColor(devHeaderFill, 0.22, 0.04, 0.2, 1)
	local devTitle = MakeFont(devHeader, "GameFontNormalSmall", 11)
	devTitle:SetPoint("LEFT", 10, 0)
	devTitle:SetText("DEV")
	devTitle:SetTextColor(0.95, 0.05, 0.75)

	local devClose = CreateFrame("Button", nil, devHeader)
	devClose:SetSize(18, 18)
	devClose:SetPoint("RIGHT", -6, 0)
	devClose:RegisterForClicks("LeftButtonUp")
	MakeCenteredCross(devClose, 8, 1.5)
	devClose:SetScript("OnClick", function()
		devPanel:Hide()
	end)
	devClose:SetScript("OnEnter", function(self)
		self:SetGlyphColor(C.bone)
	end)
	devClose:SetScript("OnLeave", function(self)
		self:SetGlyphColor(C.muted)
	end)

	frame.simKillBtn = CreateDevButton(devPanel, "Sim Kill", 128, DEV_KILL_COLOR)
	frame.simKillBtn:SetPoint("TOP", 0, -42)
	frame.simKillBtn:SetScript("OnClick", function()
		if selectedName then
			DeathNote_SimulateKill(selectedName)
		end
	end)

	frame.simDeathBtn = CreateDevButton(devPanel, "Sim Death", 128, DEV_DEATH_COLOR)
	frame.simDeathBtn:SetPoint("TOP", frame.simKillBtn, "BOTTOM", 0, -6)
	frame.simDeathBtn:SetScript("OnClick", function()
		if selectedName then
			DeathNote_SimulateDeath(selectedName)
		end
	end)

	frame.simCombatBtn = CreateDevButton(devPanel, "Sim Combat", 128, DEV_COMBAT_COLOR)
	frame.simCombatBtn:SetPoint("TOP", frame.simDeathBtn, "BOTTOM", 0, -6)
	frame.simCombatBtn:SetScript("OnClick", function()
		if selectedName then
			DeathNote_SimulateCombat(selectedName)
		end
	end)

	local DEV_SEED_COLOR = {
		r = 0.85, g = 0.08, b = 0.72, a = 0.9,
		hr = 1.0, hg = 0.28, hb = 0.9,
		br = 1.0, bg = 0.55, bb = 0.95,
		tr = 1, tg = 1, tb = 1,
	}

	local seedHorde = CreateDevButton(devPanel, "Seed Horde", 128, DEV_SEED_COLOR)
	seedHorde:SetPoint("TOP", frame.simCombatBtn, "BOTTOM", 0, -12)
	seedHorde:SetScript("OnClick", function()
		DeathNote_SeedDemo("horde")
	end)

	local seedAlliance = CreateDevButton(devPanel, "Seed Alliance", 128, DEV_SEED_COLOR)
	seedAlliance:SetPoint("TOP", seedHorde, "BOTTOM", 0, -6)
	seedAlliance:SetScript("OnClick", function()
		DeathNote_SeedDemo("alliance")
	end)

	local DEV_CLEAR_COLOR = {
		r = 0.15, g = 0.75, b = 0.85, a = 0.9,
		hr = 0.35, hg = 0.9, hb = 1.0,
		br = 0.6, bg = 1.0, bb = 1.0,
		tr = 0.02, tg = 0.08, tb = 0.12,
	}

	local clearData = CreateDevButton(devPanel, "Clear Data", 128, DEV_CLEAR_COLOR)
	clearData:SetPoint("TOP", seedAlliance, "BOTTOM", 0, -12)
	clearData:SetScript("OnClick", function()
		DeathNote_ResetAll()
	end)

	frame:SetScript("OnHide", function()
		frame.search:ClearFocus()
		frame.noteBox:ClearFocus()
		frame:HideRemoveMenu()
		frame.devPanel:Hide()
	end)

	function frame:Refresh()
		local names, total = FilteredNames()
		local maxListOffset = math.max(0, #names - VISIBLE_LIST_ROWS)
		listOffset = math.min(listOffset, maxListOffset)

		if DeathNote_TakeRename then
			local oldName, newName = DeathNote_TakeRename()
			if oldName and newName and selectedName == oldName then
				selectedName = newName
			end
		end

		if total == 0 then
			selectedName = nil
		elseif selectedName and not DeathNote_GetEntry(selectedName) then
			selectedName = nil
		end
		if not selectedName and #names > 0 then
			selectedName = names[1]
		end

		if #names == total then
			self.listCount:SetText(tostring(total))
		else
			self.listCount:SetText(#names .. " of " .. total)
		end

		for i = 1, VISIBLE_LIST_ROWS do
			local btn = listButtons[i]
			local name = names[listOffset + i]
			if name then
				local entry = DeathNote_GetEntry(name)
				btn.entryName = name
				btn.classColor = ClassColor(entry and entry.classFile)
				SetClassIcon(btn.icon, entry and entry.classFile)
				btn.name:SetText(entry and entry.name or name)
				Tint(btn.name, btn.classColor)
				btn.level:SetText(DeathNote_FormatLevel(entry and entry.level))
				Tint(btn.level, C.bone)
				local race = entry and entry.race
				local class = entry and entry.class
				if race or class then
					btn.sub:SetText(((race or "") .. " " .. (class or "")):match("^%s*(.-)%s*$"))
				else
					btn.sub:SetText("Not yet seen")
				end
				local kills = entry and entry.kills or 0
				local deaths = entry and entry.deaths or 0
				btn.kd:SetText(string.format("|cff73f28c%d|r |cff6b6360/|r |cffff6666%d|r", kills, deaths))
				btn:Paint()
				btn:Show()
			else
				btn.entryName = nil
				btn:Hide()
			end
		end

		if total == 0 then
			self.listEmpty:SetText("Your note is empty.")
			self.listEmpty:Show()
		elseif #names == 0 then
			self.listEmpty:SetText("No names match.\nPress Enter to add it.")
			self.listEmpty:Show()
		else
			self.listEmpty:Hide()
		end

		local hasSel = selectedName ~= nil
		for _, key in ipairs({ "simKillBtn", "simDeathBtn", "simCombatBtn" }) do
			local btn = self[key]
			if btn then
				if hasSel then
					btn:Enable()
				else
					btn:Disable()
				end
			end
		end

		local devOn = WoWF and WoWF.DevMode and true or false
		self.devBtn:SetShown(devOn)
		if not devOn then
			self.devPanel:Hide()
		end

		if not hasSel then
			self.noteFor = nil
			self.detail:Hide()
			self.emptyState:Show()
			return
		end
		self.emptyState:Hide()
		self.detail:Show()

		local entry = DeathNote_GetEntry(selectedName)
		local cc = ClassColor(entry and entry.classFile)
		SetClassIcon(self.portrait, entry and entry.classFile)
		Paint(self.portraitShell.edge, cc, 0.9)
		self.detailName:SetText(entry and entry.name or selectedName)
		Tint(self.detailName, cc)
		local nameW = self.detailName:GetStringWidth() or 0
		local nameLeft = self.detailName:GetLeft()
		local notedLeft = self.detailNoted:GetLeft()
		local maxW = 240
		if nameLeft and notedLeft and notedLeft - nameLeft - 28 > 40 then
			maxW = notedLeft - nameLeft - 28
		end
		if nameW > maxW then
			nameW = maxW
		end
		self.detailName:SetWidth(math.max(nameW, 1))

		local race = (entry and entry.race) or "Unknown race"
		local class = (entry and entry.class) or "Unknown class"
		self.detailSub:SetText("Level " .. DeathNote_FormatLevel(entry and entry.level) .. "  ·  " .. race .. "  ·  " .. class)
		if entry and entry.addedAt then
			self.detailNoted:SetText("Noted " .. FormatAgo(entry.addedAt))
		else
			self.detailNoted:SetText("")
		end

		local kills = entry and entry.kills or 0
		local deaths = entry and entry.deaths or 0
		local logRows = DeathNote_GetCombatLog(selectedName)
		self.tiles.kills.value:SetText(tostring(kills))
		self.tiles.deaths.value:SetText(tostring(deaths))
		self.tiles.ratio.value:SetText(FormatRatio(kills, deaths))
		self.tiles.encounters.value:SetText(tostring(#logRows))

		local tileW = math.floor((self.right:GetWidth() - 28 - 24) / 4)
		if tileW > 40 then
			for _, tile in pairs(self.tiles) do
				tile:SetWidth(tileW)
			end
		end

		local loc = entry and entry.lastSeen
		if loc then
			local zone = loc.zone or "Unknown zone"
			if loc.subzone and loc.subzone ~= "" and loc.subzone ~= zone then
				zone = zone .. "  ·  " .. loc.subzone
			end
			self.seenZone:SetText(zone)
			self.seenCoords:SetText(DeathNote_FormatCoords(loc))
			self.seenAgo:SetText(FormatAgo(loc.time))
		else
			self.seenZone:SetText("Never seen — target or mouse over them")
			self.seenCoords:SetText("—")
			self.seenAgo:SetText("")
		end

		local noteText = (entry and type(entry.note) == "string") and entry.note or ""
		if self.noteFor ~= selectedName or (not self.noteBox:HasFocus() and self.noteBox:GetText() ~= noteText) then
			self.noteSyncing = true
			self.noteBox:SetText(noteText)
			self.noteSyncing = false
			self.noteFor = selectedName
		end
		local noteWidth = (self.noteScroll:GetWidth() or 0) - 8
		if noteWidth > 40 and math.abs((self.noteBox:GetWidth() or 0) - noteWidth) > 1 then
			self.noteBox:SetWidth(noteWidth)
		end
		if noteText == "" and not self.noteBox:HasFocus() then
			self.notePlaceholder:Show()
		else
			self.notePlaceholder:Hide()
		end

		for key, tab in pairs(self.logTabs) do
			tab:SetActive(key == logFilter)
		end

		local rows = FilteredLog(selectedName)
		local maxLogOffset = math.max(0, #rows - VISIBLE_LOG_ROWS)
		logOffset = math.min(logOffset, maxLogOffset)

		local bar = self.logBar
		local trackH = bar:GetHeight() or 0
		if maxLogOffset == 0 or trackH < 8 then
			bar.thumb:SetHeight(math.max(trackH, 1))
			bar.thumb:ClearAllPoints()
			bar.thumb:SetPoint("TOP", 0, 0)
			Paint(bar.thumb, C.edge, 0.25)
		else
			local visible = math.min(VISIBLE_LOG_ROWS, #rows)
			local thumbH = math.max(18, trackH * (visible / math.max(#rows, 1)))
			if thumbH > trackH then
				thumbH = trackH
			end
			local travel = trackH - thumbH
			local pos = (logOffset / maxLogOffset) * travel
			bar.thumb:SetHeight(thumbH)
			bar.thumb:ClearAllPoints()
			bar.thumb:SetPoint("TOP", 0, -pos)
			Paint(bar.thumb, C.blood)
		end

		if #rows == 0 then
			if logFilter == "All" then
				self.logEmpty:SetText("No encounters recorded yet.")
			else
				self.logEmpty:SetText("No " .. string.lower(LOG_FILTER_LABELS[logFilter]) .. " recorded.")
			end
			self.logEmpty:Show()
		else
			self.logEmpty:Hide()
		end

		for i = 1, VISIBLE_LOG_ROWS do
			local row = logButtons[i]
			local data = rows[logOffset + i]
			if data then
				local color = RESULT_COLORS[data.result] or C.muted
				Paint(row.pill, color, 0.18)
				row.result:SetText(string.upper(data.result or "—"))
				Tint(row.result, color)
				row.levels:SetText(DeathNote_FormatLevel(data.myLevel) .. " / " .. DeathNote_FormatLevel(data.level))
				Tint(row.levels, C.bone)
				local zone = data.zone or "Unknown"
				local subzone = data.subzone
				local hasSub = subzone and subzone ~= "" and subzone ~= zone
				row.region:ClearAllPoints()
				row.region:SetPoint("LEFT", row.levels, "RIGHT", 6, hasSub and 7 or 0)
				row.region:SetPoint("RIGHT", row.coords, "LEFT", -6, hasSub and 7 or 0)
				row.region:SetText(zone)
				Tint(row.region, C.bone)
				if hasSub then
					row.subzone:SetText(subzone)
					row.subzone:Show()
				else
					row.subzone:Hide()
				end
				row.coords:SetText(DeathNote_FormatCoords(data))
				row.when:SetText(FormatAgo(data.time))
				row:Show()
			else
				row:Hide()
			end
		end
	end

	return frame
end

function DeathNoteJournal_Show()
	if not journal then
		local ok, result = pcall(CreateJournal)
		if not ok then
			print("|cffcc3333[Death Note]|r Journal create failed: " .. tostring(result))
			return
		end
		journal = result
	end
	journal:Show()
	journal:Refresh()
end

function DeathNoteJournal_Hide()
	if journal then
		journal:Hide()
	end
end

function DeathNoteJournal_Toggle()
	if journal and journal:IsShown() then
		DeathNoteJournal_Hide()
	else
		DeathNoteJournal_Show()
	end
end

function DeathNoteJournal_Refresh()
	if journal and journal:IsShown() then
		journal:Refresh()
	end
end
