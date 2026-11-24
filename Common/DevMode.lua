--- Development mode flag for WoW Forever addons.
--- Workspace source / install / in-game via install|dev: DevMode = true
--- Production package via wowf-addons-build: forced to false
---
--- Every addon loads its own copy of this file, but the flag and the listener
--- list live on the global WoWF table, so one toggle reaches every addon.
---
--- Usage:
---   if WoWF.DevMode then
---     -- extra logging, experimental behavior, etc.
---   end
---   WoWF.OnDevModeChanged(function(enabled)
---     -- update this addon's logger, frames, dev-only controls
---   end)
---   -- From Main.lua:
---   local VERSION = "0.1.0"
---   WoWF.PrintLoadBanner(ADDON_NAME, VERSION)

WoWF = WoWF or {}

-- The first addon to load sets the packaged default; later copies must not
-- reset a value the player already toggled this session.
if WoWF.DevMode == nil then
	WoWF.DevMode = true
end

WoWF._devModeListeners = WoWF._devModeListeners or {}
local devModeListeners = WoWF._devModeListeners

--- Run fn(enabled) whenever development mode changes this session.
function WoWF.OnDevModeChanged(fn)
	if type(fn) == "function" then
		devModeListeners[#devModeListeners + 1] = fn
	end
end

--- Session toggle for every addon. arg is "on", "off", or omitted to flip.
--- Reload restores the packaged flag. Reply is magenta.
function WoWF.ToggleDevMode(addonName, arg)
	arg = type(arg) == "string" and string.lower(arg) or ""
	local want
	if arg == "on" then
		want = true
	elseif arg == "off" then
		want = false
	else
		want = not WoWF.DevMode
	end
	WoWF.DevMode = want and true or false
	print(string.format(
		"|cffff00ff[%s]|r Development mode %s for all addons.",
		addonName or "Addon",
		WoWF.DevMode and "on" or "off"
	))
	for i = 1, #devModeListeners do
		local ok, err = pcall(devModeListeners[i], WoWF.DevMode)
		if not ok then
			geterrorhandler()(err)
		end
	end
	return WoWF.DevMode
end

SLASH_WOWFTK1 = "/tk"
SlashCmdList["WOWFTK"] = function(msg)
	msg = (msg and string.lower(msg):match("^%s*(.-)%s*$")) or ""
	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	if cmd == "dev" then
		WoWF.ToggleDevMode("WoW Forever", rest)
		return
	end
	print("|cffff00ff[WoW Forever]|r /tk dev [on|off] — development mode for all addons.")
end

local function GetAddonVersion(addonName)
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		return C_AddOns.GetAddOnMetadata(addonName, "Version")
	end
	if GetAddOnMetadata then
		return GetAddOnMetadata(addonName, "Version")
	end
	return nil
end

--- Print the standard addon load banner.
--- @param addonName string
--- @param version string|nil  defaults to TOC ## Version
function WoWF.PrintLoadBanner(addonName, version)
	addonName = addonName or "Addon"
	version = version or GetAddonVersion(addonName) or "?"
	local mode = WoWF.DevMode and "on" or "off"
	print(string.format(
		"%s Loaded. Version %s. Development mode %s.",
		addonName,
		version,
		mode
	))
end
