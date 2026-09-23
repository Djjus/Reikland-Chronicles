extends RefCounted
class_name GreatFiresAndFirewallLingeringHazardsTest
## Per the explicit request ("Lets correctly implement and add the
## duration based element for Great Fires of U'Zhul and Firewall.
## Lingering AoE effects should be fully removed after combat"),
## following the user's own posted Core Rulebook page image for both
## spells:
##
## Firewall: "You channel a fiery streak of Aqshy, creating a wall of
## flame. The Firewall is Willpower Bonus yards wide, and 1 yard deep.
## For every +2 SL you may extend the length of the Firewall by
## +Willpower Bonus yards. Anyone crossing the firewall gains 1 Ablaze
## condition and suffers a hit with a Damage equal to your Willpower
## Bonus, handled like a magical missile."
##
## Great Fires of U'Zhul: "You hurl a great, explosive blast of Aqshy
## into an enemy, which erupts into a furious blaze, burning with the
## heat of a forge. This is a magical missile with Damage +10 that
## ignores Armour Points and inflicts +2 Ablaze Conditions and the
## Prone Condition on a target. Everyone within the Area of Effect of
## that target suffers a Damage +5 hit ignoring Armour Points, and
## must pass a Dodge Test or also gain +1 Ablaze Condition. The spell
## stops behaving like a magic missile as the fire continues to burn
## in the Area of Effect for the duration. Anyone within the Area of
## Effect at the start of a round suffers 1d10+6 Damage, ignoring APs,
## and gains +1 Ablaze Condition."
##
## Before this fix, Great Fires was a generic is_magic_missile+is_area_
## of_effect spell (same flat Damage to everyone, soaked by Toughness
## AND Armour, nothing left behind), and Firewall was wrongly flagged
## is_area_of_effect = false entirely, routing through the ordinary
## single-target inflicts_condition path — a one-shot Ablaze on one
## chosen enemy, no wall, no lingering fire at all.
##
## Covers: Great Fires' own primary(+10)/splash(+5) split, both
## ignoring Armour Points; the primary's Prone + double Ablaze; the
## splash's Dodge-Test-or-Ablaze (deterministic via the new
## great_fires_dodge_forced_roll test seam); Firewall's own initial
## hit (Willpower Bonus Damage, NOT ignoring Armour, "handled like a
## magical missile"); both spells' new persistent_aoe_hazards ground
## hazard — laid down on this cast's own hit_squares, ticking at the
## start of every Round (deterministic for Firewall's flat damage,
## range-checked for Great Fires' own 1d10+6), hitting ANY character
## who stands there later (ally or adversary, not just the original
## targets), counting down and self-removing after Willpower Bonus
## Rounds; redo-safety (a Fortune redo never stacks a second hazard on
## top of the first, mirroring the pop-back-before-reapply pattern
## buff_added already uses); Great Fires' own Overcast being skipped
## outright (the book itself says it "stops behaving like a magic
## missile"); and the explicit "fully removed after combat" cleanup
## via _end_battle().

