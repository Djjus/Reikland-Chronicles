extends RefCounted
class_name DungeonFurnitureSearchTest
## Regression test for the "Sewer/Cave Dungeons update" request's live
## Search/loot behaviour, at the FieldEncounter layer (see
## DungeonFurnitureGenerationTest for the DungeonGenerator/BattleGrid
## layer this builds on). Generates a real dungeon (real random seed,
## same generator the game actually uses) until one comes up with a
## furnished room and a Quest room — every generated dungeon has a Quest
## room, so only furniture needs a retry loop — then drives a live
## FieldEncounter, mirroring ChasmJumpActionTest's own established
## pattern for testing a dungeon hazard/interactable end to end:
## - furniture cells and the Quest room's own chest cell are never a
##   legal Move destination (per "Character should not be able to walk
##   on these new items");
## - _adjacent_furniture()/_adjacent_quest_chest() only report available
##   when the player is genuinely standing beside the piece, per the
##   same "adjacency, not exact-tile" convention _adjacent_chasm_jump()/
##   _is_near_chest() already use;
## - searching grants the right kind of loot for the piece (a synthetic
##   room per furniture type, rolled many times, so every branch of
##   every Loot Table gets exercised regardless of what the one real
##   generated room happened to roll), and searching twice never grants
##   loot twice;
## - the Quest room's own Treasure Chest always grants 12d6 Silver
##   Shillings and never re-grants once looted.

