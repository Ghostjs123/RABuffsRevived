-- RABuffs scenarios, run by run_tests.py. Each test starts from a fresh fake game (mock.lua).
Tests = {}

function TestNames()
    local names = {}
    for name in pairs(Tests) do
        names[#names + 1] = name
    end
    return names
end

function RunTest(name)
    local ok, err = xpcall(Tests[name], debug.traceback)
    return ok, err
end

-- =================================================================
-- Helpers
-- =================================================================

function LoadAddon()
    local ns = {}
    for _, file in ipairs(ADDON_SOURCES) do
        local chunk, err = loadstring(file.source, "@" .. file.name)
        if not chunk then
            error(err)
        end
        chunk("RABuffs", ns)
    end
    return ns
end

local nextGuid = 0
function Member(name, class, group, buffs, extra)
    nextGuid = nextGuid + 1
    local u = { name = name, class = class, group = group or 1, guid = "Player-" .. nextGuid, buffs = buffs or {},
        debuffs = {} }
    for k, v in pairs(extra or {}) do
        u[k] = v
    end
    return u
end

-- The first member is the player
function SetupRaid(list)
    world.raid = true
    world.units = {}
    for i, u in ipairs(list) do
        world.units["raid" .. i] = u
    end
    world.units.player = list[1]
end

function SetupParty(list)
    world.raid = false
    world.units = { player = list[1] }
    for i = 2, #list do
        world.units["party" .. (i - 1)] = list[i]
    end
end

function Boot(opts)
    opts = opts or {}
    world.forever = opts.forever or false
    if not world.units.player then
        SetupParty({ Member("Me", opts.class or "PRIEST") })
    end
    for name, id in pairs(opts.spells or {}) do
        world.knownSpells[name] = id
    end
    for id, count in pairs(opts.items or {}) do
        world.items[id] = count
    end
    RAB = LoadAddon()
    Fire("ADDON_LOADED", "RABuffs")
    Fire("PLAYER_LOGIN")
    Fire("PLAYER_ENTERING_WORLD")
    Advance(1)
    return RAB
end

-- Makes the current profile exactly these bars
function SetBars(bars)
    wipe(RAB.bars)
    for _, bar in ipairs(bars) do
        bar.groups = bar.groups or ""
        bar.classes = bar.classes or ""
        bar.color = bar.color or { 1, 1, 1 }
        if bar.castOnClick == nil then
            bar.castOnClick = true
        end
        bar.output = bar.output or "RAID"
        bar.exclude = bar.exclude or {}
        table.insert(RAB.bars, bar)
    end
    RAB:BarsChanged()
    Advance(1)
end

function Bar(i)
    return _G["RABuffsBar" .. i]
end

function Eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
    end
end

function True(value, what)
    if not value then
        error((what or "condition") .. " was false", 2)
    end
end

-- Without color codes, as the player reads it
function Plain(text)
    return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function Contains(list, pattern, what)
    for _, line in ipairs(list) do
        if Plain(line):find(pattern, 1, true) then
            return line
        end
    end
    error(string.format("%s: no line contains '%s'. Lines:\n  %s", what or "list", pattern,
        table.concat((function()
            local out = {}
            for _, l in ipairs(list) do
                out[#out + 1] = tostring(l)
            end
            return out
        end)(), "\n  ")), 2)
end

function NoErrors()
    -- Blocked actions in the mock raise Lua errors, which would have failed the test already
    for _, line in ipairs(world.printed) do
        if line:find("Error", 1, true) then
            error("printed an error: " .. line, 2)
        end
    end
end

local PRIEST_SPELLS = { ["Power Word: Fortitude"] = 1243, ["Prayer of Fortitude"] = 21562, ["Resurrection"] = 2006 }

-- A raid of ten: groups 1 and 2. Group 2 has nobody with Fortitude.
local function FortitudeRaid()
    local pwf = function() return { Aura("Power Word: Fortitude", 10938, 1500) } end
    SetupRaid({
        Member("Me", "PRIEST", 1, pwf()),
        Member("Tanky", "WARRIOR", 1, pwf()),
        Member("Stabby", "ROGUE", 1, {}),
        Member("Frosty", "MAGE", 1, pwf()),
        Member("Leafy", "DRUID", 1, pwf()),
        Member("Holy", "PALADIN", 2, {}),
        Member("Shady", "WARLOCK", 2, {}),
        Member("Bow", "HUNTER", 2, {}),
        Member("Shouty", "WARRIOR", 2, {}),
        Member("Sparky", "MAGE", 2, {}),
    })
end

-- =================================================================
-- Loading
-- =================================================================

function Tests.loads_with_class_defaults()
    Boot({ class = "PRIEST" })
    True(RABuffsDB.profiles["Priest"], "Priest profile")
    Eq(RAB.profileName, "Priest", "profile")
    Eq(#RAB.bars, 4, "default bars")
    Eq(RAB.bars[3].buffKey, "pwf", "third bar")
    True(RABuffsFrame, "window")
    True(Bar(4), "fourth bar button")
    Contains(world.printed, "RABuffs 1.0.0-test loaded")
    local driver = world.stateDrivers[RABuffsFrame]
    Eq(driver.state, "visibility", "driver")
    Eq(driver.condition, "[group:raid] show; [group:party] show; show", "visibility condition")
end

function Tests.loads_on_forever_without_unknown_events()
    world.unknownEvents = { ADDON_RESTRICTION_STATE_CHANGED = true, UNIT_AURA_BLOCKED = true,
        UNIT_AURA_BLOCK_LIST_CLEARED = true, MODIFIER_STATE_CHANGED = true }
    Boot({ forever = true, class = "MAGE" })
    True(RAB.Compat.isForever, "detected Forever")
    Eq(RAB.bars[3].buffKey, "ai", "mage default")
end

function Tests.second_class_gets_its_own_profile()
    Boot({ class = "DRUID" })
    Eq(RAB.profileName, "Druid", "profile")
    Eq(RAB.bars[3].buffKey, "motw", "druid bar")
end

-- =================================================================
-- Counting and tooltips
-- =================================================================

function Tests.counts_who_has_fortitude()
    FortitudeRaid()
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf" } })
    Eq(Bar(1).count.text, "4/10", "count")

    Bar(1).mouseOver = true
    Bar(1).scripts.OnEnter(Bar(1))
    Contains(GameTooltip.lines, "Missing Fortitude:")
    Contains(GameTooltip.lines, "Stabby")
    Contains(GameTooltip.lines, "Holy, Shady, Bow, Shouty")
end

function Tests.shift_shows_who_has_it()
    FortitudeRaid()
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf" } })
    world.modifiers.shift = true
    Bar(1).scripts.OnEnter(Bar(1))
    Contains(GameTooltip.lines, "Has Fortitude:")
    Contains(GameTooltip.lines, "Me, Tanky, Frosty, Leafy")
end

function Tests.fading_buffs_show_as_fading()
    SetupParty({
        Member("Me", "PRIEST", 1, { Aura("Power Word: Fortitude", 10938, 1500) }),
        Member("Pal", "MAGE", 1, { Aura("Power Word: Fortitude", 10938, 120) }),
    })
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf" } })
    Eq(Bar(1).count.text, "2/2", "count")
    Eq(RAB.UI.results[1].fading, 1, "fading")
    -- The click refreshes the one about to run out
    local action = Click(Bar(1))
    Eq(action.unit, "party1", "refresh target")
end

function Tests.excluded_names_and_class_filters()
    FortitudeRaid()
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf", classes = "wm", exclude = { "shouty" } } })
    -- Warriors and mages, minus Shouty: Tanky, Frosty (have) and Sparky (missing)
    Eq(Bar(1).count.text, "2/3", "count")
end

function Tests.group_filter()
    FortitudeRaid()
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf", groups = "2" } })
    Eq(Bar(1).count.text, "0/5", "count")
end

function Tests.health_is_unavailable_on_forever()
    SetupParty({ Member("Me", "PRIEST"), Member("Pal", "MAGE") })
    Boot({ forever = true })
    SetBars({ { buffKey = "health" } })
    Eq(Bar(1).count.text, "?", "health")
end

function Tests.health_on_classic()
    SetupParty({ Member("Me", "PRIEST", 1, {}, { health = 50 }), Member("Pal", "MAGE", 1, {}, { health = 100 }) })
    Boot()
    SetBars({ { buffKey = "health" } })
    Eq(Bar(1).count.text, "75%", "health")
end

function Tests.dispel_bar_counts_my_types()
    SetupParty({ Member("Me", "PRIEST"), Member("Pal", "MAGE"), Member("Bud", "ROGUE") })
    world.units.party1.debuffs = { Aura("Shadow Word: Pain", 10894, 10, { dispelName = "Magic" }) }
    world.units.party2.debuffs = { Aura("Curse of Agony", 11713, 10, { dispelName = "Curse" }) }
    Boot({ class = "PRIEST" })
    SetBars({ { buffKey = "dremove" }, { buffKey = "dcurse" } })
    Eq(Bar(1).count.text, "1/3", "priest can remove the magic one")
    Eq(Bar(2).count.text, "1/3", "curses")
end

function Tests.custom_aura_bar()
    SetupParty({
        Member("Me", "WARRIOR", 1, { Aura("Rallying Cry of the Dragonslayer", 22888, 3000) }),
        Member("Pal", "MAGE"),
    })
    Boot({ class = "WARRIOR" })
    SetBars({ { buffKey = "custom", custom = "Rallying Cry of the Dragonslayer" }, { buffKey = "custom", custom = "22888" } })
    Eq(Bar(1).count.text, "1/2", "by name")
    Eq(Bar(2).count.text, "1/2", "by spell ID")
end

function Tests.potion_and_priest_shadow_protection_are_told_apart()
    SetupParty({
        Member("Me", "PRIEST", 1, { Aura("Shadow Protection", 10958, 500) }),
        Member("Pal", "MAGE", 1, { Aura("Shadow Protection", 17548, 500) }),
    })
    Boot({ class = "PRIEST" })
    SetBars({ { buffKey = "sprot" }, { buffKey = "gspp" } })
    Eq(Bar(1).count.text, "1/2", "priest buff")
    Eq(Bar(2).count.text, "1/2", "potion")
end

-- =================================================================
-- Click to buff
-- =================================================================

function Tests.click_casts_on_the_best_unbuffed()
    FortitudeRaid()
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS, items = { [17029] = 5 } })
    SetBars({ { buffKey = "pwf" } })
    local action = Click(Bar(1))
    Eq(action.type, "spell", "type")
    Eq(action.spell, "Power Word: Fortitude", "spell")
    -- The player's own group comes first in a raid: Stabby is the one in group 1 without it
    Eq(action.unit, "raid3", "target")
end

function Tests.alt_click_casts_the_group_buff_on_the_neediest_group()
    FortitudeRaid()
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS, items = { [17029] = 5 } })
    SetBars({ { buffKey = "pwf" } })
    world.modifiers.alt = true
    local action = Click(Bar(1))
    Eq(action.spell, "Prayer of Fortitude", "spell")
    Eq(UnitData(action.unit).group, 2, "group 2 needs it most")
