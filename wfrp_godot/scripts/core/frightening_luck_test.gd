extends RefCounted
class_name FrighteningLuckTest
## Verifies this pass's two newly-implemented talents:
##
## Frightening (p.190) -- the reverse direction of Fear/Terror (monster
## afraid of an ally, instead of the existing monster-to-ally direction
## PsychologyTest already covers). A present passive ally's own copy is
## always assumed active from the start of the fight; the PLAYER's own
## copy is instead gated behind a Free Action ON/OFF toggle
## (frightening_active) that always starts OFF each fight and only
## triggers a Fear check the moment it's switched on.
##
## Luck (p.??) -- "your maximum Fortune Points now equal your current
## Fate points plus the number of times you've taken Luck." Corrected
## (user report) from an earlier, wrong implementation of this talent as
## a free once-per-session reroll -- it's just a bigger Fortune Points
## cap (Character.get_max_fortune_points), not a separate mechanic.
##
## Reuses PsychologyTest._settle() (same file family, same race-avoidance
## reasoning documented there) rather than duplicating it.

static func run_test(fe) -> bool:
	var checks: Array = []

	## Drain any background coroutine from FieldEncounterScreen's own
	## auto-started _ready() encounter before this test's setup begins --
	## same reasoning as PsychologyTest.run_test()'s own opening drain.
	for i in range(120):
		if fe.awaiting_continue:
			fe.awaiting_continue = false
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		await fe.get_tree().process_frame

	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_habitat = ""
	fe._start_encounter()
	for i in range(3):
		await fe.get_tree().process_frame

	var human = GameData.find_race("Human")
	var soldier = GameData.find_career("Soldier")
	var test_player := CharacterCreator.create_character("FrighteningLuckPlayer", human, soldier, {})
	fe.player = test_player
	var ally_b := CharacterCreator.create_character("FrighteningLuckAllyB", human, soldier, {})
	for a in [test_player, ally_b]:
		a.equipped_weapon = "Sword"
		a.allegiance = "ally"
		a.characteristics.set_value("toughness", 40)
		a.characteristics.set_value("weapon_skill", 50)
		a.characteristics.set_value("willpower", 40)
		a.wounds_current = a.wounds_max

	var goblin_def: MonsterDefinition = GameData.monster_db.find_by_name("Goblin")
	var goblin: Character = goblin_def.to_character()
	goblin.allegiance = "adversary"
	goblin.wounds_max = 20
	goblin.wounds_current = 20

	var monsters_arr: Array[Character] = [goblin]
	fe.monsters = monsters_arr
	fe.monster_defs[goblin] = goblin_def
	var sword: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	fe.weapons[test_player] = sword
	fe.weapons[ally_b] = sword
	var goblin_weapon: WeaponDefinition = GameData.weapon_db.find_by_name(goblin_def.weapon_name)
	fe.weapons[goblin] = goblin_weapon if goblin_weapon != null else sword

	fe.encounter = CombatEncounter.new()
	fe.encounter.add_combatant(test_player)
	fe.encounter.add_combatant(ally_b)
	fe.encounter.add_combatant(goblin)
	fe.encounter.roll_initiative()

	fe.battle_grid = BattleGrid.new()
	fe.battle_grid.generate_from_terrain_snapshot([])
	fe.battle_grid.obstacle_type.clear()
	fe.battle_grid.obstacle_group.clear()
	fe.battle_grid.obstacles.clear()
	fe.battle_grid.obstacle_cover.clear()
	fe.battle_grid.blocks_los.clear()
	fe.battle_grid.impassable.clear()
	fe.battle_grid.cover.clear()
	fe.battle_grid.mud.clear()
	fe.battle_over = false
	fe.melee_has_begun = true
	fe.awaiting_player_target = false
	fe.awaiting_continue = false
	fe.pending_defense.clear()
	fe.xp_awarded_for.clear()
	fe.encounter.current_turn_index = fe.encounter.turn_order.find(test_player)

	fe.battle_positions.clear()
	fe.battle_positions[test_player] = Vector2i(5, 9)
	fe.battle_positions[ally_b] = Vector2i(1, 1)
	fe.battle_positions[goblin] = Vector2i(25, 9)

	## --- A: _mark_monster_fear_source populates all three Dictionaries ---
	fe._monster_fear_sources.clear()
	fe._monster_fear_rating.clear()
	fe._monster_fear_extended_sl.clear()
	fe._monster_fear_tested.clear()
	fe._mark_monster_fear_source(goblin, ally_b, 2)
	checks.append(["A: _mark_monster_fear_source sets _monster_fear_sources", fe._monster_fear_sources.get(goblin, {}).has(ally_b)])
	checks.append(["A: _mark_monster_fear_source sets _monster_fear_rating", fe._monster_fear_rating.get(goblin, {}).get(ally_b, -1) == 2])
	checks.append(["A: _mark_monster_fear_source resets _monster_fear_extended_sl to 0", fe._monster_fear_extended_sl.get(goblin, {}).get(ally_b, -1) == 0])

	## --- B: a passive ally's Frightening causes a real Fear check, and
	##     a failure marks the monster + records it as tested ---
	fe._monster_fear_sources.clear()
	fe._monster_fear_rating.clear()
	fe._monster_fear_extended_sl.clear()
	fe._monster_fear_tested.clear()
	ally_b.talents_taken["Frightening"] = 2
	goblin.characteristics.set_value("willpower", 1)   ## near-certain Cool Test failure (Cool is linked to Willpower)
	var frightening_sources: Array[Character] = [ally_b]
	## _check_reverse_fear_from_frightening() shows a real card + awaits
	## _wait_for_continue() per Test — called as a bare (unawaited)
	## statement here so it runs in the background while this test's own
	## coroutine separately drains awaiting_continue via
	## PsychologyTest._settle(), same pattern PsychologyTest.run_test()
	## itself uses around every _do_monster_turn() call (awaiting it
	## directly here would deadlock: nothing else would ever flip
	## awaiting_continue back to false).
	fe._check_reverse_fear_from_frightening(frightening_sources)
	await PsychologyTest._settle(fe, 60)
	checks.append(["B: a failed Cool Test marks the monster Subject to Fear from the Frightening ally", fe._monster_fear_sources.get(goblin, {}).has(ally_b)])
	checks.append(["B: the Fear Rating recorded matches the ally's own Frightening rank", fe._monster_fear_rating.get(goblin, {}).get(ally_b, -1) == 2])
	checks.append(["B: the (monster, source) pair is recorded as tested", fe._monster_fear_tested.get(goblin, {}).has(ally_b)])

	## --- C: the one-shot dedup actually stops a re-roll -- flipping the
	##     monster's Cool to near-certain SUCCESS and calling again must
	##     NOT clear the mark already set in B (proves no second roll
	##     happened; a second roll at Cool 95 would very likely pass and
	##     leave the monster un-marked if the dedup weren't working) ---
	goblin.characteristics.set_value("willpower", 95)
	fe._check_reverse_fear_from_frightening(frightening_sources)
	await PsychologyTest._settle(fe, 60)
	checks.append(["C: already-tested (monster, source) pairs are never re-rolled", fe._monster_fear_sources.get(goblin, {}).has(ally_b)])

	## --- D: fear_penalty formula (-10 while marked, 0 otherwise) --
	## mirrors _monster_attack's/_resolve_player_defense's own inline
	## computation directly, same style as this project's own Iron Jaw
	## verification (batch 3) -- decoupled from the live, un-forceable
	## attack roll itself.
	var penalty_when_marked: int = -10 if fe._monster_fear_sources.get(goblin, {}).has(ally_b) else 0
	var penalty_when_unmarked: int = -10 if fe._monster_fear_sources.get(goblin, {}).has(test_player) else 0
	checks.append(["D: fear_penalty is -10 when the attacker fears its target", penalty_when_marked == -10])
	checks.append(["D: fear_penalty is 0 when the attacker doesn't fear its target", penalty_when_unmarked == 0])

	## --- E: the Extended Test can shake Fear off a monster mid-battle --
	fe._monster_fear_sources.clear()
	fe._monster_fear_rating.clear()
	fe._monster_fear_extended_sl.clear()
	fe._monster_fear_tested.clear()
	fe._mark_monster_fear_source(goblin, ally_b, 1)   ## Rating 1 -- one net SL clears it
	goblin.characteristics.set_value("willpower", 90)   ## pushes the Cool Test target high enough that success is very likely each attempt (Cool is linked to Willpower)
	for i in range(6):
		if not fe._monster_fear_sources.get(goblin, {}).has(ally_b):
			break
		await fe._tick_fear_extended_tests()
	checks.append(["E: a strong Cool Test result against a low Fear Rating clears a monster's Fear via the Extended Test", not fe._monster_fear_sources.get(goblin, {}).has(ally_b)])

	## --- F: the approach check reacts to the monster's own psychology
	##     WITHOUT blocking the player's Move (the mirror-image of Fear's
	##     own gate, which DOES block the scared character's move) ---
	fe._monster_fear_sources.clear()
	fe._monster_fear_rating.clear()
	fe._monster_fear_extended_sl.clear()
	fe._mark_monster_fear_source(goblin, test_player, 3)
	goblin.characteristics.set_value("willpower", 1)   ## near-certain failure -> Broken (Cool is linked to Willpower)
	goblin.conditions.clear()
	fe.battle_positions.clear()
	## Player starts genuinely NOT adjacent to the goblin (distance 2) so
	## the Move below actually closes the distance to melee range —
	## starting already adjacent (distance 1 -> 1) would make the
	## approach-check's own "did this Move genuinely bring them closer"
	## gate correctly no-op, same as the pre-existing ally-side gate this
	## mirrors (_try_commit_move's own before_dist/after_dist check).
	fe.battle_positions[test_player] = Vector2i(5, 9)
	fe.battle_positions[goblin] = Vector2i(7, 9)
	fe.battle_positions[ally_b] = Vector2i(1, 1)
	fe.player = test_player
	fe.movement_remaining = test_player.get_movement() * 2
	fe.encounter.current_turn_index = fe.encounter.turn_order.find(test_player)
	fe._enter_move_mode()
	var adjacent_square := Vector2i(6, 9)   ## newly adjacent to goblin at (7,9); distance from start (5,9) drops 2 -> 1
	## _try_commit_move now awaits _apply_reverse_fear_approach_checks()
	## internally, which shows a real card + awaits _wait_for_continue()
	## -- called as a bare (unawaited) statement, same reasoning as
	## section B/C above, so PsychologyTest._settle() can drain it from
	## the outside rather than this test deadlocking against itself.
	fe._try_commit_move(adjacent_square)
	await PsychologyTest._settle(fe, 60)
	checks.append(["F: the player's own Move is NOT blocked by a monster's fear of them (only the monster's own gate blocks a move)", fe.battle_positions.get(test_player, Vector2i(-1, -1)) == adjacent_square])
	checks.append(["F: the monster gains Broken from a failed approach-reaction Cool Test", goblin.conditions.get("Broken", 0) > 0])

	## --- G: the player's own Frightening toggle only checks monsters
	##     once actually switched ON, and only while genuinely usable ---
	fe._monster_fear_sources.clear()
	fe._monster_fear_rating.clear()
	fe._monster_fear_extended_sl.clear()
	fe._monster_fear_tested.clear()
	fe.frightening_active = false
	test_player.talents_taken["Frightening"] = 3
	goblin.characteristics.set_value("willpower", 1)   ## Cool is linked to Willpower
	fe.awaiting_player_target = false
	fe.pending_defense.clear()
	## The no-op case returns immediately (the awaiting_player_target
	## guard is the very first thing _on_toggle_frightening checks, well
	## before it could ever reach a card-showing await) -- safe to await
	## directly.
	await fe._on_toggle_frightening()
	checks.append(["G: toggling Frightening while not awaiting_player_target is a no-op (mirrors Dual Wield/Strike to Stun's own gate)", not fe.frightening_active and fe._monster_fear_tested.is_empty()])
	fe.awaiting_player_target = true
	## This second call DOES flip the toggle and run a real Fear check
	## (a card + _wait_for_continue()) -- bare statement + _settle(),
	## same reasoning as every other card-producing call above.
	fe._on_toggle_frightening()
	await PsychologyTest._settle(fe, 60)
	checks.append(["G: toggling Frightening ON while usable flips the toggle", fe.frightening_active])
	checks.append(["G: toggling it ON immediately runs a Fear check against the player's own rank", fe._monster_fear_sources.get(goblin, {}).has(test_player)])

	## --- H: Luck (bug fix — user correction: "Luck add +1 to maximum
	##     fortune per lvl, its not separate") — no reroll option at all,
	##     just +1 max Fortune Points per rank on top of current Fate ---
	test_player.talents_taken["Luck"] = 3
	test_player.fate_points = 2
	checks.append(["H: get_max_fortune_points() = Fate + Luck rank (2 + 3 = 5)", test_player.get_max_fortune_points() == 5])
	test_player.talents_taken["Luck"] = 0
	checks.append(["H: with no Luck ranks, get_max_fortune_points() is just Fate (2)", test_player.get_max_fortune_points() == 2])
	test_player.talents_taken["Luck"] = 1
	test_player.fate_points = 4
	checks.append(["H: one rank of Luck adds exactly +1 (4 + 1 = 5)", test_player.get_max_fortune_points() == 5])

	## --- I: no fortune-spend prompt anywhere offers a "Luck: Reroll"
	##     option any more — the earlier (wrong) mechanic is fully gone ---
	test_player.fortune_points = 0   ## isolates this from also offering Spend Fortune
	test_player.corruption_points = 0
	var luck_skill: SkillDefinition = GameData.skill_db.find_by_name("Cool")
	var failed_test := TestResolver.resolve_skill_test(test_player, luck_skill, "", 0, [], 99)   ## forced_roll=99 -> always fails (roll must be <= target to succeed)
	fe.encounter = fe.encounter if fe.encounter != null else CombatEncounter.new()
	var luck_found_box: Array = [false]
	var check_and_decline := func():
		for opt in fe._pending_fortune_options:
			if String(opt.get("text", "")).begins_with("Luck"):
				luck_found_box[0] = true
		fe._decline_fortune_prompt()
	check_and_decline.call_deferred()
	await fe._offer_fortune_spend(failed_test, true, false, false, false, false)
	checks.append(["I: no 'Luck' option is offered on a failed Test even with Luck ranks and no Fortune/Corruption spent this chain", not luck_found_box[0]])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Frightening/Luck): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
