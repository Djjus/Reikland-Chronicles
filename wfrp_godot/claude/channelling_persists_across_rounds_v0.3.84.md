# Channelling persists across rounds — v0.3.84

Follow-up to v0.3.82, per the note (with the Core Rulebook's own Channelling Test page attached): "note that channelling is accumulative, and lasts longer then the next round."

## What this actually was

Not a functional bug — the underlying mechanic already worked correctly. `_channelling_progress` (the per-Lore `accumulated_sl` tracker) is only ever cleared in exactly two places, both inside the cast-outcome handlers (`_apply_cast_spell_outcome`/`_apply_cast_spell_outcome_aoe`), triggered by an actual cast *attempt* — any spell, success or fail, per an earlier explicit decision ("any accumulated Channeling SLs should be removed after attempting to cast the next spell even if it fails to cast"). Nothing clears it just because a Round ends. `channel_round()` itself is additive (`progress.accumulated_sl += result.success_levels`) and the same `ChannellingProgress` object is reused across calls for a given Lore, not replaced — so Channelling for 2, 3, or more Rounds in a row genuinely keeps building, and the discount it grants stays available at cast time no matter how many Rounds later that cast happens.

The actual problem was the wording of the player-facing notices. They said things like "reduces your next Fire spell's Casting Number by 6 next Round" and "Ready to cast a Fire spell next Round at CN 0" — phrasing lifted close to the core rulebook's own (p.237: "On the next Round, you can cast your spell..."), which reads as a one-Round deadline: channel this Round, cast next Round, or the benefit is implied to be gone. That's not how this project's Channelling was ever actually implemented, but the notices didn't say so — exactly the mismatch the note called out.

## The fix

Reworded every Channelling notice (player-side partial/full-reduction messages, player-side Critical Channelling message, and the monster Spellcaster AI's equivalent Critical message) to describe what actually happens: the discount is live immediately and keeps building for as many Rounds as the caster keeps Channelling, staying fully available whenever they eventually cast — not a "next Round only" window. No change to any of the underlying mechanics (`MagicResolver.channel_round`, `channelled_cn_reduction`, `_get_effective_cn`, or the two `_channelling_progress.clear()` call sites) — those already matched the intended behavior.

## Testing

New `channelling_persists_across_rounds_test.gd` (5 checks): sets 5 accumulated SL on a live `FieldEncounter`, ticks 3 Rounds forward with no cast attempt, and confirms the progress object survives completely untouched — same object, same SL, and `_get_effective_cn()` still applies the full discount afterward. Also calls `MagicResolver.channel_round()` directly in a loop (skipping Fumble/Critical branches, which have their own separate, unrelated rules) until it captures a genuine second success landing on top of an existing total, and confirms it adds rather than replaces.

Ran the full local headless suite (this new test plus the 8 already covering spells/lores/Channelling/lighting/buffs/outnumbering/the weapon-cache stall fix) 3 times with the official Godot 4.7 headless binary. All 106 checks passed every time, no regressions. The new test's own dice-dependent step (waiting for a clean non-Fumble success) came back clean across all 3 runs.

## Files changed

- `scripts/ui/field_encounter_screen.gd` — reworded the Channelling follow-up messages (`_on_channel` and the monster Spellcaster AI's Critical Channelling line) to describe genuine multi-Round persistence instead of implying a one-Round deadline.
- `scripts/core/channelling_persists_across_rounds_test.gd` — new test suite (+ its `.gd.uid`).
- `scripts/core/build_info.gd` — version bump to v0.3.84.
