# v0.3.75 — Condition marker glyph fixes (found via an actual screenshot)

## What happened

Right after shipping v0.3.74's condition markers, a real in-game
screenshot was taken to show the feature off — and it caught three of
the ten glyph picks not actually working as intended in this project's
font:

- **Blinded** ("👁") and **Broken** ("🏳") drew as plain missing-glyph
  boxes — this project's font has no glyph for either codepoint at all.
- **Bleeding** ("💧") turned out to be a full-color bitmap glyph that
  ignores `draw_string`'s own color argument, so it rendered as a blue
  droplet instead of red — reading as "water," not blood.

## The fix

Swapped all three for glyphs confirmed, by rendering actual candidates
and reading the pixels back, to both draw correctly AND still read
clearly at the small size these draw at on a token:

- Blinded: 🙈 (a monkey literally covering its own eyes)
- Broken: 😱 (the classic fear-stricken face — WFRP's own Broken
  Condition means fleeing in terror, which this reads as directly)
- Bleeding: 🔴 (a plain red circle — inherently red regardless of
  whatever the color argument does or doesn't do to it)

The other seven glyphs from v0.3.74 (🔥 Ablaze, 💫 Stunned, ⬇ Prone,
💤 Fatigued, ☣ Poisoned, ❗ Surprised, 👂 Deafened) were all confirmed
correct in the same screenshot and are unchanged.

## Verification

Confirmed by actually rendering the battle screen headless (via a
software-GL Godot run under Xvfb) with a party member and three
monsters carrying every one of the ten conditions between them, reading
the resulting screenshot back, and visually checking each of the ten
icons individually — not just trusting that a Unicode codepoint
"should" render. The existing `condition_markers_test.gd` (12 checks,
still passing) covers the *data* side of this — which glyph maps to
which Condition, stacking, ordering — but can't catch a codepoint the
project's own font can't actually draw; only the screenshot could.

Full regression sweep re-run after the swap: 437 checks across 16
suites — all passed, 0 failures.
