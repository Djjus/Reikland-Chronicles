# Critical Wound Card Fix, Mud Paths, Obstacle Overcrowd Rule — v0.2.368

## 1. Critical Wound cards now show the right "Wounds" number

The Critical Wound card's "Wounds" line was showing the normal opposed-hit damage (already displayed a moment earlier on the Defence card) instead of the Critical Wound table's own, separate Wounds column — so a Severed Finger (which the table says costs 4 extra Wounds) was showing whatever the hit itself dealt (e.g. 15), reusing the wrong number entirely. Fixed for both the normal Critical Wound card and the Critical Parry counter-strike's own card.

Per the follow-up correction: when the critical roll happens because the target was already at (or reduced to) 0 Wounds before this hit, or the result is a Death-tier entry, the table's Wounds number doesn't mean anything on its own — only whether they end up unconscious or dead matters — so the Wounds row is skipped entirely in those cases rather than showing a number that doesn't tell you anything useful.

## 2. Mud paths now cross the battle map, alongside the existing dotted patches

Battle maps now generate 0-2 winding dirt paths that cross the whole map from one side to the opposite side (west-to-east or north-to-south, picked at random, with some natural wander so they don't look ruled with a straightedge), on top of the small mud patches already scattered around. A path steps straight through any obstacle it crosses without marking it, same as the existing patches — a trail interrupted by a boulder or a stand of trees reads as natural.

## 3. Obstacles never leave an open square more than 60% surrounded

After obstacles are scattered, a new pass checks every open square on the map and removes whichever obstacle is most responsible for the worst pocket, repeating until no square a character or monster could ever stand on has more than 60% of its neighbouring squares blocked. This is a thinning pass rather than a full re-roll of the map — much faster to converge, and it never has to fall back to "no obstacles at all" the way retrying the whole scatter from scratch could.

## Where this lives in the code

- `combat_resolver.gd` — new `critical_wound_target_already_down` / `critical_parry_counter_extra_wounds` / `critical_parry_counter_target_already_down` fields on `AttackResult`, set alongside the existing critical-wound-table resolution.
- `field_encounter_screen.gd` — the two `critical_wound` card dicts now source `"wounds"` from the table's own extra-wounds field and set a new `"hide_wounds"` flag.
- `roll_card_builder.gd` — `build_critical_wound_card` skips the Wounds row entirely when `hide_wounds` is set.
- `battle_grid.gd` — `_scatter_mud_path()` for the crossing paths; `_thin_overcrowded_pockets()` / `_remove_obstacle_instance()` for the 60% rule, called from `_scatter_obstacles()` right after the existing connectivity check passes.
- `battle_obstacles_test.gd` — updated to skip thinned-away (empty-footprint) obstacle instances, plus a new check confirming no open square ever exceeds 60% blocked neighbours.

## Testing

Both regression tests (`BattleObstaclesTest`, `PsychologyTest`) pass reliably, the full 8-scene headless load check is clean, and two dedicated smoke tests directly verified the fix: one confirming the Critical Wound table's own Wounds value is now genuinely independent of the hit's own damage (and that the already-down/Death cases correctly hide the row), and one hand-building a deliberately overcrowded pocket (87.5% blocked) and confirming the new thinning pass brings it back under the 60% threshold.
