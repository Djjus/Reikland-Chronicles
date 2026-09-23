extends RefCounted
class_name MonsterRangedTraitActivationTest
## Regression test for the request ("let's change the way non
## BanditGenerator enemies are handled if they have a optional trait -
## Ranged +X (xx). Every other enemy generated as part of the group of
## enemies should get this trait activated and be able to switch to a
## appropriate ranged weapon to attack with, a bit like we just did for
## Outlaws.") — confirms:
## - CreatureTraits.build_natural_ranged_weapon() correctly parses the
##   new "Ranged (Rating/Range)" two-number format (real book values:
##   Orc "Ranged+8 (50)", Goblin "Ranged+7 (25)" — p.325-326), and
##   returns null for anything malformed/missing (including the OLD,
##   incomplete single-number placeholder still left on Ungor/Night
##   Runner at the time of writing);
## - field_encounter_screen.gd's own _maybe_activate_ranged_trait()
##   activates the trait on exactly every ODD position (0-indexed 1, 3,
##   ...) of a spawned monster GROUP, counted straight through in spawn
##   order regardless of species mixing — the request's own worked
##   example (Goblin/Orc/Orc/Goblin activates the 2nd Orc and the 4th
##   Goblin) — and never activates a malformed entry;
## - _maybe_switch_monster_weapon_for_range() correctly gives an
##   activated monster a working natural ranged option: switches to it
##   at range, back to its real manufactured melee weapon (Spear/Axe)
##   once adjacent, and a monster whose trait ISN'T activated (or has
##   none at all) never switches regardless of distance.
##
## Uses `fe` (a live FieldEncounter.tscn instance the caller owns),
## matching this project's own `run_test(fe)` convention.

