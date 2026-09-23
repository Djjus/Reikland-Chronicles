# NPCs still standing on mismatched ground tiles — v0.3.78

## Request

"NPCs in houses are still standing on mud tiles" — with two screenshots of a house interior (wood-plank walls, wood-plank floor) showing a human character and a small white/pink creature both standing on a visibly different, flatter/browner floor tile than the rest of the room. The word "still" pointed at a recurrence of `npc_ground_tile_mismatch_fix_v0.3.45.md`, an earlier fix for this exact class of bug.

## Root cause: the v0.3.45 fix was gone from the live file

Before touching anything, the device's actual current `scripts/game/overworld.gd` was re-staged fresh (not trusted from the local working copy, which was known stale for this specific file) and checked directly: `NPC_MARKER_CHARS` and `_natural_ground_char_for_npc_marker()` — the constant and helper function v0.3.45 added — were completely absent. `TILE_ATLAS` still had the original bug's mapping (`"@"`, `"N"`, `"H"`, `"S"`, `"Y"` all → `Vector2i(1, 0)`, a plain bare-path tile), and `_build_map()`'s ground-painting loop had no special case for any of these letters at all — they fell straight into the generic `else:` branch and got painted with that raw bare-path tile regardless of what surrounded them, exactly reproducing the original bug.

In other words: the fix genuinely shipped once (v0.3.45's own doc has the verification), but was lost at some point in a later change to `_build_map()` that didn't carry it forward — and because v0.3.45's own verification was a one-off headless scratch test, never saved as a real regression-suite file, nothing caught the regression when it happened. This "still" report is that exact loss made visible.

## The fix (restored, plus one deliberate scope addition)

Re-added, functionally identical to v0.3.45:

- `NPC_MARKER_CHARS` constant and `_natural_ground_char_for_npc_marker(coords)` helper in `overworld.gd`. Indoors (the marker's tile falls inside a real building footprint), it returns that building's own real floor material — `"F"` (paved stone) if the building contains a stone `"K"` wall tile, otherwise `"n"` (wood-plank floor) — the same rule `_paint_building_interiors()` already applies to every ordinary interior cell. Outdoors, it looks at the tile's four orthogonal neighbours and picks whichever real, paintable ground character is most common among them (ignoring other markers, building/wall tiles, water, the fence, and the static lamp), falling back to plain grass `"."` only if nothing qualifies.
- A new `elif ch in NPC_MARKER_CHARS:` branch in `_build_map()`'s ground-painting pass (same shape as the existing `"I"`/static-lamp special cases): resolves the natural ground character, writes it back into `tile_chars[coords]` (so shore/mud edge blending on neighbouring cells and every other downstream reader sees real terrain, not a leftover spawn letter), and paints the ground layer with it directly.

**Scope addition this time:** `"@"` (the player's own start tile) is folded into `NPC_MARKER_CHARS` now too. It has the exact same `Vector2i(1,0)` bug and was explicitly flagged as such in the v0.3.45 doc, but left out of scope on the reasoning that nobody had reported it. Given this is a recurrence of the same bug family, closing that known loose end at the same time (at effectively zero extra cost — it's the same helper function) seemed worth doing rather than leaving a second latent copy of the identical issue.

## Testing

New `npc_marker_ground_tile_test.gd` (persisted this time, unlike v0.3.45's throwaway scratch test — so a future regression like this one gets caught automatically): loads the real `Overworld.tscn` against `giessingen_village.tres` and checks all five marker positions directly against the map's own real data —

- `H` (trainer, all-grass neighbours) and `N` (traveller, all-grass neighbours) → both resolve to plain grass `"."`.
- `Y` (priest) and `S` (shopkeeper), both genuinely inside their own timber-walled buildings (neither has a `"K"` stone wall) → both resolve to `"n"` (wood-plank floor).
- `"@"` (player start, on the mud path south of the buildings — neighbours `G`/`G`/`G` plus one wall tile, excluded) → resolves to `"G"` (mud path), its real majority-neighbour terrain.
- Confirms Building A/B's own rects are unaffected (cross-check against `building_wall_walkable_test.gd`'s own already-verified building geometry on this same map).

12 checks, all passing. Also re-ran the full regression suite (507 checks across 21 suites — this test plus the also-shipped Blessing Overcast suite included) 3 consecutive times: 0 failures each run.

A headless screenshot (player warped into Building A, next to the `"Y"` priest marker) confirms the fix visually — both the player and the priest NPC (a small white/pink creature portrait, matching the report's own screenshot) now stand on the same clean wood-plank floor as the rest of the room, with no mismatched patch underneath either of them.

## Files changed/pushed to the device

- `scripts/game/overworld.gd` (`NPC_MARKER_CHARS` restored + expanded to include `"@"`, `_natural_ground_char_for_npc_marker()` restored, new ground-painting branch in `_build_map()`)
- `scripts/core/npc_marker_ground_tile_test.gd` (new, persisted regression test) + `.gd.uid`
- `scripts/core/build_info.gd` (v0.3.77 → v0.3.78)

Pushed via `device_commit_files`, guarded by fresh `expectedMtimeMs` on every pre-existing file; all 8 files in this push (this fix plus the Blessing Overcast feature shipped in the same push — see `blessing_overcast_v0.3.78.md`) succeeded, none rejected.
