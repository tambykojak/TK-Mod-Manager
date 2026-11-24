local ADDON_NAME, Addon = ...

local FRAME_WIDTH = 780
local FRAME_HEIGHT = 560
local LIST_WIDTH = 230
local ROW_HEIGHT = 38
local VISIBLE_ROWS = 10
local PAD = 16
local HEADER_H = 56
local FOOTER_H = 44
local BORDER = 2

--- Ink on dark slate, verdigris accents, parchment text.
local C = {
	void = { 0.03, 0.04, 0.045, 1 },
	bg = { 0.055, 0.07, 0.078, 0.98 },
	panel = { 0.085, 0.105, 0.115, 0.98 },
	panelHi = { 0.12, 0.15, 0.16, 1 },
	edge = { 0.15, 0.3, 0.3, 1 },
	accent = { 0.3, 0.78, 0.72, 1 },
	accentDim = { 0.16, 0.42, 0.4, 1 },
	parchment = { 0.94, 0.91, 0.8, 1 },
	ink = { 0.88, 0.88, 0.84, 1 },
	muted = { 0.62, 0.66, 0.66, 1 },
	faint = { 0.42, 0.46, 0.47, 1 },
	select = { 0.1, 0.24, 0.24, 1 },
	hover = { 0.3, 0.78, 0.72, 0.14 },
	rowA = { 1, 1, 1, 0.02 },
	rowB = { 1, 1, 1, 0.05 },
}

local KIND_COLORS = {
	gossip = { 0.55, 0.85, 0.95 },
	greeting = { 0.55, 0.85, 0.95 },
	quest_offer = { 1, 0.82, 0.25 },
	quest_progress = { 0.92, 0.7, 0.4 },
	quest_complete = { 0.55, 0.9, 0.45 },
	say = { 0.95, 0.95, 0.95 },
	yell = { 1, 0.4, 0.35 },
	emote = { 1, 0.65, 0.3 },
	whisper = { 0.75, 0.55, 1 },
}

--- Dev-only chrome. Magenta, never the addon's own palette.
local DEV_MAGENTA = { 0.85, 0.08, 0.72, 1 }
local DEV_MAGENTA_HOVER = { 1, 0.25, 0.88, 1 }

local journal
local selectedKey
local listOffset = 0
local searchText = ""
local listButtons = {}

local function Paint(tex, color, alpha)
	local a = alpha or color[4] or 1
	if tex.SetColorTexture then
		tex:SetColorTexture(color[1], color[2], color[3], a)
		return
	end
	tex:SetTexture("Interface\\Buttons\\WHITE8X8")
	tex:SetVertexColor(color[1], color[2], color[3], a)
end

local function Tint(fs, color)
	fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function Hex(color)
	return string.format(
		"|cff%02x%02x%02x",
		math.floor(color[1] * 255 + 0.5),
		math.floor(color[2] * 255 + 0.5),
		math.floor(color[3] * 255 + 0.5)
	)
end

local function MakeFont(parent, template, size)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
	if size and fs.SetFont then
		local font, _, flags = fs:GetFont()
		if font then
			fs:SetFont(font, size, flags or "")
		end
	end
	return fs
end

local function MakePanel(parent)
	local shell = CreateFrame("Frame", nil, parent)
	shell.edge = shell:CreateTexture(nil, "BACKGROUND")
	shell.edge:SetAllPoints()
	Paint(shell.edge, C.edge)
	shell.fill = shell:CreateTexture(nil, "BACKGROUND")
	shell.fill:SetDrawLayer("BACKGROUND", 1)
	shell.fill:SetPoint("TOPLEFT", 1, -1)
	shell.fill:SetPoint("BOTTOMRIGHT", -1, 1)
	Paint(shell.fill, C.panel)
	return shell
end

