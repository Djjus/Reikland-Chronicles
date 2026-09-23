extends RefCounted
class_name WeaponGroupRulesTest
## Per the request ("lets implement these weapon group rules" — 6
## rulebook screenshots covering Melee/Ranged Weapon Groups, p.296):
## confirms the core mechanics added for it, all living on Character
## (is_trained_in_weapon_group/can_use_ranged_weapon/
## get_effective_weapon_qualities) and CombatResolver.get_defense_modifiers:
##
## - Melee general rule: an untrained weapon Group still tests (Melee
##   already fell back to Weapon Skill+0 as a side effect of existing
##   code) but now genuinely loses its Qualities while keeping its
##   Flaws — Melee (Basic) itself stays exempt, matching
##   shop_screen.gd's own established "usable untrained" convention.
## - Flail: an unskilled wielder's Flail dynamically gains the
##   Dangerous Flaw even when the weapon's own data doesn't list it.
## - Parry: a one-handed Defensive weapon waives the off-hand penalty;
##   a two-handed one (even if nominally Defensive) does not.
## - Ranged general rule: an untrained Ranged Group is a hard block,
##   not just a worse roll — UNLESS Crossbow/Throwing (always usable
##   via Ballistic Skill) or the Blackpowder<->Engineering
##   cross-training exception (asymmetric: Engineering keeps full
##   Qualities using Blackpowder/Explosives gear; Blackpowder using
##   Engineering gear does not) applies.

