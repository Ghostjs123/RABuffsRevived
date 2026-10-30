# RABuffs

A port of the existing RABuffs addon to WoW Classic Era (1.15) and WoW: Forever (1.60). It's a raid and party
buff monitor: a small window of bars shows how many people have each buff; hover a bar to see who is missing it,
click it to buff the next person.

RABuffs was written in 2006 for the original 1.12 client. This port builds on these earlier versions:

- [dagochen/RABuff](https://github.com/dagochen/RABuff): the 2006 addon, put on GitHub with added consumables
- [killersmath/Rabuffs](https://github.com/killersmath/Rabuffs)
- [melbaa/Rabuffs](https://github.com/melbaa/Rabuffs)
- [pepopo978/Rabuffs](https://github.com/pepopo978/Rabuffs): profiles, per-buff options and most of the buff
  list used here

Those versions target the 1.12 client, whose API the modern clients no longer have, so the code was rewritten
here; the buff data, behavior and commands carry over. Turtle WoW's custom items and spells from those forks
are left out.

## Using it

- **Hover** a bar: who is missing it, grouped by party (by class for blessings), plus who will lose it soon.
  Hold **Shift** to see who has it instead.
- **Click**: cast it on the best person who lacks it (healers and your own party first; whoever you just
  buffed goes to the back). **Alt-click**: the group version (Arcane Brilliance, Prayer of Fortitude, Gift of the
  Wild, Greater Blessings) on the party or class that needs it most. Consumable bars use the item on you;
  oil, stone and poison bars put it on your weapon. Clicking the Alive bar resurrects the dead.
- **Ctrl-click**: report the bar to raid chat (or wherever the bar is set to report). **Right-click**: menu.
- In combat, clicks keep the target they had when combat started (the game doesn't let addons change them
  then). On Forever, buffs can't be read in combat or during some encounters; the bars keep the last reading,
  greyed out, until they can be read again.

Commands: `/rab` (help, `show`, `hide`, `options`, `lock`, `reset`, `profile ...`, `buffs`, `info`) and
`/rabq [raid|party|officer|w <name>|c <channel>] [not] <buff> [groups] [classes]`, e.g. `/rabq raid motw 1234`.

Bars, settings and profiles: `/rab options`. Each class starts on its own profile ("Priest", "Mage"...);
profiles can be exported and imported as text. A **Custom Aura** bar checks any buff by name or spell ID, for
anything RABuffs doesn't know yet.

## Files

| File | |
|---|---|
| `Compat.lua` | Every game API call that differs between the clients or can be secret on Forever |
| `Data\Buffs.lua` | The buffs, consumables and debuffs that can be checked, and each class's default bars |
| `Core.lua` | Saved settings, profiles, events and the refresh loop |
| `Scan.lua` | The aura cache, by player GUID |
| `Query.lua` | Who counts for a bar, who has the buff, and the chat report |
| `Cast.lua` | Picking whom a click buffs and setting up the secure buttons |
| `UI\` | The bars window, right-click menu and options window |

## Tests

The addon runs outside the game in Lua 5.1 against a fake client (`tests/mock.lua`), which can act like
Classic Era or like Forever (secret auras in combat, secret unit comparisons, hidden health):

```
pip install -r tests/requirements.txt
python tests/run_tests.py            # everything
python tests/run_tests.py forever    # tests whose names contain "forever"
```
