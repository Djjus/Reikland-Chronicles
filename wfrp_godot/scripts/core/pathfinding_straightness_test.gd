extends RefCounted
class_name PathfindingStraightnessTest
## Regression test for the follow-up request ("let make movement pathing
## always take the direct Straight path over angles"): BattleGrid.find_path()
## already tried direct_line() first when nothing's in the way (see that
## function's own comment), but its BFS fallback -- used once an obstacle
## actually blocks the straight line -- used to record a single `came_from`
## parent per cell (whichever neighbor happened to discover it first, a
## pure artifact of the dy/dx scan order), with no preference for how
## direct-looking the detour was. That could pick a shortest path that
## swings much farther from the straight line than necessary, reading as a
## sharp-angled dogleg rather than a route hugging the obstacle as tightly
## as the geometry allows.
##
## Deterministic setup: a 2-row-tall wall block sits across the straight
## line between `from` and `to` (both on the same row). The row directly
## below the block is open (a 1-row detour clears it); the block also
## covers the row directly above, so clearing it that way needs a 2-row
## detour instead. Both directions cost the exact same number of total
## steps (an 8-directional grid can "absorb" a shallow detour into
## existing diagonal moves for free either way, so the naive shortest-path
## length doesn't distinguish them) -- only the actual choice of route
## reveals whether the straightness tie-break is doing anything.

static func run_test(_tree) -> bool:
	var checks: Array = []

	var theme: DungeonThemeDefinition = GameData.dungeon_themes.get("sewer")
	if theme == null:
		print("RESULT (Pathfinding Straightness): SETUP FAILED (no sewer theme)")
		return false
	var w := theme.wall_char
	var f := theme.floor_char

	## y=0: open. y=1,2: a wall block at x=3..5 (blocks the straight line
	## at y=2, and also blocks the shallower y=1 detour). y=3,4: open --
	## the only "cheap" (1-row) detour is downward, through y=3.
	var rows: Array = [
		f + f + f + f + f + f + f + f + f,
		f + f + f + w + w + w + f + f + f,
		f + f + f + w + w + w + f + f + f,
		f + f + f + f + f + f + f + f + f,
		f + f + f + f + f + f + f + f + f,
	]
	var grid := BattleGrid.new()
	grid.generate_from_dungeon_grid(theme, rows, {})

	var from := Vector2i(0, 2)
	var to := Vector2i(8, 2)
	checks.append(["setup: both endpoints are genuinely walkable", grid.is_walkable(from) and grid.is_walkable(to)])
	checks.append(["setup: the straight line between them is genuinely blocked", not grid.has_clear_direct_path(from, to)])

	var path: Array = grid.find_path(from, to)
	checks.append(["find_path() found a real path", not path.is_empty()])
	checks.append(["the path actually reaches the destination", not path.is_empty() and path[path.size() - 1] == to])
	## 8-directional Chebyshev distance is 8 (pure horizontal) -- a
	## detour of only 1 or 2 rows fits inside that budget for free by
	## using diagonal steps instead of straight ones, so a correctly
	## shortest path is still exactly 8 steps long regardless of which
	## side it detours around.
	checks.append(["the path is genuinely shortest (8 steps, not padded out by the detour)", path.size() == 8])

	var max_deviation := 0
	for sq in path:
		max_deviation = maxi(max_deviation, absi(sq.y - from.y))
	## THE FIX: of the two equally-short detours, the straightness
	## tie-break picks whichever stays closest to the line -- here, the
	## 1-row dip through y=3, not the 2-row swing through y=0.
	checks.append(["THE FIX: the path takes the shallower (1-row) detour, not the deeper (2-row) one", max_deviation == 1])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Pathfinding Straightness): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
