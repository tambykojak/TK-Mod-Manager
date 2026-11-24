local FRAME_WIDTH = 720
local FRAME_HEIGHT = 560
local LIST_WIDTH = 220
local ROW_HEIGHT = 22
local ITEM_ROW_HEIGHT = 28
local VISIBLE_LIST_ROWS = 22
local VISIBLE_ITEM_ROWS = 9
local PAD = 18
local TOP = 46
local DETAIL_WIDTH = FRAME_WIDTH - PAD * 2 - (LIST_WIDTH + 18) - 8

local ICON_SIZE = 22
local COL_GAP = 8
local COL_DROPS_W = 40
local COL_RATE_W = 52
local COL_SELL_W = 128

local TEX = {
	parchment = "Interface\\QuestFrame\\QuestBG",
	rowHighlight = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight",
	plus = "Interface\\Buttons\\UI-PlusButton-Up",
	minus = "Interface\\Buttons\\UI-MinusButton-Up",
	header = "Interface\\DialogFrame\\UI-DialogBox-Header",
}

--- Quest-log palette: gold headers, cream body text on darkened parchment.
local C = {
	gold = { 1, 0.82, 0, 1 },
	goldSoft = { 0.95, 0.84, 0.58, 1 },
	cream = { 1, 0.96, 0.86, 1 },
	white = { 1, 1, 1, 1 },
	muted = { 0.72, 0.68, 0.6, 1 },
	hidden = { 0.58, 0.56, 0.52, 1 },
	teal = { 0.62, 0.9, 0.74, 1 },
	rate = { 0.55, 0.85, 1, 1 },
	stripe = { 0, 0, 0, 0.16 },
	rule = { 0.8, 0.66, 0.36, 0.45 },
	edge = { 0.55, 0.47, 0.32, 1 },
	parchmentList = { 0.34, 0.3, 0.25, 1 },
	parchmentDetail = { 0.44, 0.39, 0.32, 1 },
}

local STYLE_WINDOW = {
	bg = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
	edge = "Interface\\DialogFrame\\UI-DialogBox-Border",
	edgeSize = 32,
	tileSize = 32,
	inset = 11,
}

local STYLE_INSET = {
	edge = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 16,
	tileSize = 16,
	inset = 4,
	edgeColor = C.edge,
}

local STYLE_TILE = {
	bg = "Interface\\Tooltips\\UI-Tooltip-Background",
	edge = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 12,
	tileSize = 16,
	inset = 3,
	bgColor = { 0, 0, 0, 0.45 },
	edgeColor = C.edge,
}

local STYLE_PORTRAIT = {
	bg = "Interface\\Tooltips\\UI-Tooltip-Background",
	edge = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 16,
	tileSize = 16,
	inset = 4,
	bgColor = { 0, 0, 0, 0.9 },
	edgeColor = { 0.8, 0.68, 0.4, 1 },
}

local STYLE_MENU = {
	bg = "Interface\\Tooltips\\UI-Tooltip-Background",
	edge = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 16,
	tileSize = 16,
	inset = 4,
	bgColor = { 0.04, 0.04, 0.05, 0.96 },
	edgeColor = { 0.8, 0.68, 0.4, 1 },
}

--- Remembered yaw per mob name (radians) for the portrait model.
local portraitFacing = {}

local journal
local selectedMob
local listOffset = 0
local itemOffset = 0
local listButtons = {}
local itemButtons = {}
local contextMenu
local renderRows = {} -- rebuilt each Refresh

local function SetSolidColor(texture, r, g, b, a)
	a = a or 1
	if texture.SetColorTexture then
		texture:SetColorTexture(r, g, b, a)
		return
	end
	texture:SetTexture("Interface\\Buttons\\WHITE8X8")
	texture:SetVertexColor(r, g, b, a)
end

local function Paint(tex, color)
	SetSolidColor(tex, color[1], color[2], color[3], color[4] or 1)
end

local function Tint(fs, color)
	fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function SetFontSize(fs, size)
	if not fs.SetFont then
		return
	end
	local font, _, flags = fs:GetFont()
	if font then
		fs:SetFont(font, size, flags or "")
	end
end

local function MakeFont(parent, template, size)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
	if size then
		SetFontSize(fs, size)
	end
	return fs
end

local function MakeRule(parent, color)
	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	Paint(rule, color or C.rule)
	return rule
end

--- Forever / modern clients need BackdropTemplate for SetBackdrop.
local function CreateBackdropFrame(frameType, name, parent)
	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	local frame = CreateFrame(frameType or "Frame", name, parent, template)
	if not frame.SetBackdrop and BackdropTemplateMixin and Mixin then
		Mixin(frame, BackdropTemplateMixin)
		if frame.OnBackdropLoaded then
			frame:OnBackdropLoaded()
		end
	end
	return frame
end

local function ApplyBackdrop(frame, style)
	if frame.SetBackdrop then
		local i = style.inset or 4
		frame:SetBackdrop({
			bgFile = style.bg,
			edgeFile = style.edge,
			tile = true,
			tileSize = style.tileSize or 16,
			edgeSize = style.edgeSize or 16,
			insets = { left = i, right = i, top = i, bottom = i },
		})
		local bg = style.bgColor
		if bg and frame.SetBackdropColor then
			frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
		end
		local edge = style.edgeColor
		if edge and frame.SetBackdropBorderColor then
			frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
		end
		return
	end

	local fill = frame:CreateTexture(nil, "BACKGROUND")
	fill:SetPoint("TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", -1, 1)
	Paint(fill, style.bgColor or { 0.06, 0.06, 0.07, 0.95 })
	local edge = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
	edge:SetAllPoints()
	Paint(edge, style.edgeColor or C.edge)
end

--- Darkened quest-log parchment laid inside an inset panel.
local function AddParchment(panel, tint)
	local tex = panel:CreateTexture(nil, "BACKGROUND")
	tex:SetPoint("TOPLEFT", 4, -4)
	tex:SetPoint("BOTTOMRIGHT", -4, 4)
	tex:SetTexture(TEX.parchment)
	tex:SetTexCoord(0, 0.5859375, 0, 0.65625)
	tex:SetVertexColor(tint[1], tint[2], tint[3], 1)
	tex:SetDrawLayer("BACKGROUND", 1)
	return tex
