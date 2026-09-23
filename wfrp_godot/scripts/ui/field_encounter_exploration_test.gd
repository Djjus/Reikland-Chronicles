extends RefCounted
class_name FieldEncounterExplorationTest
## Regression/functional test for FieldEncounterScreen's exploration-mode
## capability — DungeonGeneratorTest covers the map generator in
## isolation; this exercises the actual FieldEncounter scene end-to-end
## while exploration content is pending: entering a fresh dungeon (whose
## tile grid IS the battle grid — see BattleGrid.
## generate_from_dungeon_grid()), moving with the exact same Move action
## normal combat uses, fog-of-war revealing cells while walking, opening
## a room door (an explicit action) and having monsters spawn directly
## onto the map and splice into the SAME live turn order (see
## CombatEncounter.add_combatant_mid_round()) rather than starting a
## second, separate encounter, returning from that fight back to
## exploration once every monster is defeated, a real save/load
## round-trip mid-dungeon, and finally exiting.
##
## This used to be DungeonScreenTest, then a first-pass
## FieldEncounterExplorationTest against a since-discarded "two-layer
## toggle" design (a separate exploration UI layer/DungeonMapView/prompt-
## confirm flow, and a second "exploration_encounter" CombatEncounter).
## Per the corrected design (the dungeon tile grid REPLACES the normal
## battle map, using the SAME BattleGrid/BattleGridView and the SAME
## CombatEncounter/turn_order the whole visit), this test instead drives
## the real Move button/grid-click flow and the real turn loop directly,
## exactly as a player would experience it — there is no second UI layer
## or second encounter left to test in isolation.
##
## Needs a live SceneTree (instantiates the real scene), so this follows
## the same "static run_test(tree)" shape as this project's other
## scene-level tests (e.g. ConsumeAlcoholTest's second half).

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## A plain Array append (Arrays are reference types in GDScript, so
	## this correctly mutates the outer `checks` from inside the
	## closure) — deliberately NOT tracking a running "all_pass" bool
	## alongside it, since a bool captured by a lambda is captured BY
	## VALUE in GDScript, not by reference, and would silently fail to
	## propagate a failure back out. all_pass is derived by scanning
	## `checks` once, after every check has run, instead.
	var check := func(label: String, passed: bool) -> void:
		checks.append([label, passed])

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.pending_dungeon_theme_id = "sewer"
	GameState.dungeon_entry_requested = true   ## real dungeon-entry signal, see that field's own header comment
	## Deliberately NO light source equipped — the dungeon is genuinely
	## pitch black without one (radius 0), which the fog-of-war check
	## below relies on: at radius 0, only the party's current tile is
	## ever visible=2, so the set of cells EVER revealed (vis >= 1,
	## "explored memory") should still grow as the party moves.

	var screen = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child.call_deferred(screen)
	for i in range(4):
		await tree.process_frame

	check.call("FieldEncounter instantiated without error", screen != null)
	check.call("pending exploration content was detected and activated", screen._hosted_by_exploration)
	check.call("dungeon_state was generated on entry", not screen.dungeon_state.is_empty())
	check.call("GameState.dungeon_state mirrors the screen's own state", not GameState.dungeon_state.is_empty())
	check.call("starts in exploration mode", screen._exploration_mode)
	check.call("no monsters yet -- only the party is in the live encounter", screen.encounter != null and screen.monsters.is_empty())
	check.call("turn order was rolled for the whole party (the SAME CombatEncounter the whole visit uses)", screen.encounter.turn_order.size() == GameState.party.size())

	## The dungeon tile grid IS the battle grid -- no separate map view,
	## per the corrected design.
	var grid_rows: Array = screen.dungeon_state.get("grid_rows", [])
	check.call("battle_grid is sized to the actual generated dungeon, not the fixed combat canvas", screen.battle_grid != null and screen.battle_grid.rows == grid_rows.size())
	check.call("battle_grid carries dungeon tile textures", not screen.battle_grid.cell_texture.is_empty())
	check.call("battle_grid carries fog-of-war state", not screen.battle_grid.fog_of_war.is_empty())

	var entrance: Vector2i = screen.dungeon_state.get("entrance_pos")
	check.call("entrance cell is visible (vis=2) from the start", int(screen.dungeon_state.get("visibility", {}).get(entrance, 0)) == 2)
	check.call("the whole party is placed on the grid near the entrance", GameState.party.all(func(m): return screen.battle_positions.has(m)))

	## First turn: no monsters yet, so the SAME shared turn loop
	## (_next_turn -> _prompt_player_turn -> _render_turn_action_menu)
	## dispatches to the exploration-only menu instead of the normal
	## combat one -- proven indirectly via Move's own shared handler,
	## exactly as the real UI drives it.
	var mover: Character = screen.player
	check.call("the first turn belongs to a party member (all-ally turn order)", mover != null and mover.allegiance == "ally")
	check.call("a real player turn is being prompted, same as normal combat", screen.awaiting_player_target)

	var start_pos: Vector2i = screen.battle_positions[mover]
	var visible_before: int = _count_visible(screen)
	screen.movement_remaining = mover.get_movement() * 2
	screen._on_move_button_pressed()
	check.call("Move re-uses the exact same move-mode machinery combat already has", screen.move_mode_active)
	var dest: Vector2i = _find_reachable_step(screen)
	check.call("a reachable square exists to move to", dest != Vector2i(-1, -1))
	if dest != Vector2i(-1, -1):
		screen._try_commit_move(dest)
	check.call("the mover's position actually changed on the dungeon grid", dest == Vector2i(-1, -1) or screen.battle_positions[mover] != start_pos)
	var visible_after: int = _count_visible(screen)
	check.call("fog of war revealed at least as much of the map after moving", visible_after >= visible_before)
	check.call("dungeon_state.player_grid_pos synced to the mover's new square", screen.dungeon_state.get("player_grid_pos") == screen.battle_positions[mover])

	## Force our way to a room door directly via the generated data
	## (avoids this test depending on exactly how far a single Move
	## reaches) and open it -- Open Door is an explicit action, not
	## automatic on arrival, per the design.
	## Per the "New Dungeon building rules" rework, room count varies
	## per-dungeon (the generator keeps building until a Quest room is
	## placed, then caps everything else as dead ends) — no longer a
	## fixed 2 every time.
	var rooms: Array = screen.dungeon_state.get("rooms", [])
	check.call("dungeon has at least one room", rooms.size() >= 1)
	## Pick a room guaranteed to actually have monsters (a plain "small"
	## room with no hazard rolls empty monster_names) — the Quest room
	## always does (Monster Table: 1 Rat Ogre + 1 Stormvermin), and the
	## generator's own safety valve guarantees one exists every run.
	var target_room: Dictionary = rooms[0]
	for r in rooms:
		if r.get("quest", false):
			target_room = r
			break
	var door_pos: Vector2i = target_room.get("door_pos")
	var approach: Vector2i = _find_adjacent_open(screen, door_pos)
	screen.battle_positions[mover] = approach
	screen.dungeon_state["player_grid_pos"] = approach
	screen._reveal_around(approach)
	GameState.dungeon_state = screen.dungeon_state
	screen._refresh_dungeon_battle_grid()
	screen.action_used_this_turn = false

	check.call("adjacent to the room's own closed door once approached", screen._adjacent_closed_door(approach) == door_pos)
	var combatants_before: int = screen.encounter.combatants.size()
	screen._on_open_door_pressed()
	check.call("opening an un-encountered room door spawns monsters", not screen.monsters.is_empty())
	check.call("the spawned monsters joined the SAME live encounter (never a second, separate one)", screen.encounter.combatants.size() > combatants_before)
	check.call("_exploration_mode flips to false the instant monsters join", not screen._exploration_mode)
	check.call("every spawned monster was spliced straight into the current round's turn_order", _monsters_in_turn_order(screen))
	check.call("dungeon_state remembers which room's fight is active", screen._active_combat_room != null)

	## End the fight by defeating every monster directly -- this test is
	## about the SCREEN's own hand-off/return wiring, not re-proving
	## combat resolution (field_encounter_screen's own other tests
	## already cover that) -- then use the normal Return path, which must
	## now simply resume the SAME encounter/turn loop instead of routing
	## to Overworld.
	var scene_before_combat := tree.current_scene
	for m in screen.monsters:
		m.wounds_current = 0
	screen._end_battle(true)
	screen._on_return_pressed()
	await tree.process_frame

	check.call("_exploration_mode flips back to true once the fight is over", screen._exploration_mode)
	check.call("battle_over resets so the SAME encounter can keep going", not screen.battle_over)
	check.call("returning from combat did NOT change scenes (stayed on the same FieldEncounter)", tree.current_scene == scene_before_combat)
	check.call("the fought room is marked cleared", _room_cleared(screen.dungeon_state))
	check.call("no monsters remain living, but exploration continues (the exploration-mode guard on _next_turn's own victory check)", screen.encounter.get_living("adversary").is_empty() and not screen.battle_over)

	## Save/load round-trip: serialize through the same
	## to_save_dict()/from_save_dict() path a real save uses, and confirm
	## the dungeon survives it.
	var saved: Dictionary = GameState.player_character.to_save_dict()
	GameState.dungeon_state = {}
	check.call("dungeon_state can be cleared (simulating a fresh load before restore)", GameState.dungeon_state.is_empty())
	var restored := Character.from_save_dict(saved)
	check.call("from_save_dict() restored a Character", restored != null)
	check.call("GameState.dungeon_state was repopulated by from_save_dict()", not GameState.dungeon_state.is_empty())
	check.call("restored dungeon_state has the same entrance position", GameState.dungeon_state.get("entrance_pos") == entrance)
	var restored_rooms: Array = GameState.dungeon_state.get("rooms", [])
	var any_cleared := false
	for r in restored_rooms:
		if r.get("cleared", false):
			any_cleared = true
	check.call("restored dungeon_state remembers the cleared room across save/load", any_cleared)

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (FieldEncounterExploration): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")

	## Exit flow -- deliberately LAST: _do_exit_dungeon() triggers a real
	## change_scene_to_file(), which frees this test's own scene tree
	## context mid-call (same documented gotcha as this project's existing
	## CityScreenTest). Nothing runs after it.
	GameState.dungeon_state = screen.dungeon_state
	screen._do_exit_dungeon()
	return all_pass

