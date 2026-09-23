extends RefCounted
class_name BattleObstaclesTest
## Per the follow-up request ("let's review those obstacles... make
## detailed Tiles of these... let these offer varying degrees of
## cover"): confirms BattleGrid's multi-square obstacle rework — real
## footprint sizes (normal/large/huge/line/clump), passability (nothing
## but High Grass can be walked through), cover tiers (light/medium/
## hard, matching the -10/-20/-30 penalty table), "No line of sight
## above" restricted to Huge Boulder/Structure only, huge shapes never a
## filled rectangle, every type guaranteed to appear, and the new
## get_ranged_cover() line-of-sight/cover resolution — across many
## random rolls, not just one lucky seed. Also confirms the deployment
## zones stay clear/connected and the new decorative Mud ground patches
## never land on obstacle/impassable ground.

static func run_test() -> bool:
	var checks: Array = []

	## --- Repeated real generation: every invariant must hold on every
	## one of many random rolls. ---
	var all_types_seen: Dictionary = {}
	var all_sizes_correct := true
	var all_passability_correct := true
	var all_cover_correct := true
	var all_los_correct := true
	var all_huge_not_rectangular := true
	var all_start_zones_clear := true
	var all_connected := true
	var all_mud_clear_of_obstacles := true
	var all_not_overcrowded := true
	var ally_center := Vector2i(BattleGrid.ALLY_START_COL, BattleGrid.ROWS / 2)
	var adversary_center := Vector2i(BattleGrid.ADVERSARY_START_COL, BattleGrid.ROWS / 2)

	for i in range(20):
		var grid := BattleGrid.new()
		grid.generate_from_terrain_snapshot([])   ## fully open terrain -- isolates the scatter from terrain impassability

		for inst in grid.obstacles:
			var squares: Array = inst["squares"]
			## Per the follow-up request ("never surround a character or
			## monster with a obstacle more then 60% around them"):
			## BattleGrid's own thinning pass (_thin_overcrowded_pockets,
			## called from _scatter_obstacles) can remove an instance
			## after it was placed by clearing its "squares" to [] rather
			## than shrinking the `obstacles` array (see that function's
			## own comment on why) — such a slot never made it onto the
			## real map, so every check below skips it entirely rather
			## than reading it as, say, a "large" obstacle with an
			## invalid 0-square footprint.
			if squares.is_empty():
				continue
			var type_name: String = inst["type"]
			var size_class: String = inst["size_class"]
			all_types_seen[type_name] = true
			var props: Dictionary = BattleGrid.OBSTACLE_TYPES[type_name]

			## Footprint size matches its size class.
			match size_class:
				"normal":
					if squares.size() != 1:
						all_sizes_correct = false
				"large":
					if squares.size() != 4:
						all_sizes_correct = false
				"huge":
					if squares.size() < 9 or squares.size() > 20:
						all_sizes_correct = false
					var min_x := 999
					var max_x := -999
					var min_y := 999
					var max_y := -999
					for sq in squares:
						min_x = mini(min_x, sq.x)
						max_x = maxi(max_x, sq.x)
						min_y = mini(min_y, sq.y)
						max_y = maxi(max_y, sq.y)
					var w := max_x - min_x + 1
					var h := max_y - min_y + 1
					if w > 1 and h > 1 and squares.size() == w * h:
						all_huge_not_rectangular = false
				"line":
					if squares.size() < 3 or squares.size() > 9:
						all_sizes_correct = false
				"clump":
					if squares.size() < 1 or squares.size() > 5:
						all_sizes_correct = false

			## Per the request: "None of these can be moved through
			## except high grass."
			var should_be_passable: bool = (type_name == "HighGrass")
			for sq in squares:
				var is_passable: bool = not grid.impassable.has(sq)
				if is_passable != should_be_passable:
					all_passability_correct = false
				if BattleGrid.distance_squares(sq, ally_center) < BattleGrid.OBSTACLE_START_CLEARANCE:
					all_start_zones_clear = false
				if BattleGrid.distance_squares(sq, adversary_center) < BattleGrid.OBSTACLE_START_CLEARANCE:
					all_start_zones_clear = false

			## Cover tier matches the type table, and every covering
			## square is actually recorded in obstacle_cover.
			var expected_cover: String = props["cover"]
			if inst["cover"] != expected_cover:
				all_cover_correct = false
			for sq in squares:
				var recorded: String = grid.obstacle_cover.get(sq, "none")
				if recorded != expected_cover:
					all_cover_correct = false

			## "No line of sight above" is restricted to exactly the
			## size classes each type's blocks_los_at lists (per the
			## request: only Huge Boulder/Structure fully block a
			## sightline -- everything else, even hard cover, doesn't).
			var expected_los: bool = props["blocks_los_at"].has(size_class)
			if inst["blocks_los"] != expected_los:
				all_los_correct = false
			for sq in squares:
				if grid.blocks_los.has(sq) != expected_los:
					all_los_correct = false

		for sq in grid.mud.keys():
			if grid.impassable.has(sq) or grid.obstacle_group.has(sq):
				all_mud_clear_of_obstacles = false

		## Per the follow-up request ("never surround a character or
		## monster with a obstacle more then 60% around them"): re-checks
		## the exact invariant BattleGrid's own _thin_overcrowded_pockets
		## is supposed to have already enforced — every OPEN square
		## should have at most 60% of its in-bounds neighbours
		## impassable, independent of where any character/monster
		## actually happens to be standing.
		for y in range(BattleGrid.ROWS):
			for x in range(BattleGrid.COLS):
				var open_sq := Vector2i(x, y)
				if grid.impassable.has(open_sq):
					continue
				var neighbor_total := 0
				var neighbor_blocked := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var neighbor: Vector2i = open_sq + Vector2i(dx, dy)
						if not grid.is_in_bounds(neighbor):
							continue
						neighbor_total += 1
						if grid.impassable.has(neighbor):
							neighbor_blocked += 1
				if neighbor_total > 0 and float(neighbor_blocked) / float(neighbor_total) > 0.6:
					all_not_overcrowded = false

		var ally_open := grid.find_open_square_near(ally_center, {})
		var adversary_open := grid.find_open_square_near(adversary_center, {})
		if grid.is_walkable(ally_open) and grid.is_walkable(adversary_open):
			if grid.find_path(ally_open, adversary_open, {}).is_empty():
				all_connected = false
		else:
			all_connected = false

	checks.append(["Every obstacle type appears at least once across 20 rolls (guaranteed-one-of-each queue)", all_types_seen.size() == BattleGrid.OBSTACLE_TYPES.size()])
	checks.append(["Every footprint's square count matches its size class (normal=1, large=4, huge=9-20, line=3-9, clump=1-5)", all_sizes_correct])
	checks.append(["Nothing can be moved through except High Grass", all_passability_correct])
	checks.append(["Every obstacle square's cover tier matches BattleGrid.OBSTACLE_TYPES (light/medium/hard/none)", all_cover_correct])
	checks.append(["\"No line of sight above\" only ever applies at the Huge size, for Boulder/Structure specifically", all_los_correct])
	checks.append(["A Huge obstacle's footprint is never a perfectly filled rectangle", all_huge_not_rectangular])
	checks.append(["No obstacle ever lands inside either side's own start-zone clearance", all_start_zones_clear])
	checks.append(["The two deployment zones can always still reach each other after scattering", all_connected])
	checks.append(["Mud ground patches never overlap an obstacle or other impassable ground", all_mud_clear_of_obstacles])
	checks.append(["No open square is ever more than 60% surrounded by impassable neighbours", all_not_overcrowded])

	## --- Cover/LOS resolution, isolated from random placement. ---
	var g := BattleGrid.new()
	g.generate_from_terrain_snapshot([])
	g.obstacle_type.clear()
	g.obstacle_group.clear()
	g.obstacles.clear()
	g.obstacle_cover.clear()
	g.blocks_los.clear()
	g.impassable.clear()
	g.cover.clear()
	g.mud.clear()

	var attacker := Vector2i(5, 5)
	var target := Vector2i(5, 9)
	var open_cover: Dictionary = g.get_ranged_cover(attacker, target)
	checks.append(["get_ranged_cover(): open ground gives no penalty and never blocks the shot", not open_cover["blocked"] and open_cover["penalty"] == 0])

	g.obstacle_cover[Vector2i(5, 7)] = "hard"   ## sits directly on the line between attacker and target
	var hard_cover: Dictionary = g.get_ranged_cover(attacker, target)
	checks.append(["get_ranged_cover(): a hard-cover square on the line gives the full -30 penalty without blocking the shot", not hard_cover["blocked"] and hard_cover["penalty"] == -30])
	g.obstacle_cover.clear()

	g.obstacle_cover[Vector2i(5, 7)] = "medium"
	var medium_cover: Dictionary = g.get_ranged_cover(attacker, target)
	checks.append(["get_ranged_cover(): a medium-cover square on the line gives -20", medium_cover["penalty"] == -20])
	g.obstacle_cover.clear()

	g.blocks_los[Vector2i(5, 7)] = true
	var blocked: Dictionary = g.get_ranged_cover(attacker, target)
	checks.append(["get_ranged_cover(): an LOS-blocking square on the line refuses the shot outright (blocked=true)", blocked["blocked"]])
	g.blocks_los.clear()

	## --- Bug fix: a cover-granting square directly beside the ATTACKER
	## (e.g. a Tree at the shooter's own shoulder) must not count as
	## cover for the target, even though a near-diagonal line can graze
	## it as an early step. Vector2i(6, 6) is Chebyshev distance 1 from
	## attacker (5,5) -- diagonally adjacent -- and does sit on the
	## direct line to a target chosen along that same diagonal.
	var diag_target := Vector2i(5 + 4, 5 + 4)   ## (9, 9) -- attacker's own diagonal, so (6,6) is genuinely on the line
	g.obstacle_cover[Vector2i(6, 6)] = "hard"
	var beside_attacker: Dictionary = g.get_ranged_cover(attacker, diag_target)
	checks.append(["get_ranged_cover(): a hard-cover square immediately beside the ATTACKER does NOT count as cover for a distant target", not beside_attacker["blocked"] and beside_attacker["penalty"] == 0 and beside_attacker["level"] == "none"])
	g.obstacle_cover.clear()

	## ...but the same exemption must NOT extend to cover near the
	## target, or anywhere else genuinely between them -- only squares
	## touching the attacker's own square are exempt.
	g.obstacle_cover[Vector2i(8, 8)] = "hard"   ## adjacent to the target (9,9), far from the attacker
	var beside_target: Dictionary = g.get_ranged_cover(attacker, diag_target)
	checks.append(["get_ranged_cover(): the same hard-cover square near the TARGET still fully applies", not beside_target["blocked"] and beside_target["penalty"] == -30])
	g.obstacle_cover.clear()

	## ...and if there's cover beside the attacker AND real cover
	## further along the line, the real cover still applies (the
	## adjacent-to-attacker square is just skipped, not treated as
	## invalidating the whole line).
	g.obstacle_cover[Vector2i(6, 6)] = "hard"   ## beside attacker -- exempt
	g.obstacle_cover[Vector2i(7, 7)] = "medium"   ## genuinely midway -- still counts
	var mixed_cover: Dictionary = g.get_ranged_cover(attacker, diag_target)
	checks.append(["get_ranged_cover(): real cover further along the line still applies even with an exempt square beside the attacker", not mixed_cover["blocked"] and mixed_cover["penalty"] == -20])
	g.obstacle_cover.clear()

	## A genuinely sight-blocking (Huge) obstacle immediately beside the
	## attacker still refuses the shot -- the attacker-adjacency
	## exemption is scoped to the cover-tier judgement call only, not to
	## a real LOS block.
	g.blocks_los[Vector2i(6, 6)] = true
	var blocked_beside_attacker: Dictionary = g.get_ranged_cover(attacker, diag_target)
	checks.append(["get_ranged_cover(): an LOS-blocking square beside the attacker still blocks the shot outright", blocked_beside_attacker["blocked"]])
	g.blocks_los.clear()

	## has_line_of_sight() itself, unchanged mechanically from before.
	checks.append(["has_line_of_sight() is true across open ground", g.has_line_of_sight(attacker, target)])
	g.blocks_los[Vector2i(5, 7)] = true
	checks.append(["has_line_of_sight() is false once an LOS-blocking square sits directly between the two points", not g.has_line_of_sight(attacker, target)])
	g.blocks_los.clear()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Battle Obstacles): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
