-- RABuffs: Answers a bar's question ("who is missing Arcane Intellect?") from the group and the aura cache, and
-- formats the answer for chat.
local _, RAB = ...

local L = RAB.L
local Compat = RAB.Compat

local Query = {}
RAB.Query = Query

-- =================================================================
-- Matching auras
-- =================================================================

local function MatchEntry(entry, aura)
    if type(entry) == "string" then
        return aura.name == entry
    elseif type(entry) == "number" then
        return aura.spellId == entry
    end
    if entry.id then
        -- The ID decides when it can be read; otherwise fall back to the name
        if aura.spellId then
            return aura.spellId == entry.id
        end
        return entry.name ~= nil and aura.name == entry.name
    end
    if entry.name and aura.name == entry.name then
        if entry.notIds and aura.spellId then
            for _, id in ipairs(entry.notIds) do
                if id == aura.spellId then
                    return false
                end
            end
        end
        return true
    end
    return false
end

function Query.FindAura(list, match)
    if not list or not match then
        return nil
    end
    for _, aura in ipairs(list) do
        for _, entry in ipairs(match) do
            if MatchEntry(entry, aura) then
                return aura
            end
        end
    end
    return nil
end

-- Seconds left on an aura, nil for one that doesn't run out
local function Remaining(aura)
    if aura and aura.expirationTime and aura.expirationTime > 0 then
        return math.max(0, aura.expirationTime - GetTime())
    end
    return nil
end
Query.Remaining = Remaining

-- =================================================================
-- Buff definitions for a bar
-- =================================================================

local customDefs = {}

-- The definition a bar checks. Custom bars get one built from the aura name or spell ID they were given.
function Query.DefFor(bar)
    if bar.buffKey ~= "custom" then
        return RAB.Buffs[bar.buffKey]
    end
    local text = strtrim(bar.custom or "")
    local def = customDefs[text]
    if not def then
        local id = tonumber(text)
        local name = id and Compat.SpellInfo(id) or text
        def = {
            key = "custom",
            kind = "custom",
            category = "Custom",
            name = (name and name ~= "") and name or L.CustomBuff,
            match = id and { { id = id, name = name } } or { text },
            -- A custom aura that is also a spell you know can be cast by clicking
            spell = name ~= "" and name or nil,
        }
        customDefs[text] = def
    end
    return def
end

-- =================================================================
-- Who counts
-- =================================================================

local function ExcludedNames(bar)
    if not bar.exclude or #bar.exclude == 0 then
        return nil
    end
    local set = {}
    for _, name in ipairs(bar.exclude) do
        set[strlower(strtrim(name))] = true
    end
    return set
end

-- Is this member checked by this bar? Specials that look at the dead or offline say so with allowDead/allowOffline.
function Query.Eligible(bar, def, m, excluded, allowDead, allowOffline)
    if bar.selfOnly and not m.isPlayer then
        return false
    end
    if not allowOffline and not m.connected then
        return false
    end
    if not allowDead and m.dead then
        return false
    end
    if bar.groups ~= "" and not bar.groups:find(tostring(m.group), 1, true) then
        return false
    end
    if bar.classes ~= "" and not (m.letter and bar.classes:find(m.letter, 1, true)) then
        return false
    end
    if def.class and m.class ~= def.class then
        return false
    end
    if def.ignoreClass and m.letter and def.ignoreClass:find(m.letter, 1, true) then
        return false
    end
    if def.ignoreTanks and m.role == "MAINTANK" then
        return false
    end
    if excluded and excluded[strlower(m.name)] then
        return false
    end
    return true
end

-- =================================================================
-- One member's state
-- =================================================================

