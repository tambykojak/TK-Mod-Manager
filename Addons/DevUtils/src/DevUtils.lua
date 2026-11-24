local ADDON_NAME, Addon = ...

local log = WoWF.Logger:New(ADDON_NAME, {
	minLevel = WoWF.DevMode and "DEBUG" or "INFO",
})

WoWF.OnDevModeChanged(function(enabled)
	log:SetLevel(enabled and "DEBUG" or "INFO")
end)

Addon.log = log

--- Solid-color fill that works on Classic-style clients without SetColorTexture.
function Addon.SetSolidColor(texture, r, g, b, a)
	a = a or 1
	if texture.SetColorTexture then
		texture:SetColorTexture(r, g, b, a)
		return
	end
	texture:SetTexture("Interface\\Buttons\\WHITE8X8")
	texture:SetVertexColor(r, g, b, a)
end

function Addon.EnsureDB()
	if type(DevUtilsDB) ~= "table" then
		DevUtilsDB = {}
	end
	local db = DevUtilsDB
	local prev = db.version or 0
	db.version = math.max(prev, 2)

	-- Shared explorer selection (hub for Compose tools).
	db.explorer = db.explorer or {}
	local e = db.explorer
	if prev < 2 and db.panel and db.panel.selectedPath and not e.selectedPath then
		e.selectedPath = db.panel.selectedPath
		e.category = db.panel.category
	end
	e.category = e.category or "All"
	e.search = e.search or ""
	e.selectedPath = e.selectedPath or "Interface\\DialogFrame\\UI-DialogBox-Background"
	e.previewBg = e.previewBg or "dark" -- dark | light | checker
	e.vertexColor = e.vertexColor or { r = 1, g = 1, b = 1, a = 1 }
	-- Migrate old square previewSize → independent W/H.
	local legacySize = e.previewSize or 256
	e.previewWidth = e.previewWidth or legacySize
	e.previewHeight = e.previewHeight or legacySize

	db.panel = db.panel or {}
	local p = db.panel
	p.bgPath = p.bgPath or "Interface\\DialogFrame\\UI-DialogBox-Background"
	p.edgePath = p.edgePath or "Interface\\DialogFrame\\UI-DialogBox-Border"
	p.tile = p.tile ~= false
	p.tileSize = p.tileSize or 32
	p.edgeSize = p.edgeSize or 32
	p.inset = p.inset or 8
	p.bgColor = p.bgColor or { r = 0, g = 0, b = 0, a = 0.9 }
	p.edgeColor = p.edgeColor or { r = 1, g = 1, b = 1, a = 1 }
	-- Repair border alpha wiped by the old inverted opacity picker bug.
	if not p.edgeColor.a or p.edgeColor.a <= 0 then
		p.edgeColor.a = 1
	end
	if not p.bgColor.a or p.bgColor.a < 0 then
		p.bgColor.a = 0.9
	end
	p.titleFont = p.titleFont or "GameFontNormalLarge"
	p.bodyFont = p.bodyFont or "GameFontHighlight"
	p.titleColor = p.titleColor or { r = 1, g = 0.82, b = 0 }
	p.bodyColor = p.bodyColor or { r = 1, g = 1, b = 1 }

	db.button = db.button or {}
	local b = db.button
	b.style = b.style or "UIPanelButtonTemplate"
	b.labelPreset = b.labelPreset or b.text or "Sample Button"
	b.customText = b.customText or "Custom"
	-- Migrate old free-text `text` into preset/custom if needed.
	if b.labelPreset ~= "custom" then
		local known = false
		-- Catalog may load after this file; fall back to common presets.
		local presets = Addon.BUTTON_LABELS
		if presets then
			for _, item in ipairs(presets) do
				if item.value == b.labelPreset then
					known = true
					break
				end
			end
		else
			known = true
		end
		if not known then
			b.customText = b.labelPreset
			b.labelPreset = "custom"
		end
	end
	b.width = b.width or 120
	b.height = b.height or 22
	b.font = b.font or "GameFontNormal"
	b.textColor = b.textColor or { r = 1, g = 0.82, b = 0 }
	b.normalTex = b.normalTex or "Interface\\Buttons\\UI-Panel-Button-Up"
	b.pushedTex = b.pushedTex or "Interface\\Buttons\\UI-Panel-Button-Down"
	b.disabledTex = b.disabledTex or "Interface\\Buttons\\UI-Panel-Button-Disabled"
	b.highlightTex = b.highlightTex or "Interface\\Buttons\\UI-Panel-Button-Highlight"
	b.bgColor = b.bgColor or { r = 0.15, g = 0.15, b = 0.18, a = 1 }
	b.borderColor = b.borderColor or { r = 0.45, g = 0.45, b = 0.5, a = 1 }

	-- Top-level: 1 Explore, 2 Compose. Compose tool: 1 Panel, 2 Button.
	db.lastTab = db.lastTab or 1
	db.composeTool = db.composeTool or 1
	return db
