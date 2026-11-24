local ADDON_NAME, Addon = ...

local PANEL_WIDTH = 440
local PANEL_HEIGHT = 470

local STYLE_OPTIONS = {
	{ value = "native", text = "Classic" },
	{ value = "wending", text = "WenDing" },
	{ value = "custom", text = "Custom" },
}

--- Custom-only color rows: dbKey, label, whether alpha is editable.
local COLOR_ROWS = {
	{
		key = "xpColor",
		label = "Experience Color",
		defaultKey = "DEFAULT_XP_COLOR",
		hasOpacity = false,
	},
	{
		key = "bgColor",
		label = "Background Color",
		defaultKey = "DEFAULT_BG_COLOR",
		hasOpacity = true,
	},
	{
		key = "fontColor",
		label = "Font Color",
		defaultKey = "DEFAULT_FONT_COLOR",
		hasOpacity = false,
	},
}

local INFO_TOGGLES = {
	{ key = "showPct", label = "Percent (left)" },
	{ key = "showXP", label = "Current / max XP (center)" },
	{ key = "showXPPerHour", label = "XP / hour (right)" },
	{ key = "showETA", label = "ETA to level (right)" },
}

local panel

local function SetSolidColor(texture, r, g, b, a)
	a = a or 1
	if texture.SetColorTexture then
		texture:SetColorTexture(r, g, b, a)
		return
	end
	texture:SetTexture("Interface\\Buttons\\WHITE8X8")
	texture:SetVertexColor(r, g, b, a)
end

local function StyleLabel(value)
	for _, opt in ipairs(STYLE_OPTIONS) do
		if opt.value == value then
			return opt.text
		end
	end
	return "Classic"
end

local function DefaultFor(row)
	return Addon[row.defaultKey] or { r = 1, g = 1, b = 1, a = 1 }
end

local function RefreshStyleControls()
	if not panel or not panel.stylePage then
		return
	end
	local db = Addon.EnsureDB()
	local styleType = db.styleType or "native"
	if panel.styleDropdownLabel then
		panel.styleDropdownLabel:SetText(StyleLabel(styleType))
	end
	local showCustom = styleType == "custom"
	if panel.customColors then
		panel.customColors:SetShown(showCustom)
	end
	if showCustom and panel.colorSwatches then
		for _, row in ipairs(COLOR_ROWS) do
			local swatch = panel.colorSwatches[row.key]
			if swatch then
				local c = db[row.key] or DefaultFor(row)
				local a = row.hasOpacity and (c.a ~= nil and c.a or 1) or 1
				swatch.tex:SetVertexColor(c.r or 1, c.g or 1, c.b or 1, a)
			end
		end
	end
end

local function RefreshInfoPage()
	if not panel or not panel.infoPage then
		return
	end
	local db = Addon.EnsureDB()
	for _, toggle in ipairs(INFO_TOGGLES) do
		local cb = panel.infoChecks[toggle.key]
		if cb then
			cb:SetChecked(db[toggle.key] ~= false)
		end
	end
	if panel.infoTimesText then
		local lines = Addon.GetLevelTimesLines and Addon.GetLevelTimesLines()
			or { "No milestone data yet." }
		local width = PANEL_WIDTH - 80
		panel.infoTimesText:SetWidth(width)
		panel.infoTimesText:SetText(table.concat(lines, "\n"))
		local height = panel.infoTimesText:GetStringHeight() or 40
		if panel.infoTimesChild then
			panel.infoTimesChild:SetSize(width, math.max(height + 8, 40))
		end
	end
end

local NUDGE_STEP = 1
local NUDGE_STEP_SHIFT = 10

local function ReadCurrentPosition()
	local x, y = 0, 0
	if Addon.GetFramePosition then
		x, y = Addon.GetFramePosition()
	end
	return tonumber(x) or 0, tonumber(y) or 0
end

local function ApplyPositionFromFields()
	if not panel or not Addon.SetFramePosition then
		return
	end
	local x = panel.posXEdit and tonumber(panel.posXEdit:GetText())
	local y = panel.posYEdit and tonumber(panel.posYEdit:GetText())
	if x == nil or y == nil then
		return
	end
	Addon.SetFramePosition(x, y)
end

local function ApplySizeFromField(which)
	if not panel then
		return
	end
	if which == "width" and panel.widthEdit then
		local v = tonumber(panel.widthEdit:GetText())
		if v and Addon.SetBarWidth then
			Addon.SetBarWidth(v)
		end
	elseif which == "height" and panel.heightEdit then
		local v = tonumber(panel.heightEdit:GetText())
		if v and Addon.SetBarHeight then
			Addon.SetBarHeight(v)
		end
	end
end

local function LayoutEditFocused()
	return (panel.posXEdit and panel.posXEdit:HasFocus())
		or (panel.posYEdit and panel.posYEdit:HasFocus())
		or (panel.widthEdit and panel.widthEdit:HasFocus())
		or (panel.heightEdit and panel.heightEdit:HasFocus())
