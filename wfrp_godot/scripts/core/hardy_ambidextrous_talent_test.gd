extends RefCounted
class_name HardyAmbidextrousTalentTest
## Regression coverage for the request ("implement Hardy, Accurate Shot
## and Ambidextrous"). Accurate Shot needed no changes (already correct
## -- see combat_resolver.gd's Accurate Shot damage bonus, exercised
## elsewhere) so it isn't re-tested here.
##
## Hardy (Max: Toughness Bonus): "a permanent addition to your Wounds,
## equal to your Toughness Bonus [per rank]. If your Toughness Bonus
## should increase, then the number of Wounds Hardy provides also
## increases." Cases 1-4 cover Character.recompute_max_wounds()'s new
## hardy_bonus term directly, plus that a Characteristic Advance which
## raises Toughness Bonus correctly re-scales it. Cases 5-6 cover the
## real production entry points -- Advancement.purchase_talent_advance()
## / sell_talent_advance() -- since a previous state had Wounds only
## ever recomputed on a Characteristic Advance, never on the Talent
## purchase/sell itself.
##
## Ambidextrous (Max: 2): "-10 ... not -20. If you have this Talent
## twice, you suffer no penalty at all." Case 7 exercises the new
## centralised Character.get_offhand_penalty() helper directly at all
## three ranks. Case 8 exercises CombatResolver.get_defense_modifiers()
## (the off-hand Parry defense penalty) at all three ranks. Case 9
## exercises the off-hand Parry button's own note text (built in
## field_encounter_screen.gd's _prompt_player_defense) at all three
## ranks, confirming the displayed number always matches what
## get_defense_modifiers() will actually apply.

