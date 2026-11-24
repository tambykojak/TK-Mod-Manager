local ADDON_NAME, Addon = ...

local PANEL_WIDTH = 880
local PANEL_HEIGHT = 640
local LIST_WIDTH = 300
local ROW_HEIGHT = 34
local VISIBLE_ROWS = 14

local SetSolidColor = Addon.SetSolidColor

local panel
local listButtons = {}
local listOffset = 0
local filtered = {}

local openMenu

---------------------------------------------------------------------------
-- Shared helpers
---------------------------------------------------------------------------

local function CreateSwatch(parent, size, onClick)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(size or 24, size or 24)
	btn:RegisterForClicks("LeftButtonUp")
	btn:EnableMouse(true)
	local border = btn:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	SetSolidColor(border, 0.7, 0.7, 0.7, 1)
	local tex = btn:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("TOPLEFT", 2, -2)
	tex:SetPoint("BOTTOMRIGHT", -2, 2)
	tex:SetTexture("Interface\\Buttons\\WHITE8X8")
	tex:SetVertexColor(1, 1, 1, 1)
	btn.tex = tex
	btn:SetScript("OnClick", onClick)
	function btn:SetColor(r, g, b, a)
		tex:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
	end
	return btn
end

local function CreateLabeledRow(parent, labelText, width)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(width or 280, 24)
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.label:SetPoint("LEFT", 0, 0)
	row.label:SetWidth(90)
	row.label:SetJustifyH("LEFT")
	row.label:SetText(labelText)
	return row
end

local function HideMenus()
	if openMenu then
		openMenu:Hide()
		openMenu = nil
	end
end

--- Build once; reuse. Parent to UIParent at TOOLTIP so it sits above the DIALOG panel.
--- options.previewFonts: render each row with _G[item.value] as its FontObject.
local function BuildPopupMenu(width, items, options)
	options = options or {}
	local previewFonts = options.previewFonts == true
	local rowPitch = previewFonts and 28 or 22
	local rowHeight = previewFonts and 26 or 20
	local maxVisible = previewFonts and 10 or 12
	local count = #items
	local menu = CreateFrame("Frame", nil, UIParent)
	menu:SetFrameStrata("TOOLTIP")
	menu:SetFrameLevel(100)
	menu:SetToplevel(true)
	menu:EnableMouse(true)
	menu:Hide()
	menu:SetSize(width, math.min(count, maxVisible) * rowPitch + 8)

	local bg = menu:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	SetSolidColor(bg, 0.06, 0.06, 0.08, 0.98)

	local host = menu
	local scroll
	if count > maxVisible then
		scroll = CreateFrame("ScrollFrame", nil, menu)
		scroll:SetPoint("TOPLEFT", 4, -4)
		scroll:SetPoint("BOTTOMRIGHT", -4, 4)
		host = CreateFrame("Frame", nil, scroll)
		host:SetSize(width - 8, count * rowPitch)
		scroll:SetScrollChild(host)
		menu:EnableMouseWheel(true)
		menu:SetScript("OnMouseWheel", function(_, delta)
			local cur = scroll:GetVerticalScroll() or 0
			local max = math.max(0, host:GetHeight() - scroll:GetHeight())
			scroll:SetVerticalScroll(math.max(0, math.min(max, cur - delta * rowPitch)))
		end)
	end

	menu.rows = {}
	for i, item in ipairs(items) do
		local row = CreateFrame("Button", nil, host)
		row:SetSize(width - 8, rowHeight)
		row:RegisterForClicks("LeftButtonUp")
		row:EnableMouse(true)
		if scroll then
			row:SetPoint("TOPLEFT", 0, -((i - 1) * rowPitch))
		else
			row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * rowPitch)
		end
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		SetSolidColor(row.bg, 0, 0, 0, 0)
		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.label:SetPoint("LEFT", 6, 0)
		row.label:SetPoint("RIGHT", -6, 0)
		row.label:SetJustifyH("LEFT")
		row.label:SetJustifyV("MIDDLE")
		if row.label.SetWordWrap then
			row.label:SetWordWrap(false)
		end
		if row.label.SetMaxLines then
			row.label:SetMaxLines(1)
		end
		local labelText = item.name or tostring(item.value or item.id)
		if previewFonts then
			local fontObj = item.value and _G[item.value]
			if fontObj then
				row.label:SetFontObject(fontObj)
			end
		end
		row.label:SetText(labelText)
		row.item = item
		row:SetScript("OnEnter", function(self)
			SetSolidColor(self.bg, 0.2, 0.45, 0.8, 0.45)
		end)
		row:SetScript("OnLeave", function(self)
			SetSolidColor(self.bg, 0, 0, 0, 0)
		end)
		menu.rows[i] = row
	end

	function menu:SetHandler(onSelect)
		for _, row in ipairs(self.rows) do
			row:SetScript("OnClick", function(self)
				if onSelect then
					onSelect(self.item)
				end
				HideMenus()
			end)
		end
	end

	--- Color font-preview rows (call before show; FontObjects can reset color).
	function menu:SetPreviewColor(r, g, b, a)
		if not previewFonts then
			return
		end
		a = a or 1
		for _, row in ipairs(self.rows) do
			row.label:SetTextColor(r, g, b, a)
		end
	end

	return menu
end

local function ToggleMenu(menu, anchor, onSelect)
	if openMenu and openMenu:IsShown() and openMenu == menu then
		HideMenus()
		return
	end
	HideMenus()
	menu:SetHandler(onSelect)
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	menu:Show()
	openMenu = menu
end

local function CreateDropdownButton(parent, width)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(width or 160, 24)
	btn:RegisterForClicks("LeftButtonUp")
	btn:EnableMouse(true)
	btn:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 5)

	btn.bg = btn:CreateTexture(nil, "BACKGROUND")
	btn.bg:SetAllPoints()
	SetSolidColor(btn.bg, 0.12, 0.12, 0.16, 1)

	btn.border = btn:CreateTexture(nil, "BORDER")
	btn.border:SetPoint("TOPLEFT", -1, 1)
	btn.border:SetPoint("BOTTOMRIGHT", 1, -1)
	SetSolidColor(btn.border, 0.45, 0.45, 0.5, 1)
	btn.border:SetDrawLayer("BACKGROUND", -1)

	btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	btn.label:SetPoint("LEFT", 8, 0)
	btn.label:SetPoint("RIGHT", -18, 0)
	btn.label:SetJustifyH("LEFT")

	local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	arrow:SetPoint("RIGHT", -6, 0)
	arrow:SetText("v")

	btn:SetScript("OnEnter", function(self)
		SetSolidColor(self.bg, 0.2, 0.35, 0.55, 1)
	end)
	btn:SetScript("OnLeave", function(self)
		SetSolidColor(self.bg, 0.12, 0.12, 0.16, 1)
	end)
	return btn
end

--- Forever / modern clients need BackdropTemplate for SetBackdrop.
local function CreateBackdropFrame(name, parent)
	local template = nil
	if BackdropTemplateMixin then
		template = "BackdropTemplate"
	end
	local frame = CreateFrame("Frame", name, parent, template)
	if not frame.SetBackdrop and BackdropTemplateMixin then
		Mixin(frame, BackdropTemplateMixin)
		if frame.OnBackdropLoaded then
			frame:OnBackdropLoaded()
		elseif BackdropTemplateMixin.OnLoad then
			BackdropTemplateMixin.OnLoad(frame)
		end
	end
	return frame
end

local function EnsureEdgePieces(frame)
	if frame._duEdges then
		return frame._duEdges
	end
	local edges = {}
	for _, key in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local tex = frame:CreateTexture(nil, "BORDER")
		edges[key] = tex
	end
	frame._duEdges = edges
	return edges
end

