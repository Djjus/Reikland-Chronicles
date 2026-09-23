extends RefCounted
class_name MonsterTurnChargeArrowLeakTest
## Regression test for the reported bug ("the player controlling monster
## bug again, the giant bat moved to attack eric, but before he did we
## got the move arrow from the monster as seen. Could this be related to
## player mouse clicks on the battle map during the monsters turn?").
##
## This project has fixed this exact bug SHAPE three times before
## (v0.2.460, v0.2.491, v0.2.526) — always some piece of per-ally
## battle-map UI/overlay state that isn't cleared when the Turn transitions
## from an ally to a monster, so it visually (or, in the earlier cases,
## functionally) survives into the monster's own Turn. _next_turn() is the
## single choke point every Turn transition funnels through, and by now
## resets move_mode_active, awaiting_player_target, and both action-menu
## containers unconditionally there — but the newer Charge-ready arrow
## feature (charge_ready_arrow_test.gd's own subject: a static red arrow
## from the active character's own square to their selected target,
## shown whenever they're in charge range) was added AFTER those three
## fixes and was never added to this same reset checklist.
##
## ROOT CAUSE (confirmed by reading BattleGridView._draw()):
## grid_view.set_charge_ready() is ONLY ever called from
## _render_turn_action_menu(), which only ever runs for an ally's own
## Turn. The arrow itself is drawn FROM
## positions[current_turn_character] — which DOES correctly update to
## whoever's Turn it really is (see set_state(), called every
## _render_status()) — TO whatever charge_ready_target was last set to.
## So once an ally's Turn ends leaving a Charge-ready arrow on screen,
## the very next monster Turn draws that same stale arrow starting from
## the monster's own (correctly tracked) square instead — reading
## exactly like "the player is still controlling the monster's Move",
## even though nothing about move_mode_active or the action menu
## (already covered by the earlier three fixes) is actually involved
## this time.
##
## THE FIX: _next_turn() now also unconditionally clears
## grid_view.charge_ready_target back to Vector2i(-1, -1), the same
## choke point and the same unconditional treatment already given to
## move_mode_active/target_container/side_actions_container.

static func run_test(fe) -> bool:
	var checks: Array = []

	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_habitat = ""
	fe._start_encounter()
	for i in range(3):
		await fe.get_tree().process_frame

	var player: Character = fe.player
	var goblin: Character = fe.monsters[0] if fe.monsters.size() > 0 else null
	checks.append(["setup: a monster genuinely exists", goblin != null])
	if goblin == null:
		print("RESULT (Monster Turn Charge Arrow Leak): SETUP FAILED (no monster)")
		return false

	player.equipped_weapon = "Sword"
	fe.weapons[player] = fe._resolve_weapon(player)
	fe.battle_grid = BattleGrid.new()
	fe.battle_grid.generate_from_terrain_snapshot([])   ## fully open grid
	fe.action_used_this_turn = false
	fe.awaiting_player_target = true
	fe.pending_defense.clear()

	## Deterministically force the NEXT Turn to land on a monster --
	## encounter.turn_order's own real initiative roll otherwise makes
	## this flaky (e.g. a second ally with their own genuinely-in-range
	## target could legitimately come next and redraw a fresh, correct
	## arrow, which isn't the bug this test is guarding). current_turn_
	## index is set to one-before whichever slot the first monster
	## actually landed in, so encounter.advance_turn()'s own `+= 1`
	## (called from inside _next_turn() itself) lands exactly on it --
	## the exact same mechanism a real Turn transition already uses, not
	## a bypass of it.
	var monster_index: int = fe.encounter.turn_order.find(goblin)
	checks.append(["setup: the monster is genuinely seated in turn_order", monster_index != -1])
	fe.encounter.current_turn_index = monster_index - 1 if monster_index > 0 else fe.encounter.turn_order.size() - 1

	## Same "exactly at the charge_min floor" setup charge_ready_arrow_
	## test.gd's own Case 3 uses to reliably get a real Charge-ready
	## arrow showing -- this is the ally's (fe.player's) own Turn, ending
	## with a live arrow left on screen exactly like a real player who
	## never Charged or ended their Turn differently would leave it.
	var charge_min: int = player.get_movement()
	var origin := Vector2i(5, 5)
	fe.battle_positions.clear()
	fe.battle_positions[player] = origin
	fe.battle_positions[goblin] = origin + Vector2i(charge_min + 1, 0)
	fe.selected_target = goblin
	fe._prompt_player_turn(true)
	await fe.get_tree().process_frame
	checks.append(["setup: the ally's own Turn genuinely leaves a live Charge-ready arrow on screen (matches charge_ready_arrow_test.gd's own Case 3)", fe.grid_view.charge_ready_target != Vector2i(-1, -1)])

	## Now advance the Turn -- current_turn_index was set above so this
	## lands exactly on the monster. _next_turn() runs its own reset
	## synchronously before it ever reaches the ally-vs-monster dispatch
	## decision (_prompt_player_turn() vs _do_monster_turn(), the latter
	## fired without awaiting it, same background-coroutine convention
	## this project's monster-turn code always uses) -- so the reset is
	## already in effect the instant this call returns, with no further
	## await needed to observe it, and _do_monster_turn() itself never
	## touches charge_ready_target at all (confirmed by reading it), so
	## nothing downstream can legitimately set it back to something real
	## the way a second ally's own fresh turn could.
	fe.skip_next_turn_call_once = false
	fe._next_turn()
	checks.append(["THE FIX: the stale Charge-ready arrow is cleared the instant the Turn moves to the monster", fe.grid_view.charge_ready_target == Vector2i(-1, -1)])
	checks.append(["setup sanity: the Turn that just started really is the monster's, not some other ally's", fe.encounter.get_current_combatant() == goblin])

	## Let any background monster-turn coroutine _next_turn() may have
	## just fired settle out before this test ends, same defensive
	## drain every other fe-mode test in this project already does.
	for i in range(90):
		if fe.awaiting_continue:
			fe.awaiting_continue = false
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		if fe.awaiting_fatal_moment_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fatal_moment_choice = false
		if not fe.pending_defense.is_empty():
			break
		await fe.get_tree().process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Monster Turn Charge Arrow Leak): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
