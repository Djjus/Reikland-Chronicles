extends RefCounted
class_name ChannellingPartialCnReductionTest
## Real bug fix, per the report ("channelling should reduce the CN by
## the channelling SL, this should work for partial CN reduction as
## well and to CN 0"): MagicResolver.is_channelled_for() (and every
## caller of it in field_encounter_screen.gd) used to only ever pay off
## once accumulated Channelling SL reached a spell's FULL Casting
## Number — a Fire wizard who'd channelled 6 SL got ZERO benefit
## casting a CN 10 spell (Great Fires of U'Zhul), when the book's own
## rule (p.237) is a plain 1-for-1 reduction, partial or full: 6 SL
## should knock CN 10 down to CN 4, not do nothing at all.
##
## Covers the new MagicResolver.channelled_cn_reduction() directly, and
## field_encounter_screen.gd's own _get_effective_cn() (the same
## function both the real cast flow and the War Wizard CN<=5
## eligibility check now share) against a live FieldEncounter.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- MagicResolver.channelled_cn_reduction() direct checks ---------
	var bolt: SpellDefinition = GameData.spell_db.find_by_name("Bolt")           ## CN 4
	var great_fires: SpellDefinition = GameData.spell_db.find_by_name("Great Fires of U'Zhul")  ## CN 10
	var light: SpellDefinition = GameData.spell_db.find_by_name("Light")         ## Petty, CN 0

	var partial := MagicResolver.ChannellingProgress.new()
	partial.accumulated_sl = 6
	checks.append(["THE FIX: 6 SL partially reduces a CN 10 spell by 6 (not 0)", MagicResolver.channelled_cn_reduction(partial, great_fires) == 6])
	checks.append(["6 SL fully covers (caps at) a CN 4 spell — reduction never exceeds the spell's own CN", MagicResolver.channelled_cn_reduction(partial, bolt) == 4])
	checks.append(["Petty spells never benefit from Channelling, partial or full", MagicResolver.channelled_cn_reduction(partial, light) == 0])

	var zero := MagicResolver.ChannellingProgress.new()
	checks.append(["0 SL accumulated: no reduction at all", MagicResolver.channelled_cn_reduction(zero, great_fires) == 0])

	var crit := MagicResolver.ChannellingProgress.new()
	crit.critical_ready = true
	checks.append(["Critical Channel grants the FULL reduction outright, regardless of accumulated_sl", MagicResolver.channelled_cn_reduction(crit, great_fires) == great_fires.casting_number])

	## --- field_encounter_screen.gd's _get_effective_cn() ----------------
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "Aes"
	pc.talents_taken["Arcane Magic (Fire)"] = 1
	pc.known_spells = ["Bolt", "Great Fires of U'Zhul"]

	GameState.pending_encounter_monster_names = ["Giant Rat"]
	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(5):
		await tree.process_frame

	fe._channelling_progress["Fire"] = partial   ## reuse the same 6-SL progress from above

	checks.append(["THE FIX: _get_effective_cn partially reduces Great Fires of U'Zhul (CN 10) to CN 4 with 6 SL channelled", fe._get_effective_cn(great_fires) == 4])
	checks.append(["_get_effective_cn fully zeroes out Bolt (CN 4) with 6 SL channelled (capped, not negative)", fe._get_effective_cn(bolt) == 0])

	fe._channelling_progress["Fire"] = zero
	checks.append(["with 0 SL channelled, _get_effective_cn returns the spell's own full, undiscounted CN", fe._get_effective_cn(great_fires) == great_fires.casting_number])

	fe._channelling_progress["Fire"] = crit
	checks.append(["a Critical Channel makes _get_effective_cn return 0 for any spell of that Lore", fe._get_effective_cn(great_fires) == 0])

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
	print("RESULT (Channelling Partial CN Reduction): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
