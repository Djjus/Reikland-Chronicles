extends RefCounted
class_name StaleMenuMonsterTurnTest
## Repro/regression test for the user report (with screenshots): "another
## case of player controlling the monster during their turn" — an ally's
## full action menu (Cancel Move, weapon switches, an actual weapon's
## Attack button, Disengage, ...) was still fully visible on screen
## during a MONSTER's own Turn right after that ally's Turn ended,
## because _next_turn() only ever reset the functional guard flags
## (awaiting_player_target, move_mode_active) and never actually cleared
## target_container/side_actions_container — _do_monster_turn() itself
## never touches either container, so whatever menu the last ally's Turn
## built just sat there, fully visible (if functionally inert), for the
## whole of the monster's Turn. Fixed by unconditionally clearing both
## containers in _next_turn(), right alongside the existing awaiting_
## player_target/move_mode_active reset — covers every Turn transition
## (both directions) since _do_monster_turn() and _prompt_player_turn()
## are only ever reached through _next_turn().
##
## Drives a real ally Turn's menu build, then a real transition to a
## monster's Turn, via a real FieldEncounter instance — same style as
## the rest of this suite.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	await tree.process_frame
	await tree.process_frame

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "StaleMenuTester"
	var no_pool: Array[String] = []
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	GameState.pending_encounter_monster_names = ["Giant Rat"]

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(5):
		await tree.process_frame

	var quiet_slices := 0
	var waited := 0.0
	while quiet_slices < 8 and waited < 20.0:
		if fe.awaiting_continue:
			fe.awaiting_continue = false
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		var quiet: bool = not fe.awaiting_continue and not fe.awaiting_fortune_choice
		if quiet:
			quiet_slices += 1
		else:
			quiet_slices = 0
		await tree.create_timer(0.25).timeout
		waited += 0.25
	await tree.create_timer(1.0).timeout

	var monster: Character = fe.monsters[0] if fe.monsters.size() > 0 else null
	checks.append(["setup: a real monster exists", monster != null])
	if monster == null or fe.battle_grid == null:
		fe.queue_free()
		for i in range(3): await tree.process_frame
		print("RESULT (Stale Menu Monster Turn): SETUP FAILED")
		return false

	## Force the player's own ally Turn to render its real, full menu —
	## exactly what _prompt_player_turn() does at the start of any
	## ally's Turn.
	fe.player = pc
	fe.encounter.current_turn_index = fe.encounter.turn_order.find(pc)
	fe._prompt_player_turn(true)
	await tree.process_frame

	checks.append(["setup: the ally's own Turn genuinely built a real menu (target_container non-empty)", fe.target_container.get_child_count() > 0])
	## Leave the player mid-Move — the exact "uncommitted Move/Cancel
	## fiddling" state the bug report's own combat log showed (waypoint
	## set, move cancelled, move re-entered) — to prove the fix clears
	## this leftover state too, not just an ordinary closed menu.
	if fe.battle_positions.has(pc):
		fe._enter_move_mode()
		await tree.process_frame
	var move_mode_was_active: bool = fe.move_mode_active
	checks.append(["setup: the ally genuinely left Move mode active/uncommitted (the report's own scenario)", move_mode_was_active])

	## Now force the Turn to hand off to the monster — the real
	## production transition (_next_turn() -> _do_monster_turn()), with
	## the monster patched to no-op instead of running its own full AI
	## routine (irrelevant to what's under test: whether the OUTGOING
	## ally's stale UI survives the handoff).
	fe.encounter.current_turn_index = fe.encounter.turn_order.find(pc)
	var real_do_monster_turn: Callable = Callable(fe, "_do_monster_turn")
	## GDScript can't easily monkey-patch a method on a live instance,
	## so instead: advance the turn index directly to point at the
	## monster (mirroring what encounter.advance_turn() would produce),
	## then call _next_turn()'s own real body by re-entering through
	## the same public entry point every other Turn-ending action uses.
	## _do_monster_turn() will run for real here — harmless: Giant Rat's
	## own AI Turn just moves/attacks and then calls _next_turn() again
	## on its own, which is fine, the assertion below only cares about
	## the FIRST moment (right as the handoff happens) which _next_turn()
	## itself updates synchronously before any awaited AI logic runs.
	fe._next_turn()
	## _next_turn() -> _do_monster_turn() is NOT awaited by our call
	## above (fire-and-forget signal-style, matching every other call
	## site in this file), but the container-clearing fix under test
	## runs synchronously at the very top of _next_turn(), before any
	## monster AI await — a single process_frame is enough to observe it
	## without needing the whole monster Turn to finish.
	await tree.process_frame

	checks.append(["THE BUG: target_container is genuinely cleared once the Turn hands off to a monster (used to leave the ally's menu fully visible)", fe.target_container.get_child_count() == 0])
	checks.append(["THE BUG: side_actions_container is genuinely cleared too (Act Again/Effort/Advantage Actions)", fe.side_actions_container.get_child_count() == 0])
	checks.append(["awaiting_player_target is false during the monster's own Turn", not fe.awaiting_player_target])
	checks.append(["move_mode_active no longer left dangling from the outgoing ally's uncommitted Move", not fe.move_mode_active])

	## Let whatever's left of the monster's real (now-running) Turn
	## settle out before tearing down, same quiet-slice convention as
	## every other test in this suite, so this doesn't leave a dangling
	## coroutine complaint on exit.
	var settle2 := 0
	var waited2 := 0.0
	while settle2 < 6 and waited2 < 10.0:
		if fe.awaiting_continue:
			fe.awaiting_continue = false
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		if fe.pending_defense.is_empty() and not fe.awaiting_continue and not fe.awaiting_fortune_choice:
			settle2 += 1
		else:
			settle2 = 0
		await tree.create_timer(0.2).timeout
		waited2 += 0.2

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
	print("RESULT (Stale Menu Monster Turn): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