end

function Tests.no_reagents_no_group_buff()
    FortitudeRaid()
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf" } })
    world.modifiers.alt = true
    Eq(Click(Bar(1)).spell, "Power Word: Fortitude", "falls back to single")
    Bar(1).scripts.OnEnter(Bar(1))
    Contains(GameTooltip.lines, "No reagents for Prayer of Fortitude")
end

function Tests.group_default_setting_swaps_clicks()
    FortitudeRaid()
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS, items = { [17029] = 5 } })
    RAB.settings.groupDefault = true
    SetBars({ { buffKey = "pwf" } })
    Eq(Click(Bar(1)).spell, "Prayer of Fortitude", "plain click")
    world.modifiers.alt = true
    Eq(Click(Bar(1)).spell, "Power Word: Fortitude", "alt click")
end

function Tests.ctrl_click_reports_instead_of_casting()
    FortitudeRaid()
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf" } })
    world.modifiers.ctrl = true
    Eq(Click(Bar(1)), nil, "no secure action")
    local sent = world.chat[1]
    Eq(sent.chatType, "RAID", "channel")
    True(sent.message:find("^<Buffs> Missing Fortitude: %[6 / 10%]"), "message: " .. sent.message)
    True(sent.message:find("Group 2 [5]", 1, true), "whole group named: " .. sent.message)
    True(sent.message:find("Stabby [Rogue; G1]", 1, true), "single name: " .. sent.message)
