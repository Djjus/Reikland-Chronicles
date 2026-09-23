extends RefCounted
class_name RatCatcherGuildTest
## Regression/functional test for the Rat Catcher's Guild quest hook
## (spec §10): the new "Rat Catcher's Guild" CityLocationDefinition in
## Ubersreik, CityScreen's new "guild" radial branch offering "Talk",
## and RatCatcherGuildScreen's own quest/close hand-offs — one flow all
## the way to FieldEncounter's own exploration mode (accepting the
## quest), and a second flow back to CityScreen (closing without taking
## the quest). Each flow ends in a real change_scene_to_file(), so —
## same documented gotcha as this project's other scene-transition tests
## (CityScreenTest, FieldEncounterExplorationTest) — each flow's own
## final scene change is the last thing that flow does, with nothing
## reading `self`/get_tree() context from the screen it just left
## afterward.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []
	var check := func(label: String, passed: bool) -> void:
		checks.append([label, passed])

	## --- Data + radial wiring -------------------------------------------
	## CityScreen's own CITY_LOCATIONS const isn't globally accessible
	## (a plain `const` on that script, not an autoload) — load the same
	## resource directly by path instead.
	var city_locations: CityLocationList = load("res://data/maps/ubersreik_city_locations.tres")
	var loc: CityLocationDefinition = null
	for l in city_locations.locations:
		if l.location_name == "Rat Catcher's Guild":
			loc = l
			break
	check.call("Rat Catcher's Guild location exists in Ubersreik's location list", loc != null)
	if loc == null:
		print("RESULT (RatCatcherGuild): SOME FAILED (location missing, aborting)")
		return false
	check.call("location category is \"guild\"", loc.category == "guild")
	check.call("location starts unlocked", loc.unlocked)

	## --- Flow 1: City -> Guild -> Quest -> FieldEncounter (exploration mode) ---
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.dungeon_state = {}

	var city1 = load("res://scenes/CityScreen.tscn").instantiate()
	tree.get_root().add_child.call_deferred(city1)
	for i in range(4):
		await tree.process_frame

	city1.map_view.party_token_pos = loc.map_position
	var actions: Array = city1._radial_actions_for(loc)
	var has_talk := false
	for a in actions:
		if a.get("key") == "talk" and a.get("label") == "Talk":
			has_talk = true
	check.call("standing at the Guild offers a \"Talk\" radial action", has_talk)

	city1._on_radial_action(loc, "talk")
	check.call("choosing Talk records which city to return to", GameState.pending_guild_city_id == "ubersreik")
	## city1 was added as a plain extra child of root, never as
	## tree.current_scene itself (only the runner scene started as
	## that) — change_scene_to_file() above therefore freed the RUNNER,
	## not city1, leaving city1 a permanent orphan under root unless
	## freed here explicitly. Left alone, it (and city2 below) would
	## keep accumulating as same-named "CityScreen" siblings, and a
	## later CityScreen instantiation would get silently auto-renamed
	## ("CityScreen2") to avoid the collision — breaking any later
	## `.name == "CityScreen"` check for a reason that has nothing to
	## do with the actual feature being tested.
	city1.queue_free()
	for i in range(4):
		await tree.process_frame
	var guild1 = tree.current_scene
	check.call("Talk transitions to RatCatcherGuildScreen, in place of CityScreen", guild1 != null and guild1.name == "RatCatcherGuildScreen")

	if guild1 != null and guild1.name == "RatCatcherGuildScreen":
		check.call("quest not yet taken shows the initial offer text", guild1.quest_button.text == "Quest: Clear the Sewers")
		guild1._on_quest_pressed()
		check.call("accepting the quest queues the sewer dungeon theme", GameState.pending_dungeon_theme_id == "sewer")
		for i in range(4):
			await tree.process_frame
		var dungeon1 = tree.current_scene
		check.call("accepting the quest transitions straight into exploration mode", dungeon1 != null and not dungeon1.dungeon_state.is_empty())
		check.call("the generated dungeon is the sewer theme", dungeon1 != null and dungeon1.dungeon_state.get("theme_id", "") == "sewer")

	## --- Flow 2: City -> Guild -> Close -> City (no quest taken) ---------
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.dungeon_state = {}

	var city2 = load("res://scenes/CityScreen.tscn").instantiate()
	tree.get_root().add_child.call_deferred(city2)
	for i in range(4):
		await tree.process_frame

	city2.map_view.party_token_pos = loc.map_position
	city2._on_radial_action(loc, "talk")
	city2.queue_free()   ## same orphan-avoidance as city1 above
	for i in range(4):
		await tree.process_frame
	var guild2 = tree.current_scene
	check.call("a second, independent Talk also reaches RatCatcherGuildScreen", guild2 != null and guild2.name == "RatCatcherGuildScreen")

	if guild2 != null and guild2.name == "RatCatcherGuildScreen":
		guild2._on_close()
		for i in range(4):
			await tree.process_frame
		var city3 = tree.current_scene
		check.call("closing the Guild without a quest returns to CityScreen", city3 != null and city3.name == "CityScreen")
		check.call("returning from the Guild lands back on the same city (Ubersreik)", city3 != null and city3.city_id == "ubersreik")
		check.call("no dungeon was generated on the close-without-quest path", GameState.dungeon_state.is_empty())

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (RatCatcherGuild): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
