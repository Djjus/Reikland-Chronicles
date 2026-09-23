extends RefCounted
class_name LightSpellInstantRevealTest
## Regression test for the report ("when casting light and succeeding,
## add the light to the map instantly, right now the character has to
## move before it comes on"):
##
## Root cause: _apply_cast_spell_outcome()'s Light branch set
## light_spell_rounds_remaining/light_spell_mode on the Character but
## never told the dungeon's fog-of-war system anything had changed. The
## screen's own _render_status() (called right after by the real cast
## handler) doesn't recompute fog-of-war itself either -- it just pushes
## whatever battle_grid.fog_of_war ALREADY contains to the grid view.
## The only thing that ever recomputed fog-of-war was _reveal_around_
## party() -> _commit_visibility_from_centers(), and nothing called it
## after a successful Light cast, so the bigger radius only actually
## appeared once some UNRELATED later action (a Move) happened to call
## _reveal_around_party() itself for its own reasons.
##
## Fixed by both the cast-outcome branch and the new Bright/Dim/Out
## mode-toggle buttons (see field_encounter_screen.gd's own comments at
## each call site) now calling _reveal_around_party() themselves,
## immediately, mirroring the exact pattern _on_toggle_light_pressed()
## (the equipped-lamp Free Action toggle) already used correctly.
##
## This test proves the fix two ways for each trigger (the initial cast,
## and the Dim mode-toggle button): (1) the resulting battle_grid.fog_of_
## war, captured immediately with no manual _reveal_around_party()/
## _render_status() call of the test's own in between, is BIT-FOR-BIT
## IDENTICAL to what a full manual _reveal_around_party() recompute
## produces right afterward -- proving the automatic update already
## did the complete, correct job, not a stale or partial one; and (2)
## that recompute is itself genuinely DIFFERENT from the state
## immediately before the trigger fired -- proving the scenario is not
## vacuous (the Light spell's radius really did change what's visible).
## Dictionary content is compared via .hash(), the same pattern this
## project's other tests already use for whole-dictionary comparisons
## (see GoblinFortAlwaysFreshTest).

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []
	await tree.process_frame
	await tree.process_frame

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var no_pool: Array[String] = []
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	GameState.dungeon_state = {}
	GameState.pending_dungeon_theme_id = "sewer"
	GameState.dungeon_entry_requested = true

	var pc: Character = GameState.player_character
	pc.character_name = "Aldric"
	pc.known_spells = ["Light"]

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(8):
		await tree.process_frame

	checks.append(["setup: FieldEncounter actually entered dungeon exploration", fe._exploration_mode])
	if not fe._exploration_mode or fe.battle_grid == null:
		fe.queue_free()
		for i in range(3): await tree.process_frame
		print("RESULT (Light Spell Instant Reveal): SETUP FAILED")
		return false

	var caster: Character = fe.player
	var light_spell: SpellDefinition = GameData.spell_db.find_by_name("Light")
	checks.append(["setup: Light spell exists", light_spell != null])
	checks.append(["setup: no active light source before casting", not caster.has_active_light_source()])

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

	## --- Trigger 1: the cast itself ------------------------------------
	var fog_before_cast: int = fe.battle_grid.fog_of_war.duplicate(true).hash()

	fe._apply_cast_spell_outcome(make_success_result.call(), light_spell, "Light", caster, false)
	checks.append(["setup: casting Light actually activated it", caster.light_spell_rounds_remaining > 0 and caster.has_active_light_source()])

	## Captured with NO manual _reveal_around_party()/_render_status()
	## call of this test's own in between -- exactly the "character
	## hasn't moved yet" moment the report describes.
	var fog_immediately_after_cast: int = fe.battle_grid.fog_of_war.duplicate(true).hash()

	fe._reveal_around_party()   ## the "ground truth" full recompute
	var fog_after_manual_recompute: int = fe.battle_grid.fog_of_war.duplicate(true).hash()

	checks.append(["sanity: the Light spell's radius genuinely changed what's visible (recompute differs from before the cast)",
		fog_after_manual_recompute != fog_before_cast])
	checks.append(["THE FIX: casting Light already left fog_of_war exactly as a full recompute would, with no Move needed first",
		fog_immediately_after_cast == fog_after_manual_recompute])

	## --- Trigger 2: the Bright/Dim/Out mode-toggle buttons -------------
	fe._render_turn_action_menu()
	for i in range(2):
		await tree.process_frame
	var dim_btn: Button = _find_button_with_text(fe.target_container, "Dim")
	checks.append(["setup: found the real 'Dim' light-mode button", dim_btn != null])
	if dim_btn != null:
		var fog_before_toggle: int = fe.battle_grid.fog_of_war.duplicate(true).hash()

		dim_btn.pressed.emit()
		for i in range(2):
			await tree.process_frame

		checks.append(["pressing 'Dim' actually switched the mode", caster.light_spell_mode == "dim"])
		var fog_immediately_after_toggle: int = fe.battle_grid.fog_of_war.duplicate(true).hash()

		fe._reveal_around_party()
		var fog_after_toggle_recompute: int = fe.battle_grid.fog_of_war.duplicate(true).hash()

		checks.append(["sanity: switching Bright -> Dim genuinely shrinks the lit area (recompute differs from before the toggle)",
			fog_after_toggle_recompute != fog_before_toggle])
		checks.append(["THE FIX: pressing 'Dim' already left fog_of_war exactly as a full recompute would, with no Move needed first",
			fog_immediately_after_toggle == fog_after_toggle_recompute])

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
	print("RESULT (Light Spell Instant Reveal): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass

static func _find_button_with_text(root: Node, label: String) -> Button:
	for child in root.get_children():
		if child is Button and String(child.text) == label:
			return child
		if child.get_child_count() > 0:
			var found: Button = _find_button_with_text(child, label)
			if found != null:
				return found
	return null
