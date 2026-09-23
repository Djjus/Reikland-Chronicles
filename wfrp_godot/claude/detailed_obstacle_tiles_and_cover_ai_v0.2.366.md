# Detailed Obstacle Tiles, Tiered Cover, and Cover-Aware Monster AI — v0.2.366

## What changed

### 1. Obstacles are now real, multi-square tiles instead of scattered single squares

Every obstacle on a battle map now occupies a proper footprint, sized by class:

- **Normal** — 1 square.
- **Large** — 4 squares (one of several tetromino-ish shapes, chosen at random for variety).
- **Huge** — 9 to 20 squares, grown organically so it's never a plain rectangle.
- **Line** — 3 to 9 squares long, either straight or bent once in an L (fences/walls only).
- **Clump** — 1 to 5 squares, grown the same organic way as Huge (High Grass only).

Only High Grass can be walked through — every other obstacle, at any size, blocks movement entirely.

The obstacle types and their cover/blocking behavior:

| Type | Sizes | Cover | Blocks line of sight |
|---|---|---|---|
| Boulders/rocks | normal/large/huge | Hard | Only at Huge size |
| Trees | normal | Hard | No |
| Bushes | normal | Medium | No |
| High grass | clumps up to 5 | Light | No (passable) |
| Ponds | large/huge | None | No |
| Broken carts | large | Hard | No |
| Fences/walls | lines, straight or L | Medium | No |
| Outside structures | large/huge | Hard | Only at Huge size |

The map generator guarantees at least one of every type appears, then fills in random extras (weighted toward smaller, more common pieces) until a randomized square-budget is hit — the bigger a piece is, the fewer of them show up, so huge/large obstacles stay rare and the map doesn't get cluttered while every cover type is still available somewhere.

### 2. Tiered ranged cover, with real line-of-sight blocking

Ranged attacks (both the player's and monsters') now trace the actual line between attacker and target and apply the worst cover found along the way:

- **Light cover**: −10 to hit (High Grass, or terrain forest as before).
- **Medium cover**: −20 (Bushes, Fences).
- **Hard cover**: −30 (Boulders, Trees, Broken Carts, Structures).

If a Huge Boulder or Huge Structure sits on that line, the shot is blocked outright — no line of sight, no attack roll at all, with a notice explaining why (both for the player and for monsters holding their shot).

### 3. Darker borders on impassable tiles, plus grass/mud ground texture

Every impassable square now gets a thicker black border on any edge that faces open ground, so it's visually obvious at a glance what can and can't be walked through. Multi-square obstacles render seamlessly — no internal grid lines cutting through a single boulder or wall.

Battle maps also now scatter mud patches (a handful of small clumps) alongside the existing grass, matching the way the world map already dresses terrain. (Water is already covered by the guaranteed Pond obstacle, so it wasn't added as a separate ground layer.)

### 4. Monsters now use cover — both to shoot around and to hide behind

Ranged-armed monsters:

- Weight potential targets by how exposed they are — a target with no line of sight is almost never chosen, and a target in hard cover is deprioritized versus an easier, more exposed one.
- Will actively reposition before shooting if a nearby square gives them better cover than where they're standing, as long as it doesn't take their current target out of weapon range.

**True Animals and Bestial creatures are exempted from all of this** — per the follow-up correction, they have no real grasp of tactical cover, so they keep choosing targets and moving exactly as before, cover-blind.

## Where this lives in the code

- `battle_grid.gd` — obstacle generation (shapes, sizes, placement budget), the new `get_ranged_cover()` line-tracing function, and the ground-texture (mud) scatter.
- `battle_grid_view.gd` — the tile rendering: solid fills for mass obstacles (boulders/ponds/carts/structures), icon-over-ground detail for trees/bushes/grass/fences, the thick impassable border pass, and the grass/mud texture.
- `field_encounter_screen.gd` — both ranged-attack code paths now resolve through `get_ranged_cover()` instead of a flat −10; monster target-weighting and the new pre-shot repositioning logic, gated off for animals.

## Testing

Both regression tests pass reliably across repeated runs:

- `BattleObstaclesTest` — footprint sizing, passability, cover tiers, LOS-blocking restricted to Huge boulders/structures, huge shapes never forming a plain rectangle, deployment-zone clearance, mud never overlapping obstacles, and the `get_ranged_cover()`/line-of-sight unit checks.
- `PsychologyTest` — unaffected by this round of work; also re-verified stable (a couple of unrelated test-harness timing races in this internal script were tightened up along the way, not shipped-game bugs).

Full 8-scene headless load check and a full project compile check both came back clean.

## Note on screenshots

I tried to capture an in-engine screenshot of the new obstacle tiles for this doc, but the rendering environment here couldn't produce one this round (a rendering-driver issue in the sandbox, unrelated to the game code itself — even a blank test scene hit the same wall). I can try again if you'd like, but wanted to ship the build rather than hold it up chasing that.
