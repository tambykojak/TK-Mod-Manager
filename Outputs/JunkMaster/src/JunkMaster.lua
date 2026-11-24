local ADDON_NAME, Addon = ...

local log = WoWF.Logger:New(ADDON_NAME, {
	minLevel = WoWF.DevMode and "DEBUG" or "INFO",
})

WoWF.OnDevModeChanged(function(enabled)
	log:SetLevel(enabled and "DEBUG" or "INFO")
end)

--- Poor (gray) item quality. Junk is this quality and has a vendor price.
local POOR_QUALITY = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
local POOR_LINK_COLOR = "9d9d9d"

--- Seconds between sell passes. 0 runs a pass every frame while the vendor is open.
local SELL_POLL = 0
--- Don't retry a stack that is still in the bag until the server has had this long to lock it.
local SELL_RETRY = 0.35
local BUYBACK_POLL = 0.1
--- MERCHANT_SHOW can arrive before MerchantFrame is shown.
local FRAME_GRACE = 1.5
--- Give uncached or locked junk this long, then move on.
local STALL_TIMEOUT = 2
local MAX_ATTEMPTS = 4

local merchantOpen = false
local sawMerchant = false
local selling = false
local openedAt = 0
local poll = 0
local stallAt = nil
local inFlight = {}
local inFlightKeys = {}
local nextSellAt = 0
local skipped = {}
local soldItems = 0
local soldCopper = 0
local missingApi = false

local eventFrame = CreateFrame("Frame")

--- Plain "1g 2s 3c" for the ledger. Chat can still use coin icons.
local function FormatMoneyText(copper)
	copper = math.floor(tonumber(copper) or 0)
	if copper < 0 then
		copper = 0
	end
	local gold = math.floor(copper / 10000)
	local silver = math.floor((copper % 10000) / 100)
	local copperLeft = copper % 100
	if gold > 0 then
		return string.format("%dg %ds %dc", gold, silver, copperLeft)
	end
	if silver > 0 then
		return string.format("%ds %dc", silver, copperLeft)
	end
	return string.format("%dc", copperLeft)
end

local function FormatMoney(copper)
	copper = math.floor(tonumber(copper) or 0)
	if copper < 0 then
		copper = 0
	end
	if GetCoinTextureString then
		return GetCoinTextureString(copper)
	end
	return FormatMoneyText(copper)
end

function JunkMaster_FormatMoney(copper)
	return FormatMoneyText(copper)
end

local function ItemIDFromLink(link)
	if type(link) ~= "string" then
		return nil
	end
	return tonumber(link:match("item:(%d+)"))
end

local function LookupItemName(link, itemID)
	if type(link) == "string" then
		local fromLink = link:match("%[(.-)%]")
		if fromLink and fromLink ~= "" then
			return fromLink
		end
	end
	local ref = link or itemID
	if ref and C_Item and C_Item.GetItemInfo then
		local first = C_Item.GetItemInfo(ref)
		if type(first) == "table" and type(first.itemName) == "string" and first.itemName ~= "" then
			return first.itemName
		end
		if type(first) == "string" and first ~= "" then
			return first
		end
	end
	if ref and GetItemInfo then
		local name = GetItemInfo(ref)
		if type(name) == "string" and name ~= "" then
			return name
		end
	end
	return nil
end

local function LookupItemIcon(link, itemID)
	if itemID and C_Item and C_Item.GetItemIconByID then
		local icon = C_Item.GetItemIconByID(itemID)
		if icon then
			return icon
		end
	end
	local ref = itemID or link
	if ref and GetItemIcon then
		local icon = GetItemIcon(ref)
		if icon then
			return icon
		end
	end
	if ref and GetItemInfo then
		local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(ref)
		if tex then
			return tex
		end
	end
	return nil
end

local function StampItem(info)
	if not info then
		return
	end
	if not info.itemID then
		info.itemID = ItemIDFromLink(info.link)
	end
	info.name = LookupItemName(info.link, info.itemID) or info.name
	info.icon = LookupItemIcon(info.link, info.itemID) or info.icon
end