static func _make_character(name: String, side: String, armoured: bool = false) -> Character:
	var human := GameData.find_race("Human")
	var soldier := GameData.find_career("Soldier")
	var c := Character.new()
	c.character_name = name
	c.race = human
	c.career = soldier
	c.current_tier = 1
	c.characteristics = CharacteristicSet.new()
	c.recompute_max_wounds()
	## Overridden generously high so nobody in this test dies mid-way
	## through several stacked hits/ticks — that's not what's under
	## test here, and a dead character would drop out of
	## encounter.get_living() and quietly stop taking further hits.
	c.wounds_max = 300
	c.wounds_current = 300
	c.allegiance = side
	if armoured:
		c.equipped_armour = ["Mail Shirt"]   ## 2 AP on Body — real precedent for proving "ignores Armour Points" vs. not
	return c

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## Minimal, safe boot into exploration mode (same setup
	## OutnumberingClusterDisengageTest already established) purely so
	## FieldEncounter.tscn's own _ready() has a valid GameState to
	## read — fe.encounter/battle_grid/battle_positions/player are
	## then fully replaced below with this test's own controlled
	## scenario.
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.current_field_difficulty_tier = 0
	GameState.dungeon_state = {}
	GameState.dungeon_floor_states = {}
	GameState.pending_dungeon_theme_id = "sewer"
	GameState.dungeon_entry_requested = true

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(8):
		await tree.process_frame

	var great_fires: SpellDefinition = GameData.spell_db.find_by_name("Great Fires of U'Zhul")
	var firewall: SpellDefinition = GameData.spell_db.find_by_name("Firewall")
	checks.append(["setup: Great Fires of U'Zhul exists in the spell database", great_fires != null])
	checks.append(["setup: Firewall exists in the spell database", firewall != null])
	checks.append(["THE FIX: Firewall is correctly flagged is_area_of_effect (was wrongly false before this fix)", firewall.is_area_of_effect])

	## Two casters (different Willpower Bonus so each spell's own math
	## stays cleanly separable) plus the actual targets, all real
	## combatants in one shared encounter/battle map.
	var caster_gf := _make_character("HazardCasterGF", "ally")
	caster_gf.characteristics.willpower = 40   ## WB 4
	var caster_fw := _make_character("HazardCasterFW", "ally")
	caster_fw.characteristics.willpower = 80   ## WB 8
	var primary_gf := _make_character("HazardPrimaryGF", "adversary", true)
	var splash_gf := _make_character("HazardSplashGF", "adversary", true)
	## Untrained Dodge target = Agility bonus only = 2 (floor(20/10)) — deliberately low so a forced roll of 96 is a genuine, real failure (96 >= 96 and target < 96), not a coincidence of the numbers chosen.
	var outside_gf := _make_character("HazardOutsideGF", "adversary")
	var bystander_ally := _make_character("HazardBystanderAlly", "ally")
	var target_fw := _make_character("HazardTargetFW", "adversary", true)
	var outside_fw := _make_character("HazardOutsideFW", "adversary")

	fe.encounter = CombatEncounter.new()
	for c in [caster_gf, caster_fw, primary_gf, splash_gf, outside_gf, bystander_ally, target_fw, outside_fw]:
		fe.encounter.add_combatant(c)
	fe.encounter.roll_initiative()

	fe.battle_grid = BattleGrid.new()
	fe.battle_grid.generate_from_terrain_snapshot([])   ## fully open grid

	fe.battle_positions.clear()
	fe.battle_positions[caster_gf] = Vector2i(0, 0)
	fe.battle_positions[caster_fw] = Vector2i(0, 1)
	fe.battle_positions[primary_gf] = Vector2i(10, 10)
	fe.battle_positions[splash_gf] = Vector2i(10, 11)
	fe.battle_positions[bystander_ally] = Vector2i(10, 11)   ## co-located with splash_gf -- proves the ground hazard hits an ally who was never part of the original cast's own `targets` list at all
	fe.battle_positions[outside_gf] = Vector2i(20, 20)       ## well outside either spell's own hit_squares -- negative control
	fe.battle_positions[target_fw] = Vector2i(30, 30)
	fe.battle_positions[outside_fw] = Vector2i(40, 40)

	fe.persistent_aoe_hazards.clear()

	var cast_success := MagicResolver.CastResult.new()
	cast_success.success = true
	var fake_test_result := TestResolver.TestResult.new()
	fake_test_result.target = 50
	fake_test_result.roll = 10
	fake_test_result.success = true
	fake_test_result.success_levels = 4
	cast_success.test_result = fake_test_result

	## --- Great Fires of U'Zhul: primary/splash burst -----------------------
	fe.player = caster_gf
	var gf_hit_squares: Dictionary = {Vector2i(10, 10): true, Vector2i(10, 11): true}
	var gf_targets: Array = [primary_gf, splash_gf]
	## Forced roll 96 against splash_gf's own untrained Dodge target
	## (Agility 20 -> target 20, well under 96) is a genuine, real
	## failure -- same "roll >= 96 against a target under 96 auto-fails"
	## house rule Cauterise's own agony Cool Test already exercises.
	var gf_delta: Dictionary = fe._apply_cast_spell_outcome_aoe(cast_success, great_fires, "Great Fires of U'Zhul", gf_targets, false, -1, gf_hit_squares, Vector2i(10, 10), 96)

	checks.append(["THE FIX: Great Fires' primary target takes Damage+10+WB ignoring Armour Points (12, not 12-2 AP=10)", primary_gf.wounds_current == 300 - 12])
	checks.append(["THE FIX: the primary target is knocked Prone", primary_gf.conditions.has("Prone")])
	checks.append(["THE FIX: the primary target gains +2 Ablaze", int(primary_gf.conditions.get("Ablaze", 0)) == 2])
	checks.append(["THE FIX: Great Fires' splash target takes Damage+5+WB ignoring Armour Points (7)", splash_gf.wounds_current == 300 - 7])
	checks.append(["THE FIX: a splash target who fails its Dodge Test gains +1 Ablaze", int(splash_gf.conditions.get("Ablaze", 0)) == 1])
	checks.append(["setup: a target well outside the blast radius is untouched by the burst", outside_gf.wounds_current == 300 and not outside_gf.conditions.has("Ablaze")])
	checks.append(["THE FIX: the initial burst lays down a real, tracked ground hazard", gf_delta.get("hazard_added", false) == true])
	checks.append(["THE FIX: exactly one hazard is now tracked, for Willpower Bonus (4) Rounds", fe.persistent_aoe_hazards.size() == 1 and int(fe.persistent_aoe_hazards[0]["rounds_remaining"]) == 4])
	checks.append(["setup: the hazard's own squares match this cast's hit_squares exactly", fe.persistent_aoe_hazards[0]["squares"].size() == 2 and fe.persistent_aoe_hazards[0]["squares"].has(Vector2i(10, 10)) and fe.persistent_aoe_hazards[0]["squares"].has(Vector2i(10, 11))])

	## --- Redo-safety: a Fortune redo must not stack a second hazard --------
	## Mirrors exactly what _on_cast_spell_aoe's own redo loop does: undo
	## the previous attempt's Wounds, pop the hazard it added back off,
	## then reapply.
	for t in gf_delta["aoe_wound_deltas"]:
		var amount: int = gf_delta["aoe_wound_deltas"][t]
		t.wounds_current = min(t.wounds_max, t.wounds_current + amount)
	checks.append(["setup: the redo's own undo correctly restores both targets' Wounds", primary_gf.wounds_current == 300 and splash_gf.wounds_current == 300])
	if gf_delta.get("hazard_added", false) and not fe.persistent_aoe_hazards.is_empty():
		fe.persistent_aoe_hazards.pop_back()
	checks.append(["setup: the stale hazard was popped back off before the redo", fe.persistent_aoe_hazards.is_empty()])
	var gf_delta2: Dictionary = fe._apply_cast_spell_outcome_aoe(cast_success, great_fires, "Great Fires of U'Zhul", gf_targets, true, -1, gf_hit_squares, Vector2i(10, 10), 1)
	checks.append(["THE FIX: a Fortune redo re-applies the SAME deterministic burst Damage, not a doubled one", primary_gf.wounds_current == 300 - 12 and splash_gf.wounds_current == 300 - 7])
	checks.append(["THE FIX: a Fortune redo does NOT stack a second hazard on top of the first", fe.persistent_aoe_hazards.size() == 1])

	## --- Great Fires' own Overcast is skipped outright ---------------------
	## Per the book's own "stops behaving like a magic missile" line --
	## _offer_overcasting_aoe must bail out before ever opening the
	## Overcast prompt for this spell.
	fe.awaiting_overcast_choice = false
	fe._offer_overcasting_aoe(great_fires, "Great Fires of U'Zhul", 3)
	checks.append(["THE FIX: Great Fires of U'Zhul never offers an Overcast prompt (the book says it stops behaving like a magic missile)", fe.awaiting_overcast_choice == false])

	## --- Ground hazard tick: hits the smouldering ground, not just the
	## original targets (bystander_ally never appeared in `targets` at
	## all) -------------------------------------------------------------
	var primary_before_tick: int = primary_gf.wounds_current
	var splash_before_tick: int = splash_gf.wounds_current
	var bystander_before_tick: int = bystander_ally.wounds_current
	fe._tick_persistent_aoe_hazards()
	var primary_tick_loss: int = primary_before_tick - primary_gf.wounds_current
	var splash_tick_loss: int = splash_before_tick - splash_gf.wounds_current
	var bystander_tick_loss: int = bystander_before_tick - bystander_ally.wounds_current
	checks.append(["THE FIX: the primary target, still standing on the burning ground, takes a fresh 1d10+6 hit (5-14 after Toughness Bonus)", primary_tick_loss >= 5 and primary_tick_loss <= 14])
	checks.append(["THE FIX: the splash target, likewise still there, is hit again by the same tick", splash_tick_loss >= 5 and splash_tick_loss <= 14])
	checks.append(["THE FIX: an ally who was never part of the original cast's own targets is STILL hit once they're standing on the ground fire -- the hazard belongs to the squares, not the original targets", bystander_tick_loss >= 5 and bystander_tick_loss <= 14])
	checks.append(["THE FIX: the tick also grants the ally bystander +1 Ablaze, cleanly (never touched by the burst or the redo)", int(bystander_ally.conditions.get("Ablaze", 0)) == 1])
	checks.append(["setup: a target well outside the hazard's own squares remains completely untouched by the tick", outside_gf.wounds_current == 300])
	checks.append(["setup: the hazard's own Round counter ticked down by exactly 1", int(fe.persistent_aoe_hazards[0]["rounds_remaining"]) == 3])

	## Exhaust the remaining 3 Rounds of Duration -- the hazard must
	## self-remove the moment its counter reaches 0, with no other
	## cleanup call needed.
	fe._tick_persistent_aoe_hazards()
	fe._tick_persistent_aoe_hazards()
	fe._tick_persistent_aoe_hazards()
	checks.append(["THE FIX: after Willpower Bonus (4) total Round ticks, the Great Fires hazard removes itself automatically", fe.persistent_aoe_hazards.is_empty()])

	## --- Firewall: initial hit (Willpower Bonus Damage, NOT ignoring
	## Armour Points) + its own lingering wall -------------------------------
	fe.player = caster_fw
	var fw_hit_squares: Dictionary = {Vector2i(30, 30): true}
	var fw_targets: Array = [target_fw]
	var fw_delta: Dictionary = fe._apply_cast_spell_outcome_aoe(cast_success, firewall, "Firewall", fw_targets, false, -1, fw_hit_squares, Vector2i(30, 30))
	checks.append(["THE FIX: Firewall's initial hit is a real Willpower Bonus Damage hit, soaked by Toughness AND Armour (8 Damage - 2 TB - 2 AP = 4), NOT ignoring Armour Points like Great Fires does", target_fw.wounds_current == 300 - 4])
	checks.append(["THE FIX: anyone caught as the wall goes up gains 1 Ablaze", int(target_fw.conditions.get("Ablaze", 0)) == 1])
	checks.append(["THE FIX: Firewall's own cast also lays down a real, tracked ground hazard", fw_delta.get("hazard_added", false) == true])
	checks.append(["THE FIX: exactly one Firewall hazard is tracked, for this caster's own Willpower Bonus (8) Rounds", fe.persistent_aoe_hazards.size() == 1 and fe.persistent_aoe_hazards[0]["name"] == "Firewall" and int(fe.persistent_aoe_hazards[0]["rounds_remaining"]) == 8])
	checks.append(["setup: a target well outside the wall's own squares is untouched", outside_fw.wounds_current == 300 and not outside_fw.conditions.has("Ablaze")])

	## A player casting Firewall onto open, empty ground (clicked a
	## point with no one standing in it) still lays down a real,
	## persisting wall -- it just has no one to hit on the way up.
	var fw_delta_empty: Dictionary = fe._apply_cast_spell_outcome_aoe(cast_success, firewall, "Firewall", [], true, -1, {Vector2i(50, 50): true}, Vector2i(50, 50))
	checks.append(["THE FIX: casting Firewall over empty ground still lays down a real, lingering wall (not just a no-op)", fw_delta_empty.get("hazard_added", false) == true and fe.persistent_aoe_hazards.size() == 2])
	checks.append(["setup: casting over empty ground correctly applies no Wounds to anyone", fw_delta_empty["aoe_wound_deltas"].is_empty()])

	## --- Firewall's own tick: deterministic (no dice at all) ---------------
	var target_fw_before_tick: int = target_fw.wounds_current
	fe._tick_persistent_aoe_hazards()
	checks.append(["THE FIX: Firewall's own ground tick deals exactly Willpower Bonus Damage again (8 - 2 TB - 2 AP = 4), same soak rule as its initial hit", target_fw_before_tick - target_fw.wounds_current == 4])
	checks.append(["setup: a target well outside the wall's own squares remains untouched by the tick too", outside_fw.wounds_current == 300])

	## --- "Lingering AoE effects should be fully removed after combat" ------
	checks.append(["setup: at least one hazard is still active going into end-of-battle cleanup", not fe.persistent_aoe_hazards.is_empty()])
	fe._end_battle(true)
	checks.append(["THE FIX: every lingering ground hazard is fully removed the moment combat ends", fe.persistent_aoe_hazards.is_empty()])

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
	print("RESULT (Great Fires and Firewall Lingering Hazards): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