-- "have", "missing" or "unknown" for a member, the aura found, and whether the reading is stale
function Query.UnitState(def, m)
    local entry = RAB.Scan:Get(m)
    if not entry then
        return "unknown"
    end
    local list, complete
    if def.kind == "debuff" or def.kind == "dispel" then
        list, complete = entry.debuffs, entry.debuffsComplete
    else
        list, complete = entry.buffs, entry.buffsComplete
    end

    local aura
    if def.kind == "dispel" then
        local types = def.dispelType
        if types == "mine" then
            types = RAB.DispelTypes[Compat.UnitClass("player") or ""] or {}
        else
            types = { [types] = true }
        end
        for _, a in ipairs(list) do
            if a.dispelName and types[a.dispelName] then
                aura = a
                break
            end
        end
    else
        aura = Query.FindAura(list, def.match)
    end

    if aura then
        return "have", aura, entry.stale
    end
    -- Someone far away can come back with no auras at all; that isn't proof they lack the buff
    if not complete or (m.visible == false and #list == 0) then
        return "unknown", nil, entry.stale
    end
    return "missing", nil, entry.stale
end

-- =================================================================
-- Special queries
-- =================================================================

local function AddMember(result, m, state, remaining, stacks)
    result.members[#result.members + 1] = { m = m, state = state, remaining = remaining, stacks = stacks }
    result.total = result.total + 1
    if state == "have" then
        result.buffed = result.buffed + 1
    elseif state == "unknown" then
        result.unknown = result.unknown + 1
    end
end

local Specials = {}

function Specials.alive(bar, def, result, excluded)
    for _, m in ipairs(RAB.members) do
        if Query.Eligible(bar, def, m, excluded, true) then
            AddMember(result, m, m.dead and "missing" or "have")
        end
    end
end

local function SumPower(bar, def, result, excluded, current, maximum, powerTypeOnly)
    result.numeric = true
    local value, max = 0, 0
    for _, m in ipairs(RAB.members) do
        if Query.Eligible(bar, def, m, excluded) then
            local include = true
            if powerTypeOnly then
                include = Compat.Number(UnitPowerType, m.unit) == 0
            end
            if include then
                local cur, top = current(m.unit), maximum(m.unit)
                if cur == nil or top == nil then
                    -- Forever keeps health (and sometimes power) secret; then there is nothing to add up
                    result.unavailable = true
                    return
                end
                value, max = value + cur, max + top
                AddMember(result, m, "have")
            end
        end
    end
    result.value, result.max = value, max
end

function Specials.health(bar, def, result, excluded)
    SumPower(bar, def, result, excluded,
        function(unit) return Compat.Number(UnitHealth, unit) end,
        function(unit) return Compat.Number(UnitHealthMax, unit) end)
end

function Specials.mana(bar, def, result, excluded)
    SumPower(bar, def, result, excluded,
        function(unit) return Compat.Number(UnitPower, unit, 0) end,
        function(unit) return Compat.Number(UnitPowerMax, unit, 0) end,
        true)
end

function Specials.here(bar, def, result, excluded)
    for _, m in ipairs(RAB.members) do
        if Query.Eligible(bar, def, m, excluded, true, true) then
            -- AFK is hidden inside instances on Forever; then nobody counts as away for it
            local away = not m.connected or m.visible == false or Compat.Bool(UnitIsAFK, m.unit) == true
            AddMember(result, m, away and "missing" or "have")
        end
    end
end

local function UnitFlag(fn)
    return function(bar, def, result, excluded)
        for _, m in ipairs(RAB.members) do
            if Query.Eligible(bar, def, m, excluded, true) then
                local flag = Compat.Bool(fn, m.unit)
                AddMember(result, m, flag == nil and "unknown" or (flag and "have" or "missing"))
            end
        end
    end
end
Specials.incombat = UnitFlag(UnitAffectingCombat)
Specials.pvp = UnitFlag(UnitIsPVP)

function Specials.blank()
end

-- =================================================================
-- Evaluating a bar
-- =================================================================

local function NewResult(def)
    return { def = def, buffed = 0, fading = 0, total = 0, unknown = 0, stale = false, members = {} }
end

local function EvaluateWeapon(bar, def, result)
    local player = RAB:PlayerMember()
    if not player or not Compat.WeaponInSlot(def.slot) then
        result.noWeapon = true
        return
    end
    local enchanted, remaining = Compat.WeaponEnchant(def.slot)
    AddMember(result, player, enchanted and "have" or "missing", remaining)
    if enchanted and remaining and remaining < (def.recast or 2) * 60 then
        result.fading = result.fading + 1
    end
end

-- Everything a bar shows: counts, who has and lacks it, and the facts click casting needs
function Query.Evaluate(bar)
    local def = Query.DefFor(bar)
    local result = NewResult(def)
    if not def then
        return result
    end
    local excluded = ExcludedNames(bar)

    if def.kind == "special" then
        local special = Specials[def.query]
        if special then
            special(bar, def, result, excluded)
        end
        return result
    elseif def.kind == "weapon" then
        EvaluateWeapon(bar, def, result)
        return result
    end

    local recast = def.recast and def.recast * 60
    for _, m in ipairs(RAB.members) do
        if Query.Eligible(bar, def, m, excluded) then
            local state, aura, stale = Query.UnitState(def, m)
            local remaining = Remaining(aura)
            AddMember(result, m, state, remaining, aura and aura.applications)
            if stale then
                result.stale = true
            end
            if state == "have" and recast and remaining and remaining < recast then
                result.fading = result.fading + 1
                result.members[#result.members].fading = true
            end
        end
    end
    return result
end

-- Is the bar's job done (everyone buffed, or no one debuffed)? Used to hide finished bars.
function Query.IsComplete(result)
    local def = result.def
    if not def or result.numeric or def.kind == "special" then
        return false
    end
    if def.kind == "debuff" or def.kind == "dispel" then
        return result.buffed == 0 and result.unknown == 0
    end
    if def.invert then
        return false
    end
    return result.total > 0 and result.buffed - result.fading >= result.total
end

-- =================================================================
-- Chat output
-- =================================================================

local function ClassName(token)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token or "?"
end

-- "Missing Arcane Intellect: [3 / 25] Group 2 [2], Bob [Mage; G3]." Whole groups (or classes, for blessings)
-- missing it are named as one.
function Query.Report(bar, result, showHave)
    local def = result.def
    local name = bar.label and bar.label ~= "" and bar.label or (def and def.name) or "?"
    if not def then
        return string.format(L.OutNotApplicable, name)
    end
    if result.numeric then
        if result.unavailable or not result.max or result.max == 0 then
            return string.format(L.OutNotApplicable, def.name)
        end
        return string.format("%s: %d%% (%d / %d)", def.name, math.floor(result.value * 100 / result.max),
            result.value, result.max)
    end
    local known = result.total - result.unknown
    if known <= 0 then
        return string.format(L.OutNotApplicable, def.name)
    end

    local wanted = showHave and "have" or "missing"
    local count = showHave and result.buffed or (known - result.buffed)
    local unknownText = result.unknown > 0 and string.format(L.OutUnknown, result.unknown) or ""
    if count == known then
        return string.format(showHave and L.OutEveryone or L.OutNoOne, def.name) .. unknownText
    elseif count == 0 then
        return string.format(showHave and L.OutNoOne or L.OutEveryone, def.name) .. unknownText
    end

    local byClass = def.sort == "class"
    local buckets, order = {}, {}
    for _, entry in ipairs(result.members) do
        if entry.state ~= "unknown" then
            local key = byClass and (entry.m.class or "?") or entry.m.group
            local bucket = buckets[key]
            if not bucket then
                bucket = { all = 0, names = {} }
                buckets[key] = bucket
                order[#order + 1] = key
            end
            bucket.all = bucket.all + 1
            if entry.state == wanted then
                bucket.names[#bucket.names + 1] = string.format("%s [%s; G%d]", entry.m.name,
                    ClassName(entry.m.class), entry.m.group)
            end
        end
    end
    table.sort(order, function(a, b)
        return tostring(a) < tostring(b)
    end)

    local parts = {}
    for _, key in ipairs(order) do
        local bucket = buckets[key]
        local n = #bucket.names
        if n > 1 and n == bucket.all and IsInRaid() then
            local label = byClass and string.format(L.OutClass, ClassName(key)) or string.format(L.OutGroup, key)
            parts[#parts + 1] = label .. " [" .. n .. "]"
        elseif n > 0 then
            parts[#parts + 1] = table.concat(bucket.names, ", ")
        end
    end
    local header = showHave and L.OutHave or L.OutMissing
    return string.format(header, def.name, count, known, table.concat(parts, ", ")) .. unknownText
end

-- Where a bar's report goes: a chat type and target, or nil to print it locally
local function OutputTarget(bar)
    local out = bar.output or "RAID"
    if out == "RAID" then
        if IsInRaid() then
            return "RAID"
        elseif IsInGroup() then
            return "PARTY"
        end
        return nil
    elseif out == "PARTY" then
        return IsInGroup() and "PARTY" or nil
    elseif out == "CONSOLE" then
        return nil
    end
    local whisper = out:match("^WHISPER:(.+)$")
    if whisper then
        return "WHISPER", whisper
    end
    return out
end

local function FilterPrefix(bar)
    local prefix = ""
    if bar.groups ~= "" and bar.groups ~= "12345678" then
        prefix = "[G" .. bar.groups .. "] "
    end
    if bar.classes ~= "" and #bar.classes < 9 then
        prefix = prefix .. "[" .. bar.classes .. "] "
    end
    return prefix
end

-- Sends a report in pieces under the chat limit, split at commas
local function SendLong(text, chatType, target)
    local MAX = 250
    while #text > MAX do
        local cut = text:sub(1, MAX):match(".*(), ") or MAX
        Compat.SendChat(text:sub(1, cut - 1) .. " ...", chatType, target)
        text = "... " .. text:sub(cut + 2)
    end
    Compat.SendChat(text, chatType, target)
end

-- Reports a bar to its chat channel (or locally), as Ctrl-click and /rabq do. forceTarget overrides the bar's
-- channel: a chat type, or "SELF" to print it only for you.
function Query.Output(bar, showHave, forceTarget, forceWhisper)
    RAB:BuildMembers()
    RAB.Scan:BeginPass()
    local result = Query.Evaluate(bar)
    local def = result.def
    if def and def.invert then
        showHave = not showHave
    end
    local text = L.ChatPrefix .. FilterPrefix(bar) .. Query.Report(bar, result, showHave)
    local chatType, target
    if forceTarget == "SELF" then
        chatType = nil
    elseif forceTarget then
        chatType, target = forceTarget, forceWhisper
        if chatType == "RAID" and not IsInRaid() then
            chatType = IsInGroup() and "PARTY" or nil
        elseif chatType == "PARTY" and not IsInGroup() then
            chatType = nil
        end
    else
        chatType, target = OutputTarget(bar)
    end
    if chatType and Compat.ChatLocked() then
        RAB:Print(L.ChatLocked, "warn")
        chatType = nil
    end
    if chatType then
        SendLong(text, chatType, target)
    else
        RAB:Print(text)
    end
end