local function EnsureDB()
	if type(JunkMasterDB) ~= "table" then
		JunkMasterDB = {}
	end
	if type(JunkMasterDB.items) ~= "table" then
		JunkMasterDB.items = {}
	end
	JunkMasterDB.version = JunkMasterDB.version or 1
	JunkMasterDB.itemsSold = tonumber(JunkMasterDB.itemsSold) or 0
	JunkMasterDB.copperTotal = tonumber(JunkMasterDB.copperTotal) or 0
	if JunkMasterDB.speed ~= "slow" and JunkMasterDB.speed ~= "medium" and JunkMasterDB.speed ~= "fast" then
		JunkMasterDB.speed = "medium"
	end
	return JunkMasterDB
end

function JunkMaster_GetDB()
	return EnsureDB()
end

local function ItemRecordKey(itemID, name, link)
	if itemID then
		return "id:" .. tostring(itemID)
	end
	if type(name) == "string" and name ~= "" then
		return "name:" .. name
	end
	if type(link) == "string" and link ~= "" then
		return "link:" .. link
	end
	return nil
end

function JunkMaster_RecordSale(sale)
	if type(sale) ~= "table" then
		return
	end
	local count = math.floor(tonumber(sale.count) or 1)
	if count < 1 then
		count = 1
	end
	local copper = math.floor(tonumber(sale.copper) or 0)
	if copper < 0 then
		copper = 0
	end

	local db = EnsureDB()
	local key = ItemRecordKey(sale.itemID, sale.name, sale.link)
	if not key then
		return
	end

	local entry = db.items[key]
	if type(entry) ~= "table" then
		entry = {
			count = 0,
			copper = 0,
		}
		db.items[key] = entry
	end
	entry.itemID = sale.itemID or entry.itemID
	entry.name = sale.name or entry.name
	entry.link = sale.link or entry.link
	entry.icon = sale.icon or entry.icon
	entry.count = (tonumber(entry.count) or 0) + count
	entry.copper = (tonumber(entry.copper) or 0) + copper
	db.itemsSold = (tonumber(db.itemsSold) or 0) + count
	db.copperTotal = (tonumber(db.copperTotal) or 0) + copper

	if type(JunkMasterPanel_Refresh) == "function" then
		JunkMasterPanel_Refresh()
	end
end

function JunkMaster_RemoveSale(sale)
	if type(sale) ~= "table" then
		return false
	end
	local count = math.floor(tonumber(sale.count) or 1)
	if count < 1 then
		count = 1
	end
	local copper = math.floor(tonumber(sale.copper) or 0)
	if copper < 0 then
		copper = 0
	end

	local db = EnsureDB()
	local key = ItemRecordKey(sale.itemID, sale.name, sale.link)
	local entry = key and db.items[key]
	if type(entry) ~= "table" and type(sale.name) == "string" then
		key = ItemRecordKey(nil, sale.name, nil)
		entry = key and db.items[key]
	end
	if type(entry) ~= "table" then
		return false
	end

	count = math.min(count, math.floor(tonumber(entry.count) or 0))
	if count < 1 then
		return false
	end
	copper = math.min(copper, math.floor(tonumber(entry.copper) or 0))

	entry.count = math.floor(tonumber(entry.count) or 0) - count
	entry.copper = math.floor(tonumber(entry.copper) or 0) - copper
	db.itemsSold = math.max(0, math.floor(tonumber(db.itemsSold) or 0) - count)
	db.copperTotal = math.max(0, math.floor(tonumber(db.copperTotal) or 0) - copper)
	if entry.count <= 0 then
		db.items[key] = nil
	end

	if type(JunkMasterPanel_Refresh) == "function" then
		JunkMasterPanel_Refresh()
	end
	return true
end

function JunkMaster_Reset()
	local db = EnsureDB()
	local point, relativePoint, x, y = db.point, db.relativePoint, db.x, db.y
	local speed = db.speed
	db.version = 1
	db.items = {}
	db.itemsSold = 0
	db.copperTotal = 0
	db.point = point
	db.relativePoint = relativePoint
	db.x = x
	db.y = y
	db.speed = speed
	if type(JunkMasterPanel_Refresh) == "function" then
		JunkMasterPanel_Refresh()
	end
end

--- batch: sells kept in flight. gap: pause after each stack leaves the bag.
--- Medium is one stack at a time, which stays under the bag-error threshold.
--- Fast keeps several in flight and can surface that error.
local SELL_SPEED = {
	slow = { batch = 1, gap = 0.6 },
	medium = { batch = 1, gap = 0 },
	fast = { batch = 8, gap = 0 },
}