## Counts cells EVER revealed (explored or currently visible, vis >= 1) —
## monotonically non-decreasing regardless of light radius, unlike the
## currently-visible-only (vis == 2) count, which can legitimately shrink
## as the party moves away from a cell even while genuinely making
## forward progress.
static func _count_visible(screen) -> int:
	var vis: Dictionary = screen.dungeon_state.get("visibility", {})
	var n := 0
	for v in vis.values():
		if int(v) >= 1:
			n += 1
	return n

## Grabs whatever square _enter_move_mode() (already run by the caller)
## computed as reachable — mirrors how a real click on the highlighted
## battle map would pick one, without depending on exact pathing/reach
## numbers this test shouldn't need to know.
static func _find_reachable_step(screen) -> Vector2i:
	var reachable: Array = screen._move_mode_reachable
	if reachable.is_empty():
		return Vector2i(-1, -1)
	return reachable[0]

static func _find_adjacent_open(screen, pos: Vector2i) -> Vector2i:
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var cand: Vector2i = pos + d
		var ch: String = screen._char_at(cand)
		if ch == screen.dungeon_theme.floor_char or ch == screen.dungeon_theme.entrance_char:
			return cand
	return pos

static func _monsters_in_turn_order(screen) -> bool:
	for m in screen.monsters:
		if not screen.encounter.turn_order.has(m):
			return false
	return true

static func _room_cleared(state: Dictionary) -> bool:
	for r in state.get("rooms", []):
		if r.get("cleared", false):
			return true
	return false