end

function Tests.next_click_moves_on_after_a_cast()
    FortitudeRaid()
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf" } })
    local first = Click(Bar(1))
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player")
    Advance(0.5)
    local second = Click(Bar(1))
    True(first.unit ~= second.unit, "second click picks someone else (" .. first.unit .. ")")
    Contains(world.printed, "Casting Power Word: Fortitude on")
end

function Tests.out_of_range_people_are_skipped()
    SetupParty({ Member("Me", "PRIEST", 1, { Aura("Power Word: Fortitude", 1, 1500) }),
        Member("Far", "MAGE", 1, {}, { inRange = false }), Member("Near", "ROGUE") })
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf" } })
    Eq(Click(Bar(1)).unit, "party2", "near one")
    Bar(1).scripts.OnEnter(Bar(1))
    Contains(GameTooltip.lines, "1 out of range")
end

function Tests.pvp_flagged_skipped_when_unflagged()
    SetupParty({ Member("Me", "PRIEST", 1, { Aura("Power Word: Fortitude", 1, 1500) }),
        Member("Flagged", "MAGE", 1, {}, { pvp = true }) })
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf" } })
    Eq(Click(Bar(1)), nil, "no target")
end

function Tests.non_casters_click_prints_the_report()
    FortitudeRaid()
    world.units.raid1.class = "WARRIOR"
    Boot({ class = "WARRIOR" })
    SetBars({ { buffKey = "pwf" } })
    Eq(Click(Bar(1)), nil, "nothing to cast")
    Eq(#world.chat, 0, "nothing sent to chat")
    Contains(world.printed, "Missing Fortitude")
end

function Tests.self_buff_cast_on_yourself()
    SetupParty({ Member("Me", "PRIEST"), Member("Other", "PRIEST") })
    Boot({ class = "PRIEST", spells = { ["Inner Fire"] = 10951 } })
    SetBars({ { buffKey = "innerfire" } })
    Eq(Bar(1).count.text, "0/2", "both priests checked")
    local action = Click(Bar(1))
    Eq(action.spell, "Inner Fire", "spell")
    Eq(action.unit, "player", "on me")
end

function Tests.paladin_greater_blessing_by_class()
    SetupRaid({
        Member("Me", "PALADIN", 1), Member("A", "WARRIOR", 1), Member("B", "WARRIOR", 2),
        Member("C", "WARRIOR", 3), Member("D", "MAGE", 1),
    })
    Boot({ class = "PALADIN", spells = { ["Blessing of Kings"] = 20217, ["Greater Blessing of Kings"] = 25898 },
        items = { [21177] = 20 } })
    SetBars({ { buffKey = "bok" } })
    world.modifiers.alt = true
    local action = Click(Bar(1))
    Eq(action.spell, "Greater Blessing of Kings", "spell")
    Eq(UnitData(action.unit).class, "WARRIOR", "warriors are the biggest class")
end

function Tests.salvation_skips_main_tanks()
    SetupRaid({ Member("Me", "PALADIN", 1), Member("Tank", "WARRIOR", 1, {}, { role = "MAINTANK" }),
        Member("Dps", "WARRIOR", 1) })
    Boot({ class = "PALADIN" })
    SetBars({ { buffKey = "bos" } })
    Eq(Bar(1).count.text, "0/2", "tank not counted")
end

function Tests.rogue_poison_goes_on_the_weapon()
    Boot({ class = "ROGUE", items = { [8928] = 3, [20844] = 2 } })
    world.weapons[16], world.weapons[17] = 1001, 1002
    Fire("UNIT_INVENTORY_CHANGED", "player")
    Advance(1)
    Eq(RAB.bars[3].buffKey, "instantpoison", "rogue default")
    Eq(Bar(3).count.text, "0/1", "not coated")
    local action = Click(Bar(3))
    Eq(action.type, "item", "type")
    Eq(action.item, "item:8928", "item")
    Eq(action.slot, 16, "main hand")
    local off = Click(Bar(4))
    Eq(off.slot, 17, "off hand")

    world.enchants[16] = 1200
    Fire("UNIT_INVENTORY_CHANGED", "player")
    Advance(1)
    Eq(Bar(3).count.text, "1/1", "coated")
    Eq(Click(Bar(3)), nil, "nothing to do")
end

function Tests.no_weapon_no_action()
    Boot({ class = "ROGUE", items = { [8928] = 3 } })
    Eq(Bar(3).count.text, "-", "no weapon")
    Eq(Click(Bar(3)), nil, "no action")
end

function Tests.flask_uses_the_item_on_yourself()
    SetupParty({ Member("Me", "WARRIOR"), Member("Pal", "WARRIOR", 1, { Aura("Flask of the Titans", 17626, 7000) }) })
    Boot({ class = "WARRIOR", items = { [13510] = 1 } })
    SetBars({ { buffKey = "titans" } })
    Eq(Bar(1).count.text, "1/2", "count")
    local action = Click(Bar(1))
    Eq(action.item, "item:13510", "item")
    Eq(action.unit, "player", "on me")
end

function Tests.resurrect_the_healer_first()
    SetupRaid({
        Member("Me", "PRIEST", 1), Member("Dead Warrior", "WARRIOR", 1, {}, { dead = true }),
        Member("Dead Priest", "PRIEST", 2, {}, { dead = true }),
    })
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "alive" } })
    Eq(Bar(1).count.text, "1/3", "alive")
    local action = Click(Bar(1))
    Eq(action.spell, "Resurrection", "spell")
    Eq(action.unit, "raid3", "the priest")
