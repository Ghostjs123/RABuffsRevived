-- RABuffs: The aura cache. Each group member's buffs and debuffs are read once and kept by GUID (unit tokens
-- like raid7 move to someone else when the roster changes), then read again only after a UNIT_AURA for them, or
-- every MAX_AGE seconds in case one was missed.
--
-- While the client hides auras (Forever, in combat, encounters and PvP matches) nothing is read; the last
-- reading stays and is marked stale, so bars keep showing what was true going in instead of everyone missing.
local _, RAB = ...

local Compat = RAB.Compat

local MAX_AGE = 10

local Scan = {
    cache = {},   -- guid -> { buffs, debuffs, buffsComplete, debuffsComplete, time, stale }
    dirty = {},   -- guid -> true when a UNIT_AURA came in since the last reading
    restricted = false,
}
RAB.Scan = Scan

function Scan:MarkUnit(unit)
    local guid = Compat.UnitGUID(unit)
    if guid then
        self.dirty[guid] = true
    end
end

function Scan:MarkAll()
    for guid in pairs(self.cache) do
        self.dirty[guid] = true
    end
end

-- Forgets people no longer in the group
function Scan:Prune()
    local keep = {}
    for _, entry in ipairs(Compat.Roster({})) do
        local guid = Compat.UnitGUID(entry.unit)
        if guid then
            keep[guid] = true
        end
    end
    for guid in pairs(self.cache) do
        if not keep[guid] then
            self.cache[guid] = nil
            self.dirty[guid] = nil
        end
    end
end

-- Called once per refresh, before any Get
function Scan:BeginPass()
    self.restricted = Compat.AurasRestricted()
    self.now = GetTime()
end

-- The cache entry for a member (a table from RAB.members), read now if needed. nil when nothing has ever been
-- readable for them.
function Scan:Get(member)
    local guid = member.guid
    if not guid then
        return nil
    end
    local entry = self.cache[guid]
    if self.restricted then
        if entry then
            entry.stale = true
        end
        return entry
    end
    if entry and not self.dirty[guid] and (self.now or GetTime()) - entry.time < MAX_AGE then
        return entry
    end

    local buffs, buffsComplete = Compat.ReadAuras(member.unit, "HELPFUL")
    if not buffs then
        -- Became unreadable since BeginPass
        if entry then
            entry.stale = true
        end
        return entry
    end
    local debuffs, debuffsComplete = Compat.ReadAuras(member.unit, "HARMFUL")
    entry = entry or {}
    entry.buffs = buffs
    entry.buffsComplete = buffsComplete
    entry.debuffs = debuffs or {}
    entry.debuffsComplete = debuffs ~= nil and debuffsComplete
    entry.time = GetTime()
    entry.stale = false
    self.cache[guid] = entry
    self.dirty[guid] = nil
    return entry
end
