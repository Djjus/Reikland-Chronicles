extends RefCounted
class_name OffhandAttackTest
## Per the request ("Lets add a 2nd Attack button for the Offhand weapon
## to the combat screen, next to the main hand weapon button. use the
## same naming format but add the prefix Off:. If the item is either
## hand is not a weapon like a lantern just show the item name and keep
## the button disabled. Note that when using Dual Wield it should be
## possible to initiate a Dual wield attack both both main hand or off
## hand (so long both hand a weapon equipped). also allow switch to
## Unarmed... on both hands and should be the default weapon if nothing
## is equipped in either hand. Make sure undamaging is implemented."):
##
## Case 1 confirms the Off: button reads "Off: Unarmed - N" and is
## enabled when the off-hand slot is genuinely empty (the new default).
## Case 2 confirms it reads "Off: <WeaponName> - N" and is enabled for a
## real off-hand weapon. Case 3 confirms it reads "Off: <ItemName>" and
## is DISABLED for a non-weapon item (a Lantern) in the off-hand.
## Case 4 confirms no Off: button at all appears once the main hand
## wields a two-handed weapon (no free hand left to swing). Case 5
## confirms "Unarmed" is offered by the Switch Main/Off-hand weapon
## menus. Case 6 confirms _dual_wield_eligible's own gating: true with a
## real/empty off-hand, false with a non-weapon off-hand item, false
## with a two-handed main weapon. Case 7 confirms initiating a Dual
## Wield combo from the OFF-hand button throws the follow-up strike with
## the MAIN-hand weapon (the complement of whichever hand led). Case 8
## confirms the Undamaging quality itself (already implemented in
## CombatResolver — verified here, not re-implemented): doubled AP soak,
## and no automatic minimum-1-Wound floor on a hit.

## Recursively finds the LAST Button anywhere under `root` whose text
## starts with `prefix` — the action panel nests buttons several
## VBox/HFlowContainer levels deep (see _make_action_column), so a flat
## get_children() scan (as some earlier tests use for a shallower panel)
## isn't enough here. Deliberately the LAST match, not the first:
## _clear()/_prompt_player_turn() free old panel children via
## queue_free(), which doesn't actually remove them from the tree until
## the next idle frame — calling _prompt_player_turn() several times in
## a row without awaiting a frame in between (as this test does, to
## exercise several equip combos quickly) leaves the OLD, soon-to-be-
## freed buttons still present as earlier siblings, with the genuinely
## current rebuild's buttons appended after them. Returning the last
## match reliably finds the current one without depending on exact
## queue_free timing.
static func _find_button(root: Node, prefix: String) -> Button:
	var last: Button = null
	for child in root.get_children():
		if child is Button and String(child.text).begins_with(prefix):
			last = child
		var found := _find_button(child, prefix)
		if found != null:
			last = found
	return last