end

--- A focused box keeps its old text, and RefreshLayoutPage skips it. Drop focus
--- before a button applies a change, and ignore the blur so the old text is not
--- written back over the button.
local ignoreLayoutCommit = false

local function ClearLayoutFocus()
	if not panel then
		return
	end
	ignoreLayoutCommit = true
	for _, edit in ipairs({ panel.posXEdit, panel.posYEdit, panel.widthEdit, panel.heightEdit }) do
		if edit and edit:HasFocus() then
			edit:ClearFocus()
		end
	end
	ignoreLayoutCommit = false
end

local function RefreshLayoutPage()
	if not panel or not panel.layoutPage then
		return
	end
	-- Don't clobber text while the user is typing.
	if LayoutEditFocused() then
		return
	end
	local x, y = ReadCurrentPosition()
	if panel.posXEdit then
		panel.posXEdit:SetText(string.format("%.1f", x))
	end
	if panel.posYEdit then
		panel.posYEdit:SetText(string.format("%.1f", y))
	end
	local width = Addon.GetBarWidth and Addon.GetBarWidth() or 1000
	if panel.widthEdit then
		panel.widthEdit:SetText(tostring(width))
	end
	if panel.widthSlider then
		panel.widthSlider._suppress = true
		panel.widthSlider:SetValue(width)
		panel.widthSlider._suppress = false
	end
	local height = Addon.GetBarHeight and Addon.GetBarHeight() or 13
	if panel.heightEdit then
		panel.heightEdit:SetText(tostring(height))
	end
	if panel.heightSlider then
		panel.heightSlider._suppress = true
		panel.heightSlider:SetValue(height)
		panel.heightSlider._suppress = false
	end
	if panel.layoutHint then
		panel.layoutHint:SetText("X=0 is UI center. Compass moves the bar; Shift nudges ×10.")
	end
end

local function RefreshDevPage()
	if not panel or not panel.devPage then
		return
	end
	local liveXP, liveMax = 0, 1
	if Addon.GetLivePlayerXP then
		liveXP, liveMax = Addon.GetLivePlayerXP()
	end
	local overXP, overMax = Addon.GetXPOverride and Addon.GetXPOverride()
	local active = Addon.IsXPOverrideActive and Addon.IsXPOverrideActive()
	if panel.devStatus then
		if active then
			panel.devStatus:SetText(string.format(
				"Override ON — using %s / %s (live %s / %s)",
				tostring(overXP),
				tostring(overMax),
				tostring(liveXP),
				tostring(liveMax)
			))
		else
			panel.devStatus:SetText(string.format(
				"Override OFF — live %s / %s (sim starts an override)",
				tostring(liveXP),
				tostring(liveMax)
			))
		end
	end
	if panel.devOverrideXP and not panel.devOverrideXP:HasFocus() then
		panel.devOverrideXP:SetText(tostring(overXP or liveXP))
	end
	if panel.devOverrideMax and not panel.devOverrideMax:HasFocus() then
		panel.devOverrideMax:SetText(tostring(overMax or liveMax))
	end
end

local function SelectTab(index)
	if not panel then
		return
	end
	-- Dev tab only while development mode is on.
	if index == 4 and not (WoWF and WoWF.DevMode) then
		index = 1
	end
	panel.selectedTab = index
	for i, tab in ipairs(panel.tabs) do
		local active = i == index
		tab:SetNormalFontObject(active and "GameFontHighlight" or "GameFontNormal")
		if active then
			SetSolidColor(tab.bg, 0.2, 0.45, 0.8, 0.45)
		else
			SetSolidColor(tab.bg, 0.15, 0.15, 0.18, 0.8)
		end
	end
	panel.infoPage:SetShown(index == 1)
	panel.stylePage:SetShown(index == 2)
	if panel.layoutPage then
		panel.layoutPage:SetShown(index == 3)
	end
	if panel.devPage then
		panel.devPage:SetShown(index == 4)
	end
	if index == 1 then
		RefreshInfoPage()
	elseif index == 2 then
		RefreshStyleControls()
	elseif index == 3 then
		RefreshLayoutPage()
	elseif index == 4 then
		RefreshDevPage()
	end
end

local function SyncDevTabVisibility()
	if not panel or not panel.devTab then
		return
	end
	local show = WoWF and WoWF.DevMode and true or false
	panel.devTab:SetShown(show)
	if not show and panel.selectedTab == 4 then
		SelectTab(1)
	end
end

local function CloseStyleMenu()
	if panel and panel.styleMenu then
		panel.styleMenu:Hide()
	end
end

