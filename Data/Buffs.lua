-- RABuffs: What can be checked. Each entry is a "buff key" usable in bars and /rabq.
--
-- match      auras that count as having it: a name, or { id = spellID, name = "..." } when several auras share
--            the name (the ID decides when it can be read, else the name), or { name = "...", notIds = {...} }
--            for a name that counts unless it's one of those spell IDs
-- kind       nil (a buff anyone can have), "self" (only members of `class` are checked), "aura" (a party-wide
--            aura or totem, cast without a target), "item" (a consumable, used on yourself), "weapon" (an oil,
--            stone or poison on `slot`), "debuff", "dispel" (debuffs of a dispel type) or "special" (`query`)
-- spell      the spell clicking casts (single target); groupSpell the group version, groupBy "group" (the
--            target's party) or "class" (the target's class in the raid), reagents the items groupSpell needs
-- recast     minutes left under which a buff counts as fading
-- invert     a bar about who has it (shields, Ice Block, debuffs) rather than who lacks it
-- ignoreClass class letters never checked (see RAB.ClassLetters); priority extra weight per class when
--            picking whom to buff; selfPriority the weight for yourself (default 5)
-- Turtle WoW's custom items and spells from the 2020s forks are left out: they don't exist on Blizzard's servers.
local _, RAB = ...

RAB.ClassLetters = {
    MAGE = "m", WARLOCK = "l", PRIEST = "p", ROGUE = "r", DRUID = "d",
    HUNTER = "h", SHAMAN = "s", WARRIOR = "w", PALADIN = "a",
}
RAB.LetterClasses = {}
for token, letter in pairs(RAB.ClassLetters) do
    RAB.LetterClasses[letter] = token
end
RAB.ClassOrder = { "WARRIOR", "PALADIN", "PRIEST", "SHAMAN", "DRUID", "ROGUE", "MAGE", "WARLOCK", "HUNTER" }

-- Menu order of the buff categories
RAB.Categories = {
    "Status", "Mage", "Priest", "Druid", "Paladin", "Shaman", "Warlock", "Hunter", "Warrior",
    "Flasks & Elixirs", "Protection Potions", "Utility", "Food & Drink", "World Buffs", "Weapon", "Poisons",
    "Debuffs", "Custom",
}

local CASTER_FIRST = { PRIEST = 0.5, DRUID = 0.5, PALADIN = 0.4, SHAMAN = 0.4, MAGE = 0.4, WARLOCK = 0.3 }

local B = {}
RAB.Buffs = B

-- Status -------------------------------------------------------------
B.alive = { name = "Alive", category = "Status", kind = "special", query = "alive", cast = "res",
    description = "Who is alive. Click to resurrect the dead, healers first." }
B.health = { name = "Health", category = "Status", kind = "special", query = "health",
    description = "Total health of the group. Forever hides health from addons, so there it stays blank." }
B.mana = { name = "Mana", category = "Status", kind = "special", query = "mana", ignoreClass = "rw",
    description = "Total mana of mana users." }
B.here = { name = "Present", category = "Status", kind = "special", query = "here",
    description = "Who is online, nearby and not AFK." }
B.incombat = { name = "In Combat", category = "Status", kind = "special", query = "incombat", invert = true,
    description = "Who is in combat." }
B.pvp = { name = "PvP Flagged", category = "Status", kind = "special", query = "pvp", invert = true,
    description = "Who is flagged for PvP." }
B.blank = { name = "Blank", category = "Status", kind = "special", query = "blank",
    description = "An empty bar, to use as a header." }
B.custom = { name = "Custom Aura", category = "Custom", kind = "custom",
    description = "Any buff by name or spell ID, for things RABuffs doesn't know yet." }

-- Mage ---------------------------------------------------------------
B.ai = { name = "Arcane Intellect", category = "Mage", match = { "Arcane Intellect", "Arcane Brilliance" },
    spell = "Arcane Intellect", groupSpell = "Arcane Brilliance", groupBy = "group", reagents = { 17020 },
    ignoreClass = "wr", priority = CASTER_FIRST, recast = 5 }
B.dampen = { name = "Dampen Magic", category = "Mage", match = { "Dampen Magic" }, spell = "Dampen Magic", recast = 3 }
B.amplify = { name = "Amplify Magic", category = "Mage", match = { "Amplify Magic" }, spell = "Amplify Magic", recast = 3 }
B.magearmor = { name = "Mage Armor", category = "Mage", kind = "self", class = "MAGE", match = { "Mage Armor" },
    spell = "Mage Armor", recast = 5 }
