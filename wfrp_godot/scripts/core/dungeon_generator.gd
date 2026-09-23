extends RefCounted
class_name DungeonGenerator
## v2 dungeon generator, per the request's own explicit "New Dungeon
## building rules": a tile-by-tile builder driven entirely by dice
## tables, replacing the earlier fixed-shape (one T-junction, two
## branch corridors, two big end rooms) random-walk generator.
##
## Fixed opening (never rolled): a 2x2 entrance/stairs tile, then one
## 5x2 Straight passage tile, then a 2x2 T-junction leading left and
## right. From there, every branch independently keeps building:
## after every corner or junction, roll the Passage Length Table (D12)
## for the next Straight segment, then the Passage Features Table
## (2D12) on that segment (wandering monsters / nothing / 1 door / 2
## doors, doors leading to a room each), then the Passage End Table
## (D12) for what comes after it (T-junction / dead end / right turn /
## left turn). A room's own size/type is rolled off the Room Size
## Table for whatever tier its position in the room count falls into
## (0-2 / 3-4 / 5+ rooms already placed), which can itself roll the
## Hazard Table (D3) for a Small room. See DungeonThemeDefinition for
## the Monster Table (Quest room / Monster Lair / Monster Patrol).
##
## Per the user's own explicit answer on dungeon size ("stop generating
## after the Quest room is added, cap any remaining open passages with
## dead ends"): the moment a Quest room is placed, every other branch
## still queued for building is left exactly where it stands (never
## extended further) — see `_Ctx.stop_building`. A safety valve
## (`_force_quest_room`) guarantees a Quest room exists even in the
## unlucky case none ever rolled naturally (the Room Size Table only
## offers "Large (Quest room)" once at least 3 rooms already exist).
##
## Per the request's other hard rule ("Ensure passages and rooms do
## never cross eachother or touch each other along their wall sides,
## adjust according regarless of rolls"): every placement (segment,
## turn/junction block, door+room) is checked against everything
## already built via `_Ctx.fits()` before it's committed; a placement
## that doesn't fit is simply skipped (a door silently doesn't
## attach a room, a turn/junction the branch just dead-ends at)
## rather than ever forcing an overlap or an illegal touch.
##
## Returns a plain Dictionary (a "DungeonState"), not a Resource — see
## to_save_data()/from_save_data() at the bottom for the JSON-safe
## round-trip boundary, same convention the rest of this project's save
## data already uses.

const MAX_GENERATION_ATTEMPTS := 20

## Per the "Sewer/Cave Dungeons update 2" request ("Upto 3 floors down,
## so total of 4 floors including the ground floor"): the ground floor
## is floor_index 0, so the deepest a Quest room's own stairs can ever
## lead to is floor_index 3 — a Quest room generated AT floor_index 3
## rolls no stairs_pos at all (see _attempt_room_at()/_force_quest_room()
## below), since there is no floor 4.
const MAX_DUNGEON_FLOOR := 3

## A door is a CORRIDOR_SCALE-long, 1-cell-thick line of existing ROOM
## cells (the room's own near-face cells that sit directly against the
## corridor's rail — no separate floor tile of its own gets carved for
## it) — per the follow-up request ("have door attachable to existing
## passage and room tiles, don't make they have their own 2x2 tile").
## The room is placed with ZERO gap against the corridor's rail, so the
## room and the corridor touch each other along exactly this
## CORRIDOR_SCALE-long span (the door itself) and nowhere else — see
## _attempt_room_at()'s own comment for the geometry. Kept as its own
## named constant since field_encounter_screen.gd's door-opening logic
## (_room_at_door/_door_block_cells) and battle_grid.gd's door-line
## renderer (_build_door_edges) both key off this exact span length.
## This generator's own corridor width also happens to equal
## CORRIDOR_SCALE, but that's this generator's own choice (STRAIGHT/TURN
## dimensions below), independent of why a door's span needs to match it
## (a door has to be exactly as wide as the corridor it opens onto).
const CORRIDOR_SCALE := 2

## Tile module dimensions, in final battle-grid squares — this generator
## builds directly in final grid space (no separate coarse-cell pass the
## way the old branch-random-walk generator needed).
const STRAIGHT_SHORT := 5
const STRAIGHT_LONG := 10
const TURN_SIZE := 2                 ## also the T-junction block size — matches corridor width exactly, the natural pivot shape
const OPENING_STRAIGHT_LEN := 5      ## the one FIXED intro straight, never rolled — see the request's own fixed opening sequence
const SMALL_ROOM_SIZE := 4
const LARGE_ROOM_WIDTH := 4
const LARGE_ROOM_DEPTH := 8

const MAX_OPEN_END_ITERATIONS := 400   ## hard safety valve against any runaway branch growth; never actually reached in practice
const CHEBYSHEV_DIRS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

## --- Generation context -------------------------------------------------
## Threaded through every helper below instead of passing 6-7 loose
## params everywhere. Not a Resource/autoload — a fresh one per
## _generate_once() attempt.
class _Ctx:
	var rng: RandomNumberGenerator
	var theme: DungeonThemeDefinition
	var occupied: Dictionary = {}      ## Vector2i -> true, every walkable cell this dungeon has ever placed (floor + door + entrance)
	var door_cells: Dictionary = {}    ## Vector2i -> true, subset of occupied — rendered as door_closed_char
	var rooms: Array = []
	var hallway_segments: Array = []
	var room_count: int = 0
	var quest_placed: bool = false
	var stop_building: bool = false    ## per the user's own answer: true from the instant the Quest room is placed
	var entrance_pos: Vector2i = Vector2i.ZERO
	## Per the "Sewer/Cave Dungeons update 2" request ("stairs going down
	## in the Quest room... will lead to the next floor"): 0 on the
	## ground floor, incrementing by 1 each time the party takes a
	## generated Quest room's own stairs down, up to MAX_DUNGEON_FLOOR.
	## Threaded through generate()/_generate_once() purely so the Quest
	## room knows whether it's still allowed to roll its own stairs_pos
	## (see _attempt_room_at()/_force_quest_room() below) — the floor
	## itself doesn't otherwise change how this generator builds a
	## layout at all.
	var floor_index: int = 0

	func _init(t: DungeonThemeDefinition, r: RandomNumberGenerator, f: int = 0) -> void:
		theme = t
		rng = r
		floor_index = f

	## True if every cell in `cells` is free (not already occupied) AND no
	## cell in `cells` is orthogonally adjacent to an already-occupied
	## cell UNLESS that neighbour is either part of THIS SAME batch (an
	## expected self-adjacency, e.g. consecutive cells of one straight
	## segment) or explicitly whitelisted via `allowed_touch` (the
	## specific predecessor cells this placement is meant to connect to —
	## see _rail_cells_at()). This is what actually enforces "never cross
	## or touch along wall sides" — any OTHER adjacency to a foreign,
	## unconnected feature fails the check.
	func fits(cells: Array, allowed_touch: Dictionary) -> bool:
		var batch: Dictionary = {}
		for c in cells:
			if occupied.has(c):
				return false
			batch[c] = true
		for c in cells:
			for d in CHEBYSHEV_DIRS:
				var n: Vector2i = c + d
				if occupied.has(n) and not batch.has(n) and not allowed_touch.has(n):
					return false
		return true

	func commit(cells: Array) -> void:
		for c in cells:
			occupied[c] = true

