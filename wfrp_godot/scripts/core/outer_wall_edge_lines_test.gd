extends RefCounted
class_name OuterWallEdgeLinesTest
## Regression test for the follow-up request: "add grey walls to all
## outer edges of the dungeon tiles. Use the exact same grey wall as
## already used next to doors."
##
## BattleGrid.wall_edge_lines used to only ever carry an entry for the
## "room's own near face touches its corridor, but there's no door
## there" case (BattleGrid._build_room_wall_edges) — a genuine wall/void
## cell (impassable AND never textured — the map's own outer perimeter,
## a dead-end corridor cap, any room wall not next to a door) got no
## line at all, rendering as flat black with no visible boundary.
## BattleGrid._build_outer_wall_edge_lines() (this fix) adds the exact
## same grey wall_edge_lines entry — same array, same
## BattleGridView draw code, same colour/width — wherever a real
## floor/door cell borders a genuine wall cell.

static func run_test(_tree) -> bool:
	var checks: Array = []

	var theme: DungeonThemeDefinition = GameData.dungeon_themes.get("sewer")
	checks.append(["setup: sewer theme is registered", theme != null])
	if theme == null:
		print("RESULT (Outer Wall Edge Lines): SETUP FAILED")
		return false

	## A small hand-built room with no doors at all, fully enclosed by
	## wall_char on every side -- every one of its own floor cells
	## should get a grey outer-wall line on every side that borders the
	## surrounding wall, and NONE at all on sides that border another
	## floor cell (there are none here, but this also confirms the
	## count matches exactly a fully-enclosed room's own perimeter).
	var w := theme.wall_char
	var f := theme.floor_char
	var rows: Array = [
		w + w + w + w + w,
		w + f + f + f + w,
		w + f + f + f + w,
		w + f + f + f + w,
		w + w + w + w + w,
	]
	var grid := BattleGrid.new()
	grid.generate_from_dungeon_grid(theme, rows, {})

	## The enclosed 3x3 floor block has a perimeter of 3*4 = 12 cell-edges
	## touching the surrounding wall ring, and (since there are no doors
	## and no rooms passed in at all) zero from _build_room_wall_edges.
	checks.append(["Case 1: every one of the enclosed room's 12 perimeter edges got a grey outer-wall line", grid.wall_edge_lines.size() == 12])

	var all_are_wall_neighbors := true
	var all_have_correct_shape := true
	for edge in grid.wall_edge_lines:
		var cells: Array = edge["cells"]
		var floor_cell: Vector2i = cells[0]
		var wall_cell: Vector2i = cells[1]
		if not grid.is_walkable(floor_cell) or grid.is_walkable(wall_cell) or not grid.impassable.has(wall_cell):
			all_are_wall_neighbors = false
		## Same orientation/line_pos/span convention door_edges/the
		## original wall_edge_lines case already use.
		var span_len: int = edge["span_end"] - edge["span_start"]
		if span_len != 1:
			all_have_correct_shape = false
	checks.append(["Case 2: every entry pairs a real walkable floor cell with a genuine impassable wall cell", all_are_wall_neighbors])
	checks.append(["Case 3: every entry spans exactly one cell's width, same convention as the door-adjacent case", all_have_correct_shape])

	## Per _build_outer_wall_edge_lines' own comment: these are purely
	## visual -- no wall_edges/gameplay entry, since the wall cell's own
	## impassable=true already blocks movement/LOS unconditionally.
	var any_wall_edges_dict_entry := false
	for edge in grid.wall_edge_lines:
		var cells: Array = edge["cells"]
		if grid._edge_blocked(cells[0], cells[1]):
			any_wall_edges_dict_entry = true
	checks.append(["Case 4: none of the new outer-wall entries register a redundant wall_edges gameplay entry", not any_wall_edges_dict_entry])

	## --- A door-adjacent room, to confirm the two mechanisms coexist
	## cleanly on the very case the request explicitly asked to match:
	## the door itself gets NO grey line (still its own brown door_edges
	## line), but every OTHER wall cell around the room -- including the
	## far outer perimeter -- does. Same geometry convention
	## battle_grid_wall_edges_test.gd's own hand-authored grid already
	## uses and has passing coverage for: door_pos sits ON the room's
	## own face column/row (here x=3, the room's east edge), door_dir
	## points AWAY from the corridor (west, (-1,0)) since
	## _build_room_wall_edges derives corridor_cell as face_cell -
	## door_dir; a 3-wide x 4-tall room (x=1..3, y=1..4) with its own
	## east face column at x=3, a 2-cell door span (y=2,3, matching
	## DungeonGenerator.CORRIDOR_SCALE) and two "pad" cells flanking it
	## (y=1 and y=4) that should each get a grey line to the corridor
	## column (x=4) — plus the whole rest of the room/corridor's outer
	## perimeter (into the wall_char border ring) getting the new
	## outer-wall treatment this fix adds.
	var d: String = theme.door_closed_char
	var door_rows: Array = [
		w.repeat(6),
		w + f + f + f + f + w,   ## y=1: pad cell at x=3
		w + f + f + d + f + w,   ## y=2: door
		w + f + f + d + f + w,   ## y=3: door
		w + f + f + f + f + w,   ## y=4: pad cell at x=3
		w.repeat(6),
	]
	var door_room: Dictionary = {
		"rect": Rect2i(1, 1, 3, 4),
		"door_pos": Vector2i(3, 2),
		"door_dir": Vector2i(-1, 0),
	}
	var door_grid := BattleGrid.new()
	door_grid.generate_from_dungeon_grid(theme, door_rows, {}, [door_room])
	checks.append(["Case 5 setup: the door cells are genuinely impassable while closed", door_grid.impassable.has(Vector2i(3, 2)) and door_grid.impassable.has(Vector2i(3, 3))])
	checks.append(["Case 5 setup: the pad cells (y=1, y=4) stay walkable, same as the corridor cell across from them", door_grid.is_walkable(Vector2i(3, 1)) and door_grid.is_walkable(Vector2i(4, 1))])
	var door_has_grey_line := false
	for edge in door_grid.wall_edge_lines:
		var cells: Array = edge["cells"]
		if cells.has(Vector2i(3, 2)) or cells.has(Vector2i(3, 3)):
			door_has_grey_line = true
	checks.append(["Case 5: the door cells themselves never get an outer-wall grey line (stays the door's own brown door_edges line only)", not door_has_grey_line])
	var pad_a_sealed := false
	var pad_b_sealed := false
	for edge in door_grid.wall_edge_lines:
		var cells: Array = edge["cells"]
		if cells.has(Vector2i(3, 1)) and cells.has(Vector2i(4, 1)):
			pad_a_sealed = true
		if cells.has(Vector2i(3, 4)) and cells.has(Vector2i(4, 4)):
			pad_b_sealed = true
	checks.append(["Case 5: the room's own no-door pad cells still get the original sealed-boundary grey line to the corridor (untouched by this fix)", pad_a_sealed and pad_b_sealed])
	checks.append(["Case 5: the room/corridor's own outer perimeter (into the surrounding wall ring) also got real grey lines from this fix", door_grid.wall_edge_lines.size() > 2])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Outer Wall Edge Lines): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
