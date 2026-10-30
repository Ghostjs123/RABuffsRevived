-- RABuffs: The bars window. Each bar is a secure button (so a click can cast), which makes the window protected:
-- in combat it can't be moved, shown, hidden or re-laid out by addon code. Visibility goes through a state driver
-- instead, and layout changes wait for combat to end.
local _, RAB = ...

local L = RAB.L
local Compat = RAB.Compat
local Query = RAB.Query
local Cast = RAB.Cast

local UI = {
    buttons = {},
    results = {},
}
RAB.UI = UI

local BAR_HEIGHT = 14
local TITLE_HEIGHT = 14
local PAD = 5
local BAR_TEXTURE = "Interface\\AddOns\\RABuffs\\bar.tga"
local NAMES_PER_LINE = 4

-- =================================================================
-- The window
-- =================================================================

function UI:SavePosition()
    local point, _, relativePoint, x, y = self.frame:GetPoint(1)
    RAB.charDB.position = { point, relativePoint, x, y }
end

function UI:RestorePosition()
    local f = self.frame
    f:ClearAllPoints()
    local pos = RAB.charDB.position
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    end
end

function UI:ResetPosition()
    RAB:OutOfCombat("position", function()
        RAB.charDB.position = nil
        UI:RestorePosition()
    end)
end

function UI:Create()
    if self.frame then
        return
    end
    local f = CreateFrame("Frame", "RABuffsFrame", UIParent, "BackdropTemplate")
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.6)
    f:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    self.frame = f

    local title = CreateFrame("Button", nil, f)
    title:SetHeight(TITLE_HEIGHT)
    title:SetPoint("TOPLEFT", PAD, -PAD + 1)
    title:SetPoint("TOPRIGHT", -PAD, -PAD + 1)
    title.text = title:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title.text:SetPoint("LEFT", 2, 0)
    title.text:SetPoint("RIGHT", -2, 0)
    title.text:SetJustifyH("LEFT")
    title:RegisterForDrag("LeftButton")
    title:RegisterForClicks("RightButtonUp")
    title:SetScript("OnDragStart", function()
        if not RAB.settings.locked and not InCombatLockdown() then
            f:StartMoving()
        end
    end)
    title:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        UI:SavePosition()
    end)
    title:SetScript("OnClick", function(button)
        RAB.Menu.Open(button)
    end)
    title:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:AddLine(L.AddonName)
        GameTooltip:AddLine(string.format(L.ProfileCurrent, RAB.profileName), 1, 1, 1)
        GameTooltip:AddLine(L.RightClickMenu, 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    title:SetScript("OnLeave", GameTooltip_Hide)
    self.title = title

    self:RestorePosition()
    self:RebuildBars()
    self:UpdateVisibility()
end

-- Shown or hidden by a secure state driver, so "hide in combat" works and nothing is blocked in combat
function UI:UpdateVisibility()
    if not self.frame then
        return
    end
    RAB:OutOfCombat("visibility", function()
        local s = RAB.settings
        local condition
        if RAB.charDB.hidden then
            condition = "hide"
        else
            condition = (s.hideInCombat and "[combat] hide; " or "")
                .. "[group:raid] " .. (s.showRaid and "show" or "hide") .. "; "
                .. "[group:party] " .. (s.showParty and "show" or "hide") .. "; "
                .. (s.showSolo and "show" or "hide")
        end
        RegisterStateDriver(UI.frame, "visibility", condition)
    end)
end

-- Shows the window now, whatever group you're in: if the setting for this kind of group (solo, party, raid)
-- would keep it hidden, that setting is turned on
local GROUP_SETTINGS = { [0] = "showSolo", "showParty", "showRaid" }
function UI:Show()
    local key = GROUP_SETTINGS[Compat.GroupState()]
    if not RAB.settings[key] then
        RAB.settings[key] = true
        RAB:Print(L["ShowEnabled_" .. key])
    end
    self:SetHidden(false)
end

function UI:SetHidden(hidden)
    RAB.charDB.hidden = hidden
    self:UpdateVisibility()
    if hidden then
        RAB:Print(L.WindowHidden)
    end
end

-- =================================================================
-- Bars
-- =================================================================

local function CreateBar(index)
    local b = CreateFrame("Button", "RABuffsBar" .. index, UI.frame, "SecureActionButtonTemplate")
    b.index = index
    b:SetHeight(BAR_HEIGHT)

    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.5)

    -- The fills are status bars on their own (non-secure) child frames, like unit frames' health bars, so they
    -- can change in combat. Lighter fill: everyone who has it; solid fill: those whose buff isn't running out.
    local function Fill(alpha)
        local bar = CreateFrame("StatusBar", nil, b)
        bar:SetAllPoints()
        bar:SetStatusBarTexture(BAR_TEXTURE)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:SetAlpha(alpha)
        return bar
    end
    b.fade = Fill(0.45)
    b.fill = Fill(1)

    local overlay = CreateFrame("Frame", nil, b)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(b.fill:GetFrameLevel() + 1)
    b.count = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.count:SetPoint("RIGHT", -3, 0)
    b.count:SetJustifyH("RIGHT")
    b.label = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("LEFT", 3, 0)
    b.label:SetPoint("RIGHT", b.count, "LEFT", -3, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)

    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    Cast.SetupButton(b)
    b:SetScript("PreClick", function(self)
        Cast.OnPreClick(self)
    end)
    b:SetScript("PostClick", function(self, mouseButton, down)
        UI:OnBarClick(self, mouseButton, down)
    end)
    b:SetScript("OnEnter", function(self)
        UI:ShowTooltip(self)
    end)
    b:SetScript("OnLeave", function()
        UI:HideTooltip()
    end)
    return b