static func generate(theme: DungeonThemeDefinition, rng: RandomNumberGenerator, floor_index: int = 0) -> Dictionary:
	var best: Dictionary = {}
	for attempt in range(MAX_GENERATION_ATTEMPTS):
		var state := _generate_once(theme, rng, floor_index)
		if _validate(state, theme):
			return state
		best = state   ## keep the last attempt as a fail-open fallback
	return best

## Per the Goblin Fort rework request ("Change it to a Dungeon map,
## single large square area 8x16 cells... No hazard rules"): a hand-
## authored, non-procedural alternative to generate() above — this
## theme's dungeon is always exactly the same one fixed rectangular
## room, never dice-table-generated, and never rolls the Hazard Table
## at all (no small/small_hazard/large_lair distinction — just one open
## floor). Returns the same DungeonState Dictionary shape generate()
## does (grid_rows/entrance_pos/rooms/hallway_segments/visibility/
## player_grid_pos/exit_used) so every existing reader (battle_grid.gd,
## field_encounter_screen.gd) works completely unchanged — `rooms` and
## `hallway_segments` are simply empty, since there's no door-opening or
## corridor-wandering-monster mechanic here at all: the on-entry ambush
## (see _start_exploration_mode()'s own goblin-fort branch) and the
## chest trap/reward (see the chest fields below) are both bespoke,
## same as the Goblin Fort's existing overworld chest already was.
##
## `chest_pos` is a NEW key, not part of the generate()-shaped state —
## harmless to every reader above (all `.get()` calls elsewhere), read
## only by the new dungeon-chest UI this feature adds (task: relocate
## chest into dungeon room).
static func generate_fixed_room(theme: DungeonThemeDefinition, width: int, height: int) -> Dictionary:
	## Entrance at the bottom-center of the room, chest at the far
	## (top-center) end — per the request, "the treasure chest at the
	## far end" from wherever the party walks in.
	var entrance_pos := Vector2i(int(width / 2.0), height - 1)
	var chest_pos := Vector2i(int(width / 2.0), 0)

	var grid_rows: Array = []
	## One cell of wall border all the way around, same convention
	## _build_grid_rows() above uses for the procedural generator.
	grid_rows.append(theme.wall_char.repeat(width + 2))
	for y in range(height):
		var row := theme.wall_char
		for x in range(width):
			var cell := Vector2i(x, y)
			if cell == entrance_pos:
				row += theme.entrance_char
			else:
				row += theme.floor_char
		row += theme.wall_char
		grid_rows.append(row)
	grid_rows.append(theme.wall_char.repeat(width + 2))

	## _build_grid_rows() bakes in a 1-cell margin (see its own min_x-=1
	## etc.), so every coordinate here shifts by (1, 1) to land inside
	## that same border, matching generate()'s own offset convention.
	var offset := Vector2i(1, 1)
	var shifted_entrance: Vector2i = entrance_pos + offset
	var shifted_chest: Vector2i = chest_pos + offset

	var visibility: Dictionary = {}
	visibility[shifted_entrance] = 2

	return {
		"theme_id": theme.theme_id,
		"grid_rows": grid_rows,
		"entrance_pos": shifted_entrance,
		"rooms": [],
		"hallway_segments": [],
		"visibility": visibility,
		"player_grid_pos": shifted_entrance,
		"exit_used": false,
		"chest_pos": shifted_chest,
		## Per the request ("random greenskin fight when they enter"): a
		## one-shot forced fight the FIRST time the party ever sets foot
		## in this dungeon — never re-fires on a later save/reload
		## resume of the same dungeon_state. Set true by
		## field_encounter_screen.gd's own _start_exploration_mode() the
		## moment it actually fires the fight.
		"entry_ambush_fired": false,
		## The Goblin Fort chest's own state — ported 1:1 from the old
		## overworld GameState.goblin_fort_chest_locked/looted/
		## trap_spotted fields (see field_encounter_screen.gd's chest
		## functions), just living on dungeon_state instead so it
		## naturally resets every time the party re-enters the fort
		## (dungeon_state is regenerated fresh each visit).
		"chest_locked": true,
		"chest_looted": false,
		"chest_trap_spotted": false,
	}

## --- One generation attempt -------------------------------------------

