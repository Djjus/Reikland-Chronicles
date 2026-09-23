extends RefCounted
class_name BlessingOvercastTest
## Regression test for the request: "blessings should allow overcast like
## spending on additional friendly targets (cost 2 SL), and multiply
## duration by x2/3/4/5..etc for 2 SL per stage."
##
## Before this: _apply_prayer_buff_effect() auto-spent EVERY point of a
## successful Blessing's own SL on Duration alone (a flat +6 Rounds per
## +2 SL, per the book's own "Success Levels in Combat / Blessings" rule
## — see that function's old header comment) with no player choice and
## no way to spend SL on extra targets at all. Now:
## - _apply_prayer_buff_effect() only ever applies the prayer's own BASE
##   Duration (no SL spent there any more).
## - A new _offer_blessing_overcast() offers the leftover SL as an actual
##   choice, same "Confirm/Skip" picker shape _offer_overcasting() already
##   uses for spells: Targets (RAW, +1 friendly recipient per 2 SL) and
##   Duration (a deliberate house-rule departure from RAW's own flat
##   +6/stage — this project's own version instead MULTIPLIES the base
##   Duration, x2/x3/x4/x5... per 2-SL stage, exactly as requested).
##
## Drives _apply_prayer_buff_effect() and _offer_blessing_overcast()
## directly against a real FieldEncounter fixture with two extra living
## party members (so the Targets column has real candidates to pick from)
## — same "call the resolver function directly, bypass the full cast-UI
## flow" technique overcast_aoe_card_fold_test.gd already uses for the
## spell counterpart.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []
	await tree.process_frame
	await tree.process_frame

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "OvercastAes"

	## Two extra living party members — real Targets-column candidates.
	var ally1 := Character.new()
	ally1.character_name = "OvercastElrohir"
	ally1.race = pc.race
	ally1.characteristics = pc.characteristics.duplicate()
	ally1.wounds_max = 10
	ally1.wounds_current = 10
	var ally2 := Character.new()
	ally2.character_name = "OvercastFredi"
	ally2.race = pc.race
	ally2.characteristics = pc.characteristics.duplicate()
	ally2.wounds_max = 10
	ally2.wounds_current = 10
	if GameState.party.size() < 3:
		GameState.party.append(ally1)
		GameState.party.append(ally2)

	GameState.current_field_difficulty_tier = 0
	GameState.dungeon_state = {}
	GameState.dungeon_floor_states = {}
	GameState.pending_dungeon_theme_id = "sewer"
	GameState.dungeon_entry_requested = true

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(8):
		await tree.process_frame

	checks.append(["setup: FieldEncounter entered exploration mode with a live encounter", fe._exploration_mode and fe.encounter != null])
	checks.append(["setup: both extra party members are genuine living allies", fe.encounter != null and fe.encounter.get_living("ally").has(ally1) and fe.encounter.get_living("ally").has(ally2)])
	if not fe._exploration_mode or fe.encounter == null or not fe.encounter.get_living("ally").has(ally1):
		fe.queue_free()
		for i in range(3): await tree.process_frame
		print("RESULT (Blessing Overcast): SETUP FAILED")
		return false

	## fe.player rotates to whichever party member's Turn is currently
	## active (this is a real multi-character party, not a fixed solo
	## protagonist — see field_encounter_screen.gd's own "player =
	## GameState.player_character" reassignment at the top of each
	## Turn), and by the time exploration mode has settled a few frames
	## in, that could genuinely be pc, ally1, OR ally2 depending on
	## initiative. Pinning it explicitly to `pc` before every direct
	## call below (rather than trusting whatever it happens to already
	## be) keeps this test's expectations deterministic regardless of
	## turn order/dice — the caster is always `target`, and the two
	## OTHER party members are always its Targets-column candidates.
	var target: Character = pc
	fe.player = target
	var candidates: Array = [ally1, ally2]

	## --- _apply_prayer_buff_effect() now applies ONLY the base Duration,
	## no SL involved at all -----------------------------------------
	var buff_shape: Dictionary = fe._apply_prayer_buff_effect("Blessing of Battle", target)
	checks.append(["THE FIX: _apply_prayer_buff_effect() applies the base Duration (6 Rounds) with no SL parameter any more", buff_shape.get("rounds", -1) == 6])
	checks.append(["the base buff was genuinely applied to the target's own active_buffs", target.active_buffs.size() == 1 and target.active_buffs[0]["rounds_remaining"] == 6])
	checks.append(["buff_shape carries the exact characteristic_bonuses add_timed_buff() used", buff_shape.get("characteristic_bonuses", {}) == {"weapon_skill": 10}])

	## --- _offer_blessing_overcast() with sl < 2: nothing to spend, no
	## picker opens at all -----------------------------------------------
	fe._offer_blessing_overcast("Blessing of Battle", target, 1, buff_shape)
	for i in range(3): await tree.process_frame
	checks.append(["sl < 2 (no full stage affordable): no Overcast picker opens", not fe.awaiting_overcast_choice])

	## --- Real spend: sl=5 -> 2 full stages (4 SL) affordable, 1 SL
	## unspendable and left on the table. Duration: 1 stage (x2). Targets:
	## 1 stage (+1 target, ally1 chosen). Total spend 4 of 5 SL. -------
	fe.player = target
	fe._offer_blessing_overcast("Blessing of Battle", target, 5, buff_shape)
	for i in range(3): await tree.process_frame
	checks.append(["setup: the Overcast picker is genuinely open", fe.awaiting_overcast_choice])

	var duration_picker: OptionButton = null
	var target_picker: OptionButton = null
	var pickers := _find_option_buttons(fe.target_container)
	if pickers.size() >= 1:
		duration_picker = pickers[0]
	if pickers.size() >= 2:
		target_picker = pickers[1]
	checks.append(["setup: both a Duration and a Targets dropdown were offered (2 living ally candidates exist)", duration_picker != null and target_picker != null])
	checks.append(["setup: the Duration dropdown offers up to 2 stages (skip, x2, x3) for 5 SL", duration_picker != null and duration_picker.item_count == 3])
	checks.append(["setup: the Targets dropdown offers up to 2 (skip, +1, +2) — capped by 2 real ally candidates", target_picker != null and target_picker.item_count == 3])

	var ally1_button: Button = _find_button_named(fe.target_container, ally1.character_name)
	checks.append(["setup: a real toggle button for the ally1 candidate was offered", ally1_button != null])

	if duration_picker != null:
		duration_picker.selected = 1   ## 2 SL -> x2 Duration
		duration_picker.item_selected.emit(1)
	if target_picker != null:
		target_picker.selected = 1   ## 2 SL -> +1 Target
		target_picker.item_selected.emit(1)
	if ally1_button != null:
		ally1_button.button_pressed = true
		ally1_button.pressed.emit()

	if is_instance_valid(fe._active_overcast_confirm_button):
		fe._active_overcast_confirm_button.pressed.emit()
	for i in range(3): await tree.process_frame
	checks.append(["cleanup: the Overcast prompt closed after a valid confirm", not fe.awaiting_overcast_choice])

	checks.append(["THE FIX: the original target's own buff Duration was MULTIPLIED (6 base x2 = 12), not flat-added-to", target.active_buffs.size() == 1 and target.active_buffs[0]["rounds_remaining"] == 12])
	checks.append(["THE FIX: the chosen extra target (ally1) now carries the SAME Blessing, at the SAME multiplied Duration (12)", ally1.active_buffs.size() == 1 and ally1.active_buffs[0]["name"] == "Blessing of Battle" and ally1.active_buffs[0]["rounds_remaining"] == 12])
	checks.append(["the extra target's buff carries the identical characteristic_bonuses as the original", ally1.active_buffs[0]["characteristic_bonuses"] == {"weapon_skill": 10}])
	checks.append(["the NON-chosen candidate (ally2) got nothing — Targets spend is exact, not automatic for every ally", ally2.active_buffs.is_empty()])

	## --- Overspend / mismatched-candidate-count guards: confirm refuses,
	## picker stays open, nothing is applied -----------------------------
	target.active_buffs.clear()
	ally1.active_buffs.clear()
	fe.player = target
	var buff_shape2: Dictionary = fe._apply_prayer_buff_effect("Blessing of Battle", target)
	fe._offer_blessing_overcast("Blessing of Battle", target, 3, buff_shape2)
	for i in range(3): await tree.process_frame
	var pickers2 := _find_option_buttons(fe.target_container)
	var target_picker2: OptionButton = pickers2[1] if pickers2.size() >= 2 else null
	if target_picker2 != null:
		target_picker2.selected = 1   ## claims "+1 Target" (2 SL)...
		target_picker2.item_selected.emit(1)
	## ...but no candidate button is actually toggled on, so 0 targets are
	## really selected — a mismatch the confirm handler must catch.
	if is_instance_valid(fe._active_overcast_confirm_button):
		fe._active_overcast_confirm_button.pressed.emit()
	for i in range(2): await tree.process_frame
	checks.append(["a Targets spend with no matching candidate picked is refused — picker stays open", fe.awaiting_overcast_choice])
	checks.append(["nothing was applied while the mismatch is unresolved", target.active_buffs.size() == 1 and target.active_buffs[0]["rounds_remaining"] == 6])

	## Skip out of this still-open picker cleanly for teardown.
	if is_instance_valid(fe._active_overcast_skip_button):
		fe._active_overcast_skip_button.pressed.emit()
	for i in range(2): await tree.process_frame

	## --- A prayer with a non-flat base Duration (Sigmar's Fiery Hammer,
	## Fellowship Bonus Rounds) still multiplies correctly off ITS OWN
	## base, not a hardcoded 6 -------------------------------------------
	target.active_buffs.clear()
	target.characteristics.fellowship = 30   ## FB 3
	fe.player = target
	var hammer_shape: Dictionary = fe._apply_prayer_buff_effect("Sigmar's Fiery Hammer", target)
	checks.append(["setup: Fiery Hammer's own base Duration is Fellowship Bonus Rounds (3), not a flat 6", hammer_shape.get("rounds", -1) == 3])
	fe.player = target
	fe._offer_blessing_overcast("Sigmar's Fiery Hammer", target, 2, hammer_shape)
	for i in range(3): await tree.process_frame
	if is_instance_valid(fe._active_overcast_confirm_button):
		var pickers3 := _find_option_buttons(fe.target_container)
		if pickers3.size() >= 1:
			pickers3[0].selected = 1   ## 2 SL -> x2 Duration
			pickers3[0].item_selected.emit(1)
		fe._active_overcast_confirm_button.pressed.emit()
	for i in range(3): await tree.process_frame
	checks.append(["THE FIX: Fiery Hammer's Duration multiplies off ITS OWN base (3 x2 = 6), confirming this isn't hardcoded to Blessings' flat 6", target.active_buffs.size() == 1 and target.active_buffs[0]["rounds_remaining"] == 6])
	checks.append(["Fiery Hammer's damage_bonus is preserved through the Overcast step untouched", target.active_buffs[0]["damage_bonus"] == 3])

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
	print("RESULT (Blessing Overcast): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass

## Depth-first search collecting every OptionButton under `root`, in
## the order encountered — the Overcast column nests a couple of plain
## Container layers deep, same shape overcast_aoe_card_fold_test.gd's own
## _find_option_button already navigates for the single-picker case.
static func _find_option_buttons(root: Node) -> Array:
	var found: Array = []
	if root is OptionButton:
		found.append(root)
	for child in root.get_children():
		found.append_array(_find_option_buttons(child))
	return found

## Depth-first search for a Button whose text matches `name` exactly —
## the Targets column's own per-candidate toggle buttons.
static func _find_button_named(root: Node, button_text: String) -> Button:
	if root is Button and root.text == button_text:
		return root
	for child in root.get_children():
		var found: Button = _find_button_named(child, button_text)
		if found != null:
			return found
	return null