static func run_test(fe) -> bool:
	var checks: Array = []

	## --- Direct parser checks (no live battle needed) --------------------
	var well_formed := Character.new()
	var wf_traits: Array[String] = ["Ranged (8/50)"]
	well_formed.creature_traits = wf_traits
	var w1: WeaponDefinition = CreatureTraits.build_natural_ranged_weapon(well_formed)
	checks.append(["Parser: a well-formed 'Ranged (8/50)' trait builds a real ranged weapon", w1 != null])
	if w1 != null:
		checks.append(["Parser: Rating (8) becomes the fixed Damage", w1.is_ranged and w1.damage_mode == "fixed" and w1.damage_flat == 8])
		checks.append(["Parser: Range (50) becomes range_yards", w1.range_yards == 50])

	var goblin_formed := Character.new()
	var gf_traits: Array[String] = ["Ranged (7/25)"]
	goblin_formed.creature_traits = gf_traits
	var w2: WeaponDefinition = CreatureTraits.build_natural_ranged_weapon(goblin_formed)
	checks.append(["Parser: Goblin's real book values (7/25) parse correctly too", w2 != null and w2.damage_flat == 7 and w2.range_yards == 25])

	var malformed := Character.new()
	var mf_traits: Array[String] = ["Ranged (7)"]   ## old, incomplete placeholder format
	malformed.creature_traits = mf_traits
	checks.append(["Parser: the OLD single-number placeholder ('Ranged (7)') deliberately returns null, not a guess", CreatureTraits.build_natural_ranged_weapon(malformed) == null])

	var no_trait := Character.new()
	checks.append(["Parser: a character with no Ranged trait at all returns null", CreatureTraits.build_natural_ranged_weapon(no_trait) == null])

	## --- Spawn-time alternating activation ---------------------------------
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.current_field_difficulty_tier = 0
	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	GameState.pending_encounter_monster_names = ["Goblin", "Orc", "Orc", "Goblin"]
	await fe._start_encounter()
	for i in range(5):
		await fe.get_tree().process_frame

	var setup_ok: bool = fe.monsters.size() == 4
	checks.append(["setup: all 4 requested monsters spawned in order", setup_ok])
	if not setup_ok:
		print("RESULT (Monster Ranged Trait Activation): SETUP FAILED")
		return false

	var m0: Character = fe.monsters[0]   ## Goblin, index 0 -- NOT activated
	var m1: Character = fe.monsters[1]   ## Orc, index 1 -- activated
	var m2: Character = fe.monsters[2]   ## Orc, index 2 -- NOT activated
	var m3: Character = fe.monsters[3]   ## Goblin, index 3 -- activated

	checks.append(["Index 0 (1st, Goblin): NOT activated -- even position", not m0.has_creature_trait("Ranged")])
	checks.append(["Index 1 (2nd, Orc): activated with the real Orc values (Ranged (8/50))", m1.creature_traits.has("Ranged (8/50)")])
	checks.append(["Index 2 (3rd, Orc): NOT activated -- even position", not m2.has_creature_trait("Ranged")])
	checks.append(["Index 3 (4th, Goblin): activated with the real Goblin values (Ranged (7/25))", m3.creature_traits.has("Ranged (7/25)")])

	## --- Weapon switching for an activated monster (Orc, index 1) --------
	var player_pos: Vector2i = fe.battle_positions[fe.player]
	fe.battle_positions[m1] = player_pos + Vector2i(10, 0)   ## far
	fe._maybe_switch_monster_weapon_for_range(m1)
	checks.append(["Activated Orc far from any enemy: switches to its natural ranged attack", fe.weapons.has(m1) and fe.weapons[m1] != null and fe.weapons[m1].is_ranged])
	checks.append(["Activated Orc far from any enemy: the natural ranged weapon carries the real Orc Rating/Range (8/50)", fe.weapons[m1].damage_flat == 8 and fe.weapons[m1].range_yards == 50])
	checks.append(["Activated Orc far from any enemy: equipped_weapon is left untouched (still the real Axe, nothing to equip for a natural attack)", m1.equipped_weapon == "Axe"])

	fe.battle_positions[m1] = player_pos + Vector2i(1, 0)   ## adjacent
	fe._maybe_switch_monster_weapon_for_range(m1)
	checks.append(["Activated Orc adjacent to an enemy: switches back to its real manufactured Axe", fe.weapons.has(m1) and fe.weapons[m1] != null and not fe.weapons[m1].is_ranged and fe.weapons[m1].weapon_name == "Axe"])

	fe.battle_positions[m1] = player_pos + Vector2i(10, 0)   ## far again
	fe._maybe_switch_monster_weapon_for_range(m1)
	checks.append(["Activated Orc moving back out of range switches back to its natural ranged attack again", fe.weapons.has(m1) and fe.weapons[m1] != null and fe.weapons[m1].is_ranged])

	## --- A monster whose trait ISN'T activated never switches -------------
	fe.battle_positions[m0] = player_pos + Vector2i(10, 0)   ## far
	fe._maybe_switch_monster_weapon_for_range(m0)
	checks.append(["Non-activated Goblin (index 0) far from any enemy: no-op, still its melee Spear", fe.weapons.has(m0) and fe.weapons[m0] != null and not fe.weapons[m0].is_ranged])
	fe.battle_positions[m0] = player_pos + Vector2i(1, 0)   ## adjacent
	fe._maybe_switch_monster_weapon_for_range(m0)
	checks.append(["Non-activated Goblin (index 0) adjacent: still a no-op, same melee Spear", fe.weapons.has(m0) and fe.weapons[m0] != null and not fe.weapons[m0].is_ranged])

	## --- A malformed/incomplete Ranged entry is never activated -----------
	var synthetic_mdef := MonsterDefinition.new()
	synthetic_mdef.monster_name = "Test Malformed Ranged Monster"
	var synth_chars := CharacteristicSet.new()
	synthetic_mdef.characteristics = synth_chars
	synthetic_mdef.weapon_name = "Sword"
	var synth_optional: Array[String] = ["Ranged (7)"]   ## old, incomplete placeholder -- like Ungor/Night Runner today
	synthetic_mdef.optional_creature_traits = synth_optional
	var synth_char := synthetic_mdef.to_character()
	fe._maybe_activate_ranged_trait(synth_char, synthetic_mdef, 1)   ## odd position -- would normally activate
	checks.append(["A malformed 'Ranged (7)' optional trait at an odd position is never activated (no working natural weapon to build)", not synth_char.has_creature_trait("Ranged")])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Monster Ranged Trait Activation): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