static func _generate_once(theme: DungeonThemeDefinition, rng: RandomNumberGenerator, floor_index: int = 0) -> Dictionary:
	var ctx := _Ctx.new(theme, rng, floor_index)

	## Entrance/stairs: a 2x2 floor block (matching corridor width, same
	## as every other tile module here) — only its own top-left cell
	## renders with entrance_char, the other 3 are plain floor, exactly
	## like the earlier real-tile-art rework's single-icon convention.
	var entrance_cells: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	ctx.commit(entrance_cells)
	ctx.entrance_pos = Vector2i(0, 0)

	## Fixed opening: 1 straight 5x2 passage, then a T-junction leading
	## left and right — per the follow-up request ("remove one of the
	## passages, so keep it at entrance, 1x 5x2 passage way and t
	## junction"), this part is never rolled.
	var cursor_origin := Vector2i(0, -1)
	var cursor_dir := Vector2i(0, -1)
	var opening_seg: Dictionary = _segment_cells(cursor_origin, cursor_dir, OPENING_STRAIGHT_LEN)
	ctx.commit(opening_seg["cells"])
	cursor_origin = opening_seg["next_origin"]

	var junction: Dictionary = _segment_cells(cursor_origin, cursor_dir, TURN_SIZE)
	ctx.commit(junction["cells"])
	var east_origin: Vector2i = _turn_exit(cursor_origin, cursor_dir, Vector2i(1, 0))
	var west_origin: Vector2i = _turn_exit(cursor_origin, cursor_dir, Vector2i(-1, 0))
	var open_ends: Array = [
		{"origin": east_origin, "dir": Vector2i(1, 0)},
		{"origin": west_origin, "dir": Vector2i(-1, 0)},
	]

	## Main build loop — every open branch keeps rolling Length ->
	## Features -> End until it dead-ends, collides (see _Ctx.fits), or
	## the Quest room has been placed anywhere (ctx.stop_building), at
	## which point every remaining queued end is left capped as-is.
	var iterations := 0
	while not open_ends.is_empty() and iterations < MAX_OPEN_END_ITERATIONS:
		iterations += 1
		var end: Dictionary = open_ends.pop_back()
		if ctx.stop_building:
			continue
		_build_from_open_end(ctx, end, open_ends)

	## Safety valve, per the request ("ensure there will be a Quest room,
	## and that it is reachable"): the Room Size Table only ever offers
	## "Large (Quest room)" from the 3-4/5+ room-count tiers, so an
	## unlucky run of rolls could in principle finish without one ever
	## appearing — force the last eligible room to become it rather than
	## ship a dungeon with no quest at all. Every room placed by this
	## generator is, by construction, reachable from the entrance (it's
	## one single connected structure grown outward from it), so simply
	## having a Quest room at all satisfies "and that it is reachable".
	if not ctx.quest_placed:
		_force_quest_room(ctx)

	var grid_rows: Array = _build_grid_rows(ctx)
	var offset: Vector2i = _grid_offset(ctx)
	var shifted_entrance: Vector2i = ctx.entrance_pos + offset
	var shifted_rooms: Array = []
	for room in ctx.rooms:
		var rect: Rect2i = room["rect"]
		room["rect"] = Rect2i(rect.position + offset, rect.size)
		room["door_pos"] = room["door_pos"] + offset
		room["spawn_far_corner"] = room["spawn_far_corner"] + offset
		var hp: Vector2i = room.get("hazard_pos", Vector2i(-1, -1))
		if hp != Vector2i(-1, -1):
			room["hazard_pos"] = hp + offset
		var hc: Array = room.get("hazard_cells", [])
		if not hc.is_empty():
			var shifted_hc: Array = []
			for c in hc:
				shifted_hc.append(c + offset)
			room["hazard_cells"] = shifted_hc
		## Bug fix: the Room Furniture Table / Quest room chest fields
		## (added for the "Sewer/Cave Dungeons update" request) are all
		## computed in _attempt_room_at()/_force_quest_room() BEFORE this
		## grid-offset shift ever runs, same as hazard_pos/hazard_cells
		## above — they need the exact same + offset treatment or they
		## end up pointing at stale pre-shift coordinates that fall
		## outside the room's own (now-shifted) rect entirely.
		var cp: Vector2i = room.get("chest_pos", Vector2i(-1, -1))
		if cp != Vector2i(-1, -1):
			room["chest_pos"] = cp + offset
		var fa: Vector2i = room.get("furniture_anchor", Vector2i(-1, -1))
		if fa != Vector2i(-1, -1):
			room["furniture_anchor"] = fa + offset
		var fc: Array = room.get("furniture_cells", [])
		if not fc.is_empty():
			var shifted_fc: Array = []
			for c in fc:
				shifted_fc.append(c + offset)
			room["furniture_cells"] = shifted_fc
		## Same treatment for the new stairs_pos (Sewer/Cave Dungeons
		## update 2) -- computed pre-shift in _attempt_room_at()/
		## _force_quest_room() just like chest_pos above.
		var sp: Vector2i = room.get("stairs_pos", Vector2i(-1, -1))
		if sp != Vector2i(-1, -1):
			room["stairs_pos"] = sp + offset
		shifted_rooms.append(room)
	var shifted_segments: Array = []
	for seg in ctx.hallway_segments:
		var shifted_cells: Array = []
		for c in seg["cells"]:
			shifted_cells.append(c + offset)
		seg["cells"] = shifted_cells
		shifted_segments.append(seg)

	var visibility: Dictionary = {}
	visibility[shifted_entrance] = 2

	return {
		"theme_id": theme.theme_id,
		"grid_rows": grid_rows,
		"entrance_pos": shifted_entrance,
		"rooms": shifted_rooms,
		"hallway_segments": shifted_segments,
		"visibility": visibility,
		"player_grid_pos": shifted_entrance,
		"exit_used": false,
		## Per the "Sewer/Cave Dungeons update 2" request: which floor this
		## generated layout IS (0 = ground floor) -- read by
		## field_encounter_screen.gd to scale difficulty tier / item
		## quality / money rewards, and by this same generator's own Quest
		## room stairs logic (see _attempt_room_at()) to know whether it's
		## still allowed to roll a stairs_pos at all.
		"dungeon_floor": floor_index,
	}

## --- Geometry helpers ---------------------------------------------------

## A straight run of `length` cells (each 2 wide, perpendicular to `dir`)
## starting at `origin` and heading `dir`. `origin` is always the FIRST
## new cell (i.e. already one step past whatever it's extending from),
## consistent regardless of `dir`'s sign — see _rail_cells_at() for how a
## caller finds the predecessor cells this connects to.
static func _segment_cells(origin: Vector2i, dir: Vector2i, length: int) -> Dictionary:
	var cells: Array = []
	var next_origin: Vector2i
	if dir.x == 0:
		for i in range(length):
			var y: int = origin.y + i * dir.y
			cells.append(Vector2i(origin.x, y))
			cells.append(Vector2i(origin.x + 1, y))
		next_origin = Vector2i(origin.x, origin.y + length * dir.y)
	else:
		for i in range(length):
			var x: int = origin.x + i * dir.x
			cells.append(Vector2i(x, origin.y))
			cells.append(Vector2i(x, origin.y + 1))
		next_origin = Vector2i(origin.x + length * dir.x, origin.y)
	return {"cells": cells, "next_origin": next_origin, "origin": origin, "dir": dir, "length": length}

## The 2-wide rail `step` cells behind `origin` along `dir` — step=-1
## gives the immediately-preceding placement's own last row/column,
## which is always a legitimate connection point for _Ctx.fits()'s
## `allowed_touch`, never a "foreign" touch.
static func _rail_cells_at(origin: Vector2i, dir: Vector2i, step: int) -> Dictionary:
	var out: Dictionary = {}
	if dir.x == 0:
		var y: int = origin.y + step * dir.y
		out[Vector2i(origin.x, y)] = true
		out[Vector2i(origin.x + 1, y)] = true
	else:
		var x: int = origin.x + step * dir.x
		out[Vector2i(x, origin.y)] = true
		out[Vector2i(x, origin.y + 1)] = true
	return out

## "Turn right" / "turn left" relative to a current heading — a
## consistent 90-degree rotation either way (north->east->south->west->
## north for _right_of, the reverse for _left_of), independent of which
## table roll (T-junction/right turn/left turn) is asking for it.
static func _right_of(dir: Vector2i) -> Vector2i:
	return Vector2i(-dir.y, dir.x)

static func _left_of(dir: Vector2i) -> Vector2i:
	return Vector2i(dir.y, -dir.x)

## The 2x2 pivot block's own bounding corners for a block that would be
## carved as a length-2 straight run from `origin` heading `dir`.
static func _turn_block_bounds(origin: Vector2i, dir: Vector2i) -> Dictionary:
	var min_x: int
	var max_x: int
	var min_y: int
	var max_y: int
	if dir.x == 0:
		min_x = origin.x
		max_x = origin.x + 1
		var y0: int = origin.y
		var y1: int = origin.y + dir.y
		min_y = mini(y0, y1)
		max_y = maxi(y0, y1)
	else:
		min_y = origin.y
		max_y = origin.y + 1
		var x0: int = origin.x
		var x1: int = origin.x + dir.x
		min_x = mini(x0, x1)
		max_x = maxi(x0, x1)
	return {"min": Vector2i(min_x, min_y), "max": Vector2i(max_x, max_y)}

## Where the NEXT segment should start from, given a 2x2 pivot block
## (carved at `origin`/`dir`) that's now turning to head `new_dir`
## instead — used for both a plain turn (one call) and a T-junction (two
## calls, one per new branch).
static func _turn_exit(origin: Vector2i, dir: Vector2i, new_dir: Vector2i) -> Vector2i:
	var b: Dictionary = _turn_block_bounds(origin, dir)
	var bmin: Vector2i = b["min"]
	var bmax: Vector2i = b["max"]
	if new_dir == Vector2i(1, 0):
		return Vector2i(bmax.x + 1, bmin.y)
	if new_dir == Vector2i(-1, 0):
		return Vector2i(bmin.x - 1, bmin.y)
	if new_dir == Vector2i(0, 1):
		return Vector2i(bmin.x, bmax.y + 1)
	return Vector2i(bmin.x, bmin.y - 1)   ## Vector2i(0, -1)

