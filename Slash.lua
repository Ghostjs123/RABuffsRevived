-- RABuffs: /rab and /rabq.
local _, RAB = ...

local L = RAB.L
local Compat = RAB.Compat

local function PrintLines(lines)
    for _, line in ipairs(lines) do
        RAB:Print(line)
    end
end

-- /rab info: the auras on your target, with spell IDs, for setting up custom bars
local function ListTargetAuras()
    local unit = Compat.Bool(UnitExists, "target") and "target" or "player"
    RAB:Print((Compat.UnitName(unit) or unit) .. ":")
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        local auras = Compat.ReadAuras(unit, filter)
        if not auras then
            RAB:Print("  " .. L.StaleNote, "warn")
            return
        end
        for _, aura in ipairs(auras) do
            RAB:Print(string.format("  %s%s (%s)%s", filter == "HARMFUL" and "|cffff6060" or "",
                aura.name or "?", tostring(aura.spellId or "?"), filter == "HARMFUL" and "|r" or ""))
        end
    end
end

local function ListBuffKeys()
    for _, category in ipairs(RAB.Categories) do
        local keys = {}
        for key, def in pairs(RAB.Buffs) do
            if def.category == category then
                keys[#keys + 1] = key
            end
        end
        if #keys > 0 then
            table.sort(keys)
            RAB:Print("|cffffd100" .. category .. ":|r " .. table.concat(keys, ", "))
        end
    end
end

local function ProfileCommand(rest)
    local sub, name = rest:match("^(%S+)%s*(.*)$")
    sub = sub and strlower(sub) or "list"
    name = strtrim(name or "")
    if sub == "list" then
        RAB:Print(L.ProfileList)
        for _, profile in ipairs(RAB:ProfileNames()) do
            RAB:Print("  " .. profile .. (profile == RAB.profileName and " *" or ""))
        end
    elseif sub == "current" then
        RAB:Print(string.format(L.ProfileCurrent, RAB.profileName))
    elseif sub == "load" and name ~= "" then
        RAB:LoadProfile(name)
    elseif sub == "save" and name ~= "" then
        RAB:SaveProfileAs(name)
    elseif sub == "delete" and name ~= "" then
        RAB:DeleteProfile(name)
    else
        PrintLines(L.Help)
    end
end

SLASH_RABUFFS1 = "/rab"
SLASH_RABUFFS2 = "/rabuffs"
SlashCmdList["RABUFFS"] = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")
    cmd = strlower(cmd or "")
    if cmd == "" or cmd == "help" then
        PrintLines(L.Help)
    elseif cmd == "show" and strlower(rest) == "solo" then
        RAB.settings.showSolo = not RAB.settings.showSolo
        RAB.UI:UpdateVisibility()
        RAB:Print(RAB.settings.showSolo and L.SoloOn or L.SoloOff)
    elseif cmd == "show" then
        RAB.UI:Show()
    elseif cmd == "hide" then
        RAB.UI:SetHidden(true)
    elseif cmd == "toggle" then
        if RAB.charDB.hidden then
            RAB.UI:Show()
        else
            RAB.UI:SetHidden(true)
        end
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        RAB.Options:Toggle()
    elseif cmd == "lock" or cmd == "unlock" then
        RAB.settings.locked = cmd == "lock"
        RAB:Print(RAB.settings.locked and L.WindowLocked or L.WindowUnlocked)
    elseif cmd == "reset" then
        RAB.UI:ResetPosition()
        RAB:Print(L.PositionReset)
    elseif cmd == "profile" or cmd == "profiles" then
        ProfileCommand(rest)
    elseif cmd == "buffs" then
        ListBuffKeys()
    elseif cmd == "info" then
        ListTargetAuras()
    else
        PrintLines(L.Help)
    end
end

-- /rabq [raid|party|officer|guild|say|w <name>|c <channel>] [not] <buff> [groups] [classes]
SLASH_RABUFFSQ1 = "/rabq"
SLASH_RABUFFSQ2 = "/rq"
SlashCmdList["RABUFFSQ"] = function(msg)
    msg = strtrim(msg or "")
    if msg == "" or strlower(msg) == "help" then
        PrintLines(L.QueryHelp)
        return
    end

    local words = {}
    for word in msg:gmatch("%S+") do
        words[#words + 1] = word
    end
    local i = 1
    local chatType, target = "SELF", nil
    local first = strlower(words[1])
    if first == "raid" or first == "party" or first == "officer" or first == "guild" or first == "say" then
        chatType = strupper(first)
        i = 2
    elseif (first == "w" or first == "c") and words[2] then
        if first == "w" then
            chatType, target = "WHISPER", words[2]
        else
            local channel = Compat.Number(GetChannelName, words[2])
            if not channel or channel == 0 then
                RAB:Print(L.BadQuery, "warn")
                return
            end
            chatType, target = "CHANNEL", channel
        end
        i = 3
    end

    local showHave = false
    if words[i] and strlower(words[i]) == "not" then
        showHave = true
        i = i + 1
    end

    local key = words[i] and strlower(words[i])
    local groups = words[i + 1] or ""
    local classes = words[i + 2] or ""
    -- The groups can be left out: "/rabq ai mp"
    if not groups:match("^[1-8]*$") then
        groups, classes = "", groups
    end
    classes = strlower(classes)
    if not key or not classes:match("^[mlprdhswa]*$") or words[i + 3] then
        RAB:Print(L.BadQuery, "warn")
        return
    end

    local selfOnly = false
    if not RAB.Buffs[key] and key:sub(1, 4) == "self" and RAB.Buffs[key:sub(5)] then
        key, selfOnly = key:sub(5), true
    end
    if not RAB.Buffs[key] or key == "custom" then
        RAB:Print(string.format(L.UnknownBuff, key), "warn")
        return
    end

    local bar = { buffKey = key, groups = groups, classes = classes, selfOnly = selfOnly, exclude = {},
        color = { 1, 1, 1 }, output = "CONSOLE" }
    RAB.Query.Output(bar, showHave, chatType, target)
end
