extends RefCounted
class_name CombatRerollTest
## Per the bug report (screenshots showing a Sword Melee Attack vs a
## Defence Opposed Test): "it should only have rerolled the Eric's
## attack, it should not have rerolled the Defence of Outlaw 3 as
## well. So Reroll only effect your own rolls, not the opposing roll."
## Spending a Fortune Point to reroll your OWN roll (attacker's attack,
## or — symmetrically — defender's own Defence) was silently ALSO
## re-rolling the OTHER side's already-rolled number, since both
## do_attack (the player's own attack) and do_defense (the player's
## own defence against a monster) closures in field_encounter_screen.gd
## hardcoded the non-rerolling side's forced-roll parameter to -1 (i.e.
## "roll fresh") on every call, including a redo. Confirms both
## directions now hold the other side's original roll fixed across a
## reroll, through the real _on_player_attack()/_resolve_player_defense()
## flow — not just calling CombatResolver directly, which wouldn't
## exercise the actual bug (the screen's own wiring). Each direction
## gets its own fresh FieldEncounter instance, so there's no risk of
## one still-in-flight action coroutine interfering with the other.
##
## Also confirms the related ordering fix ("move the green spent
## fortune to reroll text in the combat log to before the actual
## rerolled test, not after it"): the "spends a Fortune Point to
## reroll" notice now renders as its own segment BEFORE the rerolled
## cards' own segment within the same merged combat-log entry, instead
## of the cards always rendering above the notice regardless of which
## was actually logged first.

static func _find_card(cards: Array, title: String) -> Dictionary:
	for c in cards:
		if c.get("title", "") == title:
			return c
	return {}

## First card in `cards` that ISN'T titled "Defence" — used to find the
## attacker's own card in an opposed pair without needing to know its
## exact weapon-name title.
static func _find_non_defence_card(cards: Array) -> Dictionary:
	for c in cards:
		if c.get("title", "") != "Defence":
			return c
	return {}

