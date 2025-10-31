-- MoPRaidIDTracker - Minimap tooltip
-- Author: Domekologe
-- Comments: English; Locales are split (en/de)

local ADDON, _ = ...

local locale = GetLocale()
local L = MoPRID_Locale[locale] or MoPRID_Locale["enUS"]

-- ---- SavedVars ----
MoPRIDDB = MoPRIDDB or {}
MoPRIDDB.minimap = MoPRIDDB.minimap or { hide = false }
MoPRIDDB.chars   = MoPRIDDB.chars   or {}
MoPRIDDB.weeklyId = MoPRIDDB.weeklyId or nil
MoPRIDDB.iconSize = MoPRIDDB.iconSize or 12

local function playerKey()
  local name, realm = UnitName("player"), GetRealmName()
  return (realm or "Realm") .. "/" .. (name or "Player")
end

-- Raid Data

local RaidIDs = {
	{name = L.MSV, short = L.MSV_SHORT, instanceID = 1008},
	{name = L.HoF, short = L.HoF_SHORT, instanceID = 1009},
	{name = L.ToeS, short = L.ToeS_SHORT, instanceID = 996},
	{name = L.ToT, short = L.ToT_SHORT, instanceID = 1098},
	{name = L.SoO, short = L.SoO_SHORT, instanceID = 1136},
}

-- ---- Weekly reset calculation ----
local function SecondsUntilWeeklyReset()
  if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
    local s = C_DateAndTime.GetSecondsUntilWeeklyReset()
    if type(s) == "number" and s >= 0 then return s end
  end
  -- EU fallback
  local now = GetServerTime and GetServerTime() or time()
  local t = date("*t", now)
  local resetHour = (t.isdst == false) and 3 or 6
  local targetWday = 4 -- Wednesday
  local todayMid = now - (t.hour*3600 + t.min*60 + t.sec)
  local thisWedMid = todayMid + ((targetWday - t.wday) % 7) * 86400
  local resetTime = thisWedMid + resetHour * 3600
  if now < resetTime then
    return resetTime - now
  else
    return resetTime + 7*86400 - now
  end
end

local function CurrentWeeklyId()
  local now = GetServerTime and GetServerTime() or time()
  local secs = SecondsUntilWeeklyReset()
  local nextReset = now + secs
  return math.floor(nextReset / 604800)
end

-- ---- Icons ----
local function StatusText(done)
  if done then
    return "|cff00ff00" .. L.KILLED .. "|r"
  else
    return "|cffff2020" .. L.NOT_KILLED .. "|r"
  end
end

local function SecondsToDHMS(s)
  if not s or s <= 0 then return L.UNKNOWN end
  local d = math.floor(s/86400); s = s - d*86400
  local h = math.floor(s/3600);  s = s - h*3600
  local m = math.floor(s/60)
  if d > 0 then
    return string.format("%dd %02dh %02dm", d, h, m)
  else
    return string.format("%02dh %02dm", h, m)
  end
end

-- ---- Update current character's saved raid lockouts ----
local function UpdateCurrentCharacterRaids()
  MoPRIDDB.chars = MoPRIDDB.chars or {}
  local key = playerKey()
  MoPRIDDB.chars[key] = MoPRIDDB.chars[key] or { class = select(2, UnitClass("player")), raids = {} }

  local entry = MoPRIDDB.chars[key]
  entry.class = select(2, UnitClass("player"))
  entry.lastUpdate = GetServerTime and GetServerTime() or time()
  entry.raids = {}

  for i = 1, GetNumSavedInstances() do
    local name, lockoutId, resetSec, difficultyId, locked,
          extended, instanceIDMostSig, isRaid, maxPlayers,
          difficultyName, numEncounters, encounterProgress,
          extendDisabled, instanceId = GetSavedInstanceInfo(i)

    if isRaid then
      entry.raids[instanceId] = {
        name = name,
        locked = locked,
        reset = resetSec,
        difficultyName = difficultyName,
        progress = encounterProgress,
        numEncounters = numEncounters,
        extended = extended,
      }
    end
  end
end


