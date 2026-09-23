extends RefCounted
class_name NpcMarkerGroundTileTest
## Regression test for "NPCs in houses are still standing on mud tiles."
##
## NPC_MARKER_CHARS ("@", "N", "H", "S", "Y" — see overworld.gd's own
## comment) are pure spawn triggers (see _spawn_npc/_spawn_shopkeeper/
## _spawn_priest, called from _build_map()'s first pass), never meant
## to describe real ground — but TILE_ATLAS still had to map each one
## to *something* (Vector2i(1,0), a plain bare-path tile), so before
## this fix every spawn point rendered as an isolated, mismatched patch
## of bare path regardless of what actually surrounded it.
##
## This exact fix first shipped as v0.3.45, but was later lost from a
## rewrite of _build_map() with no regression test to catch the
## regression — that v0.3.45 doc's own verification was a throwaway
## headless scratch test, never saved as a real suite file. This test
## exists so that can't happen silently again.
##
## Coordinates below are Giessingen's own real map data (verified
## directly against giessingen_village.tres's map_rows before writing
## this test, same approach building_wall_walkable_test.gd already
## uses for this same map):
##   H (trainer)  at (20, 9)  — all four orthogonal neighbours are "."
##   N (traveller) at (13, 18) — all four orthogonal neighbours are "."
##   Y (priest)   at (8, 13)  — inside Building A, Rect2i(5,12,5,3),
##                              timber walls only (no "K" stone tile)
##   S (shopkeeper) at (17, 13) — inside Building B, Rect2i(14,12,5,3),
##                              also timber walls only (its "r" front is
##                              just a facade texture, not a "K" tile —
##                              see building_wall_walkable_test.gd's own
##                              note on this)
##   @ (player start) at (9, 16) — on the "G" mud path south of the two
##                              buildings; N=G, S=B (a wall — excluded),
##                              W=G, E=G, so "G" is the clear majority

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.pending_map_path = "res://data/maps/giessingen_village.tres"
	var ow = load("res://scenes/Overworld.tscn").instantiate()
	tree.get_root().add_child(ow)
	tree.current_scene = ow
	for i in range(15):
		await tree.process_frame

	## --- None of the five marker letters survive as literal ground chars ---
	var marker_coords := {
		"H": Vector2i(20, 9), "N": Vector2i(13, 18),
		"Y": Vector2i(8, 13), "S": Vector2i(17, 13), "@": Vector2i(9, 16),
	}
	for marker_ch in marker_coords:
		var coords: Vector2i = marker_coords[marker_ch]
		var resolved: String = ow.tile_chars.get(coords, "")
		checks.append([
			"THE FIX: '%s' marker's own tile no longer holds the raw spawn letter (resolved to '%s')" % [marker_ch, resolved],
			resolved != marker_ch,
		])

	## --- Outdoor markers (all-grass neighbours) resolve to real grass ---
	checks.append(["THE FIX: 'H' (all-grass neighbours) resolves to plain grass '.'", ow.tile_chars.get(Vector2i(20, 9), "") == "."])
	checks.append(["THE FIX: 'N' (all-grass neighbours) resolves to plain grass '.'", ow.tile_chars.get(Vector2i(13, 18), "") == "."])

	## --- Indoor markers resolve to the room's own crafted floor, not
	## the outdoor bare-path fallback ---
	checks.append(["THE FIX: 'Y' (inside a timber building) resolves to wood-plank floor 'n', not bare path", ow.tile_chars.get(Vector2i(8, 13), "") == "n"])
	checks.append(["THE FIX: 'S' (inside a timber building) resolves to wood-plank floor 'n', not bare path", ow.tile_chars.get(Vector2i(17, 13), "") == "n"])

	## --- "@" (the player start tile, previously left out of scope in
	## v0.3.45) is now folded into the same fix — majority outdoor
	## neighbour ("G", mud path) rather than the old bare-path fallback ---
	checks.append(["THE FIX (new scope): '@' resolves to its real majority-neighbour terrain 'G', not bare path", ow.tile_chars.get(Vector2i(9, 16), "") == "G"])

	## --- Not a regression: the buildings themselves are still exactly
	## where building_wall_walkable_test.gd already verified them ---
	var found_a := false
	var found_b := false
	for rect in ow.buildings:
		if rect == Rect2i(5, 12, 5, 3):
			found_a = true
		if rect == Rect2i(14, 12, 5, 3):
			found_b = true
	checks.append(["setup/no-regression: Building A's rect is unaffected by this fix", found_a])
	checks.append(["setup/no-regression: Building B's rect is unaffected by this fix", found_b])

	ow.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (NPC Marker Ground Tile): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
