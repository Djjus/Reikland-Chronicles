extends RefCounted
class_name DarknessVisionTest
## Per the request: "Night vision talent and Dark vision trait...
## field encounters be impacted by time of day and light conditions...
## include the light source system too... allow light sources in
## inventory to be equipped... with the switch weapon button. Darken
## the battle maps when its night time. Melee in darkness has a
## penalty of -20, and Ranged attacks on targets in darkness a penalty
## of -30. Both night vision and dark vision negate these penalties in
## their own way. And light source will cancel the darkness effect
## within their area... humanoid enemies will usually carry their own
## light sources at night time in combat."
##
## Confirms, through a real FieldEncounter instance (not a standalone
## unit test of the maths, since the whole point is this actually being
## wired into the real combat flow): the Melee (-20) / Ranged (-30)
## Darkness penalty applies only when the relevant square (the
## ATTACKER's own for Melee, the TARGET's for Ranged — see
## FieldEncounterScreen._darkness_penalty()'s own comment for why
## they differ) isn't lit; that the Dark Vision Creature Trait negates
## it unconditionally; that the Night Vision Talent/Trait negates it
## given at least ambient light (anywhere except a genuinely pitch-
## black dark_location) and, even there, once a light source's own
## reach is extended by its "20 yards per level" clause; that ANY
## active light source (ally or adversary) cancels the penalty for
## anyone standing in its radius regardless of vision; that switching
## onto a light source sitting in inventory via the mid-combat weapon-
## switch button actually lights it (oil-based and self-fuel sources
## both); that the battle map's own visual state (BattleGridView's
## battle_dark_active/dark_light_sources) reflects the same darkness;
## and that Humanoid adversaries are usually handed a lit Lantern of
## their own when a fight starts at night.

