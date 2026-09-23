extends RefCounted
class_name ImpassableDiagonalCornerCutTest
## Regression test for the reported bug ("second player can target the
## inside of the room to move too. third moving through wall is still
## possible. the whole time the door is still closed" + the follow-up
## "monsters are also moving through the walls and shouldnt be able
## too").
##
## ROOT CAUSE (confirmed by reading BattleGrid._edge_blocked_diagonal()):
## this project already has a "no corner-cutting" rule for wall_edges
## (the sealed pad-cell boundary case — see battle_grid_wall_edges_test.gd/
## wall_edge_real_generator_test.gd, both already passing) — but that
## same corner-cut check NEVER considered a flank cell being a plain,
## genuinely SOLID impassable cell (an ordinary dungeon wall, or a
## closed door — both set impassable[square]=true in
## generate_from_dungeon_grid()). _footprint_walkable()/_footprint_
## clear() only ever check the DESTINATION cell's own walkability, so
## nothing anywhere stopped a diagonal step from cutting straight
## across the corner of a solid wall or a closed door as long as the
## far cell itself was open floor. This let a player's Move preview
## (reachable_squares(), used by move-mode's highlight+hover-preview)
## and a monster's own AI pathing (_advance_toward() -> the exact same
## reachable_squares()/find_path()) both slip diagonally around a
## closed door's or a dungeon wall's corner into ground that was never
## actually walked through.
##
## THE FIX: _edge_blocked_diagonal() now also treats either flank cell
## being impassable as blocking the diagonal corner-cut, the same "one
## blocked flank is enough" rule already used for sealed wall_edges.
##
## Case A: a small hand-built synthetic grid (deterministic, easy to
## reason about) — a single wall cell with two open diagonal neighbors
## must refuse a direct diagonal hop between them.
## Case B: the real DungeonGenerator, many seeds — sweeps every
## impassable cell (ordinary walls AND closed doors alike) in each
## generated dungeon and confirms no diagonal corner-cut past it is
## ever offered by find_path()/reachable_squares(), with a dedicated
## count of how many of those impassable cells were specifically
## closed-door cells (the exact case from the bug report).

const RUNS := 25

