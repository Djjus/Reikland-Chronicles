extends RefCounted
class_name ChannellingPersistsAcrossRoundsTest
## Real fix, per the follow-up ("note that channelling is accumulative,
## and lasts longer then the next round.."): the player-facing
## Channelling notices used to phrase the CN discount as good only
## "next Round," mirroring p.237's own wording. But the actual
## implementation (a deliberate earlier decision — see
## _channelling_progress's own declaration comment and
## _on_cast_spell/_on_cast_spell_aoe's `_channelling_progress.clear()`)
## never expires accumulated SL just because a Round passed: it keeps
## building for as many Rounds as the player keeps Channelling, and
## stays fully available whenever they eventually cast — the ONLY thing
## that clears it is an actual cast attempt (any spell, success or
## fail). This suite proves that's genuinely true in the running game,
## not just described that way in a comment, and confirms
## MagicResolver.channel_round() itself is additive across repeated
## calls rather than replacing the running total each time.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "Aes"
	pc.talents_taken["Arcane Magic (Fire)"] = 1
	pc.skill_advances["Channelling (Fire)"] = 100   ## near-guaranteed success below, only the genuine Fumble rule can still zero it

	GameState.pending_encounter_monster_names = ["Giant Rat"]
	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(5):
		await tree.process_frame

	## --- THE FIX: passing Rounds alone never expires progress ----------
	var progress := MagicResolver.ChannellingProgress.new()
	progress.accumulated_sl = 5
	fe._channelling_progress["Fire"] = progress
	pc.tick_active_buffs()
	pc.tick_active_buffs()
	pc.tick_active_buffs()
	checks.append(["THE FIX: 3 Rounds ticking by with no cast attempt does not clear or reduce accumulated Channelling SL", fe._channelling_progress.has("Fire") and fe._channelling_progress["Fire"].accumulated_sl == 5])
	checks.append(["it's still the exact same progress object -- not silently replaced by a fresh one", fe._channelling_progress["Fire"] == progress])

	## --- _get_effective_cn() still sees the full benefit after those --
	## same 3 Rounds passed -- not just describing persistence, actually
	## still applying it at cast time.
	var great_fires: SpellDefinition = GameData.spell_db.find_by_name("Great Fires of U'Zhul")   ## CN 10
	checks.append(["the CN discount is still fully live after those 3 Rounds (CN 10 -> CN 5 with 5 SL)", fe._get_effective_cn(great_fires) == 5])

	## --- channel_round() accumulates on top of an existing total, it
	## does not overwrite it -----------------------------------------------
	var accum_progress := MagicResolver.ChannellingProgress.new()
	var saw_accumulation := false
	for attempt in range(40):
		var before: int = accum_progress.accumulated_sl
		if accum_progress.critical_ready:
			break   ## a Critical short-circuits accumulation entirely -- not what this check is about
		var result: Dictionary = MagicResolver.channel_round(pc, accum_progress, "Fire", 0, false)
		if result["test_result"].is_fumble:
			continue   ## the existing, unrelated Fumble rule genuinely does reset it to 0 -- not what this test is about
		if before > 0 and result["test_result"].success and not accum_progress.critical_ready:
			checks.append(["THE FIX: a later successful Channelling Test adds to the existing total instead of replacing it", accum_progress.accumulated_sl == before + result["test_result"].success_levels])
			saw_accumulation = true
			break
	checks.append(["setup: got a genuine second-success-on-top-of-a-first accumulation step to actually check", saw_accumulation])

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
	print("RESULT (Channelling Persists Across Rounds): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