B.icearmor = { name = "Ice Armor", category = "Mage", kind = "self", class = "MAGE",
    match = { "Ice Armor", "Frost Armor" }, spell = "Ice Armor", recast = 5 }
B.barrier = { name = "Ice Barrier", category = "Mage", kind = "self", class = "MAGE", match = { "Ice Barrier" },
    spell = "Ice Barrier", invert = true }
B.iceblock = { name = "Ice Block", category = "Mage", kind = "self", class = "MAGE", match = { "Ice Block" },
    invert = true }

-- Priest -------------------------------------------------------------
B.pwf = { name = "Fortitude", category = "Priest", match = { "Power Word: Fortitude", "Prayer of Fortitude" },
    spell = "Power Word: Fortitude", groupSpell = "Prayer of Fortitude", groupBy = "group",
    reagents = { 17028, 17029 }, recast = 5 }
B.sprot = { name = "Shadow Protection", category = "Priest",
    -- The potions' aura has the same name; they're told apart by spell ID
    match = { { name = "Shadow Protection", notIds = { 7242, 17548 } }, "Prayer of Shadow Protection" },
    spell = "Shadow Protection", groupSpell = "Prayer of Shadow Protection", groupBy = "group",
    reagents = { 17029 }, recast = 3 }
B.ds = { name = "Divine Spirit", category = "Priest", match = { "Divine Spirit", "Prayer of Spirit" },
    spell = "Divine Spirit", groupSpell = "Prayer of Spirit", groupBy = "group", reagents = { 17029 },
    ignoreClass = "wr", priority = CASTER_FIRST, recast = 5 }
B.innerfire = { name = "Inner Fire", category = "Priest", kind = "self", class = "PRIEST", match = { "Inner Fire" },
    spell = "Inner Fire", recast = 3 }
B.fearward = { name = "Fear Ward", category = "Priest", match = { "Fear Ward" }, spell = "Fear Ward", invert = true }
B.pws = { name = "Power Word: Shield", category = "Priest", match = { "Power Word: Shield" },
    spell = "Power Word: Shield", invert = true }
B.pi = { name = "Power Infusion", category = "Priest", match = { "Power Infusion" }, spell = "Power Infusion",
    invert = true, ignoreClass = "wrh", priority = { MAGE = 0.5, WARLOCK = 0.5, PRIEST = 0.2, DRUID = 0.2 },
    selfPriority = 0 }

-- Druid --------------------------------------------------------------
B.motw = { name = "Mark of the Wild", category = "Druid", match = { "Mark of the Wild", "Gift of the Wild" },
    spell = "Mark of the Wild", groupSpell = "Gift of the Wild", groupBy = "group", reagents = { 17021, 17026 },
    recast = 5 }
B.thorns = { name = "Thorns", category = "Druid", match = { "Thorns" }, spell = "Thorns", recast = 3 }
B.clarity = { name = "Omen of Clarity", category = "Druid", kind = "self", class = "DRUID",
    match = { "Omen of Clarity" }, spell = "Omen of Clarity", recast = 2 }

-- Paladin ------------------------------------------------------------
local function Blessing(key, name, extra)
    local def = {
        name = "Blessing of " .. name, category = "Paladin",
        match = { "Blessing of " .. name, "Greater Blessing of " .. name },
        spell = "Blessing of " .. name, groupSpell = "Greater Blessing of " .. name, groupBy = "class",
        reagents = { 21177 }, recast = 1, sort = "class",
    }
    for k, v in pairs(extra or {}) do
        def[k] = v
    end
    B[key] = def
end
Blessing("bom", "Might", { ignoreClass = "mplh" })
Blessing("bow", "Wisdom", { ignoreClass = "wr" })
Blessing("bok", "Kings")
Blessing("bos", "Salvation", { ignoreTanks = true })
Blessing("bol", "Light")
Blessing("bosanc", "Sanctuary")
B.bop = { name = "Blessing of Protection", category = "Paladin", match = { "Blessing of Protection" },
    spell = "Blessing of Protection", invert = true }
B.di = { name = "Divine Intervention", category = "Paladin", match = { "Divine Intervention" },
    spell = "Divine Intervention", invert = true, priority = { PRIEST = 2, PALADIN = 2, DRUID = 1, SHAMAN = 1 },
    selfPriority = -10 }
local function PaladinAura(key, name)
    B[key] = { name = name, category = "Paladin", kind = "aura", match = { name }, spell = name }
