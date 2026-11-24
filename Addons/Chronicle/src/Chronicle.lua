local ADDON_NAME, Addon = ...

local log = WoWF.Logger:New(ADDON_NAME, {
	minLevel = WoWF.DevMode and "DEBUG" or "INFO",
})

--- Oldest lines drop first once an NPC passes this many distinct lines.
local MAX_ENTRIES_PER_NPC = 150

--- Entry kinds, in the order the journal explains them.
Addon.KINDS = {
	gossip = "Gossip",
	greeting = "Greeting",
	quest_offer = "Quest offered",
	quest_progress = "Quest in progress",
	quest_complete = "Quest completed",
	say = "Says",
	yell = "Yells",
	emote = "Emotes",
	whisper = "Whispers",
}

-- ---------------------------------------------------------------------------
-- Saved data
--
-- ChronicleDB.npcs[key] = {
--   name, npcId, firstSeen = loc, lastSeen = loc,
--   entries = { { kind, title, text, objective, options, zone, subzone, time, last, count } },
-- }
-- Key is "npc:<id>" when the GUID gives an id, otherwise "name:<Name>".
-- ---------------------------------------------------------------------------

local function EnsureDB()
	if type(ChronicleDB) ~= "table" then
		ChronicleDB = {}
	end
	ChronicleDB.version = ChronicleDB.version or 1
	if type(ChronicleDB.npcs) ~= "table" then
		ChronicleDB.npcs = {}
	end
	if type(ChronicleDB.settings) ~= "table" then
		ChronicleDB.settings = {}
	end
	if ChronicleDB.settings.barks == nil then
		ChronicleDB.settings.barks = true
	end
	return ChronicleDB
end

local function PrintNote(msg)
	print("|cff4dc7b8[Chronicle]|r " .. msg)
end

local function RefreshJournal()
	if Addon.RefreshJournal then
		Addon.RefreshJournal()
	end
end

local function Clean(text)
	if type(text) ~= "string" then
		return nil
	end
	text = text:match("^%s*(.-)%s*$")
	if not text or text == "" then
		return nil
	end
	return text
end

--- Call a global API by name; nil when it is missing or errors.
local function CallString(name, ...)
	local fn = _G[name]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, ...)
	if ok then
		return Clean(result)
	end
	return nil
end

local function Now()
	return (time and time()) or 0
end

local function CaptureLocation()
	local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or nil
	local sub = GetSubZoneText and GetSubZoneText() or nil
	return {
		zone = Clean(zone),
		subzone = Clean(sub),
		time = Now(),
	}
end

local function ParseNpcId(guid)
	if type(guid) ~= "string" or not strsplit then
		return nil
	end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind == "Creature" or kind == "Vehicle" then
		return tonumber(id)
	end
	return nil
end

--- Who we are talking to. Interaction windows expose them as "npc".
local function ReadInteractionNpc()
	for _, unit in ipairs({ "npc", "target" }) do
		if UnitExists and UnitExists(unit) and not (UnitIsPlayer and UnitIsPlayer(unit)) then
			local name = Clean(UnitName(unit))
			if name then
				local guid = UnitGUID and UnitGUID(unit) or nil
				return { name = name, guid = guid, npcId = ParseNpcId(guid) }
			end
		end
	end
	return nil
end

local function NpcKey(identity)
	if identity.npcId then
		return "npc:" .. identity.npcId
	end
	return "name:" .. identity.name
end

local function LastSeenTime(npc)
	return npc.lastSeen and npc.lastSeen.time or 0
end

--- One NPC, however we met them. Clicking gives a GUID; spoken lines often do not,
--- so a name is the only thing both paths share. The id is used when both sides have one.
---   1. same id            -> same NPC
---   2. same name, and either side has no id, or the ids agree -> same NPC
---   3. same name but different ids -> two NPCs that share a name (guards, for example)
local function FindNpc(identity)
	local npcs = EnsureDB().npcs

	if identity.npcId then
		local direct = npcs[NpcKey(identity)]
		if direct then
			return NpcKey(identity), direct
		end
	end

	local bestKey, bestNpc
	for key, npc in pairs(npcs) do
		if npc.name == identity.name then
			local compatible = not identity.npcId or not npc.npcId or npc.npcId == identity.npcId
			if compatible and (not bestNpc or LastSeenTime(npc) > LastSeenTime(bestNpc)) then
				bestKey, bestNpc = key, npc
			end
		end
	end
	return bestKey, bestNpc