end

function Tests.soulstone_goes_to_a_healer()
    SetupRaid({
        Member("Me", "WARLOCK", 1), Member("Heals", "PRIEST", 1), Member("Rogue", "ROGUE", 1),
    })
    Boot({ class = "WARLOCK", items = { [16896] = 1 } })
    SetBars({ { buffKey = "ss" } })
    local action = Click(Bar(1))
    Eq(action.item, "item:16896", "stone")
    Eq(action.unit, "raid2", "the priest")
end

function Tests.soulstone_made_when_you_have_none()
    Boot({ class = "WARLOCK", spells = { ["Create Soulstone (Major)"] = 20757 } })
    SetBars({ { buffKey = "ss" } })
    Eq(Click(Bar(1)).spell, "Create Soulstone (Major)", "makes one")
end

function Tests.click_cast_off()
    FortitudeRaid()
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf", castOnClick = false } })
    Eq(Click(Bar(1)), nil, "no action")
end

-- =================================================================
-- Combat and Forever's secrets
-- =================================================================

function Tests.combat_keeps_the_aim_and_never_touches_secure_frames()
    FortitudeRaid()
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf" } })
    local before = Click(Bar(1))
    world.combat = true
    Fire("PLAYER_REGEN_DISABLED")
    -- Stabby gets buffed mid-fight; the counts follow (Classic Era can read auras in combat) but the aim can't
    world.units.raid3.buffs = { Aura("Power Word: Fortitude", 10938, 1800) }
    Fire("UNIT_AURA", "raid3")
    Advance(3)
    Eq(Bar(1).count.text, "5/10", "count updated in combat")
    Eq(Click(Bar(1)).unit, before.unit, "aim unchanged in combat")
    Bar(1).scripts.OnEnter(Bar(1))
    Contains(GameTooltip.lines, "keeps the target it had")

    world.combat = false
    Fire("PLAYER_REGEN_ENABLED")
    Advance(1)
    True(Click(Bar(1)).unit ~= "raid3", "re-aimed after combat")
