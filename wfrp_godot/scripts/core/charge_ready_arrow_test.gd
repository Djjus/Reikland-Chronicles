extends RefCounted
class_name ChargeReadyArrowTest
## Per the request ("in combat if the active character is within charge
## range of the selected target draw a Red arrow line from that
## character on the battle map to the target (write 'Charge' along the
## side of the red line), and do the same on the red charge arrow line
## that is created when selecting move position"):
##
## BattleGridView is a deliberately "dumb renderer" (see its own header
## comment) — it draws whatever state it's handed and owns none of the
## charge-range logic itself, so this test exercises the real
## FieldEncounterScreen._prompt_player_turn() flow (the same one that
## already computes can_charge for the Charge button) and asserts on
## the state it pushes down to the grid view (charge_ready_target),
## rather than trying to inspect actual pixels — the same split this
## project's test suite already draws between logic (unit-tested here)
## and rendering (screenshot-verified, see any *_v0.2.*.md project doc's
## own delivered screenshots).
##
## Case 1: a target well outside charge range (further than 2x the
## mover's own Movement) draws no arrow at all.
## Case 2: a target already adjacent (nothing to charge across) also
## draws no arrow — same "Attack normally instead" rule
## _target_in_charge_range itself already documents.
## Case 3: a target at exactly the mover's own Movement distance (the
## real charge_min floor) draws the arrow, ending on the target's own
## square — mirrors the exact same math _target_in_charge_range uses.
## Case 4: once the Action's already spent this Turn, the arrow clears
## even though the target is still, mechanically, within charge
## range — matching the Charge button's own visibility rule (see
## _prompt_player_turn's own comment on why this is gated the same
## way).
## Case 5: the existing hover-based Charge-range preview (shown while
## picking a Move destination) still works after this change —
## unrelated to charge_ready_target, but the same _draw() edit that
## added this feature's label also touches that code path, so this
## guards against a regression there.

static func run_test(fe) -> bool:
	var checks: Array = []

	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_habitat = ""
	fe._start_encounter()
	for i in range(3):
		await fe.get_tree().process_frame

	var player: Character = fe.player
	var goblin: Character = fe.monsters[0] if fe.monsters.size() > 0 else null
	checks.append(["setup: a monster genuinely exists", goblin != null])
	if goblin == null:
		print("RESULT (Charge-Ready Arrow): SETUP FAILED (no monster)")
		return false

	player.equipped_weapon = "Sword"
	fe.weapons[player] = fe._resolve_weapon(player)
	fe.battle_grid = BattleGrid.new()
	fe.battle_grid.generate_from_terrain_snapshot([])   ## fully open grid
	## Real test bug fix, surfaced by the diagonal corner-cut fix (see
	## battle_grid.gd's own _edge_blocked_diagonal() comment): an empty
	## terrain_snapshot only skips per-tile impassable marking -- it does
	## NOT skip _scatter_obstacles()'s own independent random decor pass,
	## so this "fully open grid" wasn't actually guaranteed empty. Once
	## diagonal corner-cutting past a solid obstacle was (correctly)
	## refused, an unlucky scatter roll placing an obstacle right on the
	## player-goblin diagonal could add a real extra step to the
	## charge_min-exact path in Case 3 below, intermittently failing a
	## check that's supposed to be about exact charge-range math, not
	## obstacle luck. Cleared explicitly so this test's own documented
	## intent ("fully open grid") is actually true.
	fe.battle_grid.impassable.clear()
	fe.battle_grid.obstacle_group.clear()
	fe.battle_grid.obstacles.clear()
	fe.battle_grid.obstacle_type.clear()
	fe.battle_grid.obstacle_cover.clear()
	fe.action_used_this_turn = false
	fe.awaiting_player_target = true
	fe.pending_defense.clear()

	var charge_min: int = player.get_movement()
	var origin := Vector2i(5, 5)

	## --- Case 1: well out of charge range -------------------------------
	fe.battle_positions.clear()
	fe.battle_positions[player] = origin
	fe.battle_positions[goblin] = origin + Vector2i(charge_min * 4 + 5, 0)
	fe.selected_target = goblin
	fe._prompt_player_turn(true)
	await fe.get_tree().process_frame
	checks.append(["Case 1: a target far out of charge range draws no Charge-ready arrow", fe.grid_view.charge_ready_target == Vector2i(-1, -1)])

	## --- Case 2: already adjacent -- nothing to charge across -----------
	fe.battle_positions.clear()
	fe.battle_positions[player] = origin
	fe.battle_positions[goblin] = origin + Vector2i(1, 0)
	fe.selected_target = goblin
	fe._prompt_player_turn(true)
	await fe.get_tree().process_frame
	checks.append(["Case 2: an already-adjacent target draws no Charge-ready arrow either", fe.grid_view.charge_ready_target == Vector2i(-1, -1)])

	## --- Case 3: exactly at the charge_min floor -- arrow should appear -
	fe.battle_positions.clear()
	fe.battle_positions[player] = origin
	fe.battle_positions[goblin] = origin + Vector2i(charge_min + 1, 0)
	fe.selected_target = goblin
	fe._prompt_player_turn(true)
	await fe.get_tree().process_frame
	checks.append(["Case 3: a target exactly at the mover's own Movement distance IS in charge range (matches the Charge button's own can_charge)", fe.grid_view.charge_ready_target != Vector2i(-1, -1)])
	if fe.grid_view.charge_ready_target != Vector2i(-1, -1):
		checks.append(["Case 3: ...and the arrow points at the target's own real square", fe.grid_view.charge_ready_target == fe.battle_positions[goblin]])

	## --- Case 4: same in-range target, but the Action's already spent --
	fe.action_used_this_turn = true
	fe._prompt_player_turn(false)
	await fe.get_tree().process_frame
	checks.append(["Case 4: once the Action's already spent this Turn, the arrow clears -- same visibility rule as the Charge button itself", fe.grid_view.charge_ready_target == Vector2i(-1, -1)])
	fe.action_used_this_turn = false

	## --- Case 5: the existing hover-based Charge-range preview (Move
	## destination hovering) still works -- regression guard for the
	## shared _draw() edit.
	fe.grid_view.set_charge_preview([Vector2i(10, 10)], Vector2i(8, 8))
	checks.append(["Case 5: the existing hover-based Charge-range preview arrow still sets its own state correctly (regression guard)", fe.grid_view.charge_preview_targets == [Vector2i(10, 10)] and fe.grid_view.charge_preview_origin == Vector2i(8, 8)])
	fe.grid_view.set_charge_preview([], Vector2i(-1, -1))

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Charge-Ready Arrow): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
