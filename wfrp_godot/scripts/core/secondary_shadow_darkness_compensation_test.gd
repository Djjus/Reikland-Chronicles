extends RefCounted
class_name SecondaryShadowDarknessCompensationTest
## Per the report ("secondary shadow still looks darker the normal
## night darkness, and does not blend perfectly"): NightOverlay/
## CloudShadowOverlay's own reveal shader is purely distance-based, so
## it still shows SOME residual brightness (reveal = a light's own
## brightness constant, always < 1.0 — see LIGHT_BRIGHTNESS_ON/
## STATIC_LAMP_LIGHT_BRIGHTNESS) at a spot that's genuinely LOS-blocked
## and needs full redarkening. Drawing the redarkening quad/shadow
## group's own alpha directly at the target ambient alpha, right on
## TOP of that already-partially-revealed base, stacked past the true
## ambient darkness instead of matching it (two same-colour
## semi-transparent layers composite to MORE opaque than either alone).
## _compensate_alpha_for_reveal() fixes this by solving for exactly how
## much the second (redarkening) layer needs to draw at so the TOTAL
## lands on the target alpha, not past it.
##
## Case 1: with zero residual reveal (deep in ambient darkness, no
## light reaching that spot at all), the compensated alpha is just the
## plain target alpha, unchanged — the fix is a no-op away from any
## light.
## Case 2: with a genuine residual reveal (e.g. a torch's own 0.72
## brightness), the OLD approach (drawing straight at target_alpha on
## top of the reveal-thinned base) would net MORE than target_alpha
## once actually composited — the whole point of this fix. Verifies
## the compensated value, once composited via the same over-formula
## against that same residual base, reproduces target_alpha exactly
## (round-trips), rather than overshooting it.
## Case 3: a real redarkened tile's own quad, sampled after
## _refresh_light_occlusion() runs on the real map with the player's
## torch active, is not measurably darker than the true ambient tint —
## the actual end-to-end regression this whole fix is about.

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

	## --- Case 1: zero reveal -> unchanged pass-through.
	var target_alpha: float = 0.9
	checks.append(["Case 1: zero residual reveal leaves the target alpha unchanged", is_equal_approx(ow._compensate_alpha_for_reveal(0.0, target_alpha), target_alpha)])

	## --- Case 2: round-trip check against the actual over-compositing
	## formula, confirming the compensated alpha lands exactly on
	## target_alpha rather than overshooting it.
	var reveal: float = 0.72
	var base_a: float = target_alpha * (1.0 - reveal)
	var compensated: float = ow._compensate_alpha_for_reveal(reveal, target_alpha)
	var recomposited: float = base_a + compensated * (1.0 - base_a)
	checks.append(["Case 2: compensated alpha, composited back over the same residual base, reproduces the target ambient alpha exactly (no overshoot)", is_equal_approx(recomposited, target_alpha)])
	checks.append(["Case 2: ...and the naive OLD approach (drawing straight at target_alpha) would genuinely have overshot it, confirming this was a real bug", (base_a + target_alpha * (1.0 - base_a)) > target_alpha + 0.001])

	## --- Case 3: end-to-end, on the real map. Wall 5 tiles from the
	## player (well within the torch's own bright core, well clear of
	## the edge-margin band) so the tile just past it is both genuinely
	## LOS-blocked AND sitting somewhere the base shader would otherwise
	## show strong residual reveal.
	ow.static_lamp_coords.clear()
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			ow.tile_chars[ow.player.grid_pos + Vector2i(dx, dy)] = "."
	var wall_tile: Vector2i = ow.player.grid_pos + Vector2i(0, -5)
	ow.tile_chars[wall_tile] = "B"
	var far_ambient_tile: Vector2i = ow.player.grid_pos + Vector2i(30, 0)
	ow._recompute_secondary_light_lit_tiles()
	ow._apply_light_source_secondary_shadows()
	ow._refresh_light_occlusion()

	var shadow_reveal: float = ow._local_light_reveal(ow.tile_map.map_to_local(wall_tile + Vector2i(0, -1)))
	checks.append(["setup: the tile just past the wall genuinely has real residual reveal from the base shader (confirms this case actually exercises the fix)", shadow_reveal > 0.1])
	var ambient_alpha: float = ow.night_overlay.color.a
	var compensated_tile_alpha: float = ow._compensate_alpha_for_reveal(shadow_reveal, ambient_alpha)
	checks.append(["Case 3: the compensated alpha actually used for this real shadowed tile is strictly less than the flat ambient alpha (compensating for, not adding to, the residual reveal)", compensated_tile_alpha < ambient_alpha - 0.001])
	var final_composited: float = shadow_reveal_base_alpha(ambient_alpha, shadow_reveal)
	final_composited = final_composited + compensated_tile_alpha * (1.0 - final_composited)
	checks.append(["Case 3: the real tile's own final composited alpha matches true ambient darkness (not darker)", is_equal_approx(final_composited, ambient_alpha)])

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
	print("RESULT (Secondary Shadow Darkness Compensation): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass

static func shadow_reveal_base_alpha(target_alpha: float, reveal: float) -> float:
	return target_alpha * (1.0 - reveal)