static func run_test() -> bool:
	var checks: Array = []

	var human := GameData.find_race("Human")
	var soldier := GameData.find_career("Soldier")
	var make_character := func() -> Character:
		var c := Character.new()
		c.race = human
		c.career = soldier
		c.current_tier = 1
		c.characteristics = CharacteristicSet.new()
		c.recompute_max_wounds()
		return c

	var melee_skill: SkillDefinition = GameData.skill_db.find_by_name("Melee")
	var ranged_skill: SkillDefinition = GameData.skill_db.find_by_name("Ranged")
	checks.append(["Test setup: found the real Melee/Ranged grouped skills", melee_skill != null and ranged_skill != null])

	var sword: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	var halberd: WeaponDefinition = GameData.weapon_db.find_by_name("Halberd")
	var flail: WeaponDefinition = GameData.weapon_db.find_by_name("Military Flail")
	var main_gauche: WeaponDefinition = GameData.weapon_db.find_by_name("Main Gauche")
	var elf_bow: WeaponDefinition = GameData.weapon_db.find_by_name("Elf Bow")
	var crossbow: WeaponDefinition = GameData.weapon_db.find_by_name("Crossbow")
	var dart: WeaponDefinition = GameData.weapon_db.find_by_name("Dart")
	var blunderbuss: WeaponDefinition = GameData.weapon_db.find_by_name("Blunderbuss")
	checks.append(["Test setup: found every real weapon this test needs",
		sword != null and halberd != null and flail != null and main_gauche != null and
		elf_bow != null and crossbow != null and dart != null and blunderbuss != null])
	if sword == null or halberd == null or flail == null or main_gauche == null or elf_bow == null or crossbow == null or dart == null or blunderbuss == null:
		print("FAIL  could not find real weapon data — aborting")
		return false

	## --- Melee general rule: is_trained_in_weapon_group ------------------
	var fighter: Character = make_character.call()
	checks.append(["A Basic-Group melee weapon (Sword) is always 'trained' — Melee (Basic) is not an Advanced skill", fighter.is_trained_in_weapon_group(sword)])
	checks.append(["A non-Basic Group (Halberd -> Polearm) is NOT trained with zero Advances", not fighter.is_trained_in_weapon_group(halberd)])
	fighter.skill_advances[melee_skill.display_name("Polearm")] = 1
	checks.append(["...but IS trained once Melee (Polearm) has a real Advance", fighter.is_trained_in_weapon_group(halberd)])

	## --- Melee general rule: Qualities lost, Flaws kept ------------------
	var untrained: Character = make_character.call()
	checks.append(["Untrained Halberd (Defensive/Hack/Impale, all Qualities, no Flaws): every Quality is stripped", untrained.get_effective_weapon_qualities(halberd).is_empty()])
	untrained.skill_advances[melee_skill.display_name("Polearm")] = 1
	var trained_qualities := untrained.get_effective_weapon_qualities(halberd)
	checks.append(["Trained Halberd: keeps all 3 of its real Qualities", trained_qualities.size() == 3 and trained_qualities.has("Defensive") and trained_qualities.has("Hack") and trained_qualities.has("Impale")])

	## --- Flail sub-rule ---------------------------------------------------
	var flail_wielder: Character = make_character.call()
	var untrained_flail_qualities := flail_wielder.get_effective_weapon_qualities(flail)
	checks.append(["Untrained Military Flail: Tiring (its own real Flaw) is kept", untrained_flail_qualities.has("Tiring")])
	checks.append(["Untrained Military Flail: Dangerous is dynamically ADDED even though the weapon's own data doesn't list it", untrained_flail_qualities.has("Dangerous")])
	checks.append(["Untrained Military Flail: real Qualities (Impact/Wrap) are still stripped", not untrained_flail_qualities.has("Impact") and not untrained_flail_qualities.has("Wrap")])
	flail_wielder.skill_advances[melee_skill.display_name("Flail")] = 1
	var trained_flail_qualities := flail_wielder.get_effective_weapon_qualities(flail)
	checks.append(["Trained Military Flail: full real Qualities/Flaws, and Dangerous is NOT auto-added since it's already trained", trained_flail_qualities.has("Impact") and trained_flail_qualities.has("Wrap") and not trained_flail_qualities.has("Dangerous")])

	## --- Parry sub-rule: one-handed Defensive waives the off-hand penalty
	var parrier: Character = make_character.call()
	var untrained_mods := CombatResolver.get_defense_modifiers(parrier, main_gauche, true)
	checks.append(["Untrained Main Gauche (Parry Group): Defensive Quality is lost, so the full off-hand penalty still applies", (untrained_mods["target_breakdown"] as Array).size() > 0])
	parrier.skill_advances[melee_skill.display_name("Parry")] = 1
	var trained_mods := CombatResolver.get_defense_modifiers(parrier, main_gauche, true)
	checks.append(["Trained, one-handed Defensive Main Gauche: grants its +1 SL", (trained_mods["sl_breakdown"] as Array).size() > 0])
	checks.append(["...and waives the off-hand penalty entirely (p.296)", (trained_mods["target_breakdown"] as Array).is_empty()])

	## A synthetic TWO-handed "Defensive" weapon (none exist in the real
	## data — Halberd/Military Flail are both 2H but neither carries
	## Defensive) — the rule's own wording is "Any ONE-handed weapon",
	## so this must still owe the full off-hand penalty despite being
	## Defensive and fully trained (Basic Group, always trained).
	var synthetic_2h_defensive := WeaponDefinition.new()
	synthetic_2h_defensive.weapon_name = "Test Two-Handed Defensive Weapon"
	synthetic_2h_defensive.skill_group = "Basic"
	synthetic_2h_defensive.is_two_handed = true
	synthetic_2h_defensive.qualities = ["Defensive"]
	var synthetic_mods := CombatResolver.get_defense_modifiers(parrier, synthetic_2h_defensive, true)
	checks.append(["A trained, two-handed 'Defensive' weapon still grants its +1 SL (Defensive itself doesn't require one-handed)", (synthetic_mods["sl_breakdown"] as Array).size() > 0])
	checks.append(["...but does NOT waive the off-hand penalty — only a ONE-handed Defensive weapon does (p.296)", (synthetic_mods["target_breakdown"] as Array).size() > 0])

	## --- Ranged general rule: can_use_ranged_weapon -----------------------
	var archer: Character = make_character.call()
	checks.append(["Untrained Ranged (Bow): cannot even attempt the Test — a hard block, not just a worse roll", not archer.can_use_ranged_weapon(elf_bow)])
	archer.skill_advances[ranged_skill.display_name("Bow")] = 1
	checks.append(["Trained Ranged (Bow): can attempt it", archer.can_use_ranged_weapon(elf_bow)])

	## --- Crossbows and Throwing sub-rule -----------------------------------
	var untrained_thrower: Character = make_character.call()
	checks.append(["Untrained Crossbow: always attemptable via Ballistic Skill (p.296 exception)", untrained_thrower.can_use_ranged_weapon(crossbow)])
	checks.append(["Untrained Throwing (Dart): same exception", untrained_thrower.can_use_ranged_weapon(dart)])
	checks.append(["...but Qualities are still lost (Dart's real Impale Quality)", not untrained_thrower.get_effective_weapon_qualities(dart).has("Impale")])
	checks.append(["...while Flaws are still kept (Crossbow's real Reload 1 Flaw)", untrained_thrower.get_effective_weapon_qualities(crossbow).has("Reload 1")])

	## --- Blackpowder/Explosives + Engineering cross-training --------------
	var engineer: Character = make_character.call()
	checks.append(["Untrained Ranged (Blackpowder), no Engineering either: Blunderbuss is a hard block", not engineer.can_use_ranged_weapon(blunderbuss)])
	engineer.skill_advances[ranged_skill.display_name("Engineering")] = 1
	checks.append(["Ranged (Engineering) trained: CAN use the untrained Blackpowder Blunderbuss (p.296 exception)", engineer.can_use_ranged_weapon(blunderbuss)])
	var engineer_qualities := engineer.get_effective_weapon_qualities(blunderbuss)
	checks.append(["...and 'without penalty' means full Qualities kept (real Blast 3 Quality), not stripped", engineer_qualities.has("Blast 3")])

	## The reverse direction is NOT symmetric: Ranged (Blackpowder)
	## trained does NOT grant free Engineering use — only Ranged
	## (Engineering) trained does, per the exact rule text quoted above.
	var gunner: Character = make_character.call()
	gunner.skill_advances[ranged_skill.display_name("Blackpowder")] = 1
	checks.append(["Ranged (Blackpowder) trained alone grants NOTHING extra for Blackpowder/Explosives itself (already trained the normal way)", gunner.can_use_ranged_weapon(blunderbuss)])

	## --- Parry preference (per the follow-up request: "allow user to
	## select if they want to use parry for defensive weapons... make
	## sure it remembers this choice when unequipping and reequipping
	## the same weapon") ------------------------------------------------
	var chooser: Character = make_character.call()
	checks.append(["wants_parry_skill defaults to false for a weapon never explicitly toggled", not chooser.wants_parry_skill(main_gauche)])
	chooser.parry_preference[main_gauche.weapon_name] = true
	checks.append(["Setting parry_preference[weapon_name] = true is reflected by wants_parry_skill", chooser.wants_parry_skill(main_gauche)])
	## Simulates "unequip, then re-equip the SAME weapon" — since the
	## choice is keyed by weapon NAME (not equip slot), nothing about
	## unequipping should ever touch this dictionary.
	chooser.equipped_offhand = ""
	checks.append(["Unequipping the weapon does not clear its remembered preference", chooser.wants_parry_skill(main_gauche)])
	chooser.equipped_offhand = main_gauche.weapon_name
	checks.append(["Re-equipping the same weapon (by name) still remembers the choice", chooser.wants_parry_skill(main_gauche)])

	## Round-trips through JSON, exactly as SaveManager does on disk.
	var save_dict: Dictionary = chooser.to_save_dict()
	checks.append(["to_save_dict() includes parry_preference", save_dict.has("parry_preference")])
	var json_roundtrip: Dictionary = JSON.parse_string(JSON.stringify(save_dict))
	var reloaded: Character = Character.from_save_dict(json_roundtrip)
	checks.append(["A reloaded Character (JSON round-trip) still remembers the Parry choice for this weapon", reloaded != null and reloaded.wants_parry_skill(main_gauche)])
	var no_pref_dict: Dictionary = save_dict.duplicate(true)
	no_pref_dict.erase("parry_preference")
	var reloaded_no_pref: Character = Character.from_save_dict(no_pref_dict)
	checks.append(["A save file with no parry_preference key at all still loads cleanly (empty Dictionary, not a crash)", reloaded_no_pref != null and reloaded_no_pref.parry_preference.is_empty()])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Weapon Group Rules Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
