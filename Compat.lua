-- RABuffs: The game API, wrapped so the rest of the addon runs the same on Classic Era (1.15) and Forever (1.60).
-- Both clients have the modern API. Forever can also hand back "secret" values (in combat, encounters and PvP
-- matches), and testing, comparing or indexing one throws, so anything that can be secret is read through here.
local _, RAB = ...

local Compat = {}
RAB.Compat = Compat

local issecretvalue = issecretvalue or function() return false end
local issecrettable = issecrettable or function() return false end

-- True for a value addon code may not look at
local function Secret(v)
    return issecretvalue(v) or issecrettable(v)
end
Compat.Secret = Secret

-- The value, or nil when it is secret
local function Clean(v)
    if Secret(v) then
        return nil
    end
    return v
end
Compat.Clean = Clean

local _, _, _, interface = GetBuildInfo()
Compat.interface = interface
Compat.isForever = interface >= 16000 and interface < 20000

-- Calls a yes/no unit function: true or false, or nil when the answer is secret or the call fails
function Compat.Bool(fn, ...)
    if not fn then
        return nil
    end
    local ok, value = pcall(fn, ...)
    if not ok or Secret(value) then
        return nil
    end
    return value and true or false
end

-- Calls a function returning a number: the number, or nil when it is secret or the call fails
function Compat.Number(fn, ...)
    if not fn then
        return nil
    end
    local ok, value = pcall(fn, ...)
    if not ok or Secret(value) or type(value) ~= "number" then
        return nil
    end
    return value
end

-- =================================================================
-- Auras
-- =================================================================

local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local ShouldAurasBeSecret = C_Secrets and C_Secrets.ShouldAurasBeSecret
local ShouldUnitAuraIndexBeSecret = C_Secrets and C_Secrets.ShouldUnitAuraIndexBeSecret

-- True while the client hides auras from addons. On Forever a read then throws instead of returning a secret,
-- so nothing reads auras while this is true.
function Compat.AurasRestricted()
    if not ShouldAurasBeSecret then
        return false
    end
    local ok, restricted = pcall(ShouldAurasBeSecret)
    if not ok or Secret(restricted) then
        return true
    end
    return restricted == true
end

local function AuraIndexSecret(unit, index, filter)
    if not ShouldUnitAuraIndexBeSecret then
        return false
    end
    local ok, secret = pcall(ShouldUnitAuraIndexBeSecret, unit, index, filter)
    return not ok or Secret(secret) or secret == true
end

-- One aura, copied field by field so a secret field becomes nil instead of an error later.
-- Runs inside pcall: even truth-testing a secret table throws.
local function ReadAuraAt(unit, index, filter)
    local a = GetAuraDataByIndex(unit, index, filter)
    if Secret(a) then
        return "secret"
    end
    if not a then
        return "end"
    end
    return "ok", {
        name = Clean(a.name),
        spellId = Clean(a.spellId),
        icon = Clean(a.icon),
        expirationTime = Clean(a.expirationTime),
        duration = Clean(a.duration),
        applications = Clean(a.applications),
        dispelName = Clean(a.dispelName),
        sourceUnit = Clean(a.sourceUnit),
    }
end

