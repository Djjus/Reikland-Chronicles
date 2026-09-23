extends RefCounted
class_name SocialCombatTalentsTest
## Verifies the 5 Talents from the user's rulebook screenshots (Attractive,
## Argumentative, Gregarious, Etiquette (Social Group), Cat-tongued) per
## the request ("lets implement these talents and find application for
## them in social encounters"). Four of the five already existed as
## TalentDefinition data entries in core_talents.tres; this covers:
## - Attractive/Argumentative: already-correct data, confirming the
##   generic units_digit_as_sl pipeline (TestResolver.resolve_skill_test())
##   really does apply automatically inside Social Combat's own Charm
##   attack, with zero Social-Combat-specific code.
## - Gregarious: a genuine data correction (was "group_rapport_bonus",
##   parked; corrected to "reverse_dice_on_fail" on Gossip, matching the
##   real rule) — same generic pipeline, applied to Needle (which always
##   resolves via Gossip in this project — see SocialCombatResolver.
##   attacking_skill_for()'s own comment on why Haggle never actually
##   gets used).
## - Cat-tongued: new bespoke wiring — a lying Charm attack becomes fully
##   unopposed (Character.has_unopposed_test(), checked directly by
##   SocialEncounterScreen._attempt_social_attack() since there's no
##   generic "skip the other side's roll" mechanism to hook into).
## - Etiquette (Social Group): new bespoke wiring — a flat per-rank SL
##   bonus to Charm/Gossip against an NPC whose own derived group
##   (SocialCombatNPCDefinition.get_etiquette_group(), off that NPC's
##   real Career's career_class) matches a group this character actually
##   trained Etiquette for; verified both when it matches AND when a
##   differently-grouped Etiquette rank does NOT cross over.
##
## Same conventions social_combat_conditions_test.gd already established:
## forced_attacker_roll/forced_defender_roll drive _attempt_social_attack()
## deterministically, _arm_no_fortune_prompt collapses the Fortune/Dark
## Deal prompt to its no-choice Continue shortcut, and a clean A/B
## Composure-damage delta isolates each Talent's own SL effect from
## everything else in the roll.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	var game_state = tree.get_root().get_node("/root/GameState")
	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()
	var pc: Character = game_state.player_character
	pc.fortune_points = 0
	pc.talents_taken.clear()
	pc.skill_advances.erase("Charm")
	pc.skill_advances.erase("Gossip")

	var scene_res: PackedScene = load("res://scenes/SocialEncounter.tscn")
	var screen: Control = scene_res.instantiate()
	tree.get_root().add_child(screen)
	for i in range(10):
		await tree.process_frame

	checks.append(["Screen started a real Social Combat", screen.social_combat != null])
	var npc_a: Character = screen.npc_characters[0] if not screen.npc_characters.is_empty() else null
	checks.append(["A real NPC exists to target", npc_a != null])

	if screen.social_combat == null or npc_a == null:
		var all_pass_early := true
		for chk in checks:
			print(("PASS  " if chk[1] else "FAIL  ") + chk[0])
			if not chk[1]:
				all_pass_early = false
		print("RESULT (Social Combat Talents): ", "ALL PASS" if all_pass_early else "SOME FAILED")
		return all_pass_early

	screen.selected_npc_target = npc_a
	var charm_def: SkillDefinition = GameData.skill_db.find_by_name("Charm")
	var gossip_def: SkillDefinition = GameData.skill_db.find_by_name("Gossip")

	## Neutral armor (0) for every case below, so the measured Composure
	## delta reflects only the Talent's own SL effect — see
	## _social_armor_against()'s own comment for the Status-comparison
	## formula this sidesteps.
	screen.npc_status_ordinal_by_char[npc_a] = pc.get_status_ordinal()

	## --- Attractive/Argumentative: units-digit-as-SL, already-correct
	## data. A cheap direct check (both Talents share the exact same
	## effect_tag/mechanism) plus one full round-trip through Social
	## Combat's own Charm attack for Argumentative specifically. --------
	checks.append(["Attractive grants has_units_digit_as_sl(['Charm']) with no other Talent involved", not pc.has_units_digit_as_sl(["Charm"])])
	pc.talents_taken["Attractive"] = 1
	checks.append(["...and it does once Attractive is trained", pc.has_units_digit_as_sl(["Charm"])])
	pc.talents_taken.clear()

	pc.characteristics.fellowship = 50   ## Charm skill value 50, untrained
	npc_a.characteristics.initiative = 20
	npc_a.remove_condition("Exposed")
	npc_a.remove_condition("Humiliated")

	npc_a.composure_max = 200
	npc_a.composure_current = 200
	_arm_no_fortune_prompt(screen)
	## Attacker: target 50, roll 42 -> computed SL +1 (marginal success).
	## Defender: target 20, roll 99 -> auto-fail, forced SL -7 (roll>=96
	## with a sub-96 target). Net SL = 1 - (-7) = 8, damage floor(8*1.5)=12.
	screen._attempt_social_attack(pc, SocialCombatResolver.AttackType.CHARM, charm_def, 42, 99)
	await tree.process_frame
	var drop_no_argumentative: int = 200 - npc_a.composure_current
	checks.append(["Baseline Charm hit (no Talent) lands the expected 12 Composure damage", drop_no_argumentative == 12])

	pc.talents_taken["Argumentative"] = 1
	npc_a.composure_current = 200
	_arm_no_fortune_prompt(screen)
	## Same rolls: Argumentative overrides SL to the roll's units digit
	## (2) since 2 > the computed 1. Net SL = 2 - (-7) = 9, damage
	## floor(9*1.5)=13 -- exactly 1 more than the baseline.
	screen._attempt_social_attack(pc, SocialCombatResolver.AttackType.CHARM, charm_def, 42, 99)
	await tree.process_frame
	var drop_with_argumentative: int = 200 - npc_a.composure_current
	checks.append(["Argumentative's units-digit-as-SL already works inside Social Combat's own Charm attack (+1 extra Composure damage)", drop_with_argumentative - drop_no_argumentative == 1])
	pc.talents_taken.clear()

	## --- Gregarious: reverse-dice-on-fail, corrected data, on Needle
	## (which always resolves via Gossip -- see attacking_skill_for()). -
	pc.characteristics.fellowship = 34   ## Gossip skill value 34, untrained
	npc_a.characteristics.initiative = 40
	npc_a.composure_current = 200
	_arm_no_fortune_prompt(screen)
	## Attacker: target 34, roll 43 -> a plain failure (43 > 34), and
	## nothing about a failed attack can land a hit, whatever the
	## defender rolls.
	screen._attempt_social_attack(pc, SocialCombatResolver.AttackType.NEEDLE, gossip_def, 43, 50)
	await tree.process_frame
	checks.append(["Baseline Gossip failure (no Talent) lands no hit at all", npc_a.composure_current == 200])

	pc.talents_taken["Gregarious"] = 1
	npc_a.composure_current = 200
	_arm_no_fortune_prompt(screen)
	## Same forced roll of 43: Gregarious reverses it to 34 (digit swap),
	## which succeeds against the same target of 34 -- turning the exact
	## same roll that just failed into a landed hit.
	screen._attempt_social_attack(pc, SocialCombatResolver.AttackType.NEEDLE, gossip_def, 43, 50)
	await tree.process_frame
	checks.append(["Gregarious's corrected reverse-dice-on-fail turns that same failed roll into a real hit", npc_a.composure_current < 200])
	pc.talents_taken.clear()

	## --- Cat-tongued: fully unopposed Charm -- the NPC's own strong
	## Initiative roll, which would otherwise win outright, never gets
	## the chance to. ----------------------------------------------------
	pc.characteristics.fellowship = 30   ## Charm skill value 30, untrained
	npc_a.characteristics.initiative = 90
	npc_a.composure_current = 200
	_arm_no_fortune_prompt(screen)
	## Attacker: target 30, roll 25 -> succeeds, SL +1. Defender: target
	## 90, roll 10 -> succeeds, SL +8. Net SL = 1 - 8 = -7: without
	## Cat-tongued the party's Charm attack loses outright.
	screen._attempt_social_attack(pc, SocialCombatResolver.AttackType.CHARM, charm_def, 25, 10)
	await tree.process_frame
	checks.append(["Baseline Charm attack (no Talent) loses to the NPC's strong Initiative roll", npc_a.composure_current == 200])

	pc.talents_taken["Cat-tongued"] = 1
	npc_a.composure_current = 200
	_arm_no_fortune_prompt(screen)
	## Same exact rolls on both sides: Cat-tongued zeroes out the
	## defender's contribution entirely, so the attacker's own SL +1
	## alone decides it -- a hit lands despite the identical strong
	## defender roll that just won outright above.
	screen._attempt_social_attack(pc, SocialCombatResolver.AttackType.CHARM, charm_def, 25, 10)
	await tree.process_frame
	checks.append(["Cat-tongued makes the Charm attack fully unopposed -- the same NPC roll that won before no longer stops it", npc_a.composure_current < 200])
	pc.talents_taken.clear()

	## --- Etiquette (Social Group): a flat per-rank SL bonus, matched
	## against the target NPC's own derived group -- forced directly via
	## npc_etiquette_group_by_char, same convention
	## social_combat_conditions_test.gd already uses for
	## npc_status_ordinal_by_char, rather than needing a specific
	## encounter's own real Career data lined up for the test. -----------
	pc.characteristics.fellowship = 50
	npc_a.characteristics.initiative = 20
	npc_a.composure_current = 200
	screen.npc_etiquette_group_by_char[npc_a] = "Nobles"
	_arm_no_fortune_prompt(screen)
	## Same rolls as the Argumentative baseline above (42 vs 99) with no
	## Etiquette trained at all: 12 Composure damage.
	screen._attempt_social_attack(pc, SocialCombatResolver.AttackType.CHARM, charm_def, 42, 99)
	await tree.process_frame
	var drop_no_etiquette: int = 200 - npc_a.composure_current
	checks.append(["Baseline Charm hit against a Nobles-derived NPC, no Etiquette trained, lands the expected 12 damage", drop_no_etiquette == 12])

	pc.talents_taken["Etiquette (Nobles)"] = 1
	npc_a.composure_current = 200
	_arm_no_fortune_prompt(screen)
	screen._attempt_social_attack(pc, SocialCombatResolver.AttackType.CHARM, charm_def, 42, 99)
	await tree.process_frame
	var drop_with_matching_etiquette: int = 200 - npc_a.composure_current
	checks.append(["Etiquette (Nobles) adds its +1 SL/rank bonus against a Nobles-derived NPC (+1 extra Composure damage)", drop_with_matching_etiquette - drop_no_etiquette == 1])

	pc.talents_taken.clear()
	pc.talents_taken["Etiquette (Criminals)"] = 1   ## trained for a DIFFERENT group than this NPC's own
	npc_a.composure_current = 200
	_arm_no_fortune_prompt(screen)
	screen._attempt_social_attack(pc, SocialCombatResolver.AttackType.CHARM, charm_def, 42, 99)
	await tree.process_frame
	var drop_mismatched_etiquette: int = 200 - npc_a.composure_current
	checks.append(["Etiquette (Criminals) does NOT cross over against a Nobles-derived NPC -- same baseline 12 damage, no bonus", drop_mismatched_etiquette == drop_no_etiquette])
	pc.talents_taken.clear()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Social Combat Talents): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass

static func _arm_no_fortune_prompt(screen) -> void:
	## Forces every _offer_fortune_spend() call this test triggers to
	## collapse to its own no-choice "Continue" shortcut (see that
	## function's own comment on options.size() > 1) rather than needing
	## a real button click driven across real frames.
	screen._fortune_chain_active = true
	screen._reroll_used_this_fortune_chain = true
	screen._dark_deal_used_this_fortune_chain = true
	## Also zero the party's own banked Rapport before every single
	## attack in this file: a landed Charm hit grows it by 1 (Design Doc
	## Section 4), and its +10/point roll_bonus() feeds straight into
	## _attempt_social_attack()'s own target-number modifier -- left
	## alone, a hit from one forced-roll case here would silently shift
	## the TARGET NUMBER (not just SL) of the very next case's own
	## forced roll, breaking the clean, hand-computed deltas every check
	## below depends on.
	screen.social_combat.rapport_pool.reset()