local function OpenColorPicker(row)
	local db = Addon.EnsureDB()
	local fallback = DefaultFor(row)
	local c = db[row.key] or fallback
	local r, g, b = c.r or fallback.r, c.g or fallback.g, c.b or fallback.b
	local a = c.a ~= nil and c.a or (fallback.a ~= nil and fallback.a or 1)
	local hasOpacity = row.hasOpacity and true or false

	local function apply(nr, ng, nb, na)
		local saved = { r = nr, g = ng, b = nb }
		if hasOpacity then
			saved.a = na
		end
		db[row.key] = saved
		Addon.ApplyBarStyle()
		RefreshStyleControls()
	end

	local function readRGB()
		if ColorPickerFrame.GetColorRGB then
			return ColorPickerFrame:GetColorRGB()
		end
		return r, g, b
	end

	local function readAlpha()
		if not hasOpacity then
			return 1
		end
		if ColorPickerFrame.GetColorAlpha then
			return ColorPickerFrame:GetColorAlpha()
		end
		if ColorPickerFrame.opacity then
			-- Classic often stores transparency inverted; prefer GetColorAlpha when present.
			return 1 - (ColorPickerFrame.opacity or 0)
		end
		return a
	end

	local function onChanged()
		local nr, ng, nb = readRGB()
		apply(nr, ng, nb, readAlpha())
	end

	local function onCancel()
		if ColorPickerFrame.GetPreviousValues then
			local pr, pg, pb, pa = ColorPickerFrame:GetPreviousValues()
			if pr ~= nil then
				apply(pr, pg, pb, hasOpacity and (pa ~= nil and pa or a) or 1)
				return
			end
		end
		apply(r, g, b, a)
	end

	if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r,
			g = g,
			b = b,
			opacity = a,
			hasOpacity = hasOpacity,
			swatchFunc = onChanged,
			opacityFunc = hasOpacity and onChanged or nil,
			cancelFunc = onCancel,
		})
		return
	end

	-- Classic-style fallback.
	ColorPickerFrame.func = onChanged
	ColorPickerFrame.opacityFunc = hasOpacity and onChanged or nil
	ColorPickerFrame.cancelFunc = function()
		apply(r, g, b, a)
	end
	ColorPickerFrame.hasOpacity = hasOpacity
	if hasOpacity then
		ColorPickerFrame.opacity = 1 - a
	end
	ColorPickerFrame:SetColorRGB(r, g, b)
	if ShowUIPanel then
		ShowUIPanel(ColorPickerFrame)
	else
		ColorPickerFrame:Show()
	end
end

local function CreateColorSwatch(parent)
	local swatch = CreateFrame("Button", nil, parent)
	swatch:SetSize(28, 28)
	local border = swatch:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	SetSolidColor(border, 0.7, 0.7, 0.7, 1)
	local tex = swatch:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("TOPLEFT", 2, -2)
	tex:SetPoint("BOTTOMRIGHT", -2, 2)
	tex:SetTexture("Interface\\Buttons\\WHITE8X8")
	tex:SetVertexColor(1, 1, 1, 1)
	swatch.tex = tex
	return swatch
end

local function CreateCheckbox(parent, label, onChange)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(PANEL_WIDTH - 48, 24)

	local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	cb:SetPoint("LEFT", 0, 0)
	cb:SetSize(24, 24)
	cb:SetScript("OnClick", function(self)
		onChange(self:GetChecked() and true or false)
	end)

	local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	text:SetText(label)

	row.check = cb
	return row, cb
end

local function CreateTabButton(parent, text, index)
	local tab = CreateFrame("Button", nil, parent)
	tab:SetSize(96, 28)
	tab.bg = tab:CreateTexture(nil, "BACKGROUND")
	tab.bg:SetAllPoints()
	SetSolidColor(tab.bg, 0.15, 0.15, 0.18, 0.8)

	tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	tab.label:SetPoint("CENTER")
	tab.label:SetText(text)

	tab:SetScript("OnClick", function()
		CloseStyleMenu()
		SelectTab(index)
	end)
	tab:SetScript("OnEnter", function(self)
		if panel.selectedTab ~= index then
			SetSolidColor(self.bg, 0.25, 0.25, 0.3, 0.9)
		end
	end)
	tab:SetScript("OnLeave", function(self)
		if panel.selectedTab ~= index then
			SetSolidColor(self.bg, 0.15, 0.15, 0.18, 0.8)
		end
	end)
	return tab
end

