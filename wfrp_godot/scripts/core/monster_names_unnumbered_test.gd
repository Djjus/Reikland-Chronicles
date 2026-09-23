extends RefCounted
class_name MonsterNamesUnnumberedTest
## Regression test for the request ("lets only number non-unique
## enemies... actually dont number enemies at all"): monster group
## spawning used to suffix EVERY monster in the group with its raw index
## (" 1", " 2", ...) whenever the group had more than one monster in it
## at all — so a lone Wolf standing next to two Bears read "Wolf 1",
## "Bear 2", "Bear 3", and even three genuinely distinct monster types
## (Wolf, Bear, Goblin) each got a pointless " 1"/" 2"/" 3" suffix despite
## there being no ambiguity to resolve. Per the final version of the
## request, this numbering is removed outright — no replacement
## disambiguation — since every other piece of monster-identity tracking
## in this file (battle_positions, monster_defs, weapons,
## monster_focus_target) is keyed by the Character object itself, not by
## name.
##
## Drives a real FieldEncounter spawn with a genuinely mixed group (one
## Wolf, two Bears — a real WFRP monster and a real repeat) via
## GameState.pending_encounter_monster_names, and asserts every spawned
## monster's character_name is its exact, unsuffixed monster_name.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var no_pool: Array[String] = []
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	GameState.pending_encounter_monster_names = ["Wolf", "Bear", "Bear"]

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(6):
		await tree.process_frame

	checks.append(["setup: three monsters genuinely spawned", fe.monsters.size() == 3])

	var names: Array = []
	for m in fe.monsters:
		names.append(m.character_name)
	print("DEBUG spawned monster names: ", names)

	var wolves := 0
	var bears := 0
	var any_numbered := false
	for n in names:
		if String(n).findn("wolf") != -1:
			wolves += 1
			checks.append(["THE BUG: the lone Wolf's name is exactly 'Wolf', no suffix", n == "Wolf"])
		elif String(n).findn("bear") != -1:
			bears += 1
			checks.append(["THE BUG: a Bear's name is exactly 'Bear', no numbered suffix (%s)" % n, n == "Bear"])
		if n.to_lower().ends_with(" 1") or n.to_lower().ends_with(" 2") or n.to_lower().ends_with(" 3"):
			any_numbered = true
	checks.append(["setup: found exactly 1 Wolf and 2 Bears in the spawn", wolves == 1 and bears == 2])
	checks.append(["no spawned monster name carries a numbered suffix at all", not any_numbered])

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
	print("RESULT (Monster Names Unnumbered): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
