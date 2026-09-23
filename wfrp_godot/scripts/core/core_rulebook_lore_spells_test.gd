extends RefCounted
class_name CoreRulebookLoreSpellsTest
## Covers the core-rulebook spell-list comparison work: the 2 missing
## Petty spells (Dazzle, Sounds), the 13 missing generic Arcane spells,
## and the new Lore-of-Magic system (all 8 Lores' 8 signature spells
## each, gated learning via Advancement.purchase_arcane_spell, and the
## real Condition mechanics now reachable in combat).
##
## Also covers two real bugs discovered and fixed while wiring this up:
## (1) _is_damage_effect() never counted a Condition-only spell (like
## Shock, already live) as needing an enemy target, so its Condition
## never actually landed — always fell through to "cast on self", and
## _apply_cast_spell_outcome's own `target != player` guard silently did
## nothing. (2) a spell that's both a magic missile AND inflicts a
## Condition on the same hit (several new Lore spells do this, e.g.
## Steal Life, T'Essla's Arc) previously could only ever apply one or
## the other, since the whole outcome chain is an elif.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Spell database sanity ------------------------------------------
	var all_spells: Array = GameData.spell_db.spells
	checks.append(["spell database has exactly 112 spells (33 original + 79 new)", all_spells.size() == 112])
	var seen_names: Dictionary = {}
	var dup_found := false
	for sp: SpellDefinition in all_spells:
		if seen_names.has(sp.spell_name):
			dup_found = true
		seen_names[sp.spell_name] = true
	checks.append(["no duplicate spell names", not dup_found])

	var dazzle: SpellDefinition = GameData.spell_db.find_by_name("Dazzle")
	checks.append(["Dazzle exists as a Petty spell", dazzle != null and dazzle.spell_type == "Petty" and dazzle.casting_number == 0])
	checks.append(["Dazzle inflicts Blinded", dazzle != null and dazzle.inflicts_condition == "Blinded"])
	var sounds: SpellDefinition = GameData.spell_db.find_by_name("Sounds")
	checks.append(["Sounds exists as a Petty spell", sounds != null and sounds.spell_type == "Petty" and sounds.casting_number == 0])

	var petty_count := 0
	var generic_arcane_count := 0
	var lore_counts: Dictionary = {}
	for sp: SpellDefinition in all_spells:
		if sp.spell_type == "Petty":
			petty_count += 1
		elif sp.spell_type == "Arcane" and sp.lore == "":
			generic_arcane_count += 1
		elif sp.spell_type == "Lore":
			lore_counts[sp.lore] = lore_counts.get(sp.lore, 0) + 1
	checks.append(["25 Petty spells total (23 original + Dazzle + Sounds)", petty_count == 25])
	checks.append(["23 generic Arcane spells total (10 original + 13 new)", generic_arcane_count == 23])

	var expected_lores: Array[String] = ["Beasts", "Death", "Fire", "Heavens", "Metal", "Life", "Light", "Shadow"]
	var all_lores_have_8 := true
	for lore_name in expected_lores:
		if lore_counts.get(lore_name, 0) != 8:
			all_lores_have_8 = false
	checks.append(["all 8 Lores have exactly 8 signature spells each", all_lores_have_8])
	checks.append(["no stray/unexpected Lore names", lore_counts.size() == expected_lores.size()])

	var chain_attack: SpellDefinition = GameData.spell_db.find_by_name("Chain Attack")
	checks.append(["Chain Attack is a generic magic missile (dmg +4)", chain_attack != null and chain_attack.is_magic_missile and chain_attack.damage_flat == 4 and chain_attack.lore == ""])
	var entangle: SpellDefinition = GameData.spell_db.find_by_name("Entangle")
	checks.append(["Entangle inflicts the Entangled Condition", entangle != null and entangle.inflicts_condition == "Entangled"])

	var tessla: SpellDefinition = GameData.spell_db.find_by_name("T'Essla's Arc")
	checks.append(["T'Essla's Arc (Heavens) is both a magic missile AND inflicts Blinded", tessla != null and tessla.is_magic_missile and tessla.inflicts_condition == "Blinded" and tessla.lore == "Heavens"])
	var steal_life: SpellDefinition = GameData.spell_db.find_by_name("Steal Life")
	checks.append(["Steal Life (Death) is both a magic missile AND inflicts Fatigued", steal_life != null and steal_life.is_magic_missile and steal_life.inflicts_condition == "Fatigued"])
	var choking: SpellDefinition = GameData.spell_db.find_by_name("Choking Shadows")
	checks.append(["Choking Shadows (Shadow) is a pure Condition spell, not a missile", choking != null and not choking.is_magic_missile and choking.inflicts_condition == "Fatigued"])

	## --- Learning gate: Advancement.purchase_arcane_spell ----------------
	var human: RaceDefinition = GameData.find_race("Human")
	var wizard_career: CareerDefinition = GameData.find_career("Wizard")
	var caster := CharacterCreator.create_character("Test Caster", human, wizard_career,
		{"intelligence": 2, "willpower": 1, "weapon_skill": 1})
	caster.experience_total = 100000

	var no_talent_result := Advancement.purchase_arcane_spell(caster, "Bolt")
	checks.append(["no Arcane Magic Talent: can't learn a generic Arcane spell", not no_talent_result.success])
	var no_talent_lore_result := Advancement.purchase_arcane_spell(caster, "Crown of Flame")
	checks.append(["no Arcane Magic Talent: can't learn a Lore spell either", not no_talent_lore_result.success])

	caster.talents_taken["Arcane Magic (Fire)"] = 1
	checks.append(["sanity: get_arcane_lore() reads back \"Fire\" from the situational Talent", caster.get_arcane_lore() == "Fire"])

	var generic_result := Advancement.purchase_arcane_spell(caster, "Bolt")
	checks.append(["Fire Lore holder CAN learn a generic Arcane spell (Bolt)", generic_result.success])
	var matching_lore_result := Advancement.purchase_arcane_spell(caster, "Crown of Flame")
	checks.append(["Fire Lore holder CAN learn their own Lore's spell (Crown of Flame)", matching_lore_result.success])
	var wrong_lore_result := Advancement.purchase_arcane_spell(caster, "Regenerate")
	checks.append(["Fire Lore holder CANNOT learn a different Lore's spell (Regenerate, Life)", not wrong_lore_result.success])
	checks.append(["known_spells now has Bolt and Crown of Flame but not Regenerate", caster.known_spells.has("Bolt") and caster.known_spells.has("Crown of Flame") and not caster.known_spells.has("Regenerate")])

	var already_known_result := Advancement.purchase_arcane_spell(caster, "Bolt")
	checks.append(["can't re-learn an already-known spell", not already_known_result.success])

	## --- Combat mechanics: the real fixes, exercised live -----------------
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "Elowen"
	pc.equipped_weapon = "Sword"
	pc.talents_taken["Arcane Magic (Heavens)"] = 1
	pc.known_spells = ["Shock", "T'Essla's Arc", "Choking Shadows"]

	GameState.pending_encounter_monster_names = ["Giant Rat"]
	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(5):
		await tree.process_frame

	if fe.encounter.get_living("ally").size() != 1 or fe.encounter.get_living("adversary").size() != 1:
		fe.queue_free()
		for i in range(3): await tree.process_frame
		print("RESULT (Core Rulebook Lore Spells): SETUP FAILED")
		return false

	var target: Character = fe.encounter.get_living("adversary")[0]

	## Real bug fix #1: _is_damage_effect now recognises a Condition-only
	## spell as needing an enemy target -- Shock was the pre-existing,
	## silently-broken example.
	checks.append(["_is_damage_effect() now true for a Condition-only spell (Shock) -- previously always false", fe._is_damage_effect("Shock", true)])
	checks.append(["_is_damage_effect() true for a new Lore Condition spell (Choking Shadows)", fe._is_damage_effect("Choking Shadows", true)])

	var make_success_result := func() -> MagicResolver.CastResult:
		var test_result := TestResolver.TestResult.new()
		test_result.success = true
		test_result.roll = 30
		test_result.target = 60
		test_result.success_levels = 5
		var cast_result := MagicResolver.CastResult.new()
		cast_result.success = true
		cast_result.test_result = test_result
		return cast_result

	## Shock, cast at a real enemy target (not the caster): the Condition
	## must now actually land, where before this fix it silently never
	## would have been reachable through the real UI flow at all.
	var shock: SpellDefinition = GameData.spell_db.find_by_name("Shock")
	fe._apply_cast_spell_outcome(make_success_result.call(), shock, "Shock", target, false)
	checks.append(["Shock cast at a real enemy target now actually applies Stunned", target.conditions.has("Stunned")])

	## Real bug fix #2: T'Essla's Arc is both a magic missile AND inflicts
	## a Condition -- both must land from the one cast, not just one.
	## Giant Rat's own Wounds are too low to survive a 10+WPB hit (the
	## outcome code correctly skips the Condition on a defeating blow --
	## see its own comment), so pad Wounds up first specifically so this
	## check proves the "both effects land" case rather than the
	## already-covered "skip on kill" case.
	target.wounds_current = 999
	target.wounds_max = 999
	var wounds_before := target.wounds_current
	fe._apply_cast_spell_outcome(make_success_result.call(), tessla, "T'Essla's Arc", target, false)
	checks.append(["T'Essla's Arc deals real Wound damage", target.wounds_current < wounds_before])
	checks.append(["T'Essla's Arc ALSO applies Blinded on the same cast", target.conditions.has("Blinded")])

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
	print("RESULT (Core Rulebook Lore Spells): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
