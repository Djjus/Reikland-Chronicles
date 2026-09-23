extends RefCounted
class_name SecondaryShadowEdgeBleedTest
## Per the follow-up ("there is always light bleeding through the
## edges (top row of cells)... extend secondary shadow beyond the
## circle of the light to stop this"): a tile right at the outer rim
## of a light's own true reach only gets a PARTIAL reveal from the
## shader (the last ~1-1.5 tiles are its own softness fade-out band,
## see night_overlay_light.gdshader). _tile_lit_by_any_secondary_
## light()'s membership test was a hard yes/no, so a tile barely
## inside that fading rim counted as fully "lit" — enough to exempt
## it from its own light's redarkening, or to let it cross-suppress a
## DIFFERENT light's shadow there — even though the shader itself was
## already most of the way back to black. The fix: SECONDARY_SHADOW_
## EDGE_MARGIN_TILES shrinks the radius used for "counts as lit" (for
## both the player's own light and every static lamp), so a tile has
## to be solidly inside a light's core, not just barely grazed by its
## fading rim, before something else's shadow gets cancelled there.
##
## Case 1: a tile exactly 1 tile inside the OLD (unshrunk) radius —
## i.e. within the shrink margin of the light's true edge — no longer
## counts as "lit by this light" for exemption purposes.
## Case 2: a tile still comfortably inside the shrunk core (well short
## of the margin band) still correctly counts as lit — the fix doesn't
## just blanket-shrink the whole light, only its outermost rim.
## Case 3: _player_secondary_shadow_range_tiles itself reports the
## shrunk (margin-subtracted) value, not the light's raw true radius.
## Case 4: the occlusion SWEEP itself is untouched by the shrink — a
## wall placed right at the light's true (unshrunk) edge still gets
## found and properly redarkened on its far side, confirming this fix
## only narrows the "cancels a shadow" test, not the "look for walls"
## reach the v0.2.606 true-radius fix established.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.inventory.clear()
	pc.equipped_weapon = ""
	pc.equipped_offhand = ""
	pc.inventory.append("Storm Lantern")
	pc.equipped_weapon = "Storm Lantern"
	pc.light_mode = "on"
	pc.light_fuel_minutes = 200.0

	GameState.time_minutes = 23 * 60
	GameState.pending_map_path = "res://data/maps/giessingen_village.tres"
	var ow = load("res://scenes/Overworld.tscn").instantiate()
	tree.get_root().add_child(ow)
	tree.current_scene = ow
	for i in range(10):
		await tree.process_frame

	var pc2: Character = GameState.player_character
	var true_radius: int = pc2.get_active_light_radius_tiles()
	checks.append(["setup: Storm Lantern's true radius exceeds the edge margin many times over", true_radius > ow.SECONDARY_SHADOW_EDGE_MARGIN_TILES * 3])

	for dy in range(-true_radius - 2, true_radius + 3):
		for dx in range(-true_radius - 2, true_radius + 3):
			ow.tile_chars[ow.player.grid_pos + Vector2i(dx, dy)] = "."
	ow.static_lamp_coords.clear()
	ow._recompute_secondary_light_lit_tiles()

	## Case 1: a tile 1 tile inside the light's TRUE edge (i.e. within
	## the shrink margin) must NOT count as "lit" for exemption.
	var rim_tile: Vector2i = ow.player.grid_pos + Vector2i(0, -(true_radius - 1))
	checks.append(["Case 1: a tile just inside the light's true (unshrunk) edge, within the margin band, no longer counts as genuinely lit", not ow._player_secondary_lit_tiles.has(rim_tile)])

	## Case 2: a tile safely inside the shrunk core still counts as lit.
	var core_tile: Vector2i = ow.player.grid_pos + Vector2i(0, -(true_radius - ow.SECONDARY_SHADOW_EDGE_MARGIN_TILES - 2))
	checks.append(["Case 2: a tile comfortably inside the shrunk core still counts as lit", ow._player_secondary_lit_tiles.has(core_tile)])

	## Case 3: the reported shadow range is the shrunk value.
	checks.append(["Case 3: _player_secondary_shadow_range_tiles reports the margin-shrunk radius", ow._player_secondary_shadow_range_tiles == true_radius - ow.SECONDARY_SHADOW_EDGE_MARGIN_TILES])

	## Case 4: a wall placed so its far side lands INSIDE the margin
	## band (beyond the shrunk lit radius, but still well within the
	## light's TRUE full radius) still gets found by the occlusion
	## sweep and registered as LOS-blocked -- confirming the shrink
	## narrowed only the "cancels a shadow" test, not the "look for
	## walls" reach the sweep itself uses (still the light's true,
	## unshrunk radius_tiles).
	var wall_row: int = ow.player.grid_pos.y - (true_radius - 2)
	var wall_tile: Vector2i = Vector2i(ow.player.grid_pos.x, wall_row)
	ow.tile_chars[wall_tile] = "B"
	var tile_past_wall: Vector2i = Vector2i(ow.player.grid_pos.x, wall_row - 1)
	ow._apply_light_source_secondary_shadows()
	ow._refresh_light_occlusion()
	checks.append(["Case 4: a wall whose far side lands in the margin band is still found by the full-radius occlusion sweep", ow._player_light_blocked_tiles.has(tile_past_wall)])
	checks.append(["Case 4: ...and that tile still correctly needs redarkening", ow._tile_needs_redarkening(tile_past_wall)])

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
	print("RESULT (Secondary Shadow Edge Bleed): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