function JunkMaster_GetSpeed()
	return EnsureDB().speed
end

function JunkMaster_SetSpeed(speed)
	if not SELL_SPEED[speed] then
		return JunkMaster_GetSpeed()
	end
	EnsureDB().speed = speed
	if type(JunkMasterPanel_Refresh) == "function" then
		JunkMasterPanel_Refresh()
	end
	return speed
end

local function SellProfile()
	return SELL_SPEED[JunkMaster_GetSpeed()] or SELL_SPEED.medium
end

local function MaxBagIndex()
	local maxBag = NUM_BAG_SLOTS or 4
	local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
	if type(reagent) == "number" and reagent > maxBag then
		return reagent
	end
	return maxBag
end

local function NumSlots(bag)
	if C_Container and C_Container.GetContainerNumSlots then
		return C_Container.GetContainerNumSlots(bag) or 0
	end
	if GetContainerNumSlots then
		return GetContainerNumSlots(bag) or 0
	end
	return 0
end

local function BagItemLink(bag, slot)
	if C_Container and C_Container.GetContainerItemLink then
		return C_Container.GetContainerItemLink(bag, slot)
	end
	if GetContainerItemLink then
		return GetContainerItemLink(bag, slot)
	end
	return nil
end

local function ReadSlot(bag, slot)
	local texture, count, locked, quality, _, _, link, _, noValue, itemID

	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if type(info) == "table" then
			if not info.iconFileID and not info.itemID and not info.hyperlink then
				return nil
			end
			link = info.hyperlink
			if type(link) ~= "string" then
				link = BagItemLink(bag, slot)
			end
			return {
				count = info.stackCount or 1,
				locked = info.isLocked and true or false,
				quality = info.quality,
				link = type(link) == "string" and link or nil,
				noValue = info.hasNoValue and true or false,
				itemID = info.itemID,
			}
		end
		texture, count, locked, quality, _, _, link, _, noValue, itemID = C_Container.GetContainerItemInfo(bag, slot)
	elseif GetContainerItemInfo then
		texture, count, locked, quality, _, _, link, _, noValue, itemID = GetContainerItemInfo(bag, slot)
	else
		return nil
	end

	if not texture and not itemID and type(link) ~= "string" then
		return nil
	end
	if type(link) ~= "string" then
		link = BagItemLink(bag, slot)
	end

	return {
		count = count or 1,
		locked = locked and true or false,
		quality = type(quality) == "number" and quality or nil,
		link = type(link) == "string" and link or nil,
		noValue = noValue and true or false,
		itemID = itemID,
	}
end

local function LinkIsPoor(link)
	if type(link) ~= "string" then
		return false
	end
	local color = link:match("|c(%x%x%x%x%x%x%x%x)")
	return color ~= nil and color:lower():sub(3) == POOR_LINK_COLOR
end

local function LookupSellPrice(itemID, link)
	local ref = link or itemID
	if not ref then
		return nil
	end

	if C_Item and C_Item.GetItemInfo then
		local first, _, _, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(ref)
		if type(first) == "table" then
			price = first.sellPrice
		end
		if type(price) == "number" then
			return price
		end
	end

	if GetItemInfo then
		local _, _, _, _, _, _, _, _, _, _, price = GetItemInfo(ref)
		if type(price) == "number" then
			return price
		end
	end

	return nil
end

--- Last buyback list while the vendor is open. Slot index -> item.
local buybackSlots = {}
--- Clicks waiting until the stack actually leaves the buyback list.
local pendingBuybacks = {}
local buybackPoll = 0

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

local function ReadBuyback(slot)
	local name, _, price, quantity, link

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
		name = type(name) == "string" and name or nil,
		itemID = ItemIDFromLink(link),
		link = type(link) == "string" and link or nil,
		count = quantity,
		price = tonumber(price) or 0,
	}
end

local function BuybackMatchKey(item)
	local count = tostring(item.count or 1)
	if item.itemID then
		return "id:" .. tostring(item.itemID) .. ":" .. count
	end
	if type(item.name) == "string" and item.name ~= "" then
		return "name:" .. item.name .. ":" .. count
	end
	return "link:" .. tostring(item.link) .. ":" .. count
end

local function SameBuyback(a, b)
	if not a or not b then
		return false
	end
	return BuybackMatchKey(a) == BuybackMatchKey(b)
end