end

local function AddRowHighlight(btn, layer)
	local tex = btn:CreateTexture(nil, layer or "HIGHLIGHT")
	tex:SetAllPoints()
	tex:SetTexture(TEX.rowHighlight)
	tex:SetBlendMode("ADD")
	return tex
end

--- "12" plus the gold, silver, or copper coin. Size is explicit: 0 follows the font and blanks the icon here.
local function CoinPiece(amount, icon)
	return string.format("%d|TInterface\\MoneyFrame\\UI-%sIcon:14:14:2:0|t", amount, icon)
end

local function FormatCoins(copper)
	copper = math.floor(tonumber(copper) or 0)
	if copper < 0 then
		copper = 0
	end
	local gold = math.floor(copper / 10000)
	local silver = math.floor((copper % 10000) / 100)
	local copperLeft = copper % 100
	if gold > 0 then
		return CoinPiece(gold, "Gold") .. " " .. CoinPiece(silver, "Silver") .. " " .. CoinPiece(copperLeft, "Copper")
	end
	if silver > 0 then
		return CoinPiece(silver, "Silver") .. " " .. CoinPiece(copperLeft, "Copper")
	end
	return CoinPiece(copperLeft, "Copper")
end

local function QualityColor(quality)
	quality = tonumber(quality) or 1
	if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
		local c = ITEM_QUALITY_COLORS[quality]
		return c.r, c.g, c.b
	end
	if GetItemQualityColor then
		local r, g, b = GetItemQualityColor(quality)
		return r, g, b
	end
	return 1, 1, 1
end

local function HideContextMenu()
	if contextMenu then
		contextMenu:Hide()
	end
end

local function SetSelectedMob(name)
	selectedMob = name
	itemOffset = 0
	if journal and journal.Refresh then
		journal:Refresh()
	end
end

local function AppendMobs(rows, names, zone, area, hidden)
	local kind = hidden and "hiddenMob" or "mob"
	for _, mobName in ipairs(names) do
		rows[#rows + 1] = {
			kind = kind,
			name = mobName,
			location = zone,
			area = area,
		}
	end
end

