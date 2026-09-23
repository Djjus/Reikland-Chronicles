extends RefCounted
class_name ChasmJumpActionTest
## Regression test for the request ("Chasm's should span the width (not
## length) or rooms they are in. Also do not let a player move into or
## over a chasm, when they are beside it they should have a button to
## Jump the chasm"). Generates real dungeons (real random seeds, same
## generator the game actually uses) until one comes up with a Chasm
## room, then drives a live FieldEncounter through the whole new
## mechanic:
##   (a) a chasm cell is never a legal Move destination any more —
##       BattleGrid.reachable_squares()/find_path() both refuse it, the
##       same way a solid wall would (chasm cells are marked impassable
##       in BattleGrid._build_hazard_markers());
##   (b) _adjacent_chasm_jump() only reports the Jump action available
##       when the player is genuinely standing beside the chasm, and
##       computes the correct far-side landing cell;
##   (c) a guaranteed-success Athletics Test (Agility 100 -> target 100,
##       every roll 1-100 succeeds) actually moves the character across
##       to that landing cell;
##   (d) a guaranteed-FAILURE Athletics Test (Agility 0 -> target 0,
##       success would need a roll <= 0, impossible) leaves the
##       character exactly where they stood and damages them instead.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	var theme: DungeonThemeDefinition = GameData.dungeon_themes.get("sewer")
	checks.append(["sewer theme is registered in GameData", theme != null])
	if theme == null:
		print("RESULT (Chasm Jump Action): SOME FAILED (theme missing, aborting)")
		return false

	var state: Dictionary = {}
	var chasm_room: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	for attempt in range(300):
		rng.seed = 5000 + attempt
		var candidate: Dictionary = DungeonGenerator.generate(theme, rng)
		for room in candidate.get("rooms", []):
			if room.get("hazard_type", "none") == "chasm" and room.get("hazard_cells", []).size() > 0:
				state = candidate
				chasm_room = room
				break
		if not state.is_empty():
			break
	checks.append(["found a generated dungeon with a Chasm room within 300 attempts", not state.is_empty()])
	if state.is_empty():
		print("RESULT (Chasm Jump Action): SOME FAILED (no chasm room found, aborting)")
		return false

	var hazard_cells: Array = chasm_room.get("hazard_cells", [])
	checks.append(["the Chasm's hazard_cells span exactly the room's 4-cell width", hazard_cells.size() == 4])

	## Find a standable (walkable, non-chasm) cell orthogonally adjacent
	## to one of the chasm's own cells, with a genuinely walkable far
	## side to land on — the exact spot the "Jump the Chasm" button
	## should appear from.
	var chasm_set: Dictionary = {}
	for c in hazard_cells:
		chasm_set[c] = true
	var grid_rows: Array = state.get("grid_rows", [])

	var stand_pos := Vector2i(-1, -1)
	var expected_landing := Vector2i(-1, -1)
	for c in hazard_cells:
		for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var cand: Vector2i = c + dir
			if chasm_set.has(cand):
				continue
			if not _is_open_cell(grid_rows, theme, cand):
				continue
			var land: Vector2i = c - dir
			while chasm_set.has(land):
				land -= dir
			if not _is_open_cell(grid_rows, theme, land):
				continue
			stand_pos = cand
			expected_landing = land
			break
		if stand_pos != Vector2i(-1, -1):
			break
	checks.append(["found a standable cell beside the Chasm with a valid far-side landing", stand_pos != Vector2i(-1, -1)])
	if stand_pos == Vector2i(-1, -1):
		print("RESULT (Chasm Jump Action): SOME FAILED (no jumpable side found, aborting)")
		return false

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	state["player_grid_pos"] = stand_pos
	GameState.dungeon_state = state

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(6):
		await tree.process_frame

	checks.append(["FieldEncounter picked up the injected dungeon_state instead of generating a fresh one", fe.dungeon_state.get("rooms", []).size() == state.get("rooms", []).size()])

	## Force the player onto our hand-picked standing cell — automatic
	## party placement near the entrance would otherwise ignore it.
	fe.battle_positions[fe.player] = stand_pos
	fe._reveal_around_party()

	## (a) The chasm's own cells must never be a legal Move destination.
	var reachable: Array = fe.battle_grid.reachable_squares(stand_pos, 12)
	var any_chasm_reachable := false
	for c in hazard_cells:
		if reachable.has(c):
			any_chasm_reachable = true
	checks.append(["THE FIX: no chasm cell is ever reachable via a normal Move", not any_chasm_reachable])
	var direct_path: Array = fe.battle_grid.find_path(stand_pos, hazard_cells[0], {})
	checks.append(["find_path() also refuses to route straight onto a chasm cell", direct_path.is_empty()])

	## (b) The Jump action is available exactly when standing beside the
	## chasm, and computes the correct far-side landing cell.
	var jump: Dictionary = fe._adjacent_chasm_jump(stand_pos)
	checks.append(["_adjacent_chasm_jump() reports available when standing beside the chasm", not jump.is_empty()])
	checks.append(["_adjacent_chasm_jump() computes the correct far-side landing cell", jump.get("landing", Vector2i(-99, -99)) == expected_landing])
	var far_pos: Vector2i = stand_pos + Vector2i(500, 500)   ## nowhere near any chasm
	checks.append(["_adjacent_chasm_jump() reports unavailable far away from any chasm", fe._adjacent_chasm_jump(far_pos).is_empty()])

	## (c) A guaranteed-success Athletics Test (Agility 100 -> target
	## 100, success = roll <= target, every roll 1-100 succeeds) actually
	## lands the jumper on the far side.
	fe.player.characteristics.set_value("agility", 100)
	var wounds_before_success: int = fe.player.wounds_current
	await fe._attempt_chasm_jump(fe.player, jump)
	checks.append(["a guaranteed-success Jump actually lands the character on the far side", fe.battle_positions.get(fe.player) == expected_landing])
	checks.append(["a successful Jump takes no falling damage", fe.player.wounds_current == wounds_before_success])

	## (d) A guaranteed-FAILURE Athletics Test (Agility 0 -> target 0,
	## success would need roll <= 0, impossible) leaves the character
	## exactly where they stood — beside the chasm, never on it — and
	## damages them instead.
	fe.battle_positions[fe.player] = stand_pos
	fe.player.wounds_current = fe.player.wounds_max
	fe.player.characteristics.set_value("agility", 0)
	var jump2: Dictionary = fe._adjacent_chasm_jump(stand_pos)
	await fe._attempt_chasm_jump(fe.player, jump2)
	checks.append(["a guaranteed-failure Jump leaves the character exactly where they stood", fe.battle_positions.get(fe.player) == stand_pos])
	checks.append(["a guaranteed-failure Jump never leaves the character standing ON a chasm cell", not chasm_set.has(fe.battle_positions.get(fe.player))])
	checks.append(["a failed Jump applies real falling damage", fe.player.wounds_current < fe.player.wounds_max])

	fe.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Chasm Jump Action): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass

static func _is_open_cell(grid_rows: Array, theme: DungeonThemeDefinition, pos: Vector2i) -> bool:
	if pos.y < 0 or pos.y >= grid_rows.size():
		return false
	var row: String = grid_rows[pos.y]
	if pos.x < 0 or pos.x >= row.length():
		return false
	var ch: String = row[pos.x]
	return ch == theme.floor_char or ch == theme.door_open_char or ch == theme.door_closed_char
