extends RefCounted
class_name TavernNameTitleTest
## Regression/functional test for the follow-up request ("add The
## Exploding Pig as the 2nd Tavern, and make the tavern screens a
## distinct by add the tavern name to the Tavern (- Name) title on the
## tavern screen. and hook it up for access."): drives a real
## TavernScreen instance (same "real scene instantiation, not mocked-out
## pieces" convention as CityScreenTest) and checks that GameState.
## pending_tavern_name (set by CityScreen._enter_tavern() right before
## handing off to Tavern.tscn) actually reaches the screen's own title —
## "The Tavern - <Name>" once a real name is known — is consumed exactly
## once (so it can't leak into a later, unrelated Tavern visit), and
## that a visit with no pending name at all falls back to the previous
## plain "The Tavern" rather than showing something blank or broken.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	await tree.process_frame
	await tree.process_frame

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()

	## Visit 1: a real hand-off from a specific tavern, same as
	## CityScreen._enter_tavern() actually performs (set the pending
	## field, then load Tavern.tscn fresh — no change_scene_to_file()
	## involved here since this test instantiates the scene directly
	## rather than routing through a live CityScreen, so none of this
	## project's documented "real scene change kills the test's own
	## coroutine" gotcha applies).
	GameState.pending_tavern_name = "The Exploding Pig"
	var ts1 = load("res://scenes/Tavern.tscn").instantiate()
	tree.get_root().add_child(ts1)
	for i in range(3):
		await tree.process_frame

	checks.append(["visit 1: status label names the real tavern (\"%s\")" % ts1.status_label.text, ts1.status_label.text.findn("The Exploding Pig") != -1])
	checks.append(["visit 1: pending_tavern_name was consumed by _ready() (read once, then cleared)", GameState.pending_tavern_name == ""])

	ts1.queue_free()
	await tree.process_frame

	## Visit 2: no pending name set at all (e.g. some future entry point
	## that doesn't go through CityScreen._enter_tavern()) — must fall
	## back to the original plain "The Tavern" title, not a blank or
	## malformed one.
	var ts2 = load("res://scenes/Tavern.tscn").instantiate()
	tree.get_root().add_child(ts2)
	for i in range(3):
		await tree.process_frame

	checks.append(["visit 2 (no pending name): falls back to the plain original title (\"%s\")" % ts2.status_label.text, ts2.status_label.text.findn("The Tavern") != -1 and ts2.status_label.text.findn(" - ") == -1])

	ts2.queue_free()
	await tree.process_frame

	## Visit 3: a SECOND, different tavern's name — proves this isn't
	## somehow hardcoded to "The Exploding Pig" from visit 1.
	GameState.pending_tavern_name = "The Red Moon Inn"
	var ts3 = load("res://scenes/Tavern.tscn").instantiate()
	tree.get_root().add_child(ts3)
	for i in range(3):
		await tree.process_frame

	checks.append(["visit 3: a second, different tavern's own name also reaches the title (\"%s\")" % ts3.status_label.text, ts3.status_label.text.findn("The Red Moon Inn") != -1])

	ts3.queue_free()
	await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Tavern Name Title): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
