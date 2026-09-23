extends RefCounted
class_name MonsterWeaponRangeSwitchTest
## Regression test for the follow-up request ("would the outlaw tier 2
## use his bow in combat at present?" -> "No" -> "They should always use
## all the armor they have, but weapons they should switch during combat
## to what every is best at the moment, ie ranged or melee.").
##
## Confirms field_encounter_screen.gd's new
## _maybe_switch_monster_weapon_for_range(actor):
## - switches to a real ranged weapon (Bow) when no living enemy is
##   adjacent, clearing the offhand;
## - switches to a real non-Defensive melee weapon (Sword) once an
##   enemy IS adjacent, and re-equips a carried Shield to the offhand at
##   the same time (Shield itself is excluded from the melee-weapon
##   search — it's an offhand pairing, not a standalone weapon choice);
## - refreshes the `weapons[]` cache actor -> WeaponDefinition each time,
##   which is what the rest of the monster AI (_monster_attack and its
##   movement/shooting logic) actually branches on;
## - is a safe no-op for a monster carrying only one real weapon type
##   (the overwhelming majority of ordinary MonsterDefinition-based
##   monsters), regardless of range to the nearest enemy.
##
## Uses `fe` (a live FieldEncounter.tscn instance the caller owns),
## matching this project's own `run_test(fe)` convention (see
## monster_turn_stall_watchdog_test.gd). A real BanditGenerator Tier 2
## Outlaw (Sword equipped by default, Bow with 10 Arrows + Shield in
## inventory from Tier 2's own trappings) supplies the two real weapon
## options; a plain Tier 0 Brigand (Sword only, no Bow) supplies the
## single-weapon-type no-op case.

static func run_test(fe) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.current_field_difficulty_tier = 0
	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	## A single weak, irrelevant monster -- this test never touches it;
	## it's only here so _start_encounter() has a real, complete battle
	## (turn order, battle_positions, a real living ally) to attach the
	## purpose-built bandit(s) onto below.
	GameState.pending_encounter_monster_names = ["Giant Rat"]
	await fe._start_encounter()
	for i in range(5):
		await fe.get_tree().process_frame

	var setup_ok: bool = fe.encounter != null and fe.battle_positions.has(fe.player)
	checks.append(["setup: a real encounter with the player positioned on the battle grid", setup_ok])
	if not setup_ok:
		print("RESULT (Monster Weapon Range Switch): SETUP FAILED")
		return false

	var player_pos: Vector2i = fe.battle_positions[fe.player]

	## --- Two-weapon-type bandit: Bow (ranged) + Sword (melee) + Shield --
	var bandit: Character = BanditGenerator.build_bandit("Test Weapon Switch Bandit", 2)
	checks.append(["setup: Tier 2 bandit built with both a Bow and a Sword available", bandit != null and bandit.inventory.has("Bow") and bandit.inventory.has("Shield")])
	if bandit == null:
		print("RESULT (Monster Weapon Range Switch): SETUP FAILED")
		return false
	fe.encounter.add_combatant_mid_round(bandit)
	fe.battle_positions[bandit] = player_pos + Vector2i(10, 0)   ## far away -- distance 10, nobody adjacent

	fe._maybe_switch_monster_weapon_for_range(bandit)
	checks.append(["Far from any enemy: switches to the real ranged weapon (Bow)", bandit.equipped_weapon == "Bow"])
	checks.append(["Far from any enemy: offhand is cleared (no Shield needed at range)", bandit.equipped_offhand == ""])
	checks.append(["Far from any enemy: the weapons[] AI cache is refreshed to the new ranged weapon", fe.weapons.has(bandit) and fe.weapons[bandit] != null and fe.weapons[bandit].is_ranged])

	fe.battle_positions[bandit] = player_pos + Vector2i(1, 0)   ## adjacent -- distance 1
	fe._maybe_switch_monster_weapon_for_range(bandit)
	checks.append(["Adjacent to an enemy: switches to the real melee weapon (Sword)", bandit.equipped_weapon == "Sword"])
	checks.append(["Adjacent to an enemy: a carried Shield is re-equipped to the offhand", bandit.equipped_offhand == "Shield"])
	checks.append(["Adjacent to an enemy: the weapons[] AI cache is refreshed to the new melee weapon", fe.weapons.has(bandit) and fe.weapons[bandit] != null and not fe.weapons[bandit].is_ranged])

	## Reversible: moving back out of melee range switches back to ranged
	## and clears the offhand again, exactly as the first switch did.
	fe.battle_positions[bandit] = player_pos + Vector2i(10, 0)
	fe._maybe_switch_monster_weapon_for_range(bandit)
	checks.append(["Moving back out of range switches back to the Bow", bandit.equipped_weapon == "Bow"])
	checks.append(["Moving back out of range clears the offhand again", bandit.equipped_offhand == ""])

	## Calling again with no change in range/loadout is a genuine no-op
	## (the function returns early once already carrying the right
	## weapon for the current distance) -- nothing should change.
	fe._maybe_switch_monster_weapon_for_range(bandit)
	checks.append(["Calling again at the same range changes nothing further", bandit.equipped_weapon == "Bow" and bandit.equipped_offhand == ""])

	## --- Single-weapon-type bandit: Sword only, no Bow -- must no-op ----
	var brigand: Character = BanditGenerator.build_bandit("Test Single Weapon Brigand", 0)
	checks.append(["setup: Tier 0 brigand built with only a Sword (no Bow) available", brigand != null and not brigand.inventory.has("Bow")])
	if brigand != null:
		fe.encounter.add_combatant_mid_round(brigand)
		fe.battle_positions[brigand] = player_pos + Vector2i(10, 0)   ## far
		fe._maybe_switch_monster_weapon_for_range(brigand)
		checks.append(["Single-weapon monster far from any enemy: no-op, still the starting Sword", brigand.equipped_weapon == "Sword"])
		fe.battle_positions[brigand] = player_pos + Vector2i(1, 0)   ## adjacent
		fe._maybe_switch_monster_weapon_for_range(brigand)
		checks.append(["Single-weapon monster adjacent to an enemy: still a no-op, same Sword", brigand.equipped_weapon == "Sword"])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Monster Weapon Range Switch): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
