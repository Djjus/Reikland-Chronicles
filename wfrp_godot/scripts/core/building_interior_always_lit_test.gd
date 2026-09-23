extends RefCounted
class_name BuildingInteriorAlwaysLitTest
## Per the request ("and always light up the inside of building with no
## shadows"): whichever ONE building the player currently has the roof
## hidden for (Overworld.player_inside_building — there's only ever one,
## since a building's interior floor is only actually rendered/visible
## while its own roof is off) should always read as fully lit, with no
## night darkness and no redarkening quad, regardless of whether the
## player is carrying any light source at all — a real building has its
## own ambient light (windows, a hearth) independent of a torch.
##
## Case 1: with no building currently entered (player_inside_building ==
## -1, the default), _apply_building_interior_overlay() leaves the
## shader's own interior_active uniform at 0 — completely inert.
## Case 2: entering a building (player_inside_building set to a real
## index) turns interior_active on and sends a sane, non-degenerate
## screen-space rect (min strictly less than max on both axes).
## Case 3: the SAME building's interior rect is mirrored onto
## CloudShadowOverlay's own material too, not just NightOverlay's.
## Case 4: a tile genuinely inside that building, that would otherwise
## be blocked (no light reaches it), no longer needs redarkening once
## the player is inside it — _tile_needs_redarkening() returns false.
## Case 5: the SAME tile, before the player entered the building
## (player_inside_building == -1), genuinely DOES need redarkening —
## confirms Case 4 isn't just vacuously true for every tile.
## Case 6: leaving the building again (back to -1) turns interior_active
## back off.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.inventory.clear()
	pc.equipped_weapon = ""
	pc.equipped_offhand = ""
	## No player light source at all -- the whole point of this feature
	## is that a building's interior is lit independent of one.

	GameState.time_minutes = 23 * 60   ## deep night -- the real test: is the interior lit despite full night darkness?
	GameState.pending_map_path = "res://data/maps/giessingen_village.tres"
	var ow = load("res://scenes/Overworld.tscn").instantiate()
	tree.get_root().add_child(ow)
	tree.current_scene = ow
	for i in range(10):
		await tree.process_frame

	checks.append(["setup: the real village map has at least one real building", ow.buildings.size() > 0])
	if ow.buildings.size() == 0:
		ow.queue_free()
		return false

	## --- Case 1: no building currently entered.
	ow.player_inside_building = -1
	ow._apply_light_source_overlay()
	ow._apply_building_interior_overlay()
	var mat: ShaderMaterial = ow.night_overlay.material
	checks.append(["Case 1: with no building entered, interior_active is off", is_zero_approx(float(mat.get_shader_parameter("interior_active")))])

	## --- Case 2: entering building 0.
	ow.player_inside_building = 0
	ow._apply_building_interior_overlay()
	var active: float = float(mat.get_shader_parameter("interior_active"))
	checks.append(["Case 2: entering a building turns interior_active on", active > 0.5])
	var rect_min: Vector2 = mat.get_shader_parameter("interior_rect_min_px")
	var rect_max: Vector2 = mat.get_shader_parameter("interior_rect_max_px")
	checks.append(["Case 2: the sent screen-space rect is non-degenerate (min < max on both axes)", rect_min.x < rect_max.x and rect_min.y < rect_max.y])

	## --- Case 3: mirrored onto CloudShadowOverlay too.
	var cloud_mat: ShaderMaterial = ow.cloud_shadow_overlay.material
	var cloud_active: float = float(cloud_mat.get_shader_parameter("interior_active"))
	checks.append(["Case 3: CloudShadowOverlay's own material gets the same interior_active", cloud_active > 0.5])
	var cloud_min: Vector2 = cloud_mat.get_shader_parameter("interior_rect_min_px")
	checks.append(["Case 3: ...and the same rect (matches NightOverlay's own)", cloud_min.is_equal_approx(rect_min)])

	## --- Case 4/5: a genuinely-inside tile's redarkening need before vs after.
	var b: Rect2i = ow.buildings[0]
	var inside_tile: Vector2i = b.position + b.size / 2   ## roughly the building's own center -- genuinely inside it
	checks.append(["setup: the chosen tile really is inside building 0's own rect", b.has_point(inside_tile)])
	ow.player_inside_building = -1
	checks.append(["Case 5: before entering, that tile genuinely DOES need redarkening (no light reaches it)", ow._tile_needs_redarkening(inside_tile)])
	ow.player_inside_building = 0
	checks.append(["Case 4: once inside building 0, that same tile no longer needs redarkening", not ow._tile_needs_redarkening(inside_tile)])

	## --- Case 6: leaving the building again.
	ow.player_inside_building = -1
	ow._apply_building_interior_overlay()
	checks.append(["Case 6: leaving the building turns interior_active back off", is_zero_approx(float(mat.get_shader_parameter("interior_active")))])

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
	print("RESULT (Building Interior Always Lit): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
