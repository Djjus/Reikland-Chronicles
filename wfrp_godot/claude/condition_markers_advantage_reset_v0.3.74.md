# v0.3.74 — Condition markers on the battle map, and Advantage clears on returning to exploration

## The report

> Character/monster Icons, lets add visual markers for conditions on
> each combatant (example pictures), create a suitable representative
> marker for each condition (ablaze/prone/bleeding/stunned/broken/
> blinded/fatigued/poisoned/surprised/deafened). And clear combat
> Advantage when game enters exploration mode after a fight.

## Fix 1 — Condition markers on the battle map

Every one of these ten Conditions was already tracked correctly on
`Character.conditions` (used throughout combat resolution — Fatigued
lowering Initiative, Poisoned ticking down each Round, Blinded/Deafened
penalizing rolls, and so on), but nothing on the actual battle map ever
showed them. The only places a Condition was visible at all were plain
text: the ally roster panel's small grey condition line, and the
hover tooltip when mousing over a combatant.

Added a row of small icon markers, drawn directly above each
combatant's own HP bar on their battle-grid token — one glyph per
active Condition, in a fixed left-to-right order so a combatant with
several at once always shows them in the same order every time. A
Condition currently stacked past 1 (Poisoned 3, Ablaze 2, ...) shows
its own stack count right after the glyph; a Condition that's simply
present (Surprised, which never stacks) shows just the bare icon.

| Condition | Icon |
|---|---|
| Ablaze | 🔥 |
| Bleeding | 💧 (red) |
| Poisoned | ☣ |
| Stunned | 💫 |
| Prone | ⬇ |
| Broken | 🏳 |
| Blinded | 👁 |
| Deafened | 👂 |
| Fatigued | 💤 |
| Surprised | ❗ |

These are drawn the same way this project already draws its other
on-screen glyphs (the Light spell's turn-order row, the ally/adversary
🛡/☠ side markers, ★ Victory notices) — a plain Unicode character
through the shared UI font, no new art asset needed. Unconscious keeps
its existing, separate treatment (a red X straight across the whole
token) rather than getting a redundant icon of its own.

## Fix 2 — Advantage now clears when returning to exploration after a fight

A dungeon fight that starts mid-exploration (walking into a room with
monsters) hands the party back to exploration afterward via
`_return_to_exploration_after_combat()` — which deliberately keeps the
SAME live CombatEncounter running the whole time, rather than tearing
it down and rebuilding a fresh one. That also meant its Advantage pool
(Up in Arms, p.133-135) carried straight through: whatever either side
happened to be sitting on the moment the fight ended stayed there,
completely unspent, and silently fed into the next, entirely unrelated
fight further into the dungeon.

Advantage is explicitly meant to be a per-fight resource, not a running
total — both the ally and adversary pools now reset to 0 the moment
combat actually ends and exploration resumes.

## Regression sweep

Two new tests:

- `scripts/core/condition_markers_test.gd` — tests the new
  `BattleGridView._condition_markers_for()` helper directly (split out
  of the real drawing loop specifically so this doesn't need to render
  anything to verify): confirms all ten Conditions have their own
  distinct icon, an unrelated Condition (Unconscious) gets no marker,
  stacking shows the right count, a single stack shows the bare glyph,
  and the display order is fixed regardless of how the Conditions
  Dictionary happened to be built. 12 checks.
- `scripts/core/exploration_advantage_reset_test.gd` — starts a real
  dungeon exploration fight, gives both sides Advantage as if it had
  actually been earned, calls the real hand-off back to exploration,
  and confirms both pools land on exactly 0. 6 checks.

Full sweep run in a clean, freshly-imported copy of the project: 437
checks across 16 suites — all passed, 0 failures.
