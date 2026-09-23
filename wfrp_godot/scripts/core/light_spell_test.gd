extends RefCounted
class_name LightSpellTest
## Per the request ("Lets make Light petty spell function like a Lamp,
## when cast add it to the top of the turn order with number of
## remaining turns (1 min per round), recasting will refresh the
## duration/counter"):
##
## Confirms casting Light sets Character.light_spell_rounds_remaining to
## the caster's own current Willpower value (the spell's real "Willpower
## minutes" duration, read as Rounds under this project's 1-Round-per-
## minute convention); that has_active_light_source()/
## get_active_light_radius_tiles() both recognise an active Light spell
## as a genuine light source (radius LIGHT_SPELL_RADIUS_TILES) with no
## item equipped at all, and correctly combine with a real equipped
## light-source item (whichever reaches further wins, not one silently
## overriding the other); that tick_active_buffs() (the same per-Round
## hook every other timed buff already uses) counts it down by exactly
## 1 per call and it goes fully dark once it hits 0; that recasting
## resets the counter to a fresh full value rather than adding to
## whatever was left; and that FieldEncounterScreen's own turn order
## panel shows a dedicated "💡 <name>'s Light — N" row pinned above the
## normal combatant rows for as long as it's active, gone once it
## expires.
##
## Extended for the follow-up request ("light (petty spell) should be
## 20 yards by default and should have the same bright/dim/out options
## as lamps"): the spell's own default ("bright") radius moved from a
## Candle-equivalent 10 up to a Lantern-equivalent 20 — see
## Character.LIGHT_SPELL_RADIUS_TILES's own comment — and it now has a
## genuine 3-way light_spell_mode ("bright"/"dim"/"out", independent of
## light_mode which is for an equipped item) that FieldEncounterScreen
## exposes as three buttons in the Magic / Prayers action column.
## Additional coverage below: a fresh cast always starts "bright";
## "dim" drops the radius to LIGHT_SPELL_RADIUS_TILES_LOW; "out" drops
## it to 0 and turns has_active_light_source() itself false (mirroring
## a lamp switched "off") WITHOUT resetting light_spell_rounds_remaining
## — the spell keeps ticking down even while hooded; recasting while
## dim/out resets back to "bright"; and the bright/dim/out toggle
## correctly coexists with a real equipped light-source item exactly
## like the original radius-only coexistence check did.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Spell data sanity ------------------------------------------------
	var light_spell: SpellDefinition = GameData.spell_db.find_by_name("Light")
	checks.append(["Light spell exists in the spell database", light_spell != null])
	if light_spell == null:
		print("RESULT (Light Spell): SETUP FAILED (no Light spell)")
		return false
	checks.append(["Light is a Petty spell with CN 0", light_spell.spell_type == "Petty" and light_spell.casting_number == 0])
	checks.append(["Light targets the caster (\"You\"/\"You\")", light_spell.range_text == "You" and light_spell.target_text == "You"])

	## --- Live encounter setup ----------------------------------------------
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "Aldric"
	pc.equipped_weapon = "Sword"
	pc.known_spells = ["Light"]

	GameState.pending_encounter_monster_names = ["Giant Rat"]

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(5):
		await tree.process_frame

	checks.append(["setup: ally present in the encounter", fe.encounter.get_living("ally").size() == 1])
	checks.append(["setup: monster present in the encounter", fe.encounter.get_living("adversary").size() == 1])
	if fe.encounter.get_living("ally").size() != 1 or fe.encounter.get_living("adversary").size() != 1:
		fe.queue_free()
		for i in range(3): await tree.process_frame
		print("RESULT (Light Spell): SETUP FAILED")
		return false

	var caster: Character = fe.player
	var wp: int = caster.get_effective_characteristic_value("willpower")
	checks.append(["sanity: caster's Willpower value is a real positive number", wp > 0])
	checks.append(["before casting: no active light source at all", not caster.has_active_light_source()])
	checks.append(["before casting: light_spell_rounds_remaining starts at 0", caster.light_spell_rounds_remaining == 0])

	## Builds a bare, already-succeeded CastResult directly — same
	## approach this project's other tests use to exercise a private
	## mechanical-outcome function without driving the full interactive
	## Casting-Test/Fortune-spend coroutine (_on_cast_spell) end to end,
	## which would require controlling real dice rolls to guarantee a
	## deterministic success.
	var make_success_result := func() -> MagicResolver.CastResult:
		var test_result := TestResolver.TestResult.new()
		test_result.success = true
		test_result.roll = 30
		test_result.target = 60
		test_result.success_levels = 3
		var cast_result := MagicResolver.CastResult.new()
		cast_result.success = true
		cast_result.test_result = test_result
		return cast_result

	## --- Casting sets the counter to the caster's own Willpower --------
	fe._apply_cast_spell_outcome(make_success_result.call(), light_spell, "Light", caster, false)
	checks.append(["casting Light sets light_spell_rounds_remaining to the caster's Willpower", caster.light_spell_rounds_remaining == wp])
	checks.append(["casting Light makes has_active_light_source() true with nothing equipped", caster.has_active_light_source()])
	checks.append(["a fresh cast always starts \"bright\"", caster.light_spell_mode == "bright"])
	checks.append(["casting Light grants the spell's own bright radius (20 yards) with nothing equipped", caster.get_active_light_radius_tiles() == Character.LIGHT_SPELL_RADIUS_TILES])
	checks.append(["sanity: the spell's bright radius really is 20", Character.LIGHT_SPELL_RADIUS_TILES == 20])

	## --- Bright/Dim/Out toggle ------------------------------------------
	caster.light_spell_mode = "dim"
	checks.append(["\"dim\" drops the radius to LIGHT_SPELL_RADIUS_TILES_LOW", caster.get_active_light_radius_tiles() == Character.LIGHT_SPELL_RADIUS_TILES_LOW])
	checks.append(["sanity: the dim radius (10) is genuinely lower than bright (20)", Character.LIGHT_SPELL_RADIUS_TILES_LOW < Character.LIGHT_SPELL_RADIUS_TILES])
	checks.append(["still a genuine active light source while dim", caster.has_active_light_source()])
	caster.light_spell_mode = "out"
	checks.append(["\"out\" makes has_active_light_source() false, same as a lamp switched off", not caster.has_active_light_source()])
	checks.append(["\"out\" drops the radius to 0", caster.get_active_light_radius_tiles() == 0])
	checks.append(["\"out\" does NOT reset the duration counter -- the spell keeps ticking, it just stops shining", caster.light_spell_rounds_remaining == wp])
	caster.tick_active_buffs()
	checks.append(["a Round tick while \"out\" still counts down normally", caster.light_spell_rounds_remaining == wp - 1])
	fe._apply_cast_spell_outcome(make_success_result.call(), light_spell, "Light", caster, false)
	checks.append(["recasting while \"out\" resets both the counter AND the mode back to bright", caster.light_spell_rounds_remaining == wp and caster.light_spell_mode == "bright"])

	## --- Turn order panel shows the pinned row while active -------------
	fe._render_status()
	await tree.process_frame   ## _clear() uses queue_free(), deferred to end of frame
	var found_light_row := false
	for child in fe.turn_order_list.get_children():
		for grandchild in child.get_children():
			if grandchild is Label and grandchild.text.begins_with("💡") and grandchild.text.contains("Aldric") and grandchild.text.contains(str(wp)):
				found_light_row = true
	checks.append(["turn order panel shows a pinned \"💡 Aldric's Light — N\" row with the fresh count", found_light_row])

	## --- Ticking counts down by exactly 1 per Round, alongside every
	## other timed buff (same tick_active_buffs() call) ------------------
	caster.tick_active_buffs()
	checks.append(["one Round tick reduces the counter by exactly 1", caster.light_spell_rounds_remaining == wp - 1])
	caster.tick_active_buffs()
	checks.append(["a second Round tick reduces it by 1 more", caster.light_spell_rounds_remaining == wp - 2])

	## --- Recasting REFRESHES rather than stacks -------------------------
	fe._apply_cast_spell_outcome(make_success_result.call(), light_spell, "Light", caster, false)
	checks.append(["recasting resets the counter to a fresh full Willpower value, not additive on top of the remainder", caster.light_spell_rounds_remaining == wp])

	## --- Runs all the way out: goes fully dark at 0 ---------------------
	for i in range(wp):
		caster.tick_active_buffs()
	checks.append(["ticking down to 0 leaves nothing remaining", caster.light_spell_rounds_remaining == 0])
	checks.append(["at 0, has_active_light_source() is false again with nothing equipped", not caster.has_active_light_source()])
	checks.append(["at 0, get_active_light_radius_tiles() is back to 0", caster.get_active_light_radius_tiles() == 0])

	fe._render_status()
	await tree.process_frame   ## _clear() uses queue_free(), deferred to end of frame
	var still_found := false
	for child in fe.turn_order_list.get_children():
		for grandchild in child.get_children():
			if grandchild is Label and grandchild.text.begins_with("💡"):
				still_found = true
	checks.append(["turn order panel's Light row is gone once the spell has expired", not still_found])

	## --- Coexists correctly with a real equipped light-source item:
	## whichever radius reaches further wins, neither silently overrides
	## the other. Light's own bright radius (20) now matches a Lantern's
	## own bright radius (20) exactly (see LIGHT_SPELL_RADIUS_TILES's own
	## comment on why), so this uses the Lantern's "low" mode (radius 10)
	## to keep a genuinely distinguishing "which one reaches further"
	## case, rather than the two always tying. -----------------------
	caster.inventory.append("Lantern")
	caster.equipped_offhand = "Lantern"
	caster.light_mode = "low"
	caster.light_fuel_minutes = 240.0
	var lantern: ItemDefinition = GameData.item_db.find_by_name("Lantern")
	checks.append(["sanity: Lantern's own bright radius (20) matches the Light spell's own bright radius exactly", lantern.light_radius_tiles == Character.LIGHT_SPELL_RADIUS_TILES])
	checks.append(["sanity: Lantern's own low radius (10) is lower than the Light spell's bright radius", lantern.light_radius_tiles_low < Character.LIGHT_SPELL_RADIUS_TILES])
	checks.append(["Lantern alone on low (no Light spell active) lights at its own low radius", caster.get_active_light_radius_tiles() == lantern.light_radius_tiles_low])

	fe._apply_cast_spell_outcome(make_success_result.call(), light_spell, "Light", caster, false)
	checks.append(["Light spell (bright, 20) + a dimmed Lantern (low, 10): the Light spell's own bigger radius wins", caster.get_active_light_radius_tiles() == Character.LIGHT_SPELL_RADIUS_TILES])

	caster.light_mode = "on"
	checks.append(["Lantern switched to its own full bright (20): ties with the Light spell's bright radius (20), still correctly active", caster.get_active_light_radius_tiles() == lantern.light_radius_tiles])

	caster.light_spell_mode = "out"
	checks.append(["Light spell hooded (\"out\") but Lantern lit: the Lantern's own radius still lights the way", caster.get_active_light_radius_tiles() == lantern.light_radius_tiles])
	checks.append(["Light spell hooded but Lantern lit: still a genuine active light source", caster.has_active_light_source()])

	caster.light_mode = "off"
	checks.append(["Lantern switched off AND Light spell hooded: no active light source at all", not caster.has_active_light_source()])
	checks.append(["...and the radius is correctly 0", caster.get_active_light_radius_tiles() == 0])

	caster.light_spell_mode = "bright"
	checks.append(["Lantern switched off but Light spell back to bright: the still-active Light spell's own radius takes over", caster.get_active_light_radius_tiles() == Character.LIGHT_SPELL_RADIUS_TILES])
	checks.append(["Lantern switched off but Light spell active: still a genuine active light source", caster.has_active_light_source()])

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
	print("RESULT (Light Spell): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