local function EachBuyback(callback)
	local emptyRun = 0
	local limit = BuybackLimit()
	for slot = 1, limit do
		local info = ReadBuyback(slot)
		if info then
			emptyRun = 0
			callback(slot, info)
		else
			emptyRun = emptyRun + 1
			if emptyRun >= 2 then
				break
			end
		end
	end
end

local function CountBuyback(item, fromSnapshot)
	local count = 0
	if fromSnapshot then
		for _, info in pairs(buybackSlots) do
			if SameBuyback(info, item) then
				count = count + 1
			end
		end
		return count
	end
	EachBuyback(function(_, info)
		if SameBuyback(info, item) then
			count = count + 1
		end
	end)
	return count
end

local function SnapshotBuyback()
	local snap = {}
	EachBuyback(function(slot, info)
		snap[slot] = info
	end)
	buybackSlots = snap
end

--- Buyback price is the stack refund. Some clients report a unit price instead.
local function BuybackCopper(item)
	local quantity = item.count or 1
	local price = tonumber(item.price) or 0
	local unit = LookupSellPrice(item.itemID, item.link)
	if unit and unit > 0 and quantity > 1 and price > 0 then
		local asTotal = math.abs(price - (unit * quantity))
		local asUnit = math.abs((price * quantity) - (unit * quantity))
		if asUnit < asTotal then
			return math.floor(price * quantity)
		end
	end
	if price > 0 then
		return math.floor(price)
	end
	if unit and unit > 0 then
		return math.floor(unit * quantity)
	end
	return 0
end

local function NoteBuyback(slot)
	slot = tonumber(slot)
	if not slot then
		return
	end
	local item = ReadBuyback(slot) or buybackSlots[slot]
	if not item then
		log:Debug("buyback slot empty", slot)
		return
	end
	local before = math.max(CountBuyback(item, true), CountBuyback(item, false))
	if before < 1 then
		before = 1
	end
	pendingBuybacks[#pendingBuybacks + 1] = {
		name = item.name,
		itemID = item.itemID,
		link = item.link,
		count = item.count,
		price = item.price,
		before = before,
		at = GetTime(),
	}
	log:Debug("buyback queued", item.name or item.itemID, "x" .. tostring(item.count))
end

