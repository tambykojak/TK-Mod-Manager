--- Shared chat logger for WoW Forever addons.
--- Packaging copies this file to Common/Logger.lua beside the addon's src/.
--- List that path in the TOC before addon scripts, e.g.:
---   Common\Logger.lua
---   src\Main.lua
---
--- Usage:
---   local log = WoWF.Logger:New("JunkMaster")
---   log:Info("ready")
---   log:Debug("hidden unless level is DEBUG")
---   log:SetLevel("DEBUG")

WoWF = WoWF or {}

local LEVEL = {
	DEBUG = 1,
	INFO = 2,
	WARN = 3,
	ERROR = 4,
}

local LEVEL_COLOR = {
	DEBUG = "FF9D9D9D",
	INFO = "FFFFFFFF",
	WARN = "FFFFD100",
	ERROR = "FFFF2020",
}

--- [LEVEL] [TIME] [ADDON] message
local LOG_FORMAT = "[%s] [%s] [%s] %s"
local TIMESTAMP_FORMAT = "%H:%M:%S"

local function ResolveLevel(level)
	if type(level) == "string" then
		return LEVEL[string.upper(level)]
	end
	return level
end

local function JoinMessages(...)
	local count = select("#", ...)
	if count == 0 then
		return ""
	end
	if count == 1 then
		return tostring(...)
	end
	local parts = {}
	for i = 1, count do
		parts[i] = tostring(select(i, ...))
	end
	return table.concat(parts, " ")
end

local Logger = {}
Logger.__index = Logger
Logger.LEVEL = LEVEL

--- Create a logger bound to an addon display name.
--- @param addonName string
--- @param options table|nil { minLevel = "INFO"|number }
function Logger:New(addonName, options)
	options = options or {}
	return setmetatable({
		name = addonName or "Addon",
		minLevel = ResolveLevel(options.minLevel) or LEVEL.INFO,
	}, self)
end

function Logger:SetLevel(level)
	local resolved = ResolveLevel(level)
	if resolved then
		self.minLevel = resolved
	end
end

function Logger:GetLevel()
	return self.minLevel
end

function Logger:_Emit(levelName, ...)
	local level = LEVEL[levelName]
	if not level or level < self.minLevel then
		return
	end

	local line = string.format(
		LOG_FORMAT,
		levelName,
		date(TIMESTAMP_FORMAT),
		self.name,
		JoinMessages(...)
	)
	print(string.format("|c%s%s|r", LEVEL_COLOR[levelName], line))
end

function Logger:Debug(...)
	self:_Emit("DEBUG", ...)
end

function Logger:Info(...)
	self:_Emit("INFO", ...)
end

function Logger:Warn(...)
	self:_Emit("WARN", ...)
end

function Logger:Error(...)
	self:_Emit("ERROR", ...)
end

WoWF.Logger = Logger
