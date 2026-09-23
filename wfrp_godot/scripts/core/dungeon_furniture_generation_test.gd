extends RefCounted
class_name DungeonFurnitureGenerationTest
## Regression test for the "Sewer/Cave Dungeons update" request's Room
## Furniture Table and Quest room Treasure Chest, at the DungeonGenerator/
## BattleGrid layer (see DungeonFurnitureSearchTest for the live
## FieldEncounter-level Search/loot behaviour). Generates the shipped
## Sewer preset many times with real random seeds (same generator the
## game actually uses, per this project's own established test
## convention — see DungeonGeneratorTest) and checks:
## - every room (Quest and Hazard rooms included, per "All rooms will
##   roll on the Room furniture table when generated") carries a valid
##   furniture_type, and — when one was placed — its footprint is
##   exactly the size the request specifies (2x1 for Weapon Rack/
##   Cupboard/Alchemy Table, 2x2 for Torture Rack), fully inside the
##   room's own rect, and never overlaps that room's own door span or
##   hazard cells;
## - every table outcome (Nothing and all four furniture pieces) shows
##   up across enough runs;
## - the Quest room always gets its own untrapped chest_pos (per "Quest
##   Room will additionally always contain a (untrapped) Treasure Chest
##   at the far end to where the Hero's enter"), which never overlaps
##   that room's own furniture;
## - BattleGrid.generate_from_dungeon_grid() marks every furniture/chest
##   cell impassable (per "Character should not be able to walk on these
##   new items") and builds matching furniture_markers/room_chest_markers
##   for BattleGridView to draw;
## - the save/load round-trip (DungeonGenerator.to_save_data()/
##   from_save_data()) preserves every new field.

const RUNS := 120
const FOOTPRINT_AREA := {
	"weapon_rack": 2,
	"cupboard": 2,
	"alchemy_table": 2,
	"torture_rack": 4,
}

