# Channelling partial CN reduction — v0.3.82

Per the report, with two screenshots: Aes channelled Fire for 6 SL ("enough to cast Bolt, Blast at CN 0 next Round"), then tried casting Great Fires of U'Zhul (CN 10) and it failed outright — "SL +4 - 10 = -6" — with no sign the 6 channelled SL had done anything at all. "channelling should reduce the CN by the channelling SL, this should work for partial CN reduction as well and to CN 0."

## Root cause

Channelling's actual rule (p.237) is a plain 1-for-1 reduction: every SL scored on the Channelling Test knocks 1 off the Casting Number of a spell cast within the next round, down to a minimum of 0 — a running, partial discount. `MagicResolver.is_channelled_for()` (and every caller of it — `_get_effective_cn()`, `_on_cast_spell()`, `_on_cast_spell_aoe()`, and the monster-side spellcaster AI, all in `field_encounter_screen.gd`) instead implemented an all-or-nothing gate: `accumulated_sl >= spell.casting_number`. Below that threshold, the discount was exactly zero, no matter how close accumulated SL was to covering it. 6 SL toward a CN 4 spell (Bolt) worked fine (6 ≥ 4 → free cast); 6 SL toward a CN 10 spell (Great Fires of U'Zhul) got nothing at all, when the book always meant it to knock CN down to 4.

## The fix

Added `MagicResolver.channelled_cn_reduction(progress, spell)`, returning the real reduction to apply — `min(accumulated_sl, spell.casting_number)`, or the full CN outright on a Critical Channel (`critical_ready`, unchanged from before) — capped so it can never reduce a spell's CN below 0 or refund unused SL beyond what that one spell needed. `_get_effective_cn()` now computes `spell.casting_number - best_reduction` across every Lore currently channelled, instead of returning only 0 or the full CN. `_on_cast_spell()`/`_on_cast_spell_aoe()` and their outcome-display functions (`_apply_cn_to_displayed_sl`, `_apply_cast_spell_outcome`, `_apply_cast_spell_outcome_aoe`) were reworked to thread this actual effective CN through end to end — the roll card's own "Casting Number" breakdown line and "Spell (CN N)" header now always show the real, discounted number, not a binary 0/full. The monster-side Spellcaster AI (`_monster_cast_spell`) got the same fix for consistency, since it's the identical underlying rule.

The Channelling roll's own follow-up message was also corrected — it used to say a spell short of full coverage got "not yet enough for any known Arcane spell's Casting Number," which read as "this did nothing," when it always still knocked that many points off. It now says something like "6 SL accumulated so far — reduces your next Fire spell's Casting Number by 6."

`is_channelled_for()` itself is unchanged and still used for the "which spells reach CN 0 outright" messaging — that's still a true, useful subset case, just no longer the only case that matters.

## Testing

New `channelling_partial_cn_reduction_test.gd` (9 checks): exercises `MagicResolver.channelled_cn_reduction()` directly (partial reduction, capping at the spell's own CN, Petty spells excluded, 0 SL = 0 reduction, Critical Channel = full reduction), then `_get_effective_cn()` against a real `FieldEncounter` instance for the same cases. A headless screenshot reproduces the exact reported scenario — 6 SL Fire channelled, the same +4 raw roll — and confirms Great Fires of U'Zhul (CN 10) now shows CN 4 and succeeds, instead of failing at CN 10.

Ran the full local headless suite (this new test plus the 6 already covering spells/lores/Channelling-adjacent systems) 3 times with the official Godot 4.7 headless binary. All 92 checks passed every time, no regressions.

## Files changed

- `scripts/core/magic_resolver.gd` — new `channelled_cn_reduction()`.
- `scripts/ui/field_encounter_screen.gd` — `_get_effective_cn()`, `_on_cast_spell()`, `_on_cast_spell_aoe()`, `_apply_cn_to_displayed_sl()`, `_apply_cast_spell_outcome()`, `_apply_cast_spell_outcome_aoe()`, the monster Spellcaster AI, and the Channelling follow-up message all updated for partial reduction.
- `scripts/core/channelling_partial_cn_reduction_test.gd` — new test suite (+ its `.gd.uid`).
- `scripts/core/build_info.gd` — version bump to v0.3.82.