## --- Branch building ------------------------------------------------------

## Rolls Length -> (maybe attaches doors/rooms via Features) -> End for
## one open branch end, pushing any new open ends it produces onto
## `open_ends` (shared across every branch, since a T-junction can
## itself later spawn two more of these calls).
static func _build_from_open_end(ctx: _Ctx, end: Dictionary, open_ends: Array) -> void:
	var origin: Vector2i = end["origin"]
	var dir: Vector2i = end["dir"]
	var length: int = _roll_passage_length(ctx.rng)
	var seg: Dictionary = _segment_cells(origin, dir, length)
	var connect_from: Dictionary = _rail_cells_at(origin, dir, -1)
	if not ctx.fits(seg["cells"], connect_from):
		return   ## doesn't fit anywhere -- this branch simply dead-ends where it stood, per "adjust regardless of rolls"
	ctx.commit(seg["cells"])

	var seg_id: int = ctx.hallway_segments.size()
	var features: String = _roll_passage_features(ctx.rng)
	var has_wandering: bool = features == "wandering_monsters"
	if features == "1_door" or features == "2_doors":
		var door_count: int = 1 if features == "1_door" else 2
		for i in range(door_count):
			_try_attach_room(ctx, seg)
			if ctx.stop_building:
				break

	ctx.hallway_segments.append({
		"id": seg_id,
		"cells": seg["cells"],
		"has_wandering_monsters": has_wandering,
		"monsters_spawned": false,
	})

	if ctx.stop_building:
		return   ## the Quest room just came off this very segment -- nothing continues past it

	var end_roll: String = _roll_passage_end(ctx.rng)
	match end_roll:
		"dead_end":
			pass
		"t_junction":
			var block: Dictionary = _segment_cells(seg["next_origin"], dir, TURN_SIZE)
			if ctx.fits(block["cells"], _rail_cells_at(seg["next_origin"], dir, -1)):
				ctx.commit(block["cells"])
				var e1: Vector2i = _turn_exit(seg["next_origin"], dir, _right_of(dir))
				var e2: Vector2i = _turn_exit(seg["next_origin"], dir, _left_of(dir))
				open_ends.append({"origin": e1, "dir": _right_of(dir)})
				open_ends.append({"origin": e2, "dir": _left_of(dir)})
			## if the junction block doesn't fit, this branch just dead-ends here
		"right_turn", "left_turn":
			var new_dir: Vector2i = _right_of(dir) if end_roll == "right_turn" else _left_of(dir)
			var block2: Dictionary = _segment_cells(seg["next_origin"], dir, TURN_SIZE)
			if ctx.fits(block2["cells"], _rail_cells_at(seg["next_origin"], dir, -1)):
				ctx.commit(block2["cells"])
				var exit_origin: Vector2i = _turn_exit(seg["next_origin"], dir, new_dir)
				open_ends.append({"origin": exit_origin, "dir": new_dir})
			## if it doesn't fit, this branch just dead-ends here too

## Tries every (side, offset) door position along `seg`'s own two long
## rails, starting from a random point and scanning the rest, until one
## fits (room included) — or gives up silently if none do (per "adjust
## regardless of rolls": a door that can't fit anywhere just isn't
## placed, rather than forcing an overlap).
static func _try_attach_room(ctx: _Ctx, seg: Dictionary) -> void:
	var origin: Vector2i = seg["origin"]
	var dir: Vector2i = seg["dir"]
	var length: int = seg["length"]
	if length < 2:
		return
	## The room's own near-face is SMALL_ROOM_SIZE/LARGE_ROOM_WIDTH (4)
	## cells wide, wider than the CORRIDOR_SCALE (2) door span it opens
	## onto — so with the door no longer a separate buffer tile (see
	## _attempt_room_at()'s own comment), the room's face necessarily
	## also runs alongside a cell or two of this SAME corridor to either
	## side of the door itself (a room built flush against a hallway
	## it's connected to, door in the middle — normal dungeon layout,
	## not a foreign touch). `seg_allowed` whitelists every cell of THIS
	## one segment for that reason; every other occupied cell (any other
	## corridor, turn, or room) is still off-limits, so a room can still
	## only ever connect to the one corridor it's actually opening onto.
	var seg_allowed: Dictionary = {}
	for c in seg["cells"]:
		seg_allowed[c] = true
	var max_offset: int = length - 2
	var start_side: int = 0 if ctx.rng.randf() < 0.5 else 1
	var start_offset: int = ctx.rng.randi_range(0, max_offset)
	for side_try in range(2):
		var side: int = (start_side + side_try) % 2
		for off_try in range(max_offset + 1):
			var offset: int = (start_offset + off_try) % (max_offset + 1)
			if _attempt_room_at(ctx, origin, dir, side, offset, seg_allowed):
				return

