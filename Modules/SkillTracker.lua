-- Skill ups for the Loot UI (WoW Forever): professions, secondary skills, and optionally weapon skills and Defense.
-- SKILL_LINES_CHANGED carries no payload, so we cache every skill line's rank and compare, like ReputationTracker.


local _, addon = ...

if not (C_SkillInfo and C_SkillInfo.GetSkillLineInfo) then return end;


local GetNumSkillLines = C_SkillInfo.GetNumSkillLines;
local GetSkillLineInfo = C_SkillInfo.GetSkillLineInfo;
local GetSkillLineInfoByID = C_SkillInfo.GetSkillLineInfoByID;
local Secret_CanAccess = addon.API.Secret_CanAccess;
local GetInventoryItemTexture = GetInventoryItemTexture;


local EL = CreateFrame("Frame");
EL.rankCache = {};	--[skillID] = rank

EL.staticEvents = {
	"SKILL_LINES_CHANGED",
	"PLAYER_ENTERING_WORLD",
};

-- Skill line IDs from Wowhead's Forever database
local WEAPON_SKILLS = {
	[43] = true,	--Swords
	[44] = true,	--Axes
	[45] = true,	--Bows
	[46] = true,	--Guns
	[54] = true,	--Maces
	[55] = true,	--Two-Handed Swords
	[95] = true,	--Defense
	[136] = true,	--Staves
	[160] = true,	--Two-Handed Maces
	[162] = true,	--Unarmed
	[172] = true,	--Two-Handed Axes
	[173] = true,	--Daggers
	[176] = true,	--Thrown
	[226] = true,	--Crossbows
	[228] = true,	--Wands
	[229] = true,	--Polearms
	[473] = true,	--Fist Weapons
};

local RANGED_SKILLS = {
	[45] = true, [46] = true, [176] = true, [226] = true, [228] = true,
};

local SKILL_ICONS = {
	[129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",		--First Aid
	[164] = "Interface\\Icons\\Trade_BlackSmithing",
	[165] = "Interface\\Icons\\Trade_LeatherWorking",
	[171] = "Interface\\Icons\\Trade_Alchemy",
	[182] = "Interface\\Icons\\Spell_Nature_NatureTouchGrow",	--Herbalism
	[185] = "Interface\\Icons\\INV_Misc_Food_15",				--Cooking
	[186] = "Interface\\Icons\\Trade_Mining",
	[197] = "Interface\\Icons\\Trade_Tailoring",
	[202] = "Interface\\Icons\\Trade_Engineering",
	[333] = "Interface\\Icons\\Trade_Engraving",				--Enchanting
	[356] = "Interface\\Icons\\Trade_Fishing",
	[393] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",			--Skinning
	[633] = "Interface\\Icons\\Spell_Nature_MoonKey",			--Lockpicking
	[762] = "Interface\\Icons\\Ability_Hunter_BeastTaming",		--Riding
};

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Book_08";
local DEFENSE_ICON = "Interface\\Icons\\Ability_Defend";


local function GetProfessionIcon(skillID)
	if not (GetProfessions and GetProfessionInfo) then return end;
	local professions = {GetProfessions()};
	for _, index in pairs(professions) do
		local _, icon, _, _, _, _, skillLine = GetProfessionInfo(index);
		if skillLine == skillID then
			return icon
		end
	end
end

function EL:GetSkillIcon(skillID)
	if WEAPON_SKILLS[skillID] then
		if skillID == 95 then
			return DEFENSE_ICON
		end
		local slot = RANGED_SKILLS[skillID] and 18 or 16;
		return GetInventoryItemTexture("player", slot) or DEFAULT_ICON
	end
	return SKILL_ICONS[skillID] or GetProfessionIcon(skillID) or DEFAULT_ICON
end

function EL:ShouldShowSkill(skillID)
	if WEAPON_SKILLS[skillID] then
		return self.showWeapon
	else
		return self.showProfession
	end
end

-- Visible skill lines only: a collapsed header hides its lines, so known lines are also read by ID.
function EL:ReadSkillLines()
	local lines = {};
	for i = 1, GetNumSkillLines() do
		local info = GetSkillLineInfo(i);
		if info and info.skillID and not info.isHeader then
			lines[info.skillID] = info;
		end
	end
	for skillID in pairs(self.rankCache) do
		if not lines[skillID] then
			lines[skillID] = GetSkillLineInfoByID(skillID);
		end
	end
	return lines
end

function EL:UpdateSkills()
	local lines = self:ReadSkillLines();

	for _, info in pairs(lines) do
		if not (Secret_CanAccess(info.rank) and Secret_CanAccess(info.name)) then
			-- Unreadable in combat: compare once it ends, the cache still holds the old ranks
			self:RegisterEvent("PLAYER_REGEN_ENABLED");
			return
		end
	end

	for skillID, info in pairs(lines) do
		local oldRank = self.rankCache[skillID];
		self.rankCache[skillID] = info.rank;
		if oldRank and info.rank > oldRank and self:ShouldShowSkill(skillID) then
			addon.LootUI.QueueDisplaySkill(skillID, info.name, info.rank - oldRank, info.rank, info.maxRank, self:GetSkillIcon(skillID));
		end
	end
end

function EL:CacheSkills()
	self.rankCache = {};
	for skillID, info in pairs(self:ReadSkillLines()) do
		if Secret_CanAccess(info.rank) then
			self.rankCache[skillID] = info.rank;
		end
	end
	for skillID in pairs(WEAPON_SKILLS) do
		if not self.rankCache[skillID] then
			local info = GetSkillLineInfoByID(skillID);
			if info and Secret_CanAccess(info.rank) then
				self.rankCache[skillID] = info.rank;
			end
		end
	end
end

function EL:OnEvent(event)
	if event == "SKILL_LINES_CHANGED" or event == "PLAYER_REGEN_ENABLED" then
		if event == "PLAYER_REGEN_ENABLED" then
			self:UnregisterEvent(event);
		end
		self:RequestUpdate();
	elseif event == "PLAYER_ENTERING_WORLD" then
		self:CacheSkills();
	end
end

function EL:RequestUpdate()
	-- The event comes in bursts (training, learning a recipe): read once they settle
	self.t = 0;
	self:SetScript("OnUpdate", self.OnUpdate);
end

function EL:OnUpdate(elapsed)
	self.t = self.t + elapsed;
	if self.t > 0.1 then
		self:SetScript("OnUpdate", nil);
		self:UpdateSkills();
	end
end

function EL:UpdateState()
	local enabled = self.showProfession or self.showWeapon;
	if enabled and not self.enabled then
		self.enabled = true;
		self:CacheSkills();
		addon.API.RegisterFrameForEvents(self, self.staticEvents);
		self:SetScript("OnEvent", self.OnEvent);
	elseif (not enabled) and self.enabled then
		self.enabled = nil;
		addon.API.UnregisterFrameForEvents(self, self.staticEvents);
		self:UnregisterEvent("PLAYER_REGEN_ENABLED");
		self:SetScript("OnEvent", nil);
		self:SetScript("OnUpdate", nil);
	end
end

addon.CallbackRegistry:RegisterCallback("SettingChanged.LootUI_ShowSkillUps", function(state)
	EL.showProfession = state;
	EL:UpdateState();
end);

addon.CallbackRegistry:RegisterCallback("SettingChanged.LootUI_ShowWeaponSkillUps", function(state)
	EL.showWeapon = state;
	EL:UpdateState();
end);
