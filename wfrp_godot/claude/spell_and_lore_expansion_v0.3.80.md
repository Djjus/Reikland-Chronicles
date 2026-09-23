# Spell & Lore of Magic Expansion — v0.3.80

Follows on from `core_rulebook_spell_comparison.md`, which compared the in-game `data/spells/core_spells.tres` spell list against the actual WFRP 4e core rulebook (Magic chapter, pages 239-256) and found the game was missing 2 Petty spells, 13 generic Arcane spells, and the entire Lore of Colour Magic system (8 Lores x 8 signature spells each). Per the request ("first the missing spells then the lores"), this version adds all of it: 79 new spells, bringing the spell database from 33 to 112 entries.

## What's new

**2 missing Petty spells:** Dazzle (inflicts Blinded) and Sounds (flavour-only).

**13 missing generic Arcane spells:** Bridge, Chain Attack (a magic missile, +4 damage), Drop, Entangle (inflicts Entangled), Fearsome, Flight, Magic Shield, Move Object, Mundane Aura, Push, Teleport, Terrifying, Ward. All generic Arcane spells (the original 10 plus these 13) stay in the existing shared any-Lore pool — any wizard can learn them regardless of which Lore they've specialised in.

**All 8 Lores of Colour Magic, 8 signature spells each (64 total):** Beasts, Death, Fire, Heavens, Metal, Life, Light, Shadow. Each spell was given real mechanical weight where the book's own effect maps cleanly onto something this game already tracks — a magic missile with real damage (e.g. The Amber Spear, Great Fires of U'Zhul, Comet of Casandora, T'Essla's Arc, Steal Life, Caress of Laniph), a genuine Condition on a successful cast (Firewall's Ablaze, Net of Amyntok's Stunned, Miasma-adjacent effects like Choking Shadows' Fatigued), or a few clean-burst AoE spells (Flock of Doom, Great Fires of U'Zhul, Comet of Casandora, Transmutation of Chamon) using the existing AoE damage path. Everything else is honest flavour-text-only, matching the simplification level the game already uses for spells like Dome or Arrow Shield.

## How Lore-gated learning works

`Advancement.purchase_arcane_spell()` already gated the 10 original generic Arcane spells behind having the Arcane Magic Talent at all. It's now extended so a `spell_type == "Lore"` spell additionally requires the caster's own Lore (read via `Character.get_arcane_lore()`, which just looks for a `talents_taken` key like `"Arcane Magic (Fire)"`) to match the spell's own `lore` field exactly. A Fire-Lore wizard can learn any generic Arcane spell plus any of the 8 Fire spells, but not Regenerate (Life) or any other Lore's spells. Both spell types share one combined XP-tier `known_count`.

No new UI was needed for any of this — Lore selection, the Arcane Magic Talent's own `situation_options` list, and the Channelling skill's matching `group_options` list all already existed and already round-trip correctly through the existing situational-talent purchase flow. Three of the eight Lores (Fire, Death, Light) also automatically pick up their book-accurate passive Colour Magic effect (the "Colour Effect: ON/OFF" toggle in Field Encounter) for free, purely from being tagged with the matching `lore` string — that system already existed and needed zero changes.

## Two real bugs found while wiring this up

**Fixed: Condition-only spells could never actually land their Condition in combat.** `_is_damage_effect()` only recognised `is_magic_missile` and the hardcoded "Drain" as needing a live enemy target selected; anything else (including the already-shipped Shock spell) defaulted to targeting the caster, and `_apply_cast_spell_outcome`'s own Condition branch silently does nothing when the target is the caster. This means Shock's Stunned has never actually been reachable through the real UI since it shipped. Fixed by widening `_is_damage_effect()` to also cover any spell with `inflicts_condition != ""`. Verified live in the test suite: Shock cast at a real Giant Rat target now genuinely applies Stunned.

**Fixed: a spell that's both a magic missile AND inflicts a Condition could only ever apply one effect.** `_apply_cast_spell_outcome`'s whole effect dispatch is an `elif` chain, so a spell matching `is_magic_missile` would never reach the separate `inflicts_condition` branch below it. Two new Lore spells need both (T'Essla's Arc: damage + Blinded; Steal Life: damage + Fatigued), so the Condition application was added directly inside the magic-missile branch, guarded so it's skipped if the missile itself just defeated the target (matching the book's own "you can't blind something that's already down" logic). Verified live: T'Essla's Arc now deals real Wound damage and applies Blinded from the same cast.

**Found, not fixed (out of scope):** `MAGIC_COLOUR_EFFECTS` keys its Witch-Lore passive effect as `"Witchcraft"`, but the Arcane Magic Talent's own `situation_options` (and the matching Channelling skill list) actually store `"Witchery"` — so a Witchery-Lore wizard would never trigger that passive. Left alone since Witch Magic (Hedgecraft/Witchcraft, 12 more spells) is explicitly out of scope for this pass, same as Chaos/Dark Magic.

## Explicit scope decision

This pass covers the 8 Lores of Colour Magic only. Witch Magic (Hedgecraft + Witchery, ~12 more spells) and Chaos/Dark Magic are deliberately not implemented here.

## Testing

A new headless test suite (`scripts/core/core_rulebook_lore_spells_test.gd`, 27 checks) covers: spell database sanity (112 total, correct counts per type/Lore, no duplicates), the Lore-gating logic in `Advancement.purchase_arcane_spell` (no Talent fails outright, a Fire-Lore holder can learn generic + own-Lore spells but not another Lore's, no re-learning an already-known spell), and both bug fixes exercised live against a real `FieldEncounter` scene and a Giant Rat target.

Ran the full local headless suite (this new suite plus the 4 other pre-existing SceneTree-based suites — Light Spell, Blessing Buff Turn Order, Blessing Overcast, Outnumbering Cluster Disengage) 5 times total across this session with the official Godot 4.7 headless binary. All 68 checks passed every time, with no regressions in any pre-existing suite from the two shared-code fixes.

## Files changed

- `data/spells/core_spells.tres` — 79 new spell entries (ids 34-112).
- `scripts/core/advancement.gd` — `purchase_arcane_spell()` extended for Lore-gated spells.
- `scripts/ui/field_encounter_screen.gd` — `_is_damage_effect()` widened; combined magic-missile + Condition handling added.
- `scripts/core/core_rulebook_lore_spells_test.gd` — new test suite (+ its `.gd.uid`).
- `scripts/core/build_info.gd` — version bump to v0.3.80.