local function ApplyBackdrop(frame, bgPath, edgePath, tile, tileSize, edgeSize, inset, bgColor, edgeColor)
	inset = inset or 8
	edgeSize = edgeSize or 32
	tileSize = tileSize or 32

	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = bgPath,
			edgeFile = edgePath,
			tile = tile and true or false,
			tileSize = tileSize,
			edgeSize = edgeSize,
			insets = { left = inset, right = inset, top = inset, bottom = inset },
		})
		if frame.SetBackdropColor and bgColor then
			local ba = bgColor.a
			if not ba or ba < 0 then ba = 1 end
			frame:SetBackdropColor(bgColor.r or 0, bgColor.g or 0, bgColor.b or 0, ba)
		end
		if frame.SetBackdropBorderColor and edgeColor then
			-- Never allow 0 alpha to "erase" the border from a bad picker read.
			local ea = edgeColor.a
			if not ea or ea <= 0 then ea = 1 end
			frame:SetBackdropBorderColor(edgeColor.r or 1, edgeColor.g or 1, edgeColor.b or 1, ea)
		end
		-- Hide manual fallback if we previously created it.
		if frame._duBg then
			frame._duBg:Hide()
		end
		if frame._duEdges then
			for _, tex in pairs(frame._duEdges) do
				tex:Hide()
			end
		end
		return
	end

	-- Manual fallback when SetBackdrop is unavailable: inset fill + 4 edge strips.
	if not frame._duBg then
		frame._duBg = frame:CreateTexture(nil, "BACKGROUND")
	end
	frame._duBg:Show()
	frame._duBg:ClearAllPoints()
	frame._duBg:SetPoint("TOPLEFT", inset, -inset)
	frame._duBg:SetPoint("BOTTOMRIGHT", -inset, inset)
	frame._duBg:SetTexture(bgPath or "Interface\\Buttons\\WHITE8X8")
	if tile and frame._duBg.SetHorizTile then
		frame._duBg:SetHorizTile(true)
		frame._duBg:SetVertTile(true)
	end
	if bgColor then
		frame._duBg:SetVertexColor(bgColor.r or 1, bgColor.g or 1, bgColor.b or 1, bgColor.a or 1)
	else
		frame._duBg:SetVertexColor(1, 1, 1, 1)
	end

	local edges = EnsureEdgePieces(frame)
	local er = (edgeColor and edgeColor.r) or 1
	local eg = (edgeColor and edgeColor.g) or 1
	local eb = (edgeColor and edgeColor.b) or 1
	local ea = edgeColor and edgeColor.a
	if not ea or ea <= 0 then
		ea = 1
	end
	local path = edgePath or "Interface\\DialogFrame\\UI-DialogBox-Border"

	local function Place(tex, pointA, xA, yA, pointB, xB, yB, w, h)
		tex:Show()
		tex:ClearAllPoints()
		tex:SetTexture(path)
		tex:SetVertexColor(er, eg, eb, ea)
		if w then
			tex:SetWidth(w)
		end
		if h then
			tex:SetHeight(h)
		end
		tex:SetPoint(pointA, frame, pointA, xA, yA)
		if pointB then
			tex:SetPoint(pointB, frame, pointB, xB, yB)
		end
	end

	Place(edges.TOP, "TOPLEFT", 0, 0, "TOPRIGHT", 0, 0, nil, edgeSize)
	Place(edges.BOTTOM, "BOTTOMLEFT", 0, 0, "BOTTOMRIGHT", 0, 0, nil, edgeSize)
	Place(edges.LEFT, "TOPLEFT", 0, 0, "BOTTOMLEFT", 0, 0, edgeSize, nil)
	Place(edges.RIGHT, "TOPRIGHT", 0, 0, "BOTTOMRIGHT", 0, 0, edgeSize, nil)
end

local function SafeSetFontObject(fs, fontObjectName)
	if not fs or not fontObjectName then
		return
	end
	local obj = _G[fontObjectName]
	if obj then
		fs:SetFontObject(obj)
	end
end

local function CreateTabButton(parent, text, width, onClick)
	local tab = CreateFrame("Button", nil, parent)
	tab:SetSize(width or 120, 28)
	tab:RegisterForClicks("LeftButtonUp")
	tab:EnableMouse(true)
	tab.bg = tab:CreateTexture(nil, "BACKGROUND")
	tab.bg:SetAllPoints()
	SetSolidColor(tab.bg, 0.15, 0.15, 0.18, 0.8)
	tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	tab.label:SetPoint("CENTER")
	tab.label:SetText(text)
	tab:SetScript("OnClick", onClick)
	return tab
end

local function StyleTab(tab, active)
	tab:SetNormalFontObject(active and "GameFontHighlight" or "GameFontNormal")
	if active then
		SetSolidColor(tab.bg, 0.2, 0.45, 0.8, 0.45)
	else
		SetSolidColor(tab.bg, 0.15, 0.15, 0.18, 0.8)
	end
end

local function TextureFileName(path)
	return (path and path:match("([^\\/]+)$")) or path or ""
end

local function SelectionBanner(parent)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(22)
	bar.prefix = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	bar.prefix:SetPoint("LEFT", 0, 0)
	bar.prefix:SetText("Selected:")
	bar.path = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.path:SetPoint("LEFT", bar.prefix, "RIGHT", 6, 0)
	bar.path:SetPoint("RIGHT", 0, 0)
	bar.path:SetJustifyH("LEFT")
	function bar:Refresh()
		self.path:SetText(Addon.GetSelectedPath() or "")
	end
	return bar
end

---------------------------------------------------------------------------
-- Explore (texture viewer)
---------------------------------------------------------------------------

local function ApplyPreviewBackdrop()
	if not panel or not panel.explorePreviewBg then
		return
	end
	local mode = Addon.EnsureDB().explorer.previewBg or "dark"
	local bg = panel.explorePreviewBg
	if mode == "light" then
		SetSolidColor(bg, 0.85, 0.85, 0.88, 1)
	elseif mode == "checker" then
		-- Approximate checker with mid gray; true checker needs a tile atlas.
		SetSolidColor(bg, 0.45, 0.45, 0.48, 1)
	else
		SetSolidColor(bg, 0.08, 0.08, 0.1, 1)
	end
end

local STAGE_PAD = 8
local PREVIEW_SIZE_MIN = 16
local PREVIEW_SIZE_STEP = 16

--- Max draw width/height that fit inside the background area with padding.
local function GetStageDrawMax()
	local stage = panel and panel.exploreStage
	if not stage then
		return 256, 256
	end
	local w = stage:GetWidth() or 0
	local h = stage:GetHeight() or 0
	local maxW = math.max(PREVIEW_SIZE_MIN, math.floor(w - (STAGE_PAD * 2)))
	local maxH = math.max(PREVIEW_SIZE_MIN, math.floor(h - (STAGE_PAD * 2)))
	return maxW, maxH
end

local function ClampPreviewDim(value, maxV)
	value = tonumber(value) or 256
	value = math.max(PREVIEW_SIZE_MIN, value)
	value = math.min(value, maxV or 256)
	return value
end

local function ClampPreviewSize(width, height)
	local maxW, maxH = GetStageDrawMax()
	return ClampPreviewDim(width, maxW), ClampPreviewDim(height, maxH)
end

-- Forward-declared so nudge handlers can call it (local function order).
local RefreshExplorePreview

--- dW/dH are pixel deltas (can nudge one axis or both together).
local function NudgePreviewSize(dW, dH)
	local db = Addon.EnsureDB().explorer
	local maxW, maxH = GetStageDrawMax()
	db.previewWidth = ClampPreviewDim((db.previewWidth or 256) + (dW or 0), maxW)
	db.previewHeight = ClampPreviewDim((db.previewHeight or 256) + (dH or 0), maxH)
	RefreshExplorePreview()
end

local function CommitPreviewSizeInputs()
	local db = Addon.EnsureDB().explorer
	local w = panel.exploreWidthBox and tonumber(panel.exploreWidthBox:GetText())
	local h = panel.exploreHeightBox and tonumber(panel.exploreHeightBox:GetText())
	if not w and not h then
		return
	end
	w = w or db.previewWidth or 256
	h = h or db.previewHeight or 256
	db.previewWidth, db.previewHeight = ClampPreviewSize(w, h)
	RefreshExplorePreview()
end

local function SyncPreviewSizeInputs(width, height)
	if panel.exploreWidthBox and (not panel.exploreWidthBox:HasFocus() or panel._forceSizeBoxes) then
		panel.exploreWidthBox:SetText(tostring(width))
	end
	if panel.exploreHeightBox and (not panel.exploreHeightBox:HasFocus() or panel._forceSizeBoxes) then
		panel.exploreHeightBox:SetText(tostring(height))
	end
	panel._forceSizeBoxes = nil
end

