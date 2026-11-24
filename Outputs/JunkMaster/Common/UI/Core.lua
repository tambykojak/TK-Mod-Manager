--- Shared UI primitives for WoW Forever windows.
--- Packaging copies this file to Common/UI/Core.lua beside the addon's src/.
--- List Common\UI\Core.lua in the TOC after Common\DevMode.lua and Common\Logger.lua.
---
--- Every painting function takes a palette `p`: a table of RGBA arrays with
--- these keys. Build one per addon window and pass it in.
---
---   void, bg, panel, panelHi, edge, accent, accentDim, bone, muted, select
---
---   local C = { ... }
---   C.accent = C.blood
---   C.accentDim = C.bloodDim
---   local panel = WoWF.UI.MakePanel(frame, C)

WoWF = WoWF or {}
WoWF.UI = WoWF.UI or {}

local UI = WoWF.UI

function UI.SetSolidColor(texture, r, g, b, a)
	a = a or 1
	if texture.SetColorTexture then
		texture:SetColorTexture(r, g, b, a)
		return
	end
	texture:SetTexture("Interface\\Buttons\\WHITE8X8")
	texture:SetVertexColor(r, g, b, a)
end

--- color is an RGBA array, e.g. p.panel.
function UI.Paint(tex, color, alpha)
	UI.SetSolidColor(tex, color[1], color[2], color[3], alpha or color[4] or 1)
end

function UI.Tint(fs, color)
	fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

function UI.MakeFont(parent, template, size)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
	if size and fs.SetFont then
		local font, _, flags = fs:GetFont()
		if font then
			fs:SetFont(font, size, flags or "")
		end
	end
	return fs
end

--- A 1px horizontal rule. color is required.
function UI.MakeRule(parent, color)
	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	UI.Paint(rule, color)
	return rule
end

--- A 1px edge, a panel fill inset 1px, and a dim accent lip across the top.
--- Returns the shell frame with .edge, .fill, and .lip textures.
function UI.MakePanel(parent, p)
	local shell = CreateFrame("Frame", nil, parent)
	shell.edge = shell:CreateTexture(nil, "BACKGROUND")
	shell.edge:SetAllPoints()
	UI.Paint(shell.edge, p.edge)
	shell.fill = shell:CreateTexture(nil, "BACKGROUND")
	shell.fill:SetDrawLayer("BACKGROUND", 1)
	shell.fill:SetPoint("TOPLEFT", 1, -1)
	shell.fill:SetPoint("BOTTOMRIGHT", -1, 1)
	UI.Paint(shell.fill, p.panel)
	shell.lip = shell:CreateTexture(nil, "ARTWORK")
	shell.lip:SetHeight(1)
	shell.lip:SetPoint("TOPLEFT", 1, -1)
	shell.lip:SetPoint("TOPRIGHT", -1, -1)
	UI.Paint(shell.lip, p.accentDim)
	return shell
end

--- Two rotated bars, so the mark is the geometric center of the button.
--- A font "×" sits high in its line box and looks off center.
--- Adds btn:SetGlyphColor(color). color is required.
--- Falls back to a font "×" on clients without SetRotation.
function UI.MakeCenteredCross(btn, color, length, thickness)
	length = length or 11
	thickness = thickness or 1.5
	local probe = btn:CreateTexture(nil, "OVERLAY")
	if probe.SetRotation then
		probe:SetSize(length, thickness)
		probe:SetPoint("CENTER", btn, "CENTER", 0, 0)
		probe:SetRotation(math.rad(45))
		UI.Paint(probe, color)
		local other = btn:CreateTexture(nil, "OVERLAY")
		other:SetSize(length, thickness)
		other:SetPoint("CENTER", btn, "CENTER", 0, 0)
		other:SetRotation(math.rad(-45))
		UI.Paint(other, color)
		function btn:SetGlyphColor(c)
			UI.Paint(probe, c)
			UI.Paint(other, c)
		end
		return
	end
	probe:Hide()
	btn.label = UI.MakeFont(btn, "GameFontHighlight", 16)
	btn.label:SetPoint("CENTER", btn, "CENTER", 0, -1)
	btn.label:SetJustifyH("CENTER")
	btn.label:SetJustifyV("MIDDLE")
	btn.label:SetText("×")
	UI.Tint(btn.label, color)
	function btn:SetGlyphColor(c)
		UI.Tint(self.label, c)
	end
end
