extends RefCounted
class_name EndTurnWasdFocusNoTargetTest
## Regression test for the follow-up request ("when a character has used
## his move and is not targeting a enemy monster, make End Turn the WASD
## focus"), reported with 2 screenshots: a ranged-weapon character (Eric
## Troller — Hunter) with Move exhausted (0 sq) and zero monsters around
## (pure exploration), showing Sprint apparently holding keyboard focus
## instead of End Turn.
##
## ROOT CAUSE (confirmed by reading _render_turn_action_menu()):
## melee_stuck_out_of_range only ever covers a MELEE weapon that can't
## reach any living enemy this turn — `not weapon.is_ranged` short-
## circuits it to false unconditionally for a ranged weapon, regardless
## of whether there's actually anything to shoot at. So a ranged
## character with genuinely nothing to act against (no monsters at all
## yet, or nothing within this weapon's own range bands) never got End
## Turn as the default Enter/WASD-focus target, falling through to
## whatever button happened to be first in tree order instead (Sprint,
## once Move itself is disabled) via _auto_focus_default_button()'s own
## _find_first_focusable() fallback.
##
## THE FIX: a new no_target_to_act_against flag mirrors melee_stuck_out_
## of_range for the ranged case, via the same _targets_in_weapon_range()
## already used to gate the Attack button itself — End Turn now claims
## the Enter hotkey/default focus (_active_primary_hotkey_button)
## whenever there's genuinely nothing to act against, regardless of
## weapon type.
##
## Case 1 (THE BUG — ranged weapon, zero monsters, pure exploration): a
## ranged-weapon character with Move exhausted gets End Turn as the real
## Enter-hotkey/WASD-focus default, not Sprint or anything else.
## Case 2 (regression guard): the pre-existing melee-out-of-range case
## still gets End Turn as the default too.
## Case 3 (contrast/regression guard): a ranged-weapon character WITH a
## real, in-range, living target does NOT default to End Turn — Attack
## correctly claims the Enter hotkey instead, same as before this fix.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## Let the initial scene tree finish setting itself up before this
	## test's own add_child(fe) call below — see flight_falling_test.gd's
	## own identical comment for why.
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
	GameState.dungeon_entry_requested = true   ## real dungeon-entry signal, see that field's own header comment

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(6):
		await tree.process_frame

	checks.append(["setup: FieldEncounter actually entered exploration mode", fe._exploration_mode])
	checks.append(["setup: a real battle_grid exists", fe.battle_grid != null])

	var ranged_skill: SkillDefinition = GameData.skill_db.find_by_name("Ranged")
	var elf_bow: WeaponDefinition = GameData.weapon_db.find_by_name("Elf Bow")
	checks.append(["setup: found the real Ranged skill and Elf Bow weapon", ranged_skill != null and elf_bow != null])
	if ranged_skill == null or elf_bow == null:
		print("RESULT (End Turn WASD Focus No Target): SETUP FAILED (missing skill/weapon data)")
		fe.queue_free()
		return false

	## Same Character object fe already uses as fe.player (set up by the
	## real _start_encounter() during scene setup above) — equipped and
	## trained directly, same as charge_ready_arrow_test.gd's own
	## `player.equipped_weapon = "Sword"` pattern.
	var player: Character = fe.player
	player.equipped_weapon = "Elf Bow"
	player.skill_advances[ranged_skill.display_name("Bow")] = 1
	player.inventory.append("Elf Arrow")   ## per AmmoLookup.REQUIRED_AMMO["Bow"] — needed for weapon_has_ammo
	fe.weapons[player] = fe._resolve_weapon(player)
	checks.append(["setup: the player's resolved weapon is genuinely ranged (Elf Bow)", fe.weapons[player].is_ranged])

	fe.awaiting_player_target = true
	fe.action_used_this_turn = false
	fe.movement_remaining = 0
	fe.move_mode_active = false
	fe.sprint_used_this_turn = false
	fe.selected_target = null
	fe._active_primary_hotkey_button = null

	## --- Case 1: THE BUG -- ranged weapon, zero monsters (exploration) --
	fe._render_turn_action_menu()
	for i in range(2):
		await tree.process_frame

	var end_turn_btn: Button = _find_button_containing(fe.target_container, "End Turn")
	checks.append(["Case 1 setup: a real End Turn button exists in the rebuilt menu", end_turn_btn != null])
	if end_turn_btn != null:
		checks.append(["THE FIX: End Turn shows the [Enter] hotkey hint for a ranged character with nothing to shoot at", end_turn_btn.text.find("[Enter]") != -1])
		checks.append(["THE FIX: End Turn (not Sprint or anything else) is the real Enter/WASD-focus default", fe._active_primary_hotkey_button == end_turn_btn])
	var sprint_btn: Button = _find_button_containing(fe.target_container, "Sprint")
	if sprint_btn != null:
		checks.append(["THE BUG: Sprint is genuinely NOT the WASD-focus default any more", fe._active_primary_hotkey_button != sprint_btn])

	## --- Case 2: regression guard -- pre-existing melee-out-of-range case
	player.equipped_weapon = "Sword"
	fe.weapons[player] = fe._resolve_weapon(player)
	checks.append(["Case 2 setup: the player's resolved weapon is genuinely melee (Sword)", not fe.weapons[player].is_ranged])
	fe._active_primary_hotkey_button = null
	fe._render_turn_action_menu()
	for i in range(2):
		await tree.process_frame
	var end_turn_btn_2: Button = _find_button_containing(fe.target_container, "End Turn")
	checks.append(["Case 2: the pre-existing melee-out-of-range case still defaults to End Turn (regression guard)", end_turn_btn_2 != null and fe._active_primary_hotkey_button == end_turn_btn_2])

	## --- Case 3: contrast -- ranged weapon WITH a real, in-range target -
	player.equipped_weapon = "Elf Bow"
	fe.weapons[player] = fe._resolve_weapon(player)
	var entrance: Vector2i = fe.dungeon_state.get("entrance_pos", Vector2i.ZERO)
	fe._spawn_monsters_during_exploration(["Giant Rat"], entrance, null)
	for i in range(3):
		await tree.process_frame
	checks.append(["Case 3 setup: _exploration_mode flips false once a monster is encountered", not fe._exploration_mode])
	var rat: Character = fe.monsters[fe.monsters.size() - 1] if fe.monsters.size() > 0 else null
	checks.append(["Case 3 setup: a real monster genuinely exists", rat != null])
	if rat != null and fe.battle_positions.has(player):
		fe.battle_positions[rat] = fe.battle_positions[player] + Vector2i(1, 0)   ## adjacent -- well within the Elf Bow's own range bands
		fe.selected_target = rat
		fe.action_used_this_turn = false
		fe._active_primary_hotkey_button = null
		fe._render_turn_action_menu()
		for i in range(2):
			await tree.process_frame
		var attack_btn: Button = _find_button_containing(fe.target_container, "Elf Bow")
		checks.append(["Case 3 setup: a real Attack button for the Elf Bow exists", attack_btn != null])
		var end_turn_btn_3: Button = _find_button_containing(fe.target_container, "End Turn")
		checks.append(["Case 3: with a real in-range target, End Turn does NOT claim the Enter/WASD-focus default (Attack does)", end_turn_btn_3 == null or fe._active_primary_hotkey_button != end_turn_btn_3])
		if attack_btn != null:
			checks.append(["Case 3: ...Attack genuinely claims it instead", fe._active_primary_hotkey_button == attack_btn])

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
	print("RESULT (End Turn WASD Focus No Target): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass

## Depth-first search for a Button whose text CONTAINS `substr` anywhere
## under `root` — the real menu nests several plain Container layers deep
## (see _make_action_column), so a fixed-depth check is fragile. Uses
## "contains" rather than exact match since several of these buttons
## carry dynamic suffixes (" [Enter]", " - <roll number>").
static func _find_button_containing(root: Node, substr: String) -> Button:
	for child in root.get_children():
		if child is Button and String(child.text).find(substr) != -1:
			return child
		if child.get_child_count() > 0:
			var found: Button = _find_button_containing(child, substr)
			if found != null:
				return found
	return null