end

function Tests.forever_combat_shows_the_last_reading()
    FortitudeRaid()
    Boot({ forever = true, class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf" } })
    Eq(Bar(1).count.text, "4/10", "before combat")

    world.combat = true
    world.aurasSecret = true
    Fire("PLAYER_REGEN_DISABLED")
    Fire("ADDON_RESTRICTION_STATE_CHANGED")
    world.units.raid3.buffs = { Aura("Power Word: Fortitude", 10938, 1800) }
    Fire("UNIT_AURA", "raid3")
    Advance(5)
    Eq(Bar(1).count.text, "4/10", "kept the pre-combat reading")
    Eq(Bar(1).count.textColor[1], 0.6, "greyed out")
    Bar(1).scripts.OnEnter(Bar(1))
    Contains(GameTooltip.lines, "showing what was seen before")

    world.combat = false
    world.aurasSecret = false
    Fire("ADDON_RESTRICTION_STATE_CHANGED")
    Fire("PLAYER_REGEN_ENABLED")
    Advance(1)
    Eq(Bar(1).count.text, "5/10", "read again after combat")
    Eq(Bar(1).count.textColor[1], 1, "white again")
end

function Tests.forever_join_in_combat_is_unknown_not_missing()
    SetupParty({ Member("Me", "PRIEST", 1, { Aura("Power Word: Fortitude", 1, 1500) }) })
    Boot({ forever = true, class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf" } })
    world.combat = true
    world.aurasSecret = true
    world.units.party1 = Member("Late", "MAGE", 1, { Aura("Power Word: Fortitude", 1, 1500) })
    Fire("GROUP_ROSTER_UPDATE")
    Advance(2)
    Eq(Bar(1).count.text, "1/2?", "late joiner unknown")
end

function Tests.forever_secret_aura_makes_the_unit_unknown()
    SetupParty({ Member("Me", "PRIEST", 1, { Aura("Power Word: Fortitude", 1, 1500) }), Member("Pal", "MAGE") })
    world.units.party1.buffs = { Aura(SECRET, SECRET, 100) }
    Boot({ forever = true, class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf" } })
    Eq(Bar(1).count.text, "1/2?", "can't tell")
    Eq(Click(Bar(1)), nil, "no click on an unknown")
end

function Tests.forever_secret_table_aura()
    SetupParty({ Member("Me", "PRIEST", 1, { SECRET }) })
    Boot({ forever = true, class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf" } })
    Eq(Bar(1).count.text, "0/1?", "unknown")
end

function Tests.forever_secret_range_lets_the_click_try()
    SetupParty({ Member("Me", "PRIEST", 1, { Aura("Power Word: Fortitude", 1, 1500) }),
        Member("Pal", "MAGE", 1, {}, { inRange = SECRET }) })
    Boot({ forever = true, class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf" } })
    Eq(Click(Bar(1)).unit, "party1", "aimed anyway")
end

function Tests.forever_secret_afk_counts_as_present()
    SetupParty({ Member("Me", "PRIEST"), Member("Pal", "MAGE", 1, {}, { afk = SECRET }) })
    Boot({ forever = true })
    SetBars({ { buffKey = "here" } })
    Eq(Bar(1).count.text, "2/2", "present")
end

function Tests.forever_secret_unit_comparison_in_a_raid()
    FortitudeRaid()
    world.unitCompareSecret = true
    Boot({ forever = true, class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf" } })
    Eq(Bar(1).count.text, "4/10", "count")
    Eq(Click(Bar(1)).unit, "raid3", "own group still found by GUID")
end

function Tests.reload_in_combat_builds_the_bars_afterwards()
    FortitudeRaid()
    world.combat = true
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    Eq(Bar(1), nil, "no secure buttons made in combat")
    world.combat = false
    Fire("PLAYER_REGEN_ENABLED")
    Advance(1)
    True(Bar(1) and Bar(1).shown, "made after combat")
    True(world.stateDrivers[RABuffsFrame], "visibility driver set after combat")
    Eq(Bar(3).count.text, "4/10", "counting")
end

function Tests.hide_in_combat_uses_the_state_driver()
    Boot()
    RAB.settings.hideInCombat = true
    RAB.UI:UpdateVisibility()
    Eq(world.stateDrivers[RABuffsFrame].condition,
        "[combat] hide; [group:raid] show; [group:party] show; show", "condition")
end

function Tests.editing_bars_in_combat_waits()
    FortitudeRaid()
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    world.combat = true
    Fire("PLAYER_REGEN_DISABLED")
    local count = #RAB.bars
    RAB.Options:Open("bars")
    RAB.Options:EditBar(nil)
    RAB.Options.draft.buffKey = "sprot"
    RAB.Options:SaveDraft()
    Advance(2)
    Eq(#RAB.bars, count + 1, "bar saved")
    Eq(Bar(count + 1), nil, "button waits for combat to end")
    world.combat = false
    Fire("PLAYER_REGEN_ENABLED")
    Advance(1)
    True(Bar(count + 1), "button made after combat")
    True(Bar(count + 1).shown, "and shown")
end

function Tests.chat_lockdown_prints_locally()
    FortitudeRaid()
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "pwf" } })
    world.chatLocked = true
    world.modifiers.ctrl = true
    Click(Bar(1))
    Eq(#world.chat, 0, "nothing sent")
    Contains(world.printed, "Chat is locked")
end

-- =================================================================
-- Layout
-- =================================================================

function Tests.hide_complete_bars()
    SetupParty({ Member("Me", "PRIEST", 1, { Aura("Power Word: Fortitude", 1, 1500) }), Member("Pal", "MAGE") })
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    RAB.settings.hideComplete = true
    SetBars({ { buffKey = "alive" }, { buffKey = "pwf" } })
    True(Bar(1).shown, "alive bar is never 'complete'")
    True(Bar(2).shown, "fortitude incomplete")
    world.units.party1.buffs = { Aura("Power Word: Fortitude", 1, 1500) }
    Fire("UNIT_AURA", "party1")
    Advance(1)
    Eq(Bar(2).shown, false, "hidden when everyone has it")
end

function Tests.removed_bars_are_hidden_and_disarmed()
    FortitudeRaid()
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    SetBars({ { buffKey = "alive" }, { buffKey = "pwf" } })
    True(Click(Bar(2)), "armed")
    SetBars({ { buffKey = "alive" } })
    Eq(Bar(2).shown, false, "hidden")
    Eq(Click(Bar(2)), nil, "disarmed")
end

-- =================================================================
-- Commands, profiles, menus, options
-- =================================================================

function Tests.rabq_to_raid_with_filters()
    FortitudeRaid()
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS })
    -- Warriors and mages in groups 1 and 2: Tanky and Frosty (all of group 1's) have it, Shouty and Sparky don't
    SlashCmdList.RABUFFSQ("raid not pwf 12 wm")
    local sent = world.chat[1]
    Eq(sent.chatType, "RAID", "channel")
    Eq(sent.message, "<Buffs> [G12] [wm] Has Fortitude: [2 / 4] Group 1 [2].", "message")
    world.units.raid4.buffs = {}
    Fire("UNIT_AURA", "raid4")
    SlashCmdList.RABUFFSQ("raid not pwf 12 wm")
    Eq(world.chat[2].message, "<Buffs> [G12] [wm] Has Fortitude: [1 / 4] Tanky [Warrior; G1].", "one name")
    world.units.raid4.buffs = { Aura("Power Word: Fortitude", 10938, 1500) }
    Fire("UNIT_AURA", "raid4")
    SlashCmdList.RABUFFSQ("raid pwf 1 wm")
    Eq(world.chat[3].message, "<Buffs> [G1] [wm] Everyone has Fortitude.", "everyone")
end

function Tests.rabq_locally_and_bad_queries()
    FortitudeRaid()
    Boot({ class = "PRIEST" })
    SlashCmdList.RABUFFSQ("ai")
    Contains(world.printed, "Arcane Intellect")
    SlashCmdList.RABUFFSQ("nosuchbuff")
    Contains(world.printed, "Unknown buff 'nosuchbuff'")
    SlashCmdList.RABUFFSQ("pwf 12 xyz")
    Contains(world.printed, "Couldn't read that query")
    SlashCmdList.RABUFFSQ("selfpwf")
    Contains(world.printed, "Fortitude")
    SlashCmdList.RABUFFSQ("c raidbuffs pwf")
    Eq(world.chat[1].chatType, "CHANNEL", "channel")
    Eq(world.chat[1].target, 5, "channel number")
    SlashCmdList.RABUFFSQ("party pwf")
    Eq(world.chat[2].chatType, "PARTY", "raid counts as a group")
end

function Tests.show_command_works_solo_with_solo_off()
    Boot()
    RAB.settings.showSolo = false
    RAB.UI:UpdateVisibility()
    Eq(world.stateDrivers[RABuffsFrame].condition, "[group:raid] show; [group:party] show; hide", "hidden solo")
    SlashCmdList.RABUFFS("show")
    True(RAB.settings.showSolo, "solo turned on")
    Eq(world.stateDrivers[RABuffsFrame].condition, "[group:raid] show; [group:party] show; show", "shown")
    Contains(world.printed, "Show when solo")
end

function Tests.show_solo_toggles()
    Boot()
    SlashCmdList.RABUFFS("show solo")
    Eq(RAB.settings.showSolo, false, "off")
    Eq(world.stateDrivers[RABuffsFrame].condition, "[group:raid] show; [group:party] show; hide", "hidden solo")
    SlashCmdList.RABUFFS("show Solo")
    Eq(RAB.settings.showSolo, true, "on")
    Eq(world.stateDrivers[RABuffsFrame].condition, "[group:raid] show; [group:party] show; show", "shown solo")
end

function Tests.rab_commands()
    Boot()
    SlashCmdList.RABUFFS("")
    Contains(world.printed, "RABuffs commands")
    SlashCmdList.RABUFFS("hide")
    Eq(world.stateDrivers[RABuffsFrame].condition, "hide", "hidden")
    SlashCmdList.RABUFFS("show")
    True(world.stateDrivers[RABuffsFrame].condition ~= "hide", "shown")
    SlashCmdList.RABUFFS("buffs")
    Contains(world.printed, "Mage:")
    SlashCmdList.RABUFFS("info")
    SlashCmdList.RABUFFS("options")
    True(RABuffsOptions.shown, "options open")
    SlashCmdList.RABUFFS("reset")
    SlashCmdList.RABUFFS("lock")
    True(RAB.settings.locked, "locked")
end

function Tests.profiles_save_export_import()
    Boot({ class = "PRIEST" })
    RAB.bars[1].exclude = { "Some One", "Pipe|Name" }
    RAB.bars[1].label = "Alive, all of them"
    RAB:SaveProfileAs("Raid night")
    Eq(RAB.profileName, "Raid night", "switched")
    local text = RAB:ExportProfile()
    True(text:find("^RABuffs1\n"), "header")
    RAB:ImportProfile("Copy", text)
    Eq(RAB.profileName, "Copy", "imported")
    Eq(#RAB.bars, 4, "bars")
    Eq(RAB.bars[1].exclude[2], "Pipe|Name", "escaped name")
    Eq(RAB.bars[1].label, "Alive, all of them", "label with comma")
    Eq(RAB.bars[2].classes, "pdsa", "classes")

    True(not RAB:DeleteProfile("Copy"), "can't delete the current one")
    RAB:LoadProfile("Priest")
    True(RAB:DeleteProfile("Copy"), "deleted")
    True(not RAB:ImportProfile("Bad", "print('hi')"), "rejects other text")
end

function Tests.right_click_menu()
    Boot()
    Click(Bar(1), "RightButton")
    local menu = world.lastMenu
    True(menu, "menu opened")
    local options, profiles
    for _, child in ipairs(menu.children) do
        if child.text == "Options..." then
            options = child
        elseif child.text == "Profiles" then
            profiles = child
        end
    end
    True(options and profiles, "entries")
    Eq(profiles.children[1].text, "Priest", "profile listed")
    options.a()
    True(RABuffsOptions.shown, "opened options")
end

function Tests.options_editor_adds_and_edits_bars()
    Boot({ class = "DRUID" })
    local count = #RAB.bars
    RAB.Options:Open("bars")
    RAB.Options:EditBar(nil)
    RAB.Options.draft.buffKey = "ai"
    RAB.Options.editor.label:SetText("Int")
    RAB.Options.editor.label.scripts.OnTextChanged(RAB.Options.editor.label)
    RAB.Options.draftClasses.WARRIOR = false
    RAB.Options.draftGroups[8] = false
    RAB.Options.editor.exclude:SetText("Bob, Alice ")
    RAB.Options:SaveDraft()
    Advance(1)
    local bar = RAB.bars[count + 1]
    Eq(bar.buffKey, "ai", "buff")
    Eq(bar.label, "Int", "label")
    Eq(bar.groups, "1234567", "groups")
    Eq(bar.classes, "apsdrmlh", "classes")
    Eq(bar.exclude[2], "Alice", "exclude trimmed")
    Eq(Bar(count + 1).label.text, "Int", "shown")

    -- Every class and group ticked means no filter
    RAB.Options:EditBar(count + 1)
    RAB.Options.draftClasses.WARRIOR = true
    RAB.Options.draftGroups[8] = true
    RAB.Options:SaveDraft()
    Eq(RAB.bars[count + 1].classes, "", "no class filter")
    Eq(RAB.bars[count + 1].groups, "", "no group filter")

    -- The buff menu lists categories with their buffs
    RAB.Options:EditBar(1)
    RAB.Options.editor.buff.scripts.OnClick(RAB.Options.editor.buff)
    local mage
    for _, child in ipairs(world.lastMenu.children) do
        if child.text == "Mage" then
            mage = child
        end
    end
    True(mage and #mage.children > 3, "mage buffs listed")
end

function Tests.no_accidental_globals()
    local before = {}
    for k in pairs(_G) do
        before[k] = true
    end
    FortitudeRaid()
    Boot({ class = "PRIEST", spells = PRIEST_SPELLS, items = { [17029] = 5 } })
    RAB.Options:Open("bars")
    RAB.Options:ShowPage("settings")
    RAB.Options:ShowPage("profiles")
    Click(Bar(3))
    world.modifiers.ctrl = true
    Click(Bar(3))
    SlashCmdList.RABUFFSQ("pwf")
    local allowed = { RABuffs = true, RABuffsDB = true, RABuffsCharDB = true, RABuffsFrame = true,
        RABuffsOptions = true, SLASH_RABUFFS1 = true, SLASH_RABUFFS2 = true, SLASH_RABUFFSQ1 = true,
        SLASH_RABUFFSQ2 = true, RAB = true }
    local leaked = {}
    for k in pairs(_G) do
        if not before[k] and not allowed[k] and not tostring(k):find("^RABuffsBar%d+$")
            and not tostring(k):find("^RABuffsOptions") then
            leaked[#leaked + 1] = tostring(k)
        end
    end
    table.sort(leaked)
    Eq(table.concat(leaked, ", "), "", "new globals")
end

function Tests.options_settings_and_profiles_pages()
    Boot()
    RAB.Options:Open("settings")
    RAB.Options:ShowPage("profiles")
    RAB.Options:ShowPage("bars")
    RAB.settings.width = 200
    RAB.Options:ShowPage("settings")
end
