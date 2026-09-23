extends RefCounted
class_name ActionBlockedOffTurnTest
## Regression test for the 5th reported occurrence of the "player
## controlling monster" bug class (with screenshots): "first turn of
## combat, it should be the monster's turn, but player has control. We
## need to stop this from happening for good."
##
## This project had already fixed this exact bug SHAPE four times before
## (see _next_turn()'s and _render_turn_action_menu()'s own comments,
## plus stale_menu_monster_turn_test.gd/sprint_stuck_menu_test.gd/
## monster_turn_charge_arrow_leak_test.gd for the first three) — each time
## by clearing one more specific piece of leftover UI at _next_turn(), the
## single choke point every NORMAL Turn transition funnels through. But
## any path that leaves a live Move/Attack/Sprint/End-Turn control on
## screen WITHOUT going through that choke point (a future feature, an
## ambush spawning a monster mid-round via add_combatant_mid_round()
## while the previously-acting ally's own menu is still legitimately up,
## or simply a fix site this project hasn't found yet) can leak the exact
## same way all over again — chasing each new leak site individually
## clearly isn't "stopping this for good."
##
## THE FIX (this time, root-cause hardening rather than another leak
## patch): a single authoritative guard, _is_players_own_turn(), checked
## by the action-EXECUTING handlers themselves (_enter_move_mode,
## _on_sprint, _on_end_turn_pressed, _on_player_attack, _on_cast_spell,
## _on_pray) — not just by whatever last rendered them. A stale button
## surviving on screen (for any reason, including ones not yet found)
## becomes structurally harmless to click: pressing it can never again
## move/attack/act for a character who isn't genuinely the encounter's
## own current combatant.
##
## This test deliberately does NOT go through _next_turn() at all — it
## directly desyncs `player`/the action menu from encounter.
## current_turn_index (mimicking "however a future leak might happen",
## not one specific known path), then proves the actual action handlers
## refuse to fire anyway.

static func run_test(fe) -> bool:
	var checks: Array = []

	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_habitat = ""
	fe._start_encounter()
	for i in range(3):
		await fe.get_tree().process_frame

	var pc: Character = fe.player
	var monster: Character = fe.monsters[0] if fe.monsters.size() > 0 else null
	checks.append(["setup: a real monster exists", monster != null])
	if monster == null or pc == null:
		print("RESULT (Action Blocked Off-Turn): SETUP FAILED")
		return false

	## Build a genuine, fully-live ally action menu for the player — same
	## as _prompt_player_turn() would at the start of their own Turn.
	fe.encounter.current_turn_index = fe.encounter.turn_order.find(pc)
	fe.player = pc
	fe._prompt_player_turn(true)
	await fe.get_tree().process_frame
	checks.append(["setup: a real, live action menu was built for the player", fe.target_container.get_child_count() > 0])
	checks.append(["setup: awaiting_player_target is true (menu is genuinely interactive)", fe.awaiting_player_target])

	## Desync WITHOUT ever calling _next_turn(): the encounter's own
	## authoritative turn pointer now says it's the monster's Turn, but
	## every UI flag/container is still exactly as a live ally Turn left
	## it — deliberately not modeling any one specific leak path, since
	## the whole point of this fix is that it shouldn't matter how the
	## desync happens.
	fe.encounter.current_turn_index = fe.encounter.turn_order.find(monster)
	checks.append(["setup: encounter's own current combatant is genuinely the monster now", fe.encounter.get_current_combatant() == monster])
	checks.append(["setup: `player` is still the desynced ally (the actual bug condition)", fe.player == pc])

	var movement_before: int = fe.movement_remaining
	var action_used_before: bool = fe.action_used_this_turn

	## THE ACTUAL CLICKS the user's screenshots showed: Move, then a
	## defended attempt at an Attack.
	fe._on_move_button_pressed()
	checks.append(["THE FIX: clicking Move did NOT enter move mode for the desynced player", not fe.move_mode_active])
	checks.append(["THE FIX: no movement was actually spent", fe.movement_remaining == movement_before])

	fe.selected_target = monster
	fe._on_player_attack(monster)
	checks.append(["THE FIX: clicking Attack did NOT spend the desynced player's Action", fe.action_used_this_turn == action_used_before])

	fe._on_end_turn_pressed()
	checks.append(["THE FIX: End Turn did not advance the encounter's own turn pointer out from under the real current combatant", fe.encounter.get_current_combatant() == monster])

	## Sanity check the fix isn't a blanket lockout: once `player` and the
	## encounter genuinely agree again (a real ally Turn), the exact same
	## handler must still work normally.
	fe.encounter.current_turn_index = fe.encounter.turn_order.find(pc)
	fe._prompt_player_turn(true)
	await fe.get_tree().process_frame
	fe._on_move_button_pressed()
	checks.append(["sanity: Move still works normally on the player's genuine own Turn", fe.move_mode_active])
	if fe.move_mode_active:
		fe._exit_move_mode()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Action Blocked Off-Turn): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
