extends RefCounted
class_name ProneRecoveryTest
## Prone auto-recovery spec: "let make sure that out of combat characters
## with the prone condition automatically lose it if they have 1 or more
## HP. In combat characters should have the option to Stand Up, if prone
## and Wounds have 1 HP or more. They should Have the option to spend
## Resolve to remove any condition on them, if they remove prone in this
## way automatically set their HP to 1 (unless it is already higher).
## These new buttons should be presented in the movement / Free actions
## section."
##
## Group A (direct Character/GameState logic, no scene tree needed):
## GameState.in_field_encounter gating of the wounds_current setter's
## Prone auto-clear, attempt_stand_up()'s 0-Wounds refusal,
## attempt_spend_resolve_remove_condition()'s Wounds-to-1 rule (and that
## it leaves Wounds alone both when already above 1 and when the
## Condition removed isn't Prone at all).
##
## Group B (live FieldEncounterScreen, fe mode): Stand Up/Spend Resolve
## are offered from the "Movement / Free Actions" column and NEVER from
## "Attack / Defence" (the whole reason they moved — that column is
## skipped entirely during exploration); clicking Stand Up genuinely
## clears Prone and spends the Move; GameState.in_field_encounter is
## true for the screen's lifetime and false again once it tears down;
## the battle-end sweep catches a party member left Prone but already
## healed above 0 Wounds the instant the screen exits.

