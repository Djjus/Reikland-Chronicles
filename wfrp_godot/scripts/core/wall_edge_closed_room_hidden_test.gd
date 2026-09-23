extends RefCounted
class_name WallEdgeClosedRoomHiddenTest
## Regression test for the report ("Player can still see room walls
## inside rooms before opening the doors"), sent with a screenshot of a
## dungeon corridor T-junction with short wall-segment lines visibly
## jutting into unexplored black space next to what should be a still-
## closed room.
##
## This is the SAME symptom v0.3.63 fixed once already
## (BattleGridView._wall_edge_visible() routed through _marker_fog() so
## a closed room's own near-face-row corner/side wall segments stop
## leaking through raw fog_of_war) — that fix's own dedicated regression
## test (wall_edge_closed_room_hidden_test.gd, by the same name) is
## missing from the live project entirely, most likely lost the same way
## Character.skill_any_resolved was separately found to be lost this
## same session (this project's cloud session storage has previously
## lost whole version ranges outright — see build_info.gd's own history
## comment). Recreating that lost coverage here, deliberately widened
## well past its original single-room/single-position scope, since a
## narrower recreation wouldn't by itself prove today's fresh report is
## either the exact same already-fixed leak or a new, different one:
##
## - Sweeps MANY freshly generated dungeons (not just one), across every
##   closed-door room each contains, not just the first one found.
## - Positions the FULL PARTY (not just a single lone prober position),
##   spread across multiple corridor cells at once via the real
##   _reveal_around_party() multi-center path — mirroring the report's
##   own screenshot, which shows two party members at different points
##   along a branching corridor near the closed room, not one character
##   standing still.
## - Directly exercises the actual RENDER-TIME gate,
##   BattleGridView._wall_edge_visible() against the real BattleGrid
##   BattleGridView.set_state() just populated (fe.grid_view.grid ==
##   fe.battle_grid) — not just the underlying visibility Dictionary a
##   pure data-layer check could pass on despite a rendering-layer bug,
##   since _wall_edge_visible()/_marker_fog() live one layer further
##   downstream in battle_grid_view.gd and are never touched by the
##   existing dungeon_closed_door_vision_memory_prune_test.gd.
## - Checks EVERY wall_edge_lines entry touching each closed room's own
##   genuinely-interior cells (along > 0 in the door's own facing
##   direction — the near-face row itself is a real, always-visible
##   surface once nearby, same "see the surface, not through it" rule
##   used everywhere else in this fog-of-war system, so it's correctly
##   excluded here too), not just one hand-picked sample cell.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []
	await tree.process_frame
	await tree.process_frame

	var themes: Array[String] = ["sewer", "cave"]
	var rooms_checked := 0
	var wall_edges_checked := 0
	var leaks_found := 0

	for attempt in range(24):
		GameState.reset_world_state()
		GameState.player_character = null
		GameState.ensure_player_character()
		var no_pool: Array[String] = []
		GameState.current_field_difficulty_tier = 0
		GameState.current_field_monster_pool = no_pool
		GameState.current_field_habitat = ""
		GameState.dungeon_state = {}
		GameState.pending_dungeon_theme_id = themes[attempt % themes.size()]
		GameState.dungeon_entry_requested = true

		var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
		tree.get_root().add_child(fe)
		for i in range(8):
			await tree.process_frame

		if not fe._exploration_mode:
			fe.queue_free()
			for i in range(2):
				await tree.process_frame
			continue

		var rooms: Array = fe.dungeon_state.get("rooms", [])
		var closed_rooms: Array = []
		for room in rooms:
			if not room.get("door_open", false) and room.get("door_pos") != null and room.get("door_dir") != null and room.get("rect") != null:
				closed_rooms.append(room)

		for room in closed_rooms:
			rooms_checked += 1
			var anchor: Vector2i = room["door_pos"]
			var dir: Vector2i = room["door_dir"]
			var rect: Rect2i = room["rect"]
			var perp: Vector2i = Vector2i(0, 1) if dir.x != 0 else Vector2i(1, 0)
			var outside_pos: Vector2i = anchor - dir

			## Spread the whole party out near the junction, mirroring the
			## report's own screenshot (party members at different points
			## along the corridor, not one lone stationary prober): one
			## member right outside the door, the rest a couple of cells
			## further back/sideways along the corridor if those cells
			## exist as real floor -- falls back to stacking on the same
			## cell (still a valid, if less thorough, case) when the
			## dungeon is too small for that.
			fe.battle_positions.clear()
			var party_spots: Array[Vector2i] = [outside_pos, outside_pos - dir, outside_pos + perp, outside_pos - perp]
			var i := 0
			for member in GameState.party:
				var spot: Vector2i = party_spots[i % party_spots.size()]
				if fe.battle_grid != null and fe.battle_grid.cell_texture.has(spot):
					fe.battle_positions[member] = spot
				else:
					fe.battle_positions[member] = outside_pos
				i += 1
			if not fe.battle_positions.has(fe.player):
				fe.battle_positions[fe.player] = outside_pos

			fe._reveal_around_party()
			for i2 in range(2):
				await tree.process_frame
			fe._render_status()
			for i2 in range(2):
				await tree.process_frame

			var grid: BattleGrid = fe.grid_view.grid
			checks.append(["room #%d: BattleGridView.grid is the same live grid FieldEncounter is using" % rooms_checked, grid == fe.battle_grid])
			if grid == null:
				continue

			for edge in grid.wall_edge_lines:
				var cells: Array = edge.get("cells", [])
				if cells.size() != 2:
					continue
				var touches_interior := false
				for cell in cells:
					var c: Vector2i = cell
					if not rect.has_point(c):
						continue
					var diff: Vector2i = c - anchor
					var along: int = diff.x * dir.x + diff.y * dir.y
					if along > 0:
						touches_interior = true
				if not touches_interior:
					continue
				wall_edges_checked += 1
				var visible: bool = fe.grid_view._wall_edge_visible(edge)
				if visible:
					leaks_found += 1
					checks.append(["room #%d: wall edge touching an interior cell %s stays hidden while the door is closed" % [rooms_checked, str(cells)], false])

		fe.queue_free()
		for i in range(3):
			await tree.process_frame

	checks.append(["swept a real number of closed-door rooms across the 24 generated dungeons", rooms_checked >= 10])
	checks.append(["swept a real number of interior wall-edge segments across those rooms", wall_edges_checked >= 5])

	print("--- Wall Edge Closed Room Hidden sweep: %d rooms, %d interior wall edges checked, %d leaks found ---" % [rooms_checked, wall_edges_checked, leaks_found])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Wall Edge Closed Room Hidden): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