RefreshExplorePreview = function()
	if not panel or not panel.exploreTex then
		return
	end
	local db = Addon.EnsureDB().explorer
	local path = db.selectedPath
	local width, height = ClampPreviewSize(db.previewWidth or 256, db.previewHeight or 256)
	db.previewWidth = width
	db.previewHeight = height
	local stage = panel.exploreStage or panel.exploreTex:GetParent()
	panel.exploreTex:ClearAllPoints()
	panel.exploreTex:SetPoint("TOPLEFT", stage, "TOPLEFT", STAGE_PAD, -STAGE_PAD)
	panel.exploreTex:SetSize(width, height)
	panel.exploreTex:SetTexture(path)
	local c = db.vertexColor
	panel.exploreTex:SetVertexColor(c.r or 1, c.g or 1, c.b or 1, c.a or 1)
	ApplyPreviewBackdrop()

	local entry = Addon.FindTexture(path)
	panel.exploreName:SetText(entry and entry.name or TextureFileName(path) or "Custom / unknown")
	panel.exploreCategory:SetText(entry and entry.category or "—")
	if panel.pathBox then
		-- Keep the browser bar in sync with the left-list selection.
		if not panel.pathBox:HasFocus() or panel._forcePathBox then
			panel.pathBox:SetText(path or "")
			panel._forcePathBox = nil
		end
	end
	if panel.exploreVertexSwatch then
		panel.exploreVertexSwatch:SetColor(c.r, c.g, c.b, c.a or 1)
	end
	SyncPreviewSizeInputs(width, height)
	if panel.exploreBgModeLabel then
		panel.exploreBgModeLabel:SetText(db.previewBg or "dark")
	end
	if panel.categoryLabel then
		panel.categoryLabel:SetText(db.category or "All")
	end
end

