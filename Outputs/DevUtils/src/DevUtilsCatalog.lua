local ADDON_NAME, Addon = ...

--- Curated Blizzard paths for Classic / Forever-style clients.
--- Not exhaustive — the real client has thousands inside CASC.
--- Paths that fail to load still show so you can try them; use the Path bar in Explore for anything else.

Addon.TEXTURE_CATEGORIES = {
	"Background",
	"Border",
	"StatusBar",
	"Button",
	"Frame",
	"ActionBar",
	"Character",
	"Chat",
	"Container",
	"Quest",
	"Targeting",
	"Minimap",
	"Casting",
	"Cooldown",
	"Icon",
	"Glues",
	"Misc",
}

local function FileName(path)
	return (path and path:match("([^\\/]+)$")) or path or ""
end

local function T(category, path)
	return { category = category, name = FileName(path), path = path }
end

local TEXTURES = {}

--- Display name is always the file basename (e.g. QuestBG, not "Quest Background").
--- Call as add(category, path) or add(category, ignoredLabel, path).
local function add(category, nameOrPath, path)
	if path == nil then
		path = nameOrPath
	end
	TEXTURES[#TEXTURES + 1] = T(category, path)
end

--- Four corner pieces. Filenames keep Blizzard's "Bot" token.
--- style:
---   "hyphen" → Prefix-TopLeft
---   "glued"  → PrefixTopLeft
---   "skill"  → PrefixTopLeft where Prefix already ends with Skill (TradeSkill)
local function addCorners(category, _title, pathPrefix, style)
	style = style or "hyphen"
	local parts = {
		{ token = "TopLeft" },
		{ token = "TopRight" },
		{ token = "BotLeft" },
		{ token = "BotRight" },
	}
	for _, part in ipairs(parts) do
		local path
		if style == "glued" or style == "skill" then
			path = pathPrefix .. part.token
		else
			path = pathPrefix .. "-" .. part.token
		end
		add(category, path)
	end
end

---------------------------------------------------------------------------
-- Backgrounds / fills
---------------------------------------------------------------------------
add("Background", "Dialog Box Background", "Interface\\DialogFrame\\UI-DialogBox-Background")
add("Background", "Dialog Box Background Dark", "Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
add("Background", "Dialog Box Gold Background", "Interface\\DialogFrame\\UI-DialogBox-Gold-Background")
add("Background", "Tooltip Background", "Interface\\Tooltips\\UI-Tooltip-Background")
add("Background", "Chat Frame Background", "Interface\\ChatFrame\\ChatFrameBackground")
add("Background", "White 8x8", "Interface\\Buttons\\WHITE8X8")
add("Background", "Rock", "Interface\\FrameGeneral\\UI-Background-Rock")
add("Background", "Marble", "Interface\\FrameGeneral\\UI-Background-Marble")
add("Background", "Parchment", "Interface\\AchievementFrame\\UI-Achievement-Parchment")
add("Background", "Parchment Horizontal", "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal")
add("Background", "Quest Background", "Interface\\QuestFrame\\QuestBG")
add("Background", "Quest Item Name Frame", "Interface\\QuestFrame\\UI-QuestItemNameFrame")
add("Background", "Gossip Frame", "Interface\\GossipFrame\\GossipFame")
add("Background", "Bank Background", "Interface\\BankFrame\\Bank-Background")
add("Background", "Talent Frame Background", "Interface\\TalentFrame\\TalentFrame-Background")
add("Background", "Auction Browse Background", "Interface\\AuctionFrame\\UI-AuctionFrame-Browse-Background")
add("Background", "Auction Bid Background", "Interface\\AuctionFrame\\UI-AuctionFrame-Bid-Background")
add("Background", "Auction Auction Background", "Interface\\AuctionFrame\\UI-AuctionFrame-Auction-Background")
add("Background", "Loot Toast", "Interface\\LootFrame\\LootToast")
add("Background", "Petition Background", "Interface\\PetitionFrame\\PetitionBG")
add("Background", "Tabard Frame Background", "Interface\\TabardFrame\\TabardFrameBackground")
add("Background", "Inspect Background", "Interface\\PaperDollInfoFrame\\UI-Character-CharacterTab-L1")
add("Background", "Dressing Room", "Interface\\DressUpFrame\\DressUpBackground-Troll1")
add("Background", "Reforge Portrait", "Interface\\Reforging\\Reforge-Portrait")
add("Background", "Encounter Journal Background", "Interface\\EncounterJournal\\UI-EJ-Background")
add("Background", "Collections Journal Background", "Interface\\Collections\\CollectionsBackgroundTile")
add("Background", "Garrison Mission Background", "Interface\\Garrison\\GarrisonUIBackground")
add("Background", "Order Hall", "Interface\\OrderHall\\OrderHallMissionFrame")
add("Background", "Islands Queue", "Interface\\Islands\\IslandsQueue")

---------------------------------------------------------------------------
-- Borders / edges
---------------------------------------------------------------------------
add("Border", "Dialog Box Border", "Interface\\DialogFrame\\UI-DialogBox-Border")
add("Border", "Dialog Gold Border", "Interface\\DialogFrame\\UI-DialogBox-Gold-Border")
add("Border", "Tooltip Border", "Interface\\Tooltips\\UI-Tooltip-Border")
add("Border", "Common Input Border", "Interface\\Common\\Common-Input-Border")
add("Border", "Text Panel Border", "Interface\\Glues\\Common\\TextPanel-Border")
add("Border", "UI Frame", "Interface\\FrameGeneral\\UI-Frame")
add("Border", "UI Frame Inner Horizontal Break", "Interface\\FrameGeneral\\UI-Frame-InnerHorzBreak")
add("Border", "Friends Toast Border", "Interface\\FriendsFrame\\UI-Toast-Border")
add("Border", "Casting Bar Border", "Interface\\CastingBar\\UI-CastingBar-Border")
add("Border", "Casting Bar Border Shield", "Interface\\CastingBar\\UI-CastingBar-Border-Shield")
add("Border", "Minimap Border", "Interface\\Minimap\\UI-Minimap-Border")
add("Border", "Quest Icon Border", "Interface\\ContainerFrame\\UI-Icon-QuestBorder")
add("Border", "Action Button Border", "Interface\\Buttons\\UI-ActionButton-Border")
add("Border", "Empty Slot", "Interface\\Buttons\\UI-EmptySlot")
add("Border", "Empty Slot White", "Interface\\Buttons\\UI-EmptySlot-White")
add("Border", "Quickslot", "Interface\\Buttons\\UI-Quickslot")
add("Border", "Quickslot 2", "Interface\\Buttons\\UI-Quickslot2")
add("Border", "Quickslot Red", "Interface\\Buttons\\UI-QuickslotRed")
add("Border", "Talent Gold Border", "Interface\\TalentFrame\\UI-TalentFrame-GoldBorder")
add("Border", "Common Shadow", "Interface\\Common\\ShadowOverlay-Corner")
add("Border", "Dialog Divider", "Interface\\DialogFrame\\UI-DialogBox-Divider")

---------------------------------------------------------------------------
-- Status bars
---------------------------------------------------------------------------
add("StatusBar", "Status Bar", "Interface\\TargetingFrame\\UI-StatusBar")
add("StatusBar", "Skills Bar", "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
add("StatusBar", "Raid Health Fill", "Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
add("StatusBar", "Raid Resource Fill", "Interface\\RaidFrame\\Raid-Bar-Resource-Fill")
add("StatusBar", "Experience Bar", "Interface\\MainMenuBar\\UI-XP-Bar")
add("StatusBar", "Experience Mid", "Interface\\MainMenuBar\\UI-XP-Mid")
add("StatusBar", "Reputation Bar", "Interface\\PaperDollInfoFrame\\UI-Character-ReputationBar")
add("StatusBar", "Casting Bar", "Interface\\TargetingFrame\\UI-StatusBar")
add("StatusBar", "Unit Frame Health", "Interface\\TargetingFrame\\UI-StatusBar")
add("StatusBar", "Pet Paperdoll Health", "Interface\\PetPaperDollFrame\\UI-PetFrame-Health")
add("StatusBar", "Streaming Download", "Interface\\COMMON\\StreamBackground")
add("StatusBar", "Timer Bar", "Interface\\Timer\\Challenges-TimerBar")
add("StatusBar", "Garrison Follower Portrait", "Interface\\Garrison\\GarrisonFollowerPortrait")

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
add("Button", "Panel Button Up", "Interface\\Buttons\\UI-Panel-Button-Up")
add("Button", "Panel Button Down", "Interface\\Buttons\\UI-Panel-Button-Down")
add("Button", "Panel Button Highlight", "Interface\\Buttons\\UI-Panel-Button-Highlight")
add("Button", "Panel Button Disabled", "Interface\\Buttons\\UI-Panel-Button-Disabled")
add("Button", "Panel Button Disabled Down", "Interface\\Buttons\\UI-Panel-Button-Disabled-Down")
add("Button", "Dialog Button Up", "Interface\\Buttons\\UI-DialogBox-Button-Up")
add("Button", "Dialog Button Down", "Interface\\Buttons\\UI-DialogBox-Button-Down")
add("Button", "Dialog Button Highlight", "Interface\\Buttons\\UI-DialogBox-Button-Highlight")
add("Button", "Dialog Button Disabled", "Interface\\Buttons\\UI-DialogBox-Button-Disabled")
add("Button", "Square Button Up", "Interface\\Buttons\\UI-SquareButton-Up")
add("Button", "Square Button Down", "Interface\\Buttons\\UI-SquareButton-Down")
add("Button", "Square Button Disabled", "Interface\\Buttons\\UI-SquareButton-Disabled")
add("Button", "Square Button Highlight", "Interface\\Buttons\\UI-Common-MouseHilight")
add("Button", "Minus Button Up", "Interface\\Buttons\\UI-MinusButton-Up")
add("Button", "Minus Button Down", "Interface\\Buttons\\UI-MinusButton-Down")
add("Button", "Minus Button Disabled", "Interface\\Buttons\\UI-MinusButton-Disabled")
add("Button", "Plus Button Up", "Interface\\Buttons\\UI-PlusButton-Up")
add("Button", "Plus Button Down", "Interface\\Buttons\\UI-PlusButton-Down")
add("Button", "Plus Button Disabled", "Interface\\Buttons\\UI-PlusButton-Disabled")
add("Button", "Check Box Up", "Interface\\Buttons\\UI-CheckBox-Up")
add("Button", "Check Box Down", "Interface\\Buttons\\UI-CheckBox-Down")
add("Button", "Check Box Highlight", "Interface\\Buttons\\UI-CheckBox-Highlight")
add("Button", "Check Box Check", "Interface\\Buttons\\UI-CheckBox-Check")
add("Button", "Check Box Check Disabled", "Interface\\Buttons\\UI-CheckBox-Check-Disabled")
add("Button", "Radio Button", "Interface\\Buttons\\UI-RadioButton")
add("Button", "Scroll Up Button Up", "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
add("Button", "Scroll Up Button Down", "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
add("Button", "Scroll Up Button Disabled", "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled")
add("Button", "Scroll Up Button Highlight", "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
add("Button", "Scroll Down Button Up", "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
add("Button", "Scroll Down Button Down", "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
add("Button", "Scroll Down Button Disabled", "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled")
add("Button", "Scroll Down Button Highlight", "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
add("Button", "Scroll Bar Knob", "Interface\\Buttons\\UI-ScrollBar-Knob")
add("Button", "Minimize Button Up", "Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
add("Button", "Minimize Button Down", "Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
add("Button", "Minimize Button Disabled", "Interface\\Buttons\\UI-Panel-MinimizeButton-Disabled")
add("Button", "Hide Button Up", "Interface\\Buttons\\UI-Panel-HideButton-Up")
add("Button", "Bigger Button Up", "Interface\\Buttons\\UI-Panel-BiggerButton-Up")
add("Button", "Collapse Button Up", "Interface\\Buttons\\UI-Panel-CollapseButton-Up")
add("Button", "Expand Button Up", "Interface\\Buttons\\UI-Panel-ExpandButton-Up")
add("Button", "List Box Highlight", "Interface\\Buttons\\UI-ListBox-Highlight")
add("Button", "List Box Highlight 2", "Interface\\Buttons\\UI-Listbox-Highlight2")
add("Button", "Group Loot Pass Up", "Interface\\Buttons\\UI-GroupLoot-Pass-Up")
add("Button", "Group Loot Pass Down", "Interface\\Buttons\\UI-GroupLoot-Pass-Down")
add("Button", "Group Loot Pass Highlight", "Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
add("Button", "Group Loot Coin Up", "Interface\\Buttons\\UI-GroupLoot-Coin-Up")
add("Button", "Group Loot Dice Up", "Interface\\Buttons\\UI-GroupLoot-Dice-Up")
add("Button", "Yellow Button Up", "Interface\\Buttons\\UI-YellowButtonUp")
add("Button", "Silver Button Up", "Interface\\Buttons\\UI-SilverButtonUp")
add("Button", "Red Button Up", "Interface\\Buttons\\UI-RedButton-Up")
add("Button", "Blue Button Up", "Interface\\Buttons\\UI-BlueButton-Up")
add("Button", "Cancel Button Up", "Interface\\Buttons\\CancelButton-Up")
add("Button", "Lock Button Unlocked Up", "Interface\\Buttons\\LockButton-Unlocked-Up")
add("Button", "Lock Button Locked Up", "Interface\\Buttons\\LockButton-Locked-Up")
add("Button", "Tab Active", "Interface\\PaperDollInfoFrame\\UI-Character-ActiveTab")
add("Button", "Tab Inactive", "Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab")
add("Button", "Character Tab Left 1", "Interface\\PaperDollInfoFrame\\UI-Character-CharacterTab-L1")
add("Button", "Character Tab Left 2", "Interface\\PaperDollInfoFrame\\UI-Character-CharacterTab-L2")
add("Button", "Character Tab Right", "Interface\\PaperDollInfoFrame\\UI-Character-CharacterTab-R")

---------------------------------------------------------------------------
-- Frame chrome (full corner sets)
---------------------------------------------------------------------------
add("Frame", "Dialog Header", "Interface\\DialogFrame\\UI-DialogBox-Header")
add("Frame", "Macro Icon", "Interface\\MacroFrame\\MacroFrame-Icon")
add("Frame", "Loot Panel", "Interface\\LootFrame\\UI-LootPanel")
add("Frame", "Color Picker Frame", "Interface\\ColorPickerFrame\\ColorPickerFrame")
add("Frame", "Mail Popup", "Interface\\MailFrame\\MailPopup")

addCorners("Frame", "Help Frame", "Interface\\HelpFrame\\HelpFrame", "hyphen")
addCorners("Frame", "Character Frame", "Interface\\PaperDollInfoFrame\\UI-CharacterFrame", "hyphen")
addCorners("Frame", "Spellbook Panel", "Interface\\Spellbook\\UI-SpellbookPanel", "hyphen")
addCorners("Frame", "Friends Frame", "Interface\\FriendsFrame\\UI-FriendsFrame", "hyphen")
addCorners("Frame", "Merchant Frame", "Interface\\MerchantFrame\\UI-Merchant", "hyphen")
addCorners("Frame", "Taxi Frame", "Interface\\TaxiFrame\\UI-TaxiFrame", "hyphen")
addCorners("Frame", "Trade Frame", "Interface\\TradeFrame\\UI-TradeFrame", "hyphen")
addCorners("Frame", "Class Trainer", "Interface\\ClassTrainerFrame\\UI-ClassTrainer", "hyphen")
addCorners("Frame", "Arena Registrar", "Interface\\ArenaRegistrar\\UI-ArenaRegistrar", "hyphen")
addCorners("Frame", "Void Storage", "Interface\\VoidStorageFrame\\VoidStorage", "hyphen")
addCorners("Frame", "Key Binding Frame", "Interface\\KeyBindingFrame\\UI-KeyBindingFrame", "hyphen")

addCorners("Frame", "Options Frame", "Interface\\OptionsFrame\\UI-OptionsFrame", "glued")
addCorners("Frame", "Mail Frame", "Interface\\MailFrame\\MailFrame", "glued")
addCorners("Frame", "Item Text Frame", "Interface\\ItemTextFrame\\UI-ItemText", "glued")
addCorners("Frame", "Trade Skill", "Interface\\TradeSkillFrame\\UI-TradeSkill-Skill", "skill")

---------------------------------------------------------------------------
-- Action bar / bags bar
---------------------------------------------------------------------------
add("ActionBar", "Main Menu Bar", "Interface\\MainMenuBar\\UI-MainMenuBar-Dwarf")
add("ActionBar", "Action Bar End Cap Dwarf", "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf")
add("ActionBar", "Action Bar End Cap Human", "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Human")
add("ActionBar", "Action Button Slot", "Interface\\Buttons\\UI-Quickslot2")
add("ActionBar", "Bonus Action Bar", "Interface\\BonusActionBar\\UI-BonusActionBar")
add("ActionBar", "Page Button Background", "Interface\\Buttons\\UI-PageButton-Background")
add("ActionBar", "Micro Button Highlight", "Interface\\Buttons\\UI-MicroButton-Hilight")
add("ActionBar", "Micro Button Character Up", "Interface\\Buttons\\UI-MicroButton-Character-Up")
add("ActionBar", "Micro Button Spellbook Up", "Interface\\Buttons\\UI-MicroButton-Spellbook-Up")
add("ActionBar", "Micro Button Talents Up", "Interface\\Buttons\\UI-MicroButton-Talents-Up")
add("ActionBar", "Micro Button Quest Up", "Interface\\Buttons\\UI-MicroButton-Quest-Up")
add("ActionBar", "Micro Button Socials Up", "Interface\\Buttons\\UI-MicroButton-Socials-Up")
add("ActionBar", "Micro Button World Map Up", "Interface\\Buttons\\UI-MicroButton-WorldMap-Up")
add("ActionBar", "Micro Button Main Menu Up", "Interface\\Buttons\\UI-MicroButton-MainMenu-Up")
add("ActionBar", "Micro Button Help Up", "Interface\\Buttons\\UI-MicroButton-Help-Up")
add("ActionBar", "Backpack Button Up", "Interface\\Buttons\\Button-Backpack-Up")
add("ActionBar", "Key Ring Button", "Interface\\Buttons\\UI-Button-KeyRing")
add("ActionBar", "Vehicle Exit Button Up", "Interface\\Vehicles\\UI-Vehicles-Button-Exit-Up")
add("ActionBar", "Micro Button Looking For Group Up", "Interface\\Buttons\\UI-MicroButton-LFG-Up")

---------------------------------------------------------------------------
-- Character / paperdoll
---------------------------------------------------------------------------
add("Character", "Paperdoll Background", "Interface\\PaperDollInfoFrame\\UI-Character-CharacterTab-L1")
add("Character", "Stats Background", "Interface\\PaperDollInfoFrame\\SkillFrame-TopLeft")
add("Character", "Resistance Frame", "Interface\\PaperDollInfoFrame\\UI-Character-ResistanceFrame")
add("Character", "Ammo Slot", "Interface\\PaperDollInfoFrame\\UI-Character-AmmoSlot")
add("Character", "Skills Page Header", "Interface\\PaperDollInfoFrame\\UI-Character-SkillsPageHeader")
add("Character", "Honor Background", "Interface\\PVPFrame\\UI-Character-PVP")
add("Character", "Reputation Header", "Interface\\PaperDollInfoFrame\\UI-Character-ReputationBar")
add("Character", "Pet Happiness", "Interface\\PetPaperDollFrame\\UI-PetHappiness")
add("Character", "Equipment Manager Border", "Interface\\PaperDollInfoFrame\\UI-GearManager-Border")

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------
add("Chat", "Chat Frame Background", "Interface\\ChatFrame\\ChatFrameBackground")
add("Chat", "Chat Frame Inner Border", "Interface\\ChatFrame\\ChatFrameInnerBorder")
add("Chat", "Chat Frame Border", "Interface\\ChatFrame\\ChatFrameBorder")
add("Chat", "Chat Frame Color Swatch", "Interface\\ChatFrame\\ChatFrameColorSwatch")
add("Chat", "Chat Input Border", "Interface\\ChatFrame\\UI-ChatInputBorder")
add("Chat", "Chat Input Border Focus", "Interface\\ChatFrame\\UI-ChatInputBorder-Focus")
add("Chat", "Chat Tab Left", "Interface\\ChatFrame\\ChatFrameTab-Left")
add("Chat", "Chat Tab Mid", "Interface\\ChatFrame\\ChatFrameTab-Mid")
add("Chat", "Chat Tab Right", "Interface\\ChatFrame\\ChatFrameTab-Right")
add("Chat", "Chat Tab Selected Left", "Interface\\ChatFrame\\ChatFrameTab-SelectedLeft")
add("Chat", "Channel Button", "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
add("Chat", "Voice Chat", "Interface\\ChatFrame\\UI-ChatIcon-VoiceChat")

---------------------------------------------------------------------------
-- Bags / containers
---------------------------------------------------------------------------
add("Container", "Bag Background", "Interface\\ContainerFrame\\UI-Bag-1x4")
add("Container", "Bag 1 Slot", "Interface\\ContainerFrame\\UI-Bag-1Slot")
add("Container", "Bag Slot Background", "Interface\\Buttons\\UI-Slot-Background")
add("Container", "Bank Background", "Interface\\BankFrame\\Bank-Background")
add("Container", "Bank Frame", "Interface\\BankFrame\\UI-BankFrame")
add("Container", "Keyring Border", "Interface\\ContainerFrame\\KeyRing-Bag-Icon")
add("Container", "Item Border", "Interface\\Common\\WhiteIconFrame")
add("Container", "New Item Glow", "Interface\\Buttons\\UI-ActionButton-Border")

---------------------------------------------------------------------------
-- Quest / gossip
---------------------------------------------------------------------------
add("Quest", "Quest Background", "Interface\\QuestFrame\\QuestBG")
add("Quest", "Quest Log Title", "Interface\\QuestFrame\\UI-QuestTitleHighlight")
add("Quest", "Quest Log Title Highlight", "Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
add("Quest", "Available Quest", "Interface\\GossipFrame\\AvailableQuestIcon")
add("Quest", "Active Quest", "Interface\\GossipFrame\\ActiveQuestIcon")
add("Quest", "Binder Gossip", "Interface\\GossipFrame\\BinderGossipIcon")
add("Quest", "Taxi Gossip", "Interface\\GossipFrame\\TaxiGossipIcon")
add("Quest", "Trainer Gossip", "Interface\\GossipFrame\\TrainerGossipIcon")
add("Quest", "Vendor Gossip", "Interface\\GossipFrame\\VendorGossipIcon")
add("Quest", "Banker Gossip", "Interface\\GossipFrame\\BankerGossipIcon")
add("Quest", "Battle Master Gossip", "Interface\\GossipFrame\\BattleMasterGossipIcon")
add("Quest", "Petition Gossip", "Interface\\GossipFrame\\PetitionGossipIcon")
add("Quest", "Tabard Gossip", "Interface\\GossipFrame\\TabardGossipIcon")
add("Quest", "Healer Gossip", "Interface\\GossipFrame\\HealerGossipIcon")
add("Quest", "Daily Active Quest", "Interface\\GossipFrame\\DailyActiveQuestIcon")
add("Quest", "Daily Quest", "Interface\\GossipFrame\\DailyQuestIcon")

---------------------------------------------------------------------------
-- Targeting / unit frames
---------------------------------------------------------------------------
add("Targeting", "Target Frame", "Interface\\TargetingFrame\\UI-TargetingFrame")
add("Targeting", "Target Frame Elite", "Interface\\TargetingFrame\\UI-TargetingFrame-Elite")
add("Targeting", "Target Frame Rare", "Interface\\TargetingFrame\\UI-TargetingFrame-Rare")
add("Targeting", "Target Frame Rare Elite", "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite")
add("Targeting", "Target of Target", "Interface\\TargetingFrame\\UI-TargetofTargetFrame")
add("Targeting", "Party Frame", "Interface\\TargetingFrame\\UI-PartyFrame")
add("Targeting", "Focus Frame", "Interface\\TargetingFrame\\UI-FocusFrame")
add("Targeting", "Target Flash", "Interface\\TargetingFrame\\UI-TargetingFrame-Flash")
add("Targeting", "Status Bar Fill", "Interface\\TargetingFrame\\UI-StatusBar")
add("Targeting", "Status Bar Glow", "Interface\\TargetingFrame\\UI-StatusBar-Glow")
add("Targeting", "Raid Target Star", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
add("Targeting", "Raid Target Circle", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2")
add("Targeting", "Raid Target Diamond", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3")
add("Targeting", "Raid Target Triangle", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4")
add("Targeting", "Raid Target Moon", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5")
add("Targeting", "Raid Target Square", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6")
add("Targeting", "Raid Target Cross", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7")
add("Targeting", "Raid Target Skull", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
add("Targeting", "Combo Point", "Interface\\ComboFrame\\ComboPoint")

---------------------------------------------------------------------------
-- Minimap / map
---------------------------------------------------------------------------
add("Minimap", "Minimap Border", "Interface\\Minimap\\UI-Minimap-Border")
add("Minimap", "Minimap Background", "Interface\\Minimap\\UI-Minimap-Background")
add("Minimap", "Tracking Border", "Interface\\Minimap\\MiniMap-TrackingBorder")
add("Minimap", "Zoom In", "Interface\\Minimap\\UI-Minimap-ZoomInButton-Up")
add("Minimap", "Zoom Out", "Interface\\Minimap\\UI-Minimap-ZoomOutButton-Up")
add("Minimap", "Mailbox", "Interface\\Minimap\\Tracking\\Mailbox")
add("Minimap", "Ping Arrow", "Interface\\Minimap\\MinimapArrow")
add("Minimap", "Object Icons", "Interface\\Minimap\\ObjectIcons")
add("Minimap", "World Map Bottom 1", "Interface\\WorldMap\\UI-WorldMap-Bottom1")
add("Minimap", "World Map Icon", "Interface\\WorldMap\\WorldMap-Icon")
add("Minimap", "World Map Middle 1", "Interface\\WorldMap\\UI-WorldMapMiddle1")

---------------------------------------------------------------------------
-- Casting / mirror timers
---------------------------------------------------------------------------
add("Casting", "Casting Bar Border", "Interface\\CastingBar\\UI-CastingBar-Border")
add("Casting", "Casting Bar Flash", "Interface\\CastingBar\\UI-CastingBar-Flash")
add("Casting", "Casting Bar Spark", "Interface\\CastingBar\\UI-CastingBar-Spark")
add("Casting", "Casting Bar Border Shield", "Interface\\CastingBar\\UI-CastingBar-Border-Shield")
add("Casting", "Cooldown Edge", "Interface\\CooldownTimer\\edge")

---------------------------------------------------------------------------
-- Cooldown / swipe
---------------------------------------------------------------------------
add("Cooldown", "Edge", "Interface\\CooldownTimer\\edge")
add("Cooldown", "Swipe Mask", "Interface\\CooldownTimer\\Loc-button-mask")
add("Cooldown", "Spell Activation Overlay", "Interface\\SpellActivationOverlay\\IconAlert")

---------------------------------------------------------------------------
-- Icons (sample — there are thousands)
---------------------------------------------------------------------------
add("Icon", "Question Mark", "Interface\\Icons\\INV_Misc_QuestionMark")
add("Icon", "Ability Dual Wield", "Interface\\Icons\\Ability_DualWield")
add("Icon", "Trade Engineering", "Interface\\Icons\\Trade_Engineering")
add("Icon", "Spell Nature Lightning", "Interface\\Icons\\Spell_Nature_Lightning")
add("Icon", "Spell Holy Holy Bolt", "Interface\\Icons\\Spell_Holy_HolyBolt")
add("Icon", "Spell Fire Fireball", "Interface\\Icons\\Spell_Fire_Fireball02")
add("Icon", "Spell Frost Frostbolt", "Interface\\Icons\\Spell_Frost_FrostBolt02")
add("Icon", "Spell Shadow Shadowbolt", "Interface\\Icons\\Spell_Shadow_ShadowBolt")
add("Icon", "Spell Arcane Starfire", "Interface\\Icons\\Spell_Arcane_StarFire")
add("Icon", "Inventory Sword 04", "Interface\\Icons\\INV_Sword_04")
add("Icon", "Inventory Axe 01", "Interface\\Icons\\INV_Axe_01")
add("Icon", "Inventory Shield 01", "Interface\\Icons\\INV_Shield_01")
add("Icon", "Inventory Misc Book 09", "Interface\\Icons\\INV_Misc_Book_09")
add("Icon", "Inventory Misc Bag 08", "Interface\\Icons\\INV_Misc_Bag_08")
add("Icon", "Inventory Misc Coin 01", "Interface\\Icons\\INV_Misc_Coin_01")
add("Icon", "Inventory Potion 54", "Interface\\Icons\\INV_Potion_54")
add("Icon", "Inventory Scroll 03", "Interface\\Icons\\INV_Scroll_03")
add("Icon", "Spell Charge Positive", "Interface\\Icons\\Spell_ChargePositive")
add("Icon", "Spell Charge Negative", "Interface\\Icons\\Spell_ChargeNegative")
add("Icon", "Ability Warrior Charge", "Interface\\Icons\\Ability_Warrior_Charge")
add("Icon", "Ability Rogue Sprint", "Interface\\Icons\\Ability_Rogue_Sprint")
add("Icon", "Ability Hunter Aimed Shot", "Interface\\Icons\\Ability_Hunter_AimedShot")
add("Icon", "Ability Druid Bash", "Interface\\Icons\\Ability_Druid_Bash")
add("Icon", "Spell Fire Fireball Alternate", "Interface\\Icons\\Spell_Fire_Fireball")
add("Icon", "Class Icon Warrior", "Interface\\Icons\\ClassIcon_Warrior")
add("Icon", "Class Icon Mage", "Interface\\Icons\\ClassIcon_Mage")
add("Icon", "Class Icon Priest", "Interface\\Icons\\ClassIcon_Priest")

---------------------------------------------------------------------------
-- Glues / login / character select
---------------------------------------------------------------------------
add("Glues", "Account Login", "Interface\\Glues\\AccountLogin\\UI-AccountLogin")
add("Glues", "Character Select Background", "Interface\\Glues\\CharacterSelect\\Glue-CharacterSelect-Background")
add("Glues", "Character Create Label Frame", "Interface\\Glues\\CharacterCreate\\CharacterCreate-LabelFrame")
add("Glues", "Credits Frame", "Interface\\Glues\\Credits\\TrollFemale1")
add("Glues", "Loading Bar", "Interface\\Glues\\LoadingBar\\UI-LoadingBar")
add("Glues", "Text Panel Border", "Interface\\Glues\\Common\\TextPanel-Border")
add("Glues", "Glue Panel Button Up", "Interface\\Glues\\Common\\Glue-Panel-Button-Up")
add("Glues", "Glue Panel Button Down", "Interface\\Glues\\Common\\Glue-Panel-Button-Down")
add("Glues", "Glue Panel Button Disabled Up", "Interface\\Glues\\Common\\Glue-Panel-Button-Disabled-Up")

---------------------------------------------------------------------------
-- Misc
---------------------------------------------------------------------------
add("Misc", "Tooltip Divider", "Interface\\Common\\UI-TooltipDivider-Transparent")
add("Misc", "Shadow Overlay", "Interface\\Common\\ShadowOverlay-Corner")
add("Misc", "Action Button Border", "Interface\\Buttons\\UI-ActionButton-Border")
add("Misc", "Button Highlight Square", "Interface\\Buttons\\ButtonHilight-Square")
add("Misc", "Common Mouse Highlight", "Interface\\Buttons\\UI-Common-MouseHilight")
add("Misc", "Minimap Background", "Interface\\Minimap\\UI-Minimap-Background")
add("Misc", "Spell Activation Alert", "Interface\\SpellActivationOverlay\\IconAlert")
add("Misc", "Level Up Banner", "Interface\\LevelUp\\LevelUpSpigot")
add("Misc", "Raid Frame Threat", "Interface\\RaidFrame\\UI-RaidFrame-Threat")
add("Misc", "Money Frame", "Interface\\MoneyFrame\\UI-MoneyFrame")
add("Misc", "Money Icons", "Interface\\MoneyFrame\\UI-MoneyIcons")
add("Misc", "Gold Coin Icon", "Interface\\MoneyFrame\\UI-GoldIcon")
add("Misc", "Silver Coin Icon", "Interface\\MoneyFrame\\UI-SilverIcon")
add("Misc", "Copper Coin Icon", "Interface\\MoneyFrame\\UI-CopperIcon")
add("Misc", "Player versus Player Elements", "Interface\\PVPFrame\\UI-Character-PVP-Elements")
add("Misc", "Player versus Player Banner", "Interface\\PVPFrame\\UI-PVP-BANNER")
add("Misc", "Ready Check Ready", "Interface\\RaidFrame\\ReadyCheck-Ready")
add("Misc", "Ready Check Not Ready", "Interface\\RaidFrame\\ReadyCheck-NotReady")
add("Misc", "Ready Check Waiting", "Interface\\RaidFrame\\ReadyCheck-Waiting")
add("Misc", "Loot Panel", "Interface\\LootFrame\\UI-LootPanel")
add("Misc", "Vehicle Seat Indicator", "Interface\\Vehicles\\SeatIndicator")
add("Misc", "Streaming Background", "Interface\\COMMON\\StreamBackground")
add("Misc", "Full Screen Out Of Control", "Interface\\FullScreenTextures\\OutOfControl")

Addon.TEXTURES = TEXTURES

Addon.FONT_OBJECTS = {
	{ name = "GameFontNormal", value = "GameFontNormal" },
	{ name = "GameFontNormalLarge", value = "GameFontNormalLarge" },
	{ name = "GameFontNormalHuge", value = "GameFontNormalHuge" },
	{ name = "GameFontNormalSmall", value = "GameFontNormalSmall" },
	{ name = "GameFontHighlight", value = "GameFontHighlight" },
	{ name = "GameFontHighlightLarge", value = "GameFontHighlightLarge" },
	{ name = "GameFontHighlightSmall", value = "GameFontHighlightSmall" },
	{ name = "GameFontDisable", value = "GameFontDisable" },
	{ name = "GameFontDisableLarge", value = "GameFontDisableLarge" },
	{ name = "GameFontDisableSmall", value = "GameFontDisableSmall" },
	{ name = "GameFontWhite", value = "GameFontWhite" },
	{ name = "GameFontGreen", value = "GameFontGreen" },
	{ name = "GameFontRed", value = "GameFontRed" },
	{ name = "GameFontBlackMedium", value = "GameFontBlackMedium" },
	{ name = "NumberFontNormal", value = "NumberFontNormal" },
	{ name = "NumberFontNormalLarge", value = "NumberFontNormalLarge" },
	{ name = "NumberFontNormalHuge", value = "NumberFontNormalHuge" },
	{ name = "NumberFontNormalSmall", value = "NumberFontNormalSmall" },
	{ name = "QuestFont", value = "QuestFont" },
	{ name = "QuestFontNormalSmall", value = "QuestFontNormalSmall" },
	{ name = "QuestTitleFont", value = "QuestTitleFont" },
	{ name = "MailTextFontNormal", value = "MailTextFontNormal" },
	{ name = "ChatFontNormal", value = "ChatFontNormal" },
	{ name = "ChatFontSmall", value = "ChatFontSmall" },
	{ name = "SystemFont_Med1", value = "SystemFont_Med1" },
	{ name = "SystemFont_Med2", value = "SystemFont_Med2" },
	{ name = "SystemFont_Med3", value = "SystemFont_Med3" },
	{ name = "SystemFont_Large", value = "SystemFont_Large" },
	{ name = "SystemFont_Shadow_Med1", value = "SystemFont_Shadow_Med1" },
	{ name = "SystemFont_Shadow_Med2", value = "SystemFont_Shadow_Med2" },
	{ name = "SystemFont_Shadow_Large", value = "SystemFont_Shadow_Large" },
	{ name = "Fancy12Font", value = "Fancy12Font" },
	{ name = "Fancy14Font", value = "Fancy14Font" },
	{ name = "Fancy16Font", value = "Fancy16Font" },
	{ name = "Fancy18Font", value = "Fancy18Font" },
	{ name = "Fancy20Font", value = "Fancy20Font" },
	{ name = "Fancy22Font", value = "Fancy22Font" },
	{ name = "Fancy24Font", value = "Fancy24Font" },
	{ name = "FriendsFont_Normal", value = "FriendsFont_Normal" },
	{ name = "FriendsFont_Large", value = "FriendsFont_Large" },
	{ name = "Tooltip_Med", value = "GameTooltipText" },
	{ name = "Tooltip_Small", value = "GameTooltipTextSmall" },
}

Addon.BUTTON_LABELS = {
	{ name = "Sample Button", value = "Sample Button" },
	{ name = "OK", value = "OK" },
	{ name = "Cancel", value = "Cancel" },
	{ name = "Apply", value = "Apply" },
	{ name = "Save", value = "Save" },
	{ name = "Close", value = "Close" },
	{ name = "Options", value = "Options" },
	{ name = "Accept", value = "Accept" },
	{ name = "Decline", value = "Decline" },
	{ name = "Custom", value = "custom" },
}

Addon.BUTTON_STYLES = {
	{
		id = "UIPanelButtonTemplate",
		name = "UIPanelButtonTemplate",
		template = "UIPanelButtonTemplate",
		desc = "Standard Blizzard panel button",
	},
	{
		id = "UIPanelCloseButton",
		name = "UIPanelCloseButton",
		template = "UIPanelCloseButton",
		desc = "Window close (X) button",
		fixedSize = true,
	},
	{
		id = "custom-textures",
		name = "Custom textures",
		template = nil,
		desc = "Manual normal / pushed / highlight / disabled textures",
		custom = true,
	},
	{
		id = "solid-swatch",
		name = "Solid swatch",
		template = nil,
		desc = "Flat colored button with border (no Blizzard chrome)",
		solid = true,
	},
}

Addon.PRESET_PALETTES = {
	{ name = "Gold", r = 1.00, g = 0.82, b = 0.00 },
	{ name = "White", r = 1.00, g = 1.00, b = 1.00 },
	{ name = "Soft White", r = 0.90, g = 0.90, b = 0.90 },
	{ name = "Gray", r = 0.55, g = 0.55, b = 0.55 },
	{ name = "Dark", r = 0.12, g = 0.12, b = 0.14 },
	{ name = "Black", r = 0.00, g = 0.00, b = 0.00 },
	{ name = "WenDing Cyan", r = 0.20, g = 0.80, b = 1.00 },
	{ name = "Native Experience Purple", r = 0.58, g = 0.00, b = 0.55 },
	{ name = "Quest Yellow", r = 1.00, g = 0.82, b = 0.00 },
	{ name = "Friendly Green", r = 0.00, g = 1.00, b = 0.00 },
	{ name = "Hostile Red", r = 1.00, g = 0.10, b = 0.10 },
	{ name = "Rare Blue", r = 0.00, g = 0.44, b = 0.87 },
	{ name = "Epic Purple", r = 0.64, g = 0.21, b = 0.93 },
	{ name = "Legendary Orange", r = 1.00, g = 0.50, b = 0.00 },
}

function Addon.GetButtonLabelText(db)
	db = db or Addon.EnsureDB().button
	if db.labelPreset == "custom" then
		local t = db.customText
		if not t or t == "" then
			return "Custom"
		end
		return t
	end
	return db.labelPreset or "Sample Button"
end

function Addon.FilterTextures(category, search)
	local needle = search and string.lower(search) or ""
	needle = needle:match("^%s*(.-)%s*$") or ""
	local out = {}
	for _, entry in ipairs(Addon.TEXTURES) do
		if not category or category == "All" or entry.category == category then
			if needle == ""
				or string.find(string.lower(entry.name), needle, 1, true)
				or string.find(string.lower(entry.path), needle, 1, true)
				or string.find(string.lower(entry.category), needle, 1, true)
			then
				out[#out + 1] = entry
			end
		end
	end
	return out
end

function Addon.GetTexturesByCategory(category)
	return Addon.FilterTextures(category, "")
end

function Addon.FindTexture(path)
	for _, entry in ipairs(Addon.TEXTURES) do
		if entry.path == path then
			return entry
		end
	end
	return nil
end