static func run_test(fe) -> bool:
	var checks: Array = []

	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_habitat = ""
	fe._start_encounter()
	for i in range(3):
		await fe.get_tree().process_frame

	var player: Character = fe.player
	var goblin: Character = fe.monsters[0] if fe.monsters.size() > 0 else null
	checks.append(["setup: a monster genuinely exists", goblin != null])
	if goblin == null:
		print("RESULT (Hardy/Ambidextrous): SETUP FAILED (no monster)")
		return false

	## --- Case 1: baseline Wounds with no Hardy, for comparison.
	player.talents_taken.erase("Hardy")
	player.characteristics.set_value("toughness", 30)   ## TB 3
	player.recompute_max_wounds()
	var base_wounds := player.wounds_max

	## --- Case 2: Hardy rank 1 adds exactly TB (3) Wounds.
	player.talents_taken["Hardy"] = 1
	player.recompute_max_wounds()
	checks.append(["Case 2: Hardy rank 1 adds exactly the character's Toughness Bonus (3) to max Wounds", player.wounds_max == base_wounds + 3])

	## --- Case 3: Hardy rank 2 adds 2x TB (6), not just another flat amount.
	player.talents_taken["Hardy"] = 2
	player.recompute_max_wounds()
	checks.append(["Case 3: Hardy rank 2 adds 2x Toughness Bonus (6) to max Wounds", player.wounds_max == base_wounds + 6])

	## --- Case 4: "If your Toughness Bonus should increase, then the
	## number of Wounds Hardy provides also increases" -- raise TB to 4
	## with Hardy still at rank 2 and confirm the bonus rescales to 8,
	## not staying frozen at the old TB's 6.
	player.characteristics.set_value("toughness", 40)   ## TB 4
	player.recompute_max_wounds()
	var base_wounds_tb4 := player.get_characteristic_bonus("strength") + (4 * 2) + player.get_characteristic_bonus("willpower") + (player.race.starting_extra_wounds if player.race else 0)
	checks.append(["Case 4: raising Toughness Bonus (3->4) rescales Hardy's own bonus too (2 * 4 = 8, not stuck at the old 6)", player.wounds_max == base_wounds_tb4 + 8])
	player.talents_taken.erase("Hardy")
	player.recompute_max_wounds()

	## --- Case 5: the real production entry point -- purchasing a rank
	## of Hardy via Advancement.purchase_talent_advance() must itself
	## trigger the Wounds recompute (previously ONLY a Characteristic
	## Advance did this, so taking Hardy did nothing to Wounds until some
	## unrelated later Toughness change happened to trigger it).
	## Ensure Hardy is genuinely unlocked at the character's current
	## Career level (purchase_talent_advance requires this), rather than
	## assuming the default test character's career happens to grant it.
	if player.career:
		var current_level: CareerLevel = player.career.get_level(player.current_tier)
		if current_level and not current_level.talents.has("Hardy"):
			current_level.talents.append("Hardy")
	player.experience_total = 999
	player.experience_spent = 0
	var wounds_before_purchase := player.wounds_max
	var purchase_result = Advancement.purchase_talent_advance(player, "Hardy")
	checks.append(["Case 5: purchase_talent_advance succeeded", purchase_result.success])
	checks.append(["Case 5: purchasing Hardy rank 1 immediately raises max Wounds by the current Toughness Bonus (4), with no unrelated trigger needed", player.wounds_max == wounds_before_purchase + 4])

	## --- Case 6: selling that same rank back via
	## Advancement.sell_talent_advance() immediately drops Wounds back
	## down again.
	var sell_result = Advancement.sell_talent_advance(player, "Hardy")
	checks.append(["Case 6: sell_talent_advance succeeded", sell_result.success])
	checks.append(["Case 6: selling Hardy's only rank immediately drops max Wounds back to the pre-purchase value", player.wounds_max == wounds_before_purchase])

	## --- Case 7: Character.get_offhand_penalty() itself, all 3 ranks.
	player.talents_taken.erase("Ambidextrous")
	checks.append(["Case 7a: rank 0 (no Ambidextrous) -> -20", player.get_offhand_penalty() == -20])
	player.talents_taken["Ambidextrous"] = 1
	checks.append(["Case 7b: rank 1 -> -10 (halved, not removed)", player.get_offhand_penalty() == -10])
	player.talents_taken["Ambidextrous"] = 2
	checks.append(["Case 7c: rank 2 -> 0 (no penalty at all)", player.get_offhand_penalty() == 0])
	player.talents_taken.erase("Ambidextrous")

	## --- Case 8: CombatResolver.get_defense_modifiers() -- the off-hand
	## Parry defense penalty -- at all 3 ranks. Uses a plain one-handed,
	## non-Defensive weapon so the only variable is the talent rank.
	var plain_offhand := WeaponDefinition.new()
	plain_offhand.weapon_name = "TestOffhandBlade"
	plain_offhand.is_ranged = false
	plain_offhand.skill_group = "Basic"
	plain_offhand.qualities = []

	player.talents_taken.erase("Ambidextrous")
	var mods_rank0: Dictionary = CombatResolver.get_defense_modifiers(player, plain_offhand, true)
	var penalty_rank0 := 0
	for entry in mods_rank0["target_breakdown"]:
		if entry["name"] == "Off-hand penalty":
			penalty_rank0 = entry["amount"]
	checks.append(["Case 8a: get_defense_modifiers rank 0 -> off-hand Parry penalty -20", penalty_rank0 == -20])

	player.talents_taken["Ambidextrous"] = 1
	var mods_rank1: Dictionary = CombatResolver.get_defense_modifiers(player, plain_offhand, true)
	var penalty_rank1 := 0
	for entry in mods_rank1["target_breakdown"]:
		if entry["name"] == "Off-hand penalty":
			penalty_rank1 = entry["amount"]
	checks.append(["Case 8b: get_defense_modifiers rank 1 -> off-hand Parry penalty -10", penalty_rank1 == -10])

	player.talents_taken["Ambidextrous"] = 2
	var mods_rank2: Dictionary = CombatResolver.get_defense_modifiers(player, plain_offhand, true)
	var has_penalty_rank2 := false
	for entry in mods_rank2["target_breakdown"]:
		if entry["name"] == "Off-hand penalty":
			has_penalty_rank2 = true
	checks.append(["Case 8c: get_defense_modifiers rank 2 -> no off-hand penalty entry at all", not has_penalty_rank2])
	player.talents_taken.erase("Ambidextrous")

	## --- Case 9: the off-hand Parry button's own note text (built by
	## _prompt_player_defense in field_encounter_screen.gd) matches the
	## same rank-scaled numbers, at all 3 ranks -- confirms the UI never
	## lies about what get_defense_modifiers() will actually apply.
	player.equipped_weapon = "Sword"
	player.equipped_offhand = "Dagger"
	player.inventory.append("Sword")
	player.inventory.append("Dagger")
	fe.weapons[player] = fe._resolve_weapon(player)
	fe.battle_positions[player] = fe.battle_positions.get(goblin, Vector2i.ZERO) + Vector2i(1, 0)
	var attacker_weapon: WeaponDefinition = fe._resolve_weapon(goblin) if fe.weapons.has(goblin) else fe._resolve_weapon(player)

	## Per the follow-up request ("move detail to tooltip_text"): the
	## off-hand Parry button's own text shortened to "Off-hand: <weapon>
	## - <target number>" (no more "Parry with off-hand:" prefix, no
	## penalty text baked in) -- the rank-scaled note itself moved to
	## tooltip_text, and dropped its parentheses along the way ("-20
	## off-hand penalty", not "(-20 off-hand penalty)"). Looks up the
	## button by its new "Off-hand:" prefix and checks tooltip_text
	## instead of .text for the penalty note.
	player.talents_taken.erase("Ambidextrous")
	fe._prompt_player_defense(goblin, attacker_weapon, 0)
	await fe.get_tree().process_frame
	await fe.get_tree().process_frame
	var offhand_parry_btn_0 := HardyAmbidextrousTalentTest._find_button(fe.target_container, "Off-hand:")
	checks.append(["Case 9a: rank 0 off-hand Parry button's tooltip shows the -20 note", offhand_parry_btn_0 != null and offhand_parry_btn_0.tooltip_text.contains("-20 off-hand penalty")])

	player.talents_taken["Ambidextrous"] = 1
	fe._prompt_player_defense(goblin, attacker_weapon, 0)
	await fe.get_tree().process_frame
	await fe.get_tree().process_frame
	var offhand_parry_btn_1 := HardyAmbidextrousTalentTest._find_button(fe.target_container, "Off-hand:")
	checks.append(["Case 9b: rank 1 off-hand Parry button's tooltip shows the -10 note, not -20", offhand_parry_btn_1 != null and offhand_parry_btn_1.tooltip_text.contains("-10 off-hand penalty")])

	player.talents_taken["Ambidextrous"] = 2
	fe._prompt_player_defense(goblin, attacker_weapon, 0)
	await fe.get_tree().process_frame
	await fe.get_tree().process_frame
	var offhand_parry_btn_2 := HardyAmbidextrousTalentTest._find_button(fe.target_container, "Off-hand:")
	checks.append(["Case 9c: rank 2 off-hand Parry button's tooltip shows no penalty note at all", offhand_parry_btn_2 != null and not offhand_parry_btn_2.tooltip_text.contains("off-hand penalty")])
	player.talents_taken.erase("Ambidextrous")

	var all_passed := true
	for c in checks:
		var label: String = c[0]
		var passed: bool = c[1]
		if not passed:
			all_passed = false
		print("  [%s] %s" % ["PASS" if passed else "FAIL", label])
	print("RESULT (Hardy/Ambidextrous): %s (%d/%d checks)" % ["PASS" if all_passed else "FAIL", checks.filter(func(c): return c[1]).size(), checks.size()])
	return all_passed

## Recursively finds the LAST Button anywhere under `root` whose text
## contains `substr` -- see OffhandAttackTest._find_button's own comment
## for why LAST (queue_free() deferral across repeated rebuilds).
static func _find_button(root: Node, substr: String) -> Button:
	var last: Button = null
	for child in root.get_children():
		if child is Button and String(child.text).contains(substr):
			last = child
		var found := HardyAmbidextrousTalentTest._find_button(child, substr)
		if found != null:
			last = found
	return last
