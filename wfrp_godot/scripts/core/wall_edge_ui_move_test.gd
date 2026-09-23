extends RefCounted
class_name WallEdgeUIMoveTest
## Diagnostic: wall_edge_real_generator_test.gd proves BattleGrid's own
## find_path()/reachable_squares()/has_line_of_sight() all correctly
## refuse a sealed pad-cell wall_edge boundary, straight from real
## DungeonGenerator output (with and without a save/load round trip).
## This test goes one level up and drives the REAL exploration-mode UI
## flow (_start_exploration_mode -> _enter_move_mode -> a real
## square_clicked -> _try_commit_move) that a player's actual mouse
## click goes through, with a real multi-member party (so a second,
## currently-inactive ally is also on the grid, matching the user's own
## screenshot showing two separate party tokens), to catch anything
## that's only wrong at the UI layer even though the underlying
## BattleGrid math checks out in isolation.

static func run_test(fe) -> bool:
	var checks: Array = []

	## A real two-member party so a second, currently-inactive ally sits
	## on the grid too, same shape as the user's own screenshot.
	GameState.party.clear()
	GameState.player_character = null
	GameState.ensure_player_character()
	var leader: Character = GameState.player_character
	leader.character_name = "Eric T"
	var ally := Character.new()
	ally.character_name = "Davrin"
	ally.race = leader.race
	ally.characteristics = leader.characteristics.duplicate()
	ally.allegiance = "ally"
	ally.wounds_max = 10
	ally.wounds_current = 10
	ally.equipped_weapon = "Sword"
	GameState.add_party_member(ally)

	GameState.dungeon_state = {}
	GameState.pending_dungeon_theme_id = "sewer"
	GameState.dungeon_entry_requested = true   ## real dungeon-entry signal, see that field's own header comment
	## Force a real, deterministic dungeon (not a hand-built grid) so
	## the exact geometry the generator actually produces is exercised.
	var theme: DungeonThemeDefinition = GameData.dungeon_themes.get("sewer")
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var state: Dictionary = DungeonGenerator.generate(theme, rng)
	checks.append(["setup: a real dungeon was generated", not state.is_empty()])
	if state.is_empty():
		print("RESULT (Wall Edge UI Move): SETUP FAILED")
		return false
	GameState.dungeon_state = state

	fe._start_exploration_mode()
	for i in range(3):
		await fe.get_tree().process_frame

	## Fully reveal fog-of-war so the click target is guaranteed visible
	## (this test is about movement/LOS enforcement, not fog gating).
	var full_vis: Dictionary = fe.dungeon_state.get("visibility", {})
	var grid_rows: Array = fe.dungeon_state.get("grid_rows", [])
	for y in range(grid_rows.size()):
		var row: String = grid_rows[y]
		for x in range(row.length()):
			full_vis[Vector2i(x, y)] = 2
	fe.dungeon_state["visibility"] = full_vis
	fe._refresh_dungeon_battle_grid()
	for i in range(2):
		await fe.get_tree().process_frame

	## Find a real sealed pad-cell boundary from the LIVE battle_grid
	## this exact screen is using for movement right now. Per the
	## follow-up request ("add grey walls to all outer edges of the
	## dungeon tiles"), wall_edge_lines now also carries an entry for
	## every real floor-to-wall boundary (BattleGrid.
	## _build_outer_wall_edge_lines()) on top of the original sealed
	## walkable/walkable pad-cell case this test is actually about — so
	## this can no longer just grab index 0 blind; it specifically hunts
	## for a walkable/walkable pair (the "genuine wall/void neighbour"
	## entries fail that by design, same reasoning
	## WallEdgeRealGeneratorTest's own check 0 uses to skip them).
	var face_cell: Vector2i = Vector2i(-999, -999)
	var corridor_cell: Vector2i = Vector2i(-999, -999)
	var found_pad_cell_edge := false
	for edge in fe.battle_grid.wall_edge_lines:
		var cells: Array = edge["cells"]
		var a: Vector2i = cells[0]
		var b: Vector2i = cells[1]
		if fe.battle_grid.is_walkable(a) and fe.battle_grid.is_walkable(b):
			face_cell = a
			corridor_cell = b
			found_pad_cell_edge = true
			break
	checks.append(["setup: the live battle_grid has at least one sealed walkable/walkable wall_edge_lines entry to test", found_pad_cell_edge])
	if not found_pad_cell_edge:
		print("RESULT (Wall Edge UI Move): SETUP FAILED (no walkable/walkable wall_edge_lines entry in this seed)")
		return false
	checks.append(["setup: both sides of the chosen boundary are independently walkable (the real pad-cell case)", fe.battle_grid.is_walkable(face_cell) and fe.battle_grid.is_walkable(corridor_cell)])

	## Whoever's turn it is right now, teleport them right onto the
	## face_cell (bypassing normal movement to set up the test position)
	## and try to walk them straight across the sealed boundary via the
	## exact same signal a real mouse click on the map fires.
	var mover: Character = fe.player
	var others_blocked: Dictionary = {}
	for c in fe.battle_positions.keys():
		if c != mover:
			others_blocked[fe.battle_positions[c]] = true
	fe.battle_positions[mover] = face_cell
	## Movement capped at 1 square deliberately -- with a normal full
	## Movement budget, corridor_cell would legitimately show up in
	## reachable_squares anyway via some OTHER legal route through the
	## rest of the connected dungeon (it's real corridor floor, after
	## all), which would make this test's own assertions meaningless.
	## Capping at 1 isolates exactly the question this test is actually
	## asking: is a DIRECT one-step crossing of the sealed boundary ever
	## offered or allowed.
	fe.movement_remaining = 1
	fe.action_used_this_turn = false
	fe.awaiting_player_target = true
	fe._enter_move_mode()
	for i in range(2):
		await fe.get_tree().process_frame

	checks.append(["THE FIX: the sealed-edge corridor cell is NOT among the real reachable-squares move-mode ever offers", not fe._move_mode_reachable.has(corridor_cell)])

	## Fire the exact signal a real player click on that square emits.
	fe._on_grid_square_clicked(corridor_cell)
	for i in range(3):
		await fe.get_tree().process_frame

	checks.append(["a real player click straight across the sealed boundary is refused -- the mover never actually lands on the far side", fe.battle_positions.get(mover, Vector2i(-999, -999)) != corridor_cell])
	checks.append(["the mover is still exactly where they started (face_cell) -- the click was a genuine no-op, not a partial/silent move", fe.battle_positions.get(mover, Vector2i(-999, -999)) == face_cell])

	## Vision: even standing right on face_cell, the far cell across the
	## sealed boundary should read as boundary-only (visible surface),
	## never a fully "reached" lit interior cell you could see past.
	fe._exit_move_mode()
	fe._handle_exploration_move_arrival(face_cell)
	for i in range(2):
		await fe.get_tree().process_frame
	var vis: Dictionary = fe.dungeon_state.get("visibility", {})
	## The far cell is still marked visible (it's a real surface you can
	## see FROM the near side), but nothing BEYOND it should have been
	## freshly reached by light passing through the sealed edge -- check
	## by re-deriving what a light_bfs from face_cell alone would reach,
	## and confirming corridor_cell lands in `boundary`, not `reached`.
	var reached: Dictionary = {}
	var boundary: Dictionary = {}
	fe._light_bfs(face_cell, 10, reached, boundary)
	checks.append(["light cast from the near side treats the far cell as a boundary surface, not a reached-through interior cell", boundary.has(corridor_cell) and not reached.has(corridor_cell)])

	fe.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Wall Edge UI Move): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
