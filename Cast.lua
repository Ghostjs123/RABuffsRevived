-- RABuffs: Click to buff. Bars are secure action buttons: addon code can't cast, only set up what a click will
-- do, and only out of combat. So after every refresh out of combat each bar is aimed at the best person to buff
-- next (plain click for the single-target spell, Alt-click for the group one). In combat the aim stays as it was.
local _, RAB = ...

local L = RAB.L
local Compat = RAB.Compat
local Query = RAB.Query

local Cast = {
    pending = {},   -- guid -> time until which they count as just buffed (the aura may not have arrived yet)
}
RAB.Cast = Cast

local PENDING_TIME = 3
local NOOP = ATTRIBUTE_NOOP or ""

function Cast:IsPending(guid)
    local t = guid and self.pending[guid]
    return t ~= nil and t > GetTime()
end

-- =================================================================
-- Choosing a target
-- =================================================================

local function ColoredName(m)
    local _, _, _, colorStr = Compat.ClassColor(m.class)
    return "|c" .. colorStr .. m.name .. "|r"
end
Cast.ColoredName = ColoredName

local function OwnGroup()
    local player = RAB:PlayerMember()
    return player and player.group
end

-- How much a member wants this buff: yourself first unless the buff says otherwise, your own party next,
-- classes the buff matters most to, and anyone just buffed (pending) last
local function Priority(def, m, ownGroup)
    local p = 1
    if m.isPlayer then
        p = def.selfPriority or 5
    end
    if IsInRaid() and m.group == ownGroup then
        p = p + 1
    end
    if def.priority and m.class and def.priority[m.class] then
        p = p + def.priority[m.class]
    end
    if Cast:IsPending(m.guid) then
        p = p / 10
    end
    return p
end

-- Can a spell reach them? Out of range, out of sight, dead or offline can't be buffed. When the game won't say
-- (Forever hides range in some places) we let the click try and the game answer.
local function Reachable(m)
    return m.connected and not m.dead and m.visible ~= false and m.inRange ~= false
end

-- PvP-flagged players are skipped while you aren't flagged, so a buff doesn't flag you
local function PvPSafe(m)
    if not RAB.settings.skipPvP or m.isPlayer then
        return true
    end
    if Compat.Bool(UnitIsPVP, "player") then
        return true
    end
    return Compat.Bool(UnitIsPVP, m.unit) ~= true
end

local function HasReagents(def)
    if not def.reagents then
        return true, nil
    end
    local count = 0
    for _, itemID in ipairs(def.reagents) do
        count = count + Compat.ItemCount(itemID)
    end
    return count > 0, count
end

local function SpellAction(spell, m)
    return { type = "spell", spell = spell, unit = m.unit, guid = m.guid, member = m }
end

-- =================================================================
-- Plans: what a click does, per bar
-- =================================================================

-- plan = { primary = action, alt = action, notes = { tooltip lines } }
-- action = { type = "spell"|"item", spell, item, unit, slot, guid, member, label }

local function PlanSelfSpell(def, spell, plan)
    local player = RAB:PlayerMember()
    if not player then
        return
    end
    local state, aura = Query.UnitState(def, player)
    local remaining = Query.Remaining(aura)
    local fading = state == "have" and def.recast and remaining and remaining < def.recast * 60
    if state == "have" and not fading then
        return
    end
    plan.primary = SpellAction(spell, player)
    plan.recast = fading
end

