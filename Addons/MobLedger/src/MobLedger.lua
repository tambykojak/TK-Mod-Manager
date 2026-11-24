local ADDON_NAME, Addon = ...

local log = WoWF.Logger:New(ADDON_NAME, {
	minLevel = WoWF.DevMode and "DEBUG" or "INFO",
})

WoWF.OnDevModeChanged(function(enabled)
	log:SetLevel(enabled and "DEBUG" or "INFO")
end)

--- Session-only: avoid double-counting the same corpse GUID.
local seenGuids = {}

local function EnsureDB()
	if type(MobLedgerDB) ~= "table" then
		MobLedgerDB = {}
	end
	if type(MobLedgerDB.mobs) ~= "table" then
		MobLedgerDB.mobs = {}
	end
	if type(MobLedgerDB.hiddenMobs) ~= "table" then
		MobLedgerDB.hiddenMobs = {}
	end
	if type(MobLedgerDB.hiddenLocations) ~= "table" then
		MobLedgerDB.hiddenLocations = {}
	end
	if type(MobLedgerDB.hiddenAreas) ~= "table" then
		MobLedgerDB.hiddenAreas = {}
	end
	if type(MobLedgerDB.ui) ~= "table" then
		MobLedgerDB.ui = {}
	end
	if type(MobLedgerDB.ui.expanded) ~= "table" then
		MobLedgerDB.ui.expanded = {}
	end
	if MobLedgerDB.ui.hiddenExpanded == nil then
		MobLedgerDB.ui.hiddenExpanded = false
	end
	if type(MobLedgerDB.sellPrices) ~= "table" then
		MobLedgerDB.sellPrices = {}
	end
	MobLedgerDB.version = MobLedgerDB.version or 3
	return MobLedgerDB
end

local function GetOrCreateMob(name)
	local db = EnsureDB()
	local mob = db.mobs[name]
	if not mob then
		mob = {
			loots = 0,
			copperTotal = 0,
			items = {},
			kills = {},
		}
		db.mobs[name] = mob
	end
	if type(mob.items) ~= "table" then
		mob.items = {}
	end
	if type(mob.kills) ~= "table" then
		mob.kills = {}
	end
	return mob
end

local UNKNOWN_LOCATION = "Unknown"

--- Player map coords at loot time (0–1 zone fractions when possible).
--- Returns x, y, mapID (any may be nil if the client cannot resolve a position).
--- Never call SetMapToCurrentZone — that taints / blocks on some clients.
local function GetPlayerKillCoords()
	if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
		local mapID = C_Map.GetBestMapForUnit("player")
		if mapID then
			local pos = C_Map.GetPlayerMapPosition(mapID, "player")
			if pos then
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

	if GetPlayerMapPosition then
		local x, y = GetPlayerMapPosition("player")
		if type(x) == "number" and type(y) == "number" and (x ~= 0 or y ~= 0) then
			local mapID = GetCurrentMapAreaID and GetCurrentMapAreaID() or nil
			return x, y, mapID
		end
	end

	if UnitPosition then
		-- UnitPosition returns y, x, z, mapID (continent space).
		local y, x, _, mapID = UnitPosition("player")
		if type(x) == "number" and type(y) == "number" then
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

--- Smaller place inside a zone (Goldshire inside Elwynn Forest).
local function GetSubZoneName()
	local sub = GetSubZoneText and GetSubZoneText() or nil
	if type(sub) == "string" and sub ~= "" then
		return sub
	end
	return nil
end

local function ResolveMapName(mapID)
	if not mapID then
		return nil
	end
	if C_Map and C_Map.GetMapInfo then
		local info = C_Map.GetMapInfo(mapID)
		if info and type(info.name) == "string" and info.name ~= "" then
			return info.name
		end
	end
	if GetMapNameByID then
		local name = GetMapNameByID(mapID)
		if type(name) == "string" and name ~= "" then
			return name
		end
	end
	return nil
end

function MobLedger_GetKillLocation(kill)
	if type(kill) ~= "table" then
		return UNKNOWN_LOCATION
	end
	if type(kill.zone) == "string" and kill.zone ~= "" then
		return kill.zone
	end
	local fromMap = ResolveMapName(kill.map)
	if fromMap then
		return fromMap
	end
	return UNKNOWN_LOCATION
end

--- Most common kill zone for this mob (ties → alphabetical).
function MobLedger_GetMobLocation(mob)
	local kills = MobLedger_GetKills(mob)
	if #kills == 0 then
		return UNKNOWN_LOCATION
	end
	local counts = {}
	for _, kill in ipairs(kills) do
		local loc = MobLedger_GetKillLocation(kill)
		counts[loc] = (counts[loc] or 0) + 1
	end
	local best, bestCount
	for loc, count in pairs(counts) do
		if not best
			or count > bestCount
			or (count == bestCount and loc < best)
		then
			best = loc
			bestCount = count
		end
	end
	return best or UNKNOWN_LOCATION
end

function MobLedger_MobHasLocation(mob, location)
	if not location then
		return true
	end
	local kills = MobLedger_GetKills(mob)
	if #kills == 0 then
		return location == UNKNOWN_LOCATION
	end
	for _, kill in ipairs(kills) do
		if MobLedger_GetKillLocation(kill) == location then
			return true
		end
	end
	return false
end

