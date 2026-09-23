extends RefCounted
class_name GoblinFortDungeonTest
## Scratch verification for task #29 (fixed single-room dungeon
## generator mode) — checks the new "goblin_fort" theme is registered,
## DungeonGenerator.generate_fixed_room() produces a sane 8x16 room
## with an entrance at the bottom and a chest at the far (top) end, and
## that BattleGrid.generate_from_dungeon_grid() can actually consume
## the result without error. Not part of the shipped game — deleted
## after use, same as the other one-off *_test.gd scratch scripts in
## this directory once their feature is confirmed working.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Case 1: theme registered.
	## Bare "GameData" doesn't resolve inside a custom SceneTree --script
	## entry point (autoloads aren't compile-time globals there, only
	## class_name globals are) -- same fix as goblin_fort_screenshot.gd's
	## own GameState workaround.
	var game_data = tree.get_root().get_node("/root/GameData")
	var theme: DungeonThemeDefinition = game_data.dungeon_themes.get("goblin_fort")
	checks.append(["Case 1: goblin_fort theme is registered in GameData.dungeon_themes", theme != null])
	if theme == null:
		for chk in checks:
			print(("PASS  " if chk[1] else "FAIL  ") + chk[0])
		return false

	## --- Case 2: generate_fixed_room() shape.
	var state: Dictionary = DungeonGenerator.generate_fixed_room(theme, 8, 16)
	checks.append(["Case 2: grid_rows has 16 interior rows + 2 border rows = 18", state.get("grid_rows", []).size() == 18])
	var rows: Array = state.get("grid_rows", [])
	if rows.size() > 0:
		checks.append(["Case 2: each row is 8 interior cols + 2 border cols = 10 wide", String(rows[0]).length() == 10])
	var entrance: Vector2i = state.get("entrance_pos", Vector2i(-1, -1))
	var chest: Vector2i = state.get("chest_pos", Vector2i(-1, -1))
	checks.append(["Case 2: entrance sits on the bottom row (y = 16)", entrance.y == 16])
	checks.append(["Case 2: chest sits on the top row (y = 1), the far end from the entrance", chest.y == 1])
	checks.append(["Case 2: entry_ambush_fired starts false", state.get("entry_ambush_fired", true) == false])
	checks.append(["Case 2: chest starts locked, unlooted, trap unspotted", state.get("chest_locked", false) == true and state.get("chest_looted", true) == false and state.get("chest_trap_spotted", true) == false])
	checks.append(["Case 2: rooms/hallway_segments are empty (no doors/corridors in a single fixed room)", state.get("rooms", [1]).is_empty() and state.get("hallway_segments", [1]).is_empty()])

	## --- Case 3: the entrance cell in grid_rows really is entrance_char,
	## and the chest cell is plain floor (the chest itself is drawn as
	## an overlay, not baked into the grid character).
	var entrance_row: String = rows[entrance.y]
	checks.append(["Case 3: the entrance cell's own character is theme.entrance_char", entrance_row[entrance.x] == theme.entrance_char])
	var chest_row: String = rows[chest.y]
	checks.append(["Case 3: the chest cell's own character is plain floor", chest_row[chest.x] == theme.floor_char])

	## --- Case 4: BattleGrid can actually build from this grid without
	## crashing, and treats the room as walkable inside / walled outside.
	var grid := BattleGrid.new()
	grid.generate_from_dungeon_grid(theme, rows, state.get("visibility", {}), state.get("rooms", []))
	checks.append(["Case 4: the entrance cell is NOT impassable", not grid.impassable.get(entrance, false)])
	checks.append(["Case 4: the chest cell (far end) is NOT impassable", not grid.impassable.get(chest, false)])
	checks.append(["Case 4: the top-left corner (0,0), a wall border cell, IS impassable", grid.impassable.get(Vector2i(0, 0), false)])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Goblin Fort Dungeon Generator): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