local function MakeButton(parent, label, width, height, danger)
	local edgeColor = danger and { 0.5, 0.18, 0.18, 1 } or C.edge
	local fillColor = danger and { 0.16, 0.06, 0.06, 1 } or C.panelHi
	local hoverColor = danger and { 0.34, 0.1, 0.1, 1 } or C.select
	local textColor = danger and { 1, 0.5, 0.5, 1 } or C.ink

	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(width or 90, height or 24)
	btn:RegisterForClicks("LeftButtonUp")

	btn.edge = btn:CreateTexture(nil, "BACKGROUND")
	btn.edge:SetAllPoints()
	Paint(btn.edge, edgeColor)
	btn.fill = btn:CreateTexture(nil, "BACKGROUND")
	btn.fill:SetDrawLayer("BACKGROUND", 1)
	btn.fill:SetPoint("TOPLEFT", 1, -1)
	btn.fill:SetPoint("BOTTOMRIGHT", -1, 1)
	Paint(btn.fill, fillColor)

	btn.label = MakeFont(btn, "GameFontNormalSmall", 11)
	btn.label:SetPoint("CENTER", 0, 0)
	btn.label:SetText(label)
	Tint(btn.label, textColor)

	btn:SetScript("OnEnter", function(self)
		if self:IsEnabled() then
			Paint(self.fill, hoverColor)
		end
	end)
	btn:SetScript("OnLeave", function(self)
		if self:IsEnabled() then
			Paint(self.fill, fillColor)
		end
	end)
	btn:SetScript("OnDisable", function(self)
		Paint(self.fill, C.panel)
		Paint(self.edge, edgeColor, 0.4)
		Tint(self.label, C.faint)
	end)
	btn:SetScript("OnEnable", function(self)
		Paint(self.fill, fillColor)
		Paint(self.edge, edgeColor)
		Tint(self.label, textColor)
	end)

	function btn:SetLabel(text)
		self.label:SetText(text)
	end

	return btn
end

--- Size the button from its label plus padding, not a fixed width.
local DEV_LABEL_PAD = 16

local function MakeDevButton(parent, label)
	local btn = CreateFrame("Button", nil, parent)
	btn:RegisterForClicks("LeftButtonUp")

	btn.bg = btn:CreateTexture(nil, "BACKGROUND")
	btn.bg:SetAllPoints()
	Paint(btn.bg, DEV_MAGENTA)

	btn.label = MakeFont(btn, "GameFontNormalSmall", 11)
	btn.label:SetPoint("CENTER", 0, 0)
	btn.label:SetText(label)
	btn.label:SetTextColor(1, 1, 1)

	btn:SetSize(math.ceil(btn.label:GetStringWidth()) + DEV_LABEL_PAD * 2, 24)

	btn:SetScript("OnEnter", function(self)
		Paint(self.bg, DEV_MAGENTA_HOVER)
	end)
	btn:SetScript("OnLeave", function(self)
		Paint(self.bg, DEV_MAGENTA)
	end)
	return btn
end

local function FormatAgo(t)
	if type(t) ~= "number" or t <= 0 or not time then
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

local function FormatPlace(loc)
	if not loc or not loc.zone then
		return "Unknown place"
	end
	if loc.subzone and loc.subzone ~= loc.zone then
		return loc.zone .. " — " .. loc.subzone
	end
	return loc.zone
end

local COIN_SIZE = 12

local function Coin(amount, icon)
	return amount .. "|TInterface\\MoneyFrame\\" .. icon .. ":" .. COIN_SIZE .. ":" .. COIN_SIZE .. ":2:0|t"
end

