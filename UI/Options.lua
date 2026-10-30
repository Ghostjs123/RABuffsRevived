-- RABuffs: The options window (/rab options): the bar list and bar editor, settings, and profiles.
local _, RAB = ...

local L = RAB.L
local Compat = RAB.Compat

local Options = {}
RAB.Options = Options

local WIDTH, HEIGHT = 440, 500
local ROW_HEIGHT = 22

-- =================================================================
-- Small widget helpers
-- =================================================================

local function Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 100, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Checkbox(parent, text, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.Text:SetText(text)
    cb.Text:SetFontObject("GameFontHighlightSmall")
    cb:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
    return cb
end

local function EditBox(parent, width)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(width, 20)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnEnterPressed", eb.ClearFocus)
    return eb
end

local sliderCount = 0
local function Slider(parent, label, minValue, maxValue, step, format, get, set)
    sliderCount = sliderCount + 1
    local s = CreateFrame("Slider", "RABuffsOptionsSlider" .. sliderCount, parent, "OptionsSliderTemplate")
    s:SetWidth(180)
    s:SetMinMaxValues(minValue, maxValue)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s.Low:SetText(string.format(format, minValue))
    s.High:SetText(string.format(format, maxValue))
    s.refresh = function()
        local value = get()
        s:SetValue(value)
        s.Text:SetText(string.format(label, value))
    end
    s:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        if value ~= get() then
            set(value)
        end
        s.Text:SetText(string.format(label, value))
    end)
    return s
end

-- A button showing the current choice that opens a menu of choices
local function Selector(parent, width, buildMenu)
    local b = Button(parent, "", width)
    b:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, buildMenu)
    end)
    return b
end

-- A box with a scrolling multi-line edit box, for profile export and import
local function TextArea(parent, name, width, height)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(width, height)
    box:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0, 0, 0, 0.6)
    local scroll = CreateFrame("ScrollFrame", name, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(width - 36)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    scroll:SetScrollChild(eb)
    box:SetScript("OnMouseDown", function()
        eb:SetFocus()
    end)
    box.editBox = eb
    return box
end

-- =================================================================
-- Window
-- =================================================================

function Options:Create()
    if self.frame then
        return
    end
    local f = CreateFrame("Frame", "RABuffsOptions", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f.TitleText:SetText(L.OptionsTitle)
    f:Hide()
    tinsert(UISpecialFrames, "RABuffsOptions")
    self.frame = f

    self.pages = {}
    self.tabs = {}
    local tabNames = { { "bars", L.TabBars }, { "settings", L.TabSettings }, { "profiles", L.TabProfiles } }
    for i, info in ipairs(tabNames) do
        local tab = Button(f, info[2], 100, function()
            Options:ShowPage(info[1])
        end)
        tab:SetPoint("TOPLEFT", 12 + (i - 1) * 104, -28)
        self.tabs[info[1]] = tab
        local page = CreateFrame("Frame", nil, f)
        page:SetPoint("TOPLEFT", 12, -56)
        page:SetPoint("BOTTOMRIGHT", -12, 10)
        page:Hide()
        self.pages[info[1]] = page
    end

    self:BuildBarsPage(self.pages.bars)
    self:BuildEditor(self.pages.bars)
    self:BuildSettingsPage(self.pages.settings)
    self:BuildProfilesPage(self.pages.profiles)
end

function Options:ShowPage(name)
    for key, page in pairs(self.pages) do
        page:SetShown(key == name)
        self.tabs[key]:SetEnabled(key ~= name)
    end
    self.page = name
    self:Refresh()
end

-- Opens the window; page "bars" with a bar index opens the editor on that bar
function Options:Open(page, barIndex)
    self:Create()
    self.frame:Show()
    self:ShowPage(page or self.page or "bars")
    if barIndex then
        self:EditBar(barIndex)
    end
end

function Options:Toggle()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Open()
    end
end

function Options:Refresh()
    if not self.frame or not self.frame:IsShown() then
        return
    end
    if self.page == "bars" then
        self:RefreshBarList()
    elseif self.page == "settings" then
        for _, refresh in ipairs(self.settingRefreshers) do
            refresh()
        end
    elseif self.page == "profiles" then
        self:RefreshProfiles()
    end
end

-- =================================================================
-- Bars page: the list
-- =================================================================

local function BarName(bar)
    local def = RAB.Query.DefFor(bar)
    return def and def.name or bar.buffKey
end

function Options:BuildBarsPage(page)
    local list = CreateFrame("Frame", nil, page)
    list:SetAllPoints()
    self.list = list

    local scroll = CreateFrame("ScrollFrame", "RABuffsOptionsBarScroll", list, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -24, 34)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 60, 10)
    scroll:SetScrollChild(content)
    self.listContent = content
    self.rows = {}

    local add = Button(list, L.AddBar, 120, function()
        Options:EditBar(nil)
    end)
    add:SetPoint("BOTTOMLEFT", 0, 4)
end

local function MoveBar(index, delta)
    local target = index + delta
    if target < 1 or target > #RAB.bars then
        return
    end
    RAB.bars[index], RAB.bars[target] = RAB.bars[target], RAB.bars[index]
    RAB:BarsChanged()
end

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WIDTH - 60, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)

    row.swatch = row:CreateTexture(nil, "ARTWORK")
    row.swatch:SetSize(12, 12)
    row.swatch:SetPoint("LEFT", 2, 0)
    row.swatch:SetColorTexture(1, 1, 1)

    row.text = Label(row, "", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.swatch, "RIGHT", 6, 0)
    row.text:SetWidth(200)
    row.text:SetWordWrap(false)

    row.remove = Button(row, "X", 24, function()
        table.remove(RAB.bars, row.index)
        RAB:BarsChanged()
    end)
    row.remove:SetPoint("RIGHT", 0, 0)
    row.edit = Button(row, L.EditBar, 70, function()
        Options:EditBar(row.index)
    end)
    row.edit:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
    row.down = Button(row, "v", 24, function()
        MoveBar(row.index, 1)
    end)
    row.down:SetPoint("RIGHT", row.edit, "LEFT", -2, 0)
    row.up = Button(row, "^", 24, function()
        MoveBar(row.index, -1)
    end)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
    return row