static func run_test(_tree) -> bool:
	var checks: Array = []

	## --- Case A: hand-built synthetic grid ------------------------------
	var theme: DungeonThemeDefinition = GameData.dungeon_themes.get("sewer")
	if theme == null:
		print("RESULT (Impassable Diagonal Corner Cut): SETUP FAILED (no sewer theme)")
		return false

	var w := theme.wall_char
	var f := theme.floor_char
	## A 3x3 patch: a single wall cell dead center, floor everywhere else.
	## (1,0) and (2,1) are the two orthogonal neighbours flanking the NE
	## corner of the wall at (1,1) -- a diagonal hop straight between them
	## visibly cuts across that wall's own corner.
	var synth_rows: Array = [
		f + f + f,
		f + w + f,
		f + f + f,
	]
	var synth_grid := BattleGrid.new()
	synth_grid.generate_from_dungeon_grid(theme, synth_rows, {})

	var n := Vector2i(1, 0)
	var e := Vector2i(2, 1)
	checks.append(["Case A setup: both flank cells are genuinely walkable on their own", synth_grid.is_walkable(n) and synth_grid.is_walkable(e)])
	checks.append(["THE FIX: _edge_blocked_diagonal() now refuses a diagonal cut across a solid wall's own corner", synth_grid._edge_blocked_diagonal(n, e)])
	var synth_path: Array = synth_grid.find_path(n, e, {}, 1)
	checks.append(["THE FIX: find_path() no longer offers a direct 1-step diagonal hop around the wall's corner", synth_path.size() != 1])
	var synth_reachable: Array = synth_grid.reachable_squares(n, 1, {}, 1)
	checks.append(["THE FIX: reachable_squares() (what Move-mode highlights) no longer includes the far corner in 1 step", not synth_reachable.has(e)])

	## --- Case B: the real DungeonGenerator, many seeds ------------------
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var total_impassable_checked := 0
	var total_door_cells_checked := 0
	var all_corners_blocked := true
	var all_find_path_refused := true
	var mismatches: Array = []

	for run_i in range(RUNS):
		var state: Dictionary = DungeonGenerator.generate(theme, rng)
		if state.is_empty():
			continue
		var rooms: Array = state.get("rooms", [])
		var grid_rows: Array = state.get("grid_rows", [])
		var visibility: Dictionary = state.get("visibility", {})
		for y in range(grid_rows.size()):
			var row: String = grid_rows[y]
			for x in range(row.length()):
				visibility[Vector2i(x, y)] = 2   ## fully reveal -- fog must never mask a real bug here

		var grid := BattleGrid.new()
		grid.generate_from_dungeon_grid(theme, grid_rows, visibility, rooms)

		## Every closed door cell, for the dedicated door-specific count.
		var door_cell_set: Dictionary = {}
		for room in rooms:
			if room.get("door_open", false):
				continue   ## only a CLOSED door is the reported bug's own case
			var anchor_v = room.get("door_pos")
			var dir_v = room.get("door_dir")
			if anchor_v == null or dir_v == null or Vector2i(dir_v) == Vector2i.ZERO:
				continue
			var anchor: Vector2i = anchor_v
			var dir: Vector2i = dir_v
			var perp: Vector2i = Vector2i(0, 1) if dir.x != 0 else Vector2i(1, 0)
			for i in range(DungeonGenerator.CORRIDOR_SCALE):
				door_cell_set[anchor + perp * i] = true

		for y in range(grid.rows):
			for x in range(grid.cols):
				var wall_sq := Vector2i(x, y)
				if not grid.impassable.has(wall_sq):
					continue
				total_impassable_checked += 1
				var is_door_cell: bool = door_cell_set.has(wall_sq)
				if is_door_cell:
					total_door_cells_checked += 1
				## The 4 diagonal corners this impassable cell could let a
				## mover cut across, each defined by its own pair of
				## orthogonal flanking neighbours.
				var flank_pairs := [
					[Vector2i(x, y - 1), Vector2i(x + 1, y)],
					[Vector2i(x, y - 1), Vector2i(x - 1, y)],
					[Vector2i(x, y + 1), Vector2i(x + 1, y)],
					[Vector2i(x, y + 1), Vector2i(x - 1, y)],
				]
				for pair in flank_pairs:
					var na: Vector2i = pair[0]
					var nb: Vector2i = pair[1]
					if not grid.is_in_bounds(na) or not grid.is_in_bounds(nb):
						continue
					if not grid.is_walkable(na) or not grid.is_walkable(nb):
						continue   ## one of the flanks is itself blocked for an unrelated reason -- not what this check is isolating
					if not grid._edge_blocked_diagonal(na, nb):
						all_corners_blocked = false
						mismatches.append("corner NOT blocked around %s (door=%s) between %s/%s (run %d)" % [wall_sq, is_door_cell, na, nb, run_i])
						continue
					var direct: Array = grid.find_path(na, nb, {}, 1)
					if not direct.is_empty() and direct.size() == 1:
						all_find_path_refused = false
						mismatches.append("find_path allowed a direct 1-step diagonal cut around %s (door=%s) between %s -> %s (run %d)" % [wall_sq, is_door_cell, na, nb, run_i])

	checks.append(["ran %d dungeons and checked at least one impassable cell's diagonal corners" % RUNS, total_impassable_checked > 0])
	checks.append(["...including at least one genuinely closed-door cell (the exact case from the bug report)", total_door_cells_checked > 0])
	checks.append(["THE FIX: no diagonal corner-cut is ever left unblocked around any wall or closed-door cell", all_corners_blocked])
	checks.append(["THE FIX: find_path() never offers a direct 1-step diagonal hop around any wall or closed-door corner", all_find_path_refused])

	print("Impassable cells checked across %d runs: %d (of which closed-door cells: %d)" % [RUNS, total_impassable_checked, total_door_cells_checked])
	for m in mismatches.slice(0, 20):
		print("  MISMATCH: ", m)

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Impassable Diagonal Corner Cut): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
