extends RefCounted
class_name SecondaryShadowTrueRadiusTest
## Per the follow-up report ("secondary shadows seem to only go 10 yards
## even in full light, they should continue to the edge of the map and
## merge cleanly with the dark outside the light circle. Similarly 2nd
## light should dispel shadows beyond 10 yards if it reaches that far
## (fully lit lantern)"): the player's own occlusion/lit-tile tracking
## (_player_secondary_lit_tiles, _player_light_blocked_tiles,
## _player_secondary_shadow_range_tiles) used to be capped at
## SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES (8 tiles) — the SAME cap that
## limits how far an individual shadow-blob sprite is drawn — even
## though a Lantern's own true light_radius_tiles can be 20+ (Storm
## Lantern). Past 8 tiles, a wall genuinely blocking that light's own
## (much larger) reveal circle got NO occlusion at all: the ground
## behind it just lit up as if the wall wasn't there. The fix uses the
## light's own TRUE radius_tiles for occlusion/lit-tile tracking, while
## a new, separate blob_shadow_range_tiles keeps the original short cap
## for actual shadow-sprite/wall-polygon rendering only.
##
## Case 1: with a strong (radius > 8 tiles) light and a wall placed
## exactly 12 tiles from the player straight along one axis (beyond the
## old 8-tile cap, within the light's own true radius), the tile just
## past that wall now correctly needs redarkening — the old cap would
## have silently skipped this tile's own LOS check entirely (never
## entering _player_light_blocked_tiles), leaving it un-occluded.
## Case 2: _player_secondary_shadow_range_tiles reports the light's own
## TRUE radius (12+), not the old capped 8.
## Case 3: a SEPARATE lamp's own redarkened wedge, sitting within the
## player's true light radius but beyond the OLD 8-tile cap, is now
## correctly dispelled (no longer needs redarkening) once the player's
## own strong light reaches it — this is the "2nd light should dispel
## shadows beyond 10 yards" half of the request.
## Case 4: a shadow-casting BLOB sprite for a tree far beyond the short
## blob_shadow_range_tiles cap (but within the light's true radius) is
## still NOT drawn — confirms the fix didn't accidentally widen blob
## rendering distance too (that cap is deliberately unchanged, see its
## own comment).

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.inventory.clear()
	pc.equipped_weapon = ""
	pc.equipped_offhand = ""
	## A Storm Lantern: genuinely long reveal radius (20 tiles per
	## data/items/core_items.tres), well past the old 8-tile shadow
	## cap. Must be actually lit (light_mode "on" + fuel > 0), same as
	## every other lit-light test in this suite (see
	## secondary_light_shadow_test.gd) -- equipping it alone leaves
	## has_active_light_source() false.
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

	var test_pc: Character = GameState.player_character
	var bearer_radius: int = test_pc.get_active_light_radius_tiles()
	checks.append(["setup: the equipped light source's own radius genuinely exceeds the old 8-tile shadow cap", bearer_radius > SecondaryShadowTrueRadiusTest._max_range(ow)])
	if bearer_radius <= ow.SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES:
		ow.queue_free()
		return false

	## Clear a wide patch and lay a single wall tile exactly 12 tiles
	## north of the player -- beyond the old 8-tile cap, within the
	## light's own true (>8) radius.
	for dy in range(-bearer_radius - 2, bearer_radius + 3):
		for dx in range(-bearer_radius - 2, bearer_radius + 3):
			ow.tile_chars[ow.player.grid_pos + Vector2i(dx, dy)] = "."
	var wall_tile: Vector2i = ow.player.grid_pos + Vector2i(0, -12)
	ow.tile_chars[wall_tile] = "B"
	var tile_past_wall: Vector2i = ow.player.grid_pos + Vector2i(0, -13)

	ow.static_lamp_coords.clear()
	ow._apply_light_source_secondary_shadows()
	ow._refresh_light_occlusion()

	checks.append(["Case 1: the tile just past a wall 12 tiles away (beyond the old 8-tile cap, within the light's true radius) needs redarkening", ow._tile_needs_redarkening(tile_past_wall)])
	checks.append(["Case 1: ...and is genuinely recorded as LOS-blocked by the player's own light", ow._player_light_blocked_tiles.has(tile_past_wall)])
	## Per the later "light bleeding through the edges" follow-up:
	## _player_secondary_shadow_range_tiles is now the light's true
	## radius minus SECONDARY_SHADOW_EDGE_MARGIN_TILES (see that
	## constant's own comment) rather than the raw true radius — still
	## nowhere near the old 8-tile cap this test's whole point is to
	## confirm has been fixed, just no longer counting the outermost
	## sliver of the light's own fading rim as "genuinely lit."
	checks.append(["Case 2: _player_secondary_shadow_range_tiles reports the light's TRUE radius (margin-adjusted), not the old 8-tile cap", ow._player_secondary_shadow_range_tiles == bearer_radius - ow.SECONDARY_SHADOW_EDGE_MARGIN_TILES])

	## --- Case 3: a lamp's own wedge, beyond the OLD cap but within the
	## player's true light radius, gets dispelled once the player is
	## close enough with this strong light.
	ow.tile_chars.erase(wall_tile)
	var lamp_pos: Vector2i = ow.player.grid_pos + Vector2i(6, 0)
	var lamp_wall: Vector2i = ow.player.grid_pos + Vector2i(6, -3)
	ow.tile_chars[lamp_wall] = "B"
	var lamp_shadow_tile: Vector2i = ow.player.grid_pos + Vector2i(6, -4)
	ow.static_lamp_coords.append(lamp_pos)
	ow._apply_static_lamp_secondary_shadows()
	ow._apply_light_source_secondary_shadows()
	ow._refresh_light_occlusion()
	checks.append(["setup Case 3: with only the lamp active this tile is blocked by the lamp's own nearby wall", ow._static_lamp_blocked_tiles.get(0, []).has(lamp_shadow_tile)])
	checks.append(["Case 3: the player's own strong, longer-range light now dispels that lamp-caused shadow at this distance", not ow._tile_needs_redarkening(lamp_shadow_tile)])

	## --- Case 4: blob-sprite rendering distance is unchanged -- a tree
	## far beyond blob_shadow_range_tiles (but within the true radius)
	## still gets no shadow-blob sprite.
	ow.static_lamp_coords.clear()
	ow.tile_chars.erase(lamp_wall)
	var far_tree: Vector2i = ow.player.grid_pos + Vector2i(0, -(ow.SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES + 2))
	ow.tile_chars[far_tree] = "T"
	ow._apply_light_source_secondary_shadows()
	var far_sprite: Sprite2D = ow._light_shadow_sprites.get(far_tree)
	checks.append(["Case 4: a tree beyond the short blob_shadow_range_tiles cap still gets no visible shadow-blob sprite (unchanged rendering-distance behavior)", far_sprite == null or not far_sprite.visible])

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
	print("RESULT (Secondary Shadow True Radius): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass

static func _max_range(ow) -> int:
	return ow.SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES
