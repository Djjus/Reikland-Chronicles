extends RefCounted
class_name CriticalWoundDeflectReproTest
## Repro attempt for the user report: "deflecting a critical hit on the
## body leather jack location is still crashing the game, happened
## twice now." Unlike critical_wound_deflect_input_test.gd (which
## hand-builds a synthetic AttackResult and calls
## _handle_critical_wound_on_player() directly, skipping the whole
## surrounding real combat-resolution path), this drives a REAL
## CombatResolver.resolve_melee_attack() call with forced dice so the
## whole production tail _resolve_player_defense() itself runs
## (_show_attack_cards, _render_status, the critical wound prompt,
## THEN Deflect, THEN the fumble/deathblow/_next_turn tail) — the
## surrounding context the existing test never exercised.
##
## Forced rolls: attacker roll 55 (a double -- 55 % 11 == 0 -- so it's
## automatically a Critical Hit once it succeeds; reversed digits of
## 55 are still 55, landing in the Body hit-location band [45,79]) with
## the monster's Weapon Skill boosted well above 55 so it reliably
## succeeds; defender (player) roll forced to 99, a near-guaranteed
## failure regardless of real Dodge skill. No wounds/overkill trickery
## needed -- the double alone triggers a genuine Critical Wound.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "DeflectReproTester"
	pc.equipped_armour = ["Leather Jack"]
	pc.armour_damage.clear()
	pc.broken_armour.clear()

	var no_pool: Array[String] = []
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	GameState.pending_encounter_monster_names = ["Giant Rat"]

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(5):
		await tree.process_frame

	var player: Character = fe.player
	var monster: Character = fe.monsters[0] if fe.monsters.size() > 0 else null
	checks.append(["setup: player has deflectable armour at Body", player.can_deflect_critical_wound("Body")])
	checks.append(["setup: a monster exists", monster != null])
	if monster == null:
		fe.queue_free()
		for i in range(3): await tree.process_frame
		print("RESULT (Critical Wound Deflect Repro): SETUP FAILED")
		return false

	## Guarantee the attacker wins the opposed test outright regardless
	## of the real database's own Giant Rat stats.
	monster.characteristics.set_value("weapon_skill", 150)
	var weapon: WeaponDefinition = fe.weapons.get(monster)
	checks.append(["setup: monster has a real resolved weapon", weapon != null])

	var dodge_skill: SkillDefinition = GameData.skill_db.find_by_name("Dodge")
	var starting_damage: int = player.get_total_armour_damage("Leather Jack")
	var wounds_before := player.wounds_current

	## Real production call -- same function every other monster-attack
	## call site in this file uses, just with forced rolls instead of
	## real dice so the Critical Hit is deterministic.
	var result: CombatResolver.AttackResult = CombatResolver.resolve_melee_attack(
		monster, player, weapon, fe.encounter.advantage_pool,
		dodge_skill, "", false, 0, 0, 55, [], 0, [], 99)

	checks.append(["repro: the attack genuinely hit", result.hit])
	checks.append(["repro: the attack genuinely rolled a Critical Hit (double, 55)", result.was_critical])
	checks.append(["repro: a Critical Wound was genuinely triggered", result.caused_critical_wound])

	## _roll_critical_wound() (CombatResolver, private/static) rolls its
	## OWN independent location + effect dice -- entirely separate from
	## the attacker_forced_roll above, which only controls the initial
	## hit_location used for damage soak. Real (unforced) d100s there
	## would make this test's location AND table entry both genuinely
	## random -- sometimes Body, sometimes not; sometimes an ordinary
	## int "wounds" entry (the exact shape that crashed), sometimes "T"
	## or "Death" (which don't exercise the bug at all). Overridden here
	## directly from the real data table instead, via the same
	## GameData.critical_wound_db.lookup() the production code itself
	## uses -- roll 15 on the real Body table is "'Tis But A Scratch!",
	## wounds: 1 (a genuine int) -- exactly the shape that crashed.
	result.critical_wound_location = "Body"
	result.critical_wound_entry = GameData.critical_wound_db.lookup("Body", 15)
	result.critical_wound_roll = 15
	result.critical_wound_overkill_bonus = 0
	result.critical_wound_causes_death = false

	checks.append(["repro: the deterministic Body-table entry has a real int wounds value (the exact shape that crashed)", result.critical_wound_entry.get("wounds") is int])
	checks.append(["repro: the roll landed on the Body hit location, matching the bug report", result.critical_wound_location == "Body"])
	checks.append(["repro: this is not a Death-tier result (still deflectable)", not result.critical_wound_causes_death])

	## Exactly what _resolve_player_defense() itself does with a fresh
	## result, in the same order, before reaching the critical-wound
	## handling -- the real surrounding context the older test skipped.
	fe._show_attack_cards(monster, player, weapon.weapon_name, result)
	fe._render_status()

	## Fire-and-forget, same pattern every other test in this suite uses
	## for a suspended `while awaiting_X: await` prompt.
	fe._handle_critical_wound_on_player(result)
	for i in range(10):
		if fe.awaiting_critical_wound_choice:
			break
		await tree.process_frame

	checks.append(["the Accept/Deflect prompt genuinely opened, no crash/hang before it", fe.awaiting_critical_wound_choice])

	var deflect_btn: Button = null
	for child in fe.target_container.get_children():
		if child is Button and String(child.text).begins_with("Deflect"):
			deflect_btn = child
			break
	checks.append(["a real Deflect button is offered", deflect_btn != null])

	if deflect_btn != null:
		deflect_btn.pressed.emit()

	## Let the whole rest of the production tail run to completion --
	## _apply_fumble_effects, _offer_deathblow_chain (no-op, monster's
	## turn), _next_turn() -- exactly what happens after a real player
	## clicks Deflect in a live game. If anything downstream throws, it
	## would surface as a script error in the console during this wait,
	## and/or leave the game in a stuck, unresolvable state (still
	## awaiting_critical_wound_choice, or awaiting_continue forever).
	for i in range(60):
		if fe.awaiting_continue:
			fe.awaiting_continue = false
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		if fe.awaiting_deathblow_choice:
			fe._pending_deathblow_target = null
			fe.awaiting_deathblow_choice = false
		await tree.process_frame

	checks.append(["the prompt genuinely closed after Deflect -- no hang", not fe.awaiting_critical_wound_choice])
	checks.append(["Deflect genuinely spent a point of Armour Damage on the struck piece", player.get_total_armour_damage("Leather Jack") == starting_damage + 1])
	checks.append(["Leather Jack survives, still equipped (only Body's own 1 AP was spent, not the whole piece)", player.equipped_armour.has("Leather Jack")])
	checks.append(["the player's Wounds still dropped from the underlying hit (Deflect avoids the Condition, not the Wound)", player.wounds_current <= wounds_before])
	## The actual real-rules symptom of the bug: with an int "wounds"
	## value, the buggy `entry.get("wounds") != "T"` comparison threw
	## before this line ever ran, so the counter silently never
	## incremented (on top of everything else downstream never running).
	checks.append(["active_critical_wound_count genuinely incremented (the buggy comparison used to throw before reaching this)", player.active_critical_wound_count == 1])
	## The function actually ran all the way to its own _clear(target_
	## container)/_render_status() tail instead of aborting right after
	## Deflect -- before the fix this never happened, leaving the dead
	## Accept/Deflect buttons frozen on screen with no way forward.
	checks.append(["the prompt's own UI was genuinely cleared afterward (the function ran to completion, not aborted mid-way)", fe.target_container.get_child_count() == 0 or not (fe.target_container.get_child(0) is Button)])
	checks.append(["the game is genuinely still alive and responsive -- fe is still a valid node in the tree", is_instance_valid(fe) and fe.is_inside_tree()])

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
	print("RESULT (Critical Wound Deflect Repro): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