static func _spin_up(tree: SceneTree, monster_names: Array[String], is_dark: bool, is_pitch_black: bool) -> Dictionary:
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "DarknessTester"
	pc.inventory.clear()
	pc.inventory.append("Sword")
	pc.equipped_weapon = "Sword"
	pc.equipped_offhand = ""
	pc.light_mode = "off"
	pc.light_fuel_minutes = 0.0
	pc.talents_taken.clear()

	GameState.pending_encounter_monster_names = monster_names
	GameState.pending_battle_is_dark = is_dark
	GameState.pending_battle_is_pitch_black = is_pitch_black

	var scene: PackedScene = load("res://scenes/FieldEncounter.tscn")
	var fe: Node = scene.instantiate()
	tree.get_root().add_child.call_deferred(fe)
	await tree.process_frame
	await tree.process_frame
	return {"pc": pc, "fe": fe}

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Part 1: the core Melee/Ranged Darkness penalty + negation
	## rules, on an ordinary (not pitch-black) dark night. -----------------
	var setup := await _spin_up(tree, ["Giant Rat"], true, false)
	var fe: Node = setup["fe"]
	var pc: Character = setup["pc"]
	checks.append(["FieldEncounter loaded with at least one monster in play", fe.monster_defs.size() > 0])
	var monster: Character = fe.monster_defs.keys()[0] if not fe.monster_defs.is_empty() else null
	checks.append(["battle_is_dark is captured from GameState.pending_battle_is_dark at the start of the fight", fe.battle_is_dark == true])
	checks.append(["battle_is_pitch_black is correctly false for an ordinary dark night (not a dark_location)", fe.battle_is_pitch_black == false])

	if monster != null and fe.battle_positions.has(pc):
		fe.battle_positions[monster] = fe.battle_positions[pc] + Vector2i(1, 0)

		checks.append(["Melee in darkness suffers -20 with no vision Talent/Trait and no light nearby", fe._darkness_penalty(pc, monster, false) == -20])
		checks.append(["Ranged at a target in darkness suffers -30 with no vision Talent/Trait and no light nearby", fe._darkness_penalty(pc, monster, true) == -30])

		## Night Vision negates it under ordinary night darkness — its own
		## "at least a faint source of light" is satisfied by plain
		## ambient starlight/moonlight here, no lantern needed.
		pc.talents_taken["Night Vision"] = 1
		checks.append(["Night Vision Talent negates the Melee penalty under ordinary night darkness (ambient light is enough)", fe._darkness_penalty(pc, monster, false) == 0])
		checks.append(["...and the Ranged penalty too", fe._darkness_penalty(pc, monster, true) == 0])
		pc.talents_taken.erase("Night Vision")

		## Dark Vision negates it unconditionally — even for a monster
		## attacker, and with no ambient light assumption involved at all.
		monster.creature_traits.append("Dark Vision")
		## Toggled to pitch-black just for this one check: a Giant Rat
		## naturally has its OWN innate Night Vision Creature Trait (real
		## bestiary data — see core_monsters.tres), which would otherwise
		## also negate the penalty under ordinary night darkness and mask
		## whether this specific assertion is really testing Dark Vision
		## at all. Pitch-black neutralizes that innate Night Vision (no
		## light source is present here), isolating Dark Vision's own
		## unconditional negation.
		fe.battle_is_pitch_black = true
		checks.append(["Dark Vision Trait negates the Melee penalty for a monster attacker, unconditionally — even in a pitch-black place where its own innate Night Vision alone would not", fe._darkness_penalty(monster, pc, false) == 0])
		monster.creature_traits.erase("Dark Vision")
		checks.append(["...and the penalty returns once Dark Vision is removed again (confirms the Trait, not the Giant Rat's own innate Night Vision, was doing it)", fe._darkness_penalty(monster, pc, false) == -20])
		fe.battle_is_pitch_black = false

		## An active light source right on the relevant square cancels the
		## penalty for anyone standing in it — no vision Talent needed.
		pc.inventory.append("Lantern")
		pc.equipped_offhand = "Lantern"
		pc.light_mode = "on"
		pc.light_fuel_minutes = Character.LAMP_OIL_MINUTES
		checks.append(["A lit Lantern cancels the Melee penalty for the character carrying it, with no vision Talent involved", fe._darkness_penalty(pc, monster, false) == 0])
		pc.light_mode = "off"
		pc.equipped_offhand = ""
		pc.light_fuel_minutes = 0.0
		pc.inventory.erase("Lantern")
		checks.append(["...and the penalty is back once the Lantern is put away", fe._darkness_penalty(pc, monster, false) == -20])

	fe.queue_free()
	await tree.process_frame

	## --- Part 2: a genuinely pitch-black dark_location — Night Vision
	## ALONE (no light source at all) is not enough, but its own "extend
	## the effective illumination distance of any light sources by 20
	## yards per level" clause then lets a distant light source (beyond
	## its own bare radius) still count. --------------------------------
	var setup2 := await _spin_up(tree, ["Giant Rat"], true, true)
	var fe2: Node = setup2["fe"]
	var pc2: Character = setup2["pc"]
	var monster2: Character = fe2.monster_defs.keys()[0] if not fe2.monster_defs.is_empty() else null
	checks.append(["battle_is_pitch_black is correctly true for a dark_location", fe2.battle_is_pitch_black == true])

	if monster2 != null and fe2.battle_positions.has(pc2):
		pc2.talents_taken["Night Vision"] = 1
		fe2.battle_positions[monster2] = fe2.battle_positions[pc2] + Vector2i(1, 0)
		checks.append(["In a truly pitch-black place, Night Vision ALONE (no light source in reach at all) does NOT negate the penalty", fe2._darkness_penalty(pc2, monster2, false) == -20])

		## A Candle's own bare radius is 10 yards = 5 battle-grid squares.
		## Placed 8 squares away, it's out of its own bare reach but well
		## within Night Vision rank 1's own +20-yard (+10-square) extension.
		monster2.inventory.append("Candle (dozen)")
		monster2.equipped_offhand = "Candle (dozen)"
		monster2.light_mode = "on"
		monster2.light_fuel_minutes = 240.0
		fe2.battle_positions[monster2] = fe2.battle_positions[pc2] + Vector2i(8, 0)
		checks.append(["Night Vision's own light-range extension (20 yards/rank) reaches a Candle 8 squares away in a pitch-black place, beyond its own bare 5-square radius", fe2._darkness_penalty(pc2, monster2, false) == 0])
		pc2.talents_taken.erase("Night Vision")
		checks.append(["...but without Night Vision, that same distant Candle is too far away to help — the penalty is back", fe2._darkness_penalty(pc2, monster2, false) == -20])

	fe2.queue_free()
	await tree.process_frame

	## --- Part 3: Humanoid adversaries usually carry their own lit
	## light source into a night fight — probabilistic (~75% each), so
	## spawning 20 makes "all 20 happened to roll the 25% miss" the only
	## way this could flake (0.25^20, effectively impossible). -----------
	var bandit_names: Array[String] = []
	for i in range(20):
		bandit_names.append("Highway Bandit")
	var setup3 := await _spin_up(tree, bandit_names, true, false)
	var fe3: Node = setup3["fe"]
	var any_lit := false
	for m in fe3.monsters:
		if m.equipped_offhand == "Lantern" and m.light_mode == "on":
			any_lit = true
			break
	checks.append(["At least one of 20 Humanoid adversaries spawned into a dark battle carries a lit Lantern of their own", any_lit])
	fe3.queue_free()
	await tree.process_frame

	## --- Part 4: mid-combat weapon-switch onto a light source sitting
	## in inventory — it now appears in the switch list, AND switching to
	## it actually lights it (both the oil-based and self-fuel paths). --
	var setup4 := await _spin_up(tree, ["Giant Rat"], false, false)
	var fe4: Node = setup4["fe"]
	var pc4: Character = setup4["pc"]
	pc4.inventory.append("Candle (dozen)")
	var switchable: Array[String] = fe4._switchable_weapons(pc4, pc4.equipped_weapon)
	checks.append(["A light source sitting in inventory now appears in the mid-combat weapon-switch list", switchable.has("Candle (dozen)")])

	fe4.awaiting_player_target = true
	fe4.pending_defense = {}
	fe4.main_weapon_switched_this_turn = false
	fe4._apply_main_weapon_switch("Candle (dozen)")
	checks.append(["Switching to a Candle equips it in the main hand", pc4.equipped_weapon == "Candle (dozen)"])
	checks.append(["...and automatically lights it, drawing one unit's own fuel since it started out unlit (self-fuel path)", pc4.light_mode == "on" and is_equal_approx(pc4.light_fuel_minutes, 240.0)])

	pc4.equipped_weapon = "Sword"
	pc4.light_mode = "off"
	pc4.light_fuel_minutes = 0.0
	pc4.inventory.append("Lantern")
	pc4.inventory.append("Lamp Oil")
	fe4.main_weapon_switched_this_turn = false
	fe4._apply_main_weapon_switch("Lantern")
	checks.append(["A Lantern switched in mid-combat lights from Lamp Oil already in inventory (oil path)", pc4.light_mode == "on" and is_equal_approx(pc4.light_fuel_minutes, Character.LAMP_OIL_MINUTES)])

	pc4.equipped_weapon = "Sword"
	pc4.light_mode = "off"
	pc4.light_fuel_minutes = 0.0
	pc4.inventory.append("Storm Lantern")
	fe4.main_weapon_switched_this_turn = false
	fe4._apply_main_weapon_switch("Storm Lantern")
	checks.append(["A Storm Lantern switched in with no Lamp Oil left in inventory (the earlier switch used the only unit) stays unlit rather than lighting for free", pc4.light_mode == "off"])

	## --- Part 5: the battle map's own visual state mirrors the same
	## darkness/light data (BattleGridView.battle_dark_active/
	## dark_light_sources), pushed via set_state(). ----------------------
	fe4.battle_is_dark = true
	pc4.equipped_weapon = "Sword"
	pc4.inventory.append("Lantern")
	pc4.equipped_offhand = "Lantern"
	pc4.light_mode = "on"
	pc4.light_fuel_minutes = Character.LAMP_OIL_MINUTES
	fe4._render_status()
	checks.append(["The battle grid view receives battle_dark_active == true", fe4.grid_view.battle_dark_active == true])
	checks.append(["...and at least one active light source (the lit Lantern)", not fe4.grid_view.dark_light_sources.is_empty()])
	if not fe4.grid_view.dark_light_sources.is_empty():
		var src: Dictionary = fe4.grid_view.dark_light_sources[0]
		checks.append(["The Lantern's own 20-yard radius converts to 10 battle-grid squares (BattleGrid.YARDS_PER_SQUARE == 2)", int(src["radius"]) == 10])

	fe4.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Night Vision / Dark Vision / Battle Darkness Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