## One concrete (side, offset) door attempt: places the room rect with
## ZERO gap directly against the chosen rail (no separate door tile of
## its own — per the follow-up request "have door attachable to
## existing passage and room tiles, don't make they have their own 2x2
## tile"), checks it fits, and — only if it does — rolls the Room Size
## Table, commits the room, and marks its own near-face cells (the
## CORRIDOR_SCALE-long span that actually touches the corridor's rail)
## as the door. Returns true iff a room was actually placed.
##
## The room is allowed to touch THIS corridor segment (via `fits()`'s
## `allowed_touch` = `seg_allowed`, every cell of the one segment this
## door is attaching to) — the room's own face is wider than the door
## itself, so it necessarily runs alongside a cell or two of this same
## corridor either side of the door (a normal "room built flush against
## the hallway it opens onto" layout). Everywhere else — any OTHER
## corridor, turn, junction, or room — still has to clear the usual
## no-touch margin, so a room only ever connects to the one corridor
## it's actually opening a door onto, never a different, unconnected one.
static func _attempt_room_at(ctx: _Ctx, origin: Vector2i, dir: Vector2i, side: int, offset: int, seg_allowed: Dictionary) -> bool:
	var door_dir: Vector2i
	var rail_a: Vector2i
	var rail_b: Vector2i
	var anchor: Vector2i   ## the door's own min-corner cell — one step out from rail_a, in door_dir; also the room's own near-face min corner, since the room now starts exactly here with no gap
	if dir.x == 0:
		var rail_x: int = origin.x + side
		door_dir = Vector2i(-1, 0) if side == 0 else Vector2i(1, 0)
		var y0: int = origin.y + offset * dir.y
		var y1: int = origin.y + (offset + 1) * dir.y
		var rmin: int = mini(y0, y1)
		var rmax: int = maxi(y0, y1)
		rail_a = Vector2i(rail_x, rmin)
		rail_b = Vector2i(rail_x, rmax)
		anchor = Vector2i(rail_x + door_dir.x, rmin)
	else:
		var rail_y: int = origin.y + side
		door_dir = Vector2i(0, -1) if side == 0 else Vector2i(0, 1)
		var x0: int = origin.x + offset * dir.x
		var x1: int = origin.x + (offset + 1) * dir.x
		var rmin2: int = mini(x0, x1)
		var rmax2: int = maxi(x0, x1)
		rail_a = Vector2i(rmin2, rail_y)
		rail_b = Vector2i(rmax2, rail_y)
		anchor = Vector2i(rmin2, rail_y + door_dir.y)

	var room_type: String = _roll_room_size(ctx.rng, ctx.room_count)
	var is_large: bool = room_type.begins_with("large")
	var depth: int = LARGE_ROOM_DEPTH if is_large else SMALL_ROOM_SIZE
	var width: int = LARGE_ROOM_WIDTH if is_large else SMALL_ROOM_SIZE   ## width is 4 either way — Small 4x4 / Large 4x8

	## `anchor` is the room's own near-face min corner (its edge cell
	## that borders the rail) — the room extends `depth` cells AWAY from
	## the rail in door_dir, and back TOWARD the rail on the near-face
	## axis for the negative-direction case, since _segment_cells' own
	## forward-stepping convention doesn't apply here (there's no
	## _segment_cells call left in this function at all now).
	var rect: Rect2i
	if dir.x == 0:
		var y_min: int = mini(rail_a.y, rail_b.y) - int((width - 2) / 2.0)
		rect = Rect2i(anchor.x - depth + 1, y_min, depth, width) if door_dir.x < 0 else Rect2i(anchor.x, y_min, depth, width)
	else:
		var x_min: int = mini(rail_a.x, rail_b.x) - int((width - 2) / 2.0)
		rect = Rect2i(x_min, anchor.y - depth + 1, width, depth) if door_dir.y < 0 else Rect2i(x_min, anchor.y, width, depth)

	var room_cells: Array = []
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			room_cells.append(Vector2i(x, y))

	if not ctx.fits(room_cells, seg_allowed):
		return false

	ctx.commit(room_cells)
	## The door itself: the CORRIDOR_SCALE-long, 1-cell-thick span of the
	## room's OWN near-face cells that directly border rail_a/rail_b —
	## already part of room_cells (just committed above), simply flagged
	## as door cells rather than plain floor for rendering/interaction.
	var perp: Vector2i = Vector2i(0, 1) if dir.x == 0 else Vector2i(1, 0)
	for i in range(CORRIDOR_SCALE):
		ctx.door_cells[anchor + perp * i] = true

	var hazard_type: String = "none"
	var hazard_pos: Vector2i = Vector2i(-1, -1)
	var hazard_cells: Array = []
	var monster_names: Array = []
	var is_quest := false
	match room_type:
		"small":
			pass
		"small_hazard":
			hazard_type = _roll_hazard(ctx.rng)
			hazard_pos = Vector2i(rect.position.x + int(rect.size.x / 2.0), rect.position.y + int(rect.size.y / 2.0))
			## Per the request ("Chasm's should span the width (not
			## length) of rooms they are in"): a chasm is no longer a
			## single walkable point tile — it's a full line of cells
			## running across the room's WIDTH axis (the 4-wide near
			## face, same axis the door itself sits on), at a fixed
			## mid-depth row/column. hazard_pos above still lands on
			## the exact middle cell of that same line (the two
			## formulas agree by construction), so it's kept as-is for
			## any caller that just wants "a" representative point;
			## hazard_cells is the authoritative full span used for
			## making every one of those cells impassable and for
			## drawing the chasm across the room. Other hazard types
			## (spike_trap, monster_patrol) stay single-point.
			if hazard_type == "chasm":
				hazard_cells = _chasm_span_cells(rect, door_dir)
			if hazard_type == "monster_patrol":
				monster_names = ctx.theme.monster_patrol_monster_names.duplicate()
		"large_lair":
			monster_names = ctx.theme.monster_lair_monster_names.duplicate()
		"large_quest":
			monster_names = ctx.theme.quest_room_monster_names.duplicate()
			is_quest = true
			ctx.quest_placed = true
			ctx.stop_building = true

	var door_span_cells: Dictionary = {}
	for i in range(CORRIDOR_SCALE):
		door_span_cells[anchor + perp * i] = true
	var reserved_cells: Dictionary = door_span_cells.duplicate()
	for c in hazard_cells:
		reserved_cells[c] = true
	if hazard_pos != Vector2i(-1, -1):
		reserved_cells[hazard_pos] = true
	var chest_pos := Vector2i(-1, -1)
	var stairs_pos := Vector2i(-1, -1)
	if is_quest:
		chest_pos = _far_corner(rect, anchor)
		reserved_cells[chest_pos] = true
		## Per the "Sewer/Cave Dungeons update 2" request ("let place
		## stairs going down in the Quest room"): every Quest room gets
		## its own stairs down to the next floor, UNLESS this is already
		## the deepest allowed floor ("Upto 3 floors down, so total of 4
		## floors including the ground floor" -- see MAX_DUNGEON_FLOOR).
		## Placed at the room's corner farthest from the chest (rather
		## than re-deriving _far_corner(rect, anchor) again, which risks
		## landing in the exact same corner as the chest) so the two
		## landmarks always sit in different corners of the room.
		if ctx.floor_index < MAX_DUNGEON_FLOOR:
			stairs_pos = _far_corner(rect, chest_pos)
			reserved_cells[stairs_pos] = true

	var furniture_type := _roll_furniture(ctx.rng)
	var furniture_cells: Array = []
	var furniture_anchor := Vector2i(-1, -1)
	var furniture_size := Vector2i.ZERO
	var furniture_facing := Vector2i.ZERO
	if furniture_type != "none":
		var placed: Dictionary = _place_footprint(ctx.rng, rect, FURNITURE_FOOTPRINT.get(furniture_type, Vector2i(1, 1)), reserved_cells)
		if placed.is_empty():
			furniture_type = "none"
		else:
			furniture_cells = placed["cells"]
			furniture_anchor = placed["anchor"]
			furniture_size = placed["size"]
			furniture_facing = placed["facing"]

	var room: Dictionary = {
		"rect": rect,
		"door_pos": anchor,
		"door_dir": door_dir,
		"door_open": false,
		"room_type": "large" if is_large else "small",
		"quest": is_quest,
		"hazard_type": hazard_type,
		"hazard_pos": hazard_pos,
		"hazard_cells": hazard_cells,
		"hazard_resolved": false,
		"monster_names": monster_names,
		"encountered": false,
		"cleared": false,
		"spawn_far_corner": _far_corner(rect, anchor),
		"furniture_type": furniture_type,
		"furniture_cells": furniture_cells,
		"furniture_anchor": furniture_anchor,
		"furniture_size": furniture_size,
		"furniture_facing": furniture_facing,
		"furniture_looted": false,
		"chest_pos": chest_pos,
		"chest_looted": false,
		"stairs_pos": stairs_pos,
	}
	ctx.rooms.append(room)
	ctx.room_count += 1
	return true

## Per the request ("Chasm's should span the width... of rooms they are
## in"): returns every cell of the single row/column that runs the full
## WIDTH of the room (the 4-wide near face the door itself sits on),
## at a fixed mid-DEPTH offset — the depth axis being whichever of
## rect.size.x/size.y is NOT the width. door_dir tells us which axis
## is depth: door_dir.x != 0 means the room was placed off a
## horizontal corridor and grows away in x, so rect.size.x is depth
## and rect.size.y (always 4) is width, and vice-versa for door_dir.y.
static func _chasm_span_cells(rect: Rect2i, door_dir: Vector2i) -> Array:
	var cells: Array = []
	if door_dir.x != 0:
		var depth: int = rect.size.x
		var mid_x: int = rect.position.x + int(depth / 2.0)
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			cells.append(Vector2i(mid_x, y))
	else:
		var depth2: int = rect.size.y
		var mid_y: int = rect.position.y + int(depth2 / 2.0)
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			cells.append(Vector2i(x, mid_y))
	return cells

