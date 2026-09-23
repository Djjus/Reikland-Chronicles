extends RefCounted
class_name CombatCameraAndChargeDirectionTest
## Covers three pieces of the same follow-up request:
##
## 1. "always focus the camera on the current attacker when at the start
##    of their turn" -- BattleGridView.center_on() (already used by the
##    dungeon-exploration camera) is an instant snap; confirms the math
##    still lands the target square's own center on the viewport's center.
## 2. "follow it if its a Enemy and its moving, slow down the visible
##    moving a bit" -- BattleGridView.center_on_animated() eases toward
##    that same destination over real time via a Tween rather than
##    snapping; confirms it's genuinely mid-flight partway through (not
##    already at the destination) and has actually arrived once its own
##    duration has elapsed. Also confirms FieldEncounterScreen's own
##    _follow_camera_on_enemy_move() wrapper only ever calls it for an
##    enemy actor, never an ally (the player already fully controls the
##    camera via mouse-drag pan).
## 3. "dont show charge line to targets not in the direction player is
##    moving (no backstep to charge rule)" -- FieldEncounterScreen's own
##    _charge_range_targets_from() must exclude a target that sits behind
##    the hovered destination relative to the player's own REAL current
##    square, even though nothing has actually moved yet -- the bug the
##    screenshot showed (a "Charge" preview line pointing back at a
##    target on the opposite side of the map from the hover square).

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Part 1 & 2: camera centering, on a real BattleGridView node ---
	var fe_scene: PackedScene = load("res://scenes/FieldEncounter.tscn")
	var fe: Node = fe_scene.instantiate()
	tree.get_root().add_child.call_deferred(fe)
	await tree.process_frame
	await tree.process_frame

	var grid_view: BattleGridView = fe.get_node("%BattleGridView")
	checks.append(["Found the real BattleGridView node", grid_view != null])
	if grid_view == null:
		fe.queue_free()
		print("RESULT (Combat Camera + Charge Direction): SETUP FAILED")
		return false

	## Root cause of an earlier flaky version of this test: fe's own
	## _start_encounter() keeps setting up and dispatching a real battle
	## in the background (character creation, terrain, monster spawns,
	## then a genuine _next_turn() for Round 1 Turn 1) for a real stretch
	## of time after this node is added. Per the request just implemented
	## a few edits above ("focus the camera on the current attacker when
	## at the start of their turn"), THAT real _next_turn() call now
	## fires its own grid_view.center_on() the instant it finally
	## resolves -- which, if it lands mid-poll below, silently kills this
	## test's own tracked animated tween and snaps pan_offset to whatever
	## random combatant/square the real encounter happened to dispatch
	## to, nothing to do with this test's own target square at all. Per
	## this project's own established pattern for exactly this kind of
	## race (see monster_turn_stall_watchdog_test.gd's own drain phase),
	## this polls for the encounter to reach a real, stable idle point
	## (current combatant genuinely unchanging for a few consecutive
	## checks) before touching the camera at all -- after which nothing
	## further will call _next_turn() on its own, since nothing here ever
	## simulates player input to advance a real Turn.
	var settle_current: Character = null
	var settle_stable := 0
	var settle_safety := 0
	while settle_stable < 3 and settle_safety < 60:
		settle_safety += 1
		await tree.create_timer(0.5).timeout
		var now: Character = fe.encounter.get_current_combatant() if fe.encounter != null else null
		if now == settle_current:
			settle_stable += 1
		else:
			settle_stable = 0
			settle_current = now

	grid_view.size = Vector2(900.0, 540.0)
	grid_view.zoom_level = 1.0
	grid_view.pan_offset = Vector2.ZERO
	await tree.process_frame

	var target_square := Vector2i(3, 4)
	grid_view.center_on(target_square)
	var sq_px: float = grid_view._square_px()
	var origin: Vector2 = grid_view._grid_origin(sq_px)
	var content_point: Vector2 = origin + (Vector2(target_square) + Vector2(0.5, 0.5)) * sq_px
	var screen_pos: Vector2 = grid_view.pan_offset + grid_view.zoom_level * content_point
	checks.append(["center_on(): an instant snap lands the target square's own center on the viewport's center", screen_pos.is_equal_approx(grid_view.size / 2.0)])

	## center_on_animated(): reset to a known start, ease toward a
	## different square, and confirm it's genuinely mid-flight partway
	## through -- not an instant snap in disguise -- then confirm it has
	## actually arrived once its own duration has clearly elapsed.
	grid_view.pan_offset = Vector2.ZERO
	var animated_target := Vector2i(7, 2)
	## The real expected destination -- via center_on()'s own instant,
	## already-clamped math, rather than hand-deriving the raw pre-clamp
	## point again here (which could legitimately differ from what
	## _clamp_pan() actually settles on for this grid/viewport size).
	grid_view.center_on(animated_target)
	var animated_final_target: Vector2 = grid_view.pan_offset
	grid_view.pan_offset = Vector2.ZERO
	var pan_before_animate: Vector2 = grid_view.pan_offset
	grid_view.center_on_animated(animated_target, 0.6)
	await tree.create_timer(0.2).timeout
	var mid_flight_pan: Vector2 = grid_view.pan_offset
	checks.append(["center_on_animated(): genuinely still moving partway through its own duration (not an instant snap)", not mid_flight_pan.is_equal_approx(pan_before_animate)])
	checks.append(["center_on_animated(): has NOT already arrived at its own destination partway through (that would defeat the whole point of easing)", not mid_flight_pan.is_equal_approx(animated_final_target)])
	## Generous margin (well beyond the tween's own 0.6s duration) purely
	## for this sandbox's own occasional resource contention when running
	## a whole heavy test suite back-to-back -- the settle-poll above is
	## what actually makes this reliable; this is just slack for a
	## genuinely busy run, same reasoning this project's own watchdog
	## test budgets several real seconds of margin for for (see monster_
	## turn_stall_watchdog_test.gd's own comments).
	await tree.create_timer(2.0).timeout
	checks.append(["center_on_animated(): genuinely arrives at its destination once its own duration has elapsed", grid_view.pan_offset.is_equal_approx(animated_final_target)])

	## _follow_camera_on_enemy_move(): per the request, only ever follows
	## an ENEMY's own movement -- an ally actor must be a complete no-op
	## (the player already fully controls the camera via drag).
	if fe.battle_positions.has(fe.player):
		fe.battle_positions[fe.player] = Vector2i(1, 1)
		grid_view.pan_offset = Vector2(123.0, 45.0)
		fe._follow_camera_on_enemy_move(fe.player)
		checks.append(["_follow_camera_on_enemy_move(): a genuine no-op for an ally actor", grid_view.pan_offset.is_equal_approx(Vector2(123.0, 45.0))])

	fe.queue_free()
	for i in range(2):
		await tree.process_frame

	## --- Part 3: charge-preview direction filtering ---------------------
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.current_field_difficulty_tier = 0
	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	## Two distinctly-tracked monsters so "ahead of travel" vs "behind
	## it" can be placed unambiguously on opposite sides of the mover.
	GameState.pending_encounter_monster_names = ["Giant Rat", "Giant Rat"]

	var fe2: Node = fe_scene.instantiate()
	tree.get_root().add_child(fe2)
	for i in range(5):
		await tree.process_frame

	var dir_setup_ok: bool = fe2.monsters.size() >= 2 and fe2.battle_grid != null and fe2.battle_positions.has(fe2.player)
	checks.append(["Charge-direction setup: a real encounter with two monsters and a positioned player", dir_setup_ok])
	if dir_setup_ok:
		var player: Character = fe2.player
		var ahead: Character = fe2.monsters[0]
		var behind: Character = fe2.monsters[1]
		## Player planted at the grid's own center; "ahead" placed several
		## squares in the +X direction (the same direction the hover square
		## below moves toward), "behind" placed the same distance in the
		## opposite (-X) direction -- squarely on the wrong side of travel.
		## Cleared so the straight charge lines this check needs are never
		## incidentally broken by the battle's own random obstacle/river
		## scatter -- this test only cares about the direction filter
		## itself, not whether a real random map happens to leave a clear
		## line between two arbitrary squares.
		fe2.battle_grid.impassable.clear()
		fe2.battle_grid.obstacles.clear()
		fe2.battle_grid.obstacle_type.clear()
		fe2.battle_grid.obstacle_group.clear()
		fe2.battle_grid.obstacle_cover.clear()
		fe2.battle_grid.blocks_los.clear()
		var player_sq := Vector2i(int(BattleGrid.COLS / 2), int(BattleGrid.ROWS / 2))
		fe2.battle_positions[player] = player_sq
		fe2.battle_positions[ahead] = player_sq + Vector2i(16, 0)
		fe2.battle_positions[behind] = player_sq + Vector2i(-16, 0)
		fe2._charge_blocked_targets.clear()
		var hover_sq: Vector2i = player_sq + Vector2i(4, 0)   ## hovering further in the same +X direction "ahead" sits in
		## Generous enough that the real Charge-distance floor (must cover
		## at least the mover's own full Movement) and ceiling (this Turn's
		## remaining budget) are never what's being tested here -- only the
		## direction filter itself.
		var remaining: int = player.get_movement() + 30
		var targets: Array = fe2._charge_range_targets_from(hover_sq, remaining)
		var ahead_sq: Vector2i = fe2.battle_positions[ahead]
		var behind_sq: Vector2i = fe2.battle_positions[behind]
		checks.append(["_charge_range_targets_from(): a target ahead of the real direction of travel IS included", targets.has(ahead_sq)])
		checks.append(["_charge_range_targets_from(): a target behind the real direction of travel is excluded (no backstep-to-charge preview)", not targets.has(behind_sq)])

	fe2.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Combat Camera + Charge Direction): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
