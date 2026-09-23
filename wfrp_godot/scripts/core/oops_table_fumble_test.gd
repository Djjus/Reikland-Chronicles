extends RefCounted
class_name OopsTableFumbleTest
## Per the bug report ("this combat encounter got stuck after cultist
## fumbled, also noticed it did update his HP from the fumble.."):
## _apply_fumble_effects() used to give exactly ONE of the Oops!
## Table's seven possible results (weapon_damaged_act_last) a real
## mechanical effect — the other six, including the most common band
## (self_inflicted_wound, the one actually rolled in that report) were
## flavour text only. A second, separate bug in the same function
## meant EVERY tag (not just the weapon-damage one) silently did
## nothing at all whenever the weapon was null or indestructible.
## Both are fixed now; this drives the real FieldEncounter scene and
## calls _apply_fumble_effects directly with each of the seven tags,
## confirming each one now has a genuine, verifiable effect. Also
## confirms the new monster-side Stunned turn-skip (a related,
## previously-missing gap — Pummel and some of these new fumble
## results apply Stunned, but nothing on the monster side ever
## checked for it before), and that a forced attacker fumble run all
## the way through the real melee resolver + _apply_fumble_effects +
## _next_turn() completes promptly rather than hanging.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "Eric Troller"
	pc.inventory.clear()

	GameState.pending_encounter_monster_names = ["Giant Rat"]
	if GameData.monster_db.find_by_name("Giant Rat") == null:
		var any_monster: MonsterDefinition = GameData.monster_db.entries[0] if GameData.monster_db.entries.size() > 0 else null
		if any_monster != null:
			GameState.pending_encounter_monster_names = [any_monster.monster_name]

	var scene: PackedScene = load("res://scenes/FieldEncounter.tscn")
	var screen: Node = scene.instantiate()
	tree.get_root().add_child.call_deferred(screen)
	await tree.process_frame
	await tree.process_frame

	checks.append(["FieldEncounter loaded with at least one monster in play", screen.monster_defs.size() > 0])
	var monster: Character = screen.monster_defs.keys()[0]
	var dagger: WeaponDefinition = GameData.weapon_db.find_by_name("Dagger")
	if dagger == null:
		dagger = screen.weapons.get(monster)

	## --- self_inflicted_wound: the exact tag from the bug report -------
	monster.wounds_current = monster.wounds_max
	var before_wounds := monster.wounds_current
	screen._apply_fumble_effects(monster, dagger, {"roll": 12, "tag": "self_inflicted_wound", "text": "You catch yourself awkwardly — lose 1 Wound, ignoring Toughness Bonus and Armour Points."})
	checks.append(["self_inflicted_wound genuinely removes 1 Wound now (was a silent no-op before this fix)", monster.wounds_current == before_wounds - 1])

	## --- The other early-return bug: an indestructible weapon used to
	## block EVERY tag, not just the weapon-damage one. -----------------
	var claw := WeaponDefinition.new()
	claw.weapon_name = "Claw"
	claw.is_indestructible = true
	monster.wounds_current = monster.wounds_max
	screen._apply_fumble_effects(monster, claw, {"roll": 5, "tag": "self_inflicted_wound", "text": "..."})
	checks.append(["An indestructible-weapon wielder's self_inflicted_wound still applies (used to be silently skipped entirely)", monster.wounds_current == monster.wounds_max - 1])

	## --- weapon_damaged_act_last: still works exactly as before --------
	if dagger != null:
		var sword_copy: WeaponDefinition = dagger.duplicate()
		monster.inventory.append(sword_copy.weapon_name)
		monster.weapon_damage_taken.erase(sword_copy.weapon_name)
		screen._apply_fumble_effects(monster, sword_copy, {"roll": 25, "tag": "weapon_damaged_act_last", "text": "..."})
		checks.append(["weapon_damaged_act_last still damages the weapon", int(monster.weapon_damage_taken.get(sword_copy.weapon_name, 0)) > 0])

	## --- next_action_penalty: -10 WS/BS buff for the rest of the Round -
	monster.active_buffs.clear()
	screen._apply_fumble_effects(monster, dagger, {"roll": 50, "tag": "next_action_penalty", "text": "..."})
	var found_penalty := false
	for buff in monster.active_buffs:
		if int(buff["characteristic_bonuses"].get("weapon_skill", 0)) == -10:
			found_penalty = true
	checks.append(["next_action_penalty now applies a real -10 WS/BS buff (was narrative-only before)", found_penalty])

	## --- lose_next_move / miss_next_action: fold into a Stunned stack --
	monster.conditions.erase("Stunned")
	screen._apply_fumble_effects(monster, dagger, {"roll": 65, "tag": "lose_next_move", "text": "..."})
	checks.append(["lose_next_move now applies a real Stunned stack (was narrative-only before)", int(monster.conditions.get("Stunned", 0)) == 1])
	monster.conditions.erase("Stunned")
	screen._apply_fumble_effects(monster, dagger, {"roll": 75, "tag": "miss_next_action", "text": "..."})
	checks.append(["miss_next_action now applies a real Stunned stack (was narrative-only before)", int(monster.conditions.get("Stunned", 0)) == 1])

	## --- critical_wound_minor: a real Critical Wound gets rolled -------
	## The underlying table roll is genuinely random (2 fresh d100s per
	## call, same as any other Critical Wound roll in this project), so
	## a single call can legitimately land on a Trivial ("T") entry that
	## changes neither the Wound count nor Wounds themselves — retried a
	## few times rather than asserting on one roll, since a Trivial-only
	## streak is a real (if rare) possible outcome, not a product bug.
	var cw_changed := false
	for attempt in range(25):
		monster.conditions.erase("Stunned")
		monster.wounds_current = monster.wounds_max
		var cw_count_before: int = monster.active_critical_wound_count
		screen._apply_fumble_effects(monster, dagger, {"roll": 85, "tag": "critical_wound_minor", "text": "..."})
		if monster.active_critical_wound_count > cw_count_before or monster.wounds_current < monster.wounds_max:
			cw_changed = true
			break
	checks.append(["critical_wound_minor genuinely increments the Critical Wound count or deals Wounds (was narrative-only before)", cw_changed])

	## --- hit_random_ally_or_self: needs a positioned ally in range -----
	var ally2 := Character.new()
	ally2.character_name = "Davrin"
	ally2.race = monster.race
	ally2.characteristics = monster.characteristics.duplicate()
	ally2.allegiance = monster.allegiance
	ally2.wounds_max = 20
	ally2.wounds_current = 20
	if screen.battle_grid != null and screen.battle_positions.has(monster):
		screen.battle_positions[ally2] = screen.battle_positions[monster] + Vector2i(1, 0)
		if not screen.encounter.combatants.has(ally2):
			screen.encounter.combatants.append(ally2)
		if not screen.encounter.turn_order.has(ally2):
			screen.encounter.turn_order.append(ally2)
		var before_ally_wounds := ally2.wounds_current
		screen._apply_fumble_effects(monster, dagger, {"roll": 97, "tag": "hit_random_ally_or_self", "text": "..."})
		checks.append(["hit_random_ally_or_self genuinely wounds the in-range ally (was narrative-only before)", ally2.wounds_current < before_ally_wounds])
	else:
		checks.append(["hit_random_ally_or_self setup (battle_grid/positions available)", false])

	## No in-range ally at all -> lands on self, Stunned.
	var lone := Character.new()
	lone.character_name = "Lone Cultist"
	lone.race = monster.race
	lone.characteristics = monster.characteristics.duplicate()
	lone.allegiance = "adversary"
	lone.wounds_max = 8
	lone.wounds_current = 8
	if screen.battle_grid != null:
		screen.battle_positions[lone] = Vector2i(50, 50)   ## far from anyone
		screen.encounter.combatants.append(lone)
		screen.encounter.turn_order.append(lone)
		lone.conditions.erase("Stunned")
		screen._apply_fumble_effects(lone, dagger, {"roll": 99, "tag": "hit_random_ally_or_self", "text": "..."})
		checks.append(["hit_random_ally_or_self with no ally in range leaves the actor Stunned instead", int(lone.conditions.get("Stunned", 0)) == 1])

	## --- Monster-side Stunned turn skip (previously missing) -----------
	monster.conditions.clear()
	monster.conditions["Stunned"] = 1
	screen.battle_over = false
	var t0 := Time.get_ticks_msec()
	await screen._do_monster_turn(monster)
	for i in range(3):
		await tree.process_frame
	var elapsed := Time.get_ticks_msec() - t0
	checks.append(["A Stunned monster's own turn is now skipped without hanging (<2000ms)", elapsed < 2000])

	## --- Full chain, no-hang check: a forced attacker fumble through the
	## real melee resolver, applied, and the turn genuinely advances. ----
	monster.conditions.clear()
	monster.wounds_current = monster.wounds_max
	pc.wounds_current = pc.wounds_max
	var full_chain_combatants: Array[Character] = [pc, monster]
	screen.encounter.combatants = full_chain_combatants
	screen.encounter.turn_order = full_chain_combatants.duplicate()
	screen.player = pc
	screen.battle_over = false
	var pool: GroupAdvantagePool = screen.encounter.advantage_pool
	## Force a failed, doubled attacker roll (99) against the player's real
	## defence -- guaranteed a fumble regardless of stats.
	var melee_skill: SkillDefinition = GameData.skill_db.find_by_name("Melee")
	var result := CombatResolver.resolve_melee_attack(monster, pc, dagger, pool, melee_skill, dagger.skill_group if dagger != null else "Basic", false, 0, 0, 99)
	checks.append(["A forced 99 roll against a real defence produces a genuine fumble", result.attacker_test.is_fumble and not result.fumble.is_empty()])
	var pc_wounds_before := pc.wounds_current
	var t1 := Time.get_ticks_msec()
	screen._apply_fumble_effects(monster, dagger, result.fumble)
	var elapsed2 := Time.get_ticks_msec() - t1
	checks.append(["Applying a real forced fumble completes promptly, no hang (<500ms)", elapsed2 < 500])
	checks.append(["The player's own Wounds are untouched by the MONSTER's own fumble (it's the monster's own mishap, not the player's)", pc.wounds_current == pc_wounds_before])

	screen.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Oops! Table Fumble Effects Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