--- Gold, silver, and copper icons. Uses the client string when it has one.
local function FormatMoney(copper)
	copper = math.floor(copper)
	if type(GetCoinTextureString) == "function" then
		local ok, text = pcall(GetCoinTextureString, copper)
		if ok and type(text) == "string" and text ~= "" then
			return text
		end
	end
	local gold = math.floor(copper / 10000)
	local silver = math.floor((copper % 10000) / 100)
	local left = copper % 100
	local parts = {}
	if gold > 0 then
		parts[#parts + 1] = Coin(gold, "UI-GoldIcon")
	end
	if silver > 0 then
		parts[#parts + 1] = Coin(silver, "UI-SilverIcon")
	end
	if left > 0 or #parts == 0 then
		parts[#parts + 1] = Coin(left, "UI-CopperIcon")
	end
	return table.concat(parts, " ")
end

--- The stored link is a real item link. Older entries only have a name.
local function FormatItem(item)
	if type(item) == "string" then
		return item
	end
	if type(item) ~= "table" then
		return nil
	end
	local label = item.link or item.name
	if type(label) ~= "string" or label == "" then
		return nil
	end
	if type(item.count) == "number" and item.count > 1 then
		return label .. " x" .. math.floor(item.count)
	end
	return label
end

local function JoinNamed(list)
	if type(list) ~= "table" then
		return nil
	end
	local names = {}
	for i = 1, #list do
		local name = FormatItem(list[i])
		if name then
			names[#names + 1] = name
		end
	end
	if #names == 0 then
		return nil
	end
	return table.concat(names, ", ")
end

local function FormatRewardLine(rewards)
	if type(rewards) ~= "table" then
		return nil
	end
	local lines = {}
	local given = {}
	if type(rewards.xp) == "number" and rewards.xp > 0 then
		given[#given + 1] = Hex(C.ink) .. math.floor(rewards.xp) .. " XP|r"
	end
	if type(rewards.money) == "number" and rewards.money > 0 then
		given[#given + 1] = FormatMoney(rewards.money)
	end
	local items = JoinNamed(rewards.items)
	if items then
		given[#given + 1] = items
	end
	local spells = JoinNamed(rewards.spells)
	if spells then
		given[#given + 1] = spells
	end
	if #given > 0 then
		lines[#lines + 1] = Hex(C.accent) .. "Rewards:|r " .. table.concat(given, ", ")
	end
	local choices = JoinNamed(rewards.choices)
	if choices then
		lines[#lines + 1] = Hex(C.accent) .. "Choose one:|r " .. choices
	end
	if #lines == 0 then
		return nil
	end
	return table.concat(lines, "\n")
end

--- Everything an NPC has said, newest first, as one block of colored text.
local function BuildConversationText(npc)
	local entries = npc.entries or {}
	if #entries == 0 then
		return ""
	end
	local out = {}
	for i = #entries, 1, -1 do
		local e = entries[i]
		local color = KIND_COLORS[e.kind] or C.muted
		local kind = Addon.KINDS[e.kind] or e.kind or "Line"
		local head = Hex(color) .. string.upper(kind)
		if e.title then
			head = head .. "  ·  " .. e.title
		end
		head = head .. "|r"

		local meta = FormatPlace({ zone = e.zone, subzone = e.subzone })
		if e.time and date then
			meta = meta .. "  ·  " .. date("%b %d %H:%M", e.time)
		end
		if (e.count or 1) > 1 then
			meta = meta .. "  ·  heard " .. e.count .. "x"
		end

		out[#out + 1] = head
		out[#out + 1] = Hex(C.faint) .. meta .. "|r"
		if e.text then
			out[#out + 1] = Hex(C.parchment) .. e.text .. "|r"
		end
		if e.objective then
			out[#out + 1] = Hex(C.accent) .. "Objective:|r " .. Hex(C.ink) .. e.objective .. "|r"
		end
		if e.rewards then
			local rewardLine = FormatRewardLine(e.rewards)
			if rewardLine then
				out[#out + 1] = rewardLine
			end
		end
		if e.options and #e.options > 0 then
			for _, option in ipairs(e.options) do
				out[#out + 1] = Hex(C.muted) .. "  › " .. option .. "|r"
			end
		end
		out[#out + 1] = " "
	end
	return table.concat(out, "\n")
end

local function SetSelected(key)
	selectedKey = key
	if journal then
		journal:DisarmRemove()
		journal.scroll:SetVerticalScroll(0)
		journal:Refresh()
	end
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

	btn.name = MakeFont(btn, "GameFontNormal", 12)
	btn.name:SetPoint("TOPLEFT", 12, -5)
	btn.name:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
	btn.name:SetJustifyH("LEFT")
	btn.name:SetWordWrap(false)

	btn.sub = MakeFont(btn, "GameFontDisableSmall", 10)
	btn.sub:SetPoint("TOPLEFT", btn.name, "BOTTOMLEFT", 0, -2)
	btn.sub:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
	btn.sub:SetJustifyH("LEFT")
	btn.sub:SetWordWrap(false)

	function btn:Paint()
		if self.entryKey and self.entryKey == selectedKey then
			Paint(self.bg, C.select)
			Paint(self.stripe, C.accent)
		elseif self.hovered then
			Paint(self.bg, C.hover)
			Paint(self.stripe, C.accentDim)
		else
			Paint(self.bg, self.rowIndex % 2 == 0 and C.rowB or C.rowA)
			Paint(self.stripe, C.faint, 0.5)
		end
	end

	btn:SetScript("OnEnter", function(self)
		self.hovered = true
		self:Paint()
	end)
	btn:SetScript("OnLeave", function(self)
		self.hovered = false
		self:Paint()
	end)
	btn:SetScript("OnClick", function(self)
		if self.entryKey then
			SetSelected(self.entryKey)
		end
	end)
	return btn
end

local function CreateJournal()
	local frame = CreateFrame("Frame", "ChronicleJournalFrame", UIParent)
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
		tinsert(UISpecialFrames, "ChronicleJournalFrame")
	end

	local outer = frame:CreateTexture(nil, "BACKGROUND")
	outer:SetDrawLayer("BACKGROUND", -8)
	outer:SetAllPoints()
	Paint(outer, C.accentDim)
	local inner = frame:CreateTexture(nil, "BACKGROUND")
	inner:SetDrawLayer("BACKGROUND", -7)
	inner:SetPoint("TOPLEFT", BORDER, -BORDER)
	inner:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
	Paint(inner, C.bg)

	-- Header
	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", BORDER, -BORDER)
	header:SetPoint("TOPRIGHT", -BORDER, -BORDER)
	header:SetHeight(HEADER_H)
	local headerFill = header:CreateTexture(nil, "BACKGROUND")
	headerFill:SetAllPoints()
	Paint(headerFill, C.void)
	local headerRule = header:CreateTexture(nil, "ARTWORK")
	headerRule:SetHeight(2)
	headerRule:SetPoint("BOTTOMLEFT", 0, 0)
	headerRule:SetPoint("BOTTOMRIGHT", 0, 0)
	Paint(headerRule, C.accent)

	frame.mark = WoWF.CreateCircleIcon(header, 40, "Interface\\AddOns\\Chronicle\\icon.tga", C.accent)
	local icon = frame.mark
	icon:SetPoint("LEFT", PAD, 1)

	frame.brand = MakeFont(header, "GameFontNormalLarge", 18)
	frame.brand:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -1)
	frame.brand:SetText("CHRONICLE")
	Tint(frame.brand, C.parchment)

	local brandSub = MakeFont(header, "GameFontDisableSmall", 10)
	brandSub:SetPoint("TOPLEFT", frame.brand, "BOTTOMLEFT", 0, -2)
	brandSub:SetText("EVERY WORD THEY SPOKE TO YOU")
	Tint(brandSub, C.accentDim)

	frame.close = MakeButton(header, "×", 26, 26)
	frame.close:SetPoint("RIGHT", -PAD, 0)
	frame.close.label:SetFont(frame.close.label:GetFont(), 16, "")
	frame.close:SetScript("OnClick", function()
		frame:Hide()
	end)

	-- Left column: search + NPC list
	local left = MakePanel(frame)
	left:SetPoint("TOPLEFT", PAD, -(HEADER_H + 12))
	left:SetPoint("BOTTOMLEFT", PAD, FOOTER_H)
	left:SetWidth(LIST_WIDTH + 16)

	local searchShell = MakePanel(left)
	searchShell:SetPoint("TOPLEFT", 8, -8)
	searchShell:SetPoint("TOPRIGHT", -8, -8)
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
	frame.searchHint:SetText("Search names, places, words…")
	Tint(frame.searchHint, C.faint)

	local function UpdateSearchHint()
		local hasText = (frame.search:GetText() or "") ~= ""
		if hasText or frame.search:HasFocus() then
			frame.searchHint:Hide()
		else
			frame.searchHint:Show()
		end
	end
	frame.search:SetScript("OnEditFocusGained", UpdateSearchHint)
	frame.search:SetScript("OnEditFocusLost", UpdateSearchHint)
	frame.search:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	frame.search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	frame.search:SetScript("OnTextChanged", function(self)
		searchText = self:GetText() or ""
		listOffset = 0
		UpdateSearchHint()
		frame:Refresh()
	end)

	frame.listLabel = MakeFont(left, "GameFontDisableSmall", 10)
	frame.listLabel:SetPoint("TOPLEFT", searchShell, "BOTTOMLEFT", 2, -10)
	frame.listLabel:SetText("NPCS  ·  MOST RECENT FIRST")
	Tint(frame.listLabel, C.accentDim)

	frame.listScroll = CreateFrame("ScrollFrame", nil, left)
	frame.listScroll:SetPoint("TOPLEFT", frame.listLabel, "BOTTOMLEFT", -2, -6)
	frame.listScroll:SetPoint("BOTTOMRIGHT", -8, 8)

	frame.listChild = CreateFrame("Frame", nil, frame.listScroll)
	frame.listChild:SetSize(LIST_WIDTH, VISIBLE_ROWS * ROW_HEIGHT)
	frame.listScroll:SetScrollChild(frame.listChild)

	frame.listScroll:EnableMouseWheel(true)
	frame.listScroll:SetScript("OnMouseWheel", function(_, delta)
		local list = Addon.GetNpcList(searchText)
		local maxOffset = math.max(0, #list - VISIBLE_ROWS)
		listOffset = math.min(maxOffset, math.max(0, listOffset - delta))
		frame:Refresh()
	end)

	for i = 1, VISIBLE_ROWS do
		listButtons[i] = CreateListRow(frame.listChild, i)
	end

	frame.listEmpty = MakeFont(left, "GameFontDisableSmall", 11)
	frame.listEmpty:SetPoint("TOP", frame.listScroll, "TOP", 0, -30)
	frame.listEmpty:SetWidth(LIST_WIDTH - 20)
	Tint(frame.listEmpty, C.faint)

	-- Right column: conversation
	local right = MakePanel(frame)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
	right:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_H)
	frame.right = right

	frame.emptyState = CreateFrame("Frame", nil, right)
	frame.emptyState:SetAllPoints()
	local emptyTitle = MakeFont(frame.emptyState, "GameFontNormalLarge", 16)
	emptyTitle:SetPoint("CENTER", 0, 20)
	emptyTitle:SetText("Nothing recorded yet")
	Tint(emptyTitle, C.parchment)
	local emptySub = MakeFont(frame.emptyState, "GameFontDisableSmall", 11)
	emptySub:SetPoint("TOP", emptyTitle, "BOTTOM", 0, -8)
	emptySub:SetWidth(340)
	emptySub:SetText("Talk to an NPC, open a quest, or stand near someone\nwho speaks. Every line lands here.")
	Tint(emptySub, C.muted)

	local detail = CreateFrame("Frame", nil, right)
	detail:SetAllPoints()
	frame.detail = detail

	frame.detailName = MakeFont(detail, "GameFontNormalLarge", 20)
	frame.detailName:SetPoint("TOPLEFT", 16, -14)
	frame.detailName:SetPoint("RIGHT", detail, "RIGHT", -16, 0)
	frame.detailName:SetJustifyH("LEFT")
	Tint(frame.detailName, C.parchment)

	frame.detailSub = MakeFont(detail, "GameFontHighlight", 12)
	frame.detailSub:SetPoint("TOPLEFT", frame.detailName, "BOTTOMLEFT", 0, -6)
	frame.detailSub:SetPoint("RIGHT", detail, "RIGHT", -16, 0)
	frame.detailSub:SetJustifyH("LEFT")
	Tint(frame.detailSub, C.muted)

	frame.detailMeta = MakeFont(detail, "GameFontDisableSmall", 10)
	frame.detailMeta:SetPoint("TOPLEFT", frame.detailSub, "BOTTOMLEFT", 0, -4)
	frame.detailMeta:SetJustifyH("LEFT")
	Tint(frame.detailMeta, C.faint)

	local rule = detail:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 14, -84)
	rule:SetPoint("TOPRIGHT", -14, -84)
	Paint(rule, C.edge)

	-- Scroll child starts at the top. The edit box is what makes item links hoverable.
	local textWidth = FRAME_WIDTH - PAD * 2 - (LIST_WIDTH + 16) - 10 - 32
	frame.scroll = CreateFrame("ScrollFrame", nil, detail)
	frame.scroll:SetPoint("TOPLEFT", 16, -94)
	frame.scroll:SetPoint("BOTTOMRIGHT", -16, 12)

	frame.child = CreateFrame("Frame", nil, frame.scroll)
	frame.child:SetSize(textWidth, 100)
	frame.scroll:SetScrollChild(frame.child)

	local font, _, flags = GameFontHighlight:GetFont()

	frame.measure = frame.child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.measure:SetPoint("TOPLEFT", 0, 0)
	frame.measure:SetWidth(textWidth - 8)
	frame.measure:SetJustifyH("LEFT")
	frame.measure:SetJustifyV("TOP")
	frame.measure:Hide()
	if font then
		frame.measure:SetFont(font, 12, flags or "")
	end

	frame.body = CreateFrame("EditBox", nil, frame.child)
	frame.body:SetMultiLine(true)
	frame.body:SetAutoFocus(false)
	frame.body:SetPoint("TOPLEFT", 0, 0)
	frame.body:SetWidth(textWidth - 8)
	frame.body:SetHeight(100)
	frame.body:SetJustifyH("LEFT")
	frame.body:SetTextInsets(0, 0, 0, 0)
	frame.body:EnableMouse(true)
	frame.body:EnableMouseWheel(true)
	frame.body:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
	if font then
		frame.body:SetFont(font, 12, flags or "")
	end
	if frame.body.SetHyperlinksEnabled then
		frame.body:SetHyperlinksEnabled(true)
	end
	if frame.body.EnableKeyboard then
		frame.body:EnableKeyboard(false)
	end

	local function ShowItemTooltip(owner, link)
		if not link or not GameTooltip or not GameTooltip.SetHyperlink then
			return
		end
		GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
		local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
		if ok then
			GameTooltip:Show()
		else
			GameTooltip:Hide()
		end
	end

	local function Wheel(self, delta)
		local scroll = frame.scroll
		local maxScroll = math.max(0, frame.child:GetHeight() - scroll:GetHeight())
		local target = (scroll:GetVerticalScroll() or 0) - delta * 48
		scroll:SetVerticalScroll(math.min(maxScroll, math.max(0, target)))
	end

	pcall(frame.body.SetScript, frame.body, "OnHyperlinkEnter", function(self, link)
		ShowItemTooltip(self, link)
	end)
	pcall(frame.body.SetScript, frame.body, "OnHyperlinkLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	pcall(frame.body.SetScript, frame.body, "OnHyperlinkClick", function(self, link, text, button)
		if IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
			ChatEdit_InsertLink(text)
			return
		end
		if SetItemRef then
			SetItemRef(link, text, button, self)
		else
			ShowItemTooltip(self, link)
		end
	end)
	frame.body:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	frame.body:SetScript("OnEditFocusGained", function(self)
		self:HighlightText(0, 0)
	end)
	frame.body:SetScript("OnTextChanged", function(self)
		if self.writing or not self.locked or self:GetText() == self.locked then
			return
		end
		self.writing = true
		self:SetText(self.locked)
		self.writing = false
	end)
	frame.body:SetScript("OnMouseWheel", Wheel)
	frame.scroll:EnableMouseWheel(true)
	frame.scroll:SetScript("OnMouseWheel", Wheel)

	-- Footer
	frame.removeBtn = MakeButton(frame, "Remove this NPC", 140, 24, true)
	frame.removeBtn:SetPoint("BOTTOMLEFT", PAD, 12)

	function frame:DisarmRemove()
		self.removeArmed = false
		self.removeBtn:SetLabel("Remove this NPC")
	end

	frame.removeBtn:SetScript("OnClick", function()
		if not selectedKey then
			return
		end
		if not frame.removeArmed then
			frame.removeArmed = true
			frame.removeBtn:SetLabel("Click again to confirm")
			if C_Timer and C_Timer.After then
				C_Timer.After(3, function()
					if frame.removeArmed then
						frame:DisarmRemove()
					end
				end)
			end
			return
		end
		frame:DisarmRemove()
		Addon.RemoveNpc(selectedKey)
	end)

	-- Dev-only. Built always; Refresh shows it only while WoWF.DevMode is on.
	frame.sampleBtn = MakeDevButton(frame, "Add sample")
	frame.sampleBtn:SetPoint("BOTTOMRIGHT", -PAD, 12)
	frame.sampleBtn:SetScript("OnClick", function()
		Addon.AddSample()
	end)

	frame.hint = MakeFont(frame, "GameFontDisableSmall", 10)
	frame.hint:SetPoint("BOTTOMRIGHT", -PAD, 18)
	frame.hint:SetText("Scroll to read  ·  Esc closes  ·  /ch help")
	Tint(frame.hint, C.faint)

	frame:SetScript("OnHide", function()
		frame.search:ClearFocus()
		frame:DisarmRemove()
	end)

	function frame:Refresh()
		local list, total = Addon.GetNpcList(searchText)
		listOffset = math.min(listOffset, math.max(0, #list - VISIBLE_ROWS))

		local selectedStillShown = false
		for _, item in ipairs(list) do
			if item.key == selectedKey then
				selectedStillShown = true
				break
			end
		end
		if not selectedStillShown then
			selectedKey = list[1] and list[1].key or nil
		end

		for i = 1, VISIBLE_ROWS do
			local btn = listButtons[i]
			local item = list[listOffset + i]
			if item then
				local npc = item.npc
				btn.entryKey = item.key
				btn.name:SetText(npc.name or "Unknown")
				Tint(btn.name, C.parchment)
				btn.sub:SetText(FormatPlace(npc.lastSeen) .. "  ·  " .. FormatAgo(npc.lastSeen and npc.lastSeen.time))
				btn:Paint()
				btn:Show()
			else
				btn.entryKey = nil
				btn:Hide()
			end
		end

		if total == 0 then
			self.listEmpty:SetText("No conversations yet.")
			self.listEmpty:Show()
		elseif #list == 0 then
			self.listEmpty:SetText("Nothing matches.")
			self.listEmpty:Show()
		else
			self.listEmpty:Hide()
		end

		local devOn = WoWF.DevMode and true or false
		self.sampleBtn:SetShown(devOn)
		self.hint:SetShown(not devOn)

		local npc = Addon.GetNpc(selectedKey)
		if not npc then
			self.removeBtn:Disable()
			self.detail:Hide()
			self.emptyState:Show()
			return
		end
		self.removeBtn:Enable()
		self.emptyState:Hide()
		self.detail:Show()

		self.detailName:SetText(npc.name or "Unknown")
		self.detailSub:SetText(string.format(
			"Last met in %s  ·  %s",
			FormatPlace(npc.lastSeen),
			FormatAgo(npc.lastSeen and npc.lastSeen.time)
		))
		self.detailMeta:SetText(string.format(
			"First met %s in %s",
			FormatAgo(npc.firstSeen and npc.firstSeen.time),
			FormatPlace(npc.firstSeen)
		))

		local text = BuildConversationText(npc)
		local width = (self.scroll:GetWidth() or 0) - 4
		if width < 40 then
			width = textWidth - 8
		end
		self.measure:SetWidth(width)
		self.body:SetWidth(width)
		self.measure:Show()
		self.measure:SetText(text)
		local height = self.measure:GetStringHeight() or 0
		self.measure:Hide()
		if height < 1 then
			local lines = 1
			for _ in string.gmatch(text, "\n") do
				lines = lines + 1
			end
			height = lines * 16
		end
		self.child:SetWidth(width)
		self.child:SetHeight(math.max(self.scroll:GetHeight() or 0, height + 16))
		self.body:SetHeight(height + 16)
		self.body.writing = true
		self.body.locked = text
		self.body:SetText(text)
		self.body.writing = false
	end

	return frame
end

local function EnsureJournal()
	if journal then
		return journal
	end
	local ok, result = pcall(CreateJournal)
	if not ok then
		print("|cff4dc7b8[Chronicle]|r Journal create failed: " .. tostring(result))
		return nil
	end
	journal = result
	return journal
end

function Addon.ShowJournal()
	if EnsureJournal() then
		journal:Show()
		journal:Refresh()
	end
end

function Addon.ToggleJournal()
	if journal and journal:IsShown() then
		journal:Hide()
	else
		Addon.ShowJournal()
	end
end

function Addon.RefreshJournal()
	if journal and journal:IsShown() then
		journal:Refresh()
	end
end
