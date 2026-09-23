# Cover/Modifier Readout, Stretched Obstacle Art, Larger Battle Map — v0.2.367

## 1. The floating range readout now shows cover and every other applicable modifier

The little "12 yd — Short +20" text that floats above a targeted enemy while aiming a ranged attack now also lists any other modifier that would actually apply to that exact shot, each in its own color:

- **Cover**, in red — e.g. "Cover (Hard) -30" — or "No LOS" in red if the shot would be blocked outright by something too big to see past.
- **Fear**, in red, if the target is a source of Fear for the attacker (-10).
- **Additional Effort**, in green, if it's currently active (+the bonus amount).

This mirrors exactly what `_on_player_attack` folds into the real roll, so the readout never promises something the actual attack doesn't deliver.

## 2. Multi-square obstacle art is stretched, not tiled

Boulders, ponds, broken carts, and structures — the "solid mass" obstacle types — used to have their hand-drawn detail (rock clusters, cart wheels, roof lines) drawn once per occupied square, which for a 2x2 or larger footprint showed the same small motif repeated across every square, reading as an obviously tiled pattern.

These four types now get their detail drawn once per obstacle *instance*, scaled to fill that instance's whole footprint bounding box — one boulder cluster spanning the whole rock formation, one roof spanning the whole building, instead of four identical little icons side by side. Trees, bushes, high grass, and fences are unaffected — they're either always exactly one square (trees/bushes) or naturally read as per-square texture already (grass blades, fence posts and rails), so tiling was never a problem for those.

## 3. The battle map is 50% larger, with the same default zoom

The battlefield grid grew from 30x18 to 45x27 squares (90x54 yards instead of 60x36), with obstacle density and mud-patch coverage scaled up to match so the bigger map doesn't feel emptier than before.

The default camera view still shows the same amount of detail as the old 30x18 map did — squares render at their old size by default, so the new, larger map now spills past the edges of the screen. A new zoom-out level (roughly 2/3) fits the whole enlarged map into view in one step, the same way the default zoom used to; SHIFT+scroll and SHIFT+drag both work as before to zoom and pan around the bigger battlefield.

## Where this lives in the code

- `field_encounter_screen.gd` — `_ranged_target_readout()` now returns a list of colored text segments instead of one flat string.
- `battle_grid_view.gd` — the segment-based readout renderer; the new per-instance stretched obstacle drawing pass; `DEFAULT_VIEW_COLS/ROWS`, the generalized `_clamp_pan()`, and the new zoom-out level.
- `battle_grid.gd` — `COLS`/`ROWS` and the obstacle/mud density constants scaled for the larger map.

## A bug caught along the way

Testing surfaced a genuine pre-existing bug in Huge obstacle generation: breaking up an accidental perfect-rectangle blob by removing a corner square could drop a 9-square blob down to 8, one under the documented Huge minimum. It was rare enough to slip through earlier testing, but the larger map's bigger obstacle budget rolls far more Huge instances per battle, making it likely to show up. Fixed by growing an extra square instead of removing one whenever the removal would have under-sized the footprint.

## Testing

Both regression tests (`BattleObstaclesTest`, `PsychologyTest`) pass reliably across repeated runs, the full 8-scene headless load check is clean, and a dedicated smoke test exercised the new zoom/pan math, the multi-segment readout, and the stretched-obstacle draw path directly (including forcing an actual `_draw()` pass headlessly) without errors.
