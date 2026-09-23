extends RefCounted
class_name SocialCombatAvoidFightTest
## Verifies the fix for "No way to talk your way out of a fight" (see
## claude/social_scenarios_reward_review.md's own gap description): a
## combat-flagged situation's WIN no longer unconditionally hands off
## into a real physical fight — it now depends on how decisively the
## party won the Social Combat exchange, measured by
## SocialEncounterScreen._party_composure_ratio() against
## COMBAT_AVOIDANCE_COMPOSURE_RATIO (0.5).
##
## Drives a real SocialEncounter.tscn instance (same technique
## social_combat_screen_test.gd uses) far enough to get a genuine,
## fully-wired `social_combat`/`player`/`encounter_def`, then calls
## _resolve_win() directly against a synthetic is_combat situation with
## a controlled Composure ratio — the random situation an actual
## playthrough rolls can't be relied on to be combat-flagged, or to
## land the ratio on either side of the threshold, so this is the only
## way to exercise both branches deterministically.

## history entries are pushed newest-first (push_front) and, by the time
## _resolve_win() runs, several earlier entries already exist from the
## screen's own setup (intro text, the situation hook, and so on) — so
## the notice this test is looking for isn't reliably at history[0] or
## history[history.size()-1], it's just SOMEWHERE in there. Scans every
## entry's own "notice" text rather than guessing a position.
static func _history_contains(history: Array, needle: String) -> bool:
	for entry in history:
		if str(entry.get("notice", "")).contains(needle):
			return true
	return false

static func _fresh_screen(tree: SceneTree, game_state) -> Control:
	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()
	var scene_res: PackedScene = load("res://scenes/SocialEncounter.tscn")
	var screen: Control = scene_res.instantiate()
	tree.get_root().add_child(screen)
	for i in range(10):
		await tree.process_frame
	return screen

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	var game_state = tree.get_root().get_node("/root/GameState")

	## --- Case 1: a clean win (party still at full Composure — nothing
	## has fought yet, so the natural ratio right after seating is 1.0,
	## well above the 0.5 threshold) talks the way clear: no combat
	## hand-off, the screen reaches its own _finish() instead, and the
	## "talked your way clear" notice is the one that actually printed.
	var screen_clean: Control = await _fresh_screen(tree, game_state)
	var setup_ok_clean: bool = screen_clean.social_combat != null and screen_clean.encounter_def != null and not screen_clean.social_combat.get_living("ally").is_empty()
	checks.append(["Case 1 setup: a real Social Combat seated with at least one living ally", setup_ok_clean])

	if setup_ok_clean:
		## Assigned via a typed local, not a bare `[]` literal — game_state
		## is only a dynamically-typed Node reference here (fetched via
		## get_node()), so GDScript can't infer that the target property
		## itself is declared Array[String] and coerce a bare literal into
		## it the way an in-script assignment can; an untyped empty Array
		## gets rejected by the property's own runtime type check instead.
		var no_monsters: Array[String] = []
		game_state.pending_encounter_monster_names = no_monsters
		screen_clean.chosen_situation = {
			"hook": "Test hook",
			"success_reveal": "Test reveal",
			"is_combat": true,
			"combat_monster_names": ["Test Monster"],
			"funny_loss_text": "",
		}
		var ratio_clean: float = screen_clean._party_composure_ratio()
		checks.append(["Case 1: a freshly-seated party's own Composure ratio is 1.0 (nothing has fought yet)", is_equal_approx(ratio_clean, 1.0)])

		screen_clean._resolve_win()

		checks.append(["Case 1: no combat hand-off — GameState.pending_encounter_monster_names stays empty", game_state.pending_encounter_monster_names.is_empty()])
		checks.append(["Case 1: the screen reached its own _finish() — Return button visible", is_instance_valid(screen_clean.return_button) and screen_clean.return_button.visible])
		checks.append(["Case 1: the 'talked your way clear' notice printed", _history_contains(screen_clean.history, "talked your way clear")])
		checks.append(["Case 1: the reward (XP) was still granted despite no fight", screen_clean.player.experience_total > 0])

	screen_clean.queue_free()
	for i in range(3):
		await tree.process_frame

	## --- Case 2: a narrow win (party's Composure driven below the 0.5
	## ratio floor before the check runs) still hands off into the real
	## fight — the original behaviour, now reached conditionally.
	var screen_narrow: Control = await _fresh_screen(tree, game_state)
	var setup_ok_narrow: bool = screen_narrow.social_combat != null and screen_narrow.encounter_def != null and not screen_narrow.social_combat.get_living("ally").is_empty()
	checks.append(["Case 2 setup: a real Social Combat seated with at least one living ally", setup_ok_narrow])

	if setup_ok_narrow:
		var no_monsters_2: Array[String] = []
		game_state.pending_encounter_monster_names = no_monsters_2
		## Batter every seated ally down to a low sliver of Composure —
		## whatever the real roster's Composure totals are, this puts the
		## ratio well under the 0.5 threshold without needing to know
		## those totals in advance.
		for member in screen_narrow.social_combat.combatants:
			if member.allegiance == "ally":
				member.composure_current = 1
		screen_narrow.chosen_situation = {
			"hook": "Test hook",
			"success_reveal": "Test reveal",
			"is_combat": true,
			"combat_monster_names": ["Test Monster"],
			"funny_loss_text": "",
		}
		var ratio_narrow: float = screen_narrow._party_composure_ratio()
		checks.append(["Case 2: the battered party's own Composure ratio is now under the 0.5 threshold", ratio_narrow < 0.5])

		screen_narrow._resolve_win()

		checks.append(["Case 2: the combat hand-off still fires — GameState.pending_encounter_monster_names is set", game_state.pending_encounter_monster_names == ["Test Monster"]])
		checks.append(["Case 2: the 'still coming' notice printed instead", _history_contains(screen_narrow.history, "still coming")])
		checks.append(["Case 2: the reward (XP) was still granted before the fight starts", screen_narrow.player.experience_total > 0])

	screen_narrow.queue_free()
	for i in range(3):
		await tree.process_frame

	## --- Case 3: _party_composure_ratio() itself, in isolation — a
	## malformed/empty roster (nothing to divide by) reads as a neutral
	## 1.0 ("clean") rather than crashing or forcing every combat-flagged
	## win into a fight, per that function's own comment.
	var screen_empty: Control = await _fresh_screen(tree, game_state)
	if screen_empty.social_combat != null:
		var real_combatants: Array = screen_empty.social_combat.combatants
		var no_combatants: Array[Character] = []
		screen_empty.social_combat.combatants = no_combatants
		checks.append(["Case 3: an empty combatant roster makes _party_composure_ratio() return a neutral 1.0, not crash/0", is_equal_approx(screen_empty._party_composure_ratio(), 1.0)])
		screen_empty.social_combat.combatants = real_combatants
	screen_empty.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Social Combat Avoid Fight): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