local function AppendAreas(rows, zone, areas, hidden)
	local kind = hidden and "hiddenArea" or "area"
	for _, area in ipairs(areas) do
		local mobs
		if hidden and (MobLedger_IsLocationHidden(zone) or MobLedger_IsAreaHidden(zone, area)) then
			mobs = MobLedger_GetMobNamesInArea(zone, area)
		elseif hidden then
			mobs = {}
			for _, name in ipairs(MobLedger_GetMobNamesInArea(zone, area)) do
				if MobLedger_IsMobHidden(name) then
					mobs[#mobs + 1] = name
				end
			end
		else
			mobs = MobLedger_GetVisibleMobNamesInArea(zone, area)
		end
		local expanded = MobLedger_IsAreaExpanded(zone, area)
		rows[#rows + 1] = {
			kind = kind,
			name = area,
			location = zone,
			expanded = expanded,
			count = #mobs,
		}
		if expanded then
			AppendMobs(rows, mobs, zone, area, hidden)
		end
	end
end

local function AreasForHiddenZone(zone)
	if MobLedger_IsLocationHidden(zone) then
		return MobLedger_GetAreaNames(zone)
	end
	local seen = {}
	local list = {}
	for _, area in ipairs(MobLedger_GetHiddenAreaNames(zone)) do
		seen[area] = true
		list[#list + 1] = area
	end
	for _, name in ipairs(MobLedger_GetHiddenMobNames()) do
		local mob = MobLedger_GetMob(name)
		if mob and MobLedger_MobHasLocation(mob, zone) then
			for _, area in ipairs(MobLedger_GetAreaNames(zone)) do
				if not seen[area] and MobLedger_MobInArea(mob, zone, area) then
					seen[area] = true
					list[#list + 1] = area
				end
			end
		end
	end
	table.sort(list)
	return list
end

local function ZonesForHiddenSection()
	local seen = {}
	local list = {}
	for _, loc in ipairs(MobLedger_GetHiddenLocationNames()) do
		seen[loc] = true
		list[#list + 1] = loc
	end
	for _, loc in ipairs(MobLedger_GetLocationNames()) do
		if not seen[loc] and #MobLedger_GetHiddenAreaNames(loc) > 0 then
			seen[loc] = true
			list[#list + 1] = loc
		end
	end
	for _, name in ipairs(MobLedger_GetHiddenMobNames()) do
		local mob = MobLedger_GetMob(name)
		if mob then
			for _, loc in ipairs(MobLedger_GetLocationNames()) do
				if not seen[loc] and MobLedger_MobHasLocation(mob, loc) then
					seen[loc] = true
					list[#list + 1] = loc
				end
			end
		end
	end
	table.sort(list)
	return list
end

--- Flat accordion: zone, then subzone, then mobs.
local function BuildRenderRows()
	local rows = {}

	for _, loc in ipairs(MobLedger_GetVisibleLocationNames()) do
		local areas = MobLedger_GetVisibleAreaNames(loc)
		local expanded = MobLedger_IsLocationExpanded(loc)
		rows[#rows + 1] = {
			kind = "location",
			name = loc,
			expanded = expanded,
			count = #areas,
		}
		if expanded then
			AppendAreas(rows, loc, areas, false)
		end
	end

	local hiddenOpen = MobLedger_IsHiddenSectionExpanded()
	local hiddenLocs = ZonesForHiddenSection()
	rows[#rows + 1] = {
		kind = "hiddenHeader",
		expanded = hiddenOpen,
		count = #hiddenLocs,
	}
	if hiddenOpen then
		if #hiddenLocs == 0 then
			rows[#rows + 1] = { kind = "hiddenEmpty" }
		else
			for _, loc in ipairs(hiddenLocs) do
				local areas = AreasForHiddenZone(loc)
				local expanded = MobLedger_IsLocationExpanded(loc)
				rows[#rows + 1] = {
					kind = "hiddenLocation",
					name = loc,
					expanded = expanded,
					count = #areas,
				}
				if expanded then
					AppendAreas(rows, loc, areas, true)
				end
			end
		end
	end

	return rows
end

local function BuildSortedItems(mob)
	local rows = {}
	if not mob or not mob.items then
		return rows
	end
	for key, item in pairs(mob.items) do
		rows[#rows + 1] = {
			key = key,
			name = item.name or key,
			link = item.link,
			icon = MobLedger_ResolveItemIcon(item),
			quality = item.quality or 1,
			drops = item.drops or 0,
			quantity = item.quantity or 0,
			rate = MobLedger_GetDropRate(mob, key),
			sellPrice = MobLedger_GetItemSellPrice(item),
		}
	end
	table.sort(rows, function(a, b)
		if a.rate ~= b.rate then
			return a.rate > b.rate
		end
		if a.drops ~= b.drops then
			return a.drops > b.drops
		end
		return a.name < b.name
	end)
	return rows
end

--- items: { { label = "...", onClick = function() end }, ... }
local function ShowContextMenu(anchor, items)
	HideContextMenu()
	if type(items) ~= "table" or #items == 0 then
		return
	end

	local rowH = 22
	local width = 170
	local menu = contextMenu
	if not menu then
		menu = CreateBackdropFrame("Frame", "MobLedgerContextMenu", UIParent)
		ApplyBackdrop(menu, STYLE_MENU)
		menu:SetFrameStrata("TOOLTIP")
		menu:SetFrameLevel(250)
		menu:SetToplevel(true)
		menu:EnableMouse(true)
		menu.buttons = {}
	end
	menu:SetSize(width, #items * rowH + 12)

	for i, item in ipairs(items) do
		local btn = menu.buttons[i]
		if not btn then
			btn = CreateFrame("Button", nil, menu)
			btn:SetSize(width - 12, rowH)
			btn:SetPoint("TOPLEFT", 6, -6 - (i - 1) * rowH)
			btn:RegisterForClicks("LeftButtonUp")
			local hl = AddRowHighlight(btn)
			hl:SetVertexColor(1, 0.82, 0.3, 0.8)
			btn.label = MakeFont(btn, "GameFontHighlightSmall", 12)
			btn.label:SetPoint("LEFT", 8, 0)
			btn.label:SetPoint("RIGHT", -8, 0)
			btn.label:SetJustifyH("LEFT")
			menu.buttons[i] = btn
		end
		btn.label:SetText(item.label)
		btn:SetScript("OnClick", function()
			HideContextMenu()
			if item.onClick then
				item.onClick()
			end
		end)
		btn:Show()
	end
	for i = #items + 1, #menu.buttons do
		menu.buttons[i]:Hide()
	end

	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 4)
	menu:Show()
	contextMenu = menu
	return menu
end

local function RefreshJournal()
	if journal then
		journal:Refresh()
	end
end

local function ContextHideMob(name)
	MobLedger_SetMobHidden(name, true)
	if selectedMob == name then
		selectedMob = nil
	end
	RefreshJournal()
end

local function ContextHideZone(location)
	if not location then
		return
	end
	MobLedger_SetLocationHidden(location, true)
	RefreshJournal()
end

local function ContextUnhideMob(name)
	MobLedger_SetMobHidden(name, false)
	RefreshJournal()
end

local function ContextUnhideZone(location)
	if not location then
		return
	end
	MobLedger_SetLocationHidden(location, false)
	RefreshJournal()
end

local function ContextHideArea(zone, area)
	if not zone or not area then
		return
	end
	MobLedger_SetAreaHidden(zone, area, true)
	RefreshJournal()
end

local function ContextUnhideArea(zone, area)
	if not zone or not area then
		return
	end
	MobLedger_SetAreaHidden(zone, area, false)
	RefreshJournal()
end

local CONTEXT_ACTIONS = {
	location = { "Hide entire zone", function(row) ContextHideZone(row.name) end },
	area = { "Hide entire subzone", function(row) ContextHideArea(row.location, row.name) end },
	mob = { "Hide mob", function(row) ContextHideMob(row.name) end },
	hiddenLocation = { "Unhide entire zone", function(row) ContextUnhideZone(row.name) end },
	hiddenArea = { "Unhide entire subzone", function(row) ContextUnhideArea(row.location, row.name) end },
	hiddenMob = { "Unhide mob", function(row) ContextUnhideMob(row.name) end },
}

local function CreateListButton(parent, index)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetHeight(ROW_HEIGHT)
	btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
	btn:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	btn.rowIndex = index
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:EnableMouse(true)

	btn.bg = btn:CreateTexture(nil, "BACKGROUND")
	btn.bg:SetAllPoints()
	Paint(btn.bg, { 0, 0, 0, 0 })

	btn.sel = AddRowHighlight(btn, "ARTWORK")
	btn.sel:SetVertexColor(1, 0.78, 0.25, 0.85)
	btn.sel:Hide()

	btn.accent = btn:CreateTexture(nil, "OVERLAY")
	btn.accent:SetWidth(2)
	btn.accent:SetPoint("TOPLEFT", 0, -2)
	btn.accent:SetPoint("BOTTOMLEFT", 0, 2)
	Paint(btn.accent, C.gold)
	btn.accent:Hide()

	btn.hl = AddRowHighlight(btn)

	btn.topRule = MakeRule(btn, C.rule)
	btn.topRule:SetPoint("TOPLEFT", 4, 0)
	btn.topRule:SetPoint("TOPRIGHT", -4, 0)
	btn.topRule:Hide()

	btn.expand = btn:CreateTexture(nil, "OVERLAY")
	btn.expand:SetSize(14, 14)

	btn.label = MakeFont(btn, "GameFontNormal", 12)
	btn.label:SetPoint("RIGHT", -34, 0)
	btn.label:SetJustifyH("LEFT")
	if btn.label.SetWordWrap then
		btn.label:SetWordWrap(false)
	end

	btn.meta = MakeFont(btn, "GameFontHighlightSmall", 10)
	btn.meta:SetPoint("RIGHT", -8, 0)
	btn.meta:SetJustifyH("RIGHT")
	Tint(btn.meta, C.muted)

	btn:SetScript("OnClick", function(self, button)
		HideContextMenu()
		local row = self.row
		if not row then
			return
		end

		if button == "RightButton" then
			local action = CONTEXT_ACTIONS[row.kind]
			if action then
				ShowContextMenu(self, {
					{
						label = action[1],
						onClick = function()
							action[2](row)
						end,
					},
				})
			end
			return
		end

		if row.kind == "location" or row.kind == "hiddenLocation" then
			MobLedger_SetLocationExpanded(row.name, not row.expanded)
			RefreshJournal()
		elseif row.kind == "area" or row.kind == "hiddenArea" then
			MobLedger_SetAreaExpanded(row.location, row.name, not row.expanded)
			RefreshJournal()
		elseif row.kind == "mob" or row.kind == "hiddenMob" then
			SetSelectedMob(row.name)
		elseif row.kind == "hiddenHeader" then
			MobLedger_SetHiddenSectionExpanded(not row.expanded)
			RefreshJournal()
		end
	end)

	return btn
end

--- Indent, font size, colors, and +/- icon for one accordion row.
local ROW_LOOK = {
	location = { iconX = 4, labelX = 22, size = 12, color = C.gold, hl = C.gold },
	area = { iconX = 16, labelX = 34, size = 11, color = C.goldSoft, hl = C.goldSoft },
	mob = { labelX = 40, size = 11, color = C.cream, hl = C.white },
	hiddenHeader = { iconX = 4, labelX = 22, size = 12, color = C.hidden, hl = C.hidden },
	hiddenLocation = { iconX = 10, labelX = 28, size = 11, color = C.hidden, hl = C.hidden },
	hiddenArea = { iconX = 22, labelX = 40, size = 11, color = C.hidden, hl = C.hidden },
	hiddenMob = { labelX = 46, size = 11, color = C.hidden, hl = C.hidden },
	hiddenEmpty = { labelX = 28, size = 11, color = C.muted },
}

local function ConfigureListRow(btn, row)
	local look = ROW_LOOK[row.kind] or ROW_LOOK.mob
	local isMob = row.kind == "mob" or row.kind == "hiddenMob"

	if look.iconX then
		btn.expand:ClearAllPoints()
		btn.expand:SetPoint("LEFT", look.iconX, 0)
		btn.expand:SetTexture(row.expanded and TEX.minus or TEX.plus)
		btn.expand:Show()
	else
		btn.expand:Hide()
	end

	btn.label:ClearAllPoints()
	btn.label:SetPoint("LEFT", look.labelX, 0)
	btn.label:SetPoint("RIGHT", -34, 0)
	SetFontSize(btn.label, look.size)
	Tint(btn.label, look.color)

	if look.hl then
		btn.hl:SetVertexColor(look.hl[1], look.hl[2], look.hl[3], 0.7)
		btn.hl:Show()
	else
		btn.hl:Hide()
	end

	local selected = isMob and row.name == selectedMob
	btn.sel:SetShown(selected)
	btn.accent:SetShown(selected)
	if selected then
		Tint(btn.label, C.white)
	end

	btn.topRule:SetShown(row.kind == "hiddenHeader")
	if row.kind == "location" then
		Paint(btn.bg, { 0, 0, 0, 0.22 })
	elseif row.kind == "hiddenHeader" then
		Paint(btn.bg, { 0, 0, 0, 0.3 })
	else
		Paint(btn.bg, { 0, 0, 0, 0 })
	end

	if row.kind == "hiddenHeader" then
		btn.label:SetText("Hidden")
		btn.meta:SetText(row.count > 0 and tostring(row.count) or "")
	elseif row.kind == "hiddenEmpty" then
		btn.label:SetText("Nothing hidden")
		btn.meta:SetText("")
	elseif isMob then
		btn.label:SetText(row.name)
		local mob = MobLedger_GetMob(row.name)
		btn.meta:SetText(tostring(mob and mob.loots or 0))
	else
		btn.label:SetText(row.name)
		btn.meta:SetText(tostring(row.count))
	end
end

local function CreateItemButton(parent, index)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetHeight(ITEM_ROW_HEIGHT)
	btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ITEM_ROW_HEIGHT))
	btn:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	btn.rowIndex = index

	btn.bg = btn:CreateTexture(nil, "BACKGROUND")
	btn.bg:SetAllPoints()
	Paint(btn.bg, index % 2 == 0 and C.stripe or { 0, 0, 0, 0 })

	local hl = AddRowHighlight(btn)
	hl:SetVertexColor(1, 0.9, 0.6, 0.55)

	btn.iconEdge = btn:CreateTexture(nil, "BORDER")
	btn.iconEdge:SetSize(ICON_SIZE + 2, ICON_SIZE + 2)
	btn.iconEdge:SetPoint("LEFT", 6, 0)

	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetSize(ICON_SIZE, ICON_SIZE)
	btn.icon:SetPoint("CENTER", btn.iconEdge, "CENTER", 0, 0)
	btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	-- SELL is pinned to the right so it stays inside the visible row.
	-- White so the embedded coin icons keep their own colors.
	btn.sell = MakeFont(btn, "GameFontHighlightSmall", 11)
	btn.sell:SetPoint("RIGHT", -6, 0)
	btn.sell:SetWidth(COL_SELL_W)
	btn.sell:SetJustifyH("RIGHT")
	btn.sell:SetTextColor(1, 1, 1)

	btn.rate = MakeFont(btn, "GameFontHighlight", 12)
	btn.rate:SetPoint("RIGHT", btn.sell, "LEFT", -COL_GAP, 0)
	btn.rate:SetWidth(COL_RATE_W)
	btn.rate:SetJustifyH("RIGHT")
	Tint(btn.rate, C.rate)

	-- DROPS = how many loot windows contained this item (not total stacks).
	btn.drops = MakeFont(btn, "GameFontHighlightSmall", 11)
	btn.drops:SetPoint("RIGHT", btn.rate, "LEFT", -COL_GAP, 0)
	btn.drops:SetWidth(COL_DROPS_W)
	btn.drops:SetJustifyH("RIGHT")
	Tint(btn.drops, C.cream)

	btn.name = MakeFont(btn, "GameFontHighlight", 12)
	btn.name:SetPoint("LEFT", ICON_SIZE + 14, 0)
	btn.name:SetPoint("RIGHT", btn.drops, "LEFT", -COL_GAP, 0)
	btn.name:SetJustifyH("LEFT")
	if btn.name.SetWordWrap then
		btn.name:SetWordWrap(false)
	end

	btn:SetScript("OnEnter", function(self)
		if self.itemLink and GameTooltip and GameTooltip.SetHyperlink then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self.itemLink)
			GameTooltip:Show()
		end
	end)
	btn:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)

	return btn
end

local function MakeStatTile(parent, width, caption, valueColor)
	local tile = CreateBackdropFrame("Frame", nil, parent)
	ApplyBackdrop(tile, STYLE_TILE)
	tile:SetSize(width, 44)
	tile.caption = MakeFont(tile, "GameFontNormalSmall", 9)
	tile.caption:SetPoint("TOPLEFT", 9, -7)
	tile.caption:SetPoint("TOPRIGHT", -9, -7)
	tile.caption:SetJustifyH("LEFT")
	tile.caption:SetText(caption)
	Tint(tile.caption, C.gold)
	tile.value = MakeFont(tile, "GameFontHighlight", 13)
	tile.value:SetPoint("BOTTOMLEFT", 9, 8)
	tile.value:SetPoint("BOTTOMRIGHT", -9, 8)
	tile.value:SetJustifyH("LEFT")
	Tint(tile.value, valueColor or C.white)
	return tile
end

local function MakeColumnHeader(parent, text, width, justify)
	local fs = MakeFont(parent, "GameFontNormalSmall", 9)
	fs:SetWidth(width)
	fs:SetJustifyH(justify or "RIGHT")
	fs:SetText(text)
	Tint(fs, C.goldSoft)
	return fs
end

--- Magenta, with the same outer margin as the journal and room around the label.
local DEV_BTN_H = 26
local DEV_BTN_PAD_X = 16
--- Visible gap on every side of the dev button, inside the dialog border.
local DEV_GAP = 10
--- Tooltip border's opaque edge sits this far inside the panel frame.
local DEV_ALIGN = 3

local function MakeDevButton(parent, text, onClick)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetHeight(DEV_BTN_H)
	btn:RegisterForClicks("LeftButtonUp")
	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	Paint(bg, { 0.85, 0.08, 0.72, 1 })
	btn.label = MakeFont(btn, "GameFontHighlight", 11)
	btn.label:SetPoint("LEFT", DEV_BTN_PAD_X, 0)
	btn.label:SetPoint("RIGHT", -DEV_BTN_PAD_X, 0)
	btn.label:SetJustifyH("CENTER")
	btn.label:SetText(text)
	Tint(btn.label, { 1, 1, 1, 1 })
	local textW = btn.label:GetStringWidth() or 0
	if textW < 40 then
		textW = 88
	end
	btn:SetWidth(textW + DEV_BTN_PAD_X * 2)
	btn:SetScript("OnEnter", function()
		Paint(bg, { 0.15, 0.75, 0.85, 1 })
	end)
	btn:SetScript("OnLeave", function()
		Paint(bg, { 0.85, 0.08, 0.72, 1 })
	end)
	btn:SetScript("OnClick", onClick)
	return btn
end

local function CreateJournal()
	local frame = CreateBackdropFrame("Frame", "MobLedgerJournalFrame", UIParent)
	ApplyBackdrop(frame, STYLE_WINDOW)
	frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:Hide()
	if UISpecialFrames then
		tinsert(UISpecialFrames, "MobLedgerJournalFrame")
	end

	-- Classic gold banner over the top edge, like the stock dialog windows.
	local banner = frame:CreateTexture(nil, "ARTWORK")
	banner:SetTexture(TEX.header)
	banner:SetSize(300, 64)
	banner:SetPoint("TOP", 0, 12)

	frame.title = MakeFont(frame, "GameFontNormal", 13)
	frame.title:SetPoint("TOP", banner, "TOP", 0, -14)
	frame.title:SetText("Mob Ledger")
	Tint(frame.title, C.gold)

	frame.summaryLeft = MakeFont(frame, "GameFontHighlightSmall", 11)
	frame.summaryLeft:SetPoint("TOPLEFT", PAD + 4, -22)
	frame.summaryLeft:SetJustifyH("LEFT")
	Tint(frame.summaryLeft, C.muted)

	frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close:SetPoint("TOPRIGHT", -5, -5)
	frame.close:SetScript("OnClick", function()
		HideContextMenu()
		frame:Hide()
	end)

	frame:SetScript("OnHide", function()
		HideContextMenu()
		if frame.DetachPortraits then
			frame:DetachPortraits()
		end
	end)

	-- Left: zone / subzone / mob accordion on dark parchment.
	local left = CreateBackdropFrame("Frame", nil, frame)
	ApplyBackdrop(left, STYLE_INSET)
	left:SetPoint("TOPLEFT", PAD, -TOP)
	left:SetPoint("BOTTOMLEFT", PAD, PAD)
	left:SetWidth(LIST_WIDTH + 18)
	AddParchment(left, C.parchmentList)

	frame.listScroll = CreateFrame("ScrollFrame", "MobLedgerListScroll", left)
	frame.listScroll:SetPoint("TOPLEFT", 6, -6)
	frame.listScroll:SetPoint("BOTTOMRIGHT", -6, 6)

	frame.listChild = CreateFrame("Frame", nil, frame.listScroll)
	frame.listChild:SetWidth(LIST_WIDTH + 6)
	frame.listChild:SetHeight(VISIBLE_LIST_ROWS * ROW_HEIGHT)
	frame.listScroll:SetScrollChild(frame.listChild)

	frame.listScroll:EnableMouseWheel(true)
	frame.listScroll:SetScript("OnMouseWheel", function(_, delta)
		local maxOffset = math.max(0, #renderRows - VISIBLE_LIST_ROWS)
		listOffset = math.min(maxOffset, math.max(0, listOffset - delta))
		frame:Refresh()
	end)

	for i = 1, VISIBLE_LIST_ROWS do
		listButtons[i] = CreateListButton(frame.listChild, i)
	end

	frame.listEmpty = MakeFont(left, "GameFontHighlightSmall", 11)
	frame.listEmpty:SetPoint("TOPLEFT", 14, -40)
	frame.listEmpty:SetPoint("RIGHT", -14, 0)
	frame.listEmpty:SetJustifyH("LEFT")
	frame.listEmpty:SetText("No mobs yet. Loot something and it will show up here.")
	Tint(frame.listEmpty, C.muted)
	frame.listEmpty:Hide()

	-- Right: mob details on lighter parchment.
	local right = CreateBackdropFrame("Frame", nil, frame)
	ApplyBackdrop(right, STYLE_INSET)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
	right:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	AddParchment(right, C.parchmentDetail)

	frame.placeholder = MakeFont(right, "GameFontNormal", 13)
	frame.placeholder:SetPoint("CENTER", 0, 10)
	frame.placeholder:SetText("Select a mob from the ledger")
	Tint(frame.placeholder, C.goldSoft)

	frame.placeholderSub = MakeFont(right, "GameFontHighlightSmall", 11)
	frame.placeholderSub:SetPoint("TOP", frame.placeholder, "BOTTOM", 0, -6)
	frame.placeholderSub:SetText("Right-click any row to hide it")
	Tint(frame.placeholderSub, C.muted)

	local detail = CreateFrame("Frame", nil, right)
	detail:SetAllPoints()
	frame.detail = detail

	frame.portraitShell = CreateBackdropFrame("Frame", nil, detail)
	ApplyBackdrop(frame.portraitShell, STYLE_PORTRAIT)
	frame.portraitShell:SetSize(84, 84)
	frame.portraitShell:SetPoint("TOPLEFT", 12, -12)

	frame.portraitModel = CreateFrame("PlayerModel", nil, frame.portraitShell)
	frame.portraitModel:SetPoint("TOPLEFT", 5, -5)
	frame.portraitModel:SetPoint("BOTTOMRIGHT", -5, 5)
	frame.portraitModel:EnableMouse(true)
	frame.portraitModel:EnableMouseWheel(false)
	frame.portraitModel:Hide()

	local function ApplyModelFacing(model, facing)
		facing = facing or 0
		model.facing = facing
		if model.SetRotation then
			model:SetRotation(facing)
		elseif model.SetFacing then
			model:SetFacing(facing)
		end
		if model.mobName then
			portraitFacing[model.mobName] = facing
		end
	end

	frame.portraitModel:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then
			return
		end
		self.rotating = true
		self.dragX = select(1, GetCursorPosition())
		self.dragFacing = self.facing or 0
	end)
	frame.portraitModel:SetScript("OnMouseUp", function(self)
		self.rotating = false
	end)
	frame.portraitModel:SetScript("OnEnter", function(self)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Drag to rotate", 1, 0.82, 0)
			GameTooltip:Show()
		end
	end)
	frame.portraitModel:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	frame.portraitModel:SetScript("OnUpdate", function(self)
		if self.applyFacing then
			self.applyFacing = false
			ApplyModelFacing(self, self.facing or 0)
		end
		if not self.rotating then
			return
		end
		local x = select(1, GetCursorPosition())
		local scale = self:GetEffectiveScale() or 1
		if scale == 0 then
			scale = 1
		end
		local dx = (x - (self.dragX or x)) / scale
		ApplyModelFacing(self, (self.dragFacing or 0) + dx * 0.012)
	end)
	frame.ApplyModelFacing = ApplyModelFacing

	frame.portraitTex = frame.portraitShell:CreateTexture(nil, "ARTWORK")
	frame.portraitTex:SetPoint("TOPLEFT", 5, -5)
	frame.portraitTex:SetPoint("BOTTOMRIGHT", -5, 5)
	frame.portraitTex:Hide()

	frame.portraitEmpty = MakeFont(frame.portraitShell, "GameFontNormalLarge", 22)
	frame.portraitEmpty:SetPoint("CENTER", 0, 0)
	frame.portraitEmpty:SetText("?")
	Tint(frame.portraitEmpty, C.muted)

	frame.detailHeader = MakeFont(detail, "GameFontNormalLarge", 18)
	frame.detailHeader:SetPoint("TOPLEFT", frame.portraitShell, "TOPRIGHT", 12, -8)
	frame.detailHeader:SetPoint("RIGHT", -14, 0)
	frame.detailHeader:SetJustifyH("LEFT")
	Tint(frame.detailHeader, C.cream)

	frame.locationText = MakeFont(detail, "GameFontHighlightSmall", 11)
	frame.locationText:SetPoint("TOPLEFT", frame.detailHeader, "BOTTOMLEFT", 0, -6)
	frame.locationText:SetPoint("RIGHT", -14, 0)
	frame.locationText:SetJustifyH("LEFT")
	Tint(frame.locationText, C.teal)

	frame.hiddenTag = MakeFont(detail, "GameFontHighlightSmall", 10)
	frame.hiddenTag:SetPoint("TOPLEFT", frame.locationText, "BOTTOMLEFT", 0, -6)
	frame.hiddenTag:SetText("Hidden from the main list")
	Tint(frame.hiddenTag, C.hidden)

	local gap = 6
	local tileW = math.floor((DETAIL_WIDTH - 24 - gap * 3) / 4)
	frame.statLoots = MakeStatTile(detail, tileW, "LOOTS", C.white)
	frame.statLoots:SetPoint("TOPLEFT", frame.portraitShell, "BOTTOMLEFT", 0, -10)
	frame.statAvg = MakeStatTile(detail, tileW, "AVG MONEY", C.white)
	frame.statAvg:SetPoint("LEFT", frame.statLoots, "RIGHT", gap, 0)
	frame.statTotal = MakeStatTile(detail, tileW, "TOTAL MONEY", C.white)
	frame.statTotal:SetPoint("LEFT", frame.statAvg, "RIGHT", gap, 0)
	frame.statPos = MakeStatTile(detail, tileW, "LAST KILL", C.teal)
	frame.statPos:SetPoint("LEFT", frame.statTotal, "RIGHT", gap, 0)
	frame.statPos:SetPoint("RIGHT", -12, 0)

	frame.lootTitle = MakeFont(detail, "GameFontNormal", 13)
	frame.lootTitle:SetPoint("TOPLEFT", frame.statLoots, "BOTTOMLEFT", 2, -14)
	frame.lootTitle:SetText("Loot")
	Tint(frame.lootTitle, C.gold)

	frame.lootCount = MakeFont(detail, "GameFontHighlightSmall", 10)
	frame.lootCount:SetPoint("LEFT", frame.lootTitle, "RIGHT", 8, 0)
	Tint(frame.lootCount, C.muted)

	local lootRule = MakeRule(detail, C.rule)
	lootRule:SetPoint("TOPLEFT", frame.lootTitle, "BOTTOMLEFT", -2, -5)
	lootRule:SetPoint("RIGHT", -12, 0)

	-- DROPS = loot windows that included the item. RATE = drops / loots.
	-- SELL is the rightmost column, same anchors as the item rows.
	local colHeader = CreateFrame("Frame", nil, detail)
	colHeader:SetHeight(16)
	colHeader:SetPoint("TOPLEFT", lootRule, "BOTTOMLEFT", 0, -4)
	colHeader:SetPoint("RIGHT", -12, 0)
	local sellHeader = MakeColumnHeader(colHeader, "SELL", COL_SELL_W, "RIGHT")
	sellHeader:SetPoint("RIGHT", -6, 0)
	local rateHeader = MakeColumnHeader(colHeader, "RATE", COL_RATE_W, "RIGHT")
	rateHeader:SetPoint("RIGHT", sellHeader, "LEFT", -COL_GAP, 0)
	local dropsHeader = MakeColumnHeader(colHeader, "DROPS", COL_DROPS_W, "RIGHT")
	dropsHeader:SetPoint("RIGHT", rateHeader, "LEFT", -COL_GAP, 0)
	local itemHeader = MakeColumnHeader(colHeader, "ITEM", 80, "LEFT")
	itemHeader:SetPoint("LEFT", ICON_SIZE + 14, 0)

	frame.itemScroll = CreateFrame("ScrollFrame", "MobLedgerItemScroll", detail)
	frame.itemScroll:SetPoint("TOPLEFT", colHeader, "BOTTOMLEFT", 0, -2)
	frame.itemScroll:SetPoint("BOTTOMRIGHT", -12, 8)

	frame.itemChild = CreateFrame("Frame", nil, frame.itemScroll)
	frame.itemChild:SetWidth(DETAIL_WIDTH - 24)
	frame.itemChild:SetHeight(VISIBLE_ITEM_ROWS * ITEM_ROW_HEIGHT)
	frame.itemScroll:SetScrollChild(frame.itemChild)

	frame.itemScroll:EnableMouseWheel(true)
	frame.itemScroll:SetScript("OnMouseWheel", function(_, delta)
		if not selectedMob then
			return
		end
		local items = BuildSortedItems(MobLedger_GetMob(selectedMob))
		local maxOffset = math.max(0, #items - VISIBLE_ITEM_ROWS)
		itemOffset = math.min(maxOffset, math.max(0, itemOffset - delta))
		frame:Refresh()
	end)

	for i = 1, VISIBLE_ITEM_ROWS do
		itemButtons[i] = CreateItemButton(frame.itemChild, i)
	end

	frame.empty = MakeFont(detail, "GameFontHighlightSmall", 11)
	frame.empty:SetPoint("TOP", frame.itemScroll, "TOP", 0, -24)
	frame.empty:SetText("No item drops recorded for this mob.")
	Tint(frame.empty, C.muted)
	frame.empty:Hide()

	local activePortraitSrc

	local function DetachCachedPortrait()
		if activePortraitSrc then
			local holder = activePortraitSrc.holder
			if holder then
				activePortraitSrc:SetParent(holder)
				activePortraitSrc:ClearAllPoints()
				activePortraitSrc:SetAllPoints(holder)
			else
				activePortraitSrc:SetParent(UIParent)
				activePortraitSrc:ClearAllPoints()
			end
			activePortraitSrc:Hide()
			activePortraitSrc = nil
		end
	end
	frame.DetachPortraits = DetachCachedPortrait

	local function AttachCachedPortrait(tex)
		tex:SetParent(frame.portraitShell)
		tex:ClearAllPoints()
		tex:SetPoint("TOPLEFT", 5, -5)
		tex:SetPoint("BOTTOMRIGHT", -5, 5)
		tex:Show()
		activePortraitSrc = tex
	end

	local function ShowMobPortrait(mob, name)
		DetachCachedPortrait()
		frame.portraitModel:Hide()
		frame.portraitTex:Hide()
		frame.portraitEmpty:Hide()

		name = name or selectedMob

		local function PresentModel()
			local model = frame.portraitModel
			local displayId = mob and mob.displayId
			local npcId = mob and mob.npcId
			local shown = false
			if model.ClearModel then
				model:ClearModel()
			end
			if displayId and model.SetDisplayInfo then
				model:SetDisplayInfo(displayId)
				shown = true
			elseif npcId and model.SetCreature then
				model:SetCreature(npcId)
				shown = true
			end
			if not shown then
				return false
			end
			if model.SetCamera then
				model:SetCamera(0)
			end
			model.mobName = name
			model.facing = portraitFacing[name] or 0
			model.applyFacing = true
			model.rotating = false
			model:Show()
			return true
		end

		-- 3D model first so the portrait can be turned.
		if PresentModel() then
			return
		end

		-- Flat snapshot when the client cannot rebuild the creature.
		local cached = MobLedger_GetCapturedPortraitTexture and MobLedger_GetCapturedPortraitTexture(name)
		if cached then
			AttachCachedPortrait(cached)
			return
		end

		if name and UnitExists("target") and UnitName("target") == name then
			if MobLedger_CaptureUnitPortrait then
				MobLedger_CaptureUnitPortrait(name, "target")
			end
			local again = MobLedger_GetCapturedPortraitTexture and MobLedger_GetCapturedPortraitTexture(name)
			if again then
				AttachCachedPortrait(again)
				return
			end
			if SetPortraitTexture then
				SetPortraitTexture(frame.portraitTex, "target")
				frame.portraitTex:Show()
				return
			end
		end

		frame.portraitEmpty:Show()
	end

	local function RefreshSummary()
		local mobs = MobLedger_GetTotals()
		local zones = #MobLedger_GetLocationNames()
		frame.summaryLeft:SetText(string.format("%d mobs  ·  %d zones", mobs, zones))
	end

	function frame:Refresh()
		RefreshSummary()

		renderRows = BuildRenderRows()
		local maxListOffset = math.max(0, #renderRows - VISIBLE_LIST_ROWS)
		listOffset = math.min(listOffset, maxListOffset)

		if selectedMob and not MobLedger_GetMob(selectedMob) then
			selectedMob = nil
		end

		for i = 1, VISIBLE_LIST_ROWS do
			local btn = listButtons[i]
			local row = renderRows[listOffset + i]
			btn.row = row
			if row then
				ConfigureListRow(btn, row)
				btn:Show()
			else
				btn:Hide()
			end
		end
		frame.listEmpty:SetShown(#MobLedger_GetLocationNames() == 0)

		if not selectedMob then
			detail:Hide()
			DetachCachedPortrait()
			frame.portraitModel:Hide()
			frame.placeholder:Show()
			frame.placeholderSub:Show()
			return
		end

		frame.placeholder:Hide()
		frame.placeholderSub:Hide()
		detail:Show()

		local mob = MobLedger_GetMob(selectedMob)
		local loots = mob and mob.loots or 0
		local kills = MobLedger_GetKills(mob)
		local lastKill = kills[#kills]
		local loc = MobLedger_GetMobLocation(mob)
		local area = lastKill and MobLedger_GetKillArea(lastKill) or MobLedger_GetMobArea(mob, loc)

		frame.detailHeader:SetText(selectedMob)
		ShowMobPortrait(mob, selectedMob)

		local place = loc or "Unknown"
		if area and area ~= "" then
			place = place .. "  ·  " .. area
		end
		frame.locationText:SetText(place)
		frame.hiddenTag:SetShown(MobLedger_IsMobHidden(selectedMob))

		frame.statLoots.value:SetText(tostring(loots))
		frame.statAvg.value:SetText(FormatCoins(MobLedger_GetAverageCopper(mob)))
		frame.statTotal.value:SetText(FormatCoins(mob and mob.copperTotal or 0))
		frame.statPos.value:SetText(MobLedger_FormatCoords(lastKill))

		local scrollW = frame.itemScroll:GetWidth()
		if scrollW and scrollW > 40 then
			frame.itemChild:SetWidth(scrollW)
		end

		local items = BuildSortedItems(mob)
		local maxItemOffset = math.max(0, #items - VISIBLE_ITEM_ROWS)
		itemOffset = math.min(itemOffset, maxItemOffset)

		frame.lootCount:SetText(#items == 1 and "1 item" or (#items .. " items"))
		frame.empty:SetShown(#items == 0)

		for i = 1, VISIBLE_ITEM_ROWS do
			local btn = itemButtons[i]
			local row = items[itemOffset + i]
			if row then
				btn:Show()
				btn.itemLink = row.link
				local r, g, b = QualityColor(row.quality)
				btn.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
				SetSolidColor(btn.iconEdge, r, g, b, 0.9)
				local label = row.name or ""
				if row.quantity and row.quantity > row.drops then
					label = string.format("%s  ×%d", label, row.quantity)
				end
				btn.name:SetText(label)
				btn.name:SetTextColor(r, g, b)
				btn.drops:SetText(tostring(row.drops))
				btn.rate:SetText(string.format("%.1f%%", row.rate))
				if row.sellPrice and row.sellPrice > 0 then
					btn.sell:SetText(FormatCoins(row.sellPrice))
				else
					btn.sell:SetText("—")
				end
			else
				btn:Hide()
				btn.itemLink = nil
			end
		end
	end

	-- The dialog border draws inside the frame, so the button's bottom clears that
	-- border by DEV_GAP. The same gap sits above the button. Its left edge meets
	-- the list panel's visible border. Dev off drops the strip and uses PAD again.
	local function ApplyDevChrome()
		local on = WoWF.DevMode and true or false
		local chrome = STYLE_WINDOW.inset
		local foot = on and (chrome + DEV_GAP + DEV_BTN_H + DEV_GAP) or PAD
		left:ClearAllPoints()
		left:SetPoint("TOPLEFT", PAD, -TOP)
		left:SetPoint("BOTTOMLEFT", PAD, foot)
		left:SetWidth(LIST_WIDTH + 18)
		right:ClearAllPoints()
		right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
		right:SetPoint("BOTTOMRIGHT", -PAD, foot)
		if on then
			if not frame.devReset then
				frame.devReset = MakeDevButton(frame, "Reset ledger", function()
					MobLedger_ResetAll()
					selectedMob = nil
					listOffset = 0
					itemOffset = 0
					frame:Refresh()
				end)
			end
			frame.devReset:ClearAllPoints()
			frame.devReset:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD + DEV_ALIGN, chrome + DEV_GAP)
			frame.devReset:Show()
		elseif frame.devReset then
			frame.devReset:Hide()
		end
	end
	frame.ApplyDevChrome = ApplyDevChrome
	ApplyDevChrome()

	return frame
end

function MobLedgerJournal_Show()
	if not journal then
		journal = CreateJournal()
	end
	journal:Show()
	journal:Refresh()
end

function MobLedgerJournal_Hide()
	HideContextMenu()
	if journal then
		journal:Hide()
	end
end

function MobLedgerJournal_Toggle()
	if journal and journal:IsShown() then
		MobLedgerJournal_Hide()
	else
		MobLedgerJournal_Show()
	end
end

function MobLedgerJournal_Refresh()
	if journal and journal:IsShown() then
		journal:Refresh()
	end
end

if WoWF.OnDevModeChanged then
	WoWF.OnDevModeChanged(function()
		if journal and journal.ApplyDevChrome then
			journal:ApplyDevChrome()
		end
	end)
end
