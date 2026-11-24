--- Window chrome: outer frame border, header bar, and bordered header buttons.
--- Packaging copies this file to Common/UI/Window.lua beside the addon's src/.
--- Load after Common\UI\Core.lua.
---
--- Palette keys are documented in UI/CommonCore.lua.
---
---   local frame = CreateFrame("Frame", "MyFrame", UIParent)
---   WoWF.UI.CreateFrameBorders(frame, C)
---   local header = WoWF.UI.CreateHeader(frame, C, 60)
---   frame.close = WoWF.UI.CreateHeaderButton(header, C, {
---     cross = true,
---     onClick = function() frame:Hide() end,
---   })
---   frame.close:SetPoint("RIGHT", -14, 0)

WoWF = WoWF or {}
WoWF.UI = WoWF.UI or {}

local UI = WoWF.UI

--- Paints the 2px outer border (p.accentDim) and the window fill (p.bg) inside it.
--- Returns outer, inner textures.
function UI.CreateFrameBorders(frame, p, inset)
	inset = inset or 2
	local outer = frame:CreateTexture(nil, "BACKGROUND")
	outer:SetDrawLayer("BACKGROUND", -8)
	outer:SetAllPoints()
	UI.Paint(outer, p.accentDim)
	local inner = frame:CreateTexture(nil, "BACKGROUND")
	inner:SetDrawLayer("BACKGROUND", -7)
	inner:SetPoint("TOPLEFT", inset, -inset)
	inner:SetPoint("BOTTOMRIGHT", -inset, inset)
	UI.Paint(inner, p.bg)
	return outer, inner
end

--- A header bar inset from the frame's top, left, and right edges.
--- Filled with p.void and ruled along the bottom in a 2px p.accent line.
--- Returns the header frame with .fill and .rule textures.
function UI.CreateHeader(frame, p, height, inset)
	inset = inset or 2
	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", inset, -inset)
	header:SetPoint("TOPRIGHT", -inset, -inset)
	header:SetHeight(height or 60)
	header.fill = header:CreateTexture(nil, "BACKGROUND")
	header.fill:SetAllPoints()
	UI.Paint(header.fill, p.void)
	header.rule = header:CreateTexture(nil, "ARTWORK")
	header.rule:SetHeight(2)
	header.rule:SetPoint("BOTTOMLEFT", 0, 0)
	header.rule:SetPoint("BOTTOMRIGHT", 0, 0)
	UI.Paint(header.rule, p.accent)
	return header
end

--- A 1px bordered square button. Used for close, settings, and dev buttons.
---
--- opts (all optional):
---   size        number   default 26
---   edge        color    default p.edge
---   fill        color    default p.panelHi
---   hoverEdge   color    default p.accent
---   hoverFill   color    default p.select
---   icon        texture  path; drawn inset 4px
---   cross       bool     draw an X via UI.MakeCenteredCross
---   glyph       color    cross color, default p.muted
---   hoverGlyph  color    cross color on hover, default p.bone
---   onClick     function
---
--- Returns the button. Hover swaps edge, fill, and cross color together.
function UI.CreateHeaderButton(parent, p, opts)
	opts = opts or {}
	local size = opts.size or 26
	local edgeColor = opts.edge or p.edge
	local fillColor = opts.fill or p.panelHi
	local hoverEdge = opts.hoverEdge or p.accent
	local hoverFill = opts.hoverFill or p.select

	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(size, size)
	btn:RegisterForClicks("LeftButtonUp")

	btn.edgeTex = btn:CreateTexture(nil, "BACKGROUND")
	btn.edgeTex:SetAllPoints()
	UI.Paint(btn.edgeTex, edgeColor)
	btn.fillTex = btn:CreateTexture(nil, "BACKGROUND")
	btn.fillTex:SetDrawLayer("BACKGROUND", 1)
	btn.fillTex:SetPoint("TOPLEFT", 1, -1)
	btn.fillTex:SetPoint("BOTTOMRIGHT", -1, 1)
	UI.Paint(btn.fillTex, fillColor)

	if opts.icon then
		btn.icon = btn:CreateTexture(nil, "ARTWORK")
		btn.icon:SetPoint("TOPLEFT", 4, -4)
		btn.icon:SetPoint("BOTTOMRIGHT", -4, 4)
		btn.icon:SetTexture(opts.icon)
		btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end

	local glyph = opts.glyph or p.muted
	local hoverGlyph = opts.hoverGlyph or p.bone
	if opts.cross then
		UI.MakeCenteredCross(btn, glyph, 11, 1.5)
	end

	btn:SetScript("OnEnter", function(self)
		UI.Paint(self.edgeTex, hoverEdge)
		UI.Paint(self.fillTex, hoverFill)
		if self.SetGlyphColor then
			self:SetGlyphColor(hoverGlyph)
		end
	end)
	btn:SetScript("OnLeave", function(self)
		UI.Paint(self.edgeTex, edgeColor)
		UI.Paint(self.fillTex, fillColor)
		if self.SetGlyphColor then
			self:SetGlyphColor(glyph)
		end
	end)
	if opts.onClick then
		btn:SetScript("OnClick", opts.onClick)
	end

	return btn
end