static func _far_corner(rect: Rect2i, from: Vector2i) -> Vector2i:
	var corners: Array = [
		Vector2i(rect.position.x, rect.position.y),
		Vector2i(rect.position.x + rect.size.x - 1, rect.position.y),
		Vector2i(rect.position.x, rect.position.y + rect.size.y - 1),
		Vector2i(rect.position.x + rect.size.x - 1, rect.position.y + rect.size.y - 1),
	]
	var best: Vector2i = corners[0]
	var best_d := -1
	for c in corners:
		var d: int = absi(c.x - from.x) + absi(c.y - from.y)
		if d > best_d:
			best_d = d
			best = c
	return best

## No rooms rolled a Quest room naturally (see _generate_once's own
## comment) — promote the last-placed Large (Monster Lair) room if one
## exists, else the last-placed Small room, else give up (generate()'s
## own _validate()/retry loop catches a state with no rooms at all).
static func _force_quest_room(ctx: _Ctx) -> void:
	var best_idx := -1
	for i in range(ctx.rooms.size()):
		if ctx.rooms[i].get("room_type") == "large":
			best_idx = i
	if best_idx == -1:
		for i in range(ctx.rooms.size()):
			if ctx.rooms[i].get("room_type") == "small":
				best_idx = i
				break
	if best_idx == -1:
		return
	var room: Dictionary = ctx.rooms[best_idx]
	room["quest"] = true
	room["monster_names"] = ctx.theme.quest_room_monster_names.duplicate()
	room["hazard_type"] = "none"
	room["hazard_pos"] = Vector2i(-1, -1)
	room["hazard_cells"] = []
	## Per the request ("Quest Room will additionally always contain a
	## Treasure Chest at the far end"): this promoted room needs its own
	## chest too, even though it already finished its own Room Furniture
	## roll back in _attempt_room_at() (before anyone knew it would
	## become the Quest room) — claim the room's far corner for the
	## chest now and, if that earlier furniture roll happened to land
	## there, simply drop the furniture rather than let the two overlap.
	## This only ever matters for the rare dungeon where no Quest room
	## rolled naturally at all.
	var rect: Rect2i = room["rect"]
	var door_pos: Vector2i = room["door_pos"]
	var chest_pos: Vector2i = _far_corner(rect, door_pos)
	room["chest_pos"] = chest_pos
	room["chest_looted"] = false
	## Same reasoning as _attempt_room_at()'s own stairs_pos logic: this
	## promoted room also needs its own stairs down, unless it's already
	## at the deepest allowed floor.
	var stairs_pos: Vector2i = Vector2i(-1, -1)
	if ctx.floor_index < MAX_DUNGEON_FLOOR:
		stairs_pos = _far_corner(rect, chest_pos)
	room["stairs_pos"] = stairs_pos
	var furn_cells: Array = room.get("furniture_cells", [])
	if furn_cells.has(chest_pos) or (stairs_pos != Vector2i(-1, -1) and furn_cells.has(stairs_pos)):
		room["furniture_type"] = "none"
		room["furniture_cells"] = []
		room["furniture_anchor"] = Vector2i(-1, -1)
		room["furniture_size"] = Vector2i.ZERO
		room["furniture_facing"] = Vector2i.ZERO
	ctx.rooms[best_idx] = room
	ctx.quest_placed = true

## --- Dice tables (per the request's own exact wording) --------------------

## D12: 1-8 = 5x2 Straight, 9-12 = 10x2 Straight.
static func _roll_passage_length(rng: RandomNumberGenerator) -> int:
	var d: int = rng.randi_range(1, 12)
	return STRAIGHT_SHORT if d <= 8 else STRAIGHT_LONG

## 2D12 (2-24): 2-4/22-24 = wandering monsters, 5-9 = nothing, 10-15 = 1
## door, 16-21 = 2 doors.
static func _roll_passage_features(rng: RandomNumberGenerator) -> String:
	var sum: int = rng.randi_range(1, 12) + rng.randi_range(1, 12)
	if sum <= 4:
		return "wandering_monsters"
	if sum <= 9:
		return "nothing"
	if sum <= 15:
		return "1_door"
	if sum <= 21:
		return "2_doors"
	return "wandering_monsters"

## D12: 1-3 = T junction, 4-6 = dead end, 7-9 = right turn, 10-12 = left turn.
static func _roll_passage_end(rng: RandomNumberGenerator) -> String:
	var d: int = rng.randi_range(1, 12)
	if d <= 3:
		return "t_junction"
	if d <= 6:
		return "dead_end"
	if d <= 9:
		return "right_turn"
	return "left_turn"

## Room Size Table, tiered by how many rooms already exist BEFORE this
## one (0-2 / 3-4 / 5+) — the request's own three separate D12 tables.
## Per the follow-up request's rebalance of the 0-2 and 3-4 tiers: the
## 3-4 tier no longer offers a plain "Small" outcome at all (every Small
## room rolled in that tier now also rolls a Hazard). The 5+ tier is
## unchanged from the original request.
static func _roll_room_size(rng: RandomNumberGenerator, room_count: int) -> String:
	var d: int = rng.randi_range(1, 12)
	if room_count <= 2:
		if d <= 4:
			return "small"
		if d <= 8:
			return "small_hazard"
		return "large_lair"
	elif room_count <= 4:
		if d <= 3:
			return "small_hazard"
		if d <= 9:
			return "large_lair"
		return "large_quest"
	else:
		if d <= 3:
			return "small"
		if d <= 5:
			return "small_hazard"
		if d <= 7:
			return "large_lair"
		return "large_quest"

## D3: 1 = Monster patrol, 2 = Chasm, 3 = Spike trap.
static func _roll_hazard(rng: RandomNumberGenerator) -> String:
	var d: int = rng.randi_range(1, 3)
	if d == 1:
		return "monster_patrol"
	if d == 2:
		return "chasm"
	return "spike_trap"

## Room Furniture Table (D12), per the "Sewer/Cave Dungeons update"
## request ("All rooms will roll on the Room furniture table when
## generated"): 1-2 Nothing, 3-4 Weapon Rack, 5-8 Cupboard, 9-10 Alchemy
## Table, 11-12 Torture Rack.
static func _roll_furniture(rng: RandomNumberGenerator) -> String:
	var d: int = rng.randi_range(1, 12)
	if d <= 2:
		return "none"
	if d <= 4:
		return "weapon_rack"
	if d <= 8:
		return "cupboard"
	if d <= 10:
		return "alchemy_table"
	return "torture_rack"

## Footprint sizes (in cells), per the request: "Weapon Rack/Cupboard/
## Alchemy Table 2x1 cells, Torture Rack 2x2 cells."
const FURNITURE_FOOTPRINT := {
	"weapon_rack": Vector2i(2, 1),
	"cupboard": Vector2i(2, 1),
	"alchemy_table": Vector2i(2, 1),
	"torture_rack": Vector2i(2, 2),
}

