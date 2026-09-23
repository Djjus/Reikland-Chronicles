extends RefCounted
class_name CaveDungeonTest
## Regression test for the Giessingen NE Cave rework: checks the new
## "cave" theme is registered with the Undead faction and its own
## cave-specific floor art, that the NORMAL procedural
## DungeonGenerator.generate() (not the Goblin Fort's fixed-room mode —
## "Similar to Sewer dungeon" per the request) produces a sane branching
## layout from it, that every monster name on its tables resolves to a
## real Undead MonsterDefinition, and that BattleGrid can consume the
## result without error.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Case 1: theme registered with the right identity.
	var game_data = tree.get_root().get_node("/root/GameData")
	var theme: DungeonThemeDefinition = game_data.dungeon_themes.get("cave")
	checks.append(["Case 1: cave theme is registered in GameData.dungeon_themes", theme != null])
	if theme == null:
		for chk in checks:
			print(("PASS  " if chk[1] else "FAIL  ") + chk[0])
		return false
	checks.append(["Case 1: monster_faction is Undead", theme.monster_faction == "Undead"])
	checks.append(["Case 1: has its own 8 cave floor texture variants", theme.floor_textures.size() == 8])

	## --- Case 2: every monster name on the cave's tables resolves to a
	## real, actually-Undead MonsterDefinition — catches a typo'd name
	## silently falling through to nothing at spawn time.
	var all_names: Array[String] = []
	all_names.append_array(theme.quest_room_monster_names)
	all_names.append_array(theme.monster_lair_monster_names)
	all_names.append_array(theme.monster_patrol_monster_names)
	var all_resolve := true
	var all_undead := true
	for mname in all_names:
		var mdef: MonsterDefinition = game_data.monster_db.find_by_name(mname)
		if mdef == null:
			all_resolve = false
			print("    (missing monster: ", mname, ")")
		elif mdef.faction != "Undead":
			all_undead = false
			print("    (non-Undead monster on cave table: ", mname, " is ", mdef.faction, ")")
	checks.append(["Case 2: every cave monster table name resolves to a real MonsterDefinition", all_resolve])
	checks.append(["Case 2: every resolved cave monster is genuinely Undead-faction", all_undead])

	## --- Case 3: the NORMAL procedural generator (not generate_fixed_room)
	## produces a real branching dungeon from this theme.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var state: Dictionary = DungeonGenerator.generate(theme, rng)
	var rows: Array = state.get("grid_rows", [])
	checks.append(["Case 3: generate() produced a non-empty grid", rows.size() > 0])
	checks.append(["Case 3: generate() produced at least one room", state.get("rooms", []).size() > 0])
	var entrance: Vector2i = state.get("entrance_pos", Vector2i(-1, -1))
	checks.append(["Case 3: generate() placed a real entrance_pos", entrance != Vector2i(-1, -1)])

	## --- Case 4: BattleGrid can actually build from this without
	## crashing, and the entrance is walkable.
	var grid := BattleGrid.new()
	grid.generate_from_dungeon_grid(theme, rows, state.get("visibility", {}), state.get("rooms", []))
	checks.append(["Case 4: the entrance cell is NOT impassable", not grid.impassable.get(entrance, false)])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Cave Dungeon): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
