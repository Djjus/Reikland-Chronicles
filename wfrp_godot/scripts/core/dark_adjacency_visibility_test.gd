extends RefCounted
class_name DarkAdjacencyVisibilityTest
## Regression test for the request: "when in combat with no light,
## Creatures should become visible to the player once if they are
## standing next to them (i.e. adjacent cells)."
##
## BattleGridView._draw()'s token loop hides anyone standing on a cell
## the party's own light hasn't reached (fog-of-war vis < 2) — correct
## for a monster lurking two rooms away in the dark, but wrong for one
## that's walked right up next to the party: at that range you'd
## obviously see/hear/feel them even without a light source. The fix
## lives in BattleGridView.is_adjacent_to_living_ally(), a standalone
## static helper _draw() consults before hiding a token — pure and
## parameter-only (no live scene needed), so this test calls it
## directly rather than needing a real render pass.

static func _make_character(name: String, allegiance: String, pos_wounds: int = 10) -> Character:
	var c := Character.new()
	c.character_name = name
	c.allegiance = allegiance
	c.wounds_max = pos_wounds
	c.wounds_current = pos_wounds
	c.conditions = {}
	return c

static func run_test(_tree) -> bool:
	var checks: Array = []

	var ally := _make_character("Ally", "ally")
	var adjacent_monster := _make_character("AdjacentGoblin", "adversary")
	var far_monster := _make_character("FarGoblin", "adversary")
	var down_ally := _make_character("DownedAlly", "ally", 0)
	down_ally.wounds_current = 0

	var positions := {
		ally: Vector2i(5, 5),
		adjacent_monster: Vector2i(6, 5),   ## directly east -- distance 1 (orthogonal)
		far_monster: Vector2i(9, 9),        ## far away -- well outside any adjacency
	}

	## --- Core case: a monster standing right next to a living ally is
	## treated as visible even though the party's own light hasn't
	## reached that cell.
	checks.append(["Case 1: a monster on the cell directly next to a living ally counts as adjacent", BattleGridView.is_adjacent_to_living_ally(positions[adjacent_monster], 1, positions)])
	checks.append(["Case 1: a monster far from every ally does NOT count as adjacent", not BattleGridView.is_adjacent_to_living_ally(positions[far_monster], 1, positions)])

	## --- Diagonal adjacency also counts (this project's own
	## distance_squares is Chebyshev, matching "8 neighbor directions" --
	## see BattleGrid.distance_squares' own comment).
	checks.append(["Case 2: a monster diagonally adjacent to a living ally also counts", BattleGridView.is_adjacent_to_living_ally(Vector2i(6, 6), 1, positions)])

	## --- A downed/Unconscious ally isn't perceiving anything, so
	## doesn't grant adjacency visibility on its own.
	var down_positions := {down_ally: Vector2i(6, 5)}
	checks.append(["Case 3: a downed ally's own adjacency does not reveal a monster next to it", not BattleGridView.is_adjacent_to_living_ally(Vector2i(7, 5), 1, down_positions)])

	## --- Footprint-aware: a Large (2x2) ally's whole body counts, not
	## just its anchor cell -- a monster next to the FAR edge of a big
	## ally's footprint should still count.
	var big_ally := _make_character("BigAlly", "ally")
	big_ally.creature_traits.append("Size (Large)")
	checks.append(["Case 4a: sanity -- the test ally is genuinely footprint_size 2", big_ally.get_footprint_size() == 2])
	var big_positions := {big_ally: Vector2i(0, 0)}   ## occupies (0,0)-(1,1) at footprint_size 2
	checks.append(["Case 4b: a monster next to the far edge of a Large ally's footprint still counts as adjacent", BattleGridView.is_adjacent_to_living_ally(Vector2i(2, 1), 1, big_positions)])
	checks.append(["Case 4c: a monster two squares past that same edge does NOT count", not BattleGridView.is_adjacent_to_living_ally(Vector2i(3, 1), 1, big_positions)])

	## --- Wiring sanity: confirm the actual _draw() token loop reads
	## this exact helper (catches a future refactor accidentally
	## un-wiring the call) rather than duplicating the logic inline
	## again.
	var src := FileAccess.get_file_as_string("res://scripts/ui/battle_grid_view.gd")
	checks.append(["Case 5: _draw()'s token-hiding branch actually calls is_adjacent_to_living_ally()", src.find("is_adjacent_to_living_ally(pos, c.get_footprint_size(), positions)") != -1])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Dark Adjacency Visibility): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
