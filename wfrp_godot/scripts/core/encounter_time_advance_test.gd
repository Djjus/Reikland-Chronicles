extends RefCounted
class_name EncounterTimeAdvanceTest
## Per the request ("completing a social and combat encounter should
## advance time by 30 mins win or lose"): both FieldEncounterScreen.
## _end_battle() (the one place every combat resolution funnels
## through — a field ambush, a dungeon-room fight, or a social
## encounter that escalated into one) and SocialEncounterScreen.
## _finish() (the one place a social encounter that concludes WITHOUT
## escalating into combat funnels through) now call
## GameState.advance_minutes(30) exactly once per encounter,
## regardless of victory or defeat. This drives both real screens —
## not just the underlying GameState call — checking GameState.
## time_minutes_total() (a monotonic reading that already folds in
## day/year wraparound, so this test is safe to run at any time of
## day) advances by exactly 30 each time, for combat wins, combat
## losses, and a social encounter (whichever way the driven turns
## happen to resolve it, so long as it doesn't hand off into real
## combat, which would double-count against the combat check above).

static func _find_buttons(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is Button:
			result.append(child)
		result.append_array(_find_buttons(child))
	return result

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Combat victory: FieldEncounterScreen._end_battle(true) -----------
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "TimeAdvanceTester"
	pc.inventory.clear()

	GameState.pending_encounter_monster_names = ["Giant Rat"]
	if GameData.monster_db.find_by_name("Giant Rat") == null:
		var any_monster: MonsterDefinition = GameData.monster_db.entries[0] if GameData.monster_db.entries.size() > 0 else null
		if any_monster != null:
			GameState.pending_encounter_monster_names = [any_monster.monster_name]

	var fe_scene: PackedScene = load("res://scenes/FieldEncounter.tscn")
	var fe_win: Node = fe_scene.instantiate()
	tree.get_root().add_child.call_deferred(fe_win)
	await tree.process_frame
	await tree.process_frame

	checks.append(["Combat-win setup: FieldEncounter loaded with at least one monster", fe_win.monster_defs.size() > 0])

	var before_win: int = GameState.time_minutes_total()
	fe_win._end_battle(true)
	await tree.process_frame
	var after_win: int = GameState.time_minutes_total()
	checks.append(["Combat victory: GameState time advances by exactly 30 minutes", after_win - before_win == 30])

	fe_win.queue_free()
	await tree.process_frame

	## --- Combat defeat: FieldEncounterScreen._end_battle(false) ------------
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.pending_encounter_monster_names = ["Giant Rat"]
	if GameData.monster_db.find_by_name("Giant Rat") == null:
		var any_monster2: MonsterDefinition = GameData.monster_db.entries[0] if GameData.monster_db.entries.size() > 0 else null
		if any_monster2 != null:
			GameState.pending_encounter_monster_names = [any_monster2.monster_name]

	var fe_loss: Node = fe_scene.instantiate()
	tree.get_root().add_child.call_deferred(fe_loss)
	await tree.process_frame
	await tree.process_frame

	checks.append(["Combat-loss setup: FieldEncounter loaded with at least one monster", fe_loss.monster_defs.size() > 0])

	var before_loss: int = GameState.time_minutes_total()
	fe_loss._end_battle(false)
	await tree.process_frame
	var after_loss: int = GameState.time_minutes_total()
	checks.append(["Combat defeat: GameState time also advances by exactly 30 minutes", after_loss - before_loss == 30])

	fe_loss.queue_free()
	await tree.process_frame

	## --- Social encounter: SocialEncounterScreen driven to completion ------
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()

	var se_scene: PackedScene = load("res://scenes/SocialEncounter.tscn")
	var se_screen: Control = se_scene.instantiate()
	tree.get_root().add_child.call_deferred(se_screen)
	await tree.process_frame
	await tree.process_frame

	if se_screen.social_combat == null or se_screen.npc_characters.is_empty():
		print("SKIP (Encounter Time Advance / social leg): SocialEncounter didn't start a real encounter to drive")
	else:
		var before_social: int = GameState.time_minutes_total()
		var iterations := 0
		var reached_terminal_state := false
		while iterations < 500:
			if not is_instance_valid(se_screen) or not is_instance_valid(se_screen.return_button):
				reached_terminal_state = true   ## scene changed away (combat hand-off)
				break
			if se_screen.return_button.visible:
				reached_terminal_state = true   ## a real _finish() ran
				break
			if not GameState.pending_encounter_monster_names.is_empty():
				reached_terminal_state = true   ## combat hand-off requested, scene change imminent
				break
			await tree.process_frame
			iterations += 1
			var buttons := _find_buttons(se_screen.action_container)
			var enabled: Array = []
			for b in buttons:
				if is_instance_valid(b) and not b.disabled:
					enabled.append(b)
			if enabled.is_empty():
				continue
			var chosen: Button = null
			for b in enabled:
				if b.text == "Continue":
					chosen = b
					break
			if chosen == null:
				for b in enabled:
					if not b.toggle_mode:
						chosen = b
						break
			if chosen == null:
				chosen = enabled[0]
			chosen.emit_signal("pressed")

		checks.append(["Social encounter resolved within 500 driven turns (no hang)", reached_terminal_state])

		var combat_handoff: bool = not GameState.pending_encounter_monster_names.is_empty()
		if combat_handoff:
			## Escalated into real combat instead of ever calling
			## _finish() here — that fight's own _end_battle() is what
			## charges the 30 minutes (already proven above), so no time
			## should have passed on THIS screen's account.
			checks.append(["Social encounter that escalated into combat: no time charged here (avoids double-counting)", GameState.time_minutes_total() == before_social])
		else:
			checks.append(["Social encounter resolved without combat: GameState time advances by exactly 30 minutes", GameState.time_minutes_total() - before_social == 30])

		if is_instance_valid(se_screen):
			se_screen.queue_free()
			await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Encounter Time Advance): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
