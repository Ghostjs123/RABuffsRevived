-- RABuffs: Saved settings, profiles, events and the refresh loop that drives everything else.
local ADDON, RAB = ...
_G.RABuffs = RAB

local L = RAB.L
local Compat = RAB.Compat

do
    local ok, version = pcall(C_AddOns.GetAddOnMetadata, ADDON, "Version")
    RAB.version = ok and version or "?"
end

local DEFAULT_SETTINGS = {
    showSolo = true,
    showParty = true,
    showRaid = true,
    hideInCombat = false,
    hideComplete = false,
    locked = false,
    groupDefault = false,
    announce = true,
    skipPvP = true,
    scale = 1,
    width = 160,
    interval = 1,
}

RAB.members = {}  -- this refresh's group members, see BuildMembers
RAB.roster = {}

-- =================================================================
-- Printing
-- =================================================================

function RAB:Print(message, kind)
    local color = "ff4d80ff"
    if kind == "warn" then
        color = "ffffcc00"
    elseif kind == "ok" then
        color = "ff00b300"
    end
    DEFAULT_CHAT_FRAME:AddMessage("|c" .. color .. "RABuffs|r " .. message)
end

-- "45s", "3m", "1h"
function RAB.FormatTime(seconds)
    seconds = math.floor(seconds or 0)
    if seconds < 60 then
        return seconds .. "s"
    elseif seconds < 3600 then
        return math.floor(seconds / 60) .. "m"
    end
    return math.floor(seconds / 3600) .. "h"
end

-- =================================================================
-- Saved variables and profiles
-- =================================================================

local function CopyBars(bars)
    local out = {}
    for i, bar in ipairs(bars) do
        out[i] = CopyTable(bar)
    end
    return out
end

-- Fills in fields an old or imported bar may lack
local function NormalizeBar(bar)
    bar.groups = bar.groups or ""
    bar.classes = bar.classes or ""
    bar.color = bar.color or { 0.5, 0.5, 0.5 }
    if bar.castOnClick == nil then
        bar.castOnClick = true
    end
    bar.output = bar.output or "RAID"
    bar.exclude = bar.exclude or {}
    return bar
end