end

function Addon.GetSelectedPath()
	return Addon.EnsureDB().explorer.selectedPath
end

function Addon.SetSelectedPath(path)
	if not path or path == "" then
		return
	end
	Addon.EnsureDB().explorer.selectedPath = path
	if Addon.OnSelectionChanged then
		Addon.OnSelectionChanged(path)
	end
end

function Addon.OpenColorPicker(color, onChanged)
	color = color or { r = 1, g = 1, b = 1 }
	local r, g, b = color.r or 1, color.g or 1, color.b or 1
	-- Only treat as opacity-enabled when alpha is explicitly provided.
	local hasOpacity = color.a ~= nil
	local a = hasOpacity and (color.a or 1) or 1
	if a < 0 then a = 0 end
	if a > 1 then a = 1 end

	local function readRGB()
		if ColorPickerFrame.GetColorRGB then
			return ColorPickerFrame:GetColorRGB()
		end
		return r, g, b
	end

	--- Forever / modern: GetColorAlpha is real alpha (1 = opaque).
	--- Classic OpacitySliderFrame: value is inverted (1 = transparent).
	local function readAlpha()
		if not hasOpacity then
			return 1
		end
		local na
		if ColorPickerFrame.GetColorAlpha then
			na = ColorPickerFrame:GetColorAlpha()
		elseif OpacitySliderFrame and OpacitySliderFrame.GetValue then
			na = 1 - (OpacitySliderFrame:GetValue() or 0)
		else
			na = a
		end
		na = tonumber(na) or 1
		if na < 0 then na = 0 end
		if na > 1 then na = 1 end
		return na
	end

	local function apply()
		local nr, ng, nb = readRGB()
		onChanged(nr, ng, nb, readAlpha())
	end

	local function onCancel()
		onChanged(r, g, b, a)
	end

	if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
		-- Modern API: opacity is alpha (1 = opaque), not classic inverted.
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r,
			g = g,
			b = b,
			opacity = hasOpacity and a or nil,
			hasOpacity = hasOpacity,
			swatchFunc = apply,
			opacityFunc = hasOpacity and apply or nil,
			cancelFunc = onCancel,
		})
		return
	end

	ColorPickerFrame.func = apply
	ColorPickerFrame.cancelFunc = onCancel
	ColorPickerFrame.hasOpacity = hasOpacity
	if hasOpacity then
		ColorPickerFrame.opacityFunc = apply
		-- Classic ColorPickerFrame.opacity is inverted (0 = opaque).
		ColorPickerFrame.opacity = 1 - a
	else
		ColorPickerFrame.opacityFunc = nil
	end
	ColorPickerFrame:SetColorRGB(r, g, b)
	if ShowUIPanel then
		ShowUIPanel(ColorPickerFrame)
	else
		ColorPickerFrame:Show()
	end
end

local function PrintHelp()
	print("|cff33ccff[DevUtils]|r /du — open DevUtils")
	print("|cff33ccff[DevUtils]|r /du explore — texture viewer")
	print("|cff33ccff[DevUtils]|r /du compose — composition tools")
	print("|cff33ccff[DevUtils]|r /du panel — Compose → Panel")
	print("|cff33ccff[DevUtils]|r /du button — Compose → Button")
	print("|cff33ccff[DevUtils]|r /du help — this help")
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

	if cmd == "help" or cmd == "?" then
		PrintHelp()
		return
	end

	if cmd == "explore" or cmd == "textures" or cmd == "viewer" then
		Addon.ShowPanel(1)
		return
	end

	if cmd == "compose" then
		Addon.ShowPanel(2)
		return
	end

	if cmd == "panel" or cmd == "panels" or cmd == "styles" then
		Addon.EnsureDB().composeTool = 1
		Addon.ShowPanel(2)
		return
	end

	if cmd == "button" or cmd == "buttons" or cmd == "btn" then
		Addon.EnsureDB().composeTool = 2
		Addon.ShowPanel(2)
		return
	end

	Addon.TogglePanel()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		Addon.EnsureDB()
		return
	end

	if event == "PLAYER_LOGIN" then
		log:Info("ready — /du · Explore textures, Compose panels/buttons")
	end
end)

SLASH_DEVUTILS1 = "/devutils"
SLASH_DEVUTILS2 = "/du"
SlashCmdList["DEVUTILS"] = OnSlash
