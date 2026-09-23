extends RefCounted
class_name SprintStuckMenuTest
## Repro/regression test for the user report: "after sprinting, Eric has
## no buttons and is stuck, Im not able to advance the battle." Screenshots
## showed the Attack/Defence/Movement button bar (target_container) totally
## empty right after a successful Sprint's "click within the highlighted
## range to sprint there" prompt appeared.
##
## Root cause: _on_sprint()'s own "highlight the bonus-movement squares
## and wait for the player to click one" branch set up move_mode_active
## and the grid highlight exactly like _enter_move_mode() does — but,
## unlike _enter_move_mode(), never called _prompt_player_turn(false)
## afterward to rebuild the action menu. awaiting_player_target was also
## left false (set at the very top of _on_sprint(), never restored on
## this path), and target_container had already been cleared (both by
## _on_sprint()'s own opening _clear(target_container) and by whatever
## _render_turn_action_menu() call last ran before Sprint was clicked) —
## so the button row was left permanently empty with nothing to click to
## advance the battle, exactly matching the report. Fixed by adding the
## same _prompt_player_turn(false) call _enter_move_mode() already makes,
## right before the early return.
##
## Drives the real production Sprint flow end-to-end (forced roll for a
## deterministic success) via a real FieldEncounter instance, same style
## as critical_wound_deflect_repro_test.gd.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## Let the initial scene tree finish setting itself up before this
	## test's own add_child(fe) call below — see flight_falling_test.gd's
	## own identical comment for why (called from a runner's own
	## _ready(), fired mid-setup of the initial scene, an immediate
	## add_child to tree.get_root() fails with "Parent node is busy
	## setting up children").
	await tree.process_frame
	await tree.process_frame

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "SprintReproTester"
	var no_pool: Array[String] = []
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	GameState.pending_encounter_monster_names = ["Giant Rat"]

	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(5):
		await tree.process_frame

	## Settle any auto-started prompts before touching state directly.
	var quiet_slices := 0
	var waited := 0.0
	while quiet_slices < 8 and waited < 20.0:
		if fe.awaiting_continue:
			fe.awaiting_continue = false
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		var quiet: bool = not fe.awaiting_continue and not fe.awaiting_fortune_choice
		if quiet:
			quiet_slices += 1
		else:
			quiet_slices = 0
		await tree.create_timer(0.25).timeout
		waited += 0.25
	await tree.create_timer(1.0).timeout

	## Force it to genuinely be the player's own turn, with the Action
	## still free and Move already fully spent — Sprint's own real
	## precondition (the button only ever appears once movement_
	## remaining <= 0 — see _render_turn_action_menu).
	fe.player = pc
	fe.awaiting_player_target = true
	fe.action_used_this_turn = false
	fe.movement_remaining = 0
	fe.move_mode_active = false
	fe.sprint_used_this_turn = false
	fe.pending_effort_bonus = 0
	## A real reachable square must exist for the branch under test
	## (the "reachable.is_empty()" early-exit is a different, unrelated
	## code path) — battle_positions/battle_grid should already be real
	## from _setup_battle_grid(), called by the real _start_encounter().
	checks.append(["setup: a real battle_grid exists", fe.battle_grid != null])
	checks.append(["setup: the player has a real battle position", fe.battle_positions.has(pc)])

	## Give the player an overwhelming Agility so the Average(+20)
	## Athletics Test is a guaranteed success (clamped target 100 — see
	## TestResolver.resolve()) regardless of the real, unforced roll —
	## exercises the exact "successful Sprint with real bonus squares"
	## case from the bug report, not a contrived forced-roll shortcut.
	pc.characteristics.set_value("agility", 500)

	fe._on_sprint()
	## _on_sprint() awaits _offer_fortune_spend() internally — let any
	## pending Fortune/Dark Deal prompt resolve on its own (declining is
	## fine, it doesn't affect what's under test) before checking state.
	var settle_waited := 0.0
	while fe.awaiting_fortune_choice and settle_waited < 5.0:
		fe._pending_choice_str = ""
		fe.awaiting_fortune_choice = false
		await tree.create_timer(0.1).timeout
		settle_waited += 0.1
	await tree.process_frame
	await tree.process_frame

	checks.append(["_on_sprint: a successful Sprint genuinely granted bonus movement", fe.movement_remaining > 0])
	checks.append(["_on_sprint: move_mode_active is set (the 'click a square to sprint there' state)", fe.move_mode_active])
	checks.append(["_on_sprint: sprint_finish_pending is set", fe.sprint_finish_pending])

	## The actual bug: was the action menu (target_container) left
	## genuinely empty, with no way to click anything?
	checks.append(["THE BUG: target_container is NOT empty after Sprint highlights its destination squares (used to be stuck empty)", fe.target_container.get_child_count() > 0])
	checks.append(["THE BUG: awaiting_player_target was restored to true (used to be stuck false)", fe.awaiting_player_target])

	## The Move button specifically should read "Cancel Move" while
	## move_mode_active — proof the real menu-builder ran (not just
	## some placeholder), matching the exact pattern _enter_move_mode()
	## already relies on for an ordinary Move. Buttons live 4 containers
	## deep (target_container -> columns_row -> column wrapper -> the
	## HFlowContainer itself), so this walks the whole subtree instead
	## of assuming a fixed depth.
	checks.append(["the rebuilt menu genuinely contains a real 'Cancel Move' button (not just any child)", _find_button_with_text(fe.target_container, "Cancel Move") != null])

	## Finally: clicking one of the highlighted squares should still
	## genuinely work and leave the battle in a genuinely live state —
	## the other half of "not able to advance the battle." A partial-
	## budget destination (this project lets Move be spent across
	## several clicks) legitimately reopens the same Turn's menu rather
	## than ending it outright — either outcome is fine; a target_
	## container left empty with awaiting_player_target still false
	## (the original bug) is the only genuinely stuck state.
	checks.append(["a real destination square is available to click", not fe._move_mode_reachable.is_empty()])
	if not fe._move_mode_reachable.is_empty():
		var dest: Vector2i = fe._move_mode_reachable[0]
		var round_before: int = fe.encounter.round_number
		var turn_index_before: int = fe.encounter.current_turn_index
		fe._on_grid_square_clicked(dest)
		await tree.process_frame
		checks.append(["clicking a highlighted square genuinely moved the player there", fe.battle_positions.get(pc) == dest])
		var turn_advanced: bool = fe.encounter.round_number != round_before or fe.encounter.current_turn_index != turn_index_before
		var menu_reopened_live: bool = fe.awaiting_player_target and fe.target_container.get_child_count() > 0
		checks.append(["THE BUG: the battle is genuinely NOT stuck after committing the move (turn advanced, or the menu reopened live)", turn_advanced or menu_reopened_live])

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
	print("RESULT (Sprint Stuck Menu): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass

## Depth-first search for a Button with exact text `label` anywhere
## under `root` — the real menu nests several plain Container layers
## deep (see _make_action_column), so a fixed-depth check is fragile.
static func _find_button_with_text(root: Node, label: String) -> Button:
	for child in root.get_children():
		if child is Button and String(child.text) == label:
			return child
		if child.get_child_count() > 0:
			var found: Button = _find_button_with_text(child, label)
			if found != null:
				return found
	return null
