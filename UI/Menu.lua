-- RABuffs: The right-click menu on the window and its bars (Blizzard's MenuUtil, on both Classic Era and Forever).
local _, RAB = ...

local L = RAB.L

local Menu = {}
RAB.Menu = Menu

-- Asks for a profile name, then calls onAccept(name)
StaticPopupDialogs["RABUFFS_PROFILE_NAME"] = {
    text = L.ProfileNamePrompt,
    button1 = OKAY,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 32,
    OnAccept = function(dialog, data)
        data.onAccept(dialog:GetEditBox():GetText())
    end,
    EditBoxOnEnterPressed = function(editBox, data)
        data.onAccept(editBox:GetText())
        StaticPopup_Hide("RABUFFS_PROFILE_NAME")
    end,
    EditBoxOnEscapePressed = function()
        StaticPopup_Hide("RABUFFS_PROFILE_NAME")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function Menu.AskProfileName(onAccept)
    StaticPopup_Show("RABUFFS_PROFILE_NAME", nil, nil, { onAccept = onAccept })
end

-- Right-click menu; barIndex is set when it came from a bar
function Menu.Open(owner, barIndex)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L.MenuTitle)
        local bar = barIndex and RAB.bars[barIndex]
        if bar then
            root:CreateButton(L.MenuReport, function()
                RAB.Query.Output(bar, false)
            end)
            root:CreateButton(L.MenuEditBar, function()
                RAB.Options:Open("bars", barIndex)
            end)
            root:CreateDivider()
        end
        root:CreateButton(L.MenuOptions, function()
            RAB.Options:Open()
        end)
        root:CreateCheckbox(L.MenuLock, function()
            return RAB.settings.locked
        end, function()
            RAB.settings.locked = not RAB.settings.locked
        end)

        local profiles = root:CreateButton(L.MenuProfiles)
        for _, name in ipairs(RAB:ProfileNames()) do
            profiles:CreateRadio(name, function()
                return name == RAB.profileName
            end, function()
                RAB:LoadProfile(name)
            end)
        end
        profiles:CreateDivider()
        profiles:CreateButton(L.MenuProfileSaveAs, function()
            Menu.AskProfileName(function(name)
                RAB:SaveProfileAs(name)
            end)
        end)

        root:CreateDivider()
        root:CreateButton(L.MenuHide, function()
            RAB.UI:SetHidden(true)
        end)
    end)
end