local function PlanGroupSpell(def, result, spell, groupSpell, plan)
    local ownGroup = OwnGroup()
    local missing, fading, outOfRange = {}, {}, 0
    for _, entry in ipairs(result.members) do
        local m = entry.m
        local wanted = entry.state == "missing" or (entry.state == "have" and entry.fading)
        if wanted and PvPSafe(m) then
            if Reachable(m) then
                local list = entry.state == "missing" and missing or fading
                list[#list + 1] = { m = m, p = Priority(def, m, ownGroup) }
            elseif entry.state == "missing" then
                outOfRange = outOfRange + 1
            end
        end
    end
    if outOfRange > 0 then
        plan.notes[#plan.notes + 1] = string.format(L.OutOfRange, outOfRange)
    end

    local candidates = missing
    if #candidates == 0 then
        candidates = fading
        plan.recast = true
    end
    if #candidates == 0 then
        if result.total > 0 and outOfRange == 0 then
            plan.notes[#plan.notes + 1] = L.NothingToCast
        end
        return
    end
    table.sort(candidates, function(a, b)
        return a.p > b.p
    end)

    local single = spell and SpellAction(spell, candidates[1].m)

    -- The group version goes to the party (or class) with the most people needing it
    local group
    if groupSpell and #missing >= (def.groupMin or 2) then
        local hasReagents, count = HasReagents(def)
        if not hasReagents then
            plan.notes[#plan.notes + 1] = string.format(L.NoReagent, groupSpell)
        else
            if count then
                plan.notes[#plan.notes + 1] = string.format(L.Reagents, count)
            end
            local buckets, best = {}, nil
            for _, c in ipairs(missing) do
                local key = def.groupBy == "class" and c.m.class or c.m.group
                local bucket = buckets[key]
                if not bucket then
                    bucket = { heads = 0, p = 0, target = c.m, targetP = -math.huge }
                    buckets[key] = bucket
                end
                bucket.heads = bucket.heads + 1
                bucket.p = bucket.p + c.p
                if c.p > bucket.targetP then
                    bucket.target, bucket.targetP = c.m, c.p
                end
            end
            for _, bucket in pairs(buckets) do
                if not best or bucket.heads > best.heads or (bucket.heads == best.heads and bucket.p > best.p) then
                    best = bucket
                end
            end
            if best and best.heads >= (def.groupMin or 2) then
                group = SpellAction(groupSpell, best.target)
            end
        end
    end

    if RAB.settings.groupDefault and group then
        plan.primary, plan.alt = group, single or group
    else
        plan.primary, plan.alt = single or group, group or single
    end
end

local function PlanItem(def, result, plan)
    local name = Compat.ItemName(def.item) or def.name
    local count = Compat.ItemCount(def.item)
    if count == 0 then
        plan.notes[#plan.notes + 1] = string.format(L.NoItem, name)
        return
    end
    plan.notes[#plan.notes + 1] = string.format(L.ItemCount, count)
    local player = RAB:PlayerMember()
    if not player then
        return
    end
    local state
    if def.kind == "weapon" then
        if result.noWeapon then
            plan.notes[#plan.notes + 1] = L.NoWeapon
            return
        end
        local entry = result.members[1]
        state = entry and entry.state
        if state == "have" and result.fading == 0 then
            return
        end
    else
        state = Query.UnitState(def, player)
        if state == "have" then
            return
        end
    end
    local cooldown = Compat.ItemCooldown(def.item)
    if cooldown > 0 then
        plan.notes[#plan.notes + 1] = string.format(L.OnCooldown, name, RAB.FormatTime(cooldown))
    end
    plan.primary = {
        type = "item",
        item = "item:" .. def.item,
        -- Scrolls and the like need a target; yourself. Coatings go on the weapon slot instead.
        unit = def.kind ~= "weapon" and "player" or nil,
        slot = def.kind == "weapon" and def.slot or nil,
        label = name,
    }
end

local function PlanResurrect(def, result, plan)
    local classToken = Compat.UnitClass("player")
    local spell
    for _, name in ipairs(RAB.ResSpells[classToken] or {}) do
        spell = Compat.KnownSpell(name)
        if spell then
            break
        end
    end
    if not spell then
        return
    end
    local best, bestP
    for _, entry in ipairs(result.members) do
        local m = entry.m
        if entry.state == "missing" and m.connected and m.visible ~= false and not m.isPlayer and PvPSafe(m) then
            local p = 1
            if m.class == "PRIEST" or m.class == "PALADIN" or m.class == "SHAMAN" then
                p = 3
            elseif m.class == "DRUID" or m.class == "MAGE" then
                p = 2
            end
            if Cast:IsPending(m.guid) then
                p = p / 15
            end
            if not bestP or p > bestP then
                best, bestP = m, p
            end
        end
    end
    if best then
        plan.primary = SpellAction(spell, best)
    end
end

local function PlanSoulstone(def, result, plan)
    if Compat.UnitClass("player") ~= "WARLOCK" then
        return
    end
    local stone
    for _, itemID in ipairs(RAB.Soulstones) do
        if Compat.ItemCount(itemID) > 0 then
            stone = itemID
            break
        end
    end
    if not stone then
        for _, name in ipairs(RAB.CreateSoulstone) do
            local spell = Compat.KnownSpell(name)
            if spell then
                plan.primary = { type = "spell", spell = spell, unit = "player", label = spell }
                return
            end
        end
        return
    end
    local cooldown = Compat.ItemCooldown(stone)
    local name = Compat.ItemName(stone) or def.name
    if cooldown > 0 then
        plan.notes[#plan.notes + 1] = string.format(L.OnCooldown, name, RAB.FormatTime(cooldown))
    end
    local ownGroup = OwnGroup()
    local best, bestP
    for _, entry in ipairs(result.members) do
        local m = entry.m
        if entry.state == "missing" and Reachable(m) and PvPSafe(m) then
            local p = Priority(def, m, ownGroup)
            if not bestP or p > bestP then
                best, bestP = m, p
            end
        end
    end
    if best then
        plan.primary = { type = "item", item = "item:" .. stone, unit = best.unit, guid = best.guid, member = best,
            label = name }
    end
end

-- What clicking a bar would do right now
function Cast.Plan(bar, result)
    local plan = { notes = {} }
    local def = result.def
    if not def then
        return plan
    end
    if not bar.castOnClick then
        return plan
    end
    if def.cast == "res" then
        PlanResurrect(def, result, plan)
    elseif def.cast == "soulstone" then
        PlanSoulstone(def, result, plan)
    elseif def.kind == "item" or def.kind == "weapon" then
        if def.item then
            PlanItem(def, result, plan)
        end
    elseif def.kind ~= "special" and def.kind ~= "debuff" and def.kind ~= "dispel" then
        local spell = Compat.KnownSpell(def.spell)
        local groupSpell = Compat.KnownSpell(def.groupSpell)
        if def.kind == "self" then
            if spell and Compat.UnitClass("player") == def.class then
                PlanSelfSpell(def, spell, plan)
            end
        elseif def.kind == "aura" then
            if spell then
                PlanSelfSpell(def, spell, plan)
            end
        elseif spell or groupSpell then
            PlanGroupSpell(def, result, spell, groupSpell, plan)
        end
    end
    if plan.primary and not plan.alt then
        plan.alt = plan.primary
    end
    return plan
end

-- =================================================================
-- Applying a plan to a bar's secure button
-- =================================================================

local function Signature(action)
    if not action then
        return "-"
    end
    return table.concat({ action.type or "", action.spell or "", action.item or "", action.unit or "",
        tostring(action.slot or "") }, "|")
end

local function SetAction(button, prefix, action)
    button:SetAttribute(prefix .. "type1", action and action.type or NOOP)
    button:SetAttribute(prefix .. "spell1", action and action.spell or NOOP)
    button:SetAttribute(prefix .. "item1", action and action.item or NOOP)
    button:SetAttribute(prefix .. "unit1", action and action.unit or NOOP)
    button:SetAttribute(prefix .. "target-slot1", action and action.slot or NOOP)
end

-- Set once when a bar is made: Ctrl, Shift and their mixes report or show the other list instead of casting,
-- so they must do nothing secure (otherwise they'd fall back to the plain click's cast)
function Cast.SetupButton(button)
    button:RegisterForClicks("AnyUp", "AnyDown")
    for _, prefix in ipairs({ "ctrl-", "shift-", "ctrl-shift-", "alt-ctrl-", "alt-shift-", "alt-ctrl-shift-" }) do
        button:SetAttribute(prefix .. "type1", NOOP)
    end
    button:SetAttribute("type2", NOOP)
    button:SetAttribute("*type2", NOOP)
    SetAction(button, "", nil)
    SetAction(button, "alt-", nil)
end

-- Aims a bar's button; only out of combat. Returns false when it couldn't.
function Cast.Apply(button, plan)
    if InCombatLockdown() then
        return false
    end
    local signature = Signature(plan.primary) .. "#" .. Signature(plan.alt)
    if button.rabSignature ~= signature then
        button.rabSignature = signature
        SetAction(button, "", plan.primary)
        SetAction(button, "alt-", plan.alt)
    end
    button.rabPlan = plan
    return true
end

-- =================================================================
-- After a click
-- =================================================================

local lastClick

-- PreClick runs (insecure) just before the secure click: remember what it is about to do
function Cast.OnPreClick(button)
    local plan = button.rabPlan
    if not plan or IsControlKeyDown() or IsShiftKeyDown() then
        lastClick = nil
        return
    end
    local action = IsAltKeyDown() and plan.alt or plan.primary
    if action then
        lastClick = { action = action, time = GetTime() }
    end
end

RAB:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit)
    if unit ~= "player" or not lastClick or GetTime() - lastClick.time > 2 then
        return
    end
    local action = lastClick.action
    lastClick = nil
    if action.guid then
        Cast.pending[action.guid] = GetTime() + PENDING_TIME
    end
    if RAB.settings.announce then
        if action.member then
            RAB:Print(string.format(L.CastOn, action.spell or action.label or "?", ColoredName(action.member)))
        else
            RAB:Print(string.format(L.Using, action.label or action.spell or "?"))
        end
    end
    RAB:RequestRefresh()
end)