local function CreatePanel()
	local frame = CreateFrame("Frame", "WenDingPanelFrame", UIParent)
	frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:Hide()
	if UISpecialFrames then
		tinsert(UISpecialFrames, "WenDingPanelFrame")
	end

	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true,
			tileSize = 32,
			edgeSize = 32,
			insets = { left = 8, right = 8, top = 8, bottom = 8 },
		})
		if frame.SetBackdropColor then
			frame:SetBackdropColor(0, 0, 0, 0.9)
		end
	else
		local bg = frame:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		SetSolidColor(bg, 0.05, 0.05, 0.08, 0.95)
	end

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("TOP", 0, -16)
	frame.title:SetText("WenDing")

	frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close:SetPoint("TOPRIGHT", -4, -4)
	frame.close:SetScript("OnClick", function()
		CloseStyleMenu()
		frame:Hide()
	end)

	frame.tabs = {}
	local infoTab = CreateTabButton(frame, "Information", 1)
	infoTab:SetPoint("TOPLEFT", 16, -48)
	frame.tabs[1] = infoTab

	local styleTab = CreateTabButton(frame, "Style", 2)
	styleTab:SetPoint("LEFT", infoTab, "RIGHT", 4, 0)
	frame.tabs[2] = styleTab

	local layoutTab = CreateTabButton(frame, "Layout", 3)
	layoutTab:SetPoint("LEFT", styleTab, "RIGHT", 4, 0)
	frame.tabs[3] = layoutTab

	local devTab = CreateTabButton(frame, "Dev", 4)
	devTab:SetPoint("LEFT", layoutTab, "RIGHT", 4, 0)
	frame.tabs[4] = devTab
	frame.devTab = devTab

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", 16, -84)
	content:SetPoint("BOTTOMRIGHT", -16, 16)
	frame.content = content

	-- Information page
	local infoPage = CreateFrame("Frame", nil, content)
	infoPage:SetAllPoints()
	frame.infoPage = infoPage

	local infoHint = infoPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	infoHint:SetPoint("TOPLEFT", 8, -4)
	infoHint:SetPoint("RIGHT", -8, 0)
	infoHint:SetJustifyH("LEFT")
	infoHint:SetText("Overlay toggles")

	frame.infoChecks = {}
	local y = -24
	for _, toggle in ipairs(INFO_TOGGLES) do
		local row, cb = CreateCheckbox(infoPage, toggle.label, function(checked)
			local db = Addon.EnsureDB()
			db[toggle.key] = checked
			Addon.RefreshBarOverlay()
			RefreshInfoPage()
		end)
		row:SetPoint("TOPLEFT", 8, y)
		frame.infoChecks[toggle.key] = cb
		y = y - 26
	end

	local timesTitle = infoPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	timesTitle:SetPoint("TOPLEFT", 8, y - 8)
	timesTitle:SetText("Level times")

	local timesScroll = CreateFrame("ScrollFrame", "WenDingInfoTimesScroll", infoPage, "UIPanelScrollFrameTemplate")
	timesScroll:SetPoint("TOPLEFT", 8, y - 28)
	timesScroll:SetPoint("BOTTOMRIGHT", -28, 8)

	local timesChild = CreateFrame("Frame", nil, timesScroll)
	timesChild:SetSize(PANEL_WIDTH - 80, 40)
	timesScroll:SetScrollChild(timesChild)
	frame.infoTimesChild = timesChild

	local timesText = timesChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	timesText:SetPoint("TOPLEFT", 0, 0)
	timesText:SetJustifyH("LEFT")
	timesText:SetJustifyV("TOP")
	timesText:SetNonSpaceWrap(true)
	timesText:SetText("No milestone data yet.")
	frame.infoTimesText = timesText

	-- Style page
	local stylePage = CreateFrame("Frame", nil, content)
	stylePage:SetAllPoints()
	stylePage:Hide()
	frame.stylePage = stylePage

	local typeLabel = stylePage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	typeLabel:SetPoint("TOPLEFT", 8, -8)
	typeLabel:SetText("Type")

	local dropdown = CreateFrame("Button", nil, stylePage)
	dropdown:SetSize(180, 26)
	dropdown:SetPoint("LEFT", typeLabel, "RIGHT", 12, 0)
	local dropBg = dropdown:CreateTexture(nil, "BACKGROUND")
	dropBg:SetAllPoints()
	SetSolidColor(dropBg, 0.1, 0.1, 0.12, 0.95)
	local dropBorder = dropdown:CreateTexture(nil, "BORDER")
	dropBorder:SetPoint("TOPLEFT", -1, 1)
	dropBorder:SetPoint("BOTTOMRIGHT", 1, -1)
	SetSolidColor(dropBorder, 0.4, 0.4, 0.45, 1)
	dropBorder:SetDrawLayer("BACKGROUND", -1)

	frame.styleDropdownLabel = dropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.styleDropdownLabel:SetPoint("LEFT", 8, 0)
	frame.styleDropdownLabel:SetPoint("RIGHT", -20, 0)
	frame.styleDropdownLabel:SetJustifyH("LEFT")
	frame.styleDropdownLabel:SetText("Classic")

	local arrow = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	arrow:SetPoint("RIGHT", -6, 0)
	arrow:SetText("v")

	local menu = CreateFrame("Frame", "WenDingStyleMenu", UIParent)
	menu:SetSize(180, #STYLE_OPTIONS * 24 + 8)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetToplevel(true)
	menu:Hide()
	local menuBg = menu:CreateTexture(nil, "BACKGROUND")
	menuBg:SetAllPoints()
	SetSolidColor(menuBg, 0.08, 0.08, 0.1, 0.98)
	frame.styleMenu = menu

	for i, opt in ipairs(STYLE_OPTIONS) do
		local item = CreateFrame("Button", nil, menu)
		item:SetSize(172, 22)
		item:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 24)
		item.label = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		item.label:SetPoint("LEFT", 6, 0)
		item.label:SetText(opt.text)
		item:SetScript("OnEnter", function(self)
			local hl = self.hl
			if not hl then
				hl = self:CreateTexture(nil, "HIGHLIGHT")
				hl:SetAllPoints()
				SetSolidColor(hl, 0.2, 0.45, 0.8, 0.4)
				self.hl = hl
			end
		end)
		item:SetScript("OnClick", function()
			local db = Addon.EnsureDB()
			db.styleType = opt.value
			Addon.ApplyBarStyle()
			CloseStyleMenu()
			RefreshStyleControls()
		end)
	end

	dropdown:SetScript("OnClick", function()
		if menu:IsShown() then
			menu:Hide()
			return
		end
		menu:ClearAllPoints()
		menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
		menu:Show()
	end)

	-- Custom colors: experience fill, empty-track background (+ opacity), overlay font.
	local customColors = CreateFrame("Frame", nil, stylePage)
	customColors:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -20)
	customColors:SetPoint("RIGHT", stylePage, "RIGHT", -8, 0)
	customColors:SetHeight(#COLOR_ROWS * 36)
	customColors:Hide()
	frame.customColors = customColors
	frame.colorSwatches = {}

	local customHint = customColors:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	customHint:SetPoint("TOPLEFT", 0, 0)
	customHint:SetPoint("RIGHT", 0, 0)
	customHint:SetJustifyH("LEFT")
	customHint:SetText("Background Color supports opacity in the color picker.")

	for i, row in ipairs(COLOR_ROWS) do
		local rowFrame = CreateFrame("Frame", nil, customColors)
		rowFrame:SetSize(PANEL_WIDTH - 48, 32)
		rowFrame:SetPoint("TOPLEFT", 0, -18 - (i - 1) * 36)

		local label = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("LEFT", 0, 0)
		label:SetWidth(140)
		label:SetJustifyH("LEFT")
		label:SetText(row.label)

		local swatch = CreateColorSwatch(rowFrame)
		swatch:SetPoint("LEFT", label, "RIGHT", 12, 0)
		swatch:SetScript("OnClick", function()
			OpenColorPicker(row)
		end)
		frame.colorSwatches[row.key] = swatch

		if row.hasOpacity then
			local opacityHint = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			opacityHint:SetPoint("LEFT", swatch, "RIGHT", 10, 0)
			opacityHint:SetText("(+ opacity)")
		end
	end

	-- Layout page: one control pattern for position + size.
	--   Label  [-]  [edit]  [+]  [slider…]
	local layoutPage = CreateFrame("Frame", nil, content)
	layoutPage:SetAllPoints()
	layoutPage:Hide()
	frame.layoutPage = layoutPage

	local function SectionLabel(text, yOff)
		local fs = layoutPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		fs:SetPoint("TOPLEFT", 8, yOff)
		fs:SetPoint("RIGHT", -8, 0)
		fs:SetJustifyH("LEFT")
		fs:SetText(text)
		return fs
	end

	SectionLabel("Position", -4)

	local function NudgeStep(base)
		if IsShiftKeyDown and IsShiftKeyDown() then
			return (base or NUDGE_STEP) * (NUDGE_STEP_SHIFT / NUDGE_STEP)
		end
		return base or NUDGE_STEP
	end

	local function AddTip(btn, text)
		btn:SetScript("OnEnter", function(self)
			if GameTooltip then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(text, 1, 0.82, 0)
				GameTooltip:Show()
			end
		end)
		btn:SetScript("OnLeave", function()
			if GameTooltip then
				GameTooltip:Hide()
			end
		end)
	end

	local function NudgePosition(dx, dy)
		ClearLayoutFocus()
		local x, y = ReadCurrentPosition()
		local step = NudgeStep(NUDGE_STEP)
		x = x + dx * step
		y = y + dy * step
		if Addon.SetFramePosition then
			Addon.SetFramePosition(x, y)
		end
		RefreshLayoutPage()
	end

	-- Compass pad: ↑ ↓ ← →  (Y+ up, X+ right)
	local compass = CreateFrame("Frame", nil, layoutPage)
	compass:SetSize(108, 96)
	compass:SetPoint("TOPLEFT", 16, -28)

	local btnSize = 32
	local function MakeCompassBtn(label, dx, dy, point, relPoint, ox, oy, tip)
		local btn = CreateFrame("Button", nil, compass, "UIPanelButtonTemplate")
		btn:SetSize(btnSize, 26)
		btn:SetText(label)
		btn:SetPoint(point, compass, relPoint, ox, oy)
		btn:SetScript("OnClick", function()
			NudgePosition(dx, dy)
		end)
		AddTip(btn, tip)
		return btn
	end

	MakeCompassBtn("^", 0, 1, "TOP", "TOP", 0, 0, "Move up")
	MakeCompassBtn("v", 0, -1, "BOTTOM", "BOTTOM", 0, 0, "Move down")
	MakeCompassBtn("<", -1, 0, "LEFT", "LEFT", 0, 0, "Move left")
	MakeCompassBtn(">", 1, 0, "RIGHT", "RIGHT", 0, 0, "Move right")

	local function MakeCoordEdit(labelText, yOff)
		local row = CreateFrame("Frame", nil, layoutPage)
		row:SetSize(160, 24)
		row:SetPoint("TOPLEFT", compass, "TOPRIGHT", 24, yOff)

		local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("LEFT", 0, 0)
		label:SetWidth(20)
		label:SetText(labelText)

		local edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
		edit:SetSize(80, 20)
		edit:SetPoint("LEFT", label, "RIGHT", 8, 0)
		edit:SetAutoFocus(false)
		edit:SetNumeric(false)
		edit:SetMaxLetters(10)
		edit:SetJustifyH("CENTER")
		edit:SetText("0.0")
		edit:SetScript("OnEnterPressed", function(self)
			ApplyPositionFromFields()
			self:ClearFocus()
			RefreshLayoutPage()
		end)
		edit:SetScript("OnEditFocusLost", function()
			if ignoreLayoutCommit then
				return
			end
			ApplyPositionFromFields()
			RefreshLayoutPage()
		end)
		edit:SetScript("OnEscapePressed", function(self)
			self:ClearFocus()
			RefreshLayoutPage()
		end)
		return edit
	end

	frame.posXEdit = MakeCoordEdit("X", -8)
	frame.posYEdit = MakeCoordEdit("Y", -40)

	--- Shared size row: label | - | edit | + | slider.
	local function MakeArrow(parent, text, onClick)
		local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		btn:SetSize(28, 22)
		btn:SetText(text)
		btn:SetScript("OnClick", onClick)
		return btn
	end

	local function MakeValueRow(opts)
		local row = CreateFrame("Frame", nil, layoutPage)
		row:SetSize(PANEL_WIDTH - 48, 28)
		row:SetPoint("TOPLEFT", 8, opts.yOff)

		local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("LEFT", 0, 0)
		label:SetWidth(opts.labelWidth or 44)
		label:SetJustifyH("LEFT")
		label:SetText(opts.label)

		local function commitEdit(self)
			if opts.onCommit then
				opts.onCommit(self)
			end
			self:ClearFocus()
			RefreshLayoutPage()
		end

		local minus = MakeArrow(row, "-", function()
			ClearLayoutFocus()
			if opts.onNudge then
				opts.onNudge(-1)
			end
			RefreshLayoutPage()
		end)
		minus:SetPoint("LEFT", label, "RIGHT", 4, 0)

		local edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
		edit:SetSize(opts.editWidth or 72, 20)
		edit:SetPoint("LEFT", minus, "RIGHT", 6, 0)
		edit:SetAutoFocus(false)
		edit:SetNumeric(false)
		edit:SetMaxLetters(opts.maxLetters or 10)
		edit:SetJustifyH("CENTER")
		edit:SetText(opts.initialText or "0")
		edit:SetScript("OnEnterPressed", commitEdit)
		edit:SetScript("OnEditFocusLost", function(self)
			if ignoreLayoutCommit then
				return
			end
			if opts.onCommit then
				opts.onCommit(self)
			end
			RefreshLayoutPage()
		end)
		edit:SetScript("OnEscapePressed", function(self)
			self:ClearFocus()
			RefreshLayoutPage()
		end)

		local plus = MakeArrow(row, "+", function()
			ClearLayoutFocus()
			if opts.onNudge then
				opts.onNudge(1)
			end
			RefreshLayoutPage()
		end)
		plus:SetPoint("LEFT", edit, "RIGHT", 6, 0)

		local slider
		if opts.slider then
			slider = CreateFrame("Slider", opts.sliderName, row, "OptionsSliderTemplate")
			slider:SetPoint("LEFT", plus, "RIGHT", 10, 0)
			slider:SetPoint("RIGHT", row, "RIGHT", -4, 0)
			slider:SetMinMaxValues(opts.minV, opts.maxV)
			slider:SetValueStep(opts.step or 1)
			if slider.SetObeyStepOnDrag then
				slider:SetObeyStepOnDrag(true)
			end
			slider:SetValue(opts.getValue and opts.getValue() or opts.minV)
			if slider.Text then
				slider.Text:SetText("")
			end
			if slider.Low then
				slider.Low:SetText("")
			end
			if slider.High then
				slider.High:SetText("")
			end
			slider:SetScript("OnValueChanged", function(self, value)
				value = math.floor(value + 0.5)
				if self._suppress then
					return
				end
				if opts.onSlider then
					opts.onSlider(value)
				end
				edit:SetText(tostring(value))
			end)
		end

		return edit, slider
	end

	SectionLabel("Size", -140)

	local minW = Addon.MIN_BAR_WIDTH or 400
	local maxW = Addon.MAX_BAR_WIDTH or 1400
	local minH = Addon.MIN_BAR_HEIGHT or 8
	local maxH = Addon.MAX_BAR_HEIGHT or 28

	frame.widthEdit, frame.widthSlider = MakeValueRow({
		label = "Width",
		yOff = -164,
		initialText = tostring(Addon.GetBarWidth and Addon.GetBarWidth() or 1000),
		minV = minW,
		maxV = maxW,
		step = 10,
		slider = true,
		sliderName = "WenDingWidthSlider",
		getValue = function()
			return Addon.GetBarWidth and Addon.GetBarWidth() or 1000
		end,
		onNudge = function(dir)
			local step = NudgeStep(10) * dir
			local cur = Addon.GetBarWidth and Addon.GetBarWidth() or 1000
			if Addon.SetBarWidth then
				Addon.SetBarWidth(cur + step)
			end
		end,
		onCommit = function()
			ApplySizeFromField("width")
		end,
		onSlider = function(v)
			if Addon.SetBarWidth then
				Addon.SetBarWidth(v)
			end
		end,
	})

	frame.heightEdit, frame.heightSlider = MakeValueRow({
		label = "Height",
		yOff = -196,
		initialText = tostring(Addon.GetBarHeight and Addon.GetBarHeight() or 13),
		minV = minH,
		maxV = maxH,
		step = 1,
		slider = true,
		sliderName = "WenDingHeightSlider",
		getValue = function()
			return Addon.GetBarHeight and Addon.GetBarHeight() or 13
		end,
		onNudge = function(dir)
			local step = NudgeStep(1) * dir
			local cur = Addon.GetBarHeight and Addon.GetBarHeight() or 13
			if Addon.SetBarHeight then
				Addon.SetBarHeight(cur + step)
			end
		end,
		onCommit = function()
			ApplySizeFromField("height")
		end,
		onSlider = function(v)
			if Addon.SetBarHeight then
				Addon.SetBarHeight(v)
			end
		end,
	})

	frame.layoutHint = layoutPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.layoutHint:SetPoint("TOPLEFT", 8, -236)
	frame.layoutHint:SetPoint("RIGHT", -8, 0)
	frame.layoutHint:SetJustifyH("LEFT")

	local resetPosBtn = CreateFrame("Button", nil, layoutPage, "UIPanelButtonTemplate")
	resetPosBtn:SetSize(160, 24)
	resetPosBtn:SetPoint("TOPLEFT", 8, -268)
	resetPosBtn:SetText("Reset Layout")
	resetPosBtn:SetScript("OnClick", function()
		ClearLayoutFocus()
		if Addon.ResetFramePosition then
			Addon.ResetFramePosition()
		end
		RefreshLayoutPage()
	end)

	local dragHint = layoutPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	dragHint:SetPoint("TOPLEFT", resetPosBtn, "BOTTOMLEFT", 0, -10)
	dragHint:SetPoint("RIGHT", -8, 0)
	dragHint:SetJustifyH("LEFT")
	dragHint:SetText("Reset → X=0 (UI center), default width/height.")

	-- Dev page (only while WoWF.DevMode)
	local devPage = CreateFrame("Frame", nil, content)
	devPage:SetAllPoints()
	devPage:Hide()
	frame.devPage = devPage

	local function DevLabel(text, yOff)
		local fs = devPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		fs:SetPoint("TOPLEFT", 8, yOff)
		fs:SetPoint("RIGHT", -8, 0)
		fs:SetJustifyH("LEFT")
		fs:SetText(text)
		return fs
	end

	local function DevEdit(yOff, width, initial)
		local edit = CreateFrame("EditBox", nil, devPage, "InputBoxTemplate")
		edit:SetSize(width or 80, 20)
		edit:SetPoint("TOPLEFT", 8, yOff)
		edit:SetAutoFocus(false)
		edit:SetNumeric(false)
		edit:SetMaxLetters(12)
		edit:SetJustifyH("CENTER")
		edit:SetText(initial or "0")
		edit:SetScript("OnEscapePressed", function(self)
			self:ClearFocus()
		end)
		return edit
	end

	DevLabel("XP override (simulations use this instead of UnitXP).", -4)
	frame.devStatus = devPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.devStatus:SetPoint("TOPLEFT", 8, -24)
	frame.devStatus:SetPoint("RIGHT", -8, 0)
	frame.devStatus:SetJustifyH("LEFT")

	local xpLab = devPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	xpLab:SetPoint("TOPLEFT", 8, -52)
	xpLab:SetText("XP")
	frame.devOverrideXP = DevEdit(-74, 90, "0")
	frame.devOverrideXP:ClearAllPoints()
	frame.devOverrideXP:SetPoint("LEFT", xpLab, "RIGHT", 8, 0)

	local maxLab = devPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	maxLab:SetPoint("LEFT", frame.devOverrideXP, "RIGHT", 12, 0)
	maxLab:SetText("Max")
	frame.devOverrideMax = DevEdit(-74, 90, "0")
	frame.devOverrideMax:ClearAllPoints()
	frame.devOverrideMax:SetPoint("LEFT", maxLab, "RIGHT", 8, 0)

	local applyOverride = CreateFrame("Button", nil, devPage, "UIPanelButtonTemplate")
	applyOverride:SetSize(70, 22)
	applyOverride:SetPoint("LEFT", frame.devOverrideMax, "RIGHT", 10, 0)
	applyOverride:SetText("Apply")
	applyOverride:SetScript("OnClick", function()
		if Addon.SetXPOverride then
			Addon.SetXPOverride(frame.devOverrideXP:GetText(), frame.devOverrideMax:GetText())
		end
		RefreshDevPage()
	end)

	local clearOverride = CreateFrame("Button", nil, devPage, "UIPanelButtonTemplate")
	clearOverride:SetSize(70, 22)
	clearOverride:SetPoint("LEFT", applyOverride, "RIGHT", 6, 0)
	clearOverride:SetText("Clear")
	clearOverride:SetScript("OnClick", function()
		if Addon.ClearXPOverride then
			Addon.ClearXPOverride()
		end
		RefreshDevPage()
	end)

	DevLabel("Simulate kill (feeds XP/hr pace).", -110)
	frame.devKillXP = DevEdit(-132, 90, "100")
	local killBtn = CreateFrame("Button", nil, devPage, "UIPanelButtonTemplate")
	killBtn:SetSize(120, 24)
	killBtn:SetPoint("LEFT", frame.devKillXP, "RIGHT", 10, 0)
	killBtn:SetText("Simulate Kill")
	killBtn:SetScript("OnClick", function()
		if Addon.SimulateKill then
			Addon.SimulateKill(frame.devKillXP:GetText())
		end
		RefreshDevPage()
	end)

	DevLabel("Simulate quest turn-in (ETA only — not XP/hr).", -168)
	frame.devQuestXP = DevEdit(-190, 90, "500")
	local questBtn = CreateFrame("Button", nil, devPage, "UIPanelButtonTemplate")
	questBtn:SetSize(140, 24)
	questBtn:SetPoint("LEFT", frame.devQuestXP, "RIGHT", 10, 0)
	questBtn:SetText("Simulate Quest")
	questBtn:SetScript("OnClick", function()
		if Addon.SimulateQuestTurnIn then
			Addon.SimulateQuestTurnIn(frame.devQuestXP:GetText())
		end
		RefreshDevPage()
	end)

	local paceReset = CreateFrame("Button", nil, devPage, "UIPanelButtonTemplate")
	paceReset:SetSize(120, 24)
	paceReset:SetPoint("TOPLEFT", 8, -230)
	paceReset:SetText("Reset Pace")
	paceReset:SetScript("OnClick", function()
		if Addon.ResetPace then
			Addon.ResetPace("dev")
		end
		RefreshDevPage()
	end)

	local devHint = devPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	devHint:SetPoint("TOPLEFT", paceReset, "BOTTOMLEFT", 0, -10)
	devHint:SetPoint("RIGHT", -8, 0)
	devHint:SetJustifyH("LEFT")
	devHint:SetText("Dev tab is hidden when development mode is off (/wd dev).")

	frame:SetScript("OnHide", CloseStyleMenu)
	frame:SetScript("OnShow", function()
		SyncDevTabVisibility()
		SelectTab(frame.selectedTab or 1)
	end)

	if WoWF and WoWF.OnDevModeChanged then
		WoWF.OnDevModeChanged(function()
			SyncDevTabVisibility()
			if panel and panel:IsShown() then
				SelectTab(panel.selectedTab or 1)
			end
		end)
	end
	SyncDevTabVisibility()

	return frame
end

function Addon.ShowPanel()
	if not panel then
		panel = CreatePanel()
	end
	panel:Show()
	SelectTab(panel.selectedTab or 1)
end

function Addon.HidePanel()
	if panel then
		CloseStyleMenu()
		panel:Hide()
	end
end

function Addon.TogglePanel()
	if panel and panel:IsShown() then
		Addon.HidePanel()
	else
		Addon.ShowPanel()
	end
end

function Addon.RefreshPanel()
	if panel and panel:IsShown() then
		if panel.selectedTab == 1 then
			RefreshInfoPage()
		elseif panel.selectedTab == 2 then
			RefreshStyleControls()
		elseif panel.selectedTab == 3 then
			RefreshLayoutPage()
		elseif panel.selectedTab == 4 then
			RefreshDevPage()
		end
	end
end

--- Live X/Y while the XP bar is dragged (does not require Layout tab refresh).
function Addon.SetPanelPositionFields(x, y)
	if not panel or not panel:IsShown() then
		return
	end
	x = tonumber(x)
	y = tonumber(y)
	if x == nil or y == nil then
		return
	end
	if panel.posXEdit and not panel.posXEdit:HasFocus() then
		panel.posXEdit:SetText(string.format("%.1f", x))
	end
	if panel.posYEdit and not panel.posYEdit:HasFocus() then
		panel.posYEdit:SetText(string.format("%.1f", y))
	end
end