static func _spin_up_encounter(tree: SceneTree, checks: Array) -> Dictionary:
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "RerollTester"
	pc.inventory.clear()
	pc.inventory.append("Sword")
	pc.equipped_weapon = "Sword"
	pc.characteristics.set_value("weapon_skill", 1)
	pc.characteristics.set_value("agility", 1)
	pc.fortune_points = 10

	GameState.pending_encounter_monster_names = ["Giant Rat"]
	if GameData.monster_db.find_by_name("Giant Rat") == null:
		var any_monster: MonsterDefinition = GameData.monster_db.entries[0] if GameData.monster_db.entries.size() > 0 else null
		if any_monster != null:
			GameState.pending_encounter_monster_names = [any_monster.monster_name]

	var scene: PackedScene = load("res://scenes/FieldEncounter.tscn")
	var fe: Node = scene.instantiate()
	tree.get_root().add_child.call_deferred(fe)
	await tree.process_frame
	await tree.process_frame

	checks.append(["FieldEncounter loaded with at least one monster in play", fe.monster_defs.size() > 0])
	var monster: Character = fe.monster_defs.keys()[0] if not fe.monster_defs.is_empty() else null
	if monster != null:
		## High enough that the monster's own roll is very likely to
		## succeed (its own number needs to genuinely survive a reroll of
		## the OTHER side's roll unchanged — a high target makes "it
		## happened to already be a fail" an unlikely confound).
		monster.characteristics.set_value("weapon_skill", 80)
		monster.characteristics.set_value("agility", 80)
		## Melee requires actual grid adjacency (see _on_player_attack's
		## own distance check) — the standard opening formation starts
		## both sides at opposite ends of the map, "neither side has
		## closed to melee yet," so this puts the monster right next to
		## the player before either a melee attack or a melee defense
		## roll is exercised below.
		if fe.battle_positions.has(pc):
			fe.battle_positions[monster] = fe.battle_positions[pc] + Vector2i(1, 0)
	return {"pc": pc, "fe": fe, "monster": monster}

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## Flakiness fix: this test relies on the player's crippled WS/Agility
	## 1 attack/defence tests reliably FAILING (so a Fortune-reroll prompt
	## is actually offered to test) and, separately, on the reroll's own
	## fresh number happening to land on a value distinguishable from
	## what came before — both are merely VERY likely, not guaranteed, at
	## WS/Agility 1, and every few dozen runs the unlucky 1-in-~20 tail
	## (a genuine success against a target of ~5%, or a reroll that lands
	## in a way that trips up the ordering check) would show up as a
	## false failure. Pinning Dice's own RNG stream to a fixed, verified
	## seed (per dice.gd's own doc comment: "swap the RNG's seed in
	## tests") makes the whole sequence — attack roll, reroll, monster's
	## defence roll and so on — fully deterministic instead. Also
	## reseeds Godot's own global RNG (the bare randf()/randi() calls
	## EncounterGroupBuilder/field_encounter_screen.gd use for things
	## like monster-group size and lantern chance, which Dice.rng does
	## NOT cover) — otherwise those stay dependent on however many
	## global-RNG draws whatever ran earlier in the same process already
	## consumed, silently reintroducing run-order-dependent flakiness.
	Dice.rng.seed = 2
	seed(2)

	## --- Part 1: rerolling the PLAYER's own Attack must not touch the
	## MONSTER's already-rolled Defence number. ---------------------------
	var setup1 := await _spin_up_encounter(tree, checks)
	var fe1: Node = setup1["fe"]
	var monster1: Character = setup1["monster"]

	fe1.awaiting_player_target = true
	fe1.selected_target = monster1
	fe1._on_player_attack(monster1)
	var waited := 0
	while not fe1.awaiting_fortune_choice and waited < 90:
		await tree.process_frame
		waited += 1
	checks.append(["Part 1: a Fortune-spend prompt is genuinely offered after the crippled Weapon Skill fails the attack", fe1.awaiting_fortune_choice])

	var entry_before: Dictionary = fe1.history[0] if not fe1.history.is_empty() else {}
	var cards_before: Array = []
	for seg in entry_before.get("segments", []):
		if seg.get("kind", "") == "cards":
			cards_before = seg.get("cards", [])
	var defence_before := _find_card(cards_before, "Defence")
	checks.append(["Part 1: the initial Defence card/roll genuinely exists to compare against", not defence_before.is_empty()])
	var defender_roll_before: int = defence_before.get("test").roll if not defence_before.is_empty() else -999

	if fe1.awaiting_fortune_choice:
		fe1._pending_choice_str = "reroll"
		fe1.awaiting_fortune_choice = false
		waited = 0
		while not fe1.awaiting_fortune_choice and waited < 90:
			await tree.process_frame
			waited += 1
		## A second prompt may follow the reroll (another failed attack) —
		## decline it (plain Continue) so the Action finishes cleanly either way.
		if fe1.awaiting_fortune_choice:
			fe1._pending_choice_str = ""
			fe1.awaiting_fortune_choice = false
		for i in range(10):
			await tree.process_frame

	var entry_after: Dictionary = fe1.history[0] if not fe1.history.is_empty() else {}
	var segments_after: Array = entry_after.get("segments", [])
	checks.append(["Part 1: the reroll's cards were merged into the SAME entry as the 'spends a Fortune Point' notice (still one connected block in the log)", segments_after.size() >= 2])
	## Ordering fix: the notice segment (Fortune spent) must come BEFORE
	## the cards segment (the rerolled attack/defence) within this entry.
	var notice_index := -1
	var cards_index := -1
	for i in range(segments_after.size()):
		var seg: Dictionary = segments_after[i]
		if seg.get("kind", "") == "notice" and str(seg.get("text", "")).contains("spends a Fortune Point to reroll") and notice_index == -1:
			notice_index = i
		if seg.get("kind", "") == "cards" and cards_index == -1:
			cards_index = i
	checks.append(["Part 1: the 'spends a Fortune Point to reroll' notice segment was found in the merged entry", notice_index != -1])
	checks.append(["Part 1: ...and it renders BEFORE the rerolled cards segment, not after (the ordering fix)", notice_index != -1 and cards_index != -1 and notice_index < cards_index])

	var reroll_cards: Array = segments_after[cards_index].get("cards", []) if cards_index != -1 else []
	var defence_after := _find_card(reroll_cards, "Defence")
	checks.append(["Part 1: a rerolled Defence card was actually logged", not defence_after.is_empty()])
	if not defence_after.is_empty():
		var defender_roll_after: int = defence_after.get("test").roll
		checks.append(["Part 1: rerolling the ATTACKER's own roll left the DEFENDER's already-rolled Defence number genuinely unchanged", defender_roll_after == defender_roll_before])

	fe1.queue_free()
	await tree.process_frame

	## --- Part 2: rerolling the PLAYER's own Defence must not touch the
	## MONSTER's (attacker's) already-rolled Attack number. A fresh
	## FieldEncounter instance, so nothing from Part 1's own action
	## coroutine can still be mid-flight and interfere. --------------------
	var setup2 := await _spin_up_encounter(tree, checks)
	var fe2: Node = setup2["fe"]
	var monster2: Character = setup2["monster"]
	var pc2: Character = setup2["pc"]

	var sword: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	fe2.pending_defense = {"attacker": monster2, "weapon": sword, "attacker_effort": 0, "charge_bonus": 0}
	var dodge_skill: SkillDefinition = GameData.skill_db.find_by_name("Dodge")
	fe2._resolve_player_defense(dodge_skill, "")
	waited = 0
	while not fe2.awaiting_fortune_choice and waited < 90:
		await tree.process_frame
		waited += 1
	checks.append(["Part 2: a Fortune-spend prompt is genuinely offered after the crippled Agility fails the Defence", fe2.awaiting_fortune_choice])

	var def_entry_before: Dictionary = fe2.history[0] if not fe2.history.is_empty() else {}
	var def_cards_before: Array = []
	for seg in def_entry_before.get("segments", []):
		if seg.get("kind", "") == "cards":
			def_cards_before = seg.get("cards", [])
	var attacker_card_before := _find_non_defence_card(def_cards_before)
	checks.append(["Part 2: the initial monster Attack card/roll genuinely exists to compare against", not attacker_card_before.is_empty()])
	var attacker_roll_before: int = attacker_card_before.get("test").roll if not attacker_card_before.is_empty() else -999

	if fe2.awaiting_fortune_choice:
		fe2._pending_choice_str = "reroll"
		fe2.awaiting_fortune_choice = false
		waited = 0
		while not fe2.awaiting_fortune_choice and waited < 90:
			await tree.process_frame
			waited += 1
		if fe2.awaiting_fortune_choice:
			fe2._pending_choice_str = ""
			fe2.awaiting_fortune_choice = false
		for i in range(10):
			await tree.process_frame

	var def_entry_after: Dictionary = fe2.history[0] if not fe2.history.is_empty() else {}
	var def_segments_after: Array = def_entry_after.get("segments", [])
	var def_cards_index := -1
	for i in range(def_segments_after.size()):
		if def_segments_after[i].get("kind", "") == "cards":
			def_cards_index = i
			break
	var reroll_def_cards: Array = def_segments_after[def_cards_index].get("cards", []) if def_cards_index != -1 else []
	var attacker_card_after := _find_non_defence_card(reroll_def_cards)
	checks.append(["Part 2: a rerolled monster Attack card was actually logged", not attacker_card_after.is_empty()])
	if not attacker_card_after.is_empty():
		var attacker_roll_after: int = attacker_card_after.get("test").roll
		checks.append(["Part 2: rerolling the DEFENDER's (player's) own roll left the ATTACKER's (monster's) already-rolled number genuinely unchanged", attacker_roll_after == attacker_roll_before])

	fe2.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Combat Reroll — Only Your Own Roll, Notice Before Cards): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
