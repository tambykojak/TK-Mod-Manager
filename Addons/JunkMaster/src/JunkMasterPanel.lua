local FRAME_WIDTH = 480
local FRAME_HEIGHT = 448
local ROW_HEIGHT = 28
local VISIBLE_ROWS = 10
local PAD = 16

local C = {
	bg = { 0.09, 0.09, 0.1, 0.98 },
	panel = { 0.13, 0.13, 0.15, 0.98 },
	panelHi = { 0.18, 0.18, 0.2, 1 },
	brass = { 0.9, 0.74, 0.4, 1 },
	brassDim = { 0.62, 0.5, 0.28, 1 },
	title = { 1, 0.97, 0.9, 1 },
	ink = { 0.97, 0.97, 0.95, 1 },
	muted = { 0.78, 0.76, 0.7, 1 },
	copper = { 1, 0.82, 0.5, 1 },
	poor = { 0.62, 0.62, 0.62, 1 },
	rowA = { 1, 1, 1, 0.04 },
	rowB = { 1, 1, 1, 0.08 },
	hover = { 1, 0.9, 0.55, 0.16 },
	void = { 0.07, 0.07, 0.08, 1 },
}

local panel
local listOffset = 0
local CLEAR_POPUP = "JUNKMASTER_CLEAR_LEDGER"

local function Paint(tex, color)
	local r, g, b, a = color[1], color[2], color[3], color[4] or 1
	if tex.SetColorTexture then
		tex:SetColorTexture(r, g, b, a)
		return
	end
	tex:SetTexture("Interface\\Buttons\\WHITE8X8")
	tex:SetVertexColor(r, g, b, a)
end

local function Tint(fs, color)
	fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
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

local function MakePanel(parent, w, h)
	local shell = CreateFrame("Frame", nil, parent)
	if w then
		shell:SetWidth(w)
	end
	if h then
		shell:SetHeight(h)
	end
	shell.edge = shell:CreateTexture(nil, "BORDER")
	shell.edge:SetAllPoints()
	Paint(shell.edge, C.brassDim)
	shell.fill = shell:CreateTexture(nil, "BACKGROUND")
	shell.fill:SetPoint("TOPLEFT", 1, -1)
	shell.fill:SetPoint("BOTTOMRIGHT", -1, 1)
	Paint(shell.fill, C.panel)
	shell.lip = shell:CreateTexture(nil, "ARTWORK")
	shell.lip:SetHeight(1)
	shell.lip:SetPoint("TOPLEFT", 1, -1)
	shell.lip:SetPoint("TOPRIGHT", -1, -1)
	Paint(shell.lip, C.brass)
	return shell
end

local function CornerMarks(parent, len, inset)
	len = len or 14
	inset = inset or 5
	local function tick(point, dx, dy, w, h)
		local tex = parent:CreateTexture(nil, "OVERLAY")
		tex:SetSize(w, h)
		tex:SetPoint(point, parent, point, dx, dy)
		Paint(tex, C.brass)
	end
	tick("TOPLEFT", inset, -inset, len, 1)
	tick("TOPLEFT", inset, -inset, 1, len)
	tick("TOPRIGHT", -inset, -inset, len, 1)
	tick("TOPRIGHT", -inset, -inset, 1, len)
	tick("BOTTOMLEFT", inset, inset, len, 1)
	tick("BOTTOMLEFT", inset, inset, 1, len)
	tick("BOTTOMRIGHT", -inset, inset, len, 1)
	tick("BOTTOMRIGHT", -inset, inset, 1, len)
end

