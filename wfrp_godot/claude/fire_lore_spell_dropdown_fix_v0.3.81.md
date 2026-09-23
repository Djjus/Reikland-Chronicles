# Fire Lore Spell Dropdown Fix — v0.3.81

Per the report: after v0.3.80 added all 8 Lores of Colour Magic, a Fire-Lore wizard's Character menu ("Learn an Arcane Spell (Fire)" dropdown, Spellbook tab) still only showed generic Arcane spells (Aethyric Armour, Dome, Chain Attack, and so on) — none of the 8 actual Fire spells (Crown of Flame, Purge, etc.) ever appeared to learn.

## Root cause

v0.3.80's testing covered `Advancement.purchase_arcane_spell()` directly — the business-logic layer that decides whether a given spell purchase is allowed — and confirmed it correctly accepts Lore spells. What it didn't cover was the actual player-facing screen that builds the list of spells offered *to* that function in the first place: `character_menu_screen.gd`'s `_rebuild_spells_subtab()`, in the Character menu (not the Advancement screen, which has no spell UI at all).

That function's dropdown was built from `GameData.spell_db.find_by_type("Arcane")` alone — the generic, any-Lore spell pool. It never queried `find_by_type("Lore")` at all, so none of the 64 new Lore spells could ever appear there, regardless of which Lore the character actually had. The backend was correctly willing to sell them; the shop window just never displayed them.

## Fix

`_rebuild_spells_subtab()` now also collects every `spell_type == "Lore"` entry whose own `lore` field matches the character's Lore (via `get_arcane_lore()`), appending them to the same offered list right alongside the generic Arcane spells. The known-spell count used to preview the next XP cost was also corrected to count both `"Arcane"` and `"Lore"` spells together, matching how `Advancement.purchase_arcane_spell()` has always priced them (one shared tier, not two separate ones) — previously the on-screen cost preview could undercount and show a lower price than what would actually be charged.

## Testing

Added `scripts/core/character_menu_arcane_lore_spell_list_test.gd`: instantiates the real `CharacterMenu.tscn`, gives a test character the Arcane Magic (Fire) Talent, opens the Spellbook tab, and inspects the actual `OptionButton` dropdown's item list — confirming it now offers Crown of Flame and Purge (Fire), still offers a generic spell (Dome), and correctly excludes both a different Lore's spell (Regenerate, Life) and an already-known spell.

Ran the full local headless suite (this new test plus the 5 from v0.3.80) 3 times with the official Godot 4.7 headless binary. All 74 checks passed every time, no regressions.

## Files changed

- `scripts/ui/character_menu_screen.gd` — `_rebuild_spells_subtab()` now includes matching-Lore spells in the "Learn an Arcane Spell" dropdown, and counts them toward the known-spell XP tier.
- `scripts/core/character_menu_arcane_lore_spell_list_test.gd` — new test suite (+ its `.gd.uid`).
- `scripts/core/build_info.gd` — version bump to v0.3.81.