end
PaladinAura("devotion", "Devotion Aura")
PaladinAura("retribution", "Retribution Aura")
PaladinAura("concentration", "Concentration Aura")
PaladinAura("shadowaura", "Shadow Resistance Aura")
PaladinAura("frostaura", "Frost Resistance Aura")
PaladinAura("fireaura", "Fire Resistance Aura")
PaladinAura("sanctity", "Sanctity Aura")

-- Shaman -------------------------------------------------------------
local function Totem(key, name, buff)
    B[key] = { name = name, category = "Shaman", kind = "aura", match = { buff }, spell = name }
end
Totem("soe", "Strength of Earth Totem", "Strength of Earth")
Totem("goa", "Grace of Air Totem", "Grace of Air")
Totem("manaspring", "Mana Spring Totem", "Mana Spring")
Totem("windfury", "Windfury Totem", "Windfury Totem")
Totem("tranquilair", "Tranquil Air Totem", "Tranquil Air")
B.lightningshield = { name = "Lightning Shield", category = "Shaman", kind = "self", class = "SHAMAN",
    match = { "Lightning Shield" }, spell = "Lightning Shield", recast = 2 }

-- Warlock ------------------------------------------------------------
B.ss = { name = "Soulstone", category = "Warlock", match = { "Soulstone Resurrection" }, cast = "soulstone",
    invert = true, priority = { PRIEST = 2, SHAMAN = 2, PALADIN = 1, DRUID = 1 }, selfPriority = 0.8 }
B.ub = { name = "Unending Breath", category = "Warlock", match = { "Unending Breath" }, spell = "Unending Breath",
    recast = 3 }
B.detectinvis = { name = "Detect Invisibility", category = "Warlock",
    match = { "Detect Lesser Invisibility", "Detect Invisibility", "Detect Greater Invisibility" },
    spell = "Detect Invisibility", recast = 3 }
B.demonarmor = { name = "Demon Armor", category = "Warlock", kind = "self", class = "WARLOCK",
    match = { "Demon Armor", "Demon Skin" }, spell = "Demon Armor", recast = 5 }
B.bloodpact = { name = "Blood Pact", category = "Warlock", kind = "aura", match = { "Blood Pact" } }
B.sacrifice = { name = "Demonic Sacrifice", category = "Warlock", kind = "self", class = "WARLOCK",
    match = { "Touch of Shadow", "Fel Energy", "Fel Stamina", "Burning Wish" } }

-- Hunter -------------------------------------------------------------
B.trueshot = { name = "Trueshot Aura", category = "Hunter", kind = "aura", match = { "Trueshot Aura" },
    spell = "Trueshot Aura" }
B.aspecthawk = { name = "Aspect of the Hawk", category = "Hunter", kind = "self", class = "HUNTER",
    match = { "Aspect of the Hawk" }, spell = "Aspect of the Hawk" }
B.aspectwild = { name = "Aspect of the Wild", category = "Hunter", kind = "aura", match = { "Aspect of the Wild" },
    spell = "Aspect of the Wild" }
B.aspectpack = { name = "Aspect of the Pack", category = "Hunter", kind = "aura", match = { "Aspect of the Pack" },
    spell = "Aspect of the Pack" }

-- Warrior ------------------------------------------------------------
B.battleshout = { name = "Battle Shout", category = "Warrior", kind = "aura", match = { "Battle Shout" },
    spell = "Battle Shout", recast = 0.5 }

-- Consumables ---------------------------------------------------------
local function Item(key, category, name, itemID, aura, spellID, extra)
    local def = { name = name, category = category, kind = "item", item = itemID,
        match = { spellID and { id = spellID, name = aura } or aura } }
    for k, v in pairs(extra or {}) do
        def[k] = v
    end
    B[key] = def
end

local FE = "Flasks & Elixirs"
Item("titans", FE, "Flask of the Titans", 13510, "Flask of the Titans", 17626)
Item("wisdom", FE, "Flask of Distilled Wisdom", 13511, "Distilled Wisdom", 17627)
Item("supreme", FE, "Flask of Supreme Power", 13512, "Supreme Power", 17628)
Item("chromatic", FE, "Flask of Chromatic Resistance", 13513, "Chromatic Resistance", 17629)
B.anyflask = { name = "Any Flask", category = FE, kind = "item", match = {
    { id = 17626, name = "Flask of the Titans" }, { id = 17627, name = "Distilled Wisdom" },
    { id = 17628, name = "Supreme Power" }, { id = 17629, name = "Chromatic Resistance" } } }