local function RecordKillPosition(mob)
	local x, y, mapID = GetPlayerKillCoords()
	local zone = GetZoneName()
	local entry = {
		x = x,
		y = y,
	}
	if mapID ~= nil then
		entry.map = mapID
	end
	if zone then
		entry.zone = zone
	elseif mapID then
		entry.zone = ResolveMapName(mapID)
	end
	local subzone = GetSubZoneName()
	if subzone and subzone ~= entry.zone then
		entry.subzone = subzone
	end
	mob.kills[#mob.kills + 1] = entry
	if x and y then
		log:Debug(
			"kill pos",
			string.format("%.4f, %.4f", x, y),
			"zone=",
			entry.zone or "?",
			"map=",
			mapID or "?"
		)
	else
		log:Debug("kill pos unavailable", "zone=", entry.zone or "?")
	end
end

--- Format copper as "1g 2s 3c" (omits zero higher denominations when possible).
function MobLedger_FormatCopper(copper)
	copper = math.floor(tonumber(copper) or 0)
	if copper < 0 then
		copper = 0
	end
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	if g > 0 then
		return string.format("%dg %ds %dc", g, s, c)
	end
	if s > 0 then
		return string.format("%ds %dc", s, c)
	end
	return string.format("%dc", c)
end

function MobLedger_GetMobNames(location)
	local db = EnsureDB()
	local names = {}
	for name, mob in pairs(db.mobs) do
		if MobLedger_MobHasLocation(mob, location) then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names
end

--- Sorted unique zone names present in the ledger.
function MobLedger_GetLocationNames()
	local db = EnsureDB()
	local seen = {}
	local names = {}
	for _, mob in pairs(db.mobs) do
		local kills = MobLedger_GetKills(mob)
		if #kills == 0 then
			if not seen[UNKNOWN_LOCATION] then
				seen[UNKNOWN_LOCATION] = true
				names[#names + 1] = UNKNOWN_LOCATION
			end
		else
			for _, kill in ipairs(kills) do
				local loc = MobLedger_GetKillLocation(kill)
				if not seen[loc] then
					seen[loc] = true
					names[#names + 1] = loc
				end
			end
		end
	end
	table.sort(names)
	return names
end

function MobLedger_IsMobHidden(name)
	return EnsureDB().hiddenMobs[name] and true or false
end

function MobLedger_IsLocationHidden(location)
	return EnsureDB().hiddenLocations[location] and true or false
end

function MobLedger_SetMobHidden(name, hidden)
	local db = EnsureDB()
	if hidden then
		db.hiddenMobs[name] = true
	else
		db.hiddenMobs[name] = nil
	end
	log:Info(hidden and "hid mob" or "unhid mob", name)
end

local UNKNOWN_AREA = "Unknown"

function MobLedger_AreaKey(zone, area)
	return tostring(zone or "?") .. "\31" .. tostring(area or "?")
end

function MobLedger_GetKillArea(kill)
	if type(kill) == "table" and type(kill.subzone) == "string" and kill.subzone ~= "" then
		return kill.subzone
	end
	return UNKNOWN_AREA
end

--- Most common area for this mob inside a zone (or across all kills).
function MobLedger_GetMobArea(mob, zone)
	local kills = MobLedger_GetKills(mob)
	local counts = {}
	for _, kill in ipairs(kills) do
		if not zone or MobLedger_GetKillLocation(kill) == zone then
			local area = MobLedger_GetKillArea(kill)
			counts[area] = (counts[area] or 0) + 1
		end
	end
	local best, bestCount
	for area, count in pairs(counts) do
		if not best or count > bestCount or (count == bestCount and area < best) then
			best = area
			bestCount = count
		end
	end
	return best or UNKNOWN_AREA
end

function MobLedger_MobInArea(mob, zone, area)
	local kills = MobLedger_GetKills(mob)
	if #kills == 0 then
		return zone == UNKNOWN_LOCATION and area == UNKNOWN_AREA
	end
	for _, kill in ipairs(kills) do
		if MobLedger_GetKillLocation(kill) == zone and MobLedger_GetKillArea(kill) == area then
			return true
		end
	end
	return false
end

function MobLedger_GetAreaNames(zone)
	local db = EnsureDB()
	local seen = {}
	local names = {}
	local any = false
	for _, mob in pairs(db.mobs) do
		for _, kill in ipairs(MobLedger_GetKills(mob)) do
			if MobLedger_GetKillLocation(kill) == zone then
				any = true
				local area = MobLedger_GetKillArea(kill)
				if not seen[area] then
					seen[area] = true
					names[#names + 1] = area
				end
			end
		end
	end
	if not any and not seen[UNKNOWN_AREA] then
		names[#names + 1] = UNKNOWN_AREA
	end
	table.sort(names)
	return names
end

function MobLedger_GetMobNamesInArea(zone, area)
	local db = EnsureDB()
	local names = {}
	for name, mob in pairs(db.mobs) do
		if MobLedger_MobInArea(mob, zone, area) then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names
end

function MobLedger_IsAreaHidden(zone, area)
	return EnsureDB().hiddenAreas[MobLedger_AreaKey(zone, area)] and true or false
end

function MobLedger_SetAreaHidden(zone, area, hidden)
	local db = EnsureDB()
	local key = MobLedger_AreaKey(zone, area)
	if hidden then
		db.hiddenAreas[key] = true
	else
		db.hiddenAreas[key] = nil
	end
	log:Info(hidden and "hid area" or "unhid area", zone, area)
end

function MobLedger_GetVisibleAreaNames(zone)
	local names = {}
	for _, area in ipairs(MobLedger_GetAreaNames(zone)) do
		if not MobLedger_IsAreaHidden(zone, area) then
			names[#names + 1] = area
		end
	end
	return names
end

function MobLedger_GetHiddenAreaNames(zone)
	local names = {}
	for _, area in ipairs(MobLedger_GetAreaNames(zone)) do
		if MobLedger_IsAreaHidden(zone, area) then
			names[#names + 1] = area
		end
	end
	return names
end

function MobLedger_GetVisibleMobNamesInArea(zone, area)
	local names = {}
	for _, name in ipairs(MobLedger_GetMobNamesInArea(zone, area)) do
		if not MobLedger_IsMobHidden(name) then
			names[#names + 1] = name
		end
	end
	return names
end

function MobLedger_IsAreaExpanded(zone, area)
	local v = EnsureDB().ui.expanded[MobLedger_AreaKey(zone, area)]
	if v == nil then
		return true
	end
	return v and true or false
end

function MobLedger_SetAreaExpanded(zone, area, expanded)
	EnsureDB().ui.expanded[MobLedger_AreaKey(zone, area)] = expanded and true or false
end

function MobLedger_SetLocationHidden(location, hidden)
	local db = EnsureDB()
	if hidden then
		db.hiddenLocations[location] = true
	else
		db.hiddenLocations[location] = nil
	end
	log:Info(hidden and "hid location" or "unhid location", location)
end

function MobLedger_GetHiddenMobNames()
	local db = EnsureDB()
	local names = {}
	for name in pairs(db.hiddenMobs) do
		if db.mobs[name] then
			names[#names + 1] = name
		else
			db.hiddenMobs[name] = nil
		end
	end
	table.sort(names)
	return names
end

function MobLedger_GetHiddenLocationNames()
	local db = EnsureDB()
	local present = {}
	for _, loc in ipairs(MobLedger_GetLocationNames()) do
		present[loc] = true
	end
	local names = {}
	for loc in pairs(db.hiddenLocations) do
		if present[loc] then
			names[#names + 1] = loc
		else
			db.hiddenLocations[loc] = nil
		end
	end
	table.sort(names)
	return names
end

--- Visible (non-hidden) locations, sorted.
function MobLedger_GetVisibleLocationNames()
	local names = {}
	for _, loc in ipairs(MobLedger_GetLocationNames()) do
		if not MobLedger_IsLocationHidden(loc) then
			names[#names + 1] = loc
		end
	end
	return names
end

--- Mobs in a location that are not individually hidden.
function MobLedger_GetVisibleMobNames(location)
	local names = {}
	for _, name in ipairs(MobLedger_GetMobNames(location)) do
		if not MobLedger_IsMobHidden(name) then
			names[#names + 1] = name
		end
	end
	return names
end

function MobLedger_IsLocationExpanded(location)
	local db = EnsureDB()
	local v = db.ui.expanded[location]
	if v == nil then
		return true
	end
	return v and true or false
end

function MobLedger_SetLocationExpanded(location, expanded)
	EnsureDB().ui.expanded[location] = expanded and true or false
end

function MobLedger_IsHiddenSectionExpanded()
	return EnsureDB().ui.hiddenExpanded and true or false
end

function MobLedger_SetHiddenSectionExpanded(expanded)
	EnsureDB().ui.hiddenExpanded = expanded and true or false
end

function MobLedger_GetMob(name)
	return EnsureDB().mobs[name]
end

--- mobCount, lootCount, copperTotal across the whole ledger.
function MobLedger_GetTotals()
	local mobs, loots, copper = 0, 0, 0
	for _, mob in pairs(EnsureDB().mobs) do
		mobs = mobs + 1
		loots = loots + (mob.loots or 0)
		copper = copper + (mob.copperTotal or 0)
	end
	return mobs, loots, copper
end

function MobLedger_GetDropRate(mob, itemKey)
	if not mob or not mob.loots or mob.loots <= 0 then
		return 0
	end
	local item = mob.items and mob.items[itemKey]
	if not item or not item.drops then
		return 0
	end
	return (item.drops / mob.loots) * 100
end

function MobLedger_GetAverageCopper(mob)
	if not mob or not mob.loots or mob.loots <= 0 then
		return 0
	end
	return mob.copperTotal / mob.loots
end

function MobLedger_ResetAll()
	MobLedgerDB = {
		version = 3,
		mobs = {},
		hiddenMobs = {},
		hiddenLocations = {},
		hiddenAreas = {},
		sellPrices = {},
		ui = { expanded = {}, hiddenExpanded = false },
	}
	seenGuids = {}
	log:Info("ledger cleared")
end

function MobLedger_ResetMob(name)
	local db = EnsureDB()
	if db.mobs[name] then
		db.mobs[name] = nil
		db.hiddenMobs[name] = nil
		log:Info("cleared", name)
		return true
	end
	return false
end

local function SeedItemLink(id, name, quality)
	local hex = "ffffff"
	if quality == 0 then
		hex = "9d9d9d"
	elseif quality == 2 then
		hex = "1eff00"
	elseif quality == 3 then
		hex = "0070dd"
	end
	return string.format("|cff%s|Hitem:%d::::::::1:::::::|h[%s]|h|r", hex, id, name)
end

--- Replace the ledger with sample zones, subzones, drops, and vendor prices.
--- Development only. Returns false when DevMode is off.
function MobLedger_Seed()
	if not WoWF.DevMode then
		return false
	end
	MobLedger_ResetAll()

	local linen = "Interface\\Icons\\INV_Fabric_Linen_01"
	local wool = "Interface\\Icons\\INV_Fabric_Wool_01"
	local silk = "Interface\\Icons\\INV_Fabric_Silk_01"
	local scrap = "Interface\\Icons\\INV_Misc_LeatherScrap_01"
	local meat = "Interface\\Icons\\INV_Misc_Food_14"
	local ore = "Interface\\Icons\\INV_Ore_Copper_01"
	local stone = "Interface\\Icons\\INV_Stone_05"
	local potion = "Interface\\Icons\\INV_Potion_49"
	local gem = "Interface\\Icons\\INV_Misc_Gem_Emerald_02"
	local claw = "Interface\\Icons\\INV_Misc_MonsterClaw_01"
	local bone = "Interface\\Icons\\INV_Misc_Bone_01"

	local function item(name, id, icon, quality, drops, qty, sell)
		return {
			name = name,
			id = id,
			icon = icon,
			quality = quality,
			drops = drops,
			qty = qty,
			sell = sell,
		}
	end

	local function add(spec)
		local mob = GetOrCreateMob(spec.name)
		mob.loots = spec.loots
		mob.copperTotal = spec.copper
		mob.kills = {}
		mob.items = {}
		for i = 1, spec.kills do
			mob.kills[i] = {
				x = spec.x + i * 0.011,
				y = spec.y + i * 0.007,
				zone = spec.zone,
				subzone = spec.subzone,
			}
		end
		for _, it in ipairs(spec.items) do
			mob.items[it.name] = {
				name = it.name,
				link = SeedItemLink(it.id, it.name, it.quality),
				itemId = it.id,
				icon = it.icon,
				quality = it.quality,
				drops = it.drops,
				quantity = it.qty,
				sellPrice = it.sell,
			}
		end
	end

	add({
		name = "Kobold Vermin", zone = "Elwynn Forest", subzone = "Northshire Valley",
		loots = 28, copper = 1460, kills = 6, x = 0.48, y = 0.42,
		items = {
			item("Linen Cloth", 2589, linen, 1, 12, 18, 13),
			item("Rough Stone", 2835, stone, 1, 7, 9, 4),
			item("Copper Ore", 2770, ore, 1, 3, 3, 10),
		},
	})
	add({
		name = "Kobold Worker", zone = "Elwynn Forest", subzone = "Northshire Valley",
		loots = 16, copper = 820, kills = 4, x = 0.50, y = 0.40,
		items = {
			item("Linen Cloth", 2589, linen, 1, 6, 8, 13),
			item("Copper Ore", 2770, ore, 1, 5, 6, 10),
			item("Malachite", 774, gem, 2, 1, 1, 150),
		},
	})
	add({
		name = "Mangy Wolf", zone = "Elwynn Forest", subzone = "Goldshire",
		loots = 22, copper = 640, kills = 5, x = 0.42, y = 0.66,
		items = {
			item("Ruined Leather Scraps", 2934, scrap, 0, 14, 20, 5),
			item("Stringy Wolf Meat", 2672, meat, 1, 9, 9, 4),
		},
	})
	add({
		name = "Young Wolf", zone = "Elwynn Forest", subzone = "Goldshire",
		loots = 11, copper = 210, kills = 3, x = 0.44, y = 0.68,
		items = {
			item("Stringy Wolf Meat", 2672, meat, 1, 6, 6, 4),
			item("Ruined Leather Scraps", 2934, scrap, 0, 4, 5, 5),
		},
	})
	add({
		name = "Prowler", zone = "Elwynn Forest", subzone = "Eastvale Logging Camp",
		loots = 19, copper = 2310, kills = 5, x = 0.80, y = 0.62,
		items = {
			item("Light Leather", 2318, scrap, 1, 8, 8, 20),
			item("Chunk of Boar Meat", 769, meat, 1, 7, 7, 3),
			item("Minor Healing Potion", 118, potion, 1, 2, 2, 25),
		},
	})
	add({
		name = "Defias Thug", zone = "Westfall", subzone = "The Jansen Stead",
		loots = 34, copper = 5120, kills = 7, x = 0.56, y = 0.32,
		items = {
			item("Linen Cloth", 2589, linen, 1, 18, 30, 13),
			item("Wool Cloth", 2592, wool, 1, 6, 7, 33),
			item("Minor Healing Potion", 118, potion, 1, 4, 4, 25),
		},
	})
	add({
		name = "Harvest Watcher", zone = "Westfall", subzone = "The Jansen Stead",
		loots = 15, copper = 980, kills = 4, x = 0.54, y = 0.35,
		items = {
			item("Rough Stone", 2835, stone, 1, 9, 14, 4),
			item("Copper Ore", 2770, ore, 1, 2, 2, 10),
			item("Healing Potion", 929, potion, 1, 1, 1, 100),
		},
	})
	add({
		name = "Murloc Coastrunner", zone = "Westfall", subzone = "Longshore",
		loots = 26, copper = 1740, kills = 6, x = 0.38, y = 0.72,
		items = {
			item("Raw Brilliant Smallfish", 6291, meat, 1, 11, 11, 5),
			item("Clam Meat", 5503, meat, 1, 5, 5, 8),
			item("Minor Healing Potion", 118, potion, 1, 2, 2, 25),
		},
	})
	add({
		name = "Murloc Netter", zone = "Westfall", subzone = "Longshore",
		loots = 12, copper = 460, kills = 3, x = 0.36, y = 0.74,
		items = {
			item("Raw Brilliant Smallfish", 6291, meat, 1, 4, 4, 5),
			item("Linen Cloth", 2589, linen, 1, 3, 3, 13),
		},
	})
	add({
		name = "Ravenous Dire Wolf", zone = "Duskwood", subzone = "Darkshire",
		loots = 20, copper = 8640, kills = 5, x = 0.74, y = 0.46,
		items = {
			item("Silk Cloth", 4306, silk, 1, 4, 4, 150),
			item("Lean Wolf Meat", 1015, meat, 1, 10, 10, 16),
			item("Sharp Claw", 5635, claw, 1, 6, 6, 45),
		},
	})
	add({
		name = "Skeletal Warrior", zone = "Duskwood", subzone = "Raven Hill Cemetery",
		loots = 18, copper = 3200, kills = 4, x = 0.20, y = 0.44,
		items = {
			item("Bone Fragments", 22526, bone, 1, 9, 16, 25),
			item("Wool Cloth", 2592, wool, 1, 5, 6, 33),
			item("Healing Potion", 929, potion, 1, 2, 2, 100),
		},
	})
	add({
		name = "Skeletal Horror", zone = "Duskwood", subzone = "Raven Hill Cemetery",
		loots = 9, copper = 14000, kills = 3, x = 0.22, y = 0.47,
		items = {
			item("Silk Cloth", 4306, silk, 1, 3, 3, 150),
			item("Bone Fragments", 22526, bone, 1, 4, 8, 25),
			item("Malachite", 774, gem, 2, 1, 1, 150),
		},
	})

	MobLedger_SetMobHidden("Defias Thug", true)
	MobLedger_SetAreaHidden("Duskwood", "Raven Hill Cemetery", true)
	MobLedger_SetHiddenSectionExpanded(true)
	log:Info("seeded sample ledger")
	return true
end

function MobLedger_GetKills(mob)
	if not mob or type(mob.kills) ~= "table" then
		return {}
	end
	return mob.kills
end

function MobLedger_FormatCoords(kill)
	if not kill or type(kill.x) ~= "number" or type(kill.y) ~= "number" then
		return "—"
	end
	-- Map fractions → percent; continent coords stay absolute.
	if kill.x >= 0 and kill.x <= 1 and kill.y >= 0 and kill.y <= 1 then
		return string.format("%.1f, %.1f", kill.x * 100, kill.y * 100)
	end
	return string.format("%.1f, %.1f", kill.x, kill.y)
end

local function ParseMoneyText(text)
	if type(text) ~= "string" or text == "" then
		return 0
	end
	local copper = 0
	local g = text:match("(%d+)%s+[Gg]old")
	local s = text:match("(%d+)%s+[Ss]ilver")
	local c = text:match("(%d+)%s+[Cc]opper")
	if g then
		copper = copper + tonumber(g) * 10000
	end
	if s then
		copper = copper + tonumber(s) * 100
	end
	if c then
		copper = copper + tonumber(c)
	end
	return copper
end

local function IsMoneySlot(slot, itemName, link)
	if GetLootSlotType and LOOT_SLOT_MONEY then
		local slotType = GetLootSlotType(slot)
		if slotType == LOOT_SLOT_MONEY then
			return true
		end
		if slotType == LOOT_SLOT_ITEM or (LOOT_SLOT_CURRENCY and slotType == LOOT_SLOT_CURRENCY) then
			return false
		end
	end
	if link then
		return false
	end
	-- Coin rows usually look like "12 Copper" / "1 Silver" (leading digits).
	return type(itemName) == "string" and itemName:find("^%d+") ~= nil
end

local function ItemIdFromLink(link)
	if type(link) ~= "string" then
		return nil
	end
	return tonumber(link:match("item:(%d+)"))
end

--- Last unit price learned by selling this item to a vendor. Wins over a loot-time guess.
local function VendorPriceFor(itemId)
	itemId = tonumber(itemId)
	if not itemId then
		return nil
	end
	local price = EnsureDB().sellPrices[tostring(itemId)]
	if type(price) == "number" and price > 0 then
		return price
	end
	return nil
end

local function ItemNameFromLink(link)
	if type(link) ~= "string" then
		return nil
	end
	return link:match("%[(.-)%]")
end

local priceTip

local function PriceTooltip()
	if priceTip then
		return priceTip
	end
	local ok, tip = pcall(CreateFrame, "GameTooltip", "MobLedgerPriceTip", UIParent, "GameTooltipTemplate")
	if not ok or not tip then
		return nil
	end
	priceTip = tip
	return tip
end

local function ReadTooltipMoney(tip)
	local name = tip:GetName()
	if not name then
		return nil
	end
	-- The coin frame is often hidden while its parent tooltip is hidden.
	-- staticMoney is still set, so do not require IsShown.
	for i = 1, 6 do
		local money = _G[name .. "MoneyFrame" .. i]
		if money and type(money.staticMoney) == "number" and money.staticMoney > 0 then
			return money.staticMoney
		end
	end
	if tip.GetChildren then
		local children = { tip:GetChildren() }
		for _, child in ipairs(children) do
			if type(child.staticMoney) == "number" and child.staticMoney > 0 then
				return child.staticMoney
			end
		end
	end
	local lines = tip.NumLines and tip:NumLines() or 0
	for i = 1, lines do
		local fs = _G[name .. "TextLeft" .. i]
		local text = fs and fs.GetText and fs:GetText()
		if type(text) == "string" and (text:find("Gold") or text:find("Silver") or text:find("Copper") or text:find("Sell Price")) then
			local copper = ParseMoneyText(text)
			if copper > 0 then
				return copper
			end
		end
	end
	return nil
end

--- Vendor copper shown on an item tooltip. kind is "loot", "bag", or "link".
local function SellPriceFromTooltip(kind, a, b)
	local tip = PriceTooltip()
	if not tip then
		return nil
	end
	tip:SetOwner(UIParent, "ANCHOR_NONE")
	local ok = pcall(function()
		if kind == "loot" and tip.SetLootItem then
			tip:SetLootItem(a)
		elseif kind == "bag" and tip.SetBagItem then
			tip:SetBagItem(a, b)
		elseif kind == "link" and a and tip.SetHyperlink then
			tip:SetHyperlink(a)
		end
	end)
	if not ok then
		tip:Hide()
		return nil
	end
	-- OnTooltipAddMoney does not run until the tooltip is shown.
	tip:SetAlpha(0)
	tip:Show()
	local price = ReadTooltipMoney(tip)
	tip:Hide()
	tip:SetAlpha(1)
	return price
end

--- Vendor copper for one item, or nil if the client has not cached it.
local function LookupItemSellPrice(itemRef)
	if not itemRef then
		return nil
	end
	-- C_Item.GetItemInfo returns a table on some clients and the classic
	-- multi-value list (vendor price is the 11th) on others. The global
	-- GetItemInfo may not exist at all. Same handling as JunkMaster.
	local sellPrice
	if C_Item and C_Item.GetItemInfo then
		local first, _, _, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(itemRef)
		if type(first) == "table" then
			price = first.sellPrice
		end
		sellPrice = price
	end
	if type(sellPrice) ~= "number" and GetItemInfo then
		local _, _, _, _, _, _, _, _, _, _, price = GetItemInfo(itemRef)
		sellPrice = price
	end
	if type(sellPrice) == "number" and sellPrice > 0 then
		return sellPrice
	end
	if type(itemRef) == "string" and itemRef:find("item:", 1, true) then
		return SellPriceFromTooltip("link", itemRef)
	end
	return nil
end

local function RequestItemData(itemId, link)
	if itemId and C_Item and C_Item.RequestLoadItemDataByID then
		C_Item.RequestLoadItemDataByID(itemId)
	end
	if GetItemInfo then
		GetItemInfo(link or itemId)
	end
end

local function ContainerItemLink(bag, slot)
	if C_Container and C_Container.GetContainerItemLink then
		return C_Container.GetContainerItemLink(bag, slot)
	end
	if GetContainerItemLink then
		return GetContainerItemLink(bag, slot)
	end
	return nil
end

local function ContainerNumSlots(bag)
	if C_Container and C_Container.GetContainerNumSlots then
		return C_Container.GetContainerNumSlots(bag) or 0
	end
	if GetContainerNumSlots then
		return GetContainerNumSlots(bag) or 0
	end
	return 0
end

--- The link now sitting in a bag, which is the reliable handle once the item is picked up.
local function FindBagLink(itemId, itemName)
	for bag = 0, 4 do
		for slot = 1, ContainerNumSlots(bag) do
			local link = ContainerItemLink(bag, slot)
			if link then
				if itemId and ItemIdFromLink(link) == itemId then
					return link, bag, slot
				end
				if itemName and ItemNameFromLink(link) == itemName then
					return link, bag, slot
				end
			end
		end
	end
	return nil
end

--- Loot window currently open, plus a short tail so pickup chat can still match.
local openLoot
local recentLoot
local recentUntil = 0
local pendingSell = {}
local sellRetryAt = 0
local eventFrame
local RetryPendingSellPrices

local function ActiveLoot()
	if openLoot then
		return openLoot
	end
	if recentLoot and GetTime() <= recentUntil then
		return recentLoot
	end
	return nil
end

local function RegisterLootSlot(mob, slot)
	local texture, itemName, quantity, qualityOrCurrency, qualityAlt = GetLootSlotInfo(slot)
	if not itemName then
		return
	end

	-- Classic: texture, item, quantity, quality
	-- Later:   texture, item, quantity, currencyID, quality, ...
	local quality = qualityOrCurrency
	if type(qualityAlt) == "number" then
		quality = qualityAlt
	end
	quantity = tonumber(quantity) or 1
	if quantity < 1 then
		quantity = 1
	end

	local link = GetLootSlotLink and GetLootSlotLink(slot) or nil
	local itemId = ItemIdFromLink(link)

	if IsMoneySlot(slot, itemName, link) then
		local copper = ParseMoneyText(itemName)
		if copper > 0 then
			mob.copperTotal = (mob.copperTotal or 0) + copper
			log:Debug("money", copper, "from", itemName)
		end
		return
	end

	-- Key by plain name so drop rates stay stable across link variants.
	local key = itemName
	local entry = mob.items[key]
	if not entry then
		entry = {
			name = itemName,
			link = link,
			itemId = itemId,
			icon = texture,
			quality = quality or 1,
			drops = 0,
			quantity = 0,
		}
		mob.items[key] = entry
	else
		entry.name = itemName or entry.name
		entry.link = link or entry.link
		entry.itemId = itemId or entry.itemId
		if texture then
			entry.icon = texture
		end
		if quality then
			entry.quality = quality
		end
	end

	local sellPrice = VendorPriceFor(itemId)
		or SellPriceFromTooltip("loot", slot)
		or LookupItemSellPrice(link or itemId or itemName)
	if sellPrice then
		entry.sellPrice = sellPrice
	end

	entry.drops = entry.drops + 1
	entry.quantity = entry.quantity + quantity
	log:Debug("item", key, "x" .. quantity)

	if openLoot then
		openLoot.slots[slot] = {
			key = key,
			link = link,
			itemId = itemId,
		}
	end
end

--- Write the vendor price onto a recorded item. True when nothing is left to do.
local function StoreSellPrice(mobName, key, link, itemId)
	local mob = EnsureDB().mobs[mobName]
	local entry = mob and mob.items and mob.items[key]
	if not entry then
		return true
	end
	local vendor = VendorPriceFor(itemId or entry.itemId)
	if vendor then
		entry.sellPrice = vendor
		return true
	end
	if type(entry.sellPrice) == "number" and entry.sellPrice > 0 then
		return true
	end
	local foundLink, bag, bagSlot = FindBagLink(itemId or entry.itemId, entry.name or key)
	link = link or foundLink
	if link then
		entry.link = link
	end
	itemId = itemId or entry.itemId or ItemIdFromLink(entry.link)
	if itemId then
		entry.itemId = itemId
	end
	-- The bag item tooltip carries the vendor price before GetItemInfo is cached.
	local price
	if bag then
		price = SellPriceFromTooltip("bag", bag, bagSlot)
	end
	if not price then
		price = LookupItemSellPrice(entry.link or entry.itemId or entry.name)
	end
	if price then
		entry.sellPrice = price
		log:Debug("sell price", key, price)
		return true
	end
	RequestItemData(entry.itemId, entry.link)
	return false
end

local function QueueSellPrice(mobName, key, link, itemId)
	if not mobName or not key then
		return
	end
	local id = tostring(itemId or key)
	local job = pendingSell[id]
	if job then
		job.link = link or job.link
		job.itemId = itemId or job.itemId
	else
		pendingSell[id] = {
			mobName = mobName,
			key = key,
			link = link,
			itemId = itemId,
			tries = 0,
		}
	end
	sellRetryAt = GetTime() + 0.25
	if eventFrame then
		eventFrame:SetScript("OnUpdate", RetryPendingSellPrices)
	end
end

RetryPendingSellPrices = function(self)
	if GetTime() < sellRetryAt then
		return
	end
	sellRetryAt = GetTime() + 0.4
	local stored = false
	local waiting = false
	for id, job in pairs(pendingSell) do
		job.tries = (job.tries or 0) + 1
		if StoreSellPrice(job.mobName, job.key, job.link, job.itemId) then
			pendingSell[id] = nil
			stored = true
		elseif job.tries >= 20 then
			pendingSell[id] = nil
			log:Debug("sell price unavailable", job.key)
		else
			waiting = true
		end
	end
	if stored and MobLedgerJournal_Refresh then
		MobLedgerJournal_Refresh()
	end
	if not waiting then
		self:SetScript("OnUpdate", nil)
	end
end

local function RecordPickupPrice(key, link, itemId)
	local window = ActiveLoot()
	if not window or not key then
		return
	end
	if StoreSellPrice(window.mobName, key, link, itemId) then
		if MobLedgerJournal_Refresh then
			MobLedgerJournal_Refresh()
		end
	else
		QueueSellPrice(window.mobName, key, link, itemId)
	end
end

local function OnLootSlotCleared(slot)
	slot = tonumber(slot)
	if not openLoot or not slot then
		return
	end
	local rec = openLoot.slots[slot]
	if not rec then
		return
	end
	local link, bag, bagSlot = FindBagLink(rec.itemId, rec.key)
	link = link or rec.link
	if bag then
		local price = SellPriceFromTooltip("bag", bag, bagSlot)
		local mob = EnsureDB().mobs[openLoot.mobName]
		local entry = mob and mob.items and mob.items[rec.key]
		if price and entry then
			entry.sellPrice = price
			entry.link = link or entry.link
		end
	end
	RecordPickupPrice(rec.key, link, rec.itemId)
end

--- Only the player's own "you receive loot" line, not party loot.
local function SelfLootLink(msg)
	if type(msg) ~= "string" then
		return nil
	end
	local link = msg:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)") or msg:match("(|Hitem:.-|h%[.-%]|h|r)")
	if not link then
		return nil
	end
	local function prefixOf(fmt)
		if type(fmt) ~= "string" then
			return nil
		end
		return fmt:match("^(.-)%%[sd]")
	end
	local matched = false
	local hadPrefix = false
	for _, fmt in ipairs({ LOOT_ITEM_SELF, LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_CREATED_SELF }) do
		local prefix = prefixOf(fmt)
		if prefix and prefix ~= "" then
			hadPrefix = true
			if msg:find(prefix, 1, true) then
				matched = true
			end
		end
	end
	if hadPrefix and not matched then
		return nil
	end
	if not hadPrefix and not msg:find("^You receive") then
		return nil
	end
	return link
end

local function EntryForLink(mob, link)
	if not mob or type(mob.items) ~= "table" then
		return nil
	end
	local itemId = ItemIdFromLink(link)
	local name = ItemNameFromLink(link)
	if itemId then
		for key, entry in pairs(mob.items) do
			if entry.itemId == itemId or ItemIdFromLink(entry.link) == itemId then
				return key, itemId
			end
		end
	end
	if name and mob.items[name] then
		return name, itemId
	end
	return nil
end

local function OnChatLoot(msg)
	local window = ActiveLoot()
	if not window then
		return
	end
	local link = SelfLootLink(msg)
	if not link then
		return
	end
	local mob = EnsureDB().mobs[window.mobName]
	local key, itemId = EntryForLink(mob, link)
	if key then
		RecordPickupPrice(key, link, itemId)
	end
end

local function OnItemInfo(itemId)
	itemId = tonumber(itemId)
	if not itemId then
		return
	end
	local foundId, job
	for id, candidate in pairs(pendingSell) do
		if candidate.itemId == itemId or id == tostring(itemId) then
			foundId, job = id, candidate
			break
		end
	end
	if not job then
		return
	end
	if StoreSellPrice(job.mobName, job.key, job.link, itemId) then
		pendingSell[foundId] = nil
		if MobLedgerJournal_Refresh then
			MobLedgerJournal_Refresh()
		end
	end
end

--- Creature/NPC id from a unit GUID (for portrait / model).
local function CreatureIdFromGuid(guid)
	if type(guid) ~= "string" or guid == "" then
		return nil
	end
	local parts = {}
	for part in string.gmatch(guid, "[^-]+") do
		parts[#parts + 1] = part
	end
	local kind = parts[1]
	if kind == "Creature" or kind == "Vehicle" or kind == "Pet" then
		return tonumber(parts[6])
	end
	-- Fallback: last numeric field before spawn hex.
	return tonumber(guid:match("%-(%d+)%-%x+$"))
end

--- Stored vendor price, or a live lookup from the link/name.
function MobLedger_GetItemSellPrice(item)
	if type(item) ~= "table" then
		return nil
	end
	local vendor = VendorPriceFor(item.itemId or ItemIdFromLink(item.link))
	if vendor then
		item.sellPrice = vendor
		return vendor
	end
	if type(item.sellPrice) == "number" and item.sellPrice > 0 then
		return item.sellPrice
	end
	local price = LookupItemSellPrice(item.link or item.itemId or item.name)
	if price then
		item.sellPrice = price
	end
	return price
end

function MobLedger_ResolveItemIcon(item)
	if type(item) ~= "table" then
		return nil
	end
	if type(item.icon) == "string" or type(item.icon) == "number" then
		return item.icon
	end
	local ref = item.link or item.name
	if not ref then
		return nil
	end
	if GetItemIcon then
		local icon = GetItemIcon(ref)
		if icon then
			return icon
		end
	end
	if GetItemInfo then
		local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(ref)
		return tex
	end
	return nil
end

--- Session portrait textures (SetPortraitTexture cannot be serialized to SavedVariables).
local portraitHolders = {}

local function GetPortraitHolder(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local holder = portraitHolders[name]
	if holder then
		return holder
	end
	holder = CreateFrame("Frame", nil, UIParent)
	holder:SetSize(64, 64)
	holder:Hide()
	holder.tex = holder:CreateTexture(nil, "ARTWORK")
	holder.tex:SetAllPoints()
	holder.tex.holder = holder
	portraitHolders[name] = holder
	return holder
end

--- Snapshot the current target's face into a session-stable texture for this mob.
function MobLedger_CaptureUnitPortrait(name, unit)
	unit = unit or "target"
	if type(name) ~= "string" or name == "" then
		return false
	end
	if not UnitExists(unit) then
		return false
	end
	if not SetPortraitTexture then
		return false
	end
	local holder = GetPortraitHolder(name)
	if not holder then
		return false
	end
	-- Park on the holder before painting so we never lose the owner frame.
	holder.tex:SetParent(holder)
	holder.tex:SetAllPoints(holder)
	SetPortraitTexture(holder.tex, unit)
	holder.captured = true
	log:Debug("portrait captured", name)
	return true
end

function MobLedger_HasCapturedPortrait(name)
	local holder = portraitHolders[name]
	return holder and holder.captured or false
end

--- Returns the session texture for a mob portrait, or nil.
function MobLedger_GetCapturedPortraitTexture(name)
	local holder = portraitHolders[name]
	if holder and holder.captured then
		return holder.tex
	end
	return nil
end

local function CaptureMobPortrait(mob, name)
	if not mob then
		return
	end
	local guid = UnitGUID("target")
	if guid then
		mob.guid = guid
	end
	local npcId = CreatureIdFromGuid(guid)
	if npcId then
		mob.npcId = npcId
	end
	if UnitDisplayID then
		local displayId = UnitDisplayID("target")
		if displayId and displayId > 0 then
			mob.displayId = displayId
		end
	end
	if name then
		MobLedger_CaptureUnitPortrait(name, "target")
	end
end

local function OnLootOpened()
	if not UnitExists("target") or not UnitIsDead("target") then
		log:Debug("loot opened but target is not a dead unit")
		return
	end

	local guid = UnitGUID("target")
	if guid then
		if seenGuids[guid] then
			log:Debug("already counted guid", guid)
			return
		end
		seenGuids[guid] = true
	end

	local name = UnitName("target")
	if not name or name == "" then
		log:Warn("loot opened but target has no name")
		return
	end

	local mob = GetOrCreateMob(name)
	mob.loots = (mob.loots or 0) + 1
	CaptureMobPortrait(mob, name)
	RecordKillPosition(mob)

	openLoot = { mobName = name, slots = {} }

	local num = GetNumLootItems and GetNumLootItems() or 0
	for slot = 1, num do
		local hasItem = true
		if LootSlotHasItem then
			hasItem = LootSlotHasItem(slot)
		end
		if hasItem then
			RegisterLootSlot(mob, slot)
		end
	end

	log:Debug("recorded loot for", name, "loots=", mob.loots, "slots=", num)
	for _, rec in pairs(openLoot.slots) do
		local entry = mob.items[rec.key]
		if entry and not (type(entry.sellPrice) == "number" and entry.sellPrice > 0) then
			QueueSellPrice(name, rec.key, rec.link, rec.itemId)
		end
	end
	if MobLedgerJournal_Refresh then
		MobLedgerJournal_Refresh()
	end
end

--- Selling puts the stack on the buyback list. Its price is what the vendor paid.
local buybackSeen

local function BuybackLimit()
	if GetNumBuybackItems then
		local count = GetNumBuybackItems()
		if type(count) == "number" and count > 0 then
			return count
		end
	end
	if type(BUYBACK_ITEMS_PER_PAGE) == "number" and BUYBACK_ITEMS_PER_PAGE > 0 then
		return BUYBACK_ITEMS_PER_PAGE
	end
	return 12
end

local function ReadBuybackSlot(slot)
	local name, price, quantity, link
	if GetBuybackItemInfo then
		local info = GetBuybackItemInfo(slot)
		if type(info) == "table" then
			name = info.name
			price = info.price
			quantity = info.quantity
			link = info.hyperlink or info.link
		else
			name, _, price, quantity = GetBuybackItemInfo(slot)
		end
	end
	if GetBuybackItemLink then
		local itemLink = GetBuybackItemLink(slot)
		if type(itemLink) == "string" then
			link = itemLink
		end
	end
	if type(name) ~= "string" and type(link) ~= "string" then
		return nil
	end
	quantity = math.floor(tonumber(quantity) or 1)
	if quantity < 1 then
		quantity = 1
	end
	return {
		name = type(name) == "string" and name or ItemNameFromLink(link),
		itemID = ItemIdFromLink(link),
		link = type(link) == "string" and link or nil,
		count = quantity,
		price = tonumber(price) or 0,
	}
end

local function CollectBuyback()
	local counts = {}
	local emptyRun = 0
	for slot = 1, BuybackLimit() do
		local info = ReadBuybackSlot(slot)
		if info then
			emptyRun = 0
			local id = info.itemID and ("id:" .. info.itemID) or ("name:" .. tostring(info.name))
			local key = id .. ":" .. info.count .. ":" .. info.price
			local rec = counts[key]
			if not rec then
				rec = { item = info, n = 0 }
				counts[key] = rec
			end
			rec.n = rec.n + 1
		else
			emptyRun = emptyRun + 1
			if emptyRun >= 2 then
				break
			end
		end
	end
	return counts
end

--- Buyback price is the stack refund. A few clients report one item instead.
local function UnitFromBuyback(item)
	local quantity = item.count or 1
	local price = tonumber(item.price) or 0
	if price <= 0 then
		return nil
	end
	-- Lookup only decides whether this client put the stack total or one item in `price`.
	-- The copper we store is the vendor's number, so a later change replaces the old one.
	local looked = LookupItemSellPrice(item.link or item.itemID or item.name)
	if type(looked) == "number" and looked > 0 and quantity > 1 then
		local asStack = math.abs(price - (looked * quantity))
		local asUnit = math.abs(price - looked)
		if asUnit < asStack then
			return math.floor(price)
		end
	end
	if quantity > 1 and price % quantity == 0 then
		return math.floor(price / quantity)
	end
	return math.floor(price)
end

local function RememberVendorPrice(item, unit)
	unit = math.floor(unit)
	if unit <= 0 then
		return false
	end
	local db = EnsureDB()
	local changed = false
	if item.itemID then
		local key = tostring(item.itemID)
		if db.sellPrices[key] ~= unit then
			db.sellPrices[key] = unit
			changed = true
		end
	end
	for _, mob in pairs(db.mobs) do
		for _, entry in pairs(mob.items or {}) do
			local id = entry.itemId or ItemIdFromLink(entry.link)
			local sameId = item.itemID and id == item.itemID
			local sameName = item.name and entry.name == item.name and (not item.itemID or not id)
			if sameId or sameName then
				if item.itemID and not entry.itemId then
					entry.itemId = item.itemID
				end
				if entry.sellPrice ~= unit then
					entry.sellPrice = unit
					changed = true
				end
			end
		end
	end
	if changed then
		log:Debug("vendor price", item.name or item.itemID, unit)
	end
	return changed
end

local function ScanVendorSales()
	local counts = CollectBuyback()
	if not buybackSeen then
		buybackSeen = counts
		return
	end
	local changed = false
	for key, rec in pairs(counts) do
		local before = buybackSeen[key]
		local prevN = before and before.n or 0
		if rec.n > prevN then
			local unit = UnitFromBuyback(rec.item)
			if unit and RememberVendorPrice(rec.item, unit) then
				changed = true
			end
		end
	end
	buybackSeen = counts
	if changed and MobLedgerJournal_Refresh then
		MobLedgerJournal_Refresh()
	end
end

local vendorFrame = CreateFrame("Frame")
vendorFrame:Hide()
vendorFrame:SetScript("OnUpdate", function(self, elapsed)
	self.elapsed = (self.elapsed or 0) + elapsed
	if self.elapsed < 0.2 then
		return
	end
	self.elapsed = 0
	ScanVendorSales()
end)

local function VendorOpened()
	buybackSeen = nil
	vendorFrame.elapsed = 0
	vendorFrame:Show()
	ScanVendorSales()
end

local function VendorClosed()
	ScanVendorSales()
	vendorFrame:Hide()
	buybackSeen = nil
end

eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("LOOT_OPENED")
eventFrame:RegisterEvent("LOOT_SLOT_CLEARED")
eventFrame:RegisterEvent("LOOT_CLOSED")
eventFrame:RegisterEvent("CHAT_MSG_LOOT")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:RegisterEvent("MERCHANT_UPDATE")
eventFrame:RegisterEvent("MERCHANT_CLOSED")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		EnsureDB()
		log:Info("loaded — /mobledger or /ml to open the journal")
		return
	end

	if event == "LOOT_OPENED" then
		OnLootOpened()
	elseif event == "LOOT_SLOT_CLEARED" then
		OnLootSlotCleared(arg1)
	elseif event == "LOOT_CLOSED" then
		if openLoot then
			recentLoot = openLoot
			recentUntil = GetTime() + 2
			openLoot = nil
		end
	elseif event == "CHAT_MSG_LOOT" then
		OnChatLoot(arg1)
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		OnItemInfo(arg1)
	elseif event == "BAG_UPDATE" then
		if next(pendingSell) then
			sellRetryAt = 0
			RetryPendingSellPrices(eventFrame)
		end
	elseif event == "MERCHANT_SHOW" then
		VendorOpened()
	elseif event == "MERCHANT_UPDATE" then
		ScanVendorSales()
	elseif event == "MERCHANT_CLOSED" then
		VendorClosed()
	end
end)

SLASH_MOBLEDGER1 = "/mobledger"
SLASH_MOBLEDGER2 = "/ml"
SlashCmdList["MOBLEDGER"] = function(msg)
	msg = (msg and msg:match("^%s*(.-)%s*$")) or ""
	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	cmd = cmd and string.lower(cmd) or ""

	if cmd == "dev" then
		WoWF.ToggleDevMode(ADDON_NAME, rest)
		return
	end

	if cmd == "seed" then
		if not WoWF.DevMode then
			print("|cffff00ff[MobLedger]|r Seed is a development command.")
			return
		end
		MobLedger_Seed()
		if MobLedgerJournal_Show then
			MobLedgerJournal_Show()
		end
		print("|cffff00ff[MobLedger]|r Seeded a sample ledger.")
		return
	end

	if cmd == "reset" then
		rest = rest and rest:match("^%s*(.-)%s*$") or ""
		if rest == "" or rest == "all" then
			MobLedger_ResetAll()
			if MobLedgerJournal_Refresh then
				MobLedgerJournal_Refresh()
			end
			print("|cff33ccff[MobLedger]|r Cleared all recorded mobs.")
			return
		end
		if MobLedger_ResetMob(rest) then
			if MobLedgerJournal_Refresh then
				MobLedgerJournal_Refresh()
			end
			print("|cff33ccff[MobLedger]|r Cleared " .. rest .. ".")
		else
			print("|cff33ccff[MobLedger]|r No data for '" .. rest .. "'.")
		end
		return
	end

	if MobLedgerJournal_Toggle then
		MobLedgerJournal_Toggle()
	end
end
