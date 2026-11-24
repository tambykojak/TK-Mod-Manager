local ADDON_NAME, Addon = ...

local log = WoWF.Logger:New(ADDON_NAME, {
	minLevel = WoWF.DevMode and "DEBUG" or "INFO",
})

--- Avoid double-counting the same kill in a short window.
local recentKillAt = {}
local recentDeathAt = {}
local KILL_DEDUP_SECONDS = 8

local function EnsureDB()
	if type(DeathNoteDB) ~= "table" then
		DeathNoteDB = {}
	end
	if type(DeathNoteDB.entries) ~= "table" then
		DeathNoteDB.entries = {}
	end
	DeathNoteDB.version = DeathNoteDB.version or 1
	return DeathNoteDB
end

--- Full name is the identity. Forever's second UnitName value is a surname,
--- and the same person shows up as "First Surname" or "First-Surname".
local function NormalizeName(name)
	if type(name) ~= "string" then
		return nil
	end
	name = name:match("^%s*(.-)%s*$")
	if not name or name == "" or name == "Unknown" then
		return nil
	end
	name = name:gsub("%s+", " ")
	if not name:find(" ", 1, true) then
		local first, surname = name:match("^([^%-]+)%-(.+)$")
		if first and surname and surname ~= "" and not surname:find("-", 1, true) then
			name = first .. " " .. surname
		end
	end
	return name
end