Item("mongoose", FE, "Elixir of the Mongoose", 13452, "Elixir of the Mongoose", 17538)
Item("giants", FE, "Elixir of the Giants", 9206, "Elixir of the Giants", 11405)
Item("greateragi", FE, "Elixir of Greater Agility", 9187, "Greater Agility", 11334)
Item("demonslaying", FE, "Elixir of Demonslaying", 9224, "Elixir of Demonslaying", 11406)
Item("greaterarcane", FE, "Greater Arcane Elixir", 13454, "Greater Arcane Elixir", 17539)
Item("arcaneelixir", FE, "Arcane Elixir", 9155, "Arcane Elixir", 11390)
Item("greaterfirepower", FE, "Elixir of Greater Firepower", 21546, "Greater Firepower", 26276)
Item("shadowpower", FE, "Elixir of Shadow Power", 9264, "Shadow Power", 11474)
Item("frostpower", FE, "Elixir of Frost Power", 17708, "Frost Power", 21920)
Item("sages", FE, "Elixir of the Sages", 13447, "Elixir of the Sages", 17535)
Item("fortitude", FE, "Elixir of Fortitude", 3825, "Health II", 3593)
Item("superdef", FE, "Elixir of Superior Defense", 13445, "Greater Armor", 11348)
Item("mageblood", FE, "Mageblood Potion", 20007, "Mana Regeneration", 24363)
Item("trollblood", FE, "Major Troll's Blood Potion", 20004, "Regeneration", 24361)
Item("giftarthas", FE, "Gift of Arthas", 9088, "Gift of Arthas", 11371)
Item("cortex", FE, "Cerebral Cortex Compound", 8423, "Infallible Mind", 10692)
Item("roids", FE, "R.O.I.D.S.", 8410, "Rage of Ages", 10667)
Item("scorpok", FE, "Ground Scorpok Assay", 8412, "Strike of the Scorpok", 10669)
Item("lungjuice", FE, "Lung Juice Cocktail", 8411, "Spirit of Boar", 10668)
Item("firewater", FE, "Winterfall Firewater", 12820, "Winterfall Firewater", 17038)
Item("jujupower", FE, "Juju Power", 12451, "Juju Power", 16323)
Item("jujumight", FE, "Juju Might", 12460, "Juju Might", 16329)
Item("jujuflurry", FE, "Juju Flurry", 12450, "Juju Flurry", 16322)
Item("jujuchill", FE, "Juju Chill", 12457, "Juju Chill", 16325)
Item("jujuember", FE, "Juju Ember", 12455, "Juju Ember", 16326)
Item("jujuguile", FE, "Juju Guile", 12458, "Juju Guile", 16327)
Item("jujuescape", FE, "Juju Escape", 12459, "Juju Escape", 16321)
B.anyagility = { name = "Mongoose or Greater Agility", category = FE, kind = "item", match = {
    { id = 17538, name = "Elixir of the Mongoose" }, { id = 11334, name = "Greater Agility" } } }

local PP = "Protection Potions"
Item("gfpp", PP, "Greater Fire Protection Potion", 13457, "Fire Protection", 17543)
Item("gfrpp", PP, "Greater Frost Protection Potion", 13456, "Frost Protection", 17544)
Item("gnpp", PP, "Greater Nature Protection Potion", 13458, "Nature Protection", 17546)
Item("gspp", PP, "Greater Shadow Protection Potion", 13459, "Shadow Protection", 17548)
Item("gapp", PP, "Greater Arcane Protection Potion", 13461, "Arcane Protection", 17549)
Item("ghpp", PP, "Greater Holy Protection Potion", 13460, "Holy Protection", 17545)
Item("fpp", PP, "Fire Protection Potion", 6049, "Fire Protection", 7233)
Item("frpp", PP, "Frost Protection Potion", 6050, "Frost Protection", 7239)
Item("npp", PP, "Nature Protection Potion", 6052, "Nature Protection", 7254)
Item("spp", PP, "Shadow Protection Potion", 6048, "Shadow Protection", 7242)
Item("hpp", PP, "Holy Protection Potion", 6051, "Holy Protection", 7245)
Item("frozenrune", PP, "Frozen Rune", 22682, "Fire Protection", 29432)