-- ---- Weekly reset rollover ----
local function EnsureWeekly()
  MoPRIDDB.chars = MoPRIDDB.chars or {}
  local wid = CurrentWeeklyId()
  if MoPRIDDB.weeklyId ~= wid then
    for _, charData in pairs(MoPRIDDB.chars) do
      if type(charData) == "table" and type(charData.raids) == "table" then
        for id, raid in pairs(charData.raids) do
          raid.locked = false
        end
      end
    end
    MoPRIDDB.weeklyId = wid
  end
end

-- ---- Libs / DataObject ----
local hasLDB = LibStub and LibStub("LibDataBroker-1.1", true)
local iconLib = LibStub and LibStub("LibDBIcon-1.0", true)


local dataobj
if hasLDB then
  dataobj = hasLDB:NewDataObject("MoPRaidIDTracker", {
    type = "data source",
    icon = 134230,
    text = "MoP RID",
    OnTooltipShow = function(tt)
	  tt:ClearLines()
	  tt:AddLine(L.ADDON_NAME)
	  tt:AddLine(" ")
	  tt:AddLine("|cffaaaaaaLoading raid data...|r")
	  tt:Show()

	  -- Request raid info update
	  RequestRaidInfo()

	  -- Create temporary frame to wait for event
	  local listener = CreateFrame("Frame")
	  listener:RegisterEvent("UPDATE_INSTANCE_INFO")
	  listener:SetScript("OnEvent", function(self)
		self:UnregisterEvent("UPDATE_INSTANCE_INFO")

		EnsureWeekly()
		UpdateCurrentCharacterRaids()

		tt:ClearLines()
		tt:AddLine(L.ADDON_NAME)
		tt:AddLine(" ")

		local reset = SecondsUntilWeeklyReset()
		tt:AddDoubleLine(L.RESET_IN .. ":", SecondsToDHMS(reset))

		tt:AddLine(" ")
		local header = "   "
		for _, raid in ipairs(RaidIDs) do
		  header = header .. "|cffaaaaaa" .. raid.short .. "|r  "
		end
		tt:AddDoubleLine(L.ALL_CHARS .. ":", header)

		for key, cdata in pairs(MoPRIDDB.chars) do
		  if type(cdata) == "table" and type(cdata.raids) == "table" then
			local line = "   "
			for _, raid in ipairs(RaidIDs) do
			  local entry = cdata.raids[raid.instanceID]
			  if entry and entry.locked then
				line = line .. "|cffff2020" .. raid.short .. "|r  "
			  else
				line = line .. "|cff00ff00" .. raid.short .. "|r  "
			  end
			end
			tt:AddDoubleLine(key, line)
		  end
		end

		tt:AddLine(" ")
		tt:AddLine(L.CURRENT_CHAR .. ":")

		for instanceId, raid in pairs(MoPRIDDB.chars[playerKey()].raids or {}) do
		  local color = raid.locked and "|cffff2020" or "|cff00ff00"
		  local status = raid.locked and L.LOCKED or L.CLEARED
		  local timeLeft = SecondsToDHMS(raid.reset)

		  tt:AddDoubleLine(
			string.format("%s (%s)", raid.name, raid.difficultyName or ""),
			string.format("%s%s|r  |cffaaaaaa(%s left)|r", color, status, timeLeft)
		  )
		end



		tt:Show()
	  end)
	end,


  })
end


-- ---- Initialization ----
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")

f:SetScript("OnEvent", function(self, event, name)
  if event == "ADDON_LOADED" and name == ADDON then
    MoPRIDDB = MoPRIDDB or {}
    MoPRIDDB.minimap = MoPRIDDB.minimap or { hide = false }
    MoPRIDDB.chars   = MoPRIDDB.chars or {}
    MoPRIDDB.iconSize = MoPRIDDB.iconSize or 12

    if dataobj and iconLib then
      iconLib:Register("MoPRaidIDTracker", dataobj, MoPRIDDB.minimap)
      if not MoPRIDDB.minimap.hide then iconLib:Show("MoPRaidIDTracker") end
    end
  elseif (event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED") then
    EnsureWeekly()
    RequestRaidInfo()
    C_Timer.After(2, UpdateCurrentCharacterRaids)
  end
end)