end

-- Makes one button per bar of the current profile and lays them out (waits for combat to end)
function UI:RebuildBars()
    if not self.frame then
        return
    end
    RAB:OutOfCombat("rebuild", function()
        for i = 1, #RAB.bars do
            if not UI.buttons[i] then
                UI.buttons[i] = CreateBar(i)
            end
            UI.buttons[i].rabSignature = nil
        end
        for i = #RAB.bars + 1, #UI.buttons do
            local b = UI.buttons[i]
            b:Hide()
            Cast.Apply(b, { notes = {} })
            b.rabPlan = nil
        end
        wipe(UI.results)
        UI.completeSignature = nil
        UI:Layout()
        RAB:RequestRefresh()
    end)
end

-- Positions the shown bars and sizes the window (out of combat only)
function UI:Layout()
    if InCombatLockdown() then
        self.layoutPending = true
        return
    end
    self.layoutPending = false
    local f = self.frame
    local s = RAB.settings
    local width = s.width
    f:SetScale(s.scale)
    self.title.text:SetText(L.AddonName .. "  |cff999999" .. (RAB.profileName or "") .. "|r")

    local y = -PAD - TITLE_HEIGHT
    for i = 1, #RAB.bars do
        local b = self.buttons[i]
        local result = self.results[i]
        if s.hideComplete and result and Query.IsComplete(result) then
            b:Hide()
        else
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
            b:SetWidth(width)
            b:Show()
            y = y - BAR_HEIGHT - 1
        end
    end
    f:SetWidth(width + PAD * 2)
    f:SetHeight(-y + PAD - 1)
end

local function CountText(result)
    local def = result.def
    if not def then
        return "", 0, 0
    end
    if def.query == "blank" then
        return "", 0, 0
    end
    if result.numeric then
        if result.unavailable or not result.max or result.max == 0 then
            return "?", 0, 0
        end
        local fraction = result.value / result.max
        return math.floor(fraction * 100) .. "%", fraction, fraction
    end
    if result.noWeapon then
        return "-", 0, 0
    end
    local total = result.total
    if total == 0 then
        return "0/0", 0, 0
    end
    local text = result.buffed .. "/" .. total
    if result.unknown > 0 then
        text = text .. "?"
    end
    return text, (result.buffed - result.fading) / total, result.buffed / total
end

function UI:Paint(b, bar, result)
    local def = result.def
    local r, g, bl = bar.color[1], bar.color[2], bar.color[3]
    b.fill:SetStatusBarColor(r, g, bl)
    b.fade:SetStatusBarColor(r, g, bl)
    b.label:SetText((bar.label and bar.label ~= "") and bar.label or (def and def.name) or bar.buffKey)
    local text, solid, faded = CountText(result)
    b.count:SetText(text)
    -- Grey count: buffs can't be read right now (Forever, in combat), so it shows the last reading
    if result.stale then
        b.count:SetTextColor(0.6, 0.6, 0.6)
    else
        b.count:SetTextColor(1, 1, 1)
    end
    b.fill:SetValue(math.max(0, math.min(1, solid)))
    b.fade:SetValue(math.max(0, math.min(1, faded)))
