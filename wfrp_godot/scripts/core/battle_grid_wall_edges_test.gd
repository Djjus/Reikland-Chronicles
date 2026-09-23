extends RefCounted
class_name BattleGridWallEdgesTest
## Regression test for the request ("places where passage walls touch
## rooms and there is no door (red lines on the image), should be
## impassable and player should [not] be able to see through them").
## Hand-builds a small BattleGrid directly (bypassing DungeonGenerator's
## own randomness, so the exact geometry is known) matching the real
## shape a generated room-on-corridor connection always has: a 2-wide
## vertical corridor with a 4-wide Small room's near face flush against
## one of its rails, door in the middle (2 cells), and one "pad" cell of
## bare room floor flanking the door on each side — precisely the "wall
## touches room, no door" gap the request's red lines pointed at.
##
## Also exercises BattleGrid._build_hazard_markers()'s new multi-cell
## Chasm handling via a second, independent hand-placed hazard room in
## the same grid (see the chasm_room section below).

const W := DungeonGenerator.CORRIDOR_SCALE   ## = 2, just for readability below

static func run_test(_tree) -> bool:
	var checks: Array = []
	var theme: DungeonThemeDefinition = GameData.dungeon_themes.get("sewer")
	checks.append(["sewer theme is registered in GameData", theme != null])
	if theme == null:
		print("RESULT (BattleGrid Wall Edges): SOME FAILED (theme missing, aborting)")
		return false

	## --- Grid layout (see this file's own header comment for the exact
	## geometry): a vertical corridor at x=10,11 spanning y=0..9, and a
	## Small (4-wide) room at x=6..9,y=3..6 attached to its west rail
	## (x=10), door at (9,4)/(9,5), pad cells at (9,3) and (9,6). A
	## second, unconnected 4-cell Chasm strip sits at y=9,x=1..4, purely
	## to exercise the hazard-marker side of this feature in the same
	## grid, independent of the wall-edge geometry above.
	var f: String = theme.floor_char
	var w: String = theme.wall_char
	var d: String = theme.door_closed_char
	var rows: Array = [
		"#" + w.repeat(9) + f + f + w,          ## y=0
		"#" + w.repeat(9) + f + f + w,          ## y=1
		"#" + w.repeat(9) + f + f + w,          ## y=2
		"#" + w.repeat(5) + f + f + f + f + f + f + w,   ## y=3 (room row, no door)
		"#" + w.repeat(5) + f + f + f + d + f + f + w,   ## y=4 (door)
		"#" + w.repeat(5) + f + f + f + d + f + f + w,   ## y=5 (door)
		"#" + w.repeat(5) + f + f + f + f + f + f + w,   ## y=6 (room row, no door)
		"#" + w.repeat(9) + f + f + w,          ## y=7
		"#" + w.repeat(9) + f + f + w,          ## y=8
		w + f + f + f + f + w.repeat(5) + f + f + w,   ## y=9 (chasm strip x1-4, corridor still at x10,11)
		w.repeat(13),                            ## y=10
	]
	## Sanity-check the hand-authored ASCII against plain-string slicing
	## before trusting any check built on top of it.
	checks.append(["hand-authored grid rows are all width 13", rows.all(func(r): return String(r).length() == 13)])
	checks.append(["y=4 has a door char at x=9", String(rows[4])[9] == d])

	var room: Dictionary = {
		"rect": Rect2i(6, 3, 4, 4),
		"door_pos": Vector2i(9, 4),
		"door_dir": Vector2i(-1, 0),
		"door_open": false,
		"room_type": "small",
		"quest": false,
		"hazard_type": "none",
		"hazard_pos": Vector2i(-1, -1),
		"hazard_cells": [],
		"hazard_resolved": false,
		"monster_names": [],
		"encountered": false,
		"cleared": false,
		"spawn_far_corner": Vector2i(6, 3),
	}
	var chasm_room: Dictionary = {
		"rect": Rect2i(1, 9, 4, 1),
		"door_pos": Vector2i(-1, -1),
		"door_dir": Vector2i.ZERO,   ## no door -- _build_room_wall_edges() must skip this room entirely
		"door_open": false,
		"room_type": "small",
		"quest": false,
		"hazard_type": "chasm",
		"hazard_pos": Vector2i(2, 9),
		"hazard_cells": [Vector2i(1, 9), Vector2i(2, 9), Vector2i(3, 9), Vector2i(4, 9)],
		"hazard_resolved": false,
		"monster_names": [],
		"encountered": false,
		"cleared": false,
		"spawn_far_corner": Vector2i(1, 9),
	}

	var grid := BattleGrid.new()
	grid.generate_from_dungeon_grid(theme, rows, {}, [room, chasm_room])

	## --- The pad cells at (9,3) and (9,6): the "wall touches room, no
	## door" case itself.
	var pad_a := Vector2i(9, 3)
	var pad_b := Vector2i(9, 6)
	var rail_a := Vector2i(10, 3)   ## corridor cell directly across from pad_a
	var rail_b := Vector2i(10, 6)   ## corridor cell directly across from pad_b

	checks.append(["a pad cell itself stays independently walkable", grid.is_walkable(pad_a)])
	checks.append(["the corridor cell across from it stays independently walkable too", grid.is_walkable(rail_a)])
	checks.append(["THE FIX: BattleGrid records a sealed wall_edge between the pad cell and the corridor cell", grid._edge_blocked(pad_a, rail_a)])
	checks.append(["the sealed edge is genuinely bidirectional", grid._edge_blocked(rail_a, pad_a)])
	checks.append(["the same fix applies to the OTHER pad cell (9,6) too", grid._edge_blocked(pad_b, rail_b)])

	checks.append(["a straight direct path across the sealed pad boundary is refused", not grid.has_clear_direct_path(pad_a, rail_a)])
	checks.append(["line of sight straight across the sealed pad boundary is blocked", not grid.has_line_of_sight(pad_a, rail_a)])
	checks.append(["ranged cover/LOS resolution also refuses a shot straight across the sealed boundary", grid.get_ranged_cover(pad_a, rail_a)["blocked"]])

	## A real bug caught while building this: a sealed edge only ever
	## stopped a STRAIGHT step across it -- nothing stopped a diagonal
	## hop that cuts around the exact same corner instead. Fixed via
	## _edge_blocked_diagonal() (see its own comment in battle_grid.gd).
	var diag_target := Vector2i(10, 2)   ## one diagonal hop from pad_a, landing in the corridor
	checks.append(["a diagonal step that cuts around the sealed corner is also refused", grid._edge_blocked_diagonal(pad_a, diag_target)])
	var full_path: Array = grid.find_path(pad_a, rail_a, {})
	checks.append(["find_path() never returns a path that reaches the corridor from the pad cell at all (straight or via a diagonal cut)", full_path.is_empty()])

	## --- The door itself must be COMPLETELY unaffected -- still its
	## own separate impassable-while-closed tile, no wall_edge involved,
	## and once opened, a normal walkable connection with no sealed edge
	## in the way.
	var door_cell := Vector2i(9, 4)
	var door_rail := Vector2i(10, 4)
	checks.append(["the door cell itself is impassable while closed (its own existing mechanic, untouched)", not grid.is_walkable(door_cell)])
	checks.append(["no wall_edge was recorded across the door itself", not grid._edge_blocked(door_cell, door_rail)])
	grid.generate_from_dungeon_grid(theme, [
		rows[0], rows[1], rows[2], rows[3],
		"#" + w.repeat(5) + f + f + f + theme.door_open_char + f + f + w,
		"#" + w.repeat(5) + f + f + f + theme.door_open_char + f + f + w,
		rows[6], rows[7], rows[8], rows[9], rows[10],
	], {}, [room, chasm_room])
	checks.append(["once opened, the door cell becomes walkable like any floor", grid.is_walkable(door_cell)])
	checks.append(["once opened, a straight path through the door is allowed", grid.has_clear_direct_path(door_cell, door_rail)])
	checks.append(["once opened, line of sight through the door is clear", grid.has_line_of_sight(door_cell, door_rail)])

	## --- Chasm (multi-cell span + impassable + hazard_markers shape).
	var chasm_cells: Array = chasm_room["hazard_cells"]
	var all_chasm_impassable := true
	for c in chasm_cells:
		if grid.is_walkable(c):
			all_chasm_impassable = false
	checks.append(["THE FIX: every one of a chasm's own cells is impassable", all_chasm_impassable])
	var chasm_marker := {}
	for m in grid.hazard_markers:
		if m["type"] == "chasm":
			chasm_marker = m
	checks.append(["a chasm hazard_marker entry exists", not chasm_marker.is_empty()])
	checks.append(["the chasm hazard_marker carries all 4 of its own cells for rendering", chasm_marker.get("cells", []).size() == 4])
	checks.append(["chasm cells are NOT marked blocks_los -- a physical gap doesn't block sight", not grid.blocks_los.has(chasm_cells[0])])
	checks.append(["find_path() refuses to route onto any chasm cell as a destination", grid.find_path(Vector2i(5, 9), chasm_cells[0], {}).is_empty()])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (BattleGrid Wall Edges): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
