extends RefCounted
class_name DungeonGeneratorTest
## Regression/functional test for DungeonGenerator's v2, table-driven
## builder (per the "New Dungeon building rules" request — see that
## file's own header comment for the full design). Generates the shipped
## Sewer preset many times with real random seeds and checks every hard
## rule the request laid out: a Quest room always exists and is always
## reachable, no two rooms/passages ever overlap, doors always start
## closed, room count genuinely varies (not a fixed shape), every table
## outcome (Small/Large rooms, all three Hazard Table results, wandering
## monsters) shows up across enough runs, and the save/load round-trip
## preserves every new field.

const RUNS := 80

static func run_test(_tree) -> bool:
	var checks: Array = []

	var theme: DungeonThemeDefinition = GameData.dungeon_themes.get("sewer")
	checks.append(["sewer theme is registered in GameData", theme != null])
	if theme == null:
		print("RESULT (DungeonGenerator): SOME FAILED (theme missing, aborting)")
		return false
	checks.append(["theme has quest_room_monster_names", theme.quest_room_monster_names.size() > 0])
	checks.append(["theme has monster_lair_monster_names", theme.monster_lair_monster_names.size() > 0])
	checks.append(["theme has monster_patrol_monster_names", theme.monster_patrol_monster_names.size() > 0])

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var all_valid := true
	var all_have_quest := true
	var all_quest_reachable := true
	var all_rooms_reachable := true
	var all_no_overlap := true
	var all_doors_closed := true
	var all_entrance_visible := true
	var min_rooms := 999
	var max_rooms := 0
	var total_rooms := 0
	var saw_small := false
	var saw_large_lair := false
	var saw_hazard_chasm := false
	var saw_hazard_spike := false
	var saw_hazard_monster_patrol := false
	var saw_wandering_monsters := false
	var seen_grids: Dictionary = {}
	var all_chasms_span_width := true   ## per the request "Chasm's should span the width... of rooms they are in"
	var all_chasm_cells_in_room_and_open := true

	for i in range(RUNS):
		var state: Dictionary = DungeonGenerator.generate(theme, rng)
		if state.is_empty():
			all_valid = false
			continue

		var rooms: Array = state.get("rooms", [])
		total_rooms += rooms.size()
		min_rooms = mini(min_rooms, rooms.size())
		max_rooms = maxi(max_rooms, rooms.size())

		var has_quest := false
		for room in rooms:
			if room.get("door_open", true) != false:
				all_doors_closed = false
			if room.get("quest", false):
				has_quest = true
			match room.get("room_type", ""):
				"small":
					saw_small = true
				"large":
					saw_large_lair = true
			match room.get("hazard_type", "none"):
				"chasm":
					saw_hazard_chasm = true
					var hcells: Array = room.get("hazard_cells", [])
					var hrect: Rect2i = room["rect"]
					if hcells.size() != hrect.size.x and hcells.size() != hrect.size.y:
						all_chasms_span_width = false
					for hc in hcells:
						## Every chasm cell must be a real cell of its
						## OWN room (never poking out into the corridor
						## or a neighboring room) and must line up on
						## the grid as actual floor, not a stray wall
						## character — a chasm is a real physical gap
						## in a room's own floor, not free-floating.
						if not hrect.has_point(hc):
							all_chasm_cells_in_room_and_open = false
						var hrow: String = state.get("grid_rows", [])[hc.y] if hc.y >= 0 and hc.y < state.get("grid_rows", []).size() else ""
						if hc.x < 0 or hc.x >= hrow.length() or hrow[hc.x] != theme.floor_char:
							all_chasm_cells_in_room_and_open = false
				"spike_trap":
					saw_hazard_spike = true
				"monster_patrol":
					saw_hazard_monster_patrol = true
		if not has_quest:
			all_have_quest = false

		for a_i in range(rooms.size()):
			for b_i in range(a_i + 1, rooms.size()):
				var a: Rect2i = rooms[a_i]["rect"]
				var b: Rect2i = rooms[b_i]["rect"]
				if a.intersects(b):
					all_no_overlap = false

		## Reachability: flood-fill the grid from the entrance, confirm
		## every room's door (and, separately, the Quest room's own door)
		## is in the reached set.
		var grid_rows: Array = state.get("grid_rows", [])
		var walkable: Dictionary = {}
		for y in range(grid_rows.size()):
			var row: String = grid_rows[y]
			for x in range(row.length()):
				if row[x] != theme.wall_char:
					walkable[Vector2i(x, y)] = true
		var entrance: Vector2i = state.get("entrance_pos", Vector2i.ZERO)
		var reached: Dictionary = {}
		if walkable.has(entrance):
			var stack: Array = [entrance]
			reached[entrance] = true
			while not stack.is_empty():
				var cur: Vector2i = stack.pop_back()
				for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
					var nxt: Vector2i = cur + d
					if walkable.has(nxt) and not reached.has(nxt):
						reached[nxt] = true
						stack.append(nxt)
		for room in rooms:
			if not reached.has(room["door_pos"]):
				all_rooms_reachable = false
				if room.get("quest", false):
					all_quest_reachable = false

		var visibility: Dictionary = state.get("visibility", {})
		if int(visibility.get(entrance, -1)) != 2:
			all_entrance_visible = false

		for seg in state.get("hallway_segments", []):
			if seg.get("has_wandering_monsters", false):
				saw_wandering_monsters = true

		seen_grids[str(grid_rows)] = true

	checks.append(["generation never returned an empty state", all_valid])
	checks.append(["every generated dungeon (%d runs) has a Quest room" % RUNS, all_have_quest])
	checks.append(["the Quest room is always reachable from the entrance", all_quest_reachable])
	checks.append(["every room's door is reachable from the entrance", all_rooms_reachable])
	checks.append(["no two rooms ever overlap", all_no_overlap])
	checks.append(["every door starts closed", all_doors_closed])
	checks.append(["entrance cell starts at visibility=2 (visible)", all_entrance_visible])
	checks.append(["room count genuinely varies across runs (min=%d, max=%d)" % [min_rooms, max_rooms], min_rooms < max_rooms])
	checks.append(["saw at least one Small room across %d runs" % RUNS, saw_small])
	checks.append(["saw at least one Large (Monster Lair) room across %d runs" % RUNS, saw_large_lair])
	checks.append(["saw at least one Chasm hazard across %d runs" % RUNS, saw_hazard_chasm])
	checks.append(["every Chasm's hazard_cells spans its room's own width axis, not a single point", all_chasms_span_width])
	checks.append(["every Chasm cell is a real floor cell of its own room", all_chasm_cells_in_room_and_open])
	checks.append(["saw at least one Spike trap hazard across %d runs" % RUNS, saw_hazard_spike])
	checks.append(["saw at least one Monster Patrol hazard room across %d runs" % RUNS, saw_hazard_monster_patrol])
	checks.append(["saw at least one wandering-monsters corridor segment across %d runs" % RUNS, saw_wandering_monsters])
	checks.append(["at least 2 distinct grid layouts seen across %d runs (real randomness, not pregen)" % RUNS, seen_grids.size() >= 2])
	print("Average rooms per generated dungeon: %.1f" % (float(total_rooms) / RUNS))

	## Determinism-adjacent sanity: same theme, a FRESH rng seeded
	## identically, produces an identical layout both times — the
	## generator doesn't rely on any hidden global state between calls.
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 12345
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 12345
	var state_a: Dictionary = DungeonGenerator.generate(theme, rng_a)
	var state_b: Dictionary = DungeonGenerator.generate(theme, rng_b)
	checks.append(["a fixed-seed run still produces a valid dungeon", not state_a.is_empty() and not state_a.get("rooms", []).is_empty()])
	checks.append(["a fixed-seed run is fully deterministic (identical grid_rows)", state_a.get("grid_rows", []) == state_b.get("grid_rows", [])])

	## Save/load round-trip: to_save_data()/from_save_data() must
	## reproduce an identical DungeonState, including the Vector2i-keyed
	## visibility dict and every new per-room/per-segment field.
	state_a["visibility"][Vector2i(3, 3)] = 1   ## force a non-trivial, non-entrance entry too
	var saved: Dictionary = DungeonGenerator.to_save_data(state_a)
	var restored: Dictionary = DungeonGenerator.from_save_data(saved)
	checks.append(["save/load round-trip preserves entrance_pos", restored.get("entrance_pos") == state_a.get("entrance_pos")])
	checks.append(["save/load round-trip preserves grid_rows", restored.get("grid_rows") == state_a.get("grid_rows")])
	checks.append(["save/load round-trip preserves room count", restored.get("rooms", []).size() == state_a.get("rooms", []).size()])
	var orig_rooms: Array = state_a.get("rooms", [])
	var restored_rooms: Array = restored.get("rooms", [])
	var room_fields_ok := true
	for i in range(orig_rooms.size()):
		var o: Dictionary = orig_rooms[i]
		var r: Dictionary = restored_rooms[i]
		if o.get("room_type") != r.get("room_type") or o.get("quest") != r.get("quest") \
				or o.get("hazard_type") != r.get("hazard_type") or o.get("hazard_pos") != r.get("hazard_pos") \
				or o.get("hazard_cells", []) != r.get("hazard_cells", []) \
				or o.get("door_dir") != r.get("door_dir") or o.get("monster_names") != r.get("monster_names"):
			room_fields_ok = false
	checks.append(["save/load round-trip preserves room_type/quest/hazard_type/hazard_pos/hazard_cells/door_dir/monster_names", room_fields_ok])
	var orig_segs: Array = state_a.get("hallway_segments", [])
	var restored_segs: Array = restored.get("hallway_segments", [])
	var segs_ok: bool = orig_segs.size() == restored_segs.size()
	for i in range(orig_segs.size()):
		if orig_segs[i].get("has_wandering_monsters") != restored_segs[i].get("has_wandering_monsters"):
			segs_ok = false
	checks.append(["save/load round-trip preserves hallway_segments' has_wandering_monsters", segs_ok])
	var restored_vis: Dictionary = restored.get("visibility", {})
	checks.append(["save/load round-trip preserves visibility as Vector2i keys", int(restored_vis.get(Vector2i(3, 3), -1)) == 1])
	checks.append(["save/load round-trip preserves the entrance's own visibility entry", int(restored_vis.get(state_a.get("entrance_pos"), -1)) == 2])
	checks.append(["from_save_data({}) round-trips to an empty state", DungeonGenerator.from_save_data({}).is_empty()])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (DungeonGenerator): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
