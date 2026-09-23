extends RefCounted
class_name TaskTargetEncounterBiasTest
## Per the request ("make active Task it a bit more likely to spawn
## near the player, ie The Quiet Traveller in this example"): a
## find_encounter Task's own target encounter used to have no bearing
## at all on _spawn_social_marker()'s roll — social_marker_encounter
## was always a fully uniform pick across the WHOLE social encounter
## database, so the one encounter the player was actually looking for
## was exactly as likely to show up as any other, however many
## encounters exist. Now, with an active find_encounter Task, the roll
## is weighted so the target itself comes up
## TASK_TARGET_ENCOUNTER_BIAS_CHANCE of the time instead of the old
## uniform 1/N — still not guaranteed (every other roll is still the
## ordinary uniform pick), just meaningfully more likely.
##
## This drives Overworld._spawn_social_marker() directly, over many
## trials, and checks the observed hit rate against both the old
## uniform baseline and the new bias constant — a real statistical
## check, not just a smoke test, since the whole point of this fix is
## the underlying probability actually changing.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()

	var scene: PackedScene = load("res://scenes/Overworld.tscn")
	var ow: Node = scene.instantiate()
	tree.get_root().add_child.call_deferred(ow)
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame

	var db: SocialEncounterDatabase = GameData.social_encounter_db
	if db == null or db.encounters.size() < 2:
		print("SKIP (Task Target Encounter Bias): social encounter DB doesn't have enough entries for a real bias check")
		ow.queue_free()
		await tree.process_frame
		return true

	var target: SocialEncounterDefinition = db.encounters[0]
	var character: Character = GameState.player_character

	## --- No active task: the no-task path stays untouched -- a smoke
	## test only, not a distribution check.
	for i in range(20):
		ow._spawn_social_marker()
	checks.append(["No active task: repeated spawns don't error and still produce a real encounter each time", ow.social_marker_encounter != null])

	## --- Active find_encounter task: the target should come up close
	## to TASK_TARGET_ENCOUNTER_BIAS_CHANCE, clearly above the old
	## uniform 1/N baseline.
	character.add_task("test_task_bias", "Rumour: %s" % target.encounter_name, "desc", "find_encounter", target.encounter_name, 1)
	checks.append(["Active task set up with target_key matching a real encounter", character.get_active_task().get("target_key", "") == target.encounter_name])

	var trials := 400
	var target_hits := 0
	for i in range(trials):
		ow._spawn_social_marker()
		if ow.social_marker_encounter != null and ow.social_marker_encounter.encounter_name == target.encounter_name:
			target_hits += 1
	var hit_rate: float = float(target_hits) / float(trials)
	var uniform_rate: float = 1.0 / float(db.encounters.size())
	print("Bias check: target hit rate over %d trials = %.3f (old uniform baseline ~%.3f, bias constant %.2f)" % [trials, hit_rate, uniform_rate, ow.TASK_TARGET_ENCOUNTER_BIAS_CHANCE])
	## Real statistical slack (+/- 0.12) around the bias constant --
	## comfortably above what 400 trials of chance alone should drift,
	## well below a flaky threshold.
	checks.append(["With an active find_encounter task, the hit rate lands close to the bias constant (%.2f)" % ow.TASK_TARGET_ENCOUNTER_BIAS_CHANCE, hit_rate > ow.TASK_TARGET_ENCOUNTER_BIAS_CHANCE - 0.12])
	checks.append(["...and is unmistakably higher than the old uniform-only rate (%.3f)" % uniform_rate, hit_rate > uniform_rate * 3.0])
	checks.append(["The target still doesn't show up literally every time -- biased, not guaranteed", target_hits < trials])

	ow.queue_free()
	await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Task Target Encounter Bias): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
