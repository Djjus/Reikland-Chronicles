extends RefCounted
class_name LightLineOfSightTest
## Regression test for the reported bug ("light should not illuminate
## tiles a character holding a light source can not see" — screenshots
## showed a character standing at the base of a T-junction, with light
## bleeding around BOTH corners into the perpendicular corridor's far
## reaches, well beyond a straight line of sight). Before the fix,
## _light_bfs() was a pure flood-fill: it only ever stopped at an actual
## wall/door/sealed-edge surface, so light happily wrapped around a
## 90-degree corner as long as there was a continuous run of open floor
## within radius steps -- exactly the diagonal "torch light bleeding
## around the corner" the screenshots showed.
##
## Hand-builds the same T-junction shape: a vertical corridor with the
## mover at its base, opening into a horizontal corridor above, with the
## horizontal corridor continuing well past the T on both sides.

static func run_test(fe) -> bool:
	var checks: Array = []
	var theme: DungeonThemeDefinition = GameData.dungeon_themes.get("sewer")
	var f: String = theme.floor_char
	var w: String = theme.wall_char

	## Grid (13 wide, 8 tall): a horizontal corridor at y=2 spanning the
	## full width, a vertical corridor at x=6 dropping from y=2 down to
	## y=7 where the mover stands. Everything else is solid wall.
	var rows: Array = []
	for y in range(8):
		var row := ""
		for x in range(13):
			if y == 2:
				row += f   ## the horizontal corridor bar of the T
			elif x == 6 and y > 2:
				row += f   ## the vertical stem, mover stands at its base
			else:
				row += w
		rows.append(row)

	GameState.dungeon_state = {
		"theme_id": "sewer",
		"grid_rows": rows,
		"entrance_pos": Vector2i(6, 7),
		"rooms": [],
		"hallway_segments": [],
		"visibility": {},
		"player_grid_pos": Vector2i(6, 7),
		"exit_used": false,
	}
	GameState.party.clear()
	GameState.player_character = null
	GameState.ensure_player_character()
	var mover: Character = GameState.player_character
	mover.character_name = "Davrin"
	mover.equipped_offhand = "Lantern"
	mover.equipped_weapon = "Sword"
	mover.light_mode = "on"
	mover.light_fuel_minutes = 999.0

	fe._start_exploration_mode()
	for i in range(3):
		await fe.get_tree().process_frame

	var mover_pos := Vector2i(6, 7)
	fe.battle_positions[mover] = mover_pos
	fe._refresh_dungeon_battle_grid()
	fe._reveal_around_party()
	for i in range(2):
		await fe.get_tree().process_frame

	var vis: Dictionary = fe.dungeon_state.get("visibility", {})

	## Straight up the stem, directly in line of sight -- should be lit.
	checks.append(["straight up the vertical stem (in direct line of sight) is lit", int(vis.get(Vector2i(6, 3), -1)) == 2])
	checks.append(["the T-junction cell itself (where the corridors meet) is lit", int(vis.get(Vector2i(6, 2), -1)) == 2])

	## THE FIX: far down the horizontal corridor, well around either
	## corner from the mover's own straight-line sight, should NOT be
	## lit bright just because it's flood-fill-reachable -- this is
	## exactly the screenshot's own red-arrow annotation.
	checks.append(["THE FIX: far right along the horizontal corridor, around the corner, is not bright", int(vis.get(Vector2i(11, 2), -1)) != 2])
	checks.append(["THE FIX: far left along the horizontal corridor, around the corner, is not bright", int(vis.get(Vector2i(1, 2), -1)) != 2])

	## Sanity: the fix shouldn't have gone so strict it blinds the mover
	## entirely -- their own square and the straight run up to the
	## junction (already checked above) prove real light still works,
	## just no longer wraps around a corner into the crossbar's far
	## reaches. (A single straight-ray LOS check is a simplification --
	## cells one step around a 1-wide corridor's own corner can
	## legitimately go either way depending on exact ray geometry, so
	## this test doesn't assert on those, only on the clear-cut "still
	## works" and "genuinely too far around the corner" cases above.)
	checks.append(["the mover's own square is lit", int(vis.get(mover_pos, -1)) == 2])

	fe.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Light Line Of Sight): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
