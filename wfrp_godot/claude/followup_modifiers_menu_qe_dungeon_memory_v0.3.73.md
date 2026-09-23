# v0.3.73 — Follow-up attack modifiers, Character Menu Q/E while exploring, and dungeon floor memory

## The report

One message, three separate bugs, from a screenshot of a Furious
Assault roll card showing no Modifier row at all ("Fredi attacks Wight
with a Warhammer (1H)... Furious Assault — 1 Adv... Roll vs Target 85
vs 77... SL -1"):

> outnumbering bonus and other melee action modifiers should be adding
> to Furious Assault/Frenzy attacks too. also the character menu
> doesn't allow switching character while in exploration mode, fix
> that. the dungeon should also remember which doors have been opened
> when going back up or down.

## Fix 1 — Frenzy/Furious Assault were dropping Charging, Fear, Darkness, and off-hand penalty

The main attack (the one you actually declare each turn) has always
correctly summed every situational modifier that applies — Outnumbering,
Charging, Fear, Darkness, an off-hand penalty — into both the real roll
target and the card's own Modifier breakdown. Frenzy and Furious
Assault, the two "free extra swing" follow-ups that can fire right
after that attack, only ever carried Outnumbering forward. Everything
else the triggering attack had just correctly applied to this exact
same attacker/weapon/target was silently dropped — both from the real
roll AND the display, which is exactly why the reported card showed no
Modifier row at all (nothing else was passed in to build one from).

Fixed by threading the same `charge_bonus`/`fear_penalty`/
`darkness_mod`/`off_hand_penalty` values the main attack already
computes straight through to both follow-ups, so they land in the real
roll and rebuild the same kind of Modifier breakdown the main attack
shows. Additional Effort is deliberately left out — that's a one-time
spend committed to a single specific Test, and per the pre-existing
convention this project's own Dual Wielder off-hand follow-up already
uses, it doesn't carry over to a bonus attack the player didn't
separately pay Effort for.

## Fix 2 — Character Menu ignored Q/E while exploring a dungeon

FieldEncounter's own Character Menu (opened with M while exploring —
added a few versions back) never got the Q/E "switch which party
member you're viewing" wiring Overworld's and City's own Character Menu
instances already have. The screen's blanket "menu's open, ignore every
other hotkey" guard swallowed Q/E along with everything else, so the
keys did nothing at all rather than switching who's shown.

Fixed by intercepting Q/E first, calling the same
`character_menu.cycle_displayed_character()` Overworld already calls,
before falling through to the same catch-all guard for every other key.

## Fix 3 — Dungeon floors regenerated fresh every time you went back up or down

`_take_stairs_down()`/`_take_stairs_up()` both unconditionally called
`DungeonGenerator.generate()` on every single floor change — even when
returning to a floor already visited this same delve. That discarded
the ENTIRE previous floor's state: every door slammed back shut, every
room "not yet encountered" again (risking a duplicate monster spawn),
and every bit of explored fog-of-war forgotten.

Fixed with a new same-session cache, `GameState.dungeon_floor_states`,
keyed by floor number. The first time each floor is generated it's
stashed in the cache; going back to it later reuses the cached
Dictionary instead of generating a new one. Since GDScript Dictionaries
are reference types, the cached copy and the live one exploration
mutates are the same object for as long as that floor is the one being
explored — every door opened, chest looted, or tile revealed is
automatically reflected in the cache too, with no extra bookkeeping.
Reset alongside `dungeon_state` everywhere a delve genuinely ends
(leaving the dungeon, a party wipe, a fresh character) or a stale OTHER
dungeon gets discarded before a new one starts (the Goblin Fort's own
"always fresh" entry point).

Deliberately in-memory only, not part of save data — a full app restart
mid-dungeon still only resumes whichever ONE floor is currently active,
exactly as before. This fixes the far more common case: walking up and
down between floors in the same play session without ever closing the
app.

## Regression sweep

Three new tests:

- `scripts/core/frenzy_furious_assault_modifier_test.gd` — calls
  `_execute_frenzy_attack()`/`_execute_furious_assault()` directly, once
  with every optional modifier at 0 and once with all of them set to
  distinct nonzero values, and confirms both the displayed Modifier
  breakdown AND the real roll's own target number actually moved by the
  modifiers' combined sum — not just the display. 14 checks.
- `scripts/core/character_menu_qe_exploration_test.gd` — opens the
  Character Menu during real dungeon exploration with a two-member
  party, confirms E/Q actually cycle who's shown, that the menu doesn't
  close or leak other hotkeys through while doing so, and that browsing
  never touches which character you're actively controlling. 13 checks.
- `scripts/core/dungeon_floor_memory_test.gd` — opens a door on floor 0
  of a real generated dungeon, descends to floor 1, climbs back to floor
  0, and confirms it's the exact same dungeon_state object (not a
  lookalike), the door is still open, the room is still marked
  encountered (no duplicate spawn), and the fog-of-war revealed earlier
  is still remembered. Also confirms leaving the dungeon clears the
  cache. 15 checks.

Full sweep run in a clean, freshly-imported copy of the project: 419
checks across 14 suites (the three new ones above, plus
`FieldEncounterCharacterMenuTest`, `OvercastAoeCardFoldTest`,
`ChoicePromptKeyboardFocusTest`, `CriticalWoundDeflectInputTest`,
`CriticalWoundDeflectReproTest`, `EndTurnWasdFocusNoTargetTest`,
`DungeonLootEquipableTest`, `CraftingTest`, `ShopGridTest`,
`LightSpellInstantRevealTest`, `LightSpellTest`, and
`TestResolverUncappedTargetTest`) — all passed, 0 failures.