## Tries every possible top-left origin for `footprint` (and, if it's
## non-square, both orientations of it — the orientation whose SHORT
## (depth) axis is 1 cell is the one that can sit flush against a wall
## with its long axis running along that wall) fully inside `rect`, with
## no cell touching anything in `reserved`, restricted to placements
## whose depth axis is flush against one of the room's own four walls
## (per the request "furniture items should be placed along the walls
## looking away from the wall") — a square footprint (Torture Rack) may
## flush against any of the four walls since it has no distinct depth
## axis. Returns a random valid placement as {"cells": Array, "anchor":
## Vector2i, "size": Vector2i, "facing": Vector2i} — `facing` points AWAY
## from the wall the piece is flush against, into the room (e.g. a piece
## against the room's north wall faces south, Vector2i(0, 1)); the
## renderer (BattleGridView) rotates the piece's sprite to match. Returns
## {} if nothing fits at all (a small, hazard-choked room can run out of
## open wall space; the caller's own contract is to silently skip
## placing anything in that case rather than ever forcing an overlap or
## a floating mid-room placement, matching every other placement
## convention in this file).
static func _place_footprint(rng: RandomNumberGenerator, rect: Rect2i, footprint: Vector2i, reserved: Dictionary) -> Dictionary:
	## wall_axis "y" means this orientation's depth (1-cell) axis is Y —
	## it can only flush against the room's north/south wall; "x" is the
	## mirror case (east/west wall only); "any" (square footprints only)
	## may flush against any of the four.
	var orientations: Array = []
	if footprint.x == footprint.y:
		orientations.append({"size": footprint, "wall_axis": "any"})
	else:
		orientations.append({"size": footprint, "wall_axis": "y"})
		orientations.append({"size": Vector2i(footprint.y, footprint.x), "wall_axis": "x"})

	var candidates: Array = []
	for orient in orientations:
		var size: Vector2i = orient["size"]
		var wall_axis: String = orient["wall_axis"]
		if size.x > rect.size.x or size.y > rect.size.y:
			continue
		for ox in range(rect.position.x, rect.position.x + rect.size.x - size.x + 1):
			for oy in range(rect.position.y, rect.position.y + rect.size.y - size.y + 1):
				var origin := Vector2i(ox, oy)
				var cells: Array = []
				var ok := true
				for dx in range(size.x):
					for dy in range(size.y):
						var c: Vector2i = origin + Vector2i(dx, dy)
						if reserved.has(c):
							ok = false
							break
						cells.append(c)
					if not ok:
						break
				if not ok:
					continue
				var facing := Vector2i.ZERO
				if wall_axis == "y" or wall_axis == "any":
					if origin.y == rect.position.y:
						facing = Vector2i(0, 1)      ## flush against the north wall, faces south into the room
					elif origin.y + size.y - 1 == rect.position.y + rect.size.y - 1:
						facing = Vector2i(0, -1)     ## flush against the south wall, faces north
				if facing == Vector2i.ZERO and (wall_axis == "x" or wall_axis == "any"):
					if origin.x == rect.position.x:
						facing = Vector2i(1, 0)      ## flush against the west wall, faces east
					elif origin.x + size.x - 1 == rect.position.x + rect.size.x - 1:
						facing = Vector2i(-1, 0)     ## flush against the east wall, faces west
				if facing == Vector2i.ZERO:
					continue   ## floating mid-room, not flush against any wall — not a valid placement
				candidates.append({"cells": cells, "anchor": origin, "size": size, "facing": facing})
	if candidates.is_empty():
		return {}
	return candidates[rng.randi() % candidates.size()]

## --- Grid rasterization ---------------------------------------------------