local function RefreshExploreList()
	if not panel or not panel.exploreList then
		return
	end
	local db = Addon.EnsureDB().explorer
	filtered = Addon.FilterTextures(db.category, db.search)
	local maxOffset = math.max(0, #filtered - VISIBLE_ROWS)
	listOffset = math.max(0, math.min(listOffset, maxOffset))

	for i = 1, VISIBLE_ROWS do
		local btn = listButtons[i]
		local entry = filtered[listOffset + i]
		if entry then
			btn:Show()
			btn.entry = entry
			btn.name:SetText(entry.name)
			btn.category:SetText(entry.category)
			btn.thumb:SetTexture(entry.path)
			if db.selectedPath == entry.path then
				SetSolidColor(btn.bg, 0.15, 0.35, 0.65, 0.55)
				btn.category:SetTextColor(0.75, 0.85, 1)
			else
				SetSolidColor(btn.bg, 1, 1, 1, btn.rowIndex % 2 == 0 and 0.03 or 0.07)
				btn.category:SetTextColor(0.55, 0.55, 0.58)
			end
		else
			btn.entry = nil
			btn:Hide()
		end
	end

	if panel.exploreCount then
		panel.exploreCount:SetText(string.format("%d / %d", #filtered, #Addon.TEXTURES))
	end
end

local function SelectTexture(entry)
	if not entry then
		return
	end
	Addon.SetSelectedPath(entry.path)
	if panel and panel.pathBox then
		panel.pathBox:ClearFocus()
		panel._forcePathBox = true
	end
	RefreshExploreList()
	RefreshExplorePreview()
	if panel.composeSelection then
		panel.composeSelection:Refresh()
	end
end

function Addon.OnSelectionChanged(_path)
	if not panel then
		return
	end
	if panel.composeSelection then
		panel.composeSelection:Refresh()
	end
	if panel:IsShown() and panel.selectedTab == 1 then
		RefreshExploreList()
		RefreshExplorePreview()
	end
end

local function CreateExplorePage(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()

	-- Filter bar (category + search)
	local filterBar = CreateFrame("Frame", nil, page)
	filterBar:SetPoint("TOPLEFT", 0, 0)
	filterBar:SetSize(LIST_WIDTH + 8, 32)
	filterBar:SetFrameLevel((page.GetFrameLevel and page:GetFrameLevel() or 0) + 10)
	filterBar:EnableMouse(true)

	local catItems = { { name = "All", value = "All" } }
	for _, c in ipairs(Addon.TEXTURE_CATEGORIES) do
		catItems[#catItems + 1] = { name = c, value = c }
	end
	panel.categoryMenu = BuildPopupMenu(150, catItems)

	local catBtn = CreateDropdownButton(filterBar, 110)
	catBtn:SetPoint("TOPLEFT", 4, -4)
	catBtn:SetScript("OnClick", function(self)
		ToggleMenu(panel.categoryMenu, self, function(item)
			Addon.EnsureDB().explorer.category = item.value
			listOffset = 0
			RefreshExploreList()
			RefreshExplorePreview()
		end)
	end)
	panel.categoryLabel = catBtn.label

	local searchBox = CreateFrame("EditBox", "DevUtilsSearchBox", filterBar, "InputBoxTemplate")
	searchBox:SetSize(100, 20)
	searchBox:SetPoint("LEFT", catBtn, "RIGHT", 10, 0)
	searchBox:SetAutoFocus(false)
	searchBox:SetMaxLetters(64)
	searchBox:SetText(Addon.EnsureDB().explorer.search or "")
	searchBox:SetScript("OnTextChanged", function(self, userInput)
		if not userInput and self:GetText() == (Addon.EnsureDB().explorer.search or "") then
			return
		end
		Addon.EnsureDB().explorer.search = self:GetText() or ""
		listOffset = 0
		RefreshExploreList()
	end)
	searchBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	searchBox:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	panel.searchBox = searchBox

	panel.exploreCount = filterBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.exploreCount:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)

	-- List
	local list = CreateFrame("Frame", nil, page)
	list:SetPoint("TOPLEFT", 4, -36)
	list:SetSize(LIST_WIDTH, VISIBLE_ROWS * ROW_HEIGHT)
	local listBg = list:CreateTexture(nil, "BACKGROUND")
	listBg:SetAllPoints()
	SetSolidColor(listBg, 0.05, 0.05, 0.07, 0.9)
	panel.exploreList = list

	for i = 1, VISIBLE_ROWS do
		local btn = CreateFrame("Button", nil, list)
		btn:SetHeight(ROW_HEIGHT)
		btn:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))
		btn:SetPoint("RIGHT", 0, 0)
		btn.rowIndex = i
		btn.bg = btn:CreateTexture(nil, "BACKGROUND")
		btn.bg:SetAllPoints()
		SetSolidColor(btn.bg, 1, 1, 1, i % 2 == 0 and 0.03 or 0.07)

		-- Thumb plate
		btn.thumbBorder = btn:CreateTexture(nil, "BORDER")
		btn.thumbBorder:SetSize(28, 28)
		btn.thumbBorder:SetPoint("LEFT", 4, 0)
		SetSolidColor(btn.thumbBorder, 0.35, 0.35, 0.4, 1)

		btn.thumb = btn:CreateTexture(nil, "ARTWORK")
		btn.thumb:SetSize(26, 26)
		btn.thumb:SetPoint("CENTER", btn.thumbBorder, "CENTER", 0, 0)

		-- Name only on the first line; category tag on the second.
		-- Full path lives in the address bar / tooltip — keeps long filenames out of the cell.
		btn.name = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		btn.name:SetPoint("TOPLEFT", btn.thumbBorder, "TOPRIGHT", 8, -2)
		btn.name:SetPoint("RIGHT", -8, 0)
		btn.name:SetJustifyH("LEFT")
		btn.name:SetJustifyV("TOP")
		btn.name:SetHeight(14)
		if btn.name.SetWordWrap then
			btn.name:SetWordWrap(false)
		end
		if btn.name.SetNonSpaceWrap then
			btn.name:SetNonSpaceWrap(false)
		end
		if btn.name.SetMaxLines then
			btn.name:SetMaxLines(1)
		end

		btn.category = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		btn.category:SetPoint("BOTTOMLEFT", btn.thumbBorder, "BOTTOMRIGHT", 8, 2)
		btn.category:SetPoint("RIGHT", -8, 0)
		btn.category:SetJustifyH("LEFT")
		btn.category:SetHeight(12)
		if btn.category.SetWordWrap then
			btn.category:SetWordWrap(false)
		end
		if btn.category.SetMaxLines then
			btn.category:SetMaxLines(1)
		end

		btn:SetScript("OnEnter", function(self)
			if not self.entry then
				return
			end
			SetSolidColor(self.bg, 0.2, 0.45, 0.8, 0.35)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:ClearLines()
			GameTooltip:AddLine(self.entry.name, 1, 0.82, 0)
			GameTooltip:AddLine(self.entry.category, 0.6, 0.8, 1)
			GameTooltip:AddLine(self.entry.path, 0.8, 0.8, 0.8, true)
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function(self)
			local selected = Addon.GetSelectedPath()
			if self.entry and selected == self.entry.path then
				SetSolidColor(self.bg, 0.15, 0.35, 0.65, 0.55)
				if self.category then
					self.category:SetTextColor(0.75, 0.85, 1)
				end
			else
				SetSolidColor(self.bg, 1, 1, 1, self.rowIndex % 2 == 0 and 0.03 or 0.07)
				if self.category then
					self.category:SetTextColor(0.55, 0.55, 0.58)
				end
			end
			GameTooltip:Hide()
		end)
		btn:SetScript("OnClick", function(self)
			SelectTexture(self.entry)
		end)
		listButtons[i] = btn
	end

	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		listOffset = listOffset - delta * 3
		RefreshExploreList()
	end)

	-- Preview column (browser-style: address bar → stage → image)
	local right = CreateFrame("Frame", nil, page)
	right:SetPoint("TOPLEFT", filterBar, "TOPRIGHT", 12, 0)
	right:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -4, 4)

	local addressBar = CreateFrame("Frame", nil, right)
	addressBar:SetPoint("TOPLEFT", 0, 0)
	addressBar:SetPoint("TOPRIGHT", 0, 0)
	addressBar:SetHeight(28)
	addressBar:SetFrameLevel((right.GetFrameLevel and right:GetFrameLevel() or 0) + 5)

	local pathBox = CreateFrame("EditBox", "DevUtilsPathBox", addressBar, "InputBoxTemplate")
	pathBox:SetPoint("TOPLEFT", 6, -4)
	pathBox:SetPoint("RIGHT", -54, 0)
	pathBox:SetHeight(20)
	pathBox:SetAutoFocus(false)
	pathBox:SetMaxLetters(220)
	pathBox:SetText(Addon.EnsureDB().explorer.selectedPath or "")
	pathBox:SetScript("OnEscapePressed", function(self)
		self:SetText(Addon.GetSelectedPath() or "")
		self:ClearFocus()
	end)
	local function CommitPath(self)
		local raw = self:GetText() or ""
		raw = raw:match("^%s*(.-)%s*$") or ""
		raw = raw:gsub("/", "\\")
		if raw ~= "" then
			Addon.SetSelectedPath(raw)
			RefreshExploreList()
			RefreshExplorePreview()
		end
		self:ClearFocus()
	end
	pathBox:SetScript("OnEnterPressed", CommitPath)
	panel.pathBox = pathBox

	local pathGo = CreateFrame("Button", nil, addressBar, "UIPanelButtonTemplate")
	pathGo:SetSize(44, 22)
	pathGo:SetPoint("RIGHT", 0, 0)
	pathGo:SetText("Go")
	pathGo:SetScript("OnClick", function()
		CommitPath(pathBox)
	end)

	-- Background (preview backdrop) sits under the address bar.
	local bgBar = CreateFrame("Frame", nil, right)
	bgBar:SetSize(360, 24)
	bgBar:SetPoint("TOPLEFT", addressBar, "BOTTOMLEFT", 0, -6)

	local bgLbl = bgBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	bgLbl:SetPoint("LEFT", 0, 0)
	bgLbl:SetText("Background")

	local bgItems = {
		{ name = "dark", value = "dark" },
		{ name = "light", value = "light" },
		{ name = "checker", value = "checker" },
	}
	if not panel.exploreBgMenu then
		panel.exploreBgMenu = BuildPopupMenu(120, bgItems)
	end
	local bgBtn = CreateDropdownButton(bgBar, 100)
	bgBtn:SetPoint("LEFT", bgLbl, "RIGHT", 8, 0)
	bgBtn:SetScript("OnClick", function(self)
		ToggleMenu(panel.exploreBgMenu, self, function(item)
			Addon.EnsureDB().explorer.previewBg = item.value
			RefreshExplorePreview()
		end)
	end)
	panel.exploreBgModeLabel = bgBtn.label

	local stage = CreateFrame("Frame", nil, right)
	stage:SetPoint("TOPLEFT", bgBar, "BOTTOMLEFT", 0, -8)
	stage:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, -38)
	stage:SetHeight(320)
	panel.exploreStage = stage
	panel.explorePreviewBg = stage:CreateTexture(nil, "BACKGROUND")
	panel.explorePreviewBg:SetAllPoints()
	local stageBorder = stage:CreateTexture(nil, "BORDER")
	stageBorder:SetPoint("TOPLEFT", -1, 1)
	stageBorder:SetPoint("BOTTOMRIGHT", 1, -1)
	SetSolidColor(stageBorder, 0.4, 0.4, 0.45, 1)
	stageBorder:SetDrawLayer("BACKGROUND", -1)
	stage:SetScript("OnSizeChanged", function()
		RefreshExplorePreview()
	end)

	panel.exploreTex = stage:CreateTexture(nil, "ARTWORK")
	panel.exploreTex:SetPoint("TOPLEFT", STAGE_PAD, -STAGE_PAD)

	panel.exploreName = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.exploreName:SetPoint("TOP", stage, "BOTTOM", 0, -10)
	panel.exploreName:SetWidth(480)
	panel.exploreName:SetJustifyH("CENTER")

	panel.exploreCategory = right:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	panel.exploreCategory:SetPoint("TOP", panel.exploreName, "BOTTOM", 0, -4)

	local controls = CreateFrame("Frame", nil, right)
	controls:SetPoint("TOP", panel.exploreCategory, "BOTTOM", 0, -12)
	controls:SetSize(500, 150)

	local y = 0
	local function Row(label)
		local row = CreateLabeledRow(controls, label, 500)
		row:SetPoint("TOPLEFT", 40, y)
		y = y - 28
		return row
	end

	local tintRow = Row("Tint")
	panel.exploreVertexSwatch = CreateSwatch(tintRow, 22, function()
		local c = Addon.EnsureDB().explorer.vertexColor
		Addon.OpenColorPicker(c, function(r, g, b, a)
			c.r, c.g, c.b, c.a = r, g, b, a
			RefreshExplorePreview()
		end)
	end)
	panel.exploreVertexSwatch:SetPoint("LEFT", tintRow.label, "RIGHT", 4, 0)
	local resetTint = CreateFrame("Button", nil, tintRow, "UIPanelButtonTemplate")
	resetTint:SetSize(60, 20)
	resetTint:SetPoint("LEFT", panel.exploreVertexSwatch, "RIGHT", 8, 0)
	resetTint:SetText("Reset")
	resetTint:SetScript("OnClick", function()
		local c = Addon.EnsureDB().explorer.vertexColor
		c.r, c.g, c.b, c.a = 1, 1, 1, 1
		RefreshExplorePreview()
	end)

	-- Draw size: X/Y inputs + steppers; Both nudges both axes.
	local sizeRow = Row("Draw size")
	sizeRow:SetHeight(78)
	y = y - 50

	local sizeHost = CreateFrame("Frame", nil, sizeRow)
	sizeHost:SetSize(320, 78)
	sizeHost:SetPoint("LEFT", sizeRow.label, "RIGHT", 4, -18)

	local function MakeSizeEdit(name, yOff)
		local box = CreateFrame("EditBox", name, sizeHost, "InputBoxTemplate")
		box:SetSize(48, 20)
		box:SetPoint("LEFT", 18, yOff)
		box:SetAutoFocus(false)
		box:SetMaxLetters(4)
		box:SetNumeric(true)
		box:SetScript("OnEscapePressed", function(self)
			panel._forceSizeBoxes = true
			RefreshExplorePreview()
			self:ClearFocus()
		end)
		box:SetScript("OnEnterPressed", function(self)
			CommitPreviewSizeInputs()
			self:ClearFocus()
		end)
		box:SetScript("OnEditFocusLost", function()
			CommitPreviewSizeInputs()
		end)
		return box
	end

	local function MakeStep(dW, dH, anchor, xOff)
		local minus = CreateFrame("Button", nil, sizeHost, "UIPanelButtonTemplate")
		minus:SetSize(22, 20)
		minus:SetPoint("LEFT", anchor, "RIGHT", xOff or 6, 0)
		minus:SetText("-")
		minus:SetScript("OnClick", function()
			NudgePreviewSize(dW * -PREVIEW_SIZE_STEP, dH * -PREVIEW_SIZE_STEP)
		end)
		local plus = CreateFrame("Button", nil, sizeHost, "UIPanelButtonTemplate")
		plus:SetSize(22, 20)
		plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)
		plus:SetText("+")
		plus:SetScript("OnClick", function()
			NudgePreviewSize(dW * PREVIEW_SIZE_STEP, dH * PREVIEW_SIZE_STEP)
		end)
		return plus
	end

	local xLbl = sizeHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	xLbl:SetPoint("LEFT", 0, 22)
	xLbl:SetWidth(14)
	xLbl:SetText("X")
	panel.exploreWidthBox = MakeSizeEdit("DevUtilsPreviewWidthBox", 22)
	MakeStep(1, 0, panel.exploreWidthBox, 6)

	local yLbl = sizeHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	yLbl:SetPoint("LEFT", 0, -2)
	yLbl:SetWidth(14)
	yLbl:SetText("Y")
	panel.exploreHeightBox = MakeSizeEdit("DevUtilsPreviewHeightBox", -2)
	MakeStep(0, 1, panel.exploreHeightBox, 6)

	local bothLbl = sizeHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	bothLbl:SetPoint("LEFT", 0, -26)
	bothLbl:SetWidth(36)
	bothLbl:SetText("Both")
	local bothMinus = CreateFrame("Button", nil, sizeHost, "UIPanelButtonTemplate")
	bothMinus:SetSize(22, 20)
	bothMinus:SetPoint("LEFT", bothLbl, "RIGHT", 4, 0)
	bothMinus:SetText("-")
	bothMinus:SetScript("OnClick", function()
		NudgePreviewSize(-PREVIEW_SIZE_STEP, -PREVIEW_SIZE_STEP)
	end)
	local bothPlus = CreateFrame("Button", nil, sizeHost, "UIPanelButtonTemplate")
	bothPlus:SetSize(22, 20)
	bothPlus:SetPoint("LEFT", bothMinus, "RIGHT", 2, 0)
	bothPlus:SetText("+")
	bothPlus:SetScript("OnClick", function()
		NudgePreviewSize(PREVIEW_SIZE_STEP, PREVIEW_SIZE_STEP)
	end)

	local sizeHint = sizeHost:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sizeHint:SetPoint("LEFT", bothPlus, "RIGHT", 12, 0)
	sizeHint:SetText("min " .. PREVIEW_SIZE_MIN .. ", capped to area")

	return page