static func run_test(fe) -> bool:
	var checks: Array = []

	## --- Group A: direct Character/GameState logic --------------------
	GameState.in_field_encounter = false

	## A1/A2: out-of-combat auto-clear fires; in-combat it's suppressed.
	var c1 := Character.new()
	c1.wounds_max = 10
	c1.wounds_current = 0
	c1.conditions["Prone"] = 1
	c1.wounds_current = 5   ## healed back up, out of combat
	checks.append(["Out of combat: healing back above 0 Wounds auto-clears Prone", not c1.conditions.has("Prone")])

	GameState.in_field_encounter = true
	var c2 := Character.new()
	c2.wounds_max = 10
	c2.wounds_current = 0
	c2.conditions["Prone"] = 1
	c2.wounds_current = 5   ## healed back up, genuinely mid-FieldEncounter
	checks.append(["In combat (GameState.in_field_encounter true): the same heal does NOT auto-clear Prone", c2.conditions.has("Prone")])
	GameState.in_field_encounter = false

	## A3/A4: attempt_stand_up()'s own Wounds gate.
	var c3 := Character.new()
	c3.wounds_max = 10
	c3.wounds_current = 0
	c3.conditions["Prone"] = 1
	var stood_at_zero: bool = c3.attempt_stand_up()
	checks.append(["attempt_stand_up() refuses at 0 Wounds (RAW: can only crawl)", not stood_at_zero and c3.conditions.has("Prone")])
	## Healed to 3 Wounds while genuinely "in combat" (in_field_encounter
	## true) — otherwise the wounds_current setter's own out-of-combat
	## auto-clear would remove Prone right here, before attempt_stand_up()
	## itself is ever called, making this check vacuous rather than a
	## real test of attempt_stand_up()'s own clearing behaviour.
	GameState.in_field_encounter = true
	c3.wounds_current = 3
	var stood_with_wounds: bool = c3.attempt_stand_up()
	GameState.in_field_encounter = false
	checks.append(["attempt_stand_up() succeeds and clears Prone once Wounds are 1+", stood_with_wounds and not c3.conditions.has("Prone")])

	## A5/A6: attempt_spend_resolve_remove_condition()'s Wounds-to-1 rule.
	var c4 := Character.new()
	c4.wounds_max = 10
	c4.wounds_current = 0
	c4.resolve = 1
	c4.conditions["Prone"] = 1
	c4.attempt_spend_resolve_remove_condition("Prone")
	checks.append(["Spend Resolve removing Prone from 0 Wounds sets Wounds to exactly 1", c4.wounds_current == 1])

	var c5 := Character.new()
	c5.wounds_max = 10
	c5.wounds_current = 6
	c5.resolve = 1
	c5.conditions["Prone"] = 1
	c5.attempt_spend_resolve_remove_condition("Prone")
	checks.append(["...but leaves Wounds completely untouched if already higher (not a flat +1)", c5.wounds_current == 6])

	## A7: removing a non-Prone Condition never touches Wounds at all.
	var c6 := Character.new()
	c6.wounds_max = 10
	c6.wounds_current = 0
	c6.resolve = 1
	c6.conditions["Bleeding"] = 1
	c6.attempt_spend_resolve_remove_condition("Bleeding")
	checks.append(["Removing a non-Prone Condition (Bleeding) leaves 0 Wounds at 0, not bumped to 1", c6.wounds_current == 0 and not c6.conditions.has("Bleeding")])

	## A8/A9: the usual no-op guards, untouched by this change.
	var c7 := Character.new()
	c7.resolve = 0
	c7.conditions["Prone"] = 1
	checks.append(["No Resolve left: attempt_spend_resolve_remove_condition() is a no-op", not c7.attempt_spend_resolve_remove_condition("Prone")])

	var c8 := Character.new()
	c8.resolve = 1
	checks.append(["Condition not actually held: attempt_spend_resolve_remove_condition() is a no-op", not c8.attempt_spend_resolve_remove_condition("Prone")])

	## --- Group B: live FieldEncounterScreen integration ----------------
	## Group A above deliberately toggled this global flag for its own
	## isolated Character-logic checks, unrelated to the real
	## FieldEncounterScreen `fe` — which has been alive (and its own
	## _ready() already ran, genuinely setting this true) since before
	## this function was even called. Restored here so Group B's checks
	## reflect the real screen's own state rather than Group A's leftover
	## manipulation of the same global.
	GameState.in_field_encounter = true
	## In a full batch run, GameState.player_character/party are whatever
	## an EARLIER test in the same process left them as (this is a true
	## autoload singleton, not reset between tests by rc_batch_runner.gd
	## itself) — a leftover party member with unusual equipment/
	## encumbrance from a different test could easily zero out
	## get_movement(), silently breaking the movement_remaining > 0 gate
	## Stand Up depends on. Same defensive reset other tests already use
	## (e.g. CharacterStatsGridTest) so this test's own result doesn't
	## depend on run order.
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_habitat = ""
	fe._start_encounter()
	for i in range(3):
		await fe.get_tree().process_frame

	var player: Character = fe.player
	checks.append(["setup: GameState.in_field_encounter is true for the screen's lifetime", GameState.in_field_encounter])

	## Settle any monster-first-turn/Fortune-prompt race, same convention
	## as CordeliaApothecaryTest's own live-combat section.
	var settle_frames := 0
	while not fe.awaiting_player_target and settle_frames < 300:
		if fe.awaiting_continue:
			fe.awaiting_continue = false
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		await fe.get_tree().process_frame
		settle_frames += 1
	fe.encounter.current_turn_index = fe.encounter.turn_order.find(player)

	player.wounds_current = player.wounds_max
	player.conditions["Prone"] = 1
	player.resolve = 1
	fe.action_used_this_turn = false
	fe._prompt_player_turn(true)
	await fe.get_tree().process_frame

	var stand_btn := ProneRecoveryTest._find_button(fe.target_container, "Stand Up")
	checks.append(["Stand Up is offered from Movement / Free Actions while genuinely Prone with Move and Wounds available", stand_btn != null])
	var resolve_btn := ProneRecoveryTest._find_button(fe.target_container, "Spend Resolve")
	checks.append(["Spend Resolve is also offered (Prone is a Condition it can remove)", resolve_btn != null])

	## Never in Attack / Defence: that whole column only renders once
	## _exploration_mode is false (it already is here, a real combat),
	## so this checks the actual header each button's ancestor column
	## carries, not just "some column somewhere."
	var movement_col := ProneRecoveryTest._find_column_by_header(fe.target_container, "Movement / Free Actions")
	var defence_col := ProneRecoveryTest._find_column_by_header(fe.target_container, "Attack / Defence")
	var stand_in_movement := movement_col != null and ProneRecoveryTest._find_button(movement_col, "Stand Up") != null
	var stand_in_defence := defence_col != null and ProneRecoveryTest._find_button(defence_col, "Stand Up") != null
	checks.append(["Stand Up's own column is genuinely 'Movement / Free Actions'", stand_in_movement])
	checks.append(["...and NEVER 'Attack / Defence' (the whole reason it moved)", not stand_in_defence])

	var movement_before: int = fe.movement_remaining
	if stand_btn != null:
		stand_btn.pressed.emit()
		await fe.get_tree().process_frame
	checks.append(["Clicking Stand Up actually clears Prone", not player.conditions.has("Prone")])
	checks.append(["...and spends the Move (movement_remaining drops to 0)", movement_before > 0 and fe.movement_remaining == 0])

	## In-combat healing must NOT auto-clear Prone on its own — mirrors
	## Group A's c2 check, but through the real, live screen this time.
	player.conditions["Prone"] = 1
	player.wounds_current = 0
	player.wounds_current = player.wounds_max
	checks.append(["Through the real live screen: healing mid-combat does NOT silently auto-clear Prone", player.conditions.has("Prone")])

	## Stand Up withheld once Move is exhausted; Spend Resolve withheld
	## once Resolve is exhausted.
	fe.action_used_this_turn = false
	fe.movement_remaining = 0
	fe._prompt_player_turn(false)
	await fe.get_tree().process_frame
	var stand_btn_no_move := ProneRecoveryTest._find_button(fe.target_container, "Stand Up")
	checks.append(["Stand Up is withheld once Move is exhausted, even while still Prone", stand_btn_no_move == null])

	player.resolve = 0
	fe.movement_remaining = 4
	fe._prompt_player_turn(false)
	await fe.get_tree().process_frame
	var resolve_btn_no_resolve := ProneRecoveryTest._find_button(fe.target_container, "Spend Resolve")
	checks.append(["Spend Resolve is withheld at 0 Resolve", resolve_btn_no_resolve == null])

	## Battle-end sweep: leave a party member genuinely Prone but already
	## healed above 0 Wounds, then tear the screen down exactly the way a
	## real battle end does, and confirm the sweep in _exit_tree() catches
	## them even though nothing else ever reassigned their Wounds again.
	player.conditions["Prone"] = 1
	player.wounds_current = player.wounds_max   ## already positive; no reassignment happens after this
	checks.append(["setup: party member is genuinely Prone with 1+ Wounds heading into teardown", player.conditions.has("Prone") and player.wounds_current > 0])
	fe._exit_tree()
	checks.append(["_exit_tree()'s own sweep clears Prone from anyone left Prone with 1+ Wounds", not player.conditions.has("Prone")])
	checks.append(["...and GameState.in_field_encounter is false again once the screen tears down", not GameState.in_field_encounter])

	var all_pass := true
	for c in checks:
		var label: String = c[0]
		var passed: bool = c[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Prone Recovery): ", "ALL PASS" if all_pass else "SOME FAILED", " (", checks.size(), " checks)")
	return all_pass

static func _find_button(root: Node, substr: String) -> Button:
	if root == null:
		return null
	var last: Button = null
	for child in root.get_children():
		if child is Button and String(child.text).contains(substr):
			last = child
		var found := ProneRecoveryTest._find_button(child, substr)
		if found != null:
			last = found
	return last

## Finds the action-column VBox (see _make_action_column) whose header
## Label reads exactly `header_text`, and returns that whole wrapper
## VBoxContainer (not just its original HFlowContainer — later rows like
## the Prone-recovery row are added as additional sibling
## HFlowContainers under the same wrapper, see the "Prone recovery" row
## build comment) so _find_button can be scoped to everything in that
## one column instead of the whole target_container.
static func _find_column_by_header(root: Node, header_text: String) -> Node:
	if root == null:
		return null
	for child in root.get_children():
		if child is Label and String(child.text) == header_text:
			return child.get_parent()
		var found := ProneRecoveryTest._find_column_by_header(child, header_text)
		if found != null:
			return found
	return null
