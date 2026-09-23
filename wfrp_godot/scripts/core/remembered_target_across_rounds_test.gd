extends RefCounted
class_name RememberedTargetAcrossRoundsTest
## REVERSED per the follow-up request ("clear the selected target (stop
## trying to remember the last one) after the turn").
##
## This file used to verify the opposite behavior: "remember each player
## character's target in the previous round and reset it if that target
## is still alive/undefeated in the next round" (shipped in v0.2.293 as
## `ally_focus_target`, restored at the top of `_prompt_player_turn`).
## The new request explicitly reverses that — a character's target
## selection no longer survives past their own turn at all. Rather than
## delete this regression test outright (and lose the coverage of the
## turn-transition machinery itself), it's rewritten to confirm the new
## behavior: `selected_target` and each character's own `ally_focus_target`
## entry are both wiped the instant a turn ends (see _next_turn()'s own
## turn-transition reset), so a fresh turn never inherits a previous
## pick — every character starts each of their own turns with whatever
## _ensure_valid_target()'s plain "first living enemy" default lands on,
## regardless of what they (or anyone else) targeted last round.
##
## Drives a real FieldEncounter (2 allies, 2 monsters) turn-by-turn via
## CombatEncounter.advance_turn() directly rather than the screen's own
## _next_turn()/_do_monster_turn() — this test only cares about
## FieldEncounterScreen's own target-memory reset logic at turn
## boundaries, not monster AI or attack resolution, so every adversary
## turn is simply skipped (never acted on) to stay fully deterministic
## and avoid unrelated combat RNG entirely.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var alpha: Character = GameState.player_character   ## party index 0
	alpha.character_name = "Alpha"
	alpha.equipped_weapon = "Sword"

	var human = GameData.find_race("Human")
	var soldier = GameData.find_career("Soldier")
	var bravo: Character = CharacterCreator.create_character("Bravo", human, soldier, {})
	bravo.equipped_weapon = "Sword"
	GameState.add_party_member(bravo)   ## party index 1

	## Two distinctly-tracked monsters, so a target pick can be checked
	## unambiguously against "the one I picked" vs "whatever the default
	## fallback landed on instead."
	var names: Array[String] = ["Giant Rat", "Giant Rat"]
	GameState.pending_encounter_monster_names = names

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(5):
		await tree.process_frame

	checks.append(["setup: both allies present in the encounter", fe.encounter.get_living("ally").size() == 2])
	checks.append(["setup: both monsters present in the encounter", fe.encounter.get_living("adversary").size() == 2])
	if fe.encounter.get_living("ally").size() != 2 or fe.encounter.get_living("adversary").size() != 2:
		fe.queue_free()
		for i in range(3): await tree.process_frame
		print("RESULT (Remembered Target Across Rounds): SETUP FAILED")
		return false

	var rat_1: Character = fe.monsters[0]
	var rat_2: Character = fe.monsters[1]

	## Drives combatants forward, one Turn at a time, until it's the given
	## ally's own fresh Turn again -- via encounter.advance_turn() directly
	## (not the screen's own _next_turn()), skipping every adversary Turn
	## outright with no AI/attack resolution at all (see the file comment
	## above), exactly like the original version of this test. Calling
	## fe._clear_target_memory_for_ending_turn() immediately before each
	## advance exercises the REAL production reset this test is actually
	## checking -- the exact same call _next_turn() itself makes -- without
	## ever routing through _next_turn()'s own Turn-dispatch, which would
	## fire a real, unawaited _do_monster_turn() coroutine any time the
	## Turn being skipped past belongs to a monster (introducing the exact
	## kind of uncontrolled real-time race this project's watchdog test
	## already hit once — see monster_turn_stall_watchdog_test.gd's own
	## file comment for the full story).
	var advance_to := func(ally: Character) -> void:
		var safety := 0
		while safety < 40:
			safety += 1
			fe._clear_target_memory_for_ending_turn()
			var current: Character = fe.encounter.advance_turn()
			if current == ally:
				fe.player = current
				fe._prompt_player_turn()
				return

	## --- Round 1: each ally picks their own distinct target ----------
	advance_to.call(alpha)
	checks.append(["Round 1: it's genuinely Alpha's own fresh turn", fe.player == alpha])
	fe._select_target(rat_1)
	checks.append(["Round 1: Alpha's pick landed", fe.selected_target == rat_1])
	checks.append(["Round 1: Alpha's pick is tracked in ally_focus_target while his own turn is still open", fe.ally_focus_target.get(alpha) == rat_1])

	advance_to.call(bravo)
	checks.append(["Round 1: it's genuinely Bravo's own fresh turn", fe.player == bravo])
	## Reversal's own core assertion: Alpha's own remembered-target entry
	## must be gone the instant his turn ended, not just "still there but
	## unused" — checked directly against ally_focus_target rather than
	## inferred from selected_target's own value, since _ensure_valid_
	## target()'s "first living enemy" default could otherwise coincide
	## with Alpha's actual pick (rat_1 is monsters[0]) and make a
	## selected_target-based check pass for the wrong reason.
	checks.append(["Round 1: Alpha's own remembered-target entry was erased once his turn ended", not fe.ally_focus_target.has(alpha)])
	fe._select_target(rat_2)
	checks.append(["Round 1: Bravo's pick landed", fe.selected_target == rat_2])

	## --- Round 2: neither ally's Round 1 pick should survive into their
	## own next turn -- the whole point of the reversal.
	advance_to.call(alpha)
	checks.append(["Round 2: Alpha's fresh turn starts with no remembered target of his own", not fe.ally_focus_target.has(alpha)])
	checks.append(["Round 2: Bravo's own Round 1 pick was also erased once HIS turn ended, not just Alpha's", not fe.ally_focus_target.has(bravo)])
	checks.append(["Round 2: Alpha's selection instead falls back to the default living target", fe.selected_target == rat_1 or fe.selected_target == rat_2])

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
	print("RESULT (Remembered Target Across Rounds): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