end

-- Called by RAB:Refresh: re-evaluates every bar, repaints, and re-aims the clicks out of combat
function UI:Update()
    if not self.frame then
        return
    end
    local inCombat = InCombatLockdown()
    local completeSignature = ""
    for i, bar in ipairs(RAB.bars) do
        local b = self.buttons[i]
        if b then
            local result = Query.Evaluate(bar)
            self.results[i] = result
            self:Paint(b, bar, result)
            if not inCombat then
                Cast.Apply(b, Cast.Plan(bar, result))
            end
            if RAB.settings.hideComplete then
                completeSignature = completeSignature .. (Query.IsComplete(result) and "1" or "0")
            end
        end
    end
    if not inCombat and (self.layoutPending or completeSignature ~= self.completeSignature) then
        self.completeSignature = completeSignature
        self:Layout()
    end
    self:RefreshTooltip()
end

function UI:CombatChanged()
    if not InCombatLockdown() and self.layoutPending then
        self:Layout()
    end
    self:RefreshTooltip()
end

function UI:OnBarClick(b, mouseButton, down)
    if down then
        return
    end
    local bar = RAB.bars[b.index]
    if not bar then
        return
    end
    if mouseButton == "RightButton" then
        RAB.Menu.Open(b, b.index)
    elseif mouseButton == "LeftButton" then
        if IsControlKeyDown() then
            Query.Output(bar, IsShiftKeyDown())
        elseif not (b.rabPlan and b.rabPlan.primary) then
            -- Nothing to cast: say who is missing it, just to you
            Query.Output(bar, IsShiftKeyDown(), "SELF")
        end
    end
end

-- =================================================================
-- Tooltip
-- =================================================================

local function OutputName(bar)
    local out = bar.output or "RAID"
    if out == "RAID" then
        return IsInRaid() and CHAT_MSG_RAID or (IsInGroup() and CHAT_MSG_PARTY) or L.OutSelf
    elseif out == "PARTY" then
        return CHAT_MSG_PARTY
    elseif out == "SAY" then
        return CHAT_MSG_SAY
    elseif out == "GUILD" then
        return CHAT_MSG_GUILD
    elseif out == "OFFICER" then
        return CHAT_MSG_OFFICER
    elseif out == "CONSOLE" then
        return L.OutSelf
    end
    return out:match("^WHISPER:(.+)$") or out
end