const LOOT_RUNS := 200

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	var theme: DungeonThemeDefinition = GameData.dungeon_themes.get("sewer")
	checks.append(["sewer theme is registered in GameData", theme != null])
	if theme == null:
		print("RESULT (Dungeon Furniture Search): SOME FAILED (theme missing, aborting)")
		return false

	var state: Dictionary = {}
	var furniture_room: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	for attempt in range(300):
		rng.seed = 9000 + attempt
		var candidate: Dictionary = DungeonGenerator.generate(theme, rng)
		for room in candidate.get("rooms", []):
			if room.get("furniture_type", "none") != "none":
				state = candidate
				furniture_room = room
				break
		if not state.is_empty():
			break
	checks.append(["found a generated dungeon with a furnished room within 300 attempts", not state.is_empty()])
	if state.is_empty():
		print("RESULT (Dungeon Furniture Search): SOME FAILED (no furnished room found, aborting)")
		return false

	var quest_room: Dictionary = {}
	for room in state.get("rooms", []):
		if room.get("quest", false):
			quest_room = room
			break
	checks.append(["the generated dungeon has a Quest room with its own chest_pos", not quest_room.is_empty() and quest_room.get("chest_pos", Vector2i(-1, -1)) != Vector2i(-1, -1)])

	var grid_rows: Array = state.get("grid_rows", [])
	var furniture_cells: Array = furniture_room.get("furniture_cells", [])
	var chest_pos: Vector2i = quest_room.get("chest_pos", Vector2i(-1, -1))

	var furniture_stand_pos: Vector2i = _find_adjacent_open_cell(grid_rows, theme, furniture_cells, furniture_cells)
	checks.append(["found a standable cell beside the furnished room's own furniture", furniture_stand_pos != Vector2i(-1, -1)])
	var chest_stand_pos: Vector2i = _find_adjacent_open_cell(grid_rows, theme, [chest_pos], quest_room.get("furniture_cells", []) + [chest_pos])
	checks.append(["found a standable cell beside the Quest room's own chest", chest_stand_pos != Vector2i(-1, -1)])
	if furniture_stand_pos == Vector2i(-1, -1) or chest_stand_pos == Vector2i(-1, -1):
		print("RESULT (Dungeon Furniture Search): SOME FAILED (no standable adjacency found, aborting)")
		return false

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	state["player_grid_pos"] = furniture_stand_pos
	GameState.dungeon_state = state
	## _has_pending_exploration_map() gates the exploration layer (and
	## therefore _load_or_generate_dungeon() ever picking up the
	## dungeon_state we just injected) on this flag alone, not on
	## dungeon_state's own emptiness — see its own header comment for
	## why (a stale dungeon_state must never silently hijack an
	## unrelated encounter). Same real trigger a genuine dungeon-gate
	## walk-on sets, mirrored here so FieldEncounter actually enters
	## exploration mode against our hand-built state instead of running
	## a normal combat encounter with dungeon_state sitting unused.
	GameState.dungeon_entry_requested = true

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(6):
		await tree.process_frame

	checks.append(["FieldEncounter picked up the injected dungeon_state instead of generating a fresh one", fe.dungeon_state.get("rooms", []).size() == state.get("rooms", []).size()])

	## (a) Furniture/chest cells are never a legal Move destination.
	fe.battle_positions[fe.player] = furniture_stand_pos
	fe._reveal_around_party()
	var reachable: Array = fe.battle_grid.reachable_squares(furniture_stand_pos, 12)
	var any_furniture_reachable := false
	for c in furniture_cells:
		if reachable.has(c):
			any_furniture_reachable = true
	checks.append(["no furniture cell is ever reachable via a normal Move", not any_furniture_reachable])
	checks.append(["find_path() also refuses to route straight onto a furniture cell", fe.battle_grid.find_path(furniture_stand_pos, furniture_cells[0], {}).is_empty()])

	fe.battle_positions[fe.player] = chest_stand_pos
	fe._reveal_around_party()
	var reachable2: Array = fe.battle_grid.reachable_squares(chest_stand_pos, 12)
	checks.append(["the Quest room's own chest cell is never reachable via a normal Move", not reachable2.has(chest_pos)])

	## (b) Adjacency helpers only report available when actually beside
	## the piece.
	fe.battle_positions[fe.player] = furniture_stand_pos
	var adj_room: Dictionary = fe._adjacent_furniture(furniture_stand_pos)
	checks.append(["_adjacent_furniture() reports available when standing beside the furniture", not adj_room.is_empty()])
	var far_pos: Vector2i = furniture_stand_pos + Vector2i(500, 500)
	checks.append(["_adjacent_furniture() reports unavailable far away from any furniture", fe._adjacent_furniture(far_pos).is_empty()])
	fe.battle_positions[fe.player] = chest_stand_pos
	var adj_chest_room: Dictionary = fe._adjacent_quest_chest(chest_stand_pos)
	checks.append(["_adjacent_quest_chest() reports available when standing beside the chest", not adj_chest_room.is_empty()])
	checks.append(["_adjacent_quest_chest() reports unavailable far away from any chest", fe._adjacent_quest_chest(far_pos).is_empty()])

	## (c) Searching the real generated furniture piece marks it looted
	## and stays reported (visible-but-disabled), never searches twice.
	fe._search_furniture(adj_room)
	var adj_room_after: Dictionary = fe._adjacent_furniture(furniture_stand_pos)
	checks.append(["searching the furniture marks it looted", adj_room_after.get("furniture_looted", false) == true])
	checks.append(["the searched furniture still reports (for a visible-but-disabled button), per the Goblin Fort chest's own convention", not adj_room_after.is_empty()])

	## (d) The Quest room's own chest always grants 12d6 Silver Shillings
	## (range 12-72) and never re-grants once looted.
	var pennies_before: int = fe.player.get_total_pennies()
	fe._search_quest_chest(adj_chest_room)
	var pennies_after: int = fe.player.get_total_pennies()
	var gained: int = pennies_after - pennies_before
	checks.append(["the Quest room's chest grants Silver Shillings within 12d6's own 12-72 range", gained >= 12 * Character.PENNIES_PER_SHILLING and gained <= 72 * Character.PENNIES_PER_SHILLING])
	checks.append(["the Quest room's chest is marked looted", fe._adjacent_quest_chest(chest_stand_pos).get("chest_looted", false) == true])
	fe._search_quest_chest(adj_chest_room)
	checks.append(["searching an already-looted Quest chest grants nothing further", fe.player.get_total_pennies() == pennies_after])

	fe.queue_free()
	for i in range(3):
		await tree.process_frame

	## --- Loot Table coverage (synthetic rooms, one furniture type at a
	## time, rolled many times so every branch of every table gets
	## exercised regardless of what the one real room above happened to
	## roll) — needs its own live FieldEncounter since _search_furniture/
	## _search_quest_chest both read/write `player`.
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.dungeon_state = {}
	var fe2 = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe2)
	for i in range(6):
		await tree.process_frame

	checks.append_array(_check_loot_table(fe2, "weapon_rack", LOOT_RUNS))
	checks.append_array(_check_loot_table(fe2, "cupboard", LOOT_RUNS))
	checks.append_array(_check_loot_table(fe2, "alchemy_table", LOOT_RUNS))
	checks.append_array(_check_loot_table(fe2, "torture_rack", LOOT_RUNS))

	fe2.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Dungeon Furniture Search): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass

