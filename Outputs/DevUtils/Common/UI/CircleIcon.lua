--- Circular icon for WoW Forever addons.
--- Packaging copies this file to Common/UI/CircleIcon.lua beside the addon's src/.
--- List Common\UI\CircleIcon.lua in the TOC after the other Common files.
---
---   local badge = WoWF.CreateCircleIcon(parent, 40, "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", { 0.8, 0.12, 0.16 })
---   badge:SetPoint("LEFT", 16, 0)
---   badge:SetIcon("Interface\\Icons\\INV_Misc_Wrench_01")
---   badge:SetRingColor(0.85, 0.08, 0.72)
---
--- The ring art in MiniMap-TrackingBorder sits in the top-left of the file, not
--- the middle. Centering that texture puts the ring off the icon. These sizes
--- are Blizzard's minimap tracking button (a 32px button, an 18px portrait, a
--- 54px border hung from the top-left). Every badge scales that same button,
--- so 24px and 64px land the same way.
--- SetPortraitToTexture is what makes the icon a circle. A square texture
--- always leaves corners outside the ring.

WoWF = WoWF or {}

local REF = 32
local PORTRAIT = 18
local DISC = 22
local BORDER = 54

local function ApplyRingColor(badge, r, g, b, a)
	a = a or 1
	if badge.disc then
		badge.disc:SetVertexColor(r, g, b, a)
	end
	if badge.border then
		badge.border:SetVertexColor(r, g, b, a)
	end
end

function WoWF.CreateCircleIcon(parent, size, texturePath, ringColor)
	size = size or REF
	local scale = size / REF

	local badge = CreateFrame("Frame", nil, parent)
	badge:SetSize(size, size)

	local disc = badge:CreateTexture(nil, "BACKGROUND")
	disc:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	disc:SetSize(DISC * scale, DISC * scale)
	disc:SetPoint("CENTER", badge, "CENTER", 0, 0)
	badge.disc = disc

	local icon = badge:CreateTexture(nil, "ARTWORK")
	icon:SetSize(PORTRAIT * scale, PORTRAIT * scale)
	icon:SetPoint("CENTER", badge, "CENTER", 0, 0)
	badge.icon = icon

	local border = badge:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(BORDER * scale, BORDER * scale)
	border:SetPoint("TOPLEFT", badge, "TOPLEFT", 0, 0)
	badge.border = border

	function badge:SetIcon(path)
		if not path or path == "" then
			self.icon:SetTexture(nil)
			return
		end
		if SetPortraitToTexture then
			SetPortraitToTexture(self.icon, path)
		else
			self.icon:SetTexture(path)
			self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
	end

	function badge:SetRingColor(r, g, b, a)
		ApplyRingColor(self, r, g, b, a)
	end

	if ringColor then
		ApplyRingColor(badge, ringColor[1], ringColor[2], ringColor[3], ringColor[4])
	end
	if texturePath then
		badge:SetIcon(texturePath)
	end

	return badge
end