--- "Tamby Kojak" from UnitName's first name + surname. A realm is not a surname.
local function ReadUnitName(unit)
	local first, surname
	if UnitName then
		first, surname = UnitName(unit)
	end
	if type(surname) == "string" then
		surname = surname:match("^%s*(.-)%s*$")
		if surname == "" then
			surname = nil
		end
	else
		surname = nil
	end
	if surname and GetRealmName and surname == GetRealmName() then
		surname = nil
	end
	if surname and GetNormalizedRealmName and surname == GetNormalizedRealmName() then
		surname = nil
	end

	first = NormalizeName(first)
	if first and surname and not first:find(" ", 1, true) then
		return first .. " " .. surname
	end

	if GetUnitName then
		local full = NormalizeName(GetUnitName(unit, true))
		if full and (not first or #full > #first) then
			return full
		end
	end
	return first
end

--- Read player map coords. Never call SetMapToCurrentZone / legacy map writers.
local function GetPlayerMapCoords()
	if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
		local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
		if ok and mapID then
			local okPos, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
			if okPos and pos then
				local x, y
				if pos.GetXY then
					x, y = pos.GetXY(pos)
				else
					x, y = pos.x, pos.y
				end
				if type(x) == "number" and type(y) == "number" then
					return x, y, mapID
				end
			end
		end
	end

	if UnitPosition then
		local ok, y, x, _, mapID = pcall(UnitPosition, "player")
		if ok and type(x) == "number" and type(y) == "number" then
			return x, y, mapID
		end
	end

	return nil, nil, nil
end

local function GetZoneName()
	local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or nil
	if type(zone) == "string" and zone ~= "" then
		return zone
	end
	return nil
end

local function GetSubZoneName()
	local sub = GetSubZoneText and GetSubZoneText() or nil
	if type(sub) == "string" and sub ~= "" then
		return sub
	end
	return nil
end

local function CaptureLocation()
	local x, y, mapID = GetPlayerMapCoords()
	local loc = {
		zone = GetZoneName(),
		subzone = GetSubZoneName(),
		x = x,
		y = y,
		time = time and time() or nil,
	}
	if mapID ~= nil then
		loc.map = mapID
	end
	return loc
end

local MAX_COMBAT_LOG = 40

local function EnsureCombatLog(entry)
	if type(entry.combatLog) ~= "table" then
		entry.combatLog = {}
	end
	return entry.combatLog
end

local function ReadLevel(unit)
	if not UnitLevel or not unit then
		return nil
	end
	local level = UnitLevel(unit)
	if type(level) == "number" and level > 0 then
		return level
	end
	return nil
end

--- Append a combat-log row: region, coords, result, and both levels at that moment.
local function AppendCombatLog(entry, result)
	local loc = CaptureLocation()
	local logRows = EnsureCombatLog(entry)
	logRows[#logRows + 1] = {
		result = result,
		zone = loc.zone,
		subzone = loc.subzone,
		x = loc.x,
		y = loc.y,
		map = loc.map,
		time = loc.time,
		level = entry.level,
		myLevel = ReadLevel("player"),
	}
	while #logRows > MAX_COMBAT_LOG do
		table.remove(logRows, 1)
	end
	entry.lastSeen = loc
	return logRows[#logRows]
end

function DeathNote_GetCombatLog(name)
	local entry = DeathNote_GetEntry(name)
	if not entry then
		return {}
	end
	return EnsureCombatLog(entry)
end

function DeathNote_FormatLevel(level)
	if type(level) ~= "number" or level < 1 then
		return "—"
	end
	return tostring(math.floor(level))
end

function DeathNote_FormatRegion(row)
	if not row then
		return "—"
	end
	local zone = row.zone or "Unknown"
	if row.subzone and row.subzone ~= "" and row.subzone ~= zone then
		return zone .. " — " .. row.subzone
	end
	return zone
end

local function ReadUnitIdentity(unit)
	if not unit or not UnitExists or not UnitExists(unit) then
		return nil
	end
	if UnitIsPlayer and not UnitIsPlayer(unit) then
		return nil
	end

	local name = ReadUnitName(unit)
	if not name then
		return nil
	end

	local class, classFile
	if UnitClass then
		class, classFile = UnitClass(unit)
	end
	local race, raceFile
	if UnitRace then
		race, raceFile = UnitRace(unit)
	end
	local guid = UnitGUID and UnitGUID(unit) or nil

	return {
		name = name,
		guid = guid,
		class = class,
		classFile = classFile,
		race = race,
		raceFile = raceFile,
		level = ReadLevel(unit),
	}
end

local function FindEntryKey(nameOrGuid)
	local db = EnsureDB()
	if not nameOrGuid then
		return nil
	end

	if db.entries[nameOrGuid] then
		return nameOrGuid
	end

	local bare = NormalizeName(nameOrGuid)
	if bare and db.entries[bare] then
		return bare
	end

	for key, entry in pairs(db.entries) do
		if entry.guid and entry.guid == nameOrGuid then
			return key
		end
		if bare and NormalizeName(entry.name) == bare then
			return key
		end
	end
	return nil
end

--- One entry saved before surnames existed ("Tamby") can adopt "Tamby Kojak".
--- Two people who share that first name are left alone.
local function FindLegacyFirstNameKey(fullName)
	local first = fullName and fullName:match("^(%S+)")
	if not first or first == fullName then
		return nil
	end
	local db = EnsureDB()
	local found
	for key, entry in pairs(db.entries) do
		local stored = NormalizeName(entry.name) or NormalizeName(key)
		if stored == first then
			if found then
				return nil
			end
			found = key
		end
	end
	return found
end

local pendingRenameFrom, pendingRenameTo

local function AdoptFullName(oldKey, fullName)
	if not oldKey or not fullName or oldKey == fullName then
		return oldKey
	end
	local db = EnsureDB()
	local entry = db.entries[oldKey]
	if not entry then
		return oldKey
	end
	if db.entries[fullName] and db.entries[fullName] ~= entry then
		return fullName
	end
	db.entries[oldKey] = nil
	db.entries[fullName] = entry
	entry.name = fullName
	pendingRenameFrom, pendingRenameTo = oldKey, fullName
	log:Info("renamed", oldKey, "→", fullName)
	return fullName
end

function DeathNote_TakeRename()
	local oldName, newName = pendingRenameFrom, pendingRenameTo
	pendingRenameFrom, pendingRenameTo = nil, nil
	return oldName, newName
end

--- Find a noted person by guid or full name, and move a first-name-only entry
--- onto the full name once we learn the surname.
local function LookupEntry(name, guid)
	local full = NormalizeName(name)
	local key = (guid and FindEntryKey(guid)) or nil
	local byGuid = key ~= nil
	if not key and full then
		key = FindEntryKey(full)
	end
	local byLegacy = false
	if not key and full then
		key = FindLegacyFirstNameKey(full)
		byLegacy = key ~= nil
	end
	if not key then
		return nil, nil
	end
	-- A surname can replace a first-name-only entry. Never shorten "Tamby Kojak" back to "Tamby".
	if full and key ~= full and (byGuid or byLegacy) then
		local stored = NormalizeName(EnsureDB().entries[key] and EnsureDB().entries[key].name) or key
		if full:sub(1, #stored + 1) == (stored .. " ") then
			key = AdoptFullName(key, full)
		end
	end
	local entry = EnsureDB().entries[key]
	if entry and full then
		local stored = entry.name or key
		if stored == full or full:sub(1, #stored + 1) == (stored .. " ") then
			entry.name = full
		end
	end
	return entry, key
end

local function RefreshJournal()
	if DeathNoteJournal_Refresh then
		DeathNoteJournal_Refresh()
	end
end

WoWF.OnDevModeChanged(function(enabled)
	log:SetLevel(enabled and "DEBUG" or "INFO")
	RefreshJournal()
end)

local function PrintNote(msg)
	print("|cffcc3333[Death Note]|r " .. msg)
end

--- Slash commands registered early so a later load error cannot wipe /dn.
local function OnSlash(msg)
	msg = (msg and msg:match("^%s*(.-)%s*$")) or ""
	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	cmd = cmd and string.lower(cmd) or ""
	rest = rest and rest:match("^%s*(.-)%s*$") or ""

	if cmd == "add" then
		if rest == "" then
			DeathNote_Add(nil)
		else
			DeathNote_Add(rest)
		end
		return
	end

	if cmd == "remove" or cmd == "rm" or cmd == "delete" then
		if rest == "" then
			local identity = ReadUnitIdentity("target")
			if identity then
				DeathNote_Remove(identity.name)
			else
				PrintNote("Usage: /dn remove <name>  (or target them)")
			end
		else
			DeathNote_Remove(rest)
		end
		return
	end

	if cmd == "clear" or cmd == "reset" then
		DeathNote_ResetAll()
		return
	end

	if cmd == "dev" then
		WoWF.ToggleDevMode(ADDON_NAME, rest)
		return
	end

	if cmd == "seed" then
		local side = string.lower(rest or "")
		if side == "" or side == "horde" then
			DeathNote_SeedDemo("horde")
		elseif side == "alliance" then
			DeathNote_SeedDemo("alliance")
		else
			PrintNote("Usage: /dn seed   or   /dn seed alliance")
		end
		return
	end

	if cmd == "help" then
		PrintNote("/dn — open the journal")
		PrintNote("/dn add [name] — add target or name")
		PrintNote("/dn remove [name] — remove target or name")
		PrintNote("/dn clear — wipe the Death Note")
		PrintNote("/dn dev [on|off] — toggle Development mode (this session)")
		PrintNote("/dn seed — fill with Horde names (you play Alliance)")
		PrintNote("/dn seed alliance — fill with Alliance names (you play Horde)")
		return
	end

	if type(DeathNoteJournal_Toggle) == "function" then
		local ok, err = pcall(DeathNoteJournal_Toggle)
		if not ok then
			PrintNote("Journal error: " .. tostring(err))
			log:Error("journal", err)
		end
	else
		PrintNote("Journal failed to load. Try /reload. If it persists, re-enable DeathNote in AddOns.")
	end
end

SLASH_DEATHNOTE1 = "/deathnote"
SLASH_DEATHNOTE2 = "/dn"
SLASH_DEATHNOTE3 = "/dnote"
SlashCmdList["DEATHNOTE"] = OnSlash

--- Apply observed identity/location onto an existing entry.
local function TouchEntry(entry, identity, updateLocation)
	if identity then
		if identity.guid then
			entry.guid = identity.guid
		end
		if identity.class then
			entry.class = identity.class
			entry.classFile = identity.classFile
		end
		if identity.race then
			entry.race = identity.race
			entry.raceFile = identity.raceFile
		end
		if type(identity.level) == "number" and identity.level > 0 then
			entry.level = identity.level
		end
	end
	if updateLocation then
		entry.lastSeen = CaptureLocation()
	end
end

function DeathNote_EnsureDB()
	return EnsureDB()
end

function DeathNote_GetNames()
	local db = EnsureDB()
	local names = {}
	for name in pairs(db.entries) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

function DeathNote_GetEntry(name)
	local key = FindEntryKey(name)
	if not key then
		return nil
	end
	return EnsureDB().entries[key], key
end

--- Freeform note. SavedVariables persist the table; no explicit save step.
function DeathNote_SetNote(name, text)
	local entry = DeathNote_GetEntry(name)
	if not entry then
		return false
	end
	if type(text) ~= "string" then
		text = ""
	end
	entry.note = text
	return true
end

function DeathNote_FormatCoords(loc)
	if not loc or type(loc.x) ~= "number" or type(loc.y) ~= "number" then
		return "—"
	end
	if loc.x >= 0 and loc.x <= 1 and loc.y >= 0 and loc.y <= 1 then
		return string.format("%.1f, %.1f", loc.x * 100, loc.y * 100)
	end
	return string.format("%.1f, %.1f", loc.x, loc.y)
end

function DeathNote_FormatLocation(loc)
	if not loc then
		return "Never seen"
	end
	local zone = loc.zone or "Unknown zone"
	if loc.subzone and loc.subzone ~= "" and loc.subzone ~= zone then
		zone = zone .. " — " .. loc.subzone
	end
	return string.format("%s  (%s)", zone, DeathNote_FormatCoords(loc))
end

function DeathNote_Add(nameOrNil)
	local identity
	local fromUnit = false

	if nameOrNil and nameOrNil ~= "" then
		local bare = NormalizeName(nameOrNil)
		identity = { name = bare }
		-- Prefer live unit data if target/mouseover matches.
		for _, unit in ipairs({ "target", "mouseover", "focus" }) do
			local live = ReadUnitIdentity(unit)
			if live and NormalizeName(live.name) == bare then
				identity = live
				fromUnit = true
				break
			end
		end
	else
		identity = ReadUnitIdentity("target")
		fromUnit = identity ~= nil
		if not identity then
			PrintNote("Target a player, or use /dn add <name>.")
			return nil
		end
	end

	if not identity or not identity.name then
		PrintNote("Could not resolve a player name.")
		return nil
	end

	local db = EnsureDB()
	local entry, key = LookupEntry(identity.name, identity.guid)
	local created = false
	if not entry then
		entry = {
			name = identity.name,
			kills = 0,
			deaths = 0,
			combatLog = {},
			addedAt = time and time() or nil,
		}
		db.entries[identity.name] = entry
		key = identity.name
		created = true
	end
	EnsureCombatLog(entry)

	TouchEntry(entry, identity, fromUnit)
	entry.name = identity.name or entry.name

	if created then
		PrintNote("Added " .. entry.name .. " to the Death Note.")
		log:Info("added", entry.name)
	else
		PrintNote(entry.name .. " is already in the Death Note — updated info.")
		log:Debug("updated", entry.name)
	end

	RefreshJournal()
	return entry, key
end

function DeathNote_Remove(name)
	local entry, key = DeathNote_GetEntry(name)
	if not key then
		PrintNote("No entry for '" .. tostring(name) .. "'.")
		return false
	end
	EnsureDB().entries[key] = nil
	PrintNote("Removed " .. (entry.name or key) .. " from the Death Note.")
	log:Info("removed", key)
	RefreshJournal()
	return true
end

function DeathNote_ResetAll()
	DeathNoteDB = { version = 1, entries = {} }
	recentKillAt = {}
	recentDeathAt = {}
	PrintNote("Cleared the Death Note.")
	log:Info("cleared all")
	RefreshJournal()
end

--- Video / demo roster. One enemy faction, vanilla race and class combos.
--- Log strings are oldest first: "Result:place:Nh". place is an index into SEED_PLACES.
local SEED_PLACES = {
	{ "Alterac Valley", "Dun Baldar", 0.482, 0.214 },
	{ "Alterac Valley", "Frostwolf Keep", 0.471, 0.846 },
	{ "Warsong Gulch", "Silverwing Hold", 0.524, 0.168 },
	{ "Warsong Gulch", "Warsong Lumber Mill", 0.462, 0.824 },
	{ "Arathi Basin", "Farm", 0.386, 0.612 },
	{ "Arathi Basin", "Blacksmith", 0.474, 0.448 },
	{ "Arathi Basin", "Stables", 0.368, 0.286 },
	{ "Hillsbrad Foothills", "Tarren Mill", 0.628, 0.192 },
	{ "Hillsbrad Foothills", "Southshore", 0.498, 0.574 },
	{ "Stranglethorn Vale", "Booty Bay", 0.268, 0.772 },
	{ "Stranglethorn Vale", "Nesingwary's Expedition", 0.354, 0.112 },
	{ "The Barrens", "The Crossroads", 0.518, 0.298 },
	{ "The Barrens", "Ratchet", 0.632, 0.368 },
	{ "Ashenvale", "Astranaar", 0.342, 0.492 },
	{ "Ashenvale", "Splintertree Post", 0.738, 0.622 },
	{ "Silithus", "Cenarion Hold", 0.512, 0.358 },
	{ "Eastern Plaguelands", "Light's Hope Chapel", 0.806, 0.576 },
	{ "Eastern Plaguelands", "Tyr's Hand", 0.768, 0.742 },
	{ "Burning Steppes", "Morgan's Vigil", 0.842, 0.684 },
	{ "Burning Steppes", "Flame Crest", 0.648, 0.238 },
	{ "Tanaris", "Gadgetzan", 0.522, 0.274 },
	{ "Redridge Mountains", "Lakeshire", 0.312, 0.446 },
	{ "Wetlands", "Menethil Harbor", 0.108, 0.562 },
	{ "Duskwood", "Darkshire", 0.774, 0.448 },
	{ "Stonetalon Mountains", "Sun Rock Retreat", 0.458, 0.604 },
	{ "Felwood", "Bloodvenom Post", 0.346, 0.522 },
	{ "Winterspring", "Everlook", 0.614, 0.382 },
	{ "Alterac Mountains", "Strahnbrad", 0.636, 0.422 },
	{ "Thousand Needles", "Freewind Post", 0.452, 0.508 },
	{ "Desolace", "Shadowprey Village", 0.242, 0.714 },
}

local SEED_HORDE = {
	{ name = "Azkor", race = "Orc", raceFile = "Orc", class = "Warrior", classFile = "WARRIOR",
		note = "Teabag him exactly 13 times next time I see him.",
		log = "Death:8:12d,Combat:9:9d,Death:8:7d,Kill:9:5d,Combat:28:3d,Death:8:2d,Death:8:26h,Combat:9:8h,Death:8:2h,Combat:8:18m" },
	{ name = "Borgash", race = "Orc", raceFile = "Orc", class = "Hunter", classFile = "HUNTER",
		log = "Combat:14:8d,Death:14:6d,Combat:15:4d,Kill:15:3d,Death:14:1d,Combat:14:5h,Death:14:40m" },
	{ name = "Drogna", race = "Orc", raceFile = "Orc", class = "Warlock", classFile = "WARLOCK",
		note = "Called me a baby after the fear. I am writing it down so I don't forgive her.",
		log = "Death:12:10d,Combat:13:6d,Death:12:4d,Combat:12:2d,Kill:13:1d,Death:12:9h,Combat:12:3h" },
	{ name = "Grimtusk", race = "Tauren", raceFile = "Tauren", class = "Druid", classFile = "DRUID",
		log = "Combat:25:9d,Death:25:5d,Combat:15:3d,Kill:25:2d,Death:25:22h,Combat:25:4h" },
	{ name = "Heshka", race = "Troll", raceFile = "Troll", class = "Rogue", classFile = "ROGUE",
		note = "Vanished with my swiftness pot still ticking. Thief.",
		log = "Death:21:11d,Combat:21:7d,Death:10:4d,Combat:21:2d,Kill:21:1d,Death:21:6h,Combat:21:50m" },
	{ name = "Kargesh", race = "Orc", raceFile = "Orc", class = "Shaman", classFile = "SHAMAN",
		log = "Combat:2:8d,Death:2:6d,Combat:1:4d,Death:2:2d,Kill:1:1d,Combat:2:7h,Death:2:90m" },
	{ name = "Morveth", race = "Undead", raceFile = "Scourge", class = "Mage", classFile = "MAGE",
		note = "Sheeped me in front of the whole raid. I am not over it.",
		log = "Death:1:14d,Combat:2:8d,Death:1:5d,Kill:1:3d,Combat:1:2d,Death:1:11h,Combat:1:2h,Death:1:25m" },
	{ name = "Nekros", race = "Undead", raceFile = "Scourge", class = "Warlock", classFile = "WARLOCK",
		log = "Combat:17:7d,Death:18:5d,Death:17:3d,Combat:17:1d,Kill:17:16h,Death:17:3h" },
	{ name = "Razzik", race = "Troll", raceFile = "Troll", class = "Priest", classFile = "PRIEST",
		note = "If he mind controls me into the lumber mill again I'm making it personal.",
		log = "Death:4:6d,Combat:3:4d,Kill:4:2d,Combat:4:1d,Death:4:8h,Combat:4:70m" },
	{ name = "Shavara", race = "Undead", raceFile = "Scourge", class = "Rogue", classFile = "ROGUE",
		log = "Death:24:9d,Combat:24:6d,Death:24:4d,Combat:22:2d,Kill:24:1d,Death:24:5h,Combat:24:35m" },
	{ name = "Skarrak", race = "Orc", raceFile = "Orc", class = "Rogue", classFile = "ROGUE",
		note = "Was waiting on the roof. Look up. Then look up again.",
		log = "Combat:12:8d,Death:12:6d,Death:13:3d,Kill:12:2d,Combat:12:20h,Death:12:4h,Combat:12:1h" },
	{ name = "Tornhoof", race = "Tauren", raceFile = "Tauren", class = "Hunter", classFile = "HUNTER",
		log = "Death:29:10d,Combat:29:6d,Kill:29:4d,Death:29:2d,Combat:29:9h,Death:29:80m" },
	{ name = "Vexira", race = "Undead", raceFile = "Scourge", class = "Priest", classFile = "PRIEST",
		note = "She waved after I rezzed. Wave back, then kill her.",
		log = "Combat:26:5d,Death:26:3d,Combat:26:2d,Kill:26:1d,Death:26:7h,Combat:26:2h" },
	{ name = "Zulmar", race = "Troll", raceFile = "Troll", class = "Hunter", classFile = "HUNTER",
		log = "Death:11:13d,Combat:10:7d,Kill:11:4d,Death:11:2d,Combat:11:18h,Kill:10:6h,Death:11:45m" },
}

local SEED_ALLIANCE = {
	{ name = "Aldric", race = "Human", raceFile = "Human", class = "Paladin", classFile = "PALADIN",
		log = "Death:9:12d,Combat:8:9d,Death:9:7d,Kill:8:5d,Combat:28:3d,Death:9:2d,Death:9:22h,Combat:9:6h,Death:9:90m,Combat:9:16m" },
	{ name = "Bromm", race = "Dwarf", raceFile = "Dwarf", class = "Warrior", classFile = "WARRIOR",
		note = "Hamstrings me and runs to the guards. Kick him into the water next time.",
		log = "Combat:23:8d,Death:23:5d,Kill:23:3d,Death:23:1d,Combat:23:9h,Death:23:2h" },
	{ name = "Dunric", race = "Dwarf", raceFile = "Dwarf", class = "Paladin", classFile = "PALADIN",
		log = "Death:1:11d,Combat:1:6d,Death:1:4d,Combat:1:2d,Kill:1:1d,Death:1:8h,Combat:1:70m" },
	{ name = "Elyndra", race = "Night Elf", raceFile = "NightElf", class = "Hunter", classFile = "HUNTER",
		note = "Her cat's name is Mr. Whiskers. Kill Mr. Whiskers.",
		log = "Combat:14:9d,Death:14:6d,Kill:14:3d,Death:14:2d,Combat:14:11h,Death:14:35m" },
	{ name = "Fizzwick", race = "Gnome", raceFile = "Gnome", class = "Mage", classFile = "MAGE",
		log = "Death:21:10d,Combat:21:7d,Death:21:4d,Kill:21:2d,Combat:21:1d,Death:21:5h,Combat:21:40m" },
	{ name = "Harlan", race = "Human", raceFile = "Human", class = "Warrior", classFile = "WARRIOR",
		note = "Knocked me off my mount into the lake. Twice. I counted.",
		log = "Combat:22:8d,Death:22:5d,Kill:22:3d,Death:22:26h,Combat:22:4h,Death:22:1h" },
	{ name = "Kelland", race = "Human", raceFile = "Human", class = "Warlock", classFile = "WARLOCK",
		log = "Death:24:7d,Combat:24:4d,Death:24:2d,Kill:24:1d,Combat:24:10h,Death:24:3h" },
	{ name = "Maren", race = "Human", raceFile = "Human", class = "Rogue", classFile = "ROGUE",
		note = "Pickpocketed 40 silver at the auction house. I want it back or I want a corpse.",
		log = "Combat:10:6d,Death:10:4d,Kill:10:2d,Death:10:1d,Combat:10:8h,Death:10:55m" },
	{ name = "Myra", race = "Gnome", raceFile = "Gnome", class = "Warlock", classFile = "WARLOCK",
		log = "Death:5:9d,Combat:6:5d,Kill:5:3d,Death:5:2d,Combat:5:14h,Death:5:2h" },
	{ name = "Osric", race = "Human", raceFile = "Human", class = "Hunter", classFile = "HUNTER",
		note = "Frost trap on the only door. I walked into it twice. Not a third time.",
		log = "Combat:7:8d,Death:7:5d,Kill:7:2d,Death:7:1d,Combat:7:6h,Death:7:80m" },
	{ name = "Sennara", race = "Night Elf", raceFile = "NightElf", class = "Priest", classFile = "PRIEST",
		log = "Combat:1:6d,Death:1:4d,Combat:1:2d,Kill:1:1d,Death:1:9h,Combat:1:3h" },
	{ name = "Tinkerby", race = "Gnome", raceFile = "Gnome", class = "Rogue", classFile = "ROGUE",
		note = "He was in a crate. Stab every crate in Menethil.",
		log = "Death:23:11d,Combat:23:6d,Kill:23:3d,Death:23:2d,Combat:23:12h,Death:23:70m" },
	{ name = "Thalorien", race = "Night Elf", raceFile = "NightElf", class = "Druid", classFile = "DRUID",
		log = "Combat:14:10d,Death:15:6d,Kill:14:4d,Death:14:2d,Combat:14:15h,Death:14:4h" },
	{ name = "Vale", race = "Human", raceFile = "Human", class = "Priest", classFile = "PRIEST",
		note = "Only fights when the guards can see him. Coward.",
		log = "Death:9:8d,Combat:9:5d,Kill:9:3d,Death:9:1d,Combat:9:7h,Death:9:50m" },
}

--- Current level of each seeded name. Older log rows step down from this.
local SEED_LEVEL = {
	Azkor = 59, Borgash = 52, Drogna = 47, Grimtusk = 60, Heshka = 44,
	Kargesh = 55, Morveth = 60, Nekros = 41, Razzik = 38, Shavara = 56,
	Skarrak = 49, Tornhoof = 60, Vexira = 43, Zulmar = 57,
	Aldric = 60, Bromm = 48, Dunric = 58, Elyndra = 51, Fizzwick = 42,
	Harlan = 54, Kelland = 46, Maren = 39, Myra = 36, Osric = 53,
	Sennara = 60, Tinkerby = 45, Thalorien = 57, Vale = 50,
}
--- The seeded player's level "now". Older rows were a few levels earlier.
local SEED_MY_LEVEL = 60

local SEED_AGO = { d = 86400, h = 3600, m = 60 }

local function BuildSeedEntry(spec, now)
	local logRows = {}
	local kills, deaths = 0, 0
	local newest
	local oldestAgo = 0
	for chunk in string.gmatch(spec.log, "[^,]+") do
		local result, placeIndex, amount, unit = chunk:match("^(%a+):(%d+):(%d+)([dhm])$")
		local place = SEED_PLACES[tonumber(placeIndex)]
		local ago = tonumber(amount) * SEED_AGO[unit]
		if result and place and ago then
			local days = ago / 86400
			local theirNow = SEED_LEVEL[spec.name] or 60
			local row = {
				result = result,
				zone = place[1],
				subzone = place[2],
				x = place[3],
				y = place[4],
				time = now - ago,
				level = math.max(1, theirNow - math.floor(days / 5)),
				myLevel = math.max(1, SEED_MY_LEVEL - math.floor(days / 4)),
			}
			logRows[#logRows + 1] = row
			if result == "Kill" then
				kills = kills + 1
			elseif result == "Death" then
				deaths = deaths + 1
			end
			if ago > oldestAgo then
				oldestAgo = ago
			end
			if not newest or row.time > newest.time then
				newest = row
			end
		end
	end

	return {
		name = spec.name,
		race = spec.race,
		raceFile = spec.raceFile,
		class = spec.class,
		classFile = spec.classFile,
		level = SEED_LEVEL[spec.name] or 60,
		kills = kills,
		deaths = deaths,
		note = spec.note,
		addedAt = now - oldestAgo - 7200,
		combatLog = logRows,
		lastSeen = newest and {
			zone = newest.zone,
			subzone = newest.subzone,
			x = newest.x,
			y = newest.y,
			time = newest.time,
		} or nil,
	}
end

function DeathNote_SeedDemo(side)
	if not (WoWF and WoWF.DevMode) then
		PrintNote("Seed is only available while Development mode is on.")
		return false
	end

	side = string.lower(side or "horde")
	local roster = side == "alliance" and SEED_ALLIANCE or SEED_HORDE
	local faction = side == "alliance" and "Alliance" or "Horde"
	local now = (time and time()) or 0

	local db = EnsureDB()
	db.version = 1
	db.entries = {}
	recentKillAt = {}
	recentDeathAt = {}

	local count = 0
	for i = 1, #roster do
		local entry = BuildSeedEntry(roster[i], now)
		db.entries[entry.name] = entry
		count = count + 1
	end

	PrintNote(string.format(
		"Wrote %d %s names for the video. This replaced whatever was in the note. /dn clear wipes it.",
		count,
		faction
	))
	log:Info("seeded", faction, count)
	RefreshJournal()
	if DeathNoteJournal_Show then
		DeathNoteJournal_Show()
	end
	return true
end

local function ObserveUnit(unit)
	local identity = ReadUnitIdentity(unit)
	if not identity then
		return
	end
	local entry = LookupEntry(identity.name, identity.guid)
	if not entry then
		return
	end
	TouchEntry(entry, identity, true)
	log:Debug("seen", entry.name, DeathNote_FormatLocation(entry.lastSeen))
	RefreshJournal()
end

local function Now()
	return (GetTime and GetTime()) or 0
end

--- Level of a named unit if they are currently target, mouseover, or focus.
local function ObservedLevel(name)
	local bare = NormalizeName(name)
	if not bare then
		return nil
	end
	for _, unit in ipairs({ "target", "mouseover", "focus" }) do
		local live = ReadUnitIdentity(unit)
		if live and live.name == bare and live.level then
			return live.level
		end
	end
	return nil
end

local function RecordKill(name, guid, opts)
	opts = opts or {}
	local entry, key = LookupEntry(name, guid)
	if not entry then
		return
	end
	local dedupeKey = guid or key
	local t = Now()
	if not opts.force then
		if recentKillAt[dedupeKey] and (t - recentKillAt[dedupeKey]) < KILL_DEDUP_SECONDS then
			return
		end
	end
	recentKillAt[dedupeKey] = t

	entry.kills = (entry.kills or 0) + 1
	TouchEntry(entry, {
		name = NormalizeName(name) or entry.name,
		guid = guid,
		level = ObservedLevel(name),
	}, false)
	AppendCombatLog(entry, "Kill")
	local prefix = opts.simulate and "Simulated kill" or "Kill recorded"
	PrintNote(string.format("%s: %s  (kills %d)", prefix, entry.name, entry.kills))
	log:Info(opts.simulate and "sim-kill" or "kill", entry.name, entry.kills)
	RefreshJournal()
end

local function RecordDeathFrom(name, guid, opts)
	opts = opts or {}
	local entry, key = LookupEntry(name, guid)
	if not entry then
		return
	end
	local dedupeKey = guid or key
	local t = Now()
	if not opts.force then
		if recentDeathAt[dedupeKey] and (t - recentDeathAt[dedupeKey]) < KILL_DEDUP_SECONDS then
			return
		end
	end
	recentDeathAt[dedupeKey] = t

	entry.deaths = (entry.deaths or 0) + 1
	TouchEntry(entry, {
		name = NormalizeName(name) or entry.name,
		guid = guid,
		level = ObservedLevel(name),
	}, false)
	AppendCombatLog(entry, "Death")
	local prefix = opts.simulate and "Simulated death" or "Death recorded"
	PrintNote(string.format("%s: %s  (deaths %d)", prefix, entry.name, entry.deaths))
	log:Info(opts.simulate and "sim-death" or "death", entry.name, entry.deaths)
	RefreshJournal()
end

local function RecordCombat(name, guid, opts)
	opts = opts or {}
	local entry = LookupEntry(name, guid)
	if not entry then
		return
	end
	TouchEntry(entry, {
		name = NormalizeName(name) or entry.name,
		guid = guid,
		level = ObservedLevel(name),
	}, false)
	AppendCombatLog(entry, "Combat")
	local prefix = opts.simulate and "Simulated combat" or "Combat recorded"
	PrintNote(string.format("%s: %s", prefix, entry.name))
	log:Info(opts.simulate and "sim-combat" or "combat", entry.name)
	RefreshJournal()
end

--- DevMode testing helpers — force outcomes on a noted name (bypasses dedupe).
function DeathNote_SimulateKill(name)
	if not (WoWF and WoWF.DevMode) then
		PrintNote("Simulate is only available while Development mode is on.")
		return false
	end
	if not name or name == "" then
		PrintNote("Select a name first.")
		return false
	end
	local entry = DeathNote_GetEntry(name)
	if not entry then
		PrintNote("No entry for '" .. tostring(name) .. "'.")
		return false
	end
	RecordKill(entry.name, entry.guid, { force = true, simulate = true })
	return true
end

function DeathNote_SimulateDeath(name)
	if not (WoWF and WoWF.DevMode) then
		PrintNote("Simulate is only available while Development mode is on.")
		return false
	end
	if not name or name == "" then
		PrintNote("Select a name first.")
		return false
	end
	local entry = DeathNote_GetEntry(name)
	if not entry then
		PrintNote("No entry for '" .. tostring(name) .. "'.")
		return false
	end
	RecordDeathFrom(entry.name, entry.guid, { force = true, simulate = true })
	return true
end

function DeathNote_SimulateCombat(name)
	if not (WoWF and WoWF.DevMode) then
		PrintNote("Simulate is only available while Development mode is on.")
		return false
	end
	if not name or name == "" then
		PrintNote("Select a name first.")
		return false
	end
	local entry = DeathNote_GetEntry(name)
	if not entry then
		PrintNote("No entry for '" .. tostring(name) .. "'.")
		return false
	end
	RecordCombat(entry.name, entry.guid, { force = true, simulate = true })
	return true
end

--- Forever refuses COMBAT_LOG_EVENT_UNFILTERED — parse kill chat instead.
local function ParseSlainName(msg)
	if type(msg) ~= "string" then
		return nil
	end
	local name =
		msg:match("^You have slain (.+)!$")
		or msg:match("^You have slain (.+)%.$")
		or msg:match("^You have slain (.+)$")
		or msg:match("^(.+) dies%.$")
		or msg:match("^(.+) dies!$")
		or msg:match("honorable kill.-%((.+)%)")
		or msg:match("^(.+) has been slain by .+$")
	return NormalizeName(name)
end

local function OnHostileDeathMessage(msg)
	local name = ParseSlainName(msg)
	if not name then
		log:Debug("hostile death unparsed:", msg)
		return
	end
	RecordKill(name, nil)
end

--- If our current target is a noted player who just died, count the kill.
local function OnTargetHealth()
	if not UnitExists or not UnitExists("target") then
		return
	end
	if not UnitIsDead or not UnitIsDead("target") then
		return
	end
	local identity = ReadUnitIdentity("target")
	if not identity then
		return
	end
	RecordKill(identity.name, identity.guid)
end

local function OnPlayerDead()
	-- Without combat log, attribute death to the current player target when noted.
	local identity = ReadUnitIdentity("target")
	if identity then
		RecordDeathFrom(identity.name, identity.guid)
	else
		log:Debug("died but no player target to attribute")
	end
end

local eventFrame = CreateFrame("Frame")

--- Forever refuses some events (e.g. CLEU). Never let a bad RegisterEvent abort load.
local function SafeRegister(eventName)
	local ok, err = pcall(function()
		eventFrame:RegisterEvent(eventName)
	end)
	if not ok then
		log:Warn("RegisterEvent refused:", eventName, err)
	end
end

SafeRegister("ADDON_LOADED")
SafeRegister("PLAYER_LOGIN")
SafeRegister("PLAYER_TARGET_CHANGED")
SafeRegister("UPDATE_MOUSEOVER_UNIT")
SafeRegister("PLAYER_DEAD")
SafeRegister("UNIT_HEALTH")
SafeRegister("CHAT_MSG_COMBAT_HOSTILE_DEATH")
SafeRegister("CHAT_MSG_COMBAT_HONOR_GAIN")
SafeRegister("CHAT_MSG_SYSTEM")
SafeRegister("ADDON_ACTION_BLOCKED")
SafeRegister("ADDON_ACTION_FORBIDDEN")
-- Do NOT register COMBAT_LOG_EVENT_UNFILTERED — Forever blocks it.

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		EnsureDB()
		log:Info("loaded — /dn /deathnote /dnote")
		return
	end

	if event == "PLAYER_LOGIN" then
		return
	end

	if event == "PLAYER_TARGET_CHANGED" then
		ObserveUnit("target")
		OnTargetHealth()
		return
	end

	if event == "UPDATE_MOUSEOVER_UNIT" then
		ObserveUnit("mouseover")
		return
	end

	if event == "PLAYER_DEAD" then
		OnPlayerDead()
		return
	end

	if event == "UNIT_HEALTH" then
		if arg1 == "target" then
			OnTargetHealth()
		end
		return
	end

	if event == "CHAT_MSG_COMBAT_HOSTILE_DEATH"
		or event == "CHAT_MSG_COMBAT_HONOR_GAIN"
		or event == "CHAT_MSG_SYSTEM"
	then
		OnHostileDeathMessage(arg1)
		return
	end

	if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		-- arg1 = addon name, arg2 = function name (may be nil on Forever)
		if arg1 == ADDON_NAME or arg1 == "DeathNote" then
			log:Error(event, "function=", tostring(arg2))
			PrintNote("Blocked action: " .. tostring(arg2 or "(unnamed)") .. " — tell the author.")
		end
	end
end)
