-- A fake World of Warcraft for running RABuffs outside the game (Lua 5.1, as in the client).
-- `world` holds the game state a test sets up; the functions below read it like the real API would.
-- world.forever = true acts like Forever: while world.aurasSecret is set, reading an aura throws
-- ("Auras cannot be accessed when secret while tainted"), and SECRET stands for a secret value.

SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

world = {
    time = 1000,
    combat = false,
    aurasSecret = false,
    forever = false,
    chatLocked = false,
    raid = false,
    units = {},        -- token -> { name, class, guid, group, dead, connected, visible, inRange, pvp, afk,
                       --            role, buffs = { aura... }, debuffs = {...}, health, maxHealth, power, ... }
    knownSpells = {},  -- spell name -> spell ID
    items = {},        -- itemID -> count
    itemCooldowns = {},
    weapons = {},      -- slot -> itemID
    enchants = {},     -- slot -> seconds left
    modifiers = {},
    chat = {},         -- messages sent with SendChatMessage
    printed = {},      -- lines added to the chat frame
    stateDrivers = {},
    menus = {},
    errors = {},
}

local function noop() end

-- =================================================================
-- Lua helpers the client adds
-- =================================================================

function strtrim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
function strsplit(sep, s)
    local out, pattern = {}, "([^" .. sep:gsub("%p", "%%%0") .. "]*)"
    for piece in (s .. sep):gmatch(pattern .. sep:gsub("%p", "%%%0")) do
        out[#out + 1] = piece
    end
    return unpack(out)
end
function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end
tinsert = table.insert
strlower = string.lower
strupper = string.upper
function CopyTable(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = type(v) == "table" and CopyTable(v) or v
    end
    return out
end

-- =================================================================
-- Secrets
-- =================================================================

function issecretvalue(v)
    return v == SECRET
end
function issecrettable(v)
    return v == SECRET
end
C_Secrets = {
    ShouldAurasBeSecret = function()
        return world.forever and world.aurasSecret
    end,
    ShouldUnitAuraIndexBeSecret = function()
        return false
    end,
}

-- =================================================================
-- Build, time, combat
-- =================================================================

function GetBuildInfo()
    if world.forever then
        return "1.60.1", "70532", "Oct 22 2026", 16001
    end
    return "1.15.9", "70576", "Oct 26 2026", 11509
end
function GetTime()
    return world.time
end
function InCombatLockdown()
    return world.combat
end
function GetLocale()
    return "enUS"
end
function GetRealmName()
    return "Testrealm"
end

local timers = {}
C_Timer = {
    After = function(delay, fn)
        timers[#timers + 1] = { at = world.time + delay, fn = fn }
    end,
    NewTicker = function(interval, fn)
        local ticker = { interval = interval, fn = fn, next = world.time + interval, ticker = true }
        function ticker:Cancel()
            self.cancelled = true
        end
        timers[#timers + 1] = ticker
        return ticker
    end,
}
-- Moves time forward, running timers that come due
function Advance(seconds)
    local target = world.time + seconds
    while true do
        local due, dueIndex
        for i, t in ipairs(timers) do
            local at = t.ticker and t.next or t.at
            if not t.cancelled and at <= target and (not due or at < (due.ticker and due.next or due.at)) then
                due, dueIndex = t, i
            end
        end
        if not due then
            break
        end
        world.time = math.max(world.time, due.ticker and due.next or due.at)
        if due.ticker then
            due.next = due.next + due.interval
        else
            table.remove(timers, dueIndex)
        end
        due.fn()
    end
    world.time = target
end

C_AddOns = {
    GetAddOnMetadata = function(_, field)
        return field == "Version" and "1.0.0-test" or nil
    end,
}

-- =================================================================
-- Units and the group
-- =================================================================

-- In a raid world.units has raid1..raidN (one of them also stored as "player"); in a party "player" and party1..4
local function U(token)
    return world.units[token]
end
UnitData = U

function UnitExists(token)
    return U(token) ~= nil
end
function UnitIsUnit(a, b)
    if world.unitCompareSecret then
        return SECRET
    end
    local ua, ub = U(a), U(b)
    return ua ~= nil and ua == ub
end
function UnitName(token)
    local u = U(token)
    return u and u.name
end
function GetUnitName(token)
    local u = U(token)
    return u and u.name
end
function UnitClass(token)
    local u = U(token)
    if not u then
        return nil
    end
    return u.class:sub(1, 1) .. u.class:sub(2):lower(), u.class
end
function UnitGUID(token)
    local u = U(token)
    return u and u.guid
end
function UnitIsConnected(token)
    local u = U(token)
    return u and u.connected ~= false
end
function UnitIsDeadOrGhost(token)
    local u = U(token)
    return u and u.dead == true
end
function UnitIsFeignDeath(token)
    local u = U(token)
    return u and u.feign == true
end
function UnitIsVisible(token)
    local u = U(token)
    return u and u.visible ~= false
end
function UnitInRange(token)
    local u = U(token)
    if not u then
        return false, false
    end
    if u.inRange == SECRET then
        return SECRET, SECRET
    end
    return u.inRange ~= false, true
end
function UnitIsPVP(token)
    local u = U(token)
    return u and u.pvp == true
end
function UnitIsAFK(token)
    local u = U(token)
    if u and u.afk == SECRET then
        return SECRET
    end
    return u and u.afk == true
end
function UnitAffectingCombat(token)
    local u = U(token)
    return u and u.inCombat == true
end
function UnitHealth(token)
    if world.forever then
        return SECRET
    end
    local u = U(token)
    return u and (u.health or 100)
end
function UnitHealthMax(token)
    local u = U(token)
    return u and (u.maxHealth or 100)
end
function UnitPowerType(token)
    local u = U(token)
    if not u then
        return 0
    end
    local manaless = { WARRIOR = true, ROGUE = true }
    return manaless[u.class] and 1 or 0
end
function UnitPower(token)
    local u = U(token)
    return u and (u.power or 50)
end
function UnitPowerMax(token)
    local u = U(token)
    return u and (u.maxPower or 100)
end

function IsInRaid()
    return world.raid
end
local function CountTokens(prefix)
    local n = 0
    for token in pairs(world.units) do
        if token:find("^" .. prefix .. "%d") then
            n = n + 1
        end
    end
    return n
end
function IsInGroup()
    return world.raid or CountTokens("party") > 0
end
function GetNumGroupMembers()
    if world.raid then
        return CountTokens("raid")
    end
    local party = CountTokens("party")
    return party > 0 and party + 1 or 0
end
function GetRaidRosterInfo(index)
    local u = U("raid" .. index)
    if not u then
        return nil
    end
    return u.name, 0, u.group or 1, 60, u.class, u.class, "Zone", u.connected ~= false, u.dead == true, u.role
end

-- =================================================================
-- Auras
-- =================================================================

C_UnitAuras = {
    GetAuraDataByIndex = function(token, index, filter)
        if world.forever and world.aurasSecret then
            error("Auras cannot be accessed when secret while tainted")
        end
        local u = U(token)
        if not u then
            return nil
        end
        local list = (filter == "HARMFUL") and (u.debuffs or {}) or (u.buffs or {})
        local aura = list[index]
        if aura == SECRET then
            return SECRET
        end
        return aura
    end,
}

-- A buff as the client returns it
function Aura(name, spellId, secondsLeft, extra)
    local aura = { name = name, spellId = spellId, applications = 0 }
    if secondsLeft then
        aura.duration = 1800
        aura.expirationTime = world.time + secondsLeft
    else
        aura.duration = 0
        aura.expirationTime = 0
    end
    for k, v in pairs(extra or {}) do
        aura[k] = v
    end
    return aura
end

-- =================================================================
-- Spells and items
-- =================================================================

C_Spell = {
    GetSpellInfo = function(spell)
        local id = world.knownSpells[spell]
        if not id then
            return nil
        end
        return { name = spell, iconID = 1, spellID = id }
    end,
    GetSpellCooldown = function()
        return { startTime = 0, duration = 0 }
    end,
}
C_SpellBook = {
    IsSpellKnownOrInSpellBook = function(id)
        for _, known in pairs(world.knownSpells) do
            if known == id then
                return true
            end
        end
        return false
    end,
}
C_Item = {
    GetItemCount = function(id)
        return world.items[id] or 0
    end,
    GetItemNameByID = function(id)
        return "Item" .. id
    end,
    GetItemIconByID = function()
        return 1
    end,
    GetItemInfoInstant = function(id)
        return id, "Weapon", "Dagger", "INVTYPE_WEAPON", 1, 2, 15
    end,
}
C_Container = {
    GetItemCooldown = function(id)
        local cd = world.itemCooldowns[id]
        if cd then
            return world.time, cd, 1
        end
        return 0, 0, 1
    end,
}
function GetInventoryItemID(_, slot)
    return world.weapons[slot]
end
function GetWeaponEnchantInfo()
    local mh, oh = world.enchants[16], world.enchants[17]
    return mh ~= nil, (mh or 0) * 1000, 0, mh and 1 or nil, oh ~= nil, (oh or 0) * 1000, 0, oh and 1 or nil
end
function GetChannelName(name)
    return name == "raidbuffs" and 5 or 0
end

-- =================================================================
-- Chat
-- =================================================================

C_ChatInfo = {
    SendChatMessage = function(message, chatType, _, target)
        table.insert(world.chat, { message = message, chatType = chatType, target = target })
    end,
    InChatMessagingLockdown = function()
        return world.chatLocked
    end,
}

DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, text)
        table.insert(world.printed, text)
    end,
}

function IsControlKeyDown()
    return world.modifiers.ctrl == true
end
function IsShiftKeyDown()
    return world.modifiers.shift == true
end
function IsAltKeyDown()
    return world.modifiers.alt == true
end

-- =================================================================
-- Frames
-- =================================================================

-- Methods the mock doesn't model (SetBackdrop, SetFrameStrata...) do nothing; fields default to nil
local Frame = {}
Frame.__index = function(self, key)
    local method = Frame[key]
    if method then
        return method
    end
    if type(key) == "string" and key:find("^%u") then
        return noop
    end
    return nil
end

local frames = {}
AllFrames = frames

local function NewObject(kind, name, parent)
    local f = setmetatable({ kind = kind, name = name, parent = parent, attributes = {}, scripts = {},
        events = {}, shown = true, width = 100, height = 20, points = {} }, Frame)
    if name then
        _G[name] = f
    end
    frames[#frames + 1] = f
    return f
end

function Frame:SetScript(script, fn)
    self.scripts[script] = fn
end
function Frame:GetScript(script)
    return self.scripts[script]
end
function Frame:HookScript(script, fn)
    local old = self.scripts[script]
    self.scripts[script] = function(...)
        if old then
            old(...)
        end
        fn(...)
    end
end
function Frame:RegisterEvent(event)
    if world.unknownEvents and world.unknownEvents[event] then
        error("Attempt to register unknown event \"" .. event .. "\"")
    end
    self.events[event] = true
end
Frame.RegisterUnitEvent = Frame.RegisterEvent
function Frame:SetAttribute(key, value)
    if world.combat and self.protected then
        error("ADDON_ACTION_BLOCKED: SetAttribute in combat on " .. tostring(self.name))
    end
    self.attributes[key] = value
end
function Frame:GetAttribute(key)
    return self.attributes[key]
end
local function Protected(self, what)
    if world.combat and (self.protected or self.hasProtectedChild) then
        error("ADDON_ACTION_BLOCKED: " .. what .. " in combat on " .. tostring(self.name))
    end
end
function Frame:Show()
    Protected(self, "Show")
    self.shown = true
end
function Frame:Hide()
    Protected(self, "Hide")
    self.shown = false
end
function Frame:SetShown(shown)
    if shown then
        self:Show()
    else
        self:Hide()
    end
end
function Frame:IsShown()
    return self.shown
end
function Frame:IsVisible()
    return self.shown
end
function Frame:SetPoint(...)
    Protected(self, "SetPoint")
    table.insert(self.points, { ... })
end
function Frame:ClearAllPoints()
    Protected(self, "ClearAllPoints")
    self.points = {}
end
function Frame:GetPoint()
    local p = self.points[1]
    if p then
        return p[1], p[2], p[3] or p[1], p[4] or 0, p[5] or 0
    end
    return "CENTER", UIParent, "CENTER", 0, 0
end
function Frame:SetWidth(w)
    if self.kind ~= "Texture" and self.kind ~= "FontString" then
        Protected(self, "SetWidth")
    end
    self.width = w
end
function Frame:SetHeight(h)
    if self.kind ~= "Texture" and self.kind ~= "FontString" then
        Protected(self, "SetHeight")
    end
    self.height = h
end
function Frame:SetSize(w, h)
    self:SetWidth(w)
    self:SetHeight(h)
end
function Frame:GetWidth()
    return self.width
end
function Frame:GetHeight()
    return self.height
end
function Frame:SetScale(s)
    Protected(self, "SetScale")
    self.scale = s
end
function Frame:GetCenter()
    return 800, 400
end
function Frame:GetEffectiveScale()
    return 1
end
function Frame:IsMouseOver()
    return self.mouseOver == true
end
function Frame:SetText(text)
    self.text = text
end
function Frame:GetText()
    return self.text or ""
end
function Frame:SetChecked(checked)
    self.checked = checked and true or false
end
function Frame:GetChecked()
    return self.checked
end
function Frame:SetEnabled(enabled)
    self.enabled = enabled
end
function Frame:SetValue(value)
    self.value = value
    if self.scripts.OnValueChanged then
        self.scripts.OnValueChanged(self, value)
    end
end
function Frame:GetParent()
    return self.parent
end
function Frame:SetVertexColor(r, g, b)
    self.color = { r, g, b }
end
function Frame:SetTextColor(r, g, b)
    self.textColor = { r, g, b }
end
function Frame:CreateTexture(name)
    return NewObject("Texture", name, self)
end
function Frame:CreateFontString(name)
    return NewObject("FontString", name, self)
end
function Frame:GetName()
    return self.name
end
function Frame:GetFrameLevel()
    return self.frameLevel or 1
end
function Frame:SetFrameLevel(level)
    self.frameLevel = level
end

function CreateFrame(kind, name, parent, template)
    local f = NewObject(kind, name, parent)
    template = template or ""
    if template:find("SecureActionButtonTemplate") then
        f.protected = true
        local p = parent
        while p do
            p.hasProtectedChild = true
            p = p.parent
        end
    end
    if template:find("UICheckButtonTemplate") then
        f.Text = NewObject("FontString", nil, f)
    end
    if template:find("OptionsSliderTemplate") then
        f.Text = NewObject("FontString", nil, f)
        f.Low = NewObject("FontString", nil, f)
        f.High = NewObject("FontString", nil, f)
    end
    if template:find("BasicFrameTemplate") then
        f.TitleText = NewObject("FontString", nil, f)
        f.CloseButton = NewObject("Button", nil, f)
    end
    if template:find("ScrollFrameTemplate") then
        f.ScrollBar = NewObject("Slider", nil, f)
    end
    if template:find("InputBoxTemplate") then
        f.ClearFocus = noop
    end
    return f
end

UIParent = NewObject("Frame", "UIParent")
UIParent.GetWidth = function()
    return 1600
end
ChatFontNormal = {}
UISpecialFrames = {}
ATTRIBUTE_NOOP = ""
OKAY, CANCEL, YES, NO = "Okay", "Cancel", "Yes", "No"
CHAT_MSG_RAID, CHAT_MSG_PARTY, CHAT_MSG_SAY, CHAT_MSG_GUILD, CHAT_MSG_OFFICER = "Raid", "Party", "Say", "Guild", "Officer"
LOCALIZED_CLASS_NAMES_MALE = {
    WARRIOR = "Warrior", PALADIN = "Paladin", PRIEST = "Priest", SHAMAN = "Shaman", DRUID = "Druid",
    ROGUE = "Rogue", MAGE = "Mage", WARLOCK = "Warlock", HUNTER = "Hunter",
}
RAID_CLASS_COLORS = {}
for token in pairs(LOCALIZED_CLASS_NAMES_MALE) do
    RAID_CLASS_COLORS[token] = { r = 1, g = 1, b = 1, colorStr = "ffffffff" }
end

GameTooltip = NewObject("GameTooltip", "GameTooltip")
GameTooltip.lines = {}
function GameTooltip:SetOwner(owner)
    self.owner = owner
    self.lines = {}
end
function GameTooltip:AddLine(text)
    table.insert(self.lines, text)
end
function GameTooltip:AddDoubleLine(left, right)
    table.insert(self.lines, left .. " || " .. tostring(right))
end
function GameTooltip:IsOwned(owner)
    return self.owner == owner
end
function GameTooltip_Hide()
    GameTooltip:Hide()
end

StaticPopupDialogs = {}
function StaticPopup_Show(which, a, b, data)
    world.popup = { which = which, data = data }
end
function StaticPopup_Hide()
    world.popup = nil
end
function HideUIPanel()
end
ColorPickerFrame = NewObject("Frame", "ColorPickerFrame")

function RegisterStateDriver(frame, state, condition)
    world.stateDrivers[frame] = { state = state, condition = condition }
end

-- Records the menu a test can then look at
local function MenuDescription(text)
    local d = { text = text, children = {} }
    local function add(kind, text2, a, b)
        local child = MenuDescription(text2)
        child.kind, child.a, child.b = kind, a, b
        table.insert(d.children, child)
        return child
    end
    function d:CreateTitle(t) return add("title", t) end
    function d:CreateButton(t, fn) return add("button", t, fn) end
    function d:CreateCheckbox(t, isSel, setSel) return add("checkbox", t, isSel, setSel) end
    function d:CreateRadio(t, isSel, setSel) return add("radio", t, isSel, setSel) end
    function d:CreateDivider() return add("divider") end
    function d:SetScrollMode() end
    return d
end
MenuUtil = {
    CreateContextMenu = function(owner, generator)
        local root = MenuDescription("root")
        generator(owner, root)
        world.lastMenu = root
        return root
    end,
}

Settings = {
    RegisterCanvasLayoutCategory = function()
        return {}
    end,
    RegisterAddOnCategory = noop,
}

SlashCmdList = {}

-- =================================================================
-- Driving the addon
-- =================================================================

-- Sends an event to every frame registered for it
function Fire(event, ...)
    for _, f in ipairs(frames) do
        if f.events[event] and f.scripts.OnEvent then
            f.scripts.OnEvent(f, event, ...)
        end
    end
end

-- Clicks a bar like the player would: PreClick, the secure action, PostClick. Returns what the secure
-- template would do: { type, spell, item, unit, slot } or nil
function Click(button, mouseButton)
    mouseButton = mouseButton or "LeftButton"
    local suffix = mouseButton == "LeftButton" and "1" or "2"
    local prefix = (world.modifiers.alt and "alt-" or "") .. (world.modifiers.ctrl and "ctrl-" or "")
        .. (world.modifiers.shift and "shift-" or "")
    local function attr(name)
        -- Same lookup order as Frame:GetAttribute(prefix, name, suffix)
        for _, key in ipairs({ prefix .. name .. suffix, "*" .. name .. suffix, prefix .. name .. "*",
            "*" .. name .. "*", name .. suffix, name .. "*", name }) do
            local v = button.attributes[key]
            if v ~= nil then
                if v == ATTRIBUTE_NOOP then
                    return nil
                end
                return v
            end
        end
    end
    if button.scripts.PreClick then
        button.scripts.PreClick(button, mouseButton, false)
    end
    local action
    local actionType = attr("type")
    if actionType then
        action = { type = actionType, spell = attr("spell"), item = attr("item"), unit = attr("unit"),
            slot = attr("target-slot") }
    end
    if button.scripts.PostClick then
        button.scripts.PostClick(button, mouseButton, false)
    end
    return action
end
