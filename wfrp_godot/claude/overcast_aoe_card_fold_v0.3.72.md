# v0.3.72 — Overcast Damage now folds into the Blast roll card

## The report

Two identical screenshots of a Blast spell's roll card: the boxed
"Damage 8" row and the per-target "Wight: 1 Wound(s) (7 mitigated)" /
"Cairn Wraith: 1 Wound(s) (7 mitigated)" lines all showed the plain,
pre-Overcast numbers. Underneath the card, a separate line of green
text read "Overcast (Blast): 2 Wound(s) to Wight (8 base + 5 Overcast),
5 Wound(s) to Cairn Wraith (8 base + 5 Overcast)" — the real, final
numbers, disconnected from the card itself. The ask: fold the Overcast
bonus into the card's own Damage/Wounds numbers instead of leaving the
card stale and adding a separate green line.

## Root cause

The single-target version of this flow (`_offer_overcasting()`, used
for spells like Bolt) already does exactly what was asked: when the
player spends Success Levels on Overcast Damage, it reverses the
Wounds already applied, recombines the raw pre-soak damage with the
Overcast bonus, re-soaks once, and — this is the part that matters —
mutates the *same* Dictionary/Array objects the roll card itself
renders from (its boxed Damage total, its Damage breakdown list, and
the target's own Wounds/mitigated line), then triggers a re-render.
The card visibly updates in place; nothing new gets logged.

The AoE counterpart (`_offer_overcasting_aoe()`, used for Blast) never
got the same treatment. It reversed and recombined the Wounds
correctly, but only ever *announced* the combined total in a new
plain-text notice — the roll card built earlier by
`_apply_cast_spell_outcome_aoe()` was never referenced again, so it sat
there frozen at the pre-Overcast numbers. (The code even already had a
comment above `_last_aoe_damage_hits` claiming it used "the same
fold-in pattern the singular version uses" — it just never actually
did.)

## The fix

`_apply_cast_spell_outcome_aoe()` now keeps a live reference to the
card it just built (`_last_aoe_card_data`) and its Damage breakdown
list (`_last_aoe_damage_breakdown`), plus, for each hit target, the
exact same Dictionary object that ended up in the card's own
`targets_hit` list (stored per-target in `_last_aoe_damage_hits` as
`hit_entry`).

`_offer_overcasting_aoe()` now uses those references directly: it
still reverses each target's Wounds and recombines the raw damage with
the Overcast bonus exactly as before (soak differs per target, so each
target's own Wounds/mitigated line is still recomputed individually),
but instead of writing a new notice, it appends an "Overcast" row to
the shared breakdown, bumps the shared boxed Damage total once (an AoE
spell's Damage is computed once and applied to everyone in the blast,
so this only needs to happen once, not per target), updates each
target's own Wounds/mitigated numbers in place, and calls a single
re-render. No new log line is added — the card itself is now the only
place the numbers show, and they're the real, final ones.

## Regression sweep

New test: `scripts/core/overcast_aoe_card_fold_test.gd` — casts a real
Blast spell (damage_flat 3, matching the report) at two monsters with
deliberately different Toughness so their mitigation genuinely differs,
confirms the card starts out showing the plain pre-Overcast numbers,
then spends Overcast SL on Damage and confirms: the card's own Damage
total and breakdown updated to the combined value, each target's own
Wounds/mitigated line was recomputed individually (not copy-pasted),
real Wounds landed exactly once (no double-application from the
reverse-then-reapply step), and — the actual regression — no separate
"Overcast (...)" notice was added to the log at all. 20 checks, all
passing.

Full sweep run in a clean, freshly-imported copy of the project: 367
checks across `OvercastAoeCardFoldTest`, `ChoicePromptKeyboardFocusTest`,
`CriticalWoundDeflectInputTest`, `CriticalWoundDeflectReproTest`,
`EndTurnWasdFocusNoTargetTest`, `DungeonLootEquipableTest`,
`CraftingTest`, `ShopGridTest`, `LightSpellInstantRevealTest`,
`LightSpellTest`, and `TestResolverUncappedTargetTest` — all passed, 0
failures.
