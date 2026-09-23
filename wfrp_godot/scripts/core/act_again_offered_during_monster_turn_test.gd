extends RefCounted
class_name ActAgainOfferedDuringMonsterTurnTest
## Repro/regression test for the recurrence of the "player controlling
## monster" report (screenshots showed an "Act Again (4 Adv)" button still
## live on screen during a monster's own Turn, Round 2, Wolf 2 acting).
##
## Root cause: _wait_for_continue() (and its own
## _wait_for_continue_after_own_action() wrapper) decide whether to offer
## "Act Again" purely from `player.allegiance == "ally"` plus the Ally
## Advantage pool/additional_action_used_this_turn — never checking
## whether it's actually THAT character's own Turn right now. But `player`
## is a shared variable reassigned constantly outside an ally's own Turn
## too — e.g. _monster_attack() sets `player = attack_target` when a
## monster's melee attack targets an ally, and _resolve_monster_free_attack
## sets `player = ally` — and _wait_for_continue() is itself called from
## plenty of monster-turn code (a monster's ranged attack card, a
## monster's free attack, ...). So whenever an ally had 4+ unspent
## Advantage and hadn't used Act Again yet this Round, ANY _wait_for_
## continue() call during a MONSTER's Turn could offer that ally "Act
## Again" — and clicking it opened a full, live, interactive action menu
## for the ally while the monster's own Turn coroutine was still paused
## mid-await on the call stack. That's the reported bug, verbatim.
##
## Fixed by additionally requiring encounter.get_current_combatant() ==
## player — the one signal that's set once per _next_turn() call and
## untouched by any of `player`'s own mid-turn reassignments.
##
## Drives a real FieldEncounter instance, forces the turn index to a
## monster while `player` still points at an ally sitting on 4+ unspent
## Advantage (exactly the state _monster_attack's own `player =
## attack_target` reassignment produces mid-monster-turn), calls the real
## _wait_for_continue() directly, and asserts "Act Again" is never among
## the rendered options while it's the monster's Turn.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	await tree.process_frame
	await tree.process_frame

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "ActAgainTester"
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
	if monster == null:
		fe.queue_free()
		for i in range(3): await tree.process_frame
		print("RESULT (Act Again Offered During Monster Turn): SETUP FAILED")
		return false

	## Exactly the state mid-monster-turn code produces: it's the
	## monster's Turn (current_turn_index points at it), but `player`
	## still points at the ally the monster just targeted/attacked, sitting
	## on plenty of unspent Ally Advantage and having not used Act Again
	## yet this Round.
	fe.encounter.current_turn_index = fe.encounter.turn_order.find(monster)
	fe.player = pc
	fe.encounter.advantage_pool.ally = 4
	fe.additional_action_used_this_turn = false
	checks.append(["setup: current combatant is genuinely the monster, not the ally", fe.encounter.get_current_combatant() == monster])
	checks.append(["setup: `player` still points at the ally (the exact mid-monster-turn reassignment)", fe.player == pc])

	fe._add_notice("[Test] simulated monster attack card.")
	fe._render_status()
	## Fire-and-forget, same convention the rest of this suite uses for
	## calling a real async screen function from a test without needing
	## its own completion right away (see stale_menu_monster_turn_test.gd's
	## own fe._next_turn() call) — _wait_for_continue() suspends on its own
	## `while awaiting_continue: await get_tree().process_frame` loop, so a
	## couple of frames is enough for it to have rendered its options and
	## be sitting there waiting.
	fe._wait_for_continue()
	await tree.process_frame
	await tree.process_frame

	var offered_act_again := false
	for opt in fe._pending_fortune_options:
		if String(opt.get("text", "")).findn("Act Again") != -1:
			offered_act_again = true
	checks.append(["THE BUG: Act Again is NOT offered while it's genuinely the monster's Turn", not offered_act_again])
	checks.append(["setup: _wait_for_continue() is genuinely still pending (proves it actually ran)", fe.awaiting_continue])

	## Let the still-pending _wait_for_continue() finish so it doesn't
	## leave a dangling coroutine complaint on exit.
	fe.awaiting_continue = false
	await tree.process_frame

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
	print("RESULT (Act Again Offered During Monster Turn): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