local UT = "Utility"
Item("stoneshield", UT, "Greater Stoneshield Potion", 13455, "Greater Stoneshield", 17540)
Item("freeaction", UT, "Free Action Potion", 5634, "Free Action", 6615)
Item("livingaction", UT, "Living Action Potion", 20008, "Living Free Action", 24364)
Item("restorative", UT, "Restorative Potion", 9030, "Restoration", 11359)
Item("magicres", UT, "Magic Resistance Potion", 9036, "Resistance", 11364)
Item("swiftness", UT, "Swiftness Potion", 2459, "Speed", 2379)
Item("invis", UT, "Invisibility Potion", 9172, "Invisibility", 11392)
Item("immolationoil", UT, "Oil of Immolation", 8956, "Fire Shield", 11350)
Item("scrollagi", UT, "Scroll of Agility IV", 10309, "Agility", 12174)
Item("scrollprot", UT, "Scroll of Protection IV", 10305, "Armor", 12175)
Item("scrollint", UT, "Scroll of Intellect IV", 10308, "Intellect", 12176)
Item("scrollspi", UT, "Scroll of Spirit IV", 10306, "Spirit", 12177)
Item("scrollsta", UT, "Scroll of Stamina IV", 10307, "Stamina", 12178)
Item("scrollstr", UT, "Scroll of Strength IV", 10310, "Strength", 12179)

local FD = "Food & Drink"
B.wellfed = { name = "Well Fed", category = FD, kind = "item", match = { "Well Fed" } }
B.anyfood = { name = "Any Food Buff", category = FD, kind = "item", match = { "Well Fed", "Increased Stamina",
    "Mana Regeneration", "Increased Agility", "Increased Intellect", "Increased Spirit" } }
Item("dumpling", FD, "Smoked Desert Dumplings", 20452, "Well Fed", 24799)
Item("tenderwolf", FD, "Tender Wolf Steak", 18045, "Well Fed", 19710)
Item("squid", FD, "Grilled Squid", 13928, "Increased Agility", 18192)
Item("nightfin", FD, "Nightfin Soup", 13931, "Mana Regeneration", 18194)
Item("sagefish", FD, "Sagefish Delight", 21217, "Mana Regeneration", 25889)
Item("tuber", FD, "Runn Tum Tuber Surprise", 18254, "Increased Intellect", 22730)
Item("chili", FD, "Dragonbreath Chili", 12217, "Dragonbreath Chili", 15852)
Item("sunfruit", FD, "Blessed Sunfruit", 13810, "Blessed Sunfruit", 18125)
Item("sunfruitjuice", FD, "Blessed Sunfruit Juice", 13813, "Blessed Sunfruit Juice", 18141)
Item("rumsey", FD, "Rumsey Rum Black Label", 21151, "Rumsey Rum Black Label", 25804)
Item("rumseydark", FD, "Rumsey Rum Dark", 21114, "Rumsey Rum Dark", 25722)
Item("grog", FD, "Gordok Green Grog", 18269, "Gordok Green Grog", 22789)

local WB = "World Buffs"
local function WorldBuff(key, name, aura)
    B[key] = { name = name, category = WB, match = { aura or name } }
end
WorldBuff("dragonslayer", "Rallying Cry of the Dragonslayer")
WorldBuff("zandalar", "Spirit of Zandalar")
WorldBuff("songflower", "Songflower Serenade")
WorldBuff("warchief", "Warchief's Blessing")
WorldBuff("fengus", "Fengus' Ferocity")
WorldBuff("moldar", "Mol'dar's Moxie")
WorldBuff("slipkik", "Slip'kik's Savvy")
WorldBuff("zanza", "Spirit of Zanza")

-- Weapon coatings: checked on your own weapon only
local function Weapon(key, category, name, itemID)
    B[key] = { name = name, category = category, kind = "weapon", item = itemID, slot = 16 }
    B[key .. "oh"] = { name = name .. " (off hand)", category = category, kind = "weapon", item = itemID, slot = 17 }
end
Weapon("brilliantmanaoil", "Weapon", "Brilliant Mana Oil", 20748)
Weapon("lessermanaoil", "Weapon", "Lesser Mana Oil", 20747)
Weapon("brilliantwizardoil", "Weapon", "Brilliant Wizard Oil", 20749)
Weapon("wizardoil", "Weapon", "Wizard Oil", 20750)
Weapon("blessedwizardoil", "Weapon", "Blessed Wizard Oil", 23123)
Weapon("consecratedstone", "Weapon", "Consecrated Sharpening Stone", 23122)
Weapon("elementalstone", "Weapon", "Elemental Sharpening Stone", 18262)
Weapon("densesharpening", "Weapon", "Dense Sharpening Stone", 12404)
Weapon("denseweight", "Weapon", "Dense Weightstone", 12643)
Weapon("shadowoil", "Weapon", "Shadow Oil", 3824)
Weapon("frostoil", "Weapon", "Frost Oil", 3829)
Weapon("instantpoison", "Poisons", "Instant Poison VI", 8928)
Weapon("deadlypoison", "Poisons", "Deadly Poison V", 20844)
Weapon("woundpoison", "Poisons", "Wound Poison IV", 10922)
Weapon("mindnumbing", "Poisons", "Mind-numbing Poison III", 9186)
Weapon("crippling", "Poisons", "Crippling Poison II", 3776)