-- Names grouped by party (or class, for blessings), a few per line, with the group on the right
local function AddNameLines(result, state, onlyFading)
    local byClass = result.def.sort == "class"
    local buckets, order = {}, {}
    for _, entry in ipairs(result.members) do
        local fits
        if onlyFading then
            fits = entry.fading
        else
            fits = entry.state == state
        end
        if fits then
            local m = entry.m
            local key = byClass and (m.class or "?") or m.group
            if not buckets[key] then
                buckets[key] = {}
                order[#order + 1] = key
            end
            local name = Cast.ColoredName(m)
            if m.visible == false or m.inRange == false then
                name = "|cff808080" .. m.name .. "|r"
            end
            if entry.remaining and (onlyFading or entry.fading) then
                name = name .. " |cffaaaaaa(" .. RAB.FormatTime(entry.remaining) .. ")|r"
            end
            if entry.stacks and entry.stacks > 1 then
                name = name .. " [" .. entry.stacks .. "]"
            end
            table.insert(buckets[key], name)
        end
    end
    table.sort(order, function(a, b)
        return tostring(a) < tostring(b)
    end)
    local any = false
    for _, key in ipairs(order) do
        local names = buckets[key]
        local right = byClass and ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[key]) or key)
            or (IsInRaid() and string.format(L.OutGroup, key) or "")
        for i = 1, #names, NAMES_PER_LINE do
            local line = table.concat(names, ", ", i, math.min(#names, i + NAMES_PER_LINE - 1))
            GameTooltip:AddDoubleLine(line, i == 1 and right or "", 1, 1, 1, 0.6, 0.6, 0.6)
            any = true
        end
    end
    return any
end

local function ActionTarget(action)
    if action.member then
        return Cast.ColoredName(action.member)
    end
    return action.label or action.spell or "?"
end

function UI:ShowTooltip(b)
    local bar = RAB.bars[b.index]
    local result = self.results[b.index]
    if not bar or not result or not result.def then
        return
    end
    local def = result.def
    self.tooltipButton = b

    GameTooltip:SetOwner(b, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    local x = b:GetCenter()
    if x and x * b:GetEffectiveScale() < UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2 then
        GameTooltip:SetPoint("LEFT", b, "RIGHT", 6, 0)
    else
        GameTooltip:SetPoint("RIGHT", b, "LEFT", -6, 0)
    end

    GameTooltip:AddDoubleLine(def.name, (CountText(result)), 1, 0.82, 0, 1, 1, 1)
    if def.description and (def.kind == "special" or def.kind == "custom") then
        GameTooltip:AddLine(def.description, 0.7, 0.7, 0.7, true)
    end

    if not result.numeric and def.query ~= "blank" and not result.noWeapon then
        local showHave = def.invert and true or false
        if IsShiftKeyDown() then
            showHave = not showHave
        end
        local isDebuff = def.kind == "debuff" or def.kind == "dispel"
        local header
        if isDebuff then
            header = showHave and L.AffectedHeader or L.NotAffectedHeader
        else
            header = showHave and L.HaveHeader or L.MissingHeader
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format(header, def.name) .. ":")
        if not AddNameLines(result, showHave and "have" or "missing") then
            GameTooltip:AddLine(L.NoOne, 0.6, 0.6, 0.6)
        end
        if not showHave and result.fading > 0 then
            GameTooltip:AddLine(L.FadingSoon)
            AddNameLines(result, nil, true)
        end
        if result.unknown > 0 then
            local names = {}
            for _, entry in ipairs(result.members) do
                if entry.state == "unknown" then
                    names[#names + 1] = entry.m.name
                end
            end
            GameTooltip:AddLine(string.format(L.UnknownLine, table.concat(names, ", ")), 0.6, 0.6, 0.6, true)
        end
        if result.stale then
            GameTooltip:AddLine(L.StaleNote, 0.6, 0.6, 0.6, true)
        end
    end

    local plan = b.rabPlan
    if plan then
        GameTooltip:AddLine(" ")
        if not bar.castOnClick then
            GameTooltip:AddLine(L.ClickCastOff, 0.6, 0.6, 0.6)
        elseif plan.primary then
            local p = plan.primary
            if p.type == "item" and not p.member then
                GameTooltip:AddLine(string.format(L.ClickUse, p.label or "?"), 0, 1, 0)
            else
                local fmt = plan.recast and L.ClickRecast or L.ClickCast
                GameTooltip:AddLine(string.format(fmt, p.spell or p.label or "?", ActionTarget(p)), 0, 1, 0)
            end
            if plan.alt and plan.alt ~= plan.primary then
                GameTooltip:AddLine(string.format(L.AltClickCast, plan.alt.spell or plan.alt.label or "?",
                    ActionTarget(plan.alt)), 0, 0.8, 0)
            end
            if InCombatLockdown() then
                GameTooltip:AddLine(L.CombatLocked, 1, 0.5, 0.25, true)
            end
        end
        for _, note in ipairs(plan.notes or {}) do
            GameTooltip:AddLine(note, 0.8, 0.8, 0.8, true)
        end
    end

    if not result.numeric and def.query ~= "blank" then
        GameTooltip:AddLine((IsShiftKeyDown() and L.ReleaseShift or L.HoldShift), 0.5, 0.5, 0.5)
        GameTooltip:AddLine(string.format(L.CtrlClickReport, OutputName(bar)), 0.5, 0.5, 0.5)
    end
    GameTooltip:AddLine(L.RightClickMenu, 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

function UI:HideTooltip()
    self.tooltipButton = nil
    GameTooltip:Hide()
end

function UI:RefreshTooltip()
    local b = self.tooltipButton
    if b and GameTooltip:IsOwned(b) and b:IsMouseOver() then
        self:ShowTooltip(b)
    end
end
