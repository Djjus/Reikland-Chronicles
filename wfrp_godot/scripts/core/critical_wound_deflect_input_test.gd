extends RefCounted
class_name CriticalWoundDeflectInputTest
## Regression test for the real crash reported by the user: "deflecting on
## my body Armor from a crit in combat crashed the game."
##
## Root cause (see the matching comments on
## FieldEncounterScreen.awaiting_critical_wound_choice and
## _handle_critical_wound_on_player): the Accept/Deflect prompt used to
## reuse the generic awaiting_player_target flag instead of getting its
## own dedicated flag — the exact same reentrancy bug class already fixed
## for awaiting_fatal_moment_choice, aoe_target_mode_active and
## ranged_target_mode_active elsewhere in this file. Because
## selected_target survives across turns, pressing Enter while the
## Accept/Deflect prompt was open (with a target still selected from
## earlier in the fight, and the player not yet having acted this turn)
## fell straight through _unhandled_input's KEY_ENTER chain into the
## "confirm attack on selected_target" branch — launching a second,
## concurrent attack while the prompt's own `while awaiting_X: await ...`
## loop was still suspended, corrupting shared turn state.
##
## This test reproduces the exact conditions that triggered the crash
## (a target selected, no action used yet this turn, the Accept/Deflect
## prompt open) and confirms: (1) the dedicated flag — not
## awaiting_player_target — is what's true while the prompt is open, and
## (2) pressing Enter while it's open does NOT launch a second attack and
## leaves the prompt open, exactly like the already-fixed
## awaiting_fatal_moment_choice prompt. It also exercises the Deflect
## button itself end-to-end (the specific action from the bug report),
## confirming a full Deflect completes cleanly: the struck armour takes 1
## point of Armour Damage and the prompt closes without incident.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "DeflectTester"
	## Per game_state.gd's own default, a fresh player already has
	## "Leather Jack" equipped (locations: Body, Left Arm, Right Arm, 1
	## AP) — exactly what the bug report describes ("deflecting on my
	## body Armor"), so can_deflect_critical_wound("Body") is true with
	## no extra setup.
	pc.equipped_armour = ["Leather Jack"]
	pc.armour_damage.clear()

	var no_pool: Array[String] = []
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	## Flakiness fix: pin Dice's own RNG stream to a fixed, verified seed
	## (per dice.gd's own doc comment: "swap the RNG's seed in tests") —
	## this test's setup doesn't force the monster's own group size or
	## roll outcomes, so an unseeded run occasionally hit an unlucky
	## combination (e.g. an encounter roll landing differently) that
	## tripped up an assertion further down. A fixed seed makes the whole
	## sequence fully reproducible. Also reseeds Godot's own global RNG
	## (the bare randf()/randi() calls EncounterGroupBuilder/
	## field_encounter_screen.gd use for monster-group size, lantern
	## chance, etc. — which Dice.rng does NOT cover), so this test's
	## outcome no longer depends on how many global-RNG draws whatever
	## ran earlier in the same process already consumed.
	Dice.rng.seed = 2
	seed(2)

	var scene: PackedScene = load("res://scenes/FieldEncounter.tscn")
	var fe: Node = scene.instantiate()
	tree.get_root().add_child.call_deferred(fe)
	await tree.process_frame
	await tree.process_frame

	var player: Character = fe.player
	checks.append(["setup: player genuinely has deflectable armour at Body", player.can_deflect_critical_wound("Body")])
	var starting_damage: int = player.get_total_armour_damage("Leather Jack")

	## Reproduce the exact pre-crash conditions: a target still selected
	## from earlier in the fight, and the player not having used their
	## action yet this turn — precisely the state _on_player_attack's own
	## guard (`if not awaiting_player_target or action_used_this_turn:
	## return`) needs to actually launch a real attack instead of
	## silently refusing.
	var monster: Character = fe.monsters[0] if fe.monsters.size() > 0 else null
	checks.append(["setup: a monster genuinely exists to select as the stale target", monster != null])
	if monster == null:
		print("RESULT (Critical Wound Deflect Input): SETUP FAILED (no monster)")
		return false
	fe.selected_target = monster
	fe.action_used_this_turn = false
	var monster_wounds_before: int = monster.wounds_current

	var result := CombatResolver.AttackResult.new()
	result.critical_wound_location = "Body"
	result.critical_wound_causes_death = false
	result.critical_wound_entry = {
		"name": "Test Gash",
		"flavor": "A testing wound, nothing more.",
		"wounds": "1",
		"conditions": {},
		"test_or_condition": {},
		"amputation": "",
	}

	## Real crits on the player land while it is NOT the player's own
	## target-selection turn (e.g. mid-resolution of a monster's attack,
	## or a Critical Parry counter-strike) — deliberately forced false
	## here so the test doesn't depend on which side unseeded initiative
	## happened to go to. This is exactly the state a stale selected_target
	## from an earlier turn becomes dangerous in.
	fe.awaiting_player_target = false

	## Fire the prompt without awaiting it fully — it suspends at its own
	## `while awaiting_critical_wound_choice: await get_tree().process_frame`
	## loop, exactly like a real crit landing on the player mid-battle.
	fe._handle_critical_wound_on_player(result)
	for i in range(3): await tree.process_frame

	## The core regression check: before the fix, awaiting_player_target
	## was the flag forced true here (the bug itself), regardless of
	## whether it was genuinely the player's turn to pick a target. After
	## the fix, the prompt uses its own dedicated flag and leaves
	## awaiting_player_target alone.
	checks.append(["the Accept/Deflect prompt is genuinely open (awaiting_critical_wound_choice)", fe.awaiting_critical_wound_choice])
	checks.append(["awaiting_player_target is genuinely NOT hijacked by this prompt (the actual bug)", not fe.awaiting_player_target])

	## Simulate the exact keystroke that used to crash the game: Enter,
	## with a target still selected and no action used yet this turn.
	var enter_event := InputEventKey.new()
	enter_event.keycode = KEY_ENTER
	enter_event.pressed = true
	fe._unhandled_input(enter_event)
	for i in range(3): await tree.process_frame

	checks.append(["Enter did NOT launch a second, concurrent attack on the stale selected_target", monster.wounds_current == monster_wounds_before])
	checks.append(["Enter did NOT mark an action used this turn (no attack fired)", not fe.action_used_this_turn])
	checks.append(["the Accept/Deflect prompt is still genuinely open after the stray Enter press", fe.awaiting_critical_wound_choice])

	## Now actually complete the flow the bug report describes: choose
	## Deflect. Find the "Deflect (...)" button the prompt built and
	## press it, same as a real click would.
	var deflect_btn: Button = null
	for child in fe.target_container.get_children():
		if child is Button and String(child.text).begins_with("Deflect"):
			deflect_btn = child
			break
	checks.append(["a genuine Deflect button was offered (armour is deflectable)", deflect_btn != null])
	if deflect_btn != null:
		deflect_btn.pressed.emit()
	for i in range(5): await tree.process_frame

	checks.append(["the prompt genuinely closed after choosing Deflect", not fe.awaiting_critical_wound_choice])
	## Per-location Armour Damage fix (a real bug-report correction:
	## "a Leather Jack has 3 locations, Body, Left Arm, Right Arm, each
	## with their own 1 AP — for it to be completely destroyed all 3
	## locations need to be at 0 AP"): a single Deflect at Body only
	## spends Body's own 1 AP pool — Left Arm and Right Arm stay fully
	## intact, so Leather Jack survives, still equipped, merely damaged
	## at that one location.
	checks.append(["Deflect genuinely spent a point of Armour Damage on the struck piece", player.get_total_armour_damage("Leather Jack") == starting_damage + 1])
	checks.append(["...but only at the struck location — Leather Jack stays equipped, NOT destroyed outright (its other locations, e.g. Left Arm, are untouched)", player.equipped_armour.has("Leather Jack") and player.get_armour_points("Left Arm") >= 1])
	checks.append(["the player did not receive the wound's Condition effect (deflected, not accepted)", not player.has_condition("Bleeding")])

	## Cleanup fix: this FieldEncounter instance was never freed after
	## the test finished — unlike every other test that owns its own fe
	## (see combat_reroll_test.gd's fe1.queue_free()/fe2.queue_free()),
	## meaning a run of this test back-to-back with itself (or as part
	## of the full suite) left a live, still-_process()-ing
	## FieldEncounterScreen sitting in the tree indefinitely. Freeing it
	## here matches the established pattern and stops these from piling
	## up in the background across repeated runs.
	fe.queue_free()
	await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Critical Wound Deflect Input): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