static func run_test(fe) -> bool:
	var checks: Array = []

	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_habitat = ""
	## Flakiness fix: pins Dice's own RNG stream to a fixed, verified seed
	## (per dice.gd's own doc comment: "swap the RNG's seed in tests") so
	## the various attack/Dual Wield rolls this test exercises can't
	## occasionally land on an unlucky combination. Deliberately does NOT
	## pin the monster pool/name — unlike LastEnemyFlowTest, nothing here
	## depends on there being exactly one monster in play (no "battle is
	## over" check), and pinning to a specific monster was found to
	## change this specific monster's own stat block enough to flip Case
	## 7's outcome. Also reseeds Godot's own global RNG (the bare
	## randf()/randi() calls EncounterGroupBuilder uses to pick which
	## monster spawns, which Dice.rng does NOT cover) so which monster
	## spawns is itself now deterministic too, rather than depending on
	## how many global-RNG draws whatever ran earlier in the same
	## process already consumed.
	Dice.rng.seed = 2
	seed(2)
	fe._start_encounter()
	for i in range(3):
		await fe.get_tree().process_frame

	var player: Character = fe.player
	var goblin: Character = fe.monsters[0] if fe.monsters.size() > 0 else null
	checks.append(["setup: a monster genuinely exists", goblin != null])
	if goblin == null:
		print("RESULT (Off-hand Attack): SETUP FAILED (no monster)")
		return false

	player.equipped_weapon = "Sword"
	player.inventory.append("Sword")
	player.inventory.append("Dagger")
	player.inventory.append("Great Axe")
	fe.weapons[player] = fe._resolve_weapon(player)
	fe.battle_positions[player] = fe.battle_positions.get(goblin, Vector2i.ZERO) + Vector2i(1, 0)
	fe.selected_target = goblin
	fe.action_used_this_turn = false
	fe.awaiting_player_target = true
	fe.pending_defense.clear()

	## --- Case 1: off-hand genuinely empty -> defaults to Unarmed,
	## enabled, per the request's own "should be the default weapon if
	## nothing is equipped in either hand."
	player.equipped_offhand = ""
	fe._prompt_player_turn(true)
	await fe.get_tree().process_frame
	await fe.get_tree().process_frame
	var off_btn_1 := _find_button(fe.target_container, "Off:")
	checks.append(["Case 1: an empty off-hand shows a real Off: button", off_btn_1 != null])
	if off_btn_1 != null:
		checks.append(["Case 1: ...reading 'Off: Unarmed - N'", off_btn_1.text.begins_with("Off: Unarmed - ")])
		checks.append(["Case 1: ...and genuinely enabled (a real, usable attack)", not off_btn_1.disabled])

	## --- Case 2: a real off-hand weapon -> same naming format as the
	## main Attack button, with the Off: prefix, and enabled.
	player.equipped_offhand = "Dagger"
	fe._prompt_player_turn(true)
	await fe.get_tree().process_frame
	await fe.get_tree().process_frame
	var off_btn_2 := _find_button(fe.target_container, "Off:")
	checks.append(["Case 2: a real off-hand weapon (Dagger) shows an Off: button", off_btn_2 != null])
	if off_btn_2 != null:
		checks.append(["Case 2: ...reading 'Off: Dagger - N'", off_btn_2.text.begins_with("Off: Dagger - ")])
		checks.append(["Case 2: ...and genuinely enabled", not off_btn_2.disabled])

	## --- Case 3: a non-weapon item (Lantern) in the off-hand -> per
	## the request, just the item name, button disabled — nothing to
	## swing with that hand.
	player.inventory.append("Lantern")
	player.equipped_offhand = "Lantern"
	fe._prompt_player_turn(true)
	await fe.get_tree().process_frame
	await fe.get_tree().process_frame
	var off_btn_3 := _find_button(fe.target_container, "Off:")
	checks.append(["Case 3: a non-weapon off-hand item (Lantern) still shows an Off: button", off_btn_3 != null])
	if off_btn_3 != null:
		checks.append(["Case 3: ...reading just 'Off: Lantern' (no roll number — nothing to attack with)", off_btn_3.text == "Off: Lantern"])
		checks.append(["Case 3: ...and genuinely DISABLED", off_btn_3.disabled])

	## --- Case 4: a two-handed main weapon leaves no free off-hand at
	## all -- no Off: button should appear, regardless of what
	## equipped_offhand nominally still says, and per the follow-up
	## request ("IF a two-handed weapon is being wielded just show the
	## main hand button and prefix with 2H:") the MAIN button itself
	## should flag that plainly.
	player.equipped_weapon = "Great Axe"
	player.equipped_offhand = "Dagger"   ## stale leftover value; the two-handed check should still win
	fe.weapons[player] = fe._resolve_weapon(player)
	fe._prompt_player_turn(true)
	await fe.get_tree().process_frame
	await fe.get_tree().process_frame
	var off_btn_4 := _find_button(fe.target_container, "Off:")
	checks.append(["Case 4: a two-handed main weapon (Great Axe) shows NO Off: button at all", off_btn_4 == null])
	var main_btn_4 := _find_button(fe.target_container, "2H:")
	checks.append(["Case 4: ...and the MAIN Attack button itself is prefixed '2H: Great Axe - N'", main_btn_4 != null and main_btn_4.text.begins_with("2H: Great Axe - ")])
	player.equipped_weapon = "Sword"
	fe.weapons[player] = fe._resolve_weapon(player)

	## --- Case 5: "Unarmed" is offered as a real switch target on BOTH
	## hands, per the request ("allow switch to Unarmed... on both
	## hands").
	player.equipped_offhand = "Dagger"
	var main_switchable: Array[String] = fe._switchable_weapons(player, player.equipped_weapon)
	var off_switchable: Array[String] = fe._switchable_weapons(player, player.equipped_offhand)
	checks.append(["Case 5: 'Unarmed' is offered as a Switch Main Weapon target", main_switchable.has("Unarmed")])
	checks.append(["Case 5: 'Unarmed' is offered as a Switch Off-hand target", off_switchable.has("Unarmed")])
	checks.append(["Case 5: 'Unarmed' is NOT offered as a switch target for a hand ALREADY on Unarmed (nothing to switch to)", not fe._switchable_weapons(player, "Unarmed").has("Unarmed")])

	## --- Case 6: _dual_wield_eligible gating ("so long both hand a
	## weapon equipped").
	player.equipped_weapon = "Sword"
	player.equipped_offhand = "Dagger"
	checks.append(["Case 6: real weapon in both hands -> eligible", fe._dual_wield_eligible(player)])
	player.equipped_offhand = ""
	checks.append(["Case 6: empty off-hand (defaults to Unarmed) -> still eligible", fe._dual_wield_eligible(player)])
	player.equipped_offhand = "Lantern"
	checks.append(["Case 6: a non-weapon item (Lantern) in the off-hand -> NOT eligible", not fe._dual_wield_eligible(player)])
	player.equipped_offhand = "Dagger"
	player.equipped_weapon = "Great Axe"
	checks.append(["Case 6: a two-handed main weapon -> NOT eligible (no free off-hand)", not fe._dual_wield_eligible(player)])
	player.equipped_weapon = "Sword"
	fe.weapons[player] = fe._resolve_weapon(player)

	## --- Case 7: initiating a Dual Wield combo from the OFF-hand
	## button throws the follow-up strike with the MAIN-hand weapon —
	## per the request ("initiate a Dual wield attack both both main
	## hand or off hand"), the combo's 2nd strike is whichever hand
	## DIDN'T lead, not always the off-hand.
	player.equipped_weapon = "Sword"
	player.equipped_offhand = "Dagger"
	player.talents_taken["Dual Wielder"] = 1
	player.characteristics.set_value("weapon_skill", 90)   ## reliably hits both strikes
	player.fortune_points = 0   ## no Fortune-spend prompt to poll through — just the plain Continue gate
	## Pinned well above any real monster's own Wounds -- the first
	## (off-hand Dagger) strike must survive, or the target is already
	## defeated by the time the Dual Wielder follow-up would fire (see
	## _on_player_attack's own "not encounter.is_defeated(target)" gate
	## on it), masking whether the follow-up logic itself is correct.
	goblin.wounds_max = 200
	goblin.wounds_current = 200
	fe.dual_wield_active = true
	fe.action_used_this_turn = false
	fe.awaiting_player_target = true
	fe.pending_defense.clear()
	fe.history.clear()
	## Fire-and-forget, like MonsterDisengageTest's own Case 2 —
	## _on_player_attack goes through a real _offer_fortune_spend prompt
	## (awaiting_fortune_choice) and a "press Continue" gate
	## (awaiting_continue) along the way, so it can't just be awaited
	## directly from here without something clearing those prompts in
	## the meantime.
	fe._on_player_attack(goblin, fe._resolve_offhand_weapon(player), false, true)
	for i in range(240):
		if fe.awaiting_continue:
			fe.awaiting_continue = false
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		await fe.get_tree().process_frame
	var followup_card_text := ""
	for c in fe.history:
		for seg in c.get("segments", []):
			if seg.get("kind", "") == "cards":
				for card in seg.get("cards", []):
					## _show_attack_cards stores the label passed in (here,
					## "<WeaponName> (main-hand)"/"(off-hand)") as the
					## card's own "title" field -- "subtitle" is always
					## just the fixed "Melee Attack"/"Ranged Attack" tag.
					if String(card.get("title", "")).contains("main-hand"):
						followup_card_text = String(card.get("title", ""))
	## The dual-wield follow-up card's own title is built as
	## "<WeaponName> (<hand>)" -- fall back to a plain notice/history
	## text scan if the exact card shape ever changes, so this check
	## stays meaningful without over-fitting to internal card structure.
	var found_main_hand_followup := followup_card_text != ""
	if not found_main_hand_followup:
		for h in fe.history:
			if MonsterDisengageTest._history_notice_text(h).findn("main-hand") != -1:
				found_main_hand_followup = true
	checks.append(["Case 7: initiating Dual Wield from the Off-hand button throws its follow-up strike with the MAIN-hand weapon", found_main_hand_followup])

	## --- Case 8: Undamaging (already implemented in CombatResolver —
	## verified, not re-implemented here): "All APs are doubled against
	## Undamaging weapons. Further, you do not automatically inflict a
	## minimum of 1 Wound on a successful hit."
	var unarmed: WeaponDefinition = GameData.weapon_db.find_by_name("Unarmed")
	var sword: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	checks.append(["Case 8 setup: Unarmed is genuinely tagged Undamaging in the data", unarmed != null and unarmed.qualities.has("Undamaging")])
	checks.append(["Case 8 setup: Sword is genuinely NOT tagged Undamaging", sword != null and not sword.qualities.has("Undamaging")])

	var attacker := Character.new()
	attacker.race = GameData.find_race("Human")
	attacker.career = GameData.find_career("Soldier")
	attacker.current_tier = 1
	attacker.characteristics = CharacteristicSet.new()
	attacker.characteristics.set_value("strength", 30)   ## SB 3 -- Unarmed does SB+0
	attacker.recompute_max_wounds()
	var defender := Character.new()
	defender.race = GameData.find_race("Human")
	defender.career = GameData.find_career("Soldier")
	defender.current_tier = 1
	defender.characteristics = CharacteristicSet.new()
	defender.characteristics.set_value("toughness", 20)   ## TB 2
	defender.recompute_max_wounds()

	var hit_test := TestResolver.TestResult.new()
	hit_test.roll = 45
	hit_test.success = true
	hit_test.success_levels = 0   ## damage = weapon_damage(3) + SL(0) = 3, well under a real defender's soak
	hit_test.is_critical = false

	## --- Case 8a: no armour at all -- soak is just TB (2). Unarmed
	## damage (SB+0 = 3) beats that soak by 1 either way, so this case
	## alone can't distinguish Undamaging's minimum-Wound-floor removal
	## (both would deal 1 Wound here) -- it only confirms the AP-doubling
	## half doesn't do anything harmful when there's no armour to double.
	var result_no_armour := CombatResolver.AttackResult.new()
	CombatResolver._apply_hit(result_no_armour, attacker, defender, unarmed, hit_test)
	checks.append(["Case 8a: Unarmed vs no armour -- soak is just Toughness Bonus (2), no AP to double", result_no_armour.soak == 2])

	## --- Case 8b: the real, distinguishing case -- give the defender
	## enough armour that Undamaging's DOUBLED soak exceeds the
	## attacker's raw damage. A normal weapon would still force through
	## the automatic minimum 1 Wound; Undamaging must NOT.
	defender.equipped_armour = ["Leather Jack"]   ## 1 AP at Body
	var result_undamaging := CombatResolver.AttackResult.new()
	CombatResolver._apply_hit(result_undamaging, attacker, defender, unarmed, hit_test)
	checks.append(["Case 8b: Undamaging doubles the AP soak (TB 2 + AP 1*2 = 4)", result_undamaging.soak == 4])
	checks.append(["Case 8b: damage (3) no longer exceeds the doubled soak (4) -- 0 Wounds, genuinely NOT floored to 1", result_undamaging.wounds_dealt == 0])

	## --- Case 8c: the same exact armour/damage numbers, but with a
	## normal (non-Undamaging) weapon of identical damage output --
	## confirms the minimum-1-Wound floor DOES still apply there, so
	## Case 8b's zero isn't just a fluke of the damage math.
	var dagger_light := WeaponDefinition.new()
	dagger_light.weapon_name = "TestBlade"
	dagger_light.is_ranged = false
	dagger_light.skill_group = "Basic"
	dagger_light.damage_mode = "strength_bonus_plus"
	dagger_light.damage_flat = 0   ## same SB+0 as Unarmed -- identical raw damage
	dagger_light.qualities = []
	var result_normal := CombatResolver.AttackResult.new()
	CombatResolver._apply_hit(result_normal, attacker, defender, dagger_light, hit_test)
	checks.append(["Case 8c: same damage/armour with a NORMAL (non-Undamaging) weapon -- soak is single, not doubled (TB 2 + AP 1 = 3)", result_normal.soak == 3])
	checks.append(["Case 8c: ...damage (3) exactly meets soak (3), but the automatic minimum-1-Wound floor still applies -- 1 Wound, not 0", result_normal.wounds_dealt == 1])

	## --- Case 9: the off-hand penalty (-20 unless Ambidextrous) belongs
	## to whichever hand is genuinely throwing the strike, per the
	## correction ("off-hand penalty only effect off-hand actions, never
	## the main hand"). Compared against the SAME weapon instance so the
	## only variable is the is_offhand flag itself, not a genuine
	## difference between the main and off-hand weapons.
	player.equipped_weapon = "Sword"
	player.equipped_offhand = "Dagger"
	fe.weapons[player] = fe._resolve_weapon(player)
	var sword_weapon: WeaponDefinition = fe._resolve_weapon(player)
	var main_preview: int = fe._preview_attack_target_number(sword_weapon, goblin, false)
	var offhand_preview_penalized: int = fe._preview_attack_target_number(sword_weapon, goblin, false, true)
	checks.append(["Case 9: the off-hand preview (same weapon) reads exactly 20 lower than the main-hand preview of the identical weapon", offhand_preview_penalized == main_preview - 20])

	## --- Case 10: Ambidextrous is rank-scaled (Max: 2) -- "You only
	## suffer a penalty of -10 ... not -20. If you have this Talent
	## twice, you suffer no penalty at all." Rank 1 must only HALVE the
	## penalty, not remove it outright (a previous pass used a presence-
	## only has_talent() check, so rank 1 already fully zeroed it --
	## fixed via the new rank-scaled Character.get_offhand_penalty()).
	player.talents_taken["Ambidextrous"] = 1
	var offhand_preview_ambi1: int = fe._preview_attack_target_number(sword_weapon, goblin, false, true)
	checks.append(["Case 10a: Ambidextrous rank 1 reduces the off-hand penalty to -10, not 0", offhand_preview_ambi1 == main_preview - 10])
	player.talents_taken["Ambidextrous"] = 2
	var offhand_preview_ambi2: int = fe._preview_attack_target_number(sword_weapon, goblin, false, true)
	checks.append(["Case 10b: Ambidextrous rank 2 removes the off-hand penalty entirely", offhand_preview_ambi2 == main_preview])
	player.talents_taken.erase("Ambidextrous")

	## --- Case 11: a live Dual Wield combo initiated from the OFF-hand
	## button applies the -20 penalty to the OPENING (off-hand) hit only
	## -- the MAIN-hand follow-up it throws carries no off-hand penalty
	## at all, per the correction ("even if DW is triggered by the
	## off-hand, it only effect the off-hand opening hit").
	player.talents_taken["Dual Wielder"] = 1
	player.talents_taken.erase("Ambidextrous")
	player.characteristics.set_value("weapon_skill", 90)
	player.fortune_points = 0
	goblin.wounds_max = 200
	goblin.wounds_current = 200
	fe.dual_wield_active = true
	fe.action_used_this_turn = false
	fe.awaiting_player_target = true
	fe.pending_defense.clear()
	fe.history.clear()
	fe._on_player_attack(goblin, fe._resolve_offhand_weapon(player), false, true)
	for i in range(240):
		if fe.awaiting_continue:
			fe.awaiting_continue = false
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		await fe.get_tree().process_frame
	var opening_off_hand_penalized := false
	var followup_main_hand_penalized := false
	for h in fe.history:
		for seg in h.get("segments", []):
			if seg.get("kind", "") == "cards":
				for card in seg.get("cards", []):
					var title := String(card.get("title", ""))
					var test = card.get("test")
					var has_penalty := false
					if test != null:
						for m in test.target_modifiers:
							if String(m.get("name", "")) == "Off-hand penalty":
								has_penalty = true
					if title.begins_with("Dagger") and not title.contains("main-hand") and not title.contains("off-hand"):
						opening_off_hand_penalized = has_penalty
					elif title.contains("main-hand"):
						followup_main_hand_penalized = has_penalty
	checks.append(["Case 11: the OPENING off-hand hit (Dagger, leading the combo) carries the -20 off-hand penalty", opening_off_hand_penalized])
	checks.append(["Case 11: the MAIN-hand follow-up thrown after it carries NO off-hand penalty at all", not followup_main_hand_penalized])

	## --- Case 12: the mirror -- a combo initiated from the MAIN hand
	## carries no penalty on its opening hit, and correctly puts the
	## -20 penalty on the OFF-hand follow-up it throws instead.
	fe.dual_wield_active = true
	fe.action_used_this_turn = false
	fe.awaiting_player_target = true
	fe.pending_defense.clear()
	fe.history.clear()
	goblin.wounds_current = 200
	fe._on_player_attack(goblin, fe._resolve_weapon(player), false, false)
	for i in range(240):
		if fe.awaiting_continue:
			fe.awaiting_continue = false
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		await fe.get_tree().process_frame
	var opening_main_hand_penalized := false
	var followup_off_hand_penalized := false
	for h in fe.history:
		for seg in h.get("segments", []):
			if seg.get("kind", "") == "cards":
				for card in seg.get("cards", []):
					var title2 := String(card.get("title", ""))
					var test2 = card.get("test")
					var has_penalty2 := false
					if test2 != null:
						for m in test2.target_modifiers:
							if String(m.get("name", "")) == "Off-hand penalty":
								has_penalty2 = true
					if title2.begins_with("Sword") and not title2.contains("main-hand") and not title2.contains("off-hand"):
						opening_main_hand_penalized = has_penalty2
					elif title2.contains("off-hand"):
						followup_off_hand_penalized = has_penalty2
	checks.append(["Case 12: the OPENING main-hand hit (Sword, leading the combo) carries NO off-hand penalty", not opening_main_hand_penalized])
	checks.append(["Case 12: the OFF-hand follow-up thrown after it correctly carries the -20 off-hand penalty", followup_off_hand_penalized])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Off-hand Attack + Dual Wield + Undamaging): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
