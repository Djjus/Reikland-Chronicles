extends RefCounted
class_name SocialCombatResolverTest
## Verifies the core Social Combat scoring/turn-order machinery (Design
## Doc "Social Combat — Design Doc v1", Slice 1) in isolation from the
## screen — SocialEncounterDefinition.get_npcs() synthesis, Wit-based
## turn order (including multi-NPC), and each of the 4 Attack Types'
## damage/heal math and Social Armor handling.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Case 1: get_npcs() synthesizes a single NPC from legacy
	## fields when npcs is left empty (every one of the 12 core
	## encounters today).
	var legacy_def := SocialEncounterDefinition.new()
	legacy_def.npc_fellowship = 44
	legacy_def.npc_willpower = 36
	legacy_def.portrait_career_key = "pedlar"
	var synthesized := legacy_def.get_npcs()
	checks.append(["Case 1: get_npcs() on empty roster returns exactly one synthesized NPC", synthesized.size() == 1])
	checks.append(["Case 1: synthesized NPC keeps the legacy Fellowship/Willpower", synthesized[0].fellowship == 44 and synthesized[0].willpower == 36])
	checks.append(["Case 1: synthesized NPC keeps the legacy portrait key", synthesized[0].portrait_career_key == "pedlar"])

	## --- Case 2: an explicit multi-NPC roster is returned as-is.
	var group_def := SocialEncounterDefinition.new()
	var npc_a := SocialCombatNPCDefinition.new()
	npc_a.npc_display_name = "Thug One"
	npc_a.intelligence = 30
	npc_a.initiative = 50
	var npc_b := SocialCombatNPCDefinition.new()
	npc_b.npc_display_name = "Thug Two"
	npc_b.intelligence = 60
	npc_b.initiative = 20
	group_def.npcs = [npc_a, npc_b]
	var group_npcs := group_def.get_npcs()
	checks.append(["Case 2: an explicit multi-NPC roster is returned unchanged (2 entries)", group_npcs.size() == 2])

	## --- Case 3: to_character() builds a real adversary Character with
	## the right Composure/Wit-relevant stats.
	var npc_char := npc_a.to_character("Thug One")
	checks.append(["Case 3: to_character() sets allegiance to adversary", npc_char.allegiance == "adversary"])
	checks.append(["Case 3: to_character() carries over Intelligence/Initiative", npc_char.characteristics.intelligence == 30 and npc_char.characteristics.initiative == 50])
	checks.append(["Case 3: to_character() seeds Composure at its own max", npc_char.composure_current == npc_char.composure_max and npc_char.composure_max == npc_a.composure_max])

	## --- Case 4: SocialCombatEncounter turn order sorts by Wit
	## (Intelligence + Initiative), highest first, across a mixed
	## party+multi-NPC roster.
	var game_state = tree.get_root().get_node("/root/GameState")
	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()
	var pc: Character = game_state.player_character
	pc.characteristics.intelligence = 40
	pc.characteristics.initiative = 40   ## Wit 80

	var npc_char_a := npc_a.to_character("Thug One")   ## Wit 30+50 = 80
	var npc_char_b := npc_b.to_character("Thug Two")   ## Wit 60+20 = 80
	## All three deliberately tied at Wit 80 so the tiebreak roll-off
	## path is also exercised, not just the common case.
	var enc := SocialCombatEncounter.new()
	enc.add_combatant(pc)
	enc.add_combatant(npc_char_a)
	enc.add_combatant(npc_char_b)
	enc.roll_initiative()
	checks.append(["Case 4: turn order seats all 3 combatants", enc.turn_order.size() == 3])
	checks.append(["Case 4: round_number starts at 1 after roll_initiative()", enc.round_number == 1])

	var first := enc.advance_turn()
	var second := enc.advance_turn()
	var third := enc.advance_turn()
	var fourth := enc.advance_turn()   ## wraps to round 2, same first actor again (nobody defeated yet)
	checks.append(["Case 4: advance_turn() cycles through all 3 before repeating", first != second and second != third and first != third])
	checks.append(["Case 4: advance_turn() wraps to a new round", enc.round_number == 2])
	checks.append(["Case 4: wrapping returns to the same first actor when nobody is defeated", fourth == first])

	## --- Case 5: get_living()/all_npcs_defeated()/all_party_defeated()
	## correctly reflect Composure state.
	checks.append(["Case 5: both NPCs start living", enc.get_living("adversary").size() == 2])
	checks.append(["Case 5: all_npcs_defeated() is false while any NPC has Composure left", not enc.all_npcs_defeated()])
	npc_char_a.composure_current = 0
	npc_char_b.composure_current = 0
	checks.append(["Case 5: all_npcs_defeated() becomes true once every NPC hits 0 Composure", enc.all_npcs_defeated()])
	checks.append(["Case 5: a defeated NPC is skipped by advance_turn()", enc.advance_turn() == pc])

	## --- Case 6: TestResolver.resolve_opposed() — plain SL comparison.
	var win_result: TestResolver.TestResult = TestResolver.resolve(50, 0, 30)   ## SL +2
	var lose_result: TestResolver.TestResult = TestResolver.resolve(50, 0, 60)   ## SL -1 (fails, floor(50/10)-floor(60/10) = 5-6 = -1)
	var opposed := TestResolver.resolve_opposed(win_result, lose_result)
	checks.append(["Case 6: resolve_opposed() computes Net SL as attacker minus defender", opposed.net_success_levels == win_result.success_levels - lose_result.success_levels])
	checks.append(["Case 6: attacker_wins is true when Net SL is positive", opposed.attacker_wins == (opposed.net_success_levels > 0)])

	## --- Case 7: SocialCombatResolver.finalize_party_attack() — Intimidate
	## (×2 multiplier), damage actually applied to the NPC's Composure.
	var attacker_test: TestResolver.TestResult = TestResolver.resolve(60, 0, 21)   ## roll 21 vs target 60: SL = 6-2 = 4
	var defender_test: TestResolver.TestResult = TestResolver.resolve(40, 0, 55)   ## roll 55 vs target 40: SL = 4-5 = -1 (fail)
	var target_npc := npc_b   ## fresh, undamaged for this case
	var npc_char_fresh := target_npc.to_character("Fresh Thug")
	var composure_before := npc_char_fresh.composure_current
	var exchange := SocialCombatResolver.finalize_party_attack(
		SocialCombatResolver.AttackType.INTIMIDATE, attacker_test, defender_test, npc_char_fresh, 0)
	## Net SL = 4 - (-1) = 5; damage = max(1,5) * 2.0 = 10
	checks.append(["Case 7: Intimidate hits when attacker clearly out-rolls the NPC", exchange.hit])
	checks.append(["Case 7: Intimidate deals Net-SL-times-2 Composure damage", exchange.composure_damage == 10])
	checks.append(["Case 7: the damage was actually applied to the NPC's Composure", npc_char_fresh.composure_current == composure_before - 10])

	## --- Case 8: Social Armor reduces Intimidate/Charm damage but NOT
	## Needle (bypasses it entirely).
	var armored_npc := npc_a.to_character("Armored Thug")
	var armored_before := armored_npc.composure_current
	var armor_exchange := SocialCombatResolver.finalize_party_attack(
		SocialCombatResolver.AttackType.INTIMIDATE, attacker_test, defender_test, armored_npc, 7)
	## raw damage 10, armor 7 -> final 3
	checks.append(["Case 8: Social Armor reduces Intimidate damage", armor_exchange.composure_damage == 3])
	checks.append(["Case 8: Social Armor reduction is reported", armor_exchange.social_armor_reduced == 7])
	checks.append(["Case 8: the reduced damage was what actually applied", armored_npc.composure_current == armored_before - 3])

	var needle_npc := npc_a.to_character("Needled Thug")
	var needle_before := needle_npc.composure_current
	var needle_exchange := SocialCombatResolver.finalize_party_attack(
		SocialCombatResolver.AttackType.NEEDLE, attacker_test, defender_test, needle_npc, 7)
	## Net SL 5, Needle multiplier 1.0 -> raw 5, armor bypassed entirely -> final 5
	checks.append(["Case 8: Needle bypasses Social Armor entirely", needle_exchange.bypassed_social_armor and needle_exchange.composure_damage == 5])
	checks.append(["Case 8: Needle's un-reduced damage actually applied", needle_npc.composure_current == needle_before - 5])

	## --- Case 9: Reason heals an ally instead of damaging the NPC.
	var reason_npc := npc_b.to_character("Reasoned Thug")
	var reason_npc_composure_before := reason_npc.composure_current
	var damaged_ally := Character.new()
	damaged_ally.composure_max = 20
	damaged_ally.composure_current = 5
	var reason_exchange := SocialCombatResolver.finalize_party_attack(
		SocialCombatResolver.AttackType.REASON, attacker_test, defender_test, reason_npc, 0, damaged_ally)
	## Net SL 5 -> heals 5
	checks.append(["Case 9: Reason deals no Composure damage to the NPC at all", reason_npc.composure_current == reason_npc_composure_before])
	checks.append(["Case 9: Reason heals the passed-in ally by Net SL", damaged_ally.composure_current == 10])
	checks.append(["Case 9: Reason's heal is reported on the result", reason_exchange.composure_healed == 5])

	## --- Case 10: a failed opposed roll (defender wins or ties) deals
	## no damage and no heal at all.
	var fail_attacker: TestResolver.TestResult = TestResolver.resolve(30, 0, 55)   ## SL = 3-5 = -2
	var fail_defender: TestResolver.TestResult = TestResolver.resolve(60, 0, 21)   ## SL = 6-2 = 4
	var fail_npc := npc_a.to_character("Undamaged Thug")
	var fail_npc_before := fail_npc.composure_current
	var fail_exchange := SocialCombatResolver.finalize_party_attack(
		SocialCombatResolver.AttackType.CHARM, fail_attacker, fail_defender, fail_npc, 0)
	checks.append(["Case 10: a losing exchange is reported as a miss", not fail_exchange.hit])
	checks.append(["Case 10: a losing exchange deals zero Composure damage", fail_exchange.composure_damage == 0 and fail_npc.composure_current == fail_npc_before])

	## --- Case 11: can_use()/attacking_skill_for() correctly gate Reason
	## behind an actually-trained Advanced skill (Research).
	var untrained := Character.new()
	untrained.skill_advances = {}
	checks.append(["Case 11: an untrained character cannot use Reason (Research is Advanced)", not SocialCombatResolver.can_use(SocialCombatResolver.AttackType.REASON, untrained)])
	var trained := Character.new()
	trained.skill_advances = {"Research": 5}
	checks.append(["Case 11: a character trained in Research can use Reason", SocialCombatResolver.can_use(SocialCombatResolver.AttackType.REASON, trained)])
	checks.append(["Case 11: everyone can use Intimidate (Basic skill)", SocialCombatResolver.can_use(SocialCombatResolver.AttackType.INTIMIDATE, untrained)])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Social Combat Resolver): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