-- All auras on a unit matching the filter ("HELPFUL" or "HARMFUL").
-- Returns the list (nil when auras can't be read at all) and whether every aura could be read.
function Compat.ReadAuras(unit, filter)
    if not GetAuraDataByIndex or Compat.AurasRestricted() then
        return nil, false
    end
    local list, complete = {}, true
    for i = 1, 40 do
        if AuraIndexSecret(unit, i, filter) then
            complete = false
        else
            local ok, state, aura = pcall(ReadAuraAt, unit, i, filter)
            if not ok then
                -- The client refused the read; whatever came before is still good
                return list, false
            elseif state == "end" then
                break
            elseif state == "secret" or (aura.name == nil and aura.spellId == nil) then
                -- Some spells are secret on their own; an aura we can't name could be the one asked about
                complete = false
            else
                list[#list + 1] = aura
            end
        end
    end
    return list, complete
end

-- =================================================================
-- Spells
-- =================================================================

-- name, icon and spell ID for a spell name or ID, or nil
function Compat.SpellInfo(spell)
    if not (C_Spell and C_Spell.GetSpellInfo) or spell == nil then
        return nil
    end
    local ok, name, icon, id = pcall(function()
        local info = C_Spell.GetSpellInfo(spell)
        if Secret(info) or not info then
            return nil
        end
        return Clean(info.name), Clean(info.iconID), Clean(info.spellID)
    end)
    if not ok then
        return nil
    end
    return name, icon, id
end

local knownSpells = {}

-- Forgets which spells the player knows (on SPELLS_CHANGED)
function Compat.ResetSpellCache()
    wipe(knownSpells)
end

-- The name to cast and the icon, when the player knows the spell; nil otherwise. Casting by name picks the
-- highest rank the player has.
function Compat.KnownSpell(spell)
    if not spell then
        return nil
    end
    local cached = knownSpells[spell]
    if cached == nil then
        cached = false
        local name, icon, id = Compat.SpellInfo(spell)
        if name and id then
            local known = true
            if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
                known = Compat.Bool(C_SpellBook.IsSpellKnownOrInSpellBook, id) == true
            end
            if known then
                cached = { name = name, icon = icon, id = id }
            end
        end
        knownSpells[spell] = cached
    end
    if not cached then
        return nil
    end
    return cached.name, cached.icon
end

-- Seconds until the spell is ready, 0 when ready (ignoring the global cooldown), nil when unknown
function Compat.SpellCooldown(spell)
    if not (C_Spell and C_Spell.GetSpellCooldown) then
        return nil
    end
    local ok, remaining = pcall(function()
        local info = C_Spell.GetSpellCooldown(spell)
        if Secret(info) or not info then
            return nil
        end
        local start, duration = Clean(info.startTime), Clean(info.duration)
        if not start or not duration or start == 0 or duration <= 1.5 then
            return 0
        end
        return math.max(0, start + duration - GetTime())
    end)
    return ok and remaining or nil
end

-- =================================================================
-- Items
-- =================================================================

function Compat.ItemCount(itemID)
    if C_Item and C_Item.GetItemCount then
        return Compat.Number(C_Item.GetItemCount, itemID) or 0
    end
    return 0
end

function Compat.ItemName(itemID)
    if C_Item and C_Item.GetItemNameByID then
        local ok, name = pcall(C_Item.GetItemNameByID, itemID)
        if ok then
            return Clean(name)
        end
    end
    return nil
end

function Compat.ItemIcon(itemID)
    if C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok then
            return Clean(icon)
        end
    end
    return nil
end

-- Seconds until the item can be used again, 0 when ready
function Compat.ItemCooldown(itemID)
    local getCooldown = (C_Container and C_Container.GetItemCooldown) or (C_Item and C_Item.GetItemCooldown)
    if not getCooldown then
        return 0
    end
    local ok, start, duration = pcall(getCooldown, itemID)
    start, duration = Clean(start), Clean(duration)
    if not ok or not start or not duration or start == 0 or duration <= 1.5 then
        return 0
    end
    return math.max(0, start + duration - GetTime())
end

-- Is there a weapon in the slot (16 main hand, 17 off hand) that can take an oil, stone or poison?
function Compat.WeaponInSlot(slot)
    local itemID = Compat.Number(GetInventoryItemID, "player", slot)
    if not itemID then
        return false
    end
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, itemID)
        -- Item class 2 is weapons; a shield or held-in-off-hand item can't be coated
        if ok and classID ~= nil and not Secret(classID) then
            return classID == 2
        end
    end
    return true
end

local function Pack(...)
    return select("#", ...), { ... }
end

-- Temporary weapon enchant on the slot: enchanted (bool) and seconds left (or nil)
function Compat.WeaponEnchant(slot)
    local count, values = Pack(pcall(GetWeaponEnchantInfo))
    if not values[1] then
        return false
    end
    -- Modern clients return 4 values per hand (has, expiration ms, charges, enchant ID); old ones returned 3
    local perHand = (count - 1 >= 8) and 4 or 3
    local offset = (slot == 17) and perHand or 0
    local has, expiration = Clean(values[2 + offset]), Clean(values[3 + offset])
    if not has then
        return false
    end
    return true, expiration and expiration / 1000 or nil
end

-- =================================================================
-- Units and the group
-- =================================================================

-- The name to show: "First Surname" on Forever, the plain name on Classic Era
function Compat.UnitName(unit)
    local name
    if GetUnitName then
        local ok, n = pcall(GetUnitName, unit, false)
        if ok then
            name = Clean(n)
        end
    end
    if not name then
        local ok, n = pcall(UnitName, unit)
        if ok then
            name = Clean(n)
        end
    end
    return name
end

function Compat.UnitClass(unit)
    local ok, _, token = pcall(UnitClass, unit)
    if not ok then
        return nil
    end
    return Clean(token)
end

function Compat.UnitGUID(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if not ok then
        return nil
    end
    return Clean(guid)
end

-- Is this unit token you? Unit comparisons can be secret on Forever's restricted maps (raids), but group
-- members' GUIDs stay readable, so those decide first.
function Compat.IsPlayer(unit)
    if unit == "player" then
        return true
    end
    local guid, playerGuid = Compat.UnitGUID(unit), Compat.UnitGUID("player")
    if guid and playerGuid then
        return guid == playerGuid
    end
    return Compat.Bool(UnitIsUnit, unit, "player") == true
end

-- In range for helpful spells (about 40 yards): true, false, or nil when the game won't say
function Compat.UnitInRange(unit)
    if Compat.IsPlayer(unit) then
        return true
    end
    local ok, inRange, checked = pcall(UnitInRange, unit)
    if not ok or Secret(inRange) or Secret(checked) or not checked then
        return nil
    end
    return inRange and true or false
end

function Compat.UnitIsDead(unit)
    local dead = Compat.Bool(UnitIsDeadOrGhost, unit)
    if dead and UnitIsFeignDeath and Compat.Bool(UnitIsFeignDeath, unit) then
        return false
    end
    return dead
end

-- Raid role ("MAINTANK", "MAINASSIST") of a raid roster index, or nil
function Compat.RaidRole(index)
    if not index then
        return nil
    end
    local ok, _, _, _, _, _, _, _, _, _, role = pcall(GetRaidRosterInfo, index)
    if not ok then
        return nil
    end
    return Clean(role)
end

-- Fills out with one entry per group member: { unit, group, index }. Solo, the player alone.
function Compat.Roster(out)
    wipe(out)
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if Compat.Bool(UnitExists, unit) ~= false then
                local ok, _, _, subgroup = pcall(GetRaidRosterInfo, i)
                subgroup = ok and Clean(subgroup) or 1
                out[#out + 1] = { unit = unit, group = subgroup, index = i }
            end
        end
    else
        out[1] = { unit = "player", group = 1 }
        for i = 1, math.max(0, GetNumGroupMembers() - 1) do
            local unit = "party" .. i
            if Compat.Bool(UnitExists, unit) ~= false then
                out[#out + 1] = { unit = unit, group = 1 }
            end
        end
    end
    return out
end

-- 0 solo, 1 party, 2 raid
function Compat.GroupState()
    if IsInRaid() then
        return 2
    elseif IsInGroup() then
        return 1
    end
    return 0
end

-- =================================================================
-- Chat
-- =================================================================

-- True while the client blocks addons from sending chat (boss encounters, PvP matches on Forever)
function Compat.ChatLocked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local locked = Compat.Bool(C_ChatInfo.InChatMessagingLockdown)
        return locked ~= false
    end
    return false
end

function Compat.SendChat(message, chatType, target)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    send(message, chatType, nil, target)
end

-- =================================================================
-- Misc
-- =================================================================

function Compat.ClassColor(token)
    local color = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if color then
        return color.r, color.g, color.b, color.colorStr
    end
    return 0.8, 0.8, 0.8, "ffcccccc"
end

-- Registers an event if this client has it; unknown events throw on modern clients
function Compat.RegisterEvent(frame, event)
    return pcall(frame.RegisterEvent, frame, event)
end

function Compat.RegisterUnitEvent(frame, event, ...)
    return pcall(frame.RegisterUnitEvent, frame, event, ...)
end