end

---------------------------------------------------------------------------
-- Compose → Panel
---------------------------------------------------------------------------

local function RefreshPanelCompose()
	if not panel or not panel.panelPreview then
		return
	end
	local db = Addon.EnsureDB().panel
	local preview = panel.panelPreview
	ApplyBackdrop(preview, db.bgPath, db.edgePath, db.tile, db.tileSize, db.edgeSize, db.inset, db.bgColor, db.edgeColor)
	SafeSetFontObject(preview.title, db.titleFont)
	SafeSetFontObject(preview.body, db.bodyFont)
	preview.title:SetTextColor(db.titleColor.r, db.titleColor.g, db.titleColor.b, 1)
	preview.body:SetTextColor(db.bodyColor.r, db.bodyColor.g, db.bodyColor.b, 1)

	if panel.bgPathLabel then panel.bgPathLabel:SetText((db.bgPath or ""):match("[^\\]+$") or db.bgPath or "") end
	if panel.edgePathLabel then panel.edgePathLabel:SetText((db.edgePath or ""):match("[^\\]+$") or db.edgePath or "") end
	if panel.titleFontLabel then panel.titleFontLabel:SetText(db.titleFont) end
	if panel.bodyFontLabel then panel.bodyFontLabel:SetText(db.bodyFont) end
	if panel.tileCheck then panel.tileCheck:SetChecked(db.tile ~= false) end
	if panel.tileSizeLabel then panel.tileSizeLabel:SetText(tostring(db.tileSize or 32)) end
	if panel.edgeSizeLabel then panel.edgeSizeLabel:SetText(tostring(db.edgeSize or 32)) end
	if panel.insetLabel then panel.insetLabel:SetText(tostring(db.inset or 8)) end
	if panel.bgSwatch then panel.bgSwatch:SetColor(db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgColor.a) end
	if panel.edgeSwatch then panel.edgeSwatch:SetColor(db.edgeColor.r, db.edgeColor.g, db.edgeColor.b, db.edgeColor.a) end
	if panel.titleSwatch then panel.titleSwatch:SetColor(db.titleColor.r, db.titleColor.g, db.titleColor.b, 1) end
	if panel.bodySwatch then panel.bodySwatch:SetColor(db.bodyColor.r, db.bodyColor.g, db.bodyColor.b, 1) end
	if panel.composeSelection then panel.composeSelection:Refresh() end
end

local function NudgePanel(field, delta, minV, maxV)
	local db = Addon.EnsureDB().panel
	local v = (db[field] or 0) + delta
	if minV then v = math.max(minV, v) end
	if maxV then v = math.min(maxV, v) end
	db[field] = v
	RefreshPanelCompose()
end

local function ResetPanelDefaults()
	local p = Addon.EnsureDB().panel
	p.bgPath = "Interface\\DialogFrame\\UI-DialogBox-Background"
	p.edgePath = "Interface\\DialogFrame\\UI-DialogBox-Border"
	p.tile = true
	p.tileSize = 32
	p.edgeSize = 32
	p.inset = 8
	p.bgColor.r, p.bgColor.g, p.bgColor.b, p.bgColor.a = 0, 0, 0, 0.9
	p.edgeColor.r, p.edgeColor.g, p.edgeColor.b, p.edgeColor.a = 1, 1, 1, 1
	p.titleFont = "GameFontNormalLarge"
	p.bodyFont = "GameFontHighlight"
	p.titleColor.r, p.titleColor.g, p.titleColor.b = 1, 0.82, 0
	p.bodyColor.r, p.bodyColor.g, p.bodyColor.b = 1, 1, 1
	RefreshPanelCompose()
end