-- Debuffs ------------------------------------------------------------
local function Debuff(key, name, aura)
    B[key] = { name = name, category = "Debuffs", kind = "debuff", match = { aura or name }, invert = true }
end
Debuff("markfrost", "Mark of Frost")
Debuff("marknature", "Mark of Nature")
Debuff("bronze", "Chromaggus: Bronze", "Brood Affliction: Bronze")
Debuff("digestive", "C'Thun: Digestive Acid", "Digestive Acid")
local function Dispel(key, name, dispelType)
    B[key] = { name = name, category = "Debuffs", kind = "dispel", dispelType = dispelType, invert = true }
end
Dispel("dmagic", "Debuff: Magic", "Magic")
Dispel("dcurse", "Debuff: Curse", "Curse")
Dispel("ddisease", "Debuff: Disease", "Disease")
Dispel("dpoison", "Debuff: Poison", "Poison")
Dispel("dremove", "Debuff: You can remove", "mine")

-- Which debuff types each class can remove
RAB.DispelTypes = {
    PRIEST = { Magic = true, Disease = true },
    PALADIN = { Magic = true, Poison = true, Disease = true },
    DRUID = { Curse = true, Poison = true },
    MAGE = { Curse = true },
    SHAMAN = { Poison = true, Disease = true },
}

-- Spells that bring the dead back, by class, best first
RAB.ResSpells = {
    PRIEST = { "Resurrection" },
    PALADIN = { "Redemption" },
    SHAMAN = { "Ancestral Spirit" },
    DRUID = { "Rebirth" },
}

-- Soulstones, best first, and the spells that make them
RAB.Soulstones = { 16896, 16895, 16893, 16892, 5232 }
RAB.CreateSoulstone = {
    "Create Soulstone (Major)", "Create Soulstone (Greater)", "Create Soulstone",
    "Create Soulstone (Lesser)", "Create Soulstone (Minor)",
}

for key, def in pairs(B) do
    def.key = key
end

-- Bars a new character starts with, by class
RAB.DefaultBars = {
    ALL = {
        { buffKey = "alive", label = "Alive", color = { 0.3, 1, 0.3 } },
        { buffKey = "mana", label = "Healer Mana", classes = "pdsa", color = { 0.4, 0.6, 1 } },
    },
    MAGE = { { buffKey = "ai", label = "Intellect", color = { 0, 0.6, 1 } } },
    PRIEST = {
        { buffKey = "pwf", label = "Fortitude", color = { 0.9, 0.9, 0.9 } },
        { buffKey = "sprot", label = "Shadow Prot", color = { 0.6, 0.4, 0.8 } },
    },
    DRUID = {
        { buffKey = "motw", label = "Mark", color = { 0.8, 0.2, 1 } },
        { buffKey = "thorns", label = "Thorns", color = { 0.8, 0.6, 1 } },
    },
    PALADIN = {
        { buffKey = "bok", label = "Kings", color = { 0.9, 0.7, 0.3 } },
        { buffKey = "bow", label = "Wisdom", color = { 0.4, 0.7, 1 } },
        { buffKey = "bom", label = "Might", color = { 1, 0.4, 0.3 } },
    },
    WARLOCK = { { buffKey = "ss", label = "Soulstone", color = { 0.6, 0.2, 0.8 } } },
    HUNTER = { { buffKey = "trueshot", label = "Trueshot", color = { 0.6, 0.8, 0.3 } } },
    WARRIOR = { { buffKey = "battleshout", label = "Battle Shout", color = { 0.8, 0.3, 0.2 } } },
    SHAMAN = {},
    ROGUE = {
        { buffKey = "instantpoison", label = "Main hand", color = { 0.3, 0.8, 0.3 } },
        { buffKey = "deadlypoisonoh", label = "Off hand", color = { 0.3, 0.6, 0.3 } },
    },
}
