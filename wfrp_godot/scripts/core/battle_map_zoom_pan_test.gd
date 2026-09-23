extends RefCounted
class_name BattleMapZoomPanTest
## Per the request ("make zooming out on the battle map easier, right
## now it get stuck on the edges and its difficult to pan around, have
## the map float in the middle and allow it to go over the edge of the
## map when panning/zoom"): confirms BattleGridView._clamp_pan() no
## longer hard-locks panning to exactly 0 on an axis the content
## already fits on (the old "stuck" behavior at any zoom level close to
## or below fit), that a real drag can push the map's edge past the
## viewport's own edge (blank space allowed, not forced full coverage),
## and that panning is still genuinely bounded (not infinite) so the
## map can't be lost off in space forever. Uses the real FieldEncounter
## scene's own BattleGridView (via %BattleGridView), not a standalone
## instance, so this exercises the exact same node/sizing the player
## actually sees.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	var fe_scene: PackedScene = load("res://scenes/FieldEncounter.tscn")
	var fe: Node = fe_scene.instantiate()
	tree.get_root().add_child.call_deferred(fe)
	await tree.process_frame
	await tree.process_frame

	var grid_view: BattleGridView = fe.get_node("%BattleGridView")
	checks.append(["Found the real BattleGridView node", grid_view != null])
	if grid_view == null:
		fe.queue_free()
		return false

	## Force a known, real size (this control fills CenterCol normally,
	## but forcing it here makes the exact numbers below deterministic
	## regardless of the surrounding layout/window size this test runs
	## under).
	grid_view.size = Vector2(900.0, 540.0)
	await tree.process_frame

	## --- Zoomed out enough that the whole map already fits: panning
	## used to be hard-disabled (forced to exactly 0) on any axis the
	## content fit within `size`. Now a real drag should stick, not
	## snap back to 0 -- that's the literal "stuck" complaint.
	grid_view.zoom_level = grid_view.MIN_ZOOM   ## 0.6667 -- the "whole map visible" level
	grid_view.pan_offset = Vector2.ZERO
	grid_view.pan_offset += Vector2(40.0, 25.0)
	grid_view._clamp_pan()
	checks.append(["At the fits-whole-map zoom level, a real drag no longer snaps back to exactly 0 on X", not is_equal_approx(grid_view.pan_offset.x, 0.0)])
	checks.append(["...same for Y", not is_equal_approx(grid_view.pan_offset.y, 0.0)])

	## --- The map should still default to floating centered (pan
	## untouched == 0) rather than this being a behavior change to the
	## default view itself.
	grid_view.pan_offset = Vector2.ZERO
	grid_view._clamp_pan()
	checks.append(["Leaving pan alone still leaves the map centered (pan stays at 0,0) by default", grid_view.pan_offset.is_equal_approx(Vector2.ZERO)])

	## --- At a zoom level where the map overflows the viewport, the old
	## clamp forced pan to keep content fully covering `size` (zero
	## blank space ever). Confirm a real drag can now push far enough
	## that the content's edge crosses past the viewport's own edge --
	## i.e. pan_offset.x can go beyond the old tight "must fully cover"
	## bound of `-zoom*origin.x` (which would show blank space to the
	## right of the grid's left edge).
	grid_view.zoom_level = 1.0
	var square_px: float = grid_view._square_px()
	var origin: Vector2 = grid_view._grid_origin(square_px)
	var old_tight_max_x: float = -grid_view.zoom_level * origin.x
	grid_view.pan_offset = Vector2(old_tight_max_x + 10000.0, 0.0)   ## a wild drag, far past the old wall
	grid_view._clamp_pan()
	checks.append(["A real drag can now push the map's edge past the viewport's own edge (old tight bound was exceedable)", grid_view.pan_offset.x > old_tight_max_x])

	## --- ...but it's still genuinely bounded, not infinite -- the
	## wild drag above must have been reined in somewhere reasonable,
	## not left sitting at the raw +10000 it was pushed to.
	checks.append(["...but panning is still genuinely bounded, not infinite (didn't just accept the raw +10000 push)", grid_view.pan_offset.x < old_tight_max_x + 10000.0])

	## --- Symmetric check on the opposite (negative) direction and on
	## the Y axis too, so this isn't just checking one corner.
	var content_size: Vector2 = Vector2(square_px * BattleGrid.COLS, square_px * BattleGrid.ROWS) * grid_view.zoom_level
	var old_tight_min_x: float = grid_view.size.x - content_size.x - grid_view.zoom_level * origin.x
	grid_view.pan_offset = Vector2(old_tight_min_x - 10000.0, 0.0)
	grid_view._clamp_pan()
	checks.append(["...same freedom in the opposite direction (X)", grid_view.pan_offset.x < old_tight_min_x])
	checks.append(["...and still bounded in that direction too", grid_view.pan_offset.x > old_tight_min_x - 10000.0])

	## --- _square_at() (the click/hover -> grid-square converter) must
	## still correctly invert whatever transform _draw() actually used,
	## even with a real overscrolled pan in effect -- otherwise clicks
	## would land on the wrong square whenever the map's been dragged
	## past its old tight bounds.
	grid_view.zoom_level = 1.0
	grid_view.pan_offset = Vector2.ZERO
	grid_view._clamp_pan()
	var sq_px: float = grid_view._square_px()
	var grid_origin: Vector2 = grid_view._grid_origin(sq_px)
	var center_of_square_0_0: Vector2 = grid_origin + Vector2(sq_px * 0.5, sq_px * 0.5)
	var screen_pos: Vector2 = grid_view.pan_offset + grid_view.zoom_level * center_of_square_0_0
	checks.append(["_square_at() still correctly resolves a click back to square (0,0) after a real pan/zoom round-trip", grid_view._square_at(screen_pos) == Vector2i(0, 0)])

	fe.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Battle Map Zoom/Pan Overscroll Check): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