static func _build_grid_rows(ctx: _Ctx) -> Array:
	var min_x: int = ctx.entrance_pos.x
	var max_x: int = ctx.entrance_pos.x
	var min_y: int = ctx.entrance_pos.y
	var max_y: int = ctx.entrance_pos.y
	for cell in ctx.occupied.keys():
		min_x = mini(min_x, cell.x)
		max_x = maxi(max_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_y = maxi(max_y, cell.y)
	min_x -= 1
	max_x += 1
	min_y -= 1
	max_y += 1

	var rows: Array = []
	for y in range(min_y, max_y + 1):
		var row := ""
		for x in range(min_x, max_x + 1):
			var cell := Vector2i(x, y)
			if cell == ctx.entrance_pos:
				row += ctx.theme.entrance_char
			elif ctx.door_cells.has(cell):
				row += ctx.theme.door_closed_char
			elif ctx.occupied.has(cell):
				row += ctx.theme.floor_char
			else:
				row += ctx.theme.wall_char
		rows.append(row)
	return rows

static func _grid_offset(ctx: _Ctx) -> Vector2i:
	var min_x: int = ctx.entrance_pos.x
	var min_y: int = ctx.entrance_pos.y
	for cell in ctx.occupied.keys():
		min_x = mini(min_x, cell.x)
		min_y = mini(min_y, cell.y)
	return Vector2i(-(min_x - 1), -(min_y - 1))

## --- Validation (drives the retry loop in generate()) ------------------

## A generated state is valid when at least one room exists, at least
## one of them is the Quest room, and every room's door is reachable
## from the entrance walking only floor/door/entrance cells (never a
## wall). By construction (every placement here is collision-checked
## against everything already built) an unreachable room or an overlap
## should never actually happen — this stays as a defensive check /
## retry trigger rather than the primary correctness mechanism.
static func _validate(state: Dictionary, theme: DungeonThemeDefinition) -> bool:
	var rooms: Array = state.get("rooms", [])
	if rooms.is_empty():
		return false
	var has_quest := false
	for r in rooms:
		if r.get("quest", false):
			has_quest = true
	if not has_quest:
		return false

	var walkable: Dictionary = _walkable_set(state.get("grid_rows", []), theme)
	var entrance: Vector2i = state.get("entrance_pos", Vector2i.ZERO)
	var reached: Dictionary = _flood_fill(entrance, walkable)
	for room in rooms:
		if not reached.has(room["door_pos"]):
			return false
	return true

## Any non-wall char is walkable for connectivity-checking purposes —
## grid_rows only ever contains floor/door/entrance/wall chars (see
## _build_grid_rows).
static func _walkable_set(grid_rows: Array, theme: DungeonThemeDefinition) -> Dictionary:
	var result: Dictionary = {}
	for y in range(grid_rows.size()):
		var row: String = grid_rows[y]
		for x in range(row.length()):
			var ch := row[x]
			if ch != theme.wall_char:
				result[Vector2i(x, y)] = true
	return result

static func _flood_fill(start: Vector2i, walkable: Dictionary) -> Dictionary:
	var visited: Dictionary = {}
	if not walkable.has(start):
		return visited
	var stack: Array = [start]
	visited[start] = true
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for d in CHEBYSHEV_DIRS:
			var nxt: Vector2i = cur + d
			if walkable.has(nxt) and not visited.has(nxt):
				visited[nxt] = true
				stack.append(nxt)
	return visited

## Vector2i -> "x,y" string, the same JSON-safe Dictionary-key convention
## this project already uses elsewhere for Vector2i-keyed save data.
static func _vec_key(v: Vector2i) -> String:
	return "%d,%d" % [v.x, v.y]

## --- Save/load round-trip -------------------------------------------------
##
## A live DungeonState (as returned by generate()/exploration mode's own
## runtime mutations, see field_encounter_screen.gd) holds real
## Vector2i/Rect2i values, which Godot's JSON encoder doesn't round-trip
## natively. Character.to_save_dict()/from_save_dict() call these two
## functions to convert to and from a plain-primitives shape (nested
## Arrays/Dictionaries of int/String/bool only) right at the save
## boundary — the same "flat JSON of primitives" convention every other
## piece of save data in this project already follows.

static func to_save_data(state: Dictionary) -> Dictionary:
	if state.is_empty():
		return {}
	var rooms_out: Array = []
	for room in state.get("rooms", []):
		var rect: Rect2i = room["rect"]
		rooms_out.append({
			"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
			"door_pos": _vec_to_arr(room["door_pos"]),
			"door_dir": _vec_to_arr(room.get("door_dir", Vector2i.ZERO)),
			"door_open": room["door_open"],
			"room_type": room.get("room_type", "small"),
			"quest": room.get("quest", false),
			"hazard_type": room.get("hazard_type", "none"),
			"hazard_pos": _vec_to_arr(room.get("hazard_pos", Vector2i(-1, -1))),
			"hazard_cells": _vec_array_to_arr(room.get("hazard_cells", [])),
			"hazard_resolved": room.get("hazard_resolved", false),
			"monster_names": room["monster_names"],
			"encountered": room["encountered"],
			"cleared": room["cleared"],
			"spawn_far_corner": _vec_to_arr(room["spawn_far_corner"]),
			"furniture_type": room.get("furniture_type", "none"),
			"furniture_cells": _vec_array_to_arr(room.get("furniture_cells", [])),
			"furniture_anchor": _vec_to_arr(room.get("furniture_anchor", Vector2i(-1, -1))),
			"furniture_size": _vec_to_arr(room.get("furniture_size", Vector2i.ZERO)),
			"furniture_facing": _vec_to_arr(room.get("furniture_facing", Vector2i.ZERO)),
			"furniture_looted": room.get("furniture_looted", false),
			"chest_pos": _vec_to_arr(room.get("chest_pos", Vector2i(-1, -1))),
			"chest_looted": room.get("chest_looted", false),
			"stairs_pos": _vec_to_arr(room.get("stairs_pos", Vector2i(-1, -1))),
		})
	var segments_out: Array = []
	for seg in state.get("hallway_segments", []):
		var cells_out: Array = []
		for c in seg["cells"]:
			cells_out.append(_vec_to_arr(c))
		segments_out.append({
			"id": seg["id"],
			"cells": cells_out,
			"has_wandering_monsters": seg.get("has_wandering_monsters", false),
			"monsters_spawned": seg.get("monsters_spawned", false),
		})
	return {
		"theme_id": state.get("theme_id", ""),
		"grid_rows": state.get("grid_rows", []),
		"entrance_pos": _vec_to_arr(state.get("entrance_pos", Vector2i.ZERO)),
		"rooms": rooms_out,
		"hallway_segments": segments_out,
		"visibility": _visibility_to_save(state.get("visibility", {})),
		"player_grid_pos": _vec_to_arr(state.get("player_grid_pos", Vector2i.ZERO)),
		"exit_used": state.get("exit_used", false),
		"dungeon_floor": state.get("dungeon_floor", 0),
	}

static func from_save_data(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {}
	var rooms_out: Array = []
	for room in data.get("rooms", []):
		var r: Array = room.get("rect", [0, 0, 0, 0])
		rooms_out.append({
			"rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])),
			"door_pos": _arr_to_vec(room.get("door_pos", [0, 0])),
			"door_dir": _arr_to_vec(room.get("door_dir", [0, 0])),
			"door_open": bool(room.get("door_open", false)),
			"room_type": str(room.get("room_type", "small")),
			"quest": bool(room.get("quest", false)),
			"hazard_type": str(room.get("hazard_type", "none")),
			"hazard_pos": _arr_to_vec(room.get("hazard_pos", [-1, -1])),
			"hazard_cells": _arr_to_vec_array(room.get("hazard_cells", [])),
			"hazard_resolved": bool(room.get("hazard_resolved", false)),
			"monster_names": room.get("monster_names", []),
			"encountered": bool(room.get("encountered", false)),
			"cleared": bool(room.get("cleared", false)),
			"spawn_far_corner": _arr_to_vec(room.get("spawn_far_corner", [0, 0])),
			"furniture_type": str(room.get("furniture_type", "none")),
			"furniture_cells": _arr_to_vec_array(room.get("furniture_cells", [])),
			"furniture_anchor": _arr_to_vec(room.get("furniture_anchor", [-1, -1])),
			"furniture_size": _arr_to_vec(room.get("furniture_size", [0, 0])),
			"furniture_facing": _arr_to_vec(room.get("furniture_facing", [0, 0])),
			"furniture_looted": bool(room.get("furniture_looted", false)),
			"chest_pos": _arr_to_vec(room.get("chest_pos", [-1, -1])),
			"chest_looted": bool(room.get("chest_looted", false)),
			"stairs_pos": _arr_to_vec(room.get("stairs_pos", [-1, -1])),
		})
	var segments_out: Array = []
	for seg in data.get("hallway_segments", []):
		var cells_out: Array = []
		for c in seg.get("cells", []):
			cells_out.append(_arr_to_vec(c))
		segments_out.append({
			"id": int(seg.get("id", 0)),
			"cells": cells_out,
			"has_wandering_monsters": bool(seg.get("has_wandering_monsters", false)),
			"monsters_spawned": bool(seg.get("monsters_spawned", false)),
		})
	return {
		"theme_id": str(data.get("theme_id", "")),
		"grid_rows": data.get("grid_rows", []),
		"entrance_pos": _arr_to_vec(data.get("entrance_pos", [0, 0])),
		"rooms": rooms_out,
		"hallway_segments": segments_out,
		"visibility": _visibility_from_save(data.get("visibility", {})),
		"player_grid_pos": _arr_to_vec(data.get("player_grid_pos", [0, 0])),
		"exit_used": bool(data.get("exit_used", false)),
		"dungeon_floor": int(data.get("dungeon_floor", 0)),
	}

## Runtime visibility is Vector2i-keyed (matching every other position in
## this state); JSON requires string keys, so these two functions are the
## ONLY place a "x,y" string key ever appears.
static func _visibility_to_save(visibility: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in visibility.keys():
		var v: Vector2i = key
		out[_vec_key(v)] = int(visibility[key])
	return out

static func _visibility_from_save(data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in data.keys():
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() != 2:
			continue
		out[Vector2i(int(parts[0]), int(parts[1]))] = int(data[key])
	return out

static func _vec_to_arr(v: Vector2i) -> Array:
	return [v.x, v.y]

static func _arr_to_vec(arr) -> Vector2i:
	if arr is Array and arr.size() >= 2:
		return Vector2i(int(arr[0]), int(arr[1]))
	return Vector2i.ZERO

## Same convention as _vec_to_arr/_arr_to_vec, applied to a whole Array of
## Vector2i (e.g. a chasm's hazard_cells span) — used so save/load can
## round-trip a variable-length list of grid cells the same JSON-safe way.
static func _vec_array_to_arr(cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		out.append(_vec_to_arr(c))
	return out

static func _arr_to_vec_array(arr: Array) -> Array:
	var out: Array = []
	for c in arr:
		out.append(_arr_to_vec(c))
	return out
