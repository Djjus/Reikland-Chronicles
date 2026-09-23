extends RefCounted
class_name BuildingWallWalkableTest
## Per the request ("change how the sides and back walls (W/E/N) work
## and make it so you can walk on them from the inside, and only block
## movement on their outer edges... allow walking behind the front and
## back walls too"): overworld.gd's is_walkable() gained an optional
## `from` parameter — a wall/front tile (WALL_MATERIAL_CHARS) is now
## walkable when `from` is anywhere inside the SAME building's own
## bounding rect (already inside, walking along the inside face of a
## wall), but stepping FROM a wall tile to anywhere outside that same
## building's rect stays blocked (the "outer edge"), and the old
## "no `from` given" behaviour (used by pathfinding's solid-grid setup,
## ambush/social marker placement, etc.) is completely unchanged: every
## wall/front tile is still simply solid.
##
## Per the direct follow-up ("make the southern edge of the northern
## walls impassable, just like the south wall, and allow player to walk
## behind it on the outside" → clarified as "change it to walk from
## outside"): the NORTH (back) wall row is the one deliberate exception
## to the rule above — it's walkable from the OUTSIDE (behind the
## building, or along the same back-wall row) and blocked from the
## INSIDE (the building's own interior). Every other wall (front/west/
## east) keeps the original walkable-from-inside rule.
##
## Uses Giessingen's own real map data — the small twin timber/stone
## buildings at rows 12-14 (verified directly against
## giessingen_village.tres's map_rows before writing this test):
## Building A (timber, "B"/"w"): Rect2i(5, 12, 5, 3)
##   row 12 "BBBBB"  (5..9)         -- north/back wall
##   row 13 "B..YB"  (5=B, 9=B)     -- west/east side walls, floor between
##   row 14 "wwdww"  (7=door)       -- front wall + door
## Building B (stone, "K"... actually "r" front / "B" sides here too,
## see WALL_MATERIAL_CHARS's own note that "r" is just a facade texture
## on the same kind of wall tile): Rect2i(14, 12, 5, 3), door at (16, 14).

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.pending_map_path = "res://data/maps/giessingen_village.tres"
	var ow = load("res://scenes/Overworld.tscn").instantiate()
	tree.get_root().add_child(ow)
	tree.current_scene = ow
	for i in range(15):
		await tree.process_frame

	## --- setup sanity: the two building rects are exactly where the raw map data says ---
	var found_a := false
	var found_b := false
	for rect in ow.buildings:
		if rect == Rect2i(5, 12, 5, 3):
			found_a = true
		if rect == Rect2i(14, 12, 5, 3):
			found_b = true
	checks.append(["setup: Building A's rect is (5,12,5,3) as computed from the map", found_a])
	checks.append(["setup: Building B's rect is (14,12,5,3) as computed from the map", found_b])

	## --- North (back) wall: the reversed exception -- walkable from
	## OUTSIDE (behind the building, or along the same row), blocked
	## from the INSIDE (the building's own interior). ---
	var interior: Vector2i = Vector2i(7, 13)   ## "." floor cell, Building A's middle row
	var north_wall: Vector2i = Vector2i(7, 12) ## "B", Building A's own north wall
	var north_wall_neighbor: Vector2i = Vector2i(6, 12) ## "B", same back-wall row
	var beyond_north: Vector2i = Vector2i(7, 11)  ## outside the building entirely, behind it
	checks.append(["north wall: NO LONGER walkable stepping in from the interior", not ow.is_walkable(north_wall, interior)])
	checks.append(["north wall: stepping from it INTO the interior is blocked", not ow.is_walkable(interior, north_wall)])
	checks.append(["north wall: walkable stepping in from the true exterior (behind the building)", ow.is_walkable(north_wall, beyond_north)])
	checks.append(["north wall: stepping further out behind the building (past it, outside) is now allowed", ow.is_walkable(beyond_north, north_wall)])
	checks.append(["north wall: walkable moving sideways along the same back-wall row", ow.is_walkable(north_wall_neighbor, north_wall)])

	## --- West side wall: same rule ---
	var interior_w: Vector2i = Vector2i(6, 13)
	var west_wall: Vector2i = Vector2i(5, 13)
	var beyond_west: Vector2i = Vector2i(4, 13)
	checks.append(["west wall: walkable stepping in from the interior", ow.is_walkable(west_wall, interior_w)])
	checks.append(["west wall: stepping further out past it is blocked", not ow.is_walkable(beyond_west, west_wall)])

	## --- East side wall: same rule ---
	var east_wall: Vector2i = Vector2i(9, 13)
	var beyond_east: Vector2i = Vector2i(10, 13)
	checks.append(["east wall: walkable stepping in from the interior", ow.is_walkable(east_wall, interior)])
	checks.append(["east wall: stepping further out past it is blocked", not ow.is_walkable(beyond_east, east_wall)])

	## --- Front wall (the "w" tiles flanking the door, not the door itself): same rule ---
	var front_wall: Vector2i = Vector2i(6, 14)   ## "w", Building A's own front row
	var beyond_south: Vector2i = Vector2i(6, 15)  ## outside, south of the building
	checks.append(["front wall: walkable stepping in from the interior", ow.is_walkable(front_wall, interior)])
	checks.append(["front wall: stepping further out past it (past the building, not through the door) is blocked", not ow.is_walkable(beyond_south, front_wall)])

	## --- The door itself is completely unaffected: always walkable, from outside or in ---
	var door: Vector2i = Vector2i(7, 14)
	var outside_door: Vector2i = Vector2i(7, 15)
	checks.append(["door: walkable straight in from outside, exactly as before", ow.is_walkable(door, outside_door)])
	checks.append(["door: walkable straight out from inside, exactly as before", ow.is_walkable(outside_door, door)])

	## --- Cross-building leak check: Building A's interior can't walk straight onto Building B's (non-north) wall ---
	## Uses Building B's own west wall, not its north wall — the north
	## wall's rule is deliberately "walkable from anywhere that isn't
	## THIS building's own interior," so Building A's interior (which is
	## definitely not Building B's interior) is legitimately "outside"
	## for that specific rule and wouldn't exercise a real leak here.
	var b_west_wall: Vector2i = Vector2i(14, 13)
	checks.append(["a different building's (non-north) wall tile is NOT walkable from Building A's own interior", not ow.is_walkable(b_west_wall, interior)])

	## --- No `from` given at all: every wall/front tile is still simply solid (pathfinding's own solid-grid setup relies on this) ---
	checks.append(["no-`from` calls (pathfinding/marker-placement style) still treat the north wall as solid", not ow.is_walkable(north_wall)])
	checks.append(["no-`from` calls still treat the front wall as solid", not ow.is_walkable(front_wall)])
	checks.append(["no-`from` calls still treat the door as walkable (unchanged)", ow.is_walkable(door)])

	ow.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Building Wall Walkable-From-Inside): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