local function CreatePanelTool(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()

	local preview = CreateBackdropFrame(nil, page)
	preview:SetSize(420, 160)
	preview:SetPoint("TOP", 0, -4)
	panel.panelPreview = preview
	preview.title = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	preview.title:SetPoint("TOP", 0, -22)
	preview.title:SetText("Panel Preview")
	preview.body = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	preview.body:SetPoint("TOP", preview.title, "BOTTOM", 0, -10)
	preview.body:SetWidth(360)
	preview.body:SetJustifyH("CENTER")
	preview.body:SetText("Pick a Border in Explore, then click Use selected.\nRaise Edge if the frame still looks bare.")

	local controls = CreateFrame("Frame", nil, page)
	controls:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 40, -12)
	controls:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -20, 4)

	local y = 0
	local function NextRow(label)
		local row = CreateLabeledRow(controls, label, 520)
		row:SetPoint("TOPLEFT", 0, y)
		y = y - 26
		return row
	end

	local bgRow = NextRow("Background")
	panel.bgPathLabel = bgRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.bgPathLabel:SetPoint("LEFT", bgRow.label, "RIGHT", 4, 0)
	panel.bgPathLabel:SetWidth(240)
	panel.bgPathLabel:SetJustifyH("LEFT")
	local useBg = CreateFrame("Button", nil, bgRow, "UIPanelButtonTemplate")
	useBg:SetSize(110, 18)
	useBg:SetPoint("RIGHT", 0, 0)
	useBg:SetText("Use selected")
	useBg:SetScript("OnClick", function()
		local path = Addon.GetSelectedPath()
		if path then
			Addon.EnsureDB().panel.bgPath = path
			RefreshPanelCompose()
		end
	end)

	local edgeRow = NextRow("Border")
	panel.edgePathLabel = edgeRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.edgePathLabel:SetPoint("LEFT", edgeRow.label, "RIGHT", 4, 0)
	panel.edgePathLabel:SetWidth(240)
	panel.edgePathLabel:SetJustifyH("LEFT")
	local useEdge = CreateFrame("Button", nil, edgeRow, "UIPanelButtonTemplate")
	useEdge:SetSize(110, 18)
	useEdge:SetPoint("RIGHT", 0, 0)
	useEdge:SetText("Use selected")
	useEdge:SetScript("OnClick", function()
		local path = Addon.GetSelectedPath()
		if path then
			Addon.EnsureDB().panel.edgePath = path
			RefreshPanelCompose()
		end
	end)

	local function SizeStepper(parentRow, field, minV, maxV, anchor)
		local minus = CreateFrame("Button", nil, parentRow, "UIPanelButtonTemplate")
		minus:SetSize(20, 18)
		minus:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
		minus:SetText("-")
		minus:SetScript("OnClick", function()
			NudgePanel(field, -1, minV, maxV)
		end)
		local value = parentRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
		value:SetWidth(24)
		value:SetJustifyH("CENTER")
		local plus = CreateFrame("Button", nil, parentRow, "UIPanelButtonTemplate")
		plus:SetSize(20, 18)
		plus:SetPoint("LEFT", value, "RIGHT", 4, 0)
		plus:SetText("+")
		plus:SetScript("OnClick", function()
			NudgePanel(field, 1, minV, maxV)
		end)
		return value
	end

	local geomRow = NextRow("Geometry")
	local tileCb = CreateFrame("CheckButton", nil, geomRow, "UICheckButtonTemplate")
	tileCb:SetPoint("LEFT", geomRow.label, "RIGHT", 0, 0)
	tileCb:SetSize(22, 22)
	tileCb:SetScript("OnClick", function(self)
		Addon.EnsureDB().panel.tile = self:GetChecked() and true or false
		RefreshPanelCompose()
	end)
	panel.tileCheck = tileCb
	local tileLbl = geomRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tileLbl:SetPoint("LEFT", tileCb, "RIGHT", 0, 0)
	tileLbl:SetText("tile")

	local tsLbl = geomRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	tsLbl:SetPoint("LEFT", tileLbl, "RIGHT", 12, 0)
	tsLbl:SetText("tile")
	panel.tileSizeLabel = SizeStepper(geomRow, "tileSize", 8, 128, tsLbl)

	local esLbl = geomRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	esLbl:SetPoint("LEFT", panel.tileSizeLabel, "RIGHT", 36, 0)
	esLbl:SetText("edge")
	panel.edgeSizeLabel = SizeStepper(geomRow, "edgeSize", 1, 64, esLbl)

	local inLbl = geomRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	inLbl:SetPoint("LEFT", panel.edgeSizeLabel, "RIGHT", 36, 0)
	inLbl:SetText("inset")
	panel.insetLabel = SizeStepper(geomRow, "inset", 0, 32, inLbl)

	local colorRow = NextRow("Colors")
	local function ColorChip(label, after, colorTable, withAlpha)
		local lbl = colorRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		lbl:SetPoint("LEFT", after, "RIGHT", after == colorRow.label and 4 or 12, 0)
		lbl:SetText(label)
		local sw = CreateSwatch(colorRow, 20, function()
			local payload = withAlpha and colorTable or { r = colorTable.r, g = colorTable.g, b = colorTable.b }
			Addon.OpenColorPicker(payload, function(r, g, b, a)
				colorTable.r, colorTable.g, colorTable.b = r, g, b
				if withAlpha then
					colorTable.a = a
				else
					-- Keep border/title/body fully opaque when picker has no opacity slider.
					if colorTable.a ~= nil then
						colorTable.a = 1
					end
				end
				RefreshPanelCompose()
			end)
		end)
		sw:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
		return sw
	end
	panel.bgSwatch = ColorChip("BG", colorRow.label, Addon.EnsureDB().panel.bgColor, true)
	-- Edge tint is RGB-only; opacity was wiping the border via inverted classic opacity.
	panel.edgeSwatch = ColorChip("Edge", panel.bgSwatch, Addon.EnsureDB().panel.edgeColor, false)
	panel.titleSwatch = ColorChip("Title", panel.edgeSwatch, Addon.EnsureDB().panel.titleColor, false)
	panel.bodySwatch = ColorChip("Body", panel.titleSwatch, Addon.EnsureDB().panel.bodyColor, false)

	if not panel.fontMenu then
		panel.fontMenu = BuildPopupMenu(280, Addon.FONT_OBJECTS, { previewFonts = true })
	end

	local titleFontRow = NextRow("Title font")
	local titleFontBtn = CreateDropdownButton(titleFontRow, 220)
	titleFontBtn:SetPoint("LEFT", titleFontRow.label, "RIGHT", 4, 0)
	titleFontBtn:SetScript("OnClick", function(self)
		local c = Addon.EnsureDB().panel.titleColor
		panel.fontMenu:SetPreviewColor(c.r, c.g, c.b, 1)
		ToggleMenu(panel.fontMenu, self, function(item)
			Addon.EnsureDB().panel.titleFont = item.value
			RefreshPanelCompose()
		end)
	end)
	panel.titleFontLabel = titleFontBtn.label

	local bodyFontRow = NextRow("Body font")
	local bodyFontBtn = CreateDropdownButton(bodyFontRow, 220)
	bodyFontBtn:SetPoint("LEFT", bodyFontRow.label, "RIGHT", 4, 0)
	bodyFontBtn:SetScript("OnClick", function(self)
		local c = Addon.EnsureDB().panel.bodyColor
		panel.fontMenu:SetPreviewColor(c.r, c.g, c.b, 1)
		ToggleMenu(panel.fontMenu, self, function(item)
			Addon.EnsureDB().panel.bodyFont = item.value
			RefreshPanelCompose()
		end)
	end)
	panel.bodyFontLabel = bodyFontBtn.label

	local palRow = NextRow("Palettes")
	local px = 0
	for _, pal in ipairs(Addon.PRESET_PALETTES) do
		local chip = CreateSwatch(palRow, 16, function()
			local db = Addon.EnsureDB().panel
			db.titleColor.r, db.titleColor.g, db.titleColor.b = pal.r, pal.g, pal.b
			RefreshPanelCompose()
		end)
		chip:SetColor(pal.r, pal.g, pal.b, 1)
		chip:SetPoint("LEFT", palRow.label, "RIGHT", 4 + px, 0)
		chip:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(pal.name)
			GameTooltip:Show()
		end)
		chip:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		px = px + 20
	end

	local resetBtn = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
	resetBtn:SetSize(100, 22)
	resetBtn:SetPoint("TOPLEFT", 0, y - 4)
	resetBtn:SetText("Reset")
	resetBtn:SetScript("OnClick", ResetPanelDefaults)

	return page
end

---------------------------------------------------------------------------
-- Compose → Button
---------------------------------------------------------------------------

local function DestroyPreviewButton()
	if panel and panel.previewButton then
		panel.previewButton:Hide()
		panel.previewButton:SetParent(nil)
		panel.previewButton = nil
	end
end

local function RefreshButtonCompose()
	if not panel or not panel.buttonStage then
		return
	end
	local db = Addon.EnsureDB().button
	DestroyPreviewButton()

	local style
	for _, s in ipairs(Addon.BUTTON_STYLES) do
		if s.id == db.style then
			style = s
			break
		end
	end
	style = style or Addon.BUTTON_STYLES[1]

	local btn
	if style.template then
		btn = CreateFrame("Button", "DevUtilsPreviewButton", panel.buttonStage, style.template)
	else
		btn = CreateFrame("Button", "DevUtilsPreviewButton", panel.buttonStage)
	end
	if not style.fixedSize then
		btn:SetSize(db.width or 120, db.height or 22)
	end
	btn:SetPoint("CENTER", panel.buttonStage, "CENTER", 0, 10)

	if style.custom then
		btn:SetNormalTexture(db.normalTex)
		btn:SetPushedTexture(db.pushedTex)
		btn:SetDisabledTexture(db.disabledTex)
		btn:SetHighlightTexture(db.highlightTex)
	elseif style.solid then
		btn.bg = btn:CreateTexture(nil, "BACKGROUND")
		btn.bg:SetAllPoints()
		SetSolidColor(btn.bg, db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgColor.a or 1)
		btn.border = btn:CreateTexture(nil, "BORDER")
		btn.border:SetPoint("TOPLEFT", -1, 1)
		btn.border:SetPoint("BOTTOMRIGHT", 1, -1)
		SetSolidColor(btn.border, db.borderColor.r, db.borderColor.g, db.borderColor.b, db.borderColor.a or 1)
		btn.border:SetDrawLayer("BACKGROUND", -1)
		btn:SetScript("OnEnter", function(self)
			SetSolidColor(self.bg, math.min(1, (db.bgColor.r or 0) + 0.1), math.min(1, (db.bgColor.g or 0) + 0.1), math.min(1, (db.bgColor.b or 0) + 0.1), db.bgColor.a or 1)
		end)
		btn:SetScript("OnLeave", function(self)
			SetSolidColor(self.bg, db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgColor.a or 1)
		end)
	end

	if not style.fixedSize then
		btn:SetText(Addon.GetButtonLabelText(db))
		local fs = btn:GetFontString()
		SafeSetFontObject(fs, db.font)
		if fs then
			fs:SetTextColor(db.textColor.r, db.textColor.g, db.textColor.b, 1)
		end
	end
	btn:SetScript("OnClick", function()
		print("|cff33ccff[DevUtils]|r Preview button clicked.")
	end)
	panel.previewButton = btn

	local isCustomLabel = db.labelPreset == "custom"
	local presetName = "Custom"
	if not isCustomLabel then
		presetName = db.labelPreset or "Sample Button"
	end
	if panel.buttonStyleLabel then panel.buttonStyleLabel:SetText(style.name) end
	if panel.buttonFontLabel then panel.buttonFontLabel:SetText(db.font) end
	if panel.buttonWidthLabel then panel.buttonWidthLabel:SetText(tostring(db.width)) end
	if panel.buttonHeightLabel then panel.buttonHeightLabel:SetText(tostring(db.height)) end
	if panel.buttonLabelLabel then panel.buttonLabelLabel:SetText(presetName) end
	if panel.buttonCustomText then
		panel.buttonCustomText:SetShown(isCustomLabel)
		if isCustomLabel and panel.buttonCustomText:GetText() ~= (db.customText or "") then
			panel.buttonCustomText:SetText(db.customText or "")
		end
	end
	if panel.buttonTextSwatch then panel.buttonTextSwatch:SetColor(db.textColor.r, db.textColor.g, db.textColor.b, 1) end
	if panel.buttonBgSwatch then panel.buttonBgSwatch:SetColor(db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgColor.a or 1) end
	if panel.buttonBorderSwatch then panel.buttonBorderSwatch:SetColor(db.borderColor.r, db.borderColor.g, db.borderColor.b, db.borderColor.a or 1) end
	if panel.normalTexLabel then panel.normalTexLabel:SetText((db.normalTex or ""):match("[^\\]+$") or "") end
	if panel.pushedTexLabel then panel.pushedTexLabel:SetText((db.pushedTex or ""):match("[^\\]+$") or "") end
	if panel.highlightTexLabel then panel.highlightTexLabel:SetText((db.highlightTex or ""):match("[^\\]+$") or "") end
	if panel.disabledTexLabel then panel.disabledTexLabel:SetText((db.disabledTex or ""):match("[^\\]+$") or "") end
	local showTextOpts = not style.fixedSize
	if panel.buttonLabelRow then panel.buttonLabelRow:SetShown(showTextOpts) end
	if panel.buttonFontRow then panel.buttonFontRow:SetShown(showTextOpts) end
	if panel.buttonWidthRow then panel.buttonWidthRow:SetShown(showTextOpts) end
	if panel.buttonHeightRow then panel.buttonHeightRow:SetShown(showTextOpts) end
	if panel.customTexBlock then panel.customTexBlock:SetShown(style.custom == true) end
	if panel.solidColorBlock then panel.solidColorBlock:SetShown(style.solid == true) end
	if panel.composeSelection then panel.composeSelection:Refresh() end