end

-- ---------------------------------------------------------------------------
-- Recording
-- ---------------------------------------------------------------------------

local function OptionsEqual(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

--- Store one line of dialogue under an NPC. Repeats of the same line only bump a counter.
--- fields = { title, text, objective, options, rewards }
function Addon.Record(identity, kind, fields)
	fields = fields or {}
	if not identity or not identity.name then
		return nil
	end
	if not (fields.text or fields.title) then
		return nil
	end

	local db = EnsureDB()
	local loc = CaptureLocation()

	local key, npc = FindNpc(identity)
	if not npc then
		key = NpcKey(identity)
		npc = {
			name = identity.name,
			npcId = identity.npcId,
			firstSeen = loc,
			entries = {},
		}
		db.npcs[key] = npc
		log:Info("new npc", identity.name)
	end
	npc.name = identity.name
	if identity.npcId and not npc.npcId then
		npc.npcId = identity.npcId
	end
	npc.lastSeen = loc
	if type(npc.entries) ~= "table" then
		npc.entries = {}
	end

	for i = #npc.entries, 1, -1 do
		local e = npc.entries[i]
		if e.kind == kind and e.title == fields.title and e.text == fields.text then
			e.count = (e.count or 1) + 1
			e.last = loc.time
			if fields.objective then
				e.objective = fields.objective
			end
			if fields.options and not (e.options and OptionsEqual(e.options, fields.options)) then
				e.options = fields.options
			end
			if fields.rewards then
				e.rewards = fields.rewards
			end
			log:Debug("repeat", identity.name, kind, e.count)
			RefreshJournal()
			return e, key
		end
	end

	local entry = {
		kind = kind,
		title = fields.title,
		text = fields.text,
		objective = fields.objective,
		options = fields.options,
		rewards = fields.rewards,
		zone = loc.zone,
		subzone = loc.subzone,
		time = loc.time,
		last = loc.time,
		count = 1,
	}
	npc.entries[#npc.entries + 1] = entry
	while #npc.entries > MAX_ENTRIES_PER_NPC do
		table.remove(npc.entries, 1)
	end

	log:Debug("recorded", identity.name, kind, fields.title or "")
	RefreshJournal()
	return entry, key
end

--- Fold one NPC's lines into another. Same line text adds up the counts.
local function MergeNpcInto(base, other)
	for _, e in ipairs(other.entries or {}) do
		local match
		for _, existing in ipairs(base.entries) do
			if existing.kind == e.kind and existing.title == e.title and existing.text == e.text then
				match = existing
				break
			end
		end
		if match then
			match.count = (match.count or 1) + (e.count or 1)
			match.time = math.min(match.time or e.time or 0, e.time or match.time or 0)
			match.last = math.max(match.last or 0, e.last or e.time or 0)
			match.objective = match.objective or e.objective
			match.options = match.options or e.options
			match.rewards = match.rewards or e.rewards
		else
			base.entries[#base.entries + 1] = e
		end
	end
	table.sort(base.entries, function(a, b)
		return (a.time or 0) < (b.time or 0)
	end)
	while #base.entries > MAX_ENTRIES_PER_NPC do
		table.remove(base.entries, 1)
	end
	if other.firstSeen and (not base.firstSeen or (other.firstSeen.time or 0) < (base.firstSeen.time or 0)) then
		base.firstSeen = other.firstSeen
	end
	if other.lastSeen and LastSeenTime(other) > LastSeenTime(base) then
		base.lastSeen = other.lastSeen
	end
	base.npcId = base.npcId or other.npcId
end

--- One-time cleanup for groups saved before NPCs were matched by name as well as id.
function Addon.MergeDuplicateNpcs()
	local npcs = EnsureDB().npcs
	local byName = {}
	for key, npc in pairs(npcs) do
		if type(npc.entries) ~= "table" then
			npc.entries = {}
		end
		local name = npc.name
		if name then
			byName[name] = byName[name] or {}
			table.insert(byName[name], key)
		end
	end

	local merged = 0
	for name, keys in pairs(byName) do
		if #keys > 1 then
			table.sort(keys)
			local kept = {}
			for _, key in ipairs(keys) do
				local npc = npcs[key]
				local target
				for _, baseKey in ipairs(kept) do
					local base = npcs[baseKey]
					if not npc.npcId or not base.npcId or npc.npcId == base.npcId then
						target = base
						break
					end
				end
				if target then
					MergeNpcInto(target, npc)
					npcs[key] = nil
					merged = merged + 1
				else
					kept[#kept + 1] = key
				end
			end
		end
	end

	if merged > 0 then
		log:Info("merged duplicate npc groups", merged)
	end
	return merged
end

-- ---------------------------------------------------------------------------
-- Reading the conversation windows
-- ---------------------------------------------------------------------------

local function ReadGossipText()
	if C_GossipInfo and C_GossipInfo.GetText then
		local ok, text = pcall(C_GossipInfo.GetText)
		if ok then
			return Clean(text)
		end
		return nil
	end
	return CallString("GetGossipText")
end

local function ReadGossipOptions()
	local out = {}
	if C_GossipInfo and C_GossipInfo.GetOptions then
		local ok, opts = pcall(C_GossipInfo.GetOptions)
		if ok and type(opts) == "table" then
			for _, opt in ipairs(opts) do
				local name = type(opt) == "table" and Clean(opt.name)
				if name then
					out[#out + 1] = name
				end
			end
		end
	elseif GetGossipOptions then
		local packed = { pcall(GetGossipOptions) }
		-- { ok, name1, type1, name2, type2, ... }
		for i = 2, #packed, 2 do
			local name = Clean(packed[i])
			if name then
				out[#out + 1] = name
			end
		end
	end
	if #out == 0 then
		return nil
	end
	return out
end

local function UnknownNpc()
	return { name = "Unknown" }
end

local function CallNumber(name, ...)
	local fn = _G[name]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, ...)
	if ok and type(result) == "number" then
		return result
	end
	return nil
end

local function PositiveCount(name)
	local n = CallNumber(name)
	if n and n > 0 then
		return math.floor(n)
	end
	return 0
end

local function IsTexture(value)
	return type(value) == "string"
		and (value:find("\\", 1, true) or value:find("/", 1, true) or value:find("^Interface"))
end

local function QualityHex(quality)
	local colors = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if type(colors) ~= "table" then
		return "ffffffff"
	end
	if type(colors.hex) == "string" then
		local hex = colors.hex:match("(%x%x%x%x%x%x)$")
		if hex then
			return hex
		end
	end
	if type(colors.r) == "number" then
		return string.format(
			"%02x%02x%02x",
			math.floor(colors.r * 255 + 0.5),
			math.floor((colors.g or 1) * 255 + 0.5),
			math.floor((colors.b or 1) * 255 + 0.5)
		)
	end
	return "ffffffff"
end

--- A real item link when the client gives one. Otherwise build one from the item id.
local function ItemLink(link, name, itemID, quality)
	if type(link) == "string" and link:find("|H", 1, true) then
		return link
	end
	if type(itemID) == "number" and itemID > 0 and type(name) == "string" then
		return string.format("|cff%s|Hitem:%d:0:0:0|h[%s]|h|r", QualityHex(quality), math.floor(itemID), name)
	end
	return nil
end

--- Item name from a quest reward slot. The link is what the journal shows, so it can be hovered and shift-clicked.
local function ReadQuestItem(kind, index)
	local name, count, itemID, quality, link
	if GetQuestItemLink then
		local ok, result = pcall(GetQuestItemLink, kind, index)
		if ok and type(result) == "string" then
			link = result
			name = result:match("%[(.-)%]")
		end
	end
	if GetQuestItemInfo then
		local ok, first, second, third, fourth, _, sixth = pcall(GetQuestItemInfo, kind, index)
		if ok then
			if not name then
				if type(first) == "string" and not IsTexture(first) then
					name = first
				elseif type(second) == "string" and not IsTexture(second) then
					name = second
				end
			end
			if type(third) == "number" and third > 1 then
				count = math.floor(third)
			end
			if type(fourth) == "number" then
				quality = fourth
			end
			if type(sixth) == "number" and sixth > 0 then
				itemID = math.floor(sixth)
			end
		end
	end
	name = Clean(name)
	if not name then
		return nil
	end
	return { name = name, count = count, link = ItemLink(link, name, itemID, quality) }
end

local function ReadQuestItemList(kind, countName)
	local n = PositiveCount(countName)
	if n == 0 then
		return nil
	end
	local list = {}
	for i = 1, n do
		local item = ReadQuestItem(kind, i)
		if item then
			list[#list + 1] = item
		end
	end
	if #list == 0 then
		return nil
	end
	return list
end

local function SpellName(...)
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		if type(value) == "string" and not IsTexture(value) then
			return Clean(value)
		end
	end
	return nil
end

local function ReadSpellRewards()
	local list = {}
	local n = PositiveCount("GetNumRewardSpells")
	if n > 0 and type(GetRewardSpell) == "function" then
		for i = 1, n do
			local ok, a, b, c = pcall(GetRewardSpell, i)
			local name = ok and SpellName(a, b, c)
			if name then
				list[#list + 1] = name
			end
		end
	elseif type(GetRewardSpell) == "function" then
		local ok, a, b, c = pcall(GetRewardSpell)
		local name = ok and SpellName(a, b, c)
		if name then
			list[1] = name
		end
	end
	if #list == 0 then
		return nil
	end
	return list
end

--- Experience is not on every client. Try the API, then a quest-frame region named for XP.
local function FontNumber(fs)
	if not fs or type(fs.GetText) ~= "function" then
		return nil
	end
	local text = fs:GetText()
	if type(text) ~= "string" then
		return nil
	end
	local n = tonumber((text:gsub(",", ""):match("(%d+)")))
	if n and n > 0 then
		return math.floor(n)
	end
	return nil
end

local function XPFromFrame(frame, depth)
	if not frame or depth > 5 or type(frame.GetName) ~= "function" then
		return nil
	end
	local name = frame:GetName()
	if type(name) == "string" and (name:find("XP", 1, true) or name:find("Experience", 1, true)) then
		local n = FontNumber(frame) or FontNumber(frame.ValueText) or FontNumber(frame.Text)
		if n then
			return n
		end
	end
	if type(frame.GetChildren) ~= "function" then
		return nil
	end
	local children = { frame:GetChildren() }
	for i = 1, #children do
		local n = XPFromFrame(children[i], depth + 1)
		if n then
			return n
		end
	end
	return nil
end

local function ReadRewardXP()
	local xp = CallNumber("GetRewardXP") or CallNumber("GetQuestRewardXP")
	if xp and xp > 0 then
		return math.floor(xp)
	end
	return XPFromFrame(_G.QuestFrame, 0) or XPFromFrame(_G.QuestInfoFrame, 0)
end

--- Rewards shown on the offer and the turn-in. Nil when the window lists none.
local function ReadQuestRewards()
	local rewards = {}
	local xp = ReadRewardXP()
	if xp then
		rewards.xp = xp
	end
	local money = CallNumber("GetRewardMoney")
	if money and money > 0 then
		rewards.money = math.floor(money)
	end
	rewards.items = ReadQuestItemList("reward", "GetNumQuestRewards")
	rewards.choices = ReadQuestItemList("choice", "GetNumQuestChoices")
	rewards.spells = ReadSpellRewards()
	if not (rewards.xp or rewards.money or rewards.items or rewards.choices or rewards.spells) then
		return nil
	end
	log:Debug(
		"rewards",
		"xp", rewards.xp or 0,
		"money", rewards.money or 0,
		"items", rewards.items and #rewards.items or 0,
		"choices", rewards.choices and #rewards.choices or 0
	)
	return rewards
end

local HANDLERS = {}

function HANDLERS.GOSSIP_SHOW()
	Addon.Record(ReadInteractionNpc() or UnknownNpc(), "gossip", {
		text = ReadGossipText(),
		options = ReadGossipOptions(),
	})
end

function HANDLERS.QUEST_GREETING()
	Addon.Record(ReadInteractionNpc() or UnknownNpc(), "greeting", {
		text = CallString("GetGreetingText"),
	})
end

function HANDLERS.QUEST_DETAIL()
	Addon.Record(ReadInteractionNpc() or UnknownNpc(), "quest_offer", {
		title = CallString("GetTitleText"),
		text = CallString("GetQuestText"),
		objective = CallString("GetObjectiveText"),
		rewards = ReadQuestRewards(),
	})
end

function HANDLERS.QUEST_PROGRESS()
	Addon.Record(ReadInteractionNpc() or UnknownNpc(), "quest_progress", {
		title = CallString("GetTitleText"),
		text = CallString("GetProgressText"),
	})
end

function HANDLERS.QUEST_COMPLETE()
	Addon.Record(ReadInteractionNpc() or UnknownNpc(), "quest_complete", {
		title = CallString("GetTitleText"),
		text = CallString("GetRewardText"),
		rewards = ReadQuestRewards(),
	})
end

--- Spoken lines. Chat payload: text, sender, ... guid is argument 12.
local CHAT_KIND = {
	CHAT_MSG_MONSTER_SAY = "say",
	CHAT_MSG_MONSTER_PARTY = "say",
	CHAT_MSG_MONSTER_YELL = "yell",
	CHAT_MSG_MONSTER_EMOTE = "emote",
	CHAT_MSG_MONSTER_WHISPER = "whisper",
	CHAT_MSG_RAID_BOSS_EMOTE = "emote",
	CHAT_MSG_RAID_BOSS_WHISPER = "whisper",
}

local function OnChatLine(kind, ...)
	if not EnsureDB().settings.barks then
		return
	end
	local text, sender = ...
	text, sender = Clean(text), Clean(sender)
	if not text or not sender then
		return
	end
	local guid = select(12, ...)
	if type(guid) ~= "string" then
		guid = nil
	end
	Addon.Record({ name = sender, guid = guid, npcId = ParseNpcId(guid) }, kind, { text = text })
end

-- ---------------------------------------------------------------------------
-- Queries used by the journal
-- ---------------------------------------------------------------------------

local function NpcMatches(npc, q)
	if string.find(string.lower(npc.name or ""), q, 1, true) then
		return true
	end
	if npc.lastSeen and npc.lastSeen.zone and string.find(string.lower(npc.lastSeen.zone), q, 1, true) then
		return true
	end
	for _, e in ipairs(npc.entries or {}) do
		if (e.text and string.find(string.lower(e.text), q, 1, true))
			or (e.title and string.find(string.lower(e.title), q, 1, true))
		then
			return true
		end
	end
	return false
end

--- Most recently met first. Returns list of { key, npc } and the unfiltered total.
function Addon.GetNpcList(query)
	local db = EnsureDB()
	local q = string.lower(Clean(query) or "")
	local list, total = {}, 0
	for key, npc in pairs(db.npcs) do
		total = total + 1
		if q == "" or NpcMatches(npc, q) then
			list[#list + 1] = { key = key, npc = npc }
		end
	end
	table.sort(list, function(a, b)
		local ta = a.npc.lastSeen and a.npc.lastSeen.time or 0
		local tb = b.npc.lastSeen and b.npc.lastSeen.time or 0
		if ta ~= tb then
			return ta > tb
		end
		return (a.npc.name or "") < (b.npc.name or "")
	end)
	return list, total
end

function Addon.GetNpc(key)
	return key and EnsureDB().npcs[key] or nil
end

function Addon.CountLines()
	local npcs, lines = 0, 0
	for _, npc in pairs(EnsureDB().npcs) do
		npcs = npcs + 1
		lines = lines + #(npc.entries or {})
	end
	return npcs, lines
end

function Addon.RemoveNpc(key)
	local npc = Addon.GetNpc(key)
	if not npc then
		return false
	end
	EnsureDB().npcs[key] = nil
	PrintNote("Removed " .. (npc.name or key) .. " from the Chronicle.")
	log:Info("removed", key)
	RefreshJournal()
	return true
end

function Addon.ClearAll()
	local settings = EnsureDB().settings
	ChronicleDB = { version = 1, npcs = {}, settings = settings }
	PrintNote("Cleared the Chronicle.")
	log:Info("cleared all")
	RefreshJournal()
end

--- Dev-only: writes a few fake lines so the journal can be checked without a quest giver.
function Addon.AddSample()
	if not WoWF.DevMode then
		PrintNote("Sample data is only available while Development mode is on.")
		return false
	end
	local giver = { name = "Sample Questgiver", npcId = 999001 }
	Addon.Record(giver, "gossip", {
		text = "Well met, traveler. The roads have not been safe since the bridge fell.",
		options = { "Tell me about the bridge.", "I need a quest.", "Goodbye." },
	})
	Addon.Record(giver, "quest_offer", {
		title = "The Broken Bridge",
		text = "Bandits cut the ropes at dusk and took everything we had. Find their camp east of here and bring back the ledger they stole.",
		objective = "Recover the Stolen Ledger from the bandit camp.",
		rewards = {
			xp = 170,
			money = 10228,
			choices = {
				{ name = "Stiletto", link = "|cffffffff|Hitem:2494:0:0:0|h[Stiletto]|h|r" },
				{ name = "Wooden Mallet", link = "|cffffffff|Hitem:2493:0:0:0|h[Wooden Mallet]|h|r" },
			},
		},
	})
	Addon.Record(giver, "quest_complete", {
		title = "The Broken Bridge",
		text = "You found it! Now we know who paid them. Take this, you have earned it.",
		rewards = {
			xp = 170,
			money = 28,
			items = { { name = "Linen Cloth", count = 5, link = "|cffffffff|Hitem:2589:0:0:0|h[Linen Cloth]|h|r" } },
		},
	})
	Addon.Record({ name = "Sample Bandit", npcId = 999002 }, "yell", {
		text = "You'll never take the camp alive!",
	})
	PrintNote("Added sample conversations.")
	return true
end

-- ---------------------------------------------------------------------------
-- Slash commands and events
-- ---------------------------------------------------------------------------

WoWF.OnDevModeChanged(function(enabled)
	log:SetLevel(enabled and "DEBUG" or "INFO")
	RefreshJournal()
end)

--- Registered early so a later load error cannot wipe the command.
local function OnSlash(msg)
	msg = (msg and msg:match("^%s*(.-)%s*$")) or ""
	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	cmd = cmd and string.lower(cmd) or ""
	rest = rest and string.lower(rest:match("^%s*(.-)%s*$")) or ""

	if cmd == "dev" then
		WoWF.ToggleDevMode(ADDON_NAME, rest)
		return
	end

	if cmd == "barks" then
		local settings = EnsureDB().settings
		if rest == "on" then
			settings.barks = true
		elseif rest == "off" then
			settings.barks = false
		else
			settings.barks = not settings.barks
		end
		PrintNote("Spoken lines (say / yell / emote / whisper) are " .. (settings.barks and "recorded." or "ignored."))
		return
	end

	if cmd == "clear" then
		if rest == "confirm" then
			Addon.ClearAll()
		else
			PrintNote("This erases every recorded conversation. Type /chron clear confirm to proceed.")
		end
		return
	end

	if cmd == "status" then
		local npcs, lines = Addon.CountLines()
		PrintNote(string.format("%d NPCs, %d distinct lines recorded.", npcs, lines))
		return
	end

	if cmd == "help" then
		PrintNote("/ch — open the journal")
		PrintNote("/chron status — how much has been recorded")
		PrintNote("/chron barks [on|off] — record spoken say/yell/emote lines")
		PrintNote("/chron clear confirm — erase everything")
		PrintNote("/chron dev [on|off] — toggle Development mode (this session)")
		return
	end

	if Addon.ToggleJournal then
		local ok, err = pcall(Addon.ToggleJournal)
		if not ok then
			PrintNote("Journal error: " .. tostring(err))
			log:Error("journal", err)
		end
	else
		PrintNote("Journal failed to load. Try /reload.")
	end
end

SLASH_CHRONICLE1 = "/chronicle"
SLASH_CHRONICLE2 = "/chron"
SLASH_CHRONICLE3 = "/ch"
SlashCmdList["CHRONICLE"] = OnSlash

local eventFrame = CreateFrame("Frame")

--- Forever refuses some events. Never let a bad RegisterEvent abort load.
local function SafeRegister(eventName)
	local ok, err = pcall(function()
		eventFrame:RegisterEvent(eventName)
	end)
	if not ok then
		log:Warn("RegisterEvent refused:", eventName, err)
	end
end

SafeRegister("ADDON_LOADED")
for event in pairs(HANDLERS) do
	SafeRegister(event)
end
for event in pairs(CHAT_KIND) do
	SafeRegister(event)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if (...) == ADDON_NAME then
			EnsureDB()
			local ok, err = pcall(Addon.MergeDuplicateNpcs)
			if not ok then
				log:Error("merge", err)
			end
			log:Info("loaded — /ch /chron /chronicle")
		end
		return
	end

	local ok, err
	if HANDLERS[event] then
		ok, err = pcall(HANDLERS[event])
	elseif CHAT_KIND[event] then
		ok, err = pcall(OnChatLine, CHAT_KIND[event], ...)
	else
		return
	end
	if not ok then
		log:Error(event, err)
	end
end)