static func run_test(_tree) -> bool:
	var checks: Array = []

	var theme: DungeonThemeDefinition = GameData.dungeon_themes.get("sewer")
	checks.append(["sewer theme is registered in GameData", theme != null])
	if theme == null:
		print("RESULT (Dungeon Furniture Generation): SOME FAILED (theme missing, aborting)")
		return false

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var saw_none := false
	var saw_weapon_rack := false
	var saw_cupboard := false
	var saw_alchemy_table := false
	var saw_torture_rack := false
	var all_footprints_correct_size := true
	var all_footprints_in_rect := true
	var all_footprints_clear_of_door := true
	var all_footprints_clear_of_hazard := true
	var all_footprints_flush_against_a_wall := true
	var all_facings_point_away_from_their_wall := true
	var all_quest_rooms_have_chest := true
	var all_non_quest_rooms_have_no_chest := true
	var all_chests_clear_of_furniture := true
	var all_chests_in_rect := true
	var all_chests_start_unlooted := true
	var quest_rooms_seen := 0

	var last_state: Dictionary = {}
	var last_room_with_furniture: Dictionary = {}

	for i in range(RUNS):
		var state: Dictionary = DungeonGenerator.generate(theme, rng)
		if state.is_empty():
			continue
		last_state = state
		for room in state.get("rooms", []):
			var rect: Rect2i = room["rect"]
			var ftype: String = room.get("furniture_type", "none")
			match ftype:
				"none": saw_none = true
				"weapon_rack": saw_weapon_rack = true
				"cupboard": saw_cupboard = true
				"alchemy_table": saw_alchemy_table = true
				"torture_rack": saw_torture_rack = true
				_: all_footprints_correct_size = false   ## unrecognised type

			var fcells: Array = room.get("furniture_cells", [])
			if ftype != "none":
				last_room_with_furniture = room
				if fcells.size() != FOOTPRINT_AREA.get(ftype, -1):
					all_footprints_correct_size = false
				for c in fcells:
					if not rect.has_point(c):
						all_footprints_in_rect = false
				var door_dir: Vector2i = room.get("door_dir", Vector2i.ZERO)
				var perp: Vector2i = Vector2i(0, 1) if door_dir.x != 0 else Vector2i(1, 0)
				var door_span: Array = [room["door_pos"], room["door_pos"] + perp]
				for c in fcells:
					if door_span.has(c):
						all_footprints_clear_of_door = false
				var hazard_cells: Array = room.get("hazard_cells", [])
				var hazard_pos: Vector2i = room.get("hazard_pos", Vector2i(-1, -1))
				for c in fcells:
					if hazard_cells.has(c) or c == hazard_pos:
						all_footprints_clear_of_hazard = false

				## Per the request ("furniture items should be placed
				## along the walls looking away from the wall"): every
				## placed piece must be flush against one of its own
				## room's 4 walls, and furniture_facing must point away
				## from THAT SAME wall into the room.
				var fanchor: Vector2i = room.get("furniture_anchor", Vector2i(-1, -1))
				var fsize: Vector2i = room.get("furniture_size", Vector2i.ZERO)
				var facing: Vector2i = room.get("furniture_facing", Vector2i.ZERO)
				var touches_north: bool = fanchor.y == rect.position.y
				var touches_south: bool = fanchor.y + fsize.y - 1 == rect.position.y + rect.size.y - 1
				var touches_west: bool = fanchor.x == rect.position.x
				var touches_east: bool = fanchor.x + fsize.x - 1 == rect.position.x + rect.size.x - 1
				var flush: bool = touches_north or touches_south or touches_west or touches_east
				if not flush:
					all_footprints_flush_against_a_wall = false
				var facing_ok := false
				if facing == Vector2i(0, 1) and touches_north:
					facing_ok = true
				elif facing == Vector2i(0, -1) and touches_south:
					facing_ok = true
				elif facing == Vector2i(1, 0) and touches_west:
					facing_ok = true
				elif facing == Vector2i(-1, 0) and touches_east:
					facing_ok = true
				if not facing_ok:
					all_facings_point_away_from_their_wall = false

			var chest_pos: Vector2i = room.get("chest_pos", Vector2i(-1, -1))
			if room.get("quest", false):
				quest_rooms_seen += 1
				if chest_pos == Vector2i(-1, -1):
					all_quest_rooms_have_chest = false
				else:
					if not rect.has_point(chest_pos):
						all_chests_in_rect = false
					if fcells.has(chest_pos):
						all_chests_clear_of_furniture = false
				if room.get("chest_looted", false):
					all_chests_start_unlooted = false
			else:
				if chest_pos != Vector2i(-1, -1):
					all_non_quest_rooms_have_no_chest = false

	checks.append(["saw 'Nothing' rolled at least once across %d runs" % RUNS, saw_none])
	checks.append(["saw a Weapon Rack rolled at least once", saw_weapon_rack])
	checks.append(["saw a Cupboard rolled at least once", saw_cupboard])
	checks.append(["saw an Alchemy Table rolled at least once", saw_alchemy_table])
	checks.append(["saw a Torture Rack rolled at least once", saw_torture_rack])
	checks.append(["every placed footprint is exactly the requested size (2 cells for the 2x1 pieces, 4 for the 2x2 Torture Rack)", all_footprints_correct_size])
	checks.append(["every placed footprint stays fully inside its own room's rect", all_footprints_in_rect])
	checks.append(["furniture never overlaps its own room's door span", all_footprints_clear_of_door])
	checks.append(["furniture never overlaps its own room's hazard cells", all_footprints_clear_of_hazard])
	checks.append(["every placed furniture piece is flush against one of its own room's 4 walls", all_footprints_flush_against_a_wall])
	checks.append(["every furniture_facing points away from the wall the piece is actually flush against", all_facings_point_away_from_their_wall])
	checks.append(["at least one Quest room was seen across %d runs" % RUNS, quest_rooms_seen > 0])
	checks.append(["every Quest room got its own Treasure Chest (chest_pos set)", all_quest_rooms_have_chest])
	checks.append(["no non-Quest room ever got a chest_pos", all_non_quest_rooms_have_no_chest])
	checks.append(["every Quest room's chest sits inside its own rect", all_chests_in_rect])
	checks.append(["a Quest room's chest never overlaps its own furniture", all_chests_clear_of_furniture])
	checks.append(["every Quest room's chest starts unlooted", all_chests_start_unlooted])

	## --- BattleGrid consumption: impassability + markers -------------------
	if not last_state.is_empty():
		var rows: Array = last_state.get("grid_rows", [])
		var rooms: Array = last_state.get("rooms", [])
		var grid := BattleGrid.new()
		grid.generate_from_dungeon_grid(theme, rows, last_state.get("visibility", {}), rooms)

		var expected_furniture_rooms := 0
		var all_furniture_cells_impassable := true
		for room in rooms:
			if room.get("furniture_type", "none") == "none":
				continue
			expected_furniture_rooms += 1
			for c in room.get("furniture_cells", []):
				if not grid.impassable.get(c, false):
					all_furniture_cells_impassable = false
		checks.append(["BattleGrid marks every furniture cell impassable", all_furniture_cells_impassable])
		checks.append(["BattleGrid built exactly one furniture_markers entry per furnished room", grid.furniture_markers.size() == expected_furniture_rooms])

		var expected_chest_rooms := 0
		var all_chest_cells_impassable := true
		for room in rooms:
			var cp: Vector2i = room.get("chest_pos", Vector2i(-1, -1))
			if cp == Vector2i(-1, -1):
				continue
			expected_chest_rooms += 1
			if not grid.impassable.get(cp, false):
				all_chest_cells_impassable = false
		checks.append(["BattleGrid marks the Quest room's chest cell impassable", all_chest_cells_impassable])
		checks.append(["BattleGrid built exactly one room_chest_markers entry (the Quest room's own chest)", grid.room_chest_markers.size() == expected_chest_rooms and expected_chest_rooms == 1])

		if not last_room_with_furniture.is_empty():
			var found_marker := false
			for m in grid.furniture_markers:
				if m.get("anchor") == last_room_with_furniture.get("furniture_anchor"):
					found_marker = true
					checks.append(["furniture_markers entry's own type matches the room's furniture_type", m.get("type") == last_room_with_furniture.get("furniture_type")])
					checks.append(["furniture_markers entry's own cells match the room's furniture_cells", m.get("cells") == last_room_with_furniture.get("furniture_cells")])
					checks.append(["furniture_markers entry starts not-looted, matching a freshly generated room", m.get("looted") == false])
					checks.append(["furniture_markers entry's own facing matches the room's furniture_facing", m.get("facing") == last_room_with_furniture.get("furniture_facing")])
			checks.append(["found a furniture_markers entry for the sampled furnished room", found_marker])
	else:
		checks.append(["at least one non-empty dungeon was generated to test BattleGrid against", false])

	## --- Save/load round-trip -----------------------------------------------
	if not last_state.is_empty():
		var restored: Dictionary = DungeonGenerator.from_save_data(DungeonGenerator.to_save_data(last_state))
		var rooms_a: Array = last_state.get("rooms", [])
		var rooms_b: Array = restored.get("rooms", [])
		var round_trip_ok := rooms_a.size() == rooms_b.size()
		for i in range(min(rooms_a.size(), rooms_b.size())):
			var ra: Dictionary = rooms_a[i]
			var rb: Dictionary = rooms_b[i]
			if ra.get("furniture_type", "none") != rb.get("furniture_type", "none"):
				round_trip_ok = false
			if ra.get("furniture_cells", []) != rb.get("furniture_cells", []):
				round_trip_ok = false
			if ra.get("furniture_anchor", Vector2i(-1, -1)) != rb.get("furniture_anchor", Vector2i(-1, -1)):
				round_trip_ok = false
			if ra.get("furniture_size", Vector2i.ZERO) != rb.get("furniture_size", Vector2i.ZERO):
				round_trip_ok = false
			if ra.get("furniture_facing", Vector2i.ZERO) != rb.get("furniture_facing", Vector2i.ZERO):
				round_trip_ok = false
			if bool(ra.get("furniture_looted", false)) != bool(rb.get("furniture_looted", false)):
				round_trip_ok = false
			if ra.get("chest_pos", Vector2i(-1, -1)) != rb.get("chest_pos", Vector2i(-1, -1)):
				round_trip_ok = false
			if bool(ra.get("chest_looted", false)) != bool(rb.get("chest_looted", false)):
				round_trip_ok = false
		checks.append(["save/load round-trip preserves every furniture/chest field on every room", round_trip_ok])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Dungeon Furniture Generation): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