end

local function ResetButtonDefaults()
	local b = Addon.EnsureDB().button
	b.style = "UIPanelButtonTemplate"
	b.labelPreset = "Sample Button"
	b.customText = "Custom"
	b.width = 120
	b.height = 22
	b.font = "GameFontNormal"
	b.textColor.r, b.textColor.g, b.textColor.b = 1, 0.82, 0
	b.normalTex = "Interface\\Buttons\\UI-Panel-Button-Up"
	b.pushedTex = "Interface\\Buttons\\UI-Panel-Button-Down"
	b.disabledTex = "Interface\\Buttons\\UI-Panel-Button-Disabled"
	b.highlightTex = "Interface\\Buttons\\UI-Panel-Button-Highlight"
	b.bgColor.r, b.bgColor.g, b.bgColor.b, b.bgColor.a = 0.15, 0.15, 0.18, 1
	b.borderColor.r, b.borderColor.g, b.borderColor.b, b.borderColor.a = 0.45, 0.45, 0.5, 1
	RefreshButtonCompose()
end

local function NudgeButton(field, delta, minV, maxV)
	local db = Addon.EnsureDB().button
	local v = (db[field] or 0) + delta
	if minV then v = math.max(minV, v) end
	if maxV then v = math.min(maxV, v) end
	db[field] = v
	RefreshButtonCompose()
end

local function CreateButtonTool(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()

	local stage = CreateFrame("Frame", nil, page)
	stage:SetSize(360, 110)
	stage:SetPoint("TOP", 0, -4)
	local stageBg = stage:CreateTexture(nil, "BACKGROUND")
	stageBg:SetAllPoints()
	SetSolidColor(stageBg, 0.08, 0.08, 0.1, 0.95)
	panel.buttonStage = stage
	local hint = stage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOM", 0, 6)
	hint:SetText("Live preview — click to test")

	local controls = CreateFrame("Frame", nil, page)
	controls:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", -20, -12)
	controls:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -20, 4)

	local y = 0
	local function NextRow(label)
		local row = CreateLabeledRow(controls, label, 520)
		row:SetPoint("TOPLEFT", 0, y)
		y = y - 28
		return row
	end

	local styleItems = {}
	for _, s in ipairs(Addon.BUTTON_STYLES) do
		styleItems[#styleItems + 1] = { name = s.name, value = s.id }
	end
	panel.buttonStyleMenu = BuildPopupMenu(240, styleItems)

	local styleRow = NextRow("Style")
	local styleBtn = CreateDropdownButton(styleRow, 220)
	styleBtn:SetPoint("LEFT", styleRow.label, "RIGHT", 4, 0)
	styleBtn:SetScript("OnClick", function(self)
		ToggleMenu(panel.buttonStyleMenu, self, function(item)
			Addon.EnsureDB().button.style = item.value
			RefreshButtonCompose()
		end)
	end)
	panel.buttonStyleLabel = styleBtn.label

	panel.buttonLabelMenu = BuildPopupMenu(180, Addon.BUTTON_LABELS)

	local textRow = NextRow("Label")
	panel.buttonLabelRow = textRow
	local labelBtn = CreateDropdownButton(textRow, 160)
	labelBtn:SetPoint("LEFT", textRow.label, "RIGHT", 4, 0)
	labelBtn:SetScript("OnClick", function(self)
		ToggleMenu(panel.buttonLabelMenu, self, function(item)
			local db = Addon.EnsureDB().button
			db.labelPreset = item.value
			if item.value == "custom" and (not db.customText or db.customText == "") then
				db.customText = "Custom"
			end
			RefreshButtonCompose()
			if item.value == "custom" and panel.buttonCustomText then
				panel.buttonCustomText:SetFocus()
			end
		end)
	end)
	panel.buttonLabelLabel = labelBtn.label

	local customBox = CreateFrame("EditBox", "DevUtilsButtonCustomText", textRow, "InputBoxTemplate")
	customBox:SetSize(160, 20)
	customBox:SetPoint("LEFT", labelBtn, "RIGHT", 10, 0)
	customBox:SetAutoFocus(false)
	customBox:SetMaxLetters(48)
	customBox:Hide()
	customBox:SetScript("OnTextChanged", function(self, userInput)
		if not userInput then
			return
		end
		Addon.EnsureDB().button.customText = self:GetText() or ""
		RefreshButtonCompose()
	end)
	customBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	customBox:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	panel.buttonCustomText = customBox

	if not panel.buttonFontMenu then
		panel.buttonFontMenu = BuildPopupMenu(280, Addon.FONT_OBJECTS, { previewFonts = true })
	end

	local fontRow = NextRow("Font")
	panel.buttonFontRow = fontRow
	local fontBtn = CreateDropdownButton(fontRow, 200)
	fontBtn:SetPoint("LEFT", fontRow.label, "RIGHT", 4, 0)
	fontBtn:SetScript("OnClick", function(self)
		local c = Addon.EnsureDB().button.textColor
		panel.buttonFontMenu:SetPreviewColor(c.r, c.g, c.b, 1)
		ToggleMenu(panel.buttonFontMenu, self, function(item)
			Addon.EnsureDB().button.font = item.value
			RefreshButtonCompose()
		end)
	end)
	panel.buttonFontLabel = fontBtn.label
	panel.buttonTextSwatch = CreateSwatch(fontRow, 22, function()
		local c = Addon.EnsureDB().button.textColor
		Addon.OpenColorPicker({ r = c.r, g = c.g, b = c.b }, function(r, g, b)
			c.r, c.g, c.b = r, g, b
			RefreshButtonCompose()
		end)
	end)
	panel.buttonTextSwatch:SetPoint("LEFT", fontBtn, "RIGHT", 8, 0)

	local function SizeRow(label, field, minV, maxV)
		local row = NextRow(label)
		local minus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		minus:SetSize(22, 20)
		minus:SetPoint("LEFT", row.label, "RIGHT", 4, 0)
		minus:SetText("-")
		minus:SetScript("OnClick", function()
			NudgeButton(field, -2, minV, maxV)
		end)
		local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		value:SetPoint("LEFT", minus, "RIGHT", 8, 0)
		value:SetWidth(36)
		value:SetJustifyH("CENTER")
		local plus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		plus:SetSize(22, 20)
		plus:SetPoint("LEFT", value, "RIGHT", 8, 0)
		plus:SetText("+")
		plus:SetScript("OnClick", function()
			NudgeButton(field, 2, minV, maxV)
		end)
		return row, value
	end
	panel.buttonWidthRow, panel.buttonWidthLabel = SizeRow("Width", "width", 40, 400)
	panel.buttonHeightRow, panel.buttonHeightLabel = SizeRow("Height", "height", 16, 80)

	local customBlock = CreateFrame("Frame", nil, controls)
	customBlock:SetPoint("TOPLEFT", 0, y)
	customBlock:SetSize(520, 120)
	panel.customTexBlock = customBlock
	local function TexRow(label, field, yOff)
		local row = CreateFrame("Frame", nil, customBlock)
		row:SetSize(520, 24)
		row:SetPoint("TOPLEFT", 0, yOff)
		local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		lbl:SetPoint("LEFT", 0, 0)
		lbl:SetWidth(90)
		lbl:SetText(label)
		local pathFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		pathFs:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
		pathFs:SetWidth(240)
		pathFs:SetJustifyH("LEFT")
		local useSel = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		useSel:SetSize(110, 18)
		useSel:SetPoint("LEFT", pathFs, "RIGHT", 8, 0)
		useSel:SetText("Use selected")
		useSel:SetScript("OnClick", function()
			local selected = Addon.GetSelectedPath()
			if selected then
				Addon.EnsureDB().button[field] = selected
				RefreshButtonCompose()
			end
		end)
		return pathFs
	end
	local cy = 0
	local customTitle = customBlock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	customTitle:SetPoint("TOPLEFT", 0, cy)
	customTitle:SetText("Custom textures — assign Explore selection")
	cy = cy - 22
	panel.normalTexLabel = TexRow("Normal", "normalTex", cy)
	cy = cy - 26
	panel.pushedTexLabel = TexRow("Pushed", "pushedTex", cy)
	cy = cy - 26
	panel.highlightTexLabel = TexRow("Highlight", "highlightTex", cy)
	cy = cy - 26
	panel.disabledTexLabel = TexRow("Disabled", "disabledTex", cy)

	local solidBlock = CreateFrame("Frame", nil, controls)
	solidBlock:SetPoint("TOPLEFT", 0, y)
	solidBlock:SetSize(520, 50)
	panel.solidColorBlock = solidBlock
	local solidTitle = solidBlock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	solidTitle:SetPoint("TOPLEFT", 0, 0)
	solidTitle:SetText("Solid swatch colors")
	local bgLbl = solidBlock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	bgLbl:SetPoint("TOPLEFT", 0, -24)
	bgLbl:SetText("Fill")
	panel.buttonBgSwatch = CreateSwatch(solidBlock, 22, function()
		local c = Addon.EnsureDB().button.bgColor
		Addon.OpenColorPicker(c, function(r, g, b, a)
			c.r, c.g, c.b, c.a = r, g, b, a
			RefreshButtonCompose()
		end)
	end)
	panel.buttonBgSwatch:SetPoint("LEFT", bgLbl, "RIGHT", 8, 0)
	local borderLbl = solidBlock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	borderLbl:SetPoint("LEFT", panel.buttonBgSwatch, "RIGHT", 20, 0)
	borderLbl:SetText("Border")
	panel.buttonBorderSwatch = CreateSwatch(solidBlock, 22, function()
		local c = Addon.EnsureDB().button.borderColor
		Addon.OpenColorPicker(c, function(r, g, b, a)
			c.r, c.g, c.b, c.a = r, g, b, a
			RefreshButtonCompose()
		end)
	end)
	panel.buttonBorderSwatch:SetPoint("LEFT", borderLbl, "RIGHT", 8, 0)

	y = y - 130
	local resetBtn = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
	resetBtn:SetSize(100, 22)
	resetBtn:SetPoint("TOPLEFT", 0, y)
	resetBtn:SetText("Reset")
	resetBtn:SetScript("OnClick", ResetButtonDefaults)

	local disableToggle = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
	disableToggle:SetSize(120, 22)
	disableToggle:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)
	disableToggle:SetText("Toggle enable")
	disableToggle:SetScript("OnClick", function()
		if panel.previewButton then
			if panel.previewButton:IsEnabled() then
				panel.previewButton:Disable()
			else
				panel.previewButton:Enable()
			end
		end
	end)

	return page