end

function Options:RefreshBarList()
    if not self.listContent then
        return
    end
    for i, bar in ipairs(RAB.bars) do
        local row = self.rows[i] or CreateRow(self.listContent, i)
        self.rows[i] = row
        row.index = i
        row.swatch:SetVertexColor(bar.color[1], bar.color[2], bar.color[3])
        local name = BarName(bar)
        local label = (bar.label and bar.label ~= "" and bar.label ~= name) and (bar.label .. "  |cff999999" .. name .. "|r")
            or name
        row.text:SetText(label)
        row.up:SetEnabled(i > 1)
        row.down:SetEnabled(i < #RAB.bars)
        row:Show()
    end
    for i = #RAB.bars + 1, #self.rows do
        self.rows[i]:Hide()
    end
    self.listContent:SetHeight(math.max(10, #RAB.bars * ROW_HEIGHT))
end

-- =================================================================
-- Bars page: the editor
-- =================================================================

local OUTPUTS = {
    { "RAID", "OutRaid" }, { "PARTY", "OutParty" }, { "SAY", "OutSay" }, { "GUILD", "OutGuild" },
    { "OFFICER", "OutOfficer" }, { "CONSOLE", "OutSelf" },
}

function Options:BuildEditor(page)
    local e = CreateFrame("Frame", nil, page)
    e:SetAllPoints()
    e:Hide()
    self.editor = e

    e.header = Label(e, L.EditBar, "GameFontNormalLarge")
    e.header:SetPoint("TOPLEFT", 0, -4)

    -- Buff
    local y = -36
    Label(e, L.BarBuff):SetPoint("TOPLEFT", 0, y)
    e.buff = Selector(e, 230, function(_, root)
        for _, category in ipairs(RAB.Categories) do
            local defs = {}
            for _, def in pairs(RAB.Buffs) do
                if def.category == category then
                    defs[#defs + 1] = def
                end
            end
            table.sort(defs, function(a, b)
                return a.name < b.name
            end)
            if #defs > 0 then
                local sub = root:CreateButton(category)
                sub:SetScrollMode(400)
                for _, def in ipairs(defs) do
                    sub:CreateRadio(def.name, function()
                        return Options.draft.buffKey == def.key
                    end, function()
                        Options.draft.buffKey = def.key
                        Options:RefreshEditor()
                    end)
                end
            end
        end
    end)
    e.buff:SetPoint("TOPLEFT", 110, y + 4)

    -- Custom aura name, only for custom bars
    y = y - 28
    e.customLabel = Label(e, L.BarCustomName, "GameFontHighlightSmall")
    e.customLabel:SetPoint("TOPLEFT", 0, y)
    e.custom = EditBox(e, 200)
    e.custom:SetPoint("TOPLEFT", 186, y + 3)
    e.custom:SetScript("OnTextChanged", function(self)
        Options.draft.custom = strtrim(self:GetText())
    end)

    -- Label and color
    y = y - 28
    Label(e, L.BarLabel):SetPoint("TOPLEFT", 0, y)
    e.label = EditBox(e, 180)
    e.label:SetPoint("TOPLEFT", 112, y + 3)
    e.label:SetScript("OnTextChanged", function(self)
        Options.draft.label = self:GetText()
    end)
    e.color = CreateFrame("Button", nil, e)
    e.color:SetSize(20, 20)
    e.color:SetPoint("LEFT", e.label, "RIGHT", 16, 0)
    e.color.tex = e.color:CreateTexture(nil, "ARTWORK")
    e.color.tex:SetAllPoints()
    e.color.tex:SetColorTexture(1, 1, 1)
    e.color:SetScript("OnClick", function()
        Options:PickColor()
    end)

    -- Groups
    y = y - 32
    Label(e, L.BarGroups):SetPoint("TOPLEFT", 0, y)
    e.groups = {}
    for g = 1, 8 do
        local cb = Checkbox(e, tostring(g), function(checked)
            Options.draftGroups[g] = checked
        end)
        cb:SetPoint("TOPLEFT", 70 + (g - 1) * 40, y + 5)
        e.groups[g] = cb
    end

    -- Classes
    y = y - 30
    Label(e, L.BarClasses):SetPoint("TOPLEFT", 0, y)
    e.classes = {}
    for i, token in ipairs(RAB.ClassOrder) do
        local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token
        local _, _, _, colorStr = Compat.ClassColor(token)
        local cb = Checkbox(e, "|c" .. colorStr .. name .. "|r", function(checked)
            Options.draftClasses[token] = checked
        end)
        local col, line = (i - 1) % 3, math.floor((i - 1) / 3)
        cb:SetPoint("TOPLEFT", 70 + col * 110, y + 5 - line * 24)
        e.classes[token] = cb
    end

    -- Flags
    y = y - 82
    e.selfOnly = Checkbox(e, L.BarSelfOnly, function(checked)
        Options.draft.selfOnly = checked
    end)
    e.selfOnly:SetPoint("TOPLEFT", 0, y)
    e.castOnClick = Checkbox(e, L.BarCastOnClick, function(checked)
        Options.draft.castOnClick = checked
    end)
    e.castOnClick:SetPoint("TOPLEFT", 200, y)

    -- Excluded names
    y = y - 34
    Label(e, L.BarExclude, "GameFontHighlightSmall"):SetPoint("TOPLEFT", 0, y)
    e.exclude = EditBox(e, 390)
    e.exclude:SetPoint("TOPLEFT", 6, y - 14)

    -- Output
    y = y - 48
    Label(e, L.BarOutput):SetPoint("TOPLEFT", 0, y)
    e.output = Selector(e, 200, function(_, root)
        for _, info in ipairs(OUTPUTS) do
            root:CreateRadio(L[info[2]], function()
                return Options.draft.output == info[1]
            end, function()
                Options.draft.output = info[1]
                Options:RefreshEditor()
            end)
        end
    end)
    e.output:SetPoint("TOPLEFT", 170, y + 4)

    -- Buttons
    e.save = Button(e, L.Save, 90, function()
        Options:SaveDraft()
    end)
    e.save:SetPoint("BOTTOMLEFT", 0, 4)
    e.cancel = Button(e, L.Cancel, 90, function()
        Options:CloseEditor()
    end)
    e.cancel:SetPoint("LEFT", e.save, "RIGHT", 6, 0)
    e.remove = Button(e, L.RemoveBar, 90, function()
        if Options.editIndex then
            table.remove(RAB.bars, Options.editIndex)
            Options:CloseEditor()
            RAB:BarsChanged()
        end
    end)
    e.remove:SetPoint("BOTTOMRIGHT", 0, 4)
end

-- Opens the editor on a bar (index) or on a new one (nil)
function Options:EditBar(index)
    local source = index and RAB.bars[index]
    if index and not source then
        return
    end
    self.editIndex = index
    self.draft = source and CopyTable(source) or {
        buffKey = nil, label = "", color = { 0.5, 0.5, 0.5 }, groups = "", classes = "", castOnClick = true,
        output = "RAID", exclude = {},
    }
    self.draftGroups, self.draftClasses = {}, {}
    for g = 1, 8 do
        self.draftGroups[g] = self.draft.groups == "" or self.draft.groups:find(tostring(g), 1, true) ~= nil
    end
    for _, token in ipairs(RAB.ClassOrder) do
        local letter = RAB.ClassLetters[token]
        self.draftClasses[token] = self.draft.classes == "" or self.draft.classes:find(letter, 1, true) ~= nil
    end

    local e = self.editor
    e.header:SetText(index and L.EditBar or L.NewBar)
    e.label:SetText(self.draft.label or "")
    e.custom:SetText(self.draft.custom or "")
    e.exclude:SetText(table.concat(self.draft.exclude or {}, ", "))
    e.remove:SetShown(index ~= nil)
    self.list:Hide()
    e:Show()
    self:RefreshEditor()
end

function Options:RefreshEditor()
    local e, d = self.editor, self.draft
    if not d then
        return
    end
    local def = d.buffKey and RAB.Buffs[d.buffKey]
    e.buff:SetText(def and def.name or L.ChooseBuff)
    local custom = d.buffKey == "custom"
    e.customLabel:SetShown(custom)
    e.custom:SetShown(custom)
    e.color.tex:SetVertexColor(d.color[1], d.color[2], d.color[3])
    for g = 1, 8 do
        e.groups[g]:SetChecked(self.draftGroups[g])
    end
    for token, cb in pairs(e.classes) do
        cb:SetChecked(self.draftClasses[token])
    end
    e.selfOnly:SetChecked(d.selfOnly)
    e.castOnClick:SetChecked(d.castOnClick)
    local outputName = d.output
    for _, info in ipairs(OUTPUTS) do
        if info[1] == d.output then
            outputName = L[info[2]]
        end
    end
    e.output:SetText(outputName)
    e.save:SetEnabled(def ~= nil and (not custom or (d.custom or "") ~= ""))
end

function Options:PickColor()
    local d = self.draft
    local previous = { d.color[1], d.color[2], d.color[3] }
    local function apply(r, g, b)
        d.color = { r, g, b }
        Options:RefreshEditor()
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        r = d.color[1], g = d.color[2], b = d.color[3],
        hasOpacity = false,
        swatchFunc = function()
            apply(ColorPickerFrame:GetColorRGB())
        end,
        cancelFunc = function()
            apply(previous[1], previous[2], previous[3])
        end,
    })
end

function Options:SaveDraft()
    local d = self.draft
    if not d or not d.buffKey then
        return
    end
    -- Every group or class ticked means no filter
    local groups = ""
    for g = 1, 8 do
        if self.draftGroups[g] then
            groups = groups .. g
        end
    end
    d.groups = (groups == "12345678") and "" or groups
    local classes, all = "", true
    for _, token in ipairs(RAB.ClassOrder) do
        if self.draftClasses[token] then
            classes = classes .. RAB.ClassLetters[token]
        else
            all = false
        end
    end
    d.classes = all and "" or classes
    d.exclude = {}
    for name in self.editor.exclude:GetText():gmatch("[^,]+") do
        name = strtrim(name)
        if name ~= "" then
            d.exclude[#d.exclude + 1] = name
        end
    end
    if d.label == "" then
        d.label = nil
    end
    if d.buffKey ~= "custom" then
        d.custom = nil
    end

    if self.editIndex then
        RAB.bars[self.editIndex] = d
    else
        table.insert(RAB.bars, d)
    end
    self:CloseEditor()
    RAB:BarsChanged()
end

function Options:CloseEditor()
    self.draft = nil
    self.editIndex = nil
    self.editor:Hide()
    self.list:Show()
    self:RefreshBarList()
end

-- =================================================================
-- Settings page
-- =================================================================

local function SettingChanged(key)
    if key == "showSolo" or key == "showParty" or key == "showRaid" or key == "hideInCombat" then
        RAB.UI:UpdateVisibility()
    elseif key == "interval" then
        RAB:StartTicker()
    elseif key == "scale" or key == "width" or key == "hideComplete" then
        RAB:OutOfCombat("layout", function()
            RAB.UI.completeSignature = nil
            RAB.UI:Layout()
        end)
    end
    RAB:RequestRefresh()
end

function Options:BuildSettingsPage(page)
    self.settingRefreshers = {}
    local checks = {
        { "showSolo", L.SetShowSolo }, { "showParty", L.SetShowParty }, { "showRaid", L.SetShowRaid },
        { "hideInCombat", L.SetHideInCombat }, { "hideComplete", L.SetHideComplete }, { "locked", L.SetLocked },
        { "groupDefault", L.SetGroupDefault }, { "announce", L.SetAnnounce }, { "skipPvP", L.SetSkipPvP },
    }
    local y = -4
    for _, info in ipairs(checks) do
        local key = info[1]
        local cb = Checkbox(page, info[2], function(checked)
            RAB.settings[key] = checked
            SettingChanged(key)
        end)
        cb:SetPoint("TOPLEFT", 0, y)
        table.insert(self.settingRefreshers, function()
            cb:SetChecked(RAB.settings[key])
        end)
        y = y - 26
    end

    local sliders = {
        { "scale", L.SetScale .. ": %.2f", 0.5, 2, 0.05, "%.1f" },
        { "width", L.SetWidth .. ": %d", 100, 300, 10, "%d" },
        { "interval", L.SetInterval, 0.5, 3, 0.5, "%.1f" },
    }
    y = y - 20
    for _, info in ipairs(sliders) do
        local key = info[1]
        local s = Slider(page, info[2], info[3], info[4], info[5], info[6], function()
            return RAB.settings[key]
        end, function(value)
            RAB.settings[key] = value
            SettingChanged(key)
        end)
        s:SetPoint("TOPLEFT", 12, y)
        table.insert(self.settingRefreshers, s.refresh)
        y = y - 46
    end
end

-- =================================================================
-- Profiles page
-- =================================================================

StaticPopupDialogs["RABUFFS_DELETE_PROFILE"] = {
    text = L.ProfileDeleteConfirm,
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data)
        RAB:DeleteProfile(data)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function Options:BuildProfilesPage(page)
    self.profileLabel = Label(page, "")
    self.profileLabel:SetPoint("TOPLEFT", 0, -6)

    self.profileSelect = Selector(page, 200, function(_, root)
        for _, name in ipairs(RAB:ProfileNames()) do
            root:CreateRadio(name, function()
                return name == Options.selectedProfile
            end, function()
                Options.selectedProfile = name
                Options:RefreshProfiles()
            end)
        end
    end)
    self.profileSelect:SetPoint("TOPLEFT", 0, -30)

    local load = Button(page, L.MenuProfileLoad, 80, function()
        if Options.selectedProfile then
            RAB:LoadProfile(Options.selectedProfile)
            Options:RefreshProfiles()
        end
    end)
    load:SetPoint("LEFT", self.profileSelect, "RIGHT", 6, 0)
    local delete = Button(page, L.ProfilesDelete, 80, function()
        if Options.selectedProfile then
            StaticPopup_Show("RABUFFS_DELETE_PROFILE", Options.selectedProfile, nil, Options.selectedProfile)
        end
    end)
    delete:SetPoint("LEFT", load, "RIGHT", 6, 0)

    local saveAs = Button(page, L.ProfilesSaveAs, 200, function()
        RAB.Menu.AskProfileName(function(name)
            RAB:SaveProfileAs(name)
            Options:RefreshProfiles()
        end)
    end)
    saveAs:SetPoint("TOPLEFT", 0, -60)

    local hint = Label(page, L.ProfilesExportHint .. "\n" .. L.ProfilesImportHint, "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 0, -98)
    hint:SetWidth(WIDTH - 40)

    self.io = TextArea(page, "RABuffsOptionsProfileText", WIDTH - 30, 230)
    self.io:SetPoint("TOPLEFT", 0, -130)

    local export = Button(page, L.ProfilesExport, 100, function()
        local eb = Options.io.editBox
        eb:SetText(RAB:ExportProfile())
        eb:HighlightText()
        eb:SetFocus()
    end)
    export:SetPoint("BOTTOMLEFT", 0, 4)
    local import = Button(page, L.ProfilesImport, 100, function()
        local text = Options.io.editBox:GetText()
        RAB.Menu.AskProfileName(function(name)
            RAB:ImportProfile(name, text)
            Options:RefreshProfiles()
        end)
    end)
    import:SetPoint("LEFT", export, "RIGHT", 6, 0)
end

function Options:RefreshProfiles()
    if not self.profileLabel then
        return
    end
    if not self.selectedProfile or not RAB.db.profiles[self.selectedProfile] then
        self.selectedProfile = RAB.profileName
    end
    self.profileLabel:SetText(string.format(L.ProfilesCurrent, RAB.profileName))
    self.profileSelect:SetText(self.selectedProfile or "")
end

-- =================================================================
-- A page in the game's AddOns settings that opens this window
-- =================================================================

RAB:On("PLAYER_LOGIN", function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end
    local panel = CreateFrame("Frame")
    local title = Label(panel, L.AddonName, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    local open = Button(panel, L.MenuOptions, 160, function()
        if SettingsPanel then
            HideUIPanel(SettingsPanel)
        end
        Options:Open()
    end)
    open:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    pcall(function()
        local category = Settings.RegisterCanvasLayoutCategory(panel, L.AddonName)
        Settings.RegisterAddOnCategory(category)
    end)
end)