local function DefaultBarsFor(classToken)
    local bars = {}
    for _, bar in ipairs(RAB.DefaultBars.ALL) do
        bars[#bars + 1] = NormalizeBar(CopyTable(bar))
    end
    for _, bar in ipairs(RAB.DefaultBars[classToken] or {}) do
        bars[#bars + 1] = NormalizeBar(CopyTable(bar))
    end
    return bars
end

function RAB:CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

function RAB:InitDB()
    RABuffsDB = RABuffsDB or {}
    local db = RABuffsDB
    db.version = 1
    db.settings = db.settings or {}
    for key, value in pairs(DEFAULT_SETTINGS) do
        if db.settings[key] == nil then
            db.settings[key] = value
        end
    end
    db.profiles = db.profiles or {}
    db.charProfile = db.charProfile or {}
    RABuffsCharDB = RABuffsCharDB or {}

    self.db = db
    self.settings = db.settings
    self.charDB = RABuffsCharDB

    -- A character without a profile starts on one for its class ("Priest"), shared by every priest
    local name = db.charProfile[self:CharKey()]
    if not name or not db.profiles[name] then
        local className, classToken = UnitClass("player")
        name = className or "Default"
        if not db.profiles[name] then
            db.profiles[name] = { bars = DefaultBarsFor(classToken) }
        end
        db.charProfile[self:CharKey()] = name
    end
    self:UseProfile(name)
end

function RAB:UseProfile(name)
    self.profileName = name
    self.db.charProfile[self:CharKey()] = name
    self.bars = self.db.profiles[name].bars
    for i = #self.bars, 1, -1 do
        local bar = NormalizeBar(self.bars[i])
        if not RAB.Buffs[bar.buffKey] then
            self:Print(string.format(L.UnknownBuff, tostring(bar.buffKey)), "warn")
            table.remove(self.bars, i)
        end
    end
end

-- Bars changed (added, removed, edited, reordered, another profile): rebuild what shows
function RAB:BarsChanged()
    if self.UI then
        self.UI:RebuildBars()
    end
    if self.Options then
        self.Options:Refresh()
    end
    self:RequestRefresh()
end

function RAB:ProfileNames()
    local names = {}
    for name in pairs(self.db.profiles) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

function RAB:LoadProfile(name)
    if not self.db.profiles[name] then
        self:Print(string.format(L.ProfileMissing, name), "warn")
        return false
    end
    self:UseProfile(name)
    self:BarsChanged()
    self:Print(string.format(L.ProfileLoaded, name), "ok")
    return true
end

-- Copies the current bars into a profile (new or existing) and switches to it
function RAB:SaveProfileAs(name)
    name = strtrim(name or "")
    if name == "" then
        return false
    end
    self.db.profiles[name] = { bars = CopyBars(self.bars) }
    self:UseProfile(name)
    self:BarsChanged()
    self:Print(string.format(L.ProfileSaved, name), "ok")
    return true
end

function RAB:DeleteProfile(name)
    if not self.db.profiles[name] then
        self:Print(string.format(L.ProfileMissing, name), "warn")
        return false
    end
    if name == self.profileName then
        self:Print(string.format(L.ProfileCantDeleteCurrent, name), "warn")
        return false
    end
    self.db.profiles[name] = nil
    for char, profile in pairs(self.db.charProfile) do
        if profile == name then
            self.db.charProfile[char] = nil
        end
    end
    self:Print(string.format(L.ProfileDeleted, name), "ok")
    if self.Options then
        self.Options:Refresh()
    end
    return true
end

-- Export format: "RABuffs1" then one line per bar of escaped fields. Plain text, never run as code, so a
-- pasted profile can't do anything but describe bars.
local FIELD_SEP, LIST_SEP = "|", ","

local function Escape(s)
    return (tostring(s):gsub("[%%|,\n]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

local function Unescape(s)
    return (s:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

function RAB:ExportProfile()
    local lines = { "RABuffs1" }
    for _, bar in ipairs(self.bars) do
        local excluded = {}
        for _, name in ipairs(bar.exclude) do
            excluded[#excluded + 1] = Escape(name)
        end
        lines[#lines + 1] = table.concat({
            Escape(bar.buffKey),
            Escape(bar.label or ""),
            string.format("%.2f,%.2f,%.2f", bar.color[1], bar.color[2], bar.color[3]),
            Escape(bar.groups),
            Escape(bar.classes),
            bar.selfOnly and "1" or "0",
            bar.castOnClick and "1" or "0",
            Escape(bar.output),
            table.concat(excluded, LIST_SEP),
            Escape(bar.custom or ""),
        }, FIELD_SEP)
    end
    return table.concat(lines, "\n")
end

local function ParseProfile(text)
    text = (text or ""):gsub("\r", "")
    local lines = { strsplit("\n", text) }
    if strtrim(lines[1] or "") ~= "RABuffs1" then
        return nil
    end
    local bars = {}
    for i = 2, #lines do
        local line = strtrim(lines[i])
        if line ~= "" then
            local f = { strsplit(FIELD_SEP, line) }
            local key = Unescape(f[1] or "")
            if RAB.Buffs[key] then
                local r, g, b = strsplit(LIST_SEP, f[3] or "")
                local excluded = {}
                for name in (f[9] or ""):gmatch("[^,]+") do
                    excluded[#excluded + 1] = Unescape(name)
                end
                local custom = Unescape(f[10] or "")
                bars[#bars + 1] = NormalizeBar({
                    buffKey = key,
                    label = (f[2] and f[2] ~= "") and Unescape(f[2]) or nil,
                    color = { tonumber(r) or 0.5, tonumber(g) or 0.5, tonumber(b) or 0.5 },
                    groups = Unescape(f[4] or ""):gsub("[^1-8]", ""),
                    classes = Unescape(f[5] or ""):gsub("[^mlprdhswa]", ""),
                    selfOnly = f[6] == "1",
                    castOnClick = f[7] ~= "0",
                    output = Unescape(f[8] or "RAID"),
                    exclude = excluded,
                    custom = custom ~= "" and custom or nil,
                })
            end
        end
    end
    return bars
end

function RAB:ImportProfile(name, text)
    name = strtrim(name or "")
    local bars = ParseProfile(text)
    if name == "" or not bars then
        self:Print(L.ProfileImportFailed, "warn")
        return false
    end
    self.db.profiles[name] = { bars = bars }
    self:UseProfile(name)
    self:BarsChanged()
    self:Print(string.format(L.ProfileImported, name), "ok")
    return true
end

-- =================================================================
-- Group members
-- =================================================================

-- One table per member for this refresh, read once and shared by every bar
function RAB:BuildMembers()
    local members = self.members
    wipe(members)
    Compat.Roster(self.roster)
    for _, entry in ipairs(self.roster) do
        local unit = entry.unit
        local class = Compat.UnitClass(unit)
        members[#members + 1] = {
            unit = unit,
            guid = Compat.UnitGUID(unit),
            name = Compat.UnitName(unit) or "?",
            class = class,
            letter = class and RAB.ClassLetters[class],
            group = entry.group or 1,
            role = Compat.RaidRole(entry.index),
            isPlayer = Compat.IsPlayer(unit),
            connected = Compat.Bool(UnitIsConnected, unit) ~= false,
            dead = Compat.UnitIsDead(unit) == true,
            visible = Compat.Bool(UnitIsVisible, unit),
            inRange = Compat.UnitInRange(unit),
        }
    end
    return members
end

function RAB:PlayerMember()
    for _, m in ipairs(self.members) do
        if m.isPlayer then
            return m
        end
    end
end

-- =================================================================
-- Refreshing
-- =================================================================

local refreshQueued = false

-- Something changed: refresh soon (at most a few times a second however many events arrive)
function RAB:RequestRefresh()
    if refreshQueued or not self.ready then
        return
    end
    refreshQueued = true
    C_Timer.After(0.2, function()
        refreshQueued = false
        RAB:Refresh()
    end)
end

function RAB:Refresh()
    if not self.ready then
        return
    end
    self:BuildMembers()
    self.Scan:BeginPass()
    if self.UI then
        self.UI:Update()
    end
end

function RAB:StartTicker()
    if self.ticker then
        self.ticker:Cancel()
    end
    self.ticker = C_Timer.NewTicker(self.settings.interval, function()
        RAB:Refresh()
    end)
end

-- =================================================================
-- Combat
-- =================================================================

local afterCombat = {}

-- Runs fn now, or when combat ends if the client wouldn't allow it now. A later call with the same key
-- replaces an earlier one still waiting.
function RAB:OutOfCombat(key, fn)
    if InCombatLockdown() then
        afterCombat[key] = fn
        return false
    end
    fn()
    return true
end

local function RunAfterCombat()
    for key, fn in pairs(afterCombat) do
        afterCombat[key] = nil
        fn()
    end
end

-- =================================================================
-- Events
-- =================================================================

local frame = CreateFrame("Frame")
RAB.eventFrame = frame
local handlers = {}

function RAB:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        Compat.RegisterEvent(frame, event)
    end
    table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if list then
        for _, fn in ipairs(list) do
            fn(event, ...)
        end
    end
end)

-- Saved variables are loaded by now, and the character's name and class are known
RAB:On("PLAYER_LOGIN", function()
    RAB:InitDB()
    RAB.ready = true
    if RAB.UI then
        RAB.UI:Create()
    end
    RAB:BuildMembers()
    RAB:StartTicker()
    RAB:Refresh()
    RAB:Print(string.format(L.Loaded, RAB.version))
end)

local function GroupChanged()
    RAB.Scan:Prune()
    RAB:RequestRefresh()
end
RAB:On("GROUP_ROSTER_UPDATE", GroupChanged)
RAB:On("PLAYER_ENTERING_WORLD", function()
    RAB.Scan:MarkAll()
    GroupChanged()
end)

RAB:On("UNIT_AURA", function(_, unit)
    if unit and (unit == "player" or unit:find("^party%d") or unit:find("^raid%d")) then
        RAB.Scan:MarkUnit(unit)
        RAB:RequestRefresh()
    end
end)

local function Changed()
    RAB:RequestRefresh()
end
for _, event in ipairs({ "UNIT_CONNECTION", "UNIT_FLAGS", "PLAYER_FLAGS_CHANGED", "UNIT_INVENTORY_CHANGED",
    "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED" }) do
    RAB:On(event, Changed)
end

RAB:On("SPELLS_CHANGED", function()
    Compat.ResetSpellCache()
    RAB:RequestRefresh()
end)

-- Forever: the client started or stopped hiding auras; old readings may no longer match
for _, event in ipairs({ "ADDON_RESTRICTION_STATE_CHANGED", "UNIT_AURA_BLOCKED", "UNIT_AURA_BLOCK_LIST_CLEARED" }) do
    RAB:On(event, function()
        RAB.Scan:MarkAll()
        RAB:RequestRefresh()
    end)
end

RAB:On("PLAYER_REGEN_DISABLED", function()
    if RAB.UI then
        RAB.UI:CombatChanged()
    end
end)

RAB:On("PLAYER_REGEN_ENABLED", function()
    RunAfterCombat()
    RAB.Scan:MarkAll()
    if RAB.UI then
        RAB.UI:CombatChanged()
    end
    RAB:Refresh()
end)

RAB:On("MODIFIER_STATE_CHANGED", function()
    if RAB.UI then
        RAB.UI:RefreshTooltip()
    end
end)