local function SortedItems()
	local db = JunkMaster_GetDB()
	local rows = {}
	for _, entry in pairs(db.items) do
		if type(entry) == "table" then
			rows[#rows + 1] = entry
		end
	end
	table.sort(rows, function(a, b)
		local aCopper = tonumber(a.copper) or 0
		local bCopper = tonumber(b.copper) or 0
		if aCopper ~= bCopper then
			return aCopper > bCopper
		end
		local aCount = tonumber(a.count) or 0
		local bCount = tonumber(b.count) or 0
		if aCount ~= bCount then
			return aCount > bCount
		end
		return (a.name or "") < (b.name or "")
	end)
	return rows
end

local function PaintRow(btn)
	if btn.hover then
		Paint(btn.bg, C.hover)
		return
	end
	Paint(btn.bg, (btn.stripe or 1) % 2 == 0 and C.rowB or C.rowA)
end

local function HideTip()
	if GameTooltip then
		GameTooltip:Hide()
	end
end

local function ShowItemTip(owner, link)
	if not link or not GameTooltip or not GameTooltip.SetHyperlink then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
	if ok then
		GameTooltip:Show()
	else
		GameTooltip:Hide()
	end
end

local function ScrollList(delta)
	if not panel then
		return
	end
	local total = panel.rows and #panel.rows or 0
	local maxOffset = math.max(0, total - VISIBLE_ROWS)
	listOffset = math.min(maxOffset, math.max(0, listOffset - delta))
	panel:Refresh()
end

local function CreateRow(parent, index)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetHeight(ROW_HEIGHT)
	btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
	btn:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

	btn.bg = btn:CreateTexture(nil, "BACKGROUND")
	btn.bg:SetAllPoints()
	Paint(btn.bg, C.rowA)

	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetSize(20, 20)
	btn.icon:SetPoint("LEFT", 6, 0)
	btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	btn.name = MakeFont(btn, "GameFontHighlight", 12)
	btn.name:SetPoint("LEFT", 32, 0)
	btn.name:SetPoint("RIGHT", -168, 0)
	btn.name:SetJustifyH("LEFT")
	btn.name:SetWordWrap(false)

	btn.qty = MakeFont(btn, "GameFontHighlight", 12)
	btn.qty:SetPoint("RIGHT", -112, 0)
	btn.qty:SetWidth(48)
	btn.qty:SetJustifyH("RIGHT")
	Tint(btn.qty, C.ink)

	btn.value = MakeFont(btn, "GameFontHighlight", 12)
	btn.value:SetPoint("RIGHT", -8, 0)
	btn.value:SetWidth(96)
	btn.value:SetJustifyH("RIGHT")
	Tint(btn.value, C.copper)

	btn:EnableMouseWheel(true)
	btn:SetScript("OnMouseWheel", function(_, delta)
		ScrollList(delta)
	end)
	btn:SetScript("OnEnter", function(self)
		self.hover = true
		PaintRow(self)
		if self.entry then
			ShowItemTip(self, self.entry.link)
		end
	end)
	btn:SetScript("OnLeave", function(self)
		self.hover = false
		PaintRow(self)
		HideTip()
	end)

	return btn
end

local function ApplyRow(btn, entry, stripe)
	btn.entry = entry
	btn.stripe = stripe
	btn.hover = false
	if entry.icon then
		btn.icon:SetTexture(entry.icon)
		btn.icon:Show()
	else
		btn.icon:Hide()
	end
	btn.name:SetText(entry.name or "Unknown item")
	Tint(btn.name, C.poor)
	btn.qty:SetText(tostring(tonumber(entry.count) or 0))
	btn.value:SetText(JunkMaster_FormatMoney(entry.copper or 0))
	PaintRow(btn)
	btn:Show()
end

local function RestorePoint(frame)
	local db = JunkMaster_GetDB()
	if type(db.point) == "string" and type(db.x) == "number" and type(db.y) == "number" then
		frame:ClearAllPoints()
		frame:SetPoint(db.point, UIParent, db.relativePoint or db.point, db.x, db.y)
	end
end

local function SavePoint(frame)
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	if not point then
		return
	end
	local db = JunkMaster_GetDB()
	db.point = point
	db.relativePoint = relativePoint
	db.x = x
	db.y = y
end

local function EnsureClearPopup()
	if type(StaticPopupDialogs) ~= "table" then
		return false
	end
	if StaticPopupDialogs[CLEAR_POPUP] then
		return true
	end
	StaticPopupDialogs[CLEAR_POPUP] = {
		text = "Clear every recorded junk sale?",
		button1 = "Clear",
		button2 = "Cancel",
		OnAccept = function()
			JunkMaster_Reset()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	return true
end

local function CreatePanel()
	local frame = CreateFrame("Frame", "JunkMasterPanelFrame", UIParent)
	frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePoint(self)
	end)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:Hide()
	if UISpecialFrames then
		tinsert(UISpecialFrames, "JunkMasterPanelFrame")
	end

	local outer = frame:CreateTexture(nil, "BACKGROUND")
	outer:SetAllPoints()
	Paint(outer, C.void)

	local brassEdge = frame:CreateTexture(nil, "BORDER")
	brassEdge:SetAllPoints()
	Paint(brassEdge, C.brass)

	local gutter = frame:CreateTexture(nil, "ARTWORK")
	gutter:SetPoint("TOPLEFT", 1, -1)
	gutter:SetPoint("BOTTOMRIGHT", -1, 1)
	Paint(gutter, C.brassDim)

	local inner = frame:CreateTexture(nil, "OVERLAY")
	inner:SetPoint("TOPLEFT", 3, -3)
	inner:SetPoint("BOTTOMRIGHT", -3, 3)
	Paint(inner, C.bg)
	inner:SetDrawLayer("BACKGROUND", 1)

	CornerMarks(frame, 18, 6)

	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", 3, -3)
	header:SetPoint("TOPRIGHT", -3, -3)
	header:SetHeight(58)

	local headerFill = header:CreateTexture(nil, "BACKGROUND")
	headerFill:SetAllPoints()
	Paint(headerFill, { 0.03, 0.024, 0.018, 1 })

	local headerRule = header:CreateTexture(nil, "ARTWORK")
	headerRule:SetHeight(2)
	headerRule:SetPoint("BOTTOMLEFT", 0, 0)
	headerRule:SetPoint("BOTTOMRIGHT", 0, 0)
	Paint(headerRule, C.brass)

	local mark = MakeFont(header, "GameFontNormalLarge", 16)
	mark:SetPoint("LEFT", PAD, 4)
	mark:SetText("◆")
	Tint(mark, C.brass)

	local brand = MakeFont(header, "GameFontNormalLarge", 20)
	brand:SetPoint("LEFT", mark, "RIGHT", 8, 1)
	brand:SetText("JUNK MASTER")
	Tint(brand, C.title)

	local brandSub = MakeFont(header, "GameFontDisableSmall", 10)
	brandSub:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 0, -2)
	brandSub:SetText("GRAY JUNK SOLD")
	Tint(brandSub, C.brassDim)

	local close = CreateFrame("Button", nil, header)
	close:SetSize(24, 24)
	close:SetPoint("RIGHT", -14, 2)
	local closeEdge = close:CreateTexture(nil, "BORDER")
	closeEdge:SetAllPoints()
	Paint(closeEdge, C.brassDim)
	local closeBg = close:CreateTexture(nil, "BACKGROUND")
	closeBg:SetPoint("TOPLEFT", 1, -1)
	closeBg:SetPoint("BOTTOMRIGHT", -1, 1)
	Paint(closeBg, C.panelHi)
	close.label = MakeFont(close, "GameFontHighlight", 14)
	close.label:SetPoint("CENTER", 0, 1)
	close.label:SetText("×")
	Tint(close.label, C.muted)
	close:SetScript("OnEnter", function()
		Paint(closeEdge, C.brass)
		Paint(closeBg, C.hover)
		Tint(close.label, C.title)
	end)
	close:SetScript("OnLeave", function()
		Paint(closeEdge, C.brassDim)
		Paint(closeBg, C.panelHi)
		Tint(close.label, C.muted)
	end)
	close:SetScript("OnClick", function()
		HideTip()
		frame:Hide()
	end)

	local body = MakePanel(frame)
	body:SetPoint("TOPLEFT", PAD, -74)
	body:SetPoint("BOTTOMRIGHT", -PAD, 40)

	local statItems = MakePanel(body, 208, 52)
	statItems:SetPoint("TOPLEFT", 12, -12)
	Paint(statItems.fill, C.panelHi)
	statItems.caption = MakeFont(statItems, "GameFontDisableSmall", 9)
	statItems.caption:SetPoint("TOPLEFT", 10, -8)
	statItems.caption:SetText("ITEMS SOLD")
	Tint(statItems.caption, C.muted)
	statItems.value = MakeFont(statItems, "GameFontHighlight", 16)
	statItems.value:SetPoint("BOTTOMLEFT", 10, 8)
	statItems.value:SetPoint("BOTTOMRIGHT", -10, 8)
	statItems.value:SetJustifyH("LEFT")
	Tint(statItems.value, C.ink)
	frame.statItems = statItems

	local statCopper = MakePanel(body, 208, 52)
	statCopper:SetPoint("TOPLEFT", statItems, "TOPRIGHT", 8, 0)
	Paint(statCopper.fill, C.panelHi)
	statCopper.caption = MakeFont(statCopper, "GameFontDisableSmall", 9)
	statCopper.caption:SetPoint("TOPLEFT", 10, -8)
	statCopper.caption:SetText("COPPER EARNED")
	Tint(statCopper.caption, C.muted)
	statCopper.value = MakeFont(statCopper, "GameFontHighlight", 16)
	statCopper.value:SetPoint("BOTTOMLEFT", 10, 8)
	statCopper.value:SetPoint("BOTTOMRIGHT", -10, 8)
	statCopper.value:SetJustifyH("LEFT")
	Tint(statCopper.value, C.copper)
	frame.statCopper = statCopper

	local colItem = MakeFont(body, "GameFontDisableSmall", 9)
	colItem:SetPoint("TOPLEFT", statItems, "BOTTOMLEFT", 32, -14)
	colItem:SetText("ITEM")
	Tint(colItem, C.muted)

	local colQty = MakeFont(body, "GameFontDisableSmall", 9)
	colQty:SetPoint("TOPRIGHT", statCopper, "BOTTOMRIGHT", -112, -14)
	colQty:SetWidth(48)
	colQty:SetJustifyH("RIGHT")
	colQty:SetText("SOLD")
	Tint(colQty, C.muted)

	local colValue = MakeFont(body, "GameFontDisableSmall", 9)
	colValue:SetPoint("TOPRIGHT", statCopper, "BOTTOMRIGHT", -8, -14)
	colValue:SetWidth(96)
	colValue:SetJustifyH("RIGHT")
	colValue:SetText("VALUE")
	Tint(colValue, C.muted)

	local list = CreateFrame("Frame", nil, body)
	list:SetPoint("TOPLEFT", 12, -96)
	list:SetPoint("BOTTOMRIGHT", -12, 12)
	list:EnableMouse(true)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		ScrollList(delta)
	end)

	frame.empty = MakeFont(list, "GameFontDisable", 12)
	frame.empty:SetPoint("CENTER", 0, 8)
	frame.empty:SetText("Nothing sold yet.")
	Tint(frame.empty, C.muted)

	frame.buttons = {}
	for i = 1, VISIBLE_ROWS do
		frame.buttons[i] = CreateRow(list, i)
		frame.buttons[i]:Hide()
	end

	frame:SetScript("OnHide", HideTip)

	local PaintSpeedButton

	function frame:Refresh()
		local db = JunkMaster_GetDB()
		self.statItems.value:SetText(tostring(tonumber(db.itemsSold) or 0))
		self.statCopper.value:SetText(JunkMaster_FormatMoney(db.copperTotal or 0))

		self.rows = SortedItems()
		local maxOffset = math.max(0, #self.rows - VISIBLE_ROWS)
		if listOffset > maxOffset then
			listOffset = maxOffset
		end

		local empty = #self.rows == 0
		self.empty:SetShown(empty)
		for i = 1, VISIBLE_ROWS do
			local btn = self.buttons[i]
			local entry = self.rows[i + listOffset]
			if entry then
				ApplyRow(btn, entry, i + listOffset)
			else
				btn.entry = nil
				btn:Hide()
			end
		end

		local speed = JunkMaster_GetSpeed()
		for _, btn in ipairs(self.speedButtons) do
			PaintSpeedButton(btn, btn.speed == speed)
		end
	end

	local speedLabel = MakeFont(frame, "GameFontDisableSmall", 9)
	speedLabel:SetPoint("BOTTOMLEFT", PAD, 16)
	speedLabel:SetText("SPEED")
	Tint(speedLabel, C.brassDim)

	PaintSpeedButton = function(btn, selected)
		if selected then
			Paint(btn.edge, C.brass)
			Paint(btn.bg, C.hover)
			Tint(btn.label, C.title)
		elseif btn.hover then
			Paint(btn.edge, C.brass)
			Paint(btn.bg, C.panelHi)
			Tint(btn.label, C.ink)
		else
			Paint(btn.edge, C.brassDim)
			Paint(btn.bg, C.panelHi)
			Tint(btn.label, C.muted)
		end
	end

	local speedNames = { "slow", "medium", "fast" }
	local speedText = { slow = "Slow", medium = "Medium", fast = "Fast" }
	frame.speedButtons = {}
	for i, speed in ipairs(speedNames) do
		local btn = CreateFrame("Button", nil, frame)
		btn:SetSize(64, 22)
		btn:SetPoint("BOTTOMLEFT", PAD + 46 + (i - 1) * 68, 10)
		btn.speed = speed
		btn.edge = btn:CreateTexture(nil, "BORDER")
		btn.edge:SetAllPoints()
		btn.bg = btn:CreateTexture(nil, "BACKGROUND")
		btn.bg:SetPoint("TOPLEFT", 1, -1)
		btn.bg:SetPoint("BOTTOMRIGHT", -1, 1)
		btn.label = MakeFont(btn, "GameFontHighlight", 11)
		btn.label:SetPoint("CENTER", 0, 0)
		btn.label:SetText(speedText[speed])
		btn:SetScript("OnEnter", function(self)
			self.hover = true
			PaintSpeedButton(self, JunkMaster_GetSpeed() == self.speed)
		end)
		btn:SetScript("OnLeave", function(self)
			self.hover = false
			PaintSpeedButton(self, JunkMaster_GetSpeed() == self.speed)
		end)
		btn:SetScript("OnClick", function(self)
			JunkMaster_SetSpeed(self.speed)
		end)
		frame.speedButtons[i] = btn
	end

	local clearBtn = CreateFrame("Button", nil, frame)
	clearBtn:SetSize(64, 22)
	clearBtn:SetPoint("BOTTOMRIGHT", -PAD, 10)
	local clearEdge = clearBtn:CreateTexture(nil, "BORDER")
	clearEdge:SetAllPoints()
	Paint(clearEdge, C.brassDim)
	local clearBg = clearBtn:CreateTexture(nil, "BACKGROUND")
	clearBg:SetPoint("TOPLEFT", 1, -1)
	clearBg:SetPoint("BOTTOMRIGHT", -1, 1)
	Paint(clearBg, C.panelHi)
	clearBtn.label = MakeFont(clearBtn, "GameFontHighlight", 11)
	clearBtn.label:SetPoint("CENTER", 0, 0)
	clearBtn.label:SetText("Clear")
	Tint(clearBtn.label, C.muted)
	clearBtn:SetScript("OnEnter", function()
		Paint(clearEdge, C.brass)
		Paint(clearBg, C.hover)
		Tint(clearBtn.label, C.title)
	end)
	clearBtn:SetScript("OnLeave", function()
		Paint(clearEdge, C.brassDim)
		Paint(clearBg, C.panelHi)
		Tint(clearBtn.label, C.muted)
	end)
	clearBtn:SetScript("OnClick", function()
		HideTip()
		if EnsureClearPopup() and StaticPopup_Show then
			StaticPopup_Show(CLEAR_POPUP)
			return
		end
		JunkMaster_Reset()
	end)

	RestorePoint(frame)
	frame:Refresh()
	return frame
end

function JunkMasterPanel_Refresh()
	if panel and panel.Refresh then
		panel:Refresh()
	end
end

function JunkMasterPanel_Toggle()
	if not panel then
		panel = CreatePanel()
	end
	if panel:IsShown() then
		panel:Hide()
		return
	end
	panel:Refresh()
	panel:Show()
end