end

---------------------------------------------------------------------------
-- Compose shell (Panel | Button tools)
---------------------------------------------------------------------------

local function SelectComposeTool(index)
	if not panel then
		return
	end
	panel.composeTool = index
	Addon.EnsureDB().composeTool = index
	for i, tab in ipairs(panel.composeTabs) do
		StyleTab(tab, i == index)
	end
	panel.panelTool:SetShown(index == 1)
	panel.buttonTool:SetShown(index == 2)
	if index == 1 then
		RefreshPanelCompose()
	else
		RefreshButtonCompose()
	end
end

local function CreateComposePage(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()
	page:Hide()

	panel.composeSelection = SelectionBanner(page)
	panel.composeSelection:SetPoint("TOPLEFT", 8, -2)
	panel.composeSelection:SetPoint("RIGHT", -8, 0)

	panel.composeTabs = {}
	local panelTab = CreateTabButton(page, "Panel", 100, function()
		HideMenus()
		SelectComposeTool(1)
	end)
	panelTab:SetPoint("TOPLEFT", 8, -28)
	panel.composeTabs[1] = panelTab

	local buttonTab = CreateTabButton(page, "Button", 100, function()
		HideMenus()
		SelectComposeTool(2)
	end)
	buttonTab:SetPoint("LEFT", panelTab, "RIGHT", 6, 0)
	panel.composeTabs[2] = buttonTab

	local toolHost = CreateFrame("Frame", nil, page)
	toolHost:SetPoint("TOPLEFT", 0, -62)
	toolHost:SetPoint("BOTTOMRIGHT", 0, 0)

	panel.panelTool = CreatePanelTool(toolHost)
	panel.buttonTool = CreateButtonTool(toolHost)
	panel.buttonTool:Hide()

	return page
end

---------------------------------------------------------------------------
-- Main frame (Explore | Compose)
---------------------------------------------------------------------------

function Addon.SelectTab(index)
	if not panel then
		return
	end
	panel.selectedTab = index
	Addon.EnsureDB().lastTab = index
	for i, tab in ipairs(panel.tabs) do
		StyleTab(tab, i == index)
	end
	panel.explorePage:SetShown(index == 1)
	panel.composePage:SetShown(index == 2)
	HideMenus()
	if index == 1 then
		RefreshExploreList()
		RefreshExplorePreview()
	else
		SelectComposeTool(panel.composeTool or Addon.EnsureDB().composeTool or 1)
	end
end

local function CreatePanel()
	local frame = CreateBackdropFrame("DevUtilsPanelFrame", UIParent)
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
		tinsert(UISpecialFrames, "DevUtilsPanelFrame")
	end

	ApplyBackdrop(
		frame,
		"Interface\\DialogFrame\\UI-DialogBox-Background",
		"Interface\\DialogFrame\\UI-DialogBox-Border",
		true, 32, 32, 8,
		{ r = 0, g = 0, b = 0, a = 0.92 },
		{ r = 1, g = 1, b = 1, a = 1 }
	)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("TOP", 0, -16)
	frame.title:SetText("DevUtils")

	frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close:SetPoint("TOPRIGHT", -4, -4)
	frame.close:SetScript("OnClick", function()
		HideMenus()
		frame:Hide()
	end)

	frame.tabs = {}
	local exploreTab = CreateTabButton(frame, "Explore", 130, function()
		HideMenus()
		Addon.SelectTab(1)
	end)
	exploreTab:SetPoint("TOPLEFT", 20, -48)
	frame.tabs[1] = exploreTab

	local composeTab = CreateTabButton(frame, "Compose", 130, function()
		HideMenus()
		Addon.SelectTab(2)
	end)
	composeTab:SetPoint("LEFT", exploreTab, "RIGHT", 6, 0)
	frame.tabs[2] = composeTab

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", 16, -84)
	content:SetPoint("BOTTOMRIGHT", -16, 16)
	frame.content = content

	panel = frame
	frame.explorePage = CreateExplorePage(content)
	frame.composePage = CreateComposePage(content)

	frame:SetScript("OnHide", HideMenus)
	frame:SetScript("OnShow", function()
		Addon.SelectTab(frame.selectedTab or Addon.EnsureDB().lastTab or 1)
	end)

	return frame
end

function Addon.ShowPanel(tabIndex)
	if not panel then
		panel = CreatePanel()
	end
	if tabIndex then
		panel.selectedTab = tabIndex
	end
	panel:Show()
	Addon.SelectTab(panel.selectedTab or Addon.EnsureDB().lastTab or 1)
end

function Addon.HidePanel()
	if panel then
		HideMenus()
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