local function ConfirmBuybacks()
	if #pendingBuybacks == 0 then
		SnapshotBuyback()
		return
	end
	local still = {}
	local removed = {}
	local now = GetTime()
	for _, item in ipairs(pendingBuybacks) do
		local key = BuybackMatchKey(item)
		local live = CountBuyback(item, false) + (removed[key] or 0)
		if live < item.before then
			local didRemove = JunkMaster_RemoveSale({
				itemID = item.itemID,
				name = item.name,
				link = item.link,
				count = item.count,
				copper = BuybackCopper(item),
			})
			removed[key] = (removed[key] or 0) + 1
			if didRemove then
				log:Debug("bought back", item.name or item.itemID, "x" .. tostring(item.count))
			else
				log:Debug("buyback was not in the ledger", item.name or item.itemID)
			end
		elseif now - item.at > 3 then
			log:Debug("buyback did not complete", item.name or item.itemID)
		else
			still[#still + 1] = item
		end
	end
	pendingBuybacks = still
	SnapshotBuyback()
end

local function InstallBuybackHook()
	local function OnBuyback(...)
		local slot
		for i = 1, select("#", ...) do
			local value = select(i, ...)
			if type(value) == "number" then
				slot = value
				break
			end
		end
		if slot then
			NoteBuyback(slot)
		end
	end

	if hooksecurefunc and type(BuybackItem) == "function" then
		hooksecurefunc("BuybackItem", OnBuyback)
		return
	end
	if type(BuybackItem) == "function" then
		local original = BuybackItem
		BuybackItem = function(slot, ...)
			NoteBuyback(slot)
			return original(slot, ...)
		end
		return
	end
	if hooksecurefunc and C_MerchantFrame and type(C_MerchantFrame.BuybackItem) == "function" then
		hooksecurefunc(C_MerchantFrame, "BuybackItem", OnBuyback)
		return
	end
	log:Warn("cannot watch buyback: BuybackItem is missing")
end

--- "junk", "keep", or "unknown" when the client has not cached the item yet.
local function Classify(info)
	if info.noValue then
		return "keep"
	end
	if type(info.quality) == "number" then
		if info.quality == POOR_QUALITY then
			return "junk"
		end
		return "keep"
	end
	if LinkIsPoor(info.link) then
		return "junk"
	end

	local ref = info.link or info.itemID
	if ref and GetItemInfo then
		local _, _, quality = GetItemInfo(ref)
		if type(quality) == "number" then
			info.quality = quality
			if quality == POOR_QUALITY then
				return "junk"
			end
			return "keep"
		end
	end
	return "unknown"
end

local function SlotKey(info)
	return tostring(info.bag) .. ":" .. tostring(info.slot) .. ":" .. tostring(info.itemID or info.link or "")
end

local function SameItem(info, item)
	if not info or not item then
		return false
	end
	if item.itemID and info.itemID then
		return info.itemID == item.itemID
	end
	if item.link and info.link then
		return info.link == item.link
	end
	return true
end

local function UseBagItem(bag, slot)
	local fn = (C_Container and C_Container.UseContainerItem) or UseContainerItem
	if not fn then
		if not missingApi then
			missingApi = true
			log:Error("cannot sell junk: UseContainerItem is missing")
		end
		selling = false
		return false
	end
	local ok, err = pcall(fn, bag, slot)
	if not ok then
		log:Debug("UseContainerItem failed", err)
		return false
	end
	return true
end

local function MerchantReady()
	if not merchantOpen then
		return false
	end
	if MerchantFrame and MerchantFrame.IsShown then
		return MerchantFrame:IsShown()
	end
	return true
end

local function Report()
	if soldItems <= 0 then
		log:Debug("no junk sold")
		return
	end
	local noun = soldItems == 1 and "item" or "items"
	if soldCopper > 0 then
		log:Info(string.format("Sold %d junk %s for %s.", soldItems, noun, FormatMoney(soldCopper)))
	else
		log:Info(string.format("Sold %d junk %s.", soldItems, noun))
	end
end

local function ClearTotals()
	soldItems = 0
	soldCopper = 0
	inFlight = {}
	inFlightKeys = {}
	stallAt = nil
	nextSellAt = 0
end

local function RecordSold(item)
	local count = item.count or 1
	local copper = 0
	if type(item.price) == "number" and item.price > 0 then
		copper = item.price * count
	end
	soldItems = soldItems + count
	soldCopper = soldCopper + copper
	StampItem(item)
	JunkMaster_RecordSale({
		itemID = item.itemID,
		name = item.name,
		link = item.link,
		icon = item.icon,
		count = count,
		copper = copper,
	})
	log:Debug("sold", item.link or item.name or item.itemID, "x" .. tostring(count))
	local gap = SellProfile().gap
	if gap > 0 then
		nextSellAt = GetTime() + gap
	end
end

local function CreditInFlight()
	for _, item in ipairs(inFlight) do
		local info = ReadSlot(item.bag, item.slot)
		if not info or not SameItem(info, item) then
			RecordSold(item)
		end
	end
	inFlight = {}
	inFlightKeys = {}
end

local function BeginAttempt(info)
	StampItem(info)
	if not UseBagItem(info.bag, info.slot) then
		skipped[info.key] = true
		return false
	end
	info.attempts = 1
	info.triedAt = GetTime()
	inFlight[#inFlight + 1] = info
	inFlightKeys[info.key] = true
	stallAt = nil
	return true
end

local function ReconcileInFlight()
	local still = {}
	local now = GetTime()
	for _, item in ipairs(inFlight) do
		local info = ReadSlot(item.bag, item.slot)
		if not info or not SameItem(info, item) then
			inFlightKeys[item.key] = nil
			RecordSold(item)
		elseif info.locked or (now - (item.triedAt or 0)) < SELL_RETRY then
			still[#still + 1] = item
		else
			item.attempts = (item.attempts or 1) + 1
			if item.attempts > MAX_ATTEMPTS or not UseBagItem(item.bag, item.slot) then
				inFlightKeys[item.key] = nil
				skipped[item.key] = true
				log:Debug("could not sell", item.link or item.itemID)
			else
				item.triedAt = now
				still[#still + 1] = item
			end
		end
	end
	inFlight = still
end

local function TickSell()
	ReconcileInFlight()
	local profile = SellProfile()
	if GetTime() < nextSellAt then
		return
	end
	if #inFlight >= profile.batch then
		return
	end

	local waiting = false
	local force = stallAt ~= nil and (GetTime() - stallAt) >= STALL_TIMEOUT

	for bag = 0, MaxBagIndex() do
		for slot = 1, NumSlots(bag) do
			local info = ReadSlot(bag, slot)
			if info then
				info.bag = bag
				info.slot = slot
				info.key = SlotKey(info)
				if not skipped[info.key] and not inFlightKeys[info.key] then
					local class = Classify(info)
					if class == "unknown" then
						if force then
							skipped[info.key] = true
						else
							waiting = true
						end
					elseif class == "junk" then
						info.price = LookupSellPrice(info.itemID, info.link)
						if info.locked then
							if force then
								skipped[info.key] = true
							else
								waiting = true
							end
						elseif info.price == nil then
							if force then
								if BeginAttempt(info) and (#inFlight >= profile.batch or missingApi or not selling) then
									return
								end
								if missingApi or not selling then
									return
								end
							else
								waiting = true
							end
						elseif info.price <= 0 then
							skipped[info.key] = true
						elseif BeginAttempt(info) and (#inFlight >= profile.batch or missingApi or not selling) then
							return
						elseif missingApi or not selling then
							return
						end
					end
				end
			end
		end
	end

	if #inFlight > 0 then
		return
	end

	if waiting then
		if not stallAt then
			stallAt = GetTime()
		end
		return
	end

	selling = false
	Report()
	ClearTotals()
end

local function SafeRegister(eventName)
	local ok, err = pcall(function()
		eventFrame:RegisterEvent(eventName)
	end)
	if not ok then
		log:Warn("RegisterEvent refused:", eventName, err)
	end
	return ok
end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		EnsureDB()
		log:Info("loaded — /junkmaster or /jm")
		return
	end

	if event == "MERCHANT_SHOW" then
		skipped = {}
		ClearTotals()
		pendingBuybacks = {}
		merchantOpen = true
		sawMerchant = false
		selling = true
		openedAt = GetTime()
		poll = 0
		SnapshotBuyback()
		log:Debug("vendor opened")
		return
	end

	if event == "MERCHANT_UPDATE" then
		ConfirmBuybacks()
		return
	end

	if event == "MERCHANT_CLOSED" then
		merchantOpen = false
		if selling or #inFlight > 0 or soldItems > 0 then
			CreditInFlight()
			selling = false
			Report()
			ClearTotals()
		end
		pendingBuybacks = {}
		buybackSlots = {}
	end
end)

eventFrame:SetScript("OnUpdate", function(_, delta)
	if merchantOpen then
		buybackPoll = buybackPoll + delta
		if buybackPoll >= BUYBACK_POLL then
			buybackPoll = 0
			ConfirmBuybacks()
		end
	end

	if not selling then
		return
	end

	if MerchantReady() then
		sawMerchant = true
	elseif not sawMerchant then
		if (GetTime() - openedAt) >= FRAME_GRACE then
			selling = false
			merchantOpen = false
			log:Debug("vendor closed before junk scan")
		end
		return
	else
		CreditInFlight()
		selling = false
		merchantOpen = false
		Report()
		ClearTotals()
		return
	end

	poll = poll + delta
	if poll < SELL_POLL then
		return
	end
	poll = 0
	TickSell()
end)

SafeRegister("ADDON_LOADED")
SafeRegister("MERCHANT_SHOW")
SafeRegister("MERCHANT_UPDATE")
SafeRegister("MERCHANT_CLOSED")
InstallBuybackHook()

SLASH_JUNKMASTER1 = "/junkmaster"
SLASH_JUNKMASTER2 = "/jm"
SlashCmdList["JUNKMASTER"] = function(msg)
	msg = (msg and string.lower(msg):match("^%s*(.-)%s*$")) or ""
	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	if cmd == "dev" then
		WoWF.ToggleDevMode(ADDON_NAME, rest)
		return
	end
	if msg == "reset" or msg == "clear" then
		JunkMaster_Reset()
		log:Info("cleared the junk ledger")
		return
	end
	if msg == "slow" or msg == "medium" or msg == "fast" then
		JunkMaster_SetSpeed(msg)
		log:Info("sell speed", msg)
		return
	end
	if type(JunkMasterPanel_Toggle) == "function" then
		JunkMasterPanel_Toggle()
		return
	end
	log:Error("ledger panel failed to load")
end
