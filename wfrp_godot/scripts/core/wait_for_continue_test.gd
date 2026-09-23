extends RefCounted
class_name WaitForContinueTest

static func run_test(fe) -> bool:
	var checks: Array = []

	var human = GameData.find_race("Human")
	var soldier = GameData.find_career("Soldier")
	fe.player = CharacterCreator.create_character("WFCTestPlayer", human, soldier, {})
	fe.player.wounds_current = fe.player.wounds_max

	var rat_def: MonsterDefinition = GameData.monster_db.find_by_name("Giant Rat")
	var rat := rat_def.to_character()
	rat.wounds_current = rat.wounds_max
	var monsters_arr: Array[Character] = [rat]
	fe.monsters = monsters_arr
	var combatants: Array[Character] = [fe.player, rat]
	fe.encounter.combatants = combatants
	## Real bug fix (in this test's own setup, not production code):
	## CombatEncounter.get_living() — which _wait_for_continue() itself
	## calls to decide whether to skip the prompt — reads `turn_order`,
	## not `combatants`. Leaving turn_order populated with whatever
	## _start_encounter() rolled for the real player/monster group (from
	## this same FieldEncounter instance's own _ready()) meant every
	## "side already empty" case below was silently checked against
	## stale, still-living real combatants instead of this test's own
	## synthetic player/rat — so the shortcut this test exists to prove
	## never actually triggered, and await fe._wait_for_continue() below
	## hung forever waiting for a Continue/Space press that never comes
	## in a headless run.
	fe.encounter.turn_order = combatants
	fe.battle_over = false

	## Case 1 (the actual fix): adversary side already empty -> _wait_for_continue()
	## genuinely returns immediately, no Space needed, awaiting_continue never set.
	rat.wounds_current = 0
	fe.awaiting_continue = false
	var t0 := Time.get_ticks_msec()
	await fe._wait_for_continue()
	var elapsed_ms := Time.get_ticks_msec() - t0
	checks.append(["once the adversary side is empty, _wait_for_continue() genuinely returns almost instantly (<50ms), no Space needed", elapsed_ms < 50])
	checks.append(["...and never actually set awaiting_continue true along the way", not fe.awaiting_continue])

	## Case 2: ally side empty (defeat) -> also genuinely skips
	rat.wounds_current = rat.wounds_max
	fe.player.wounds_current = 0
	fe.awaiting_continue = false
	var t1 := Time.get_ticks_msec()
	await fe._wait_for_continue()
	var elapsed_ms2 := Time.get_ticks_msec() - t1
	checks.append(["with the ally side empty (defeat), _wait_for_continue() also genuinely returns almost instantly", elapsed_ms2 < 50])

	## Case 3: battle_over already true -> always skips regardless of living sides
	fe.player.wounds_current = fe.player.wounds_max
	rat.wounds_current = rat.wounds_max
	fe.battle_over = true
	fe.awaiting_continue = false
	var t2 := Time.get_ticks_msec()
	await fe._wait_for_continue()
	var elapsed_ms3 := Time.get_ticks_msec() - t2
	checks.append(["once battle_over is true, _wait_for_continue() genuinely always returns almost instantly regardless of living sides", elapsed_ms3 < 50])

	## Case 4, the full realistic chain: kill lands -> wait_for_continue -> next_turn
	## reaches battle_over with zero extra Space presses required.
	fe.battle_over = false
	fe.player.wounds_current = fe.player.wounds_max
	rat.wounds_current = 0
	await fe._wait_for_continue()
	fe._next_turn()
	for i in range(3): await fe.get_tree().process_frame
	checks.append(["the full realistic chain (kill -> wait_for_continue -> next_turn) genuinely reaches battle_over with zero extra Space presses", fe.battle_over])
	## Per the follow-up request ("instead of auto picking up loot, i
	## want a new pop up window with the battle report"): the old Return
	## button is never surfaced any more — _end_battle() now shows the
	## Battle Report overlay instead (see _show_battle_report()), whose
	## own Close button does what Return used to.
	checks.append(["...and the Battle Report overlay is genuinely visible at the end of that same chain", fe.battle_report_overlay.visible])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Wait For Continue Skip Fix): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
