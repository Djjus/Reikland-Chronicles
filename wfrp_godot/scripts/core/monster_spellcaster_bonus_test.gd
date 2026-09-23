extends RefCounted
class_name MonsterSpellcasterBonusTest
## Regression test for the follow-up request ("lets do something
## similar with the Spellcaster trait, add the difficulty tier bonus on
## top of the +10's") — confirms CreatureTraits.apply_spellcaster_bonus():
## - grants Channelling (matching the trait's own Lore qualifier) and
##   Language (Magick) skill_advances, per the book's own fallback
##   clause for the Spellcaster Creature Trait (p.338-343: "add
##   Channelling (Choose a Wind) (WP +10) and Language (Magick)
##   (Int +10) as if they were Basic Skills");
## - adds the current field's own Difficulty Tier bonus on top of the
##   flat +10, per the follow-up request;
## - is a no-op for a Character with no active Spellcaster trait;
## - only ever fires for a monster where Spellcaster is an ACTIVE base
##   trait (Cultist, Chaos Warrior, Bray-Shaman) — a monster where it's
##   merely optional (Gor, Necromancer, Dragon, Fimir, Vampire) is left
##   untouched, matching this project's "optional traits are
##   GM-reference only" convention; no alternating per-group activation
##   was requested for this trait the way there was for Ranged.
##
## Uses `fe` (a live FieldEncounter.tscn instance the caller owns) for
## the real-monster-spawn checks, matching this project's own
## `run_test(fe)` convention.

static func run_test(fe) -> bool:
	var checks: Array = []

	## --- Direct parser/bonus checks (no live battle needed) --------------
	var chaos_caster := Character.new()
	var chaos_traits: Array[String] = ["Spellcaster (Chaos)"]
	chaos_caster.creature_traits = chaos_traits
	CreatureTraits.apply_spellcaster_bonus(chaos_caster, 0)
	checks.append(["Tier 0: Channelling (Chaos) granted at flat +10 (0 Tier bonus)", int(chaos_caster.skill_advances.get("Channelling (Chaos)", -1)) == 10])
	checks.append(["Tier 0: Language (Magick) granted at flat +10 too", int(chaos_caster.skill_advances.get("Language (Magick)", -1)) == 10])

	var chaos_caster_t3 := Character.new()
	chaos_caster_t3.creature_traits = chaos_traits
	CreatureTraits.apply_spellcaster_bonus(chaos_caster_t3, 3)
	checks.append(["Tier 3: Channelling (Chaos) is +10 PLUS the Tier 3 Difficulty bonus (+30) = 40", int(chaos_caster_t3.skill_advances.get("Channelling (Chaos)", -1)) == 40])
	checks.append(["Tier 3: Language (Magick) is also 40 (same +10+30 formula)", int(chaos_caster_t3.skill_advances.get("Language (Magick)", -1)) == 40])

	var beast_caster := Character.new()
	var beast_traits: Array[String] = ["Spellcaster (Beasts)"]
	beast_caster.creature_traits = beast_traits
	CreatureTraits.apply_spellcaster_bonus(beast_caster, 2)
	checks.append(["A different Lore qualifier (Beasts) produces its own matching Channelling (Beasts), not a hardcoded Chaos", int(beast_caster.skill_advances.get("Channelling (Beasts)", -1)) == 30])

	var bare_caster := Character.new()
	var bare_traits: Array[String] = ["Spellcaster"]
	bare_caster.creature_traits = bare_traits
	CreatureTraits.apply_spellcaster_bonus(bare_caster, 0)
	checks.append(["A bare 'Spellcaster' trait with no Lore qualifier at all still grants plain 'Channelling'", int(bare_caster.skill_advances.get("Channelling", -1)) == 10])

	var non_caster := Character.new()
	CreatureTraits.apply_spellcaster_bonus(non_caster, 5)
	checks.append(["A Character with no Spellcaster trait at all: no skill_advances granted, no-op", non_caster.skill_advances.is_empty()])

	## --- Real monster integration ------------------------------------------
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.current_field_difficulty_tier = 3
	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	GameState.pending_encounter_monster_names = ["Cultist", "Gor"]
	await fe._start_encounter()
	for i in range(5):
		await fe.get_tree().process_frame

	var setup_ok: bool = fe.monsters.size() == 2
	checks.append(["setup: both requested monsters spawned", setup_ok])
	if setup_ok:
		var cultist: Character = fe.monsters[0]
		var gor: Character = fe.monsters[1]
		checks.append(["Cultist (real base Spellcaster (Chaos) trait) got the Tier 3 Channelling bonus (10+30=40)", int(cultist.skill_advances.get("Channelling (Chaos)", -1)) == 40])
		checks.append(["Cultist also got the matching Language (Magick) bonus", int(cultist.skill_advances.get("Language (Magick)", -1)) == 40])
		checks.append(["Gor (Spellcaster is only OPTIONAL for it, not active) got NO Channelling/Language (Magick) bonus", not gor.skill_advances.has("Language (Magick)") and not gor.skill_advances.keys().any(func(k): return str(k).begins_with("Channelling"))])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Monster Spellcaster Bonus): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
