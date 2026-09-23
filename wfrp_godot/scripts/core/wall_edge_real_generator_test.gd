extends RefCounted
class_name WallEdgeRealGeneratorTest
## Diagnostic: battle_grid_wall_edges_test.gd proves the wall_edges
## mechanic works on a HAND-BUILT grid (bypassing DungeonGenerator's own
## randomness entirely, per that file's own header comment). This test
## instead runs the REAL DungeonGenerator across many seeds and many
## real rooms per dungeon, feeding its actual output straight into
## BattleGrid.generate_from_dungeon_grid() exactly the way
## _refresh_dungeon_battle_grid() does in real gameplay, to catch any
## integration mismatch the isolated hand-built test can't see -- e.g.
## a room whose real door_pos/door_dir/rect combination produces a
## wall_edge_lines entry that _edge_blocked()/find_path() don't
## actually agree with. Also round-trips every generated dungeon
## through DungeonGenerator.to_save_data()/from_save_data() first --
## the exact path a real "re-enter an already-generated dungeon"
## (Character.to_save_dict/from_save_dict, per game_state.gd's own
## comment on dungeon_state) goes through on every save/reload -- since
## that's a code path this project's other wall_edges tests never
## exercise at all.

const RUNS := 40

static func run_test(_tree) -> bool:
	var checks: Array = []
	var theme: DungeonThemeDefinition = GameData.dungeon_themes.get("sewer")
	if theme == null:
		print("RESULT (Wall Edge Real Generator): SETUP FAILED (no sewer theme)")
		return false

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var total_wall_edge_lines := 0
	var all_lines_match_wall_edges := true
	var all_lines_block_find_path := true
	var all_lines_block_diagonal_cut := true
	var all_lines_block_los := true
	var mismatches: Array = []

	for run_i in range(RUNS):
		var state: Dictionary = DungeonGenerator.generate(theme, rng)
		if state.is_empty():
			continue
		## Round-trip through the exact save/load path a real "re-enter an
		## already-generated dungeon" (Character.to_save_dict/from_save_dict,
		## which call these) goes through, per game_state.gd's own comment
		## on dungeon_state -- exercises whatever the disk save/reload path
		## does that a purely in-memory session (like this test's earlier
		## runs) never touches at all.
		state = DungeonGenerator.from_save_data(DungeonGenerator.to_save_data(state))
		var rooms: Array = state.get("rooms", [])
		var grid_rows: Array = state.get("grid_rows", [])
		var visibility: Dictionary = state.get("visibility", {})
		## Fully reveal so any fog-of-war gating never masks a real bug.
		for y in range(grid_rows.size()):
			var row: String = grid_rows[y]
			for x in range(row.length()):
				visibility[Vector2i(x, y)] = 2

		var grid := BattleGrid.new()
		grid.generate_from_dungeon_grid(theme, grid_rows, visibility, rooms)

		total_wall_edge_lines += grid.wall_edge_lines.size()
		for edge in grid.wall_edge_lines:
			var cells: Array = edge["cells"]
			var face_cell: Vector2i = cells[0]
			var corridor_cell: Vector2i = cells[1]

			## 0. Per the follow-up request ("add grey walls to all outer
			## edges of the dungeon tiles"): wall_edge_lines now also
			## carries an entry for every real floor-cell-to-wall-cell
			## boundary (BattleGrid._build_outer_wall_edge_lines()) —
			## the map's own outer perimeter, dead-end corridor caps, any
			## room wall not next to a door — on top of the original
			## "sealed pad-cell between two walkable cells" case this
			## test was written for. Those blank-wall-side entries are a
			## genuinely different mechanism (blocked by the wall cell's
			## own `impassable` entry, never registered in `wall_edges`
			## at all, deliberately — see that function's own comment),
			## so this whole test — which specifically verifies the
			## wall_edges/find_path/diagonal-cut/LOS mechanism — only
			## ever applies to the walkable/walkable pairs, exactly like
			## check 2 already singled out below. Moved ahead of check 1
			## so an outer-wall entry skips the wall_edges agreement
			## check too, not just the pad-cell walkability check.
			if not grid.is_walkable(face_cell) or not grid.is_walkable(corridor_cell):
				continue   ## a genuinely different case (e.g. hazard overlap, or a real wall/void neighbour) -- not what this test is checking

			## 1. The rendered line and the real wall_edges dict must
			## agree -- if wall_edge_lines says a boundary is sealed,
			## _edge_blocked() must say so too (both directions).
			if not grid._edge_blocked(face_cell, corridor_cell) or not grid._edge_blocked(corridor_cell, face_cell):
				all_lines_match_wall_edges = false
				mismatches.append("edge_blocked mismatch at %s/%s (run %d)" % [face_cell, corridor_cell, run_i])

			## 2. Both cells must themselves stay independently
			## walkable (the pad-cell design -- only the EDGE is
			## sealed) -- otherwise this wouldn't be a wall_edge case
			## at all, it'd just be a normal impassable cell. (Already
			## verified by check 0 above; kept here as a no-op guard so
			## this line's own history/intent stays visible in place.)
			if not grid.is_walkable(face_cell) or not grid.is_walkable(corridor_cell):
				continue

			## 3. find_path() must never report a path that steps
			## straight from one to the other (footprint_size 1, the
			## normal player case).
			var direct: Array = grid.find_path(face_cell, corridor_cell, {}, 1)
			if not direct.is_empty() and direct.size() == 1:
				all_lines_block_find_path = false
				mismatches.append("find_path allowed a direct 1-step crossing at %s -> %s (run %d)" % [face_cell, corridor_cell, run_i])

			## 4. No diagonal hop can cut around the same corner either
			## (explicit diagonal neighbors of face_cell that land
			## adjacent to corridor_cell around the corner).
			var delta: Vector2i = corridor_cell - face_cell
			var diag_candidates: Array = []
			if delta.x != 0:
				diag_candidates = [face_cell + Vector2i(delta.x, 1), face_cell + Vector2i(delta.x, -1)]
			else:
				diag_candidates = [face_cell + Vector2i(1, delta.y), face_cell + Vector2i(-1, delta.y)]
			for dc in diag_candidates:
				if grid.is_walkable(dc) and grid._edge_blocked_diagonal(face_cell, dc):
					## it's correctly flagged as blocked -- fine. We're
					## checking for the ABSENCE of a check, so verify
					## find_path also genuinely can't reach corridor_cell
					## by routing face_cell -> dc -> corridor_cell in one
					## diagonal-adjacent hop from dc.
					if grid.is_walkable(dc) and not grid._edge_blocked(dc, corridor_cell) and BattleGrid.footprint_distance(dc, 1, corridor_cell, 1) <= 1:
						## dc is diagonally adjacent to corridor_cell with
						## no sealed edge between THEM specifically -- the
						## corner-cut protection is what's supposed to
						## stop face_cell -> dc -> corridor_cell from ever
						## being offered as a legal 2-step move in the
						## first place at the corner itself. Confirm via
						## a real find_path from face_cell to corridor_cell
						## that no route sneaks through dc.
						var path_via_dc: Array = grid.find_path(face_cell, corridor_cell, {}, 1)
						if not path_via_dc.is_empty() and path_via_dc.size() <= 2 and path_via_dc.has(dc):
							all_lines_block_diagonal_cut = false
							mismatches.append("a path via diagonal %s crossed the sealed corner at %s/%s (run %d)" % [dc, face_cell, corridor_cell, run_i])

			## 5. Line of sight must also be blocked straight across.
			if grid.has_line_of_sight(face_cell, corridor_cell):
				all_lines_block_los = false
				mismatches.append("has_line_of_sight allowed straight across %s -> %s (run %d)" % [face_cell, corridor_cell, run_i])

	checks.append(["ran %d dungeons and saw at least one wall_edge_lines entry to check" % RUNS, total_wall_edge_lines > 0])
	checks.append(["every rendered wall_edge_lines entry has a matching sealed wall_edges entry (both directions)", all_lines_match_wall_edges])
	checks.append(["find_path() never allows a direct 1-step crossing of a sealed pad-cell boundary", all_lines_block_find_path])
	checks.append(["no diagonal hop is ever offered as a real path around a sealed corner", all_lines_block_diagonal_cut])
	checks.append(["has_line_of_sight() never allows a straight look across a sealed pad-cell boundary", all_lines_block_los])

	print("Total wall_edge_lines checked across %d runs: %d" % [RUNS, total_wall_edge_lines])
	for m in mismatches:
		print("  MISMATCH: ", m)

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Wall Edge Real Generator): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