## Rolls one furniture type's own Loot Table `runs` times (a fresh
## synthetic room + a fully reset player each time, so one run's loot
## can never bleed into the next) and checks: a "Nothing" outcome shows
## up, a "something" outcome shows up, and — for the two multi-branch
## tables (Cupboard, Alchemy Table) — every distinct kind of reward
## shows up too.
static func _check_loot_table(fe, ftype: String, runs: int) -> Array:
	var out: Array = []
	var saw_nothing := false
	var saw_weapon := false
	var saw_gold := false
	var saw_armour := false
	var saw_draught := false
	var saw_rope := false
	for i in range(runs):
		fe.player.inventory.clear()
		fe.player.gold_crowns = 0
		fe.player.silver_shillings = 0
		fe.player.brass_pennies = 0
		var room: Dictionary = {"door_pos": Vector2i(-1000 - i, -1000), "furniture_type": ftype, "furniture_looted": false}
		fe._search_furniture(room)
		if not room.get("furniture_looted", false):
			out.append(["_search_furniture() always marks the room looted (%s, run %d)" % [ftype, i], false])
		if fe.player.inventory.is_empty() and fe.player.get_total_pennies() == 0:
			saw_nothing = true
		elif ftype == "weapon_rack":
			if not fe.player.inventory.is_empty():
				saw_weapon = true
		elif ftype == "cupboard":
			if fe.player.get_total_pennies() > 0:
				saw_gold = true
			if not fe.player.inventory.is_empty():
				saw_armour = true
		elif ftype == "alchemy_table":
			if fe.player.get_total_pennies() > 0:
				saw_gold = true
			if fe.player.inventory.has(HEALING_DRAUGHT_NAME):
				saw_draught = true
		elif ftype == "torture_rack":
			if fe.player.inventory.has("Rope, 10 yards"):
				saw_rope = true

	out.append(["%s Loot Table: 'Nothing' shows up across %d rolls" % [ftype, runs], saw_nothing])
	match ftype:
		"weapon_rack":
			out.append(["Weapon Rack Loot Table: a random Weapon shows up across %d rolls" % runs, saw_weapon])
		"cupboard":
			out.append(["Cupboard Loot Table: 3d6 Silver Shillings shows up across %d rolls" % runs, saw_gold])
			out.append(["Cupboard Loot Table: a random Armour piece shows up across %d rolls" % runs, saw_armour])
		"alchemy_table":
			out.append(["Alchemy Table Loot Table: 3d6 Silver Shillings shows up across %d rolls" % runs, saw_gold])
			out.append(["Alchemy Table Loot Table: a Healing Draught shows up across %d rolls" % runs, saw_draught])
		"torture_rack":
			out.append(["Torture Rack Loot Table: Rope, 10 yards shows up across %d rolls" % runs, saw_rope])
	return out

const HEALING_DRAUGHT_NAME := "Healing Draught"

## Finds an open (floor/door) cell orthogonally-or-diagonally adjacent to
## any cell in `target_cells` that is itself not one of `exclude_cells`
## (so the returned stand position is never accidentally on top of the
## very thing — or a sibling piece of furniture — it's meant to stand
## beside).
static func _find_adjacent_open_cell(grid_rows: Array, theme: DungeonThemeDefinition, target_cells: Array, exclude_cells: Array) -> Vector2i:
	var exclude_set: Dictionary = {}
	for c in exclude_cells:
		exclude_set[c] = true
	for t in target_cells:
		for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			var cand: Vector2i = t + dir
			if exclude_set.has(cand):
				continue
			if _is_open_cell(grid_rows, theme, cand):
				return cand
	return Vector2i(-1, -1)

static func _is_open_cell(grid_rows: Array, theme: DungeonThemeDefinition, pos: Vector2i) -> bool:
	if pos.y < 0 or pos.y >= grid_rows.size():
		return false
	var row: String = grid_rows[pos.y]
	if pos.x < 0 or pos.x >= row.length():
		return false
	var ch: String = row[pos.x]
	return ch == theme.floor_char or ch == theme.door_open_char or ch == theme.door_closed_char
