extends RefCounted
class_name BattleGrid
## Combat Encounter rework (per the request): a 45x27 square tactical
## battle grid (originally 30x18, enlarged ~50% per a follow-up request —
## see COLS/ROWS below), 2 yards per square (90x54 yards total),
## auto-generated from the 3x3 field-map tiles centered on wherever the
## player was standing when the encounter started.
##
## FieldEncounter.tscn is reached via a full `change_scene_to_file()`
## from Overworld, which destroys the Overworld instance — so this class
## never touches Overworld/LocalMapDefinition/TILE_ATLAS directly. It
## consumes a pre-computed 9-entry passability snapshot instead (see
## Overworld._capture_battle_terrain_snapshot(), which stashes it on
## GameState.pending_battle_terrain right before the scene change) —
## keeping this module fully decoupled and independently testable
## without spinning up a real Overworld/map at all.
##
## **Phase 1 scope, per the request**: terrain is binary for now — each
## of the 9 source field tiles is either fully walkable (open ground) or
## fully impassable (wall/water, from Overworld's own WATER_CHARS/
## BUILDING_CHARS classification). Richer per-square terrain (forest =
## difficult ground, elevation, cover bonuses) is deliberately deferred
## to a follow-up build once this skeleton is confirmed working — see
## the project doc for the phase breakdown. Nothing here assumes binary
## terrain will stay that way: `impassable` is keyed per-square, so a
## future pass can replace the flood-fill in
## generate_from_terrain_snapshot() with real per-square classification
## without changing any of this class's own public API.

## Per the follow-up request ("make the Battle around 50% larger
## vertically and horizontally"): 30x18 -> 45x27, both still exact
## multiples of 3 so the 3x3 source-tile block mapping below stays
## seamless with no leftover rows/columns to special-case. The default
## on-screen VIEW still shows a 30x18-cell window (see
## BattleGridView.DEFAULT_VIEW_COLS/ROWS) — this only changes how much
## battlefield actually exists, not how much of it fits on screen
## without zooming out.
const COLS := 45
const ROWS := 27
const YARDS_PER_SQUARE := 2
## Each of the 3x3 source field tiles blows up into its own block of
## battle squares — 45/3 = 15 columns wide, 27/3 = 9 rows tall. Chosen
## specifically so 3 divides evenly into both COLS and ROWS, giving every
## source tile an identically-sized, seamless block with no leftover
## rows/columns to special-case.
const BLOCK_COLS := COLS / 3
const BLOCK_ROWS := ROWS / 3

## Exploration mode (Dungeon Encounter Screen rework): a BattleGrid built
## from a generated dungeon (see generate_from_dungeon_grid() below) is
## NOT the fixed COLS x ROWS battlefield canvas — a dungeon can be any
## size. `cols`/`rows` are the REAL per-instance bounds every method
## below actually uses (is_in_bounds, pathing, drawing); they default to
## the fixed COLS/ROWS constants so every normal
## generate_from_terrain_snapshot() battlefield (the vast majority of
## instances) is completely unaffected.
var cols: int = COLS
var rows: int = ROWS

## Exploration mode: per-square tile art (Vector2i -> Texture2D), set by
## generate_from_dungeon_grid() from the active DungeonThemeDefinition's
## own tile_atlas. Empty for a normal combat battlefield —
## BattleGridView only consults this when it's non-empty, falling back
## to its existing flat-colour battlefield rendering otherwise.
var cell_texture: Dictionary = {}

## Exploration mode: per-square fog-of-war state (Vector2i -> int: 0
## unseen, 1 explored-not-currently-visible, 2 currently visible — same
## convention DungeonGenerator's own DungeonState.visibility already
## uses), set by generate_from_dungeon_grid() and kept live by
## refresh_fog_of_war() below. Deliberately the SAME Dictionary object
## the caller passes in (never cloned) — field_encounter_screen.gd's own
## _reveal_around() mutates DungeonState's visibility Dictionary in
## place, so this field automatically stays in sync with it with no
## explicit resync needed, as long as callers never replace
## dungeon_state["visibility"] with a brand new Dictionary object.
## Empty for a normal combat battlefield — BattleGridView only
## dims/hides squares when this is non-empty.
var fog_of_war: Dictionary = {}

## Exploration mode: door threshold lines to draw, one entry per room
## door — per the request ("change Doors to a thick brown line running
## along the Tile edges they sit on") doors are no longer a tile of
## their own (see cell_texture above, which now textures a door cell
## exactly like ordinary floor); this is the overlay BattleGridView
## draws on top instead. Per the follow-up request ("have door
## attachable to existing passage and room tiles, don't make they have
## their own 2x2 tile"), the door itself is now a span of the room's OWN
## cells rather than a separate block — the line is drawn exactly on the
## shared boundary between the corridor's rail and the room's near-face
## cells. Each entry: {"orientation": "vertical"/"horizontal",
## "line_pos": int, "span_start": int, "span_end": int, "door_anchor":
## Vector2i}. `line_pos` is the grid coordinate (x for vertical, y for
## horizontal) the line runs along; `span_start`/`span_end` are the
## perpendicular coordinate range the line spans (exclusive `span_end`,
## i.e. [start, end)). `door_anchor` is the room's own door_pos, used to
## find the door's real cells for a fog_of_war check before drawing
## ("should be visible for the player when close enough") — computed
## fresh by generate_from_dungeon_grid() below every time it runs, from
## the `rooms` array's own door_pos/door_dir fields.
var door_edges: Array = []

## Per the request ("the player can still see the first row of floor
## tiles behind closed doors, we need to hide those until the door is
## opened (but still show doors and walls)" — and its own immediate
## follow-up, "inside closed room, the floor tiles next to the grey wall
## lines are still visible, fix those too"): the set of cells belonging
## to a still-CLOSED room's own entire near-face row (the door's own
## span AND its flanking pad cells — a room's near-face row can be
## wider than its door; the rest of that row is sealed off from the
## corridor via wall_edges instead of a door, but _light_bfs() still
## marks it visible as a boundary cell either way). BattleGridView
## forces these specific cells to render as solid unexplored black
## while the door is closed, WITHOUT touching the door-threshold-line
## overlay itself (door_edges, above) or the underlying fog_of_war
## visibility entry — both of those are what let the door/wall LINE
## keep rendering ("still show doors and walls"). Rebuilt every
## generate_from_dungeon_grid() call from `rooms`' own rect/door_pos/
## door_dir geometry, the same `along <= 0` rule
## field_encounter_screen.gd's own closed-door vision-memory-prune fix
## already uses — see _build_closed_door_near_face_cells() below.
## Vector2i(cell) -> true.
var closed_door_near_face_cells: Dictionary = {}

## Per the request ("places where passage walls touch rooms and there is
## no door... should be impassable"): a room's own near-face cells that
## flank its door (the "pad" cells that make the room's 4-wide face
## necessarily run alongside a cell or two of the corridor it opens
## onto — see DungeonGenerator._try_attach_room()'s own comment on why
## that touch is allowed for PLACEMENT purposes) were never actually
## sealed with a wall of their own, leaving those specific spots
## walkable/see-through even though there's no door there. A genuine
## wall tile can't be carved at either cell (both must stay
## independently walkable — they're each still ordinary floor, just not
## connected to EACH OTHER) so this is an edge-level block instead:
## Vector2i(cell) -> Dictionary(neighbor Vector2i -> true), bidirectional,
## for the one specific shared boundary between each pad cell and the
## corridor cell directly across it. See _add_wall_edge()/_edge_blocked()
## and _build_room_wall_edges() below. Consulted by every movement/LOS
## function alongside impassable/blocks_los (has_line_of_sight,
## get_ranged_cover, find_path, reachable_squares,
## has_clear_direct_path) plus field_encounter_screen.gd's own
## exploration-mode fog-of-war BFS (_light_bfs), which doesn't go
## through this class's LOS functions at all.
var wall_edges: Dictionary = {}

## Same data as wall_edges, reshaped for BattleGridView's drawing pass —
## one entry per sealed pad-cell boundary: {"orientation":
## "vertical"/"horizontal", "line_pos": int, "span_start": int,
## "span_end": int, "cells": [face_cell, corridor_cell]}, same
## line-drawing convention door_edges already uses (see its own
## declaration comment) but always a single-cell-wide span, since each
## pad-cell boundary is only ever 1 cell wide (unlike a door's
## CORRIDOR_SCALE-wide span).
var wall_edge_lines: Array = []

## Exploration mode: physical hazard tiles (Chasm/Spike trap, Hazard
## Table D3) to draw a marker for — one entry per hazard room, {"pos":
## Vector2i, "type": "chasm"/"spike_trap", "resolved": bool}. A Chasm is
## a visible physical gap (drawn regardless of `resolved`); a Spike trap
## is a HIDDEN trap per genre convention — BattleGridView only draws a
## marker for one once `resolved` is true (i.e. after it's already been
## sprung/spotted), never before, same as the rest of this project's
## "traps are hidden until triggered" default. Rebuilt fresh by
## generate_from_dungeon_grid() every time (see _build_hazard_markers())
## so a hazard flips to its resolved look the moment the room dict
## itself is updated.
var hazard_markers: Array = []

## Room Furniture (D12, "Sewer/Cave Dungeons update"): one entry per
## room that rolled a piece of furniture, {"type": String, "cells":
## Array[Vector2i], "anchor": Vector2i (top-left cell), "size": Vector2i
## (footprint in cells), "looted": bool}. Same "rebuilt fresh by
## generate_from_dungeon_grid() every time" convention as hazard_markers
## above (see _build_furniture_markers()) so a piece flips to its looted
## look the moment the room dict itself is updated. Per the request
## ("Character should not be able to walk on these new items"), every
## cell in `cells` is marked impassable here the same way a hazard's own
## cells are.
var furniture_markers: Array = []

## The procedural Quest room's own Treasure Chest (per the "Sewer/Cave
## Dungeons update" request: "Quest Room will additionally always
## contain a (untrapped) Treasure Chest at the far end to where the
## Hero's enter") — one entry per Quest room that has one, {"pos":
## Vector2i, "looted": bool}. Deliberately separate from chest_marker_
## pos below (the Goblin Fort's own single, dungeon-level, LOCKED/
## trapped chest) — this is a per-ROOM, always-unlocked-and-untrapped
## chest that only ever appears on the procedural generate() path (see
## DungeonGenerator._attempt_room_at()'s own chest_pos field), so both
## chest systems can coexist without either one having to special-case
## the other. Also marked impassable, same as furniture_markers above.
var room_chest_markers: Array = []

## The procedural Quest room's own stairs down to the next dungeon
## floor ("Sewer/Cave Dungeons update 2" request: "let place stairs
## going down in the Quest room, this will lead to the next floor") --
## one entry per Quest room that still has a floor below it to lead to
## (DungeonGenerator._attempt_room_at()/_force_quest_room() leave
## stairs_pos at (-1, -1) once MAX_DUNGEON_FLOOR is reached, so the
## deepest floor's own Quest room simply never gets an entry here),
## {"pos": Vector2i}. Same "rebuilt fresh by generate_from_dungeon_grid()
## every time" convention as room_chest_markers above.
##
## Per the follow-up request ("player should be able to step on the
## stairs tile too"): UNLIKE room_chest_markers/furniture_markers above,
## this is deliberately NOT marked impassable -- the party can walk
## right onto it, same as any other open floor tile. Actually taking the
## stairs down still requires the adjacent Free Action button (see
## field_encounter_screen.gd's _on_take_stairs_pressed()), not just
## standing on the tile -- stepping onto it is now merely allowed, not a
## trigger in itself.
var room_stairs_markers: Array = []

## The Goblin Fort Dungeon's own lootable chest marker (see
## field_encounter_screen.gd's "Goblin Fort chest" section) — unlike
## hazard_markers above, this ISN'T derived from `rooms` (the fixed-
## room generator never populates rooms at all, see DungeonGenerator.
## generate_fixed_room()), so generate_from_dungeon_grid() itself never
## touches it. field_encounter_screen.gd sets this directly, right
## after every generate_from_dungeon_grid() call, from dungeon_state's
## own chest_pos — (-1, -1) means "no chest on this grid," the default
## for every dungeon that isn't the Goblin Fort. BattleGridView draws
## the actual monster_chest.png sprite here, same art (and the same
## always-closed look, locked or not, looted or not) the original
## overworld tile always used.
var chest_marker_pos: Vector2i = Vector2i(-1, -1)

## Per the request ("show the location of the entrance/exit of the
## Greenskin fort, right now there is no indication where it is"): the
## dungeon's own entrance/exit tile — same "field_encounter_screen.gd
## sets this directly, right after every generate_from_dungeon_grid()
## call" convention as chest_marker_pos just above, read from dungeon_
## state's own entrance_pos (every theme has one, not just the Goblin
## Fort, so this applies universally rather than being Goblin-Fort-only
## like the chest). (-1, -1) means "nothing to draw" — the harmless
## default before the very first dungeon load. BattleGridView draws a
## plain "EXIT" marker here (see that script's own comment) since there
## is no dedicated gate/door sprite for it, unlike the chest's own
## monster_chest.png.
var entrance_marker_pos: Vector2i = Vector2i(-1, -1)

## Vector2i(square) -> true for every impassable square. Absence from
## this dictionary means walkable — sparser than a full COLS*ROWS array
## for the common case (a mostly-open battlefield) and cheap to check.
var impassable: Dictionary = {}

## Combat Encounter rework, Phase 2: Vector2i(square) -> true for every
## square that grants "cover" against ranged attacks — per the request,
## cover-vs-ranged only for this phase (no difficult-ground movement
## cost, no elevation). Sourced from forest/tree tiles on the local map
## (see Overworld._capture_battle_terrain_snapshot()'s cover snapshot).
## Same sparse convention as impassable: absence = no cover. A square
## can be both impassable AND cover-granting-to-its-neighbors in
## principle, but in practice a square can't be both impassable and
## occupied/covered at once since nobody can stand on an impassable
## square — cover only ever matters for whatever square a living
## combatant is actually standing on.
var cover: Dictionary = {}

## Per the follow-up request ("when the battlemap includes a large
## section of greyed out cells due to overworld map water, fill this in
## with the same tiles as overworld water rather then Grey tiles, allow
## this water to merge with ponds too"): Vector2i(square) -> true for
## every impassable square whose SOURCE overworld tile was specifically
## water (a subset of `impassable` — a building block is impassable too
## but stays out of this dict, so it keeps the old plain wall colour).
## BattleGridView treats a `water` square exactly like a Pond square for
## drawing purposes — same flat water fill, same shore/edge blend art on
## the grass bordering it (see its own _resolve_water_shore_atlas()) —
## so a scattered Pond that happens to land next to one of these blocks
## reads as one continuous body of water instead of two.
var water: Dictionary = {}

## `terrain_snapshot`: a 9-entry Array[bool] (or Array — callers may pass
## a plain Array from a Dictionary/JSON round-trip), index (dy+1)*3+dx+1
## in relative-tile terms — index 0 = NW tile (dx=-1,dy=-1), index 4 =
## the player's own tile (dx=0,dy=0, the grid's own center block),
## index 8 = SE tile. This is exactly the layout
## Overworld._capture_battle_terrain_snapshot() writes. A malformed or
## short snapshot (e.g. a dev/test path that never set one) falls back
## to treating any missing index as walkable, so a battle can never fail
## to start over bad snapshot data — it just starts on more open ground
## than the real map would have given it.
##
## `cover_snapshot`: an optional second 9-entry Array, same index
## convention, true where that source tile grants cover. Defaults to an
## empty Array (no cover anywhere) so callers written before Phase 2
## keep working unchanged.
##
## `water_snapshot`: an optional third 9-entry Array, same index
## convention, true where that source tile is specifically water (see
## the `water` dict's own declaration comment). Defaults to an empty
## Array (no water anywhere — every impassable block just keeps the old
## plain wall colour) so callers written before this existed keep
## working unchanged.
func generate_from_terrain_snapshot(terrain_snapshot: Array, cover_snapshot: Array = [], water_snapshot: Array = []) -> void:
	impassable.clear()
	cover.clear()
	water.clear()
	for dy in range(3):
		for dx in range(3):
			var idx := dy * 3 + dx
			var tile_impassable: bool = bool(terrain_snapshot[idx]) if idx < terrain_snapshot.size() else false
			var tile_cover: bool = bool(cover_snapshot[idx]) if idx < cover_snapshot.size() else false
			var tile_water: bool = bool(water_snapshot[idx]) if idx < water_snapshot.size() else false
			if not tile_impassable and not tile_cover:
				continue
			var block_x0 := dx * BLOCK_COLS
			var block_y0 := dy * BLOCK_ROWS
			for by in range(BLOCK_ROWS):
				for bx in range(BLOCK_COLS):
					var sq := Vector2i(block_x0 + bx, block_y0 + by)
					if tile_impassable:
						impassable[sq] = true
						if tile_water:
							water[sq] = true
					if tile_cover:
						cover[sq] = true
	## Per the follow-up request ("BrokenCart... near the mud path" /
	## "Fence... a couple of segments along the mud path"): the winding
	## path trails need to exist BEFORE obstacles scatter so those two
	## types can bias their own placement toward them — see
	## _scatter_mud_paths()'s own comment. The small dotted-around mud
	## patches still scatter AFTER obstacles (unchanged from before) so
	## they can keep steering clear of whatever landed — see
	## _scatter_mud_patches()'s own comment.
	_scatter_mud_paths()
	_scatter_obstacles()
	_scatter_mud_patches()

## Exploration mode (Dungeon Encounter Screen rework, per the explicit
## clarification "the generated tile dungeon should replace the normal
## battle map"): builds this BattleGrid directly from a generated
## dungeon's own grid_rows/visibility — the real, 1:1 combat map for
## exploration mode, not a re-synthesized battlefield. No obstacle
## scatter/ground dressing here (those are generate_from_terrain_
## snapshot()'s own random-battlefield concerns) — a dungeon's own walls
## ARE its obstacles, and its own tile art (theme.tile_atlas) supplies
## all the visual variety a random battlefield's procedural obstacles
## give a normal fight. Callers rebuild the whole grid via a fresh call
## to this any time grid_rows changes (a door opens) — dungeons are
## modest-sized and this only ever runs on a discrete, turn-based player
## action, so a full rebuild is simpler and safer than incrementally
## patching impassable/cell_texture in place.
func generate_from_dungeon_grid(theme: DungeonThemeDefinition, grid_rows: Array, visibility: Dictionary, rooms: Array = []) -> void:
	impassable.clear()
	cover.clear()
	obstacle_group.clear()
	obstacles.clear()
	obstacle_type.clear()
	obstacle_cover.clear()
	blocks_los.clear()
	mud.clear()
	cell_texture.clear()
	door_edges.clear()
	wall_edges.clear()
	wall_edge_lines.clear()
	hazard_markers.clear()
	furniture_markers.clear()
	room_chest_markers.clear()
	room_stairs_markers.clear()
	rows = grid_rows.size()
	cols = 0
	for r in grid_rows:
		cols = max(cols, String(r).length())
	for y in range(grid_rows.size()):
		var row: String = grid_rows[y]
		for x in range(row.length()):
			var square := Vector2i(x, y)
			var ch: String = row[x]
			if ch == theme.wall_char or ch == "":
				impassable[square] = true
				blocks_los[square] = true   ## a dungeon wall blocks sight exactly like it blocks movement
				continue   ## per the request ("remove the wall tiles completely"): never textured, plain void
			elif ch == theme.door_closed_char:
				impassable[square] = true   ## blocks movement until opened
				blocks_los[square] = true
			if ch == theme.floor_char or ch == theme.door_closed_char or ch == theme.door_open_char:
				## Real DungeonCrawl tile art (per the user's own explicit
				## instruction to use their provided source file): a door
				## cell is visually just floor — the door itself is drawn
				## as a line overlay (see door_edges below), not a tile —
				## so it gets the exact same texture-variety treatment as
				## plain floor.
				var floor_tex: Texture2D = _pick_floor_texture(theme, x, y)
				if floor_tex != null:
					cell_texture[square] = floor_tex
				continue
			var tex: Texture2D = theme.tile_atlas.get(ch)
			if tex != null:
				cell_texture[square] = tex
	_build_door_edges(rooms)
	_build_room_wall_edges(rooms)
	_build_outer_wall_edge_lines()
	_build_hazard_markers(rooms)
	_build_furniture_markers(rooms)
	_build_room_chest_markers(rooms)
	_build_room_stairs_markers(rooms)
	_build_closed_door_near_face_cells(rooms)
	refresh_fog_of_war(visibility)

## Deterministic per-cell floor texture pick — stable across re-renders
## of the same square (so floor art doesn't change every time the grid
## rebuilds, e.g. when a door opens elsewhere), but varied from square
## to square, reusing the same stable hash BattleGridView's own ground-
## texture speckle already relies on. Falls back to the theme's single
## tile_atlas[floor_char] entry when floor_textures is empty, so older
## themes/tests that never set floor_textures keep working unchanged.
func _pick_floor_texture(theme: DungeonThemeDefinition, x: int, y: int) -> Texture2D:
	if theme.floor_textures.is_empty():
		return theme.tile_atlas.get(theme.floor_char)
	var h: float = BattleGridView._hash01(x, y, 7)
	var idx: int = int(h * theme.floor_textures.size())
	idx = clampi(idx, 0, theme.floor_textures.size() - 1)
	return theme.floor_textures[idx]

## Builds door_edges (see its own declaration comment) from `rooms`'
## own door_pos (the room's own near-face min-corner cell, directly
## touching the corridor's rail — no separate door tile of its own,
## per the follow-up request) and door_dir (unit direction from
## corridor toward the room) fields, set by DungeonGenerator.
## _attempt_room_at(). The line is drawn exactly on the shared boundary
## between the corridor's rail and the room's own near-face cells —
## the one point of contact a room is allowed to have with its
## corridor — the natural place a real door would actually hang.
func _build_door_edges(rooms: Array) -> void:
	var scale: int = DungeonGenerator.CORRIDOR_SCALE
	for room in rooms:
		var anchor_v = room.get("door_pos")
		var dir_v = room.get("door_dir")
		if anchor_v == null or dir_v == null:
			continue
		var anchor: Vector2i = anchor_v
		var dir: Vector2i = dir_v
		var entry: Dictionary = {"door_anchor": anchor}
		if dir.x != 0:
			entry["orientation"] = "vertical"
			entry["line_pos"] = anchor.x if dir.x > 0 else anchor.x + (scale - 1)
			entry["span_start"] = anchor.y
			entry["span_end"] = anchor.y + scale
		elif dir.y != 0:
			entry["orientation"] = "horizontal"
			entry["line_pos"] = anchor.y if dir.y > 0 else anchor.y + (scale - 1)
			entry["span_start"] = anchor.x
			entry["span_end"] = anchor.x + scale
		else:
			continue   ## no direction recorded (shouldn't happen) -- skip rather than guess
		door_edges.append(entry)

## Rebuilds closed_door_near_face_cells (see its own declaration
## comment) directly from `rooms`' own rect/door_pos/door_dir geometry —
## covers the room's ENTIRE near-face row in one pass, not just the
## door's own CORRIDOR_SCALE-wide span, since a room's face can be wider
## than its door. Same `along <= 0` rule
## field_encounter_screen.gd's own vision-memory-prune fix uses: `along`
## is how far a cell sits past the near-face row along the door's own
## inward direction — 0 or negative means "still on the near-face row
## itself," anything positive is genuinely INSIDE the room.
func _build_closed_door_near_face_cells(rooms: Array) -> void:
	closed_door_near_face_cells.clear()
	for room in rooms:
		if room.get("door_open", false):
			continue   ## an open door's near-face row is a legitimate visible surface -- nothing to hide
		var anchor_v = room.get("door_pos")
		var dir_v = room.get("door_dir")
		var rect_v = room.get("rect")
		if anchor_v == null or dir_v == null or rect_v == null:
			continue
		var anchor: Vector2i = anchor_v
		var dir: Vector2i = dir_v
		var rect: Rect2i = rect_v
		if dir == Vector2i.ZERO:
			continue
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				var cell := Vector2i(x, y)
				var diff: Vector2i = cell - anchor
				var along: int = diff.x * dir.x + diff.y * dir.y
				if along <= 0:
					closed_door_near_face_cells[cell] = true

## Records a sealed boundary between two orthogonally-adjacent cells,
## both directions (order-independent lookup — see _edge_blocked()).
func _add_wall_edge(a: Vector2i, b: Vector2i) -> void:
	if not wall_edges.has(a):
		wall_edges[a] = {}
	wall_edges[a][b] = true
	if not wall_edges.has(b):
		wall_edges[b] = {}
	wall_edges[b][a] = true

func _edge_blocked(a: Vector2i, b: Vector2i) -> bool:
	return wall_edges.has(a) and wall_edges[a].has(b)

## A real bug fix caught while building the pad-cell wall feature: a
## sealed edge only ever stops an ORTHOGONAL step straight across it —
## nothing stopped a diagonal step from hopping around the same corner
## instead (e.g. sealed between a room's own (9,3) and the corridor's
## (10,3): a plain _edge_blocked() check never fires for a diagonal move
## from (9,3) to (10,2), even though that diagonal visibly cuts across
## the exact same sealed boundary). Standard "no corner-cutting"
## grid-pathing rule, expressed in terms of THIS class's own wall_edges
## instead of plain impassable cells: for a diagonal step between `a`
## and `b`, the two cells that "flank" the corner are (a.x, b.y) and
## (b.x, a.y) — if the edge from `a` to the SECOND of those, or from `b`
## to the FIRST, is sealed, the diagonal is cutting straight through
## that sealed boundary and must be refused too. (Symmetric: swapping
## a/b swaps which flank is "first"/"second" but checks the exact same
## two edges either way.) A no-op for an orthogonal step (a.x==b.x or
## a.y==b.y), which _edge_blocked() alone already covers correctly.
##
## Real bug fix, per the report ("player can target the inside of the
## room to move too... moving through wall is still possible. the whole
## time the door is still closed" + the follow-up "monsters are also
## moving through the walls and shouldnt be able too"): this function
## only ever checked wall_edges (the sealed PAD-cell boundary case) —
## it never once considered a flank cell being a genuinely SOLID
## impassable cell (an ordinary dungeon wall, or a closed door — see
## generate_from_dungeon_grid()'s own impassable[square]=true for both).
## _footprint_walkable()/_footprint_clear() only ever check the
## DESTINATION cell's own walkability, so nothing anywhere stopped a
## diagonal step from cutting straight across the corner of a solid
## wall or a closed door as long as the far cell itself was open floor
## — exactly what let a player's Move preview (reachable_squares) and a
## monster's own AI pathing (_advance_toward -> the same reachable_
## squares/find_path) both slip diagonally around a closed door or a
## dungeon wall's corner into a room that was never actually entered
## through its (still-closed) door. Same "one sealed flank is enough to
## refuse the corner-cut" rule wall_edges already uses above, now
## applied identically to a genuinely impassable flank.
func _edge_blocked_diagonal(a: Vector2i, b: Vector2i) -> bool:
	if a.x == b.x or a.y == b.y:
		return false
	var flank1 := Vector2i(a.x, b.y)
	var flank2 := Vector2i(b.x, a.y)
	if impassable.has(flank1) or impassable.has(flank2):
		return true
	return _edge_blocked(a, flank2) or _edge_blocked(b, flank1)

## True if any consecutive pair along `from` -> line[0] -> line[1] -> ...
## crosses a sealed wall_edge boundary. `line` is a direct_line()-shaped
## array (excludes `from`, includes the final destination) — used by
## has_line_of_sight/get_ranged_cover, which both already walk a
## direct_line the same way.
func _crosses_wall_edge(from: Vector2i, line: Array) -> bool:
	if wall_edges.is_empty():
		return false
	var prev: Vector2i = from
	for cell in line:
		if _edge_blocked(prev, cell):
			return true
		prev = cell
	return false

## Shared by _build_room_wall_edges (a boundary between two WALKABLE
## cells that just aren't connected here — a room's own near-face vs.
## its corridor, no door) and _build_outer_wall_edge_lines (a boundary
## between a walkable cell and a genuine wall/void cell) — both just
## need "which edge of the grid sits between these two adjacent cells,"
## same convention door_edges already uses: horizontally-adjacent cells
## (different x) share a VERTICAL edge line at the larger x; vertically-
## adjacent cells (different y) share a HORIZONTAL edge line at the
## larger y, spanning exactly the width of one cell.
func _wall_edge_line_entry(a: Vector2i, b: Vector2i) -> Dictionary:
	var entry: Dictionary = {"cells": [a, b]}
	if a.x != b.x:
		entry["orientation"] = "vertical"
		entry["line_pos"] = maxi(a.x, b.x)
		entry["span_start"] = a.y
		entry["span_end"] = a.y + 1
	else:
		entry["orientation"] = "horizontal"
		entry["line_pos"] = maxi(a.y, b.y)
		entry["span_start"] = a.x
		entry["span_end"] = a.x + 1
	return entry

## Builds wall_edges/wall_edge_lines (see their own declaration
## comments) purely from each room's own rect/door_pos/door_dir fields —
## no DungeonGenerator changes needed. For every cell of a room's near
## face (the row/column of its own cells directly bordering the
## corridor it opens onto) that ISN'T one of the door's own
## CORRIDOR_SCALE cells, seals the boundary between that cell and the
## corridor cell directly across from it — exactly the "passage wall
## touches a room and there's no door" gap from the request.
func _build_room_wall_edges(rooms: Array) -> void:
	var scale: int = DungeonGenerator.CORRIDOR_SCALE
	for room in rooms:
		var anchor_v = room.get("door_pos")
		var dir_v = room.get("door_dir")
		var rect_v = room.get("rect")
		if anchor_v == null or dir_v == null or rect_v == null:
			continue
		var anchor: Vector2i = anchor_v
		var door_dir: Vector2i = dir_v
		var rect: Rect2i = rect_v
		if door_dir == Vector2i.ZERO:
			continue
		var perp: Vector2i = Vector2i(0, 1) if door_dir.x != 0 else Vector2i(1, 0)
		var near_face_start: Vector2i
		var width: int
		if door_dir.x != 0:
			near_face_start = Vector2i(anchor.x, rect.position.y)
			width = rect.size.y
		else:
			near_face_start = Vector2i(rect.position.x, anchor.y)
			width = rect.size.x
		var door_cell_set: Dictionary = {}
		for i in range(scale):
			door_cell_set[anchor + perp * i] = true
		for i in range(width):
			var face_cell: Vector2i = near_face_start + perp * i
			if door_cell_set.has(face_cell):
				continue   ## the real door -- already its own impassable/blocks_los tile while closed, no separate wall needed
			var corridor_cell: Vector2i = face_cell - door_dir
			_add_wall_edge(face_cell, corridor_cell)
			wall_edge_lines.append(_wall_edge_line_entry(face_cell, corridor_cell))

## Per the follow-up request ("add grey walls to all outer edges of the
## dungeon tiles. Use the exact same grey wall as already used next to
## doors"): _build_room_wall_edges above only ever draws the grey line
## between two WALKABLE cells that happen to be sealed off from each
## other (a room's near face vs. its own corridor). Every genuine
## wall/void cell (impassable AND never textured — see
## generate_from_dungeon_grid's own "never textured, plain void" wall_char
## handling just above) got no line at all — including the whole map's
## own outer perimeter, dead-end corridor caps, and any room wall that
## isn't next to a door. This walks every real floor/door cell instead
## (cell_texture.keys() — floor_char/door_open_char/door_closed_char all
## get a texture, only wall_char cells don't) and adds the exact same
## grey line wherever one of its 4 neighbours is a genuine wall cell.
## A closed door is impassable too, but stays textured, so
## `not cell_texture.has(neighbor)` correctly still leaves the door's
## own brown door_edges line alone here rather than drawing both on the
## same edge. No wall_edges gameplay entry needed here (unlike the
## no-door-gap case above) — impassable[] already blocks movement/LOS
## against a real wall cell unconditionally; this is purely the visual.
const _NEIGHBOR_DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
func _build_outer_wall_edge_lines() -> void:
	for sq in cell_texture.keys():
		for dir in _NEIGHBOR_DIRS:
			var neighbor: Vector2i = sq + dir
			if not impassable.has(neighbor) or cell_texture.has(neighbor):
				continue
			wall_edge_lines.append(_wall_edge_line_entry(sq, neighbor))

## Builds hazard_markers (see its own declaration comment) from `rooms`'
## own hazard_type/hazard_pos/hazard_cells/hazard_resolved fields (set by
## DungeonGenerator and mutated live by field_encounter_screen.gd's
## _maybe_trigger_hazard() once a hazard actually resolves). Per the
## request ("do not let a player move into or over a chasm"): every cell
## of a chasm's own span (hazard_cells — see DungeonGenerator's own
## comment on why it's now a line across the room's WIDTH rather than a
## single point) is marked impassable here, the same way a wall is —
## which for free makes every existing pathfinding function (find_path,
## reachable_squares, the move-highlight overlay) refuse it as a normal
## move destination with no further changes needed there. Deliberately
## NOT added to blocks_los — a physical gap in the floor doesn't block
## sight the way a wall does. Falls back to a single-cell span built from
## the older hazard_pos field for any save data from before this field
## existed. spike_trap is unaffected (stays a single hidden point, never
## impassable — its whole mechanic is that you can walk onto it).
func _build_hazard_markers(rooms: Array) -> void:
	for room in rooms:
		var htype: String = room.get("hazard_type", "none")
		if htype != "chasm" and htype != "spike_trap":
			continue
		if htype == "chasm":
			var cells_v = room.get("hazard_cells", [])
			var cells: Array = cells_v if cells_v is Array else []
			if cells.is_empty():
				var pos_v = room.get("hazard_pos")
				if pos_v != null and pos_v != Vector2i(-1, -1):
					cells = [pos_v]
			if cells.is_empty():
				continue
			for c in cells:
				impassable[c] = true
			hazard_markers.append({
				"pos": room.get("hazard_pos", cells[int(cells.size() / 2)]),
				"cells": cells,
				"type": htype,
				"resolved": room.get("hazard_resolved", false),
			})
		else:
			var pos_v = room.get("hazard_pos")
			if pos_v == null or pos_v == Vector2i(-1, -1):
				continue
			hazard_markers.append({
				"pos": pos_v,
				"type": htype,
				"resolved": room.get("hazard_resolved", false),
			})

## Builds furniture_markers (see its own declaration comment) from
## `rooms`' own furniture_type/furniture_cells/furniture_anchor/
## furniture_size/furniture_looted fields (set by DungeonGenerator and
## mutated live by field_encounter_screen.gd once a piece is actually
## searched). Same "mark every cell impassable" treatment
## _build_hazard_markers() above gives a chasm's own cells — per the
## request ("Character should not be able to walk on these new items"),
## this is what makes every pathing function (find_path,
## reachable_squares, the move-highlight overlay) refuse a furniture
## cell as a normal move destination, for free, with no changes needed
## anywhere else.
func _build_furniture_markers(rooms: Array) -> void:
	for room in rooms:
		var ftype: String = room.get("furniture_type", "none")
		if ftype == "none":
			continue
		var cells_v = room.get("furniture_cells", [])
		var cells: Array = cells_v if cells_v is Array else []
		if cells.is_empty():
			continue
		for c in cells:
			impassable[c] = true
		furniture_markers.append({
			"type": ftype,
			"cells": cells,
			"anchor": room.get("furniture_anchor", cells[0]),
			"size": room.get("furniture_size", Vector2i(1, 1)),
			"looted": room.get("furniture_looted", false),
			## Per the request ("furniture items should be placed along
			## the walls looking away from the wall"): points away from
			## the wall this piece is flush against, into the room — see
			## DungeonGenerator._place_footprint()'s own declaration
			## comment. BattleGridView rotates the piece's sprite to
			## match this direction.
			"facing": room.get("furniture_facing", Vector2i.ZERO),
		})

## Builds room_chest_markers (see its own declaration comment) from
## `rooms`' own chest_pos/chest_looted fields — only ever set on the
## Quest room (DungeonGenerator only ever populates chest_pos there),
## and only on the procedural generate() path (generate_fixed_room()'s
## Goblin Fort never populates `rooms` at all, so this is naturally a
## no-op there — see chest_marker_pos's own declaration comment for that
## dungeon's separate chest system). Marked impassable, same as
## furniture_markers above — a chest is as solid an obstacle as a rack
## or cupboard.
func _build_room_chest_markers(rooms: Array) -> void:
	for room in rooms:
		var pos_v = room.get("chest_pos", Vector2i(-1, -1))
		if pos_v == null or pos_v == Vector2i(-1, -1):
			continue
		impassable[pos_v] = true
		room_chest_markers.append({
			"pos": pos_v,
			"looted": room.get("chest_looted", false),
		})

## Builds room_stairs_markers (see its own declaration comment) from
## `rooms`' own stairs_pos field -- only ever set on the Quest room, and
## left at (-1, -1) once the dungeon has already reached its deepest
## floor (MAX_DUNGEON_FLOOR). Per the follow-up request, deliberately
## NOT marked impassable (unlike room_chest_markers above) -- the party
## can walk onto the stairs tile itself.
func _build_room_stairs_markers(rooms: Array) -> void:
	for room in rooms:
		var pos_v = room.get("stairs_pos", Vector2i(-1, -1))
		if pos_v == null or pos_v == Vector2i(-1, -1):
			continue
		room_stairs_markers.append({
			"pos": pos_v,
		})

## Called any time exploration mode's own fog-of-war recompute runs (see
## field_encounter_screen.gd's _reveal_around()) so the battle grid — the
## same grid the party is standing on and will fight on — always
## reflects the same fog state the party sees while exploring. See
## fog_of_war's own declaration comment for why this is usually a no-op
## in practice (the same Dictionary object is already being mutated in
## place) — called explicitly anyway for clarity at every call site.
func refresh_fog_of_war(visibility: Dictionary) -> void:
	fog_of_war = visibility

## Combat Encounter rework, Phase 4 (per the follow-up request: "detailed
## Tiles... let these offer varying degrees of cover" — a full rework of
## the original Phase 3 single-square scatter): every obstacle now
## occupies a real multi-square footprint, one of four size classes:
##   - "normal": 1 square
##   - "large": 4 squares (a compact block or short tetromino)
##   - "huge": 9-20 squares, deliberately irregular — per the request,
##     "huge ones will never be perfect square shapes" — grown organically
##     rather than filled as a rectangle (see _shape_huge/
##     _break_rectangle_if_needed)
##   - "line": 3-9 squares, straight or bent once at a right angle
##     (fences/walls only, per the request "straight or L shape")
## plus High Grass's own small "clump" (1-5 squares, "in clumps of upto
## 5"), grown the same organic way as "huge" just far smaller.
##
## `obstacle_group`: Vector2i(square) -> index into `obstacles` below,
## so a renderer or any mechanics code can find an obstacle's whole
## footprint/type from any one of its own squares (used for seamless
## multi-square rendering in BattleGridView, and for telling two
## different obstacle instances apart when they happen to sit adjacent).
## `obstacles`: Array[Dictionary], one entry per placed instance —
## {"type": String, "size_class": String, "squares": Array[Vector2i],
## "cover": String ("none"/"light"/"medium"/"hard"), "blocks_los": bool}.
var obstacle_group: Dictionary = {}
var obstacles: Array = []

## Kept for BattleGridView and existing tests: Vector2i(square) -> type
## name, same convention Phase 3 already used — now just derived from
## `obstacles` at scatter time instead of being the primary record.
var obstacle_type: Dictionary = {}

## Per-square cover tier granted by an obstacle specifically — as
## opposed to `cover` above, which is the older, unrelated terrain-
## forest "standing in it" cover sourced from the encounter's own
## terrain snapshot. Vector2i(square) -> "light"/"medium"/"hard", read
## by get_ranged_cover() below. Obstacles no longer feed into `cover`
## itself (Phase 3 used to): most obstacle types are impassable now, so
## a defender can never actually stand ON one — cover has to come from
## what's standing BETWEEN the attacker and the defender instead, which
## is exactly what get_ranged_cover()'s own line-scan checks for.
var obstacle_cover: Dictionary = {}

## Line-of-sight blockers — used by has_line_of_sight() below (the
## Broken Condition's "a full Round hidden out of line of sight" auto-
## recovery) and by get_ranged_cover() (per the request: "dont allow to
## shoot if there is no line of sight"). Per the request's own "No line
## of sight above" note, only Boulder and Structure at their Huge size
## are tall/dense enough to fully block a sightline — every other
## obstacle, even a hard-cover one, only ever worsens the shot (see
## COVER_PENALTY), never blocks it outright.
var blocks_los: Dictionary = {}

const COVER_PENALTY := {"light": -10, "medium": -20, "hard": -30, "none": 0}

## type -> {sizes: Array[String] (repeated entries weight which size
## gets picked how often — see _pick_size — biasing toward the smaller,
## more common ones per the request: "the bigger they are, the less
## amount of them should be added to the map"), cover: String, passable:
## bool, blocks_los_at: Array[String] (size classes at which this type
## fully blocks line of sight rather than just granting cover)}.
##
## Per the follow-up request ("Battle map obstacle positioning and
## sizes"): Boulder ("Rocks") and Structure no longer use the old
## generic "normal"/"large"/"huge" sizes at all — see RECT_SIZE_DIMS
## below for the named rectangular footprints each now picks from
## instead (still weighted toward the smaller ones, same principle as
## before). Bush and Tree each gained a "clump" option alongside their
## old solitary "normal" (see _shape_for's own "clump" case, shared with
## HighGrass) so some show up as small clusters rather than always one
## lone square — "some separate, some in clumps." Pond dropped its old
## "large" weighting almost entirely in favour of "huge" ("less separate
## ponds but bigger ones" — see also OBSTACLE_MAX_COUNT and
## POND_CENTER_EXCLUSION_FRAC below for the count cap and the "not in
## the center" placement rule, and _shape_huge()'s own widened range for
## the "bigger" half of that request).
const OBSTACLE_TYPES := {
	"Boulder": {"sizes": ["2x2", "2x2", "2x2", "3x3", "3x3", "2x3", "3x2", "3x4"], "cover": "hard", "passable": false, "blocks_los_at": ["3x4", "3x3"]},
	"Tree": {"sizes": ["normal", "normal", "normal", "clump", "clump"], "cover": "hard", "passable": false, "blocks_los_at": []},
	"Bush": {"sizes": ["normal", "normal", "normal", "clump", "clump"], "cover": "medium", "passable": false, "blocks_los_at": []},
	"HighGrass": {"sizes": ["clump"], "cover": "light", "passable": true, "blocks_los_at": []},
	"Pond": {"sizes": ["huge", "huge", "huge", "large"], "cover": "none", "passable": false, "blocks_los_at": []},
	"BrokenCart": {"sizes": ["large"], "cover": "hard", "passable": false, "blocks_los_at": []},
	"Fence": {"sizes": ["line"], "cover": "medium", "passable": false, "blocks_los_at": []},
	"Structure": {"sizes": ["2x2", "2x2", "3x3"], "cover": "hard", "passable": false, "blocks_los_at": ["3x3"]},
}

## Per the follow-up request: hard instance caps for the four types
## called out as needing to be LESS numerous ("Less separate ponds...
## max 2", "BrokenCart... less in number (max 3-4)", "Fence : less
## random", "Structures : Maximum 3-4"). A type absent from this dict
## (Boulder/Tree/Bush/HighGrass) has no cap at all — see
## _try_scatter_obstacles()'s own comment for why that's exactly what
## makes those four read as "more in number" without needing their own
## explicit boost: once the capped types stop being eligible, the same
## square budget just keeps flowing to whichever types are left.
## Re-rolled per generation (_roll_obstacle_max_counts()) rather than
## fixed, so e.g. BrokenCart isn't ALWAYS exactly 4 every single map.
func _roll_obstacle_max_counts() -> Dictionary:
	return {
		"Pond": randi_range(1, 2),
		"BrokenCart": randi_range(3, 4),
		"Structure": randi_range(3, 4),
		"Fence": 2,   ## "a couple of segments" -- literally a couple, not a range
	}

## Per the follow-up request ("battle map forest sections... should
## change to be clumps of tree's rather then the big square with green
## dot tiles... The clumps of trees should be dense but still allow
## moving about the area, ie no solid walls of trees"): a forest-
## flagged terrain block (`cover` above — unchanged, still the exact
## same whole-relative-tile flag from the encounter's own terrain
## snapshot, still grants the same ranged "standing in it" cover bonus
## it always has via get_ranged_cover/is_covered) used to just render
## as one flat tinted square with a scattering of decorative dots. This
## instead scatters real Tree obstacle instances across the cover
## footprint, so a forest genuinely reads as a stand of trees. Called
## FIRST inside _try_scatter_obstacles() below (before the general
## random budget loop even starts), and since every retry in
## _scatter_obstacles()'s own loop calls _clear_obstacles_only() then
## _try_scatter_obstacles() fresh, forest trees are re-rolled right
## alongside everything else on each attempt — fully participating in
## the same _obstacles_leave_grid_connected() check AND
## _thin_overcrowded_pockets() safety net every other obstacle type
## already relies on. That thinning pass (same 60%-surrounded rule as
## everything else) is what actually guarantees "no solid walls of
## trees" — no forest-specific exemption needed, it's already generic.
const FOREST_TREE_DENSITY := 0.5   ## target fraction of forest-flagged squares occupied by a Tree instance -- "dense" without aiming for literally solid

func _scatter_forest_trees() -> void:
	if cover.is_empty():
		return
	var forest_squares: Array = cover.keys()
	var target: int = int(forest_squares.size() * FOREST_TREE_DENSITY)
	var ally_center := Vector2i(ALLY_START_COL, ROWS / 2)
	var adversary_center := Vector2i(ADVERSARY_START_COL, ROWS / 2)
	var props: Dictionary = OBSTACLE_TYPES["Tree"]
	var placed := 0
	var attempts := 0
	var max_attempts: int = forest_squares.size() * 3
	while placed < target and attempts < max_attempts:
		attempts += 1
		## Anchored directly at a forest square (no near-path-style
		## jitter) and every one of the shape's own squares is required
		## to ALSO be a forest square below — unlike BrokenCart/Fence's
		## "near the mud path" bias (which is fine drifting a few squares
		## off the path itself), a tree standing outside the forest
		## footprint would leave a stray Tree on plain grass with no
		## forest-floor ground tile under it, an obvious mismatch once
		## BattleGridView starts drawing real forest-floor art there.
		var anchor: Vector2i = forest_squares[randi() % forest_squares.size()]
		var size_class: String = _pick_size("Tree")
		var shape: Array = _shape_for("Tree", size_class)
		var squares: Array = []
		var ok := true
		for rel in shape:
			var sq: Vector2i = anchor + rel
			if not is_in_bounds(sq) or not cover.has(sq) or impassable.has(sq) or obstacle_group.has(sq):
				ok = false
				break
			if distance_squares(sq, ally_center) < OBSTACLE_START_CLEARANCE or distance_squares(sq, adversary_center) < OBSTACLE_START_CLEARANCE:
				ok = false
				break
			## Per the follow-up request ("keep tree's and bushes off the
			## mud path too"): a forest square that happens to also be a
			## mud path square (the path can wind straight through a
			## forest-flagged block) is skipped same as any other
			## disqualified square — `mud` only holds the path trails at
			## this point, same call-order guarantee _try_scatter_
			## obstacles already relies on for BrokenCart/Fence's own
			## near_squares bias.
			if mud.has(sq):
				ok = false
				break
			squares.append(sq)
		if not ok:
			continue
		var idx := obstacles.size()
		var blocks_los_here: bool = props["blocks_los_at"].has(size_class)
		obstacles.append({
			"type": "Tree", "size_class": size_class, "squares": squares,
			"cover": props["cover"], "blocks_los": blocks_los_here,
		})
		for sq in squares:
			obstacle_group[sq] = idx
			obstacle_type[sq] = "Tree"
			impassable[sq] = true
			obstacle_cover[sq] = props["cover"]
			if blocks_los_here:
				blocks_los[sq] = true
		placed += squares.size()

## Named rectangular footprints for Boulder ("Rocks") and Structure (per
## the follow-up request's explicit size lists for each) — a plain solid
## block, unlike Boulder's old jagged LARGE_SHAPES/organic-blob "huge".
const RECT_SIZE_DIMS := {
	"2x2": Vector2i(2, 2),
	"3x3": Vector2i(3, 3),
	"2x3": Vector2i(2, 3),
	"3x2": Vector2i(3, 2),
	"3x4": Vector2i(3, 4),
}

## Scaled by the same ~2.25x area factor as the COLS/ROWS enlargement
## (30x18=540 squares -> 45x27=1215 squares) so the battlefield keeps the
## same obstacle DENSITY as before rather than reading as suddenly much
## emptier — the original 50/90 (out of 540) values are still the design
## intent, just rebased to the new total.
## Per the follow-up request ("add more tree's, bushes and high
## grass"): bumped ~20% from the original 113/203 rebase — most of that
## extra budget flows straight to vegetation via VEGETATION_DRAW_WEIGHT
## below and the extra guaranteed Tree/Bush/HighGrass queue entries in
## _try_scatter_obstacles, not spread evenly across every type.
const GROUND_BUDGET_MIN := 135   ## total obstacle-occupied squares targeted per map (out of 1215) —
const GROUND_BUDGET_MAX := 240   ## enough real variety without ever feeling clogged (see the request's own "dont make it cluttered")
const OBSTACLE_MAX_INSTANCES := 230   ## safety cap on placement attempts, never actually reached in practice
const OBSTACLE_PLACEMENT_ATTEMPTS := 50   ## random anchor tries before giving up on one particular instance
## Per the follow-up request ("add more tree's, bushes and high
## grass"): how many times Tree/Bush/HighGrass each appear in the
## weighted random-draw pool once the capped types (Pond/BrokenCart/
## Structure/Fence) drop out of eligibility — see the while loop in
## _try_scatter_obstacles. Anything absent here (Boulder, or any capped
## type still under its cap) defaults to a plain weight of 1.
const VEGETATION_DRAW_WEIGHT := {
	"Tree": 3,
	"Bush": 3,
	"HighGrass": 3,
}
## Chebyshev squares kept clear around each side's own starting block
## (see ALLY_START_COL/ADVERSARY_START_COL below) so a scattered
## obstacle can never wall a side into its own deployment corner right
## at encounter start.
const OBSTACLE_START_CLEARANCE := 3
## Per the follow-up request ("Ponds... Not in the center of the map"):
## a Pond instance's whole footprint is rejected if ANY of its squares
## fall within this fraction of COLS/ROWS either side of the grid's own
## center point — e.g. 0.16 excludes the middle ~32% band of both axes,
## leaving the edges/corners (where a pond reads more naturally anyway)
## open. See _in_center_zone().
const POND_CENTER_EXCLUSION_FRAC := 0.16
## Per the follow-up request ("BrokenCart... near the mud path" /
## "Fence... along the mud path"): when biasing an anchor toward a mud
## path square (see _place_obstacle's own near_squares param), this is
## how far the anchor is allowed to jitter from the chosen path square —
## a small wobble so a cart/fence segment sits close beside the path
## rather than stamped exactly on top of it every time.
const NEAR_PATH_JITTER := 3

## Randomly scatters obstacles across the grid, retrying a few times
## (fully re-rolling scatter, not just nudging the offending square) if
## the result would wall the two deployment zones off from each other
## entirely. Falls back to no obstacles at all if every retry still
## fails, which is always a safe, valid battlefield even if a plain one.
func _scatter_obstacles() -> void:
	for attempt in range(5):
		_clear_obstacles_only()
		_try_scatter_obstacles()
		if _obstacles_leave_grid_connected():
			## Per the follow-up request ("never surround a character or
			## monster with a obstacle more then 60% around them"): a
			## thinning pass, not another full reroll — see its own
			## comment for why. Runs only once connectivity's already
			## confirmed good, since removing obstacles can only ever
			## open the map up further, never re-break connectivity.
			_thin_overcrowded_pockets()
			return
	_clear_obstacles_only()

func _clear_obstacles_only() -> void:
	for sq in obstacle_group.keys():
		## Every square recorded here was confirmed NOT already
		## impassable at placement time (see _place_obstacle), so any
		## impassability here can only have come from the obstacle
		## itself — safe to unconditionally erase (a no-op for the one
		## passable type, High Grass, which was never added).
		impassable.erase(sq)
		obstacle_cover.erase(sq)
		blocks_los.erase(sq)
	obstacle_group.clear()
	obstacle_type.clear()
	obstacles.clear()

## Picks one of `type_name`'s allowed sizes, weighted by however many
## times it's repeated in OBSTACLE_TYPES' own sizes list.
static func _pick_size(type_name: String) -> String:
	var sizes: Array = OBSTACLE_TYPES[type_name]["sizes"]
	return sizes[randi() % sizes.size()]

## Relative-coordinate shape generators — every shape is anchored so its
## own first-placed cell sits at Vector2i.ZERO; _place_obstacle offsets
## every point by the same randomly-chosen anchor square once, then
## checks/commits purely in absolute grid space.

## "large" (4 squares): a handful of small, mostly-compact shapes for
## natural-feature types (Boulder/Pond) — picked per-instance for
## visual variety. BrokenCart/Structure always use the plain 2x2 block
## instead (see _shape_for) — a cart or a small outbuilding reads as one
## coherent object with a real rectangular footprint, not a jagged
## tetromino.
const LARGE_SHAPES := [
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],   ## 2x2 block
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],   ## horizontal 1x4
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)],   ## vertical 4x1
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)],   ## L
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],   ## T
]

static func _shape_2x2() -> Array:
	return [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]

## Shared organic grower for "huge" and High Grass's "clump" — grows one
## square at a time from a random already-placed cell's empty orthogonal
## neighbour, which by construction almost never fills a perfect
## rectangle on its own.
static func _grow_blob(target: int) -> Array:
	var cells: Array = [Vector2i.ZERO]
	var cell_set: Dictionary = {Vector2i.ZERO: true}
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var attempts := 0
	while cells.size() < target and attempts < target * 20:
		attempts += 1
		var base: Vector2i = cells[randi() % cells.size()]
		var next: Vector2i = base + dirs[randi() % dirs.size()]
		if cell_set.has(next):
			continue
		cells.append(next)
		cell_set[next] = true
	return cells

## "huge" (16-32 squares): per the original request, "huge ones will
## never be perfect square shapes" — _grow_blob already almost never
## produces a filled rectangle, but the one case it might (a small,
## unlucky target that happens to fill its own bounding box) is
## explicitly broken here. Range widened from the original 9-20 per the
## follow-up request ("less separate ponds but bigger ones") — this is
## now the ONLY size Pond meaningfully rolls (see OBSTACLE_TYPES' own
## weighting), so making it bigger directly delivers "bigger ones."
static func _shape_huge() -> Array:
	var cells: Array = _grow_blob(randi_range(16, 32))
	var cell_set: Dictionary = {}
	for c in cells:
		cell_set[c] = true
	var min_x := 999
	var max_x := -999
	var min_y := 999
	var max_y := -999
	for c in cells:
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_y = mini(min_y, c.y)
		max_y = maxi(max_y, c.y)
	var w := max_x - min_x + 1
	var h := max_y - min_y + 1
	if w > 1 and h > 1 and cells.size() == w * h:
		## Bug fix (surfaced by the follow-up request's larger obstacle
		## budget rolling far more Huge instances per map, which made a
		## previously-rare edge case common enough to actually hit):
		## removing a corner to break the rectangle would drop the
		## footprint BELOW the Huge minimum (16 squares, widened from the
		## original 9 — see _shape_huge's own comment) whenever the blob
		## started at exactly that size. Grow one extra cell instead
		## whenever removing would under-size it (attaching onto a
		## random existing cell's empty orthogonal neighbour, same style
		## as _grow_blob) — that also breaks the perfect rectangle, just
		## by extending it rather than shrinking it. Safe to just remove
		## the corner once the blob is already comfortably above the
		## minimum.
		if cells.size() - 1 < 16:
			var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			var attempts := 0
			while attempts < 100:
				attempts += 1
				var base: Vector2i = cells[randi() % cells.size()]
				var next: Vector2i = base + dirs[randi() % dirs.size()]
				if not cell_set.has(next):
					cells.append(next)
					break
		else:
			cells.erase(Vector2i(max_x, max_y))   ## drop one corner to break the rectangle
	return cells

## High Grass "clump" (per the request: "in clumps of upto 5") — same
## organic grower, small enough that no rectangle guard is needed (a
## 1x5 or 2x3-minus-one line still reads as "a clump of grass").
static func _shape_clump(max_size: int) -> Array:
	return _grow_blob(randi_range(1, max_size))

## Fence/wall "line" (per the request: "3-9 squares long... straight or
## L shape").
static func _shape_line() -> Array:
	var length: int = randi_range(3, 9)
	if length < 4 or randf() < 0.5:
		var horizontal := randf() < 0.5
		var cells: Array = []
		for i in range(length):
			cells.append(Vector2i(i, 0) if horizontal else Vector2i(0, i))
		return cells
	## L-shape: two straight legs sharing one corner cell, so the total
	## cell count still comes out to `length`.
	var leg1: int = randi_range(2, length - 2)
	var leg2: int = length - leg1 + 1
	var dir_options := [
		[Vector2i(1, 0), Vector2i(0, 1)], [Vector2i(1, 0), Vector2i(0, -1)],
		[Vector2i(-1, 0), Vector2i(0, 1)], [Vector2i(-1, 0), Vector2i(0, -1)],
	]
	var dirs: Array = dir_options[randi() % dir_options.size()]
	var cell_set: Dictionary = {}
	var cur := Vector2i.ZERO
	cell_set[cur] = true
	for i in range(leg1 - 1):
		cur += dirs[0]
		cell_set[cur] = true
	var corner := cur
	for i in range(leg2 - 1):
		cur = corner + dirs[1] * (i + 1)
		cell_set[cur] = true
	return cell_set.keys()

## Plain solid rectangle, w columns by h rows, anchored at Vector2i.ZERO —
## used for Boulder/Structure's named RECT_SIZE_DIMS footprints below
## (a rock or a building reads as one coherent block, not a jagged
## tetromino/blob like the older "large"/"huge" shapes).
static func _shape_rect(w: int, h: int) -> Array:
	var cells: Array = []
	for y in range(h):
		for x in range(w):
			cells.append(Vector2i(x, y))
	return cells

static func _shape_for(type_name: String, size_class: String) -> Array:
	if RECT_SIZE_DIMS.has(size_class):
		var dims: Vector2i = RECT_SIZE_DIMS[size_class]
		return _shape_rect(dims.x, dims.y)
	match size_class:
		"clump":
			return _shape_clump(5)
		"line":
			return _shape_line()
		"large":
			if type_name == "BrokenCart" or type_name == "Structure":
				return _shape_2x2()
			return LARGE_SHAPES[randi() % LARGE_SHAPES.size()].duplicate()
		"huge":
			return _shape_huge()
		_:
			return [Vector2i.ZERO]   ## "normal"

## Per the follow-up request ("Ponds... Not in the center of the map"):
## true if `sq` falls within POND_CENTER_EXCLUSION_FRAC of COLS/ROWS
## either side of the grid's own center point.
func _in_center_zone(sq: Vector2i) -> bool:
	var margin_x: int = int(COLS * POND_CENTER_EXCLUSION_FRAC)
	var margin_y: int = int(ROWS * POND_CENTER_EXCLUSION_FRAC)
	var cx := COLS / 2
	var cy := ROWS / 2
	return absi(sq.x - cx) <= margin_x and absi(sq.y - cy) <= margin_y

## Tries up to OBSTACLE_PLACEMENT_ATTEMPTS random anchor squares for one
## obstacle instance; commits and returns true on the first anchor whose
## whole footprint is in-bounds, clear of every other impassable/
## obstacle square, and outside both deployment clearances. Returns
## false (the caller just skips this instance) if no anchor works —
## expected occasionally on a crowded map, never a failure state.
##
## `near_squares` (per the follow-up request, "BrokenCart... near the
## mud path" / "Fence... along the mud path"): when non-empty, each
## attempt's anchor is chosen as a random square from this list jittered
## by up to NEAR_PATH_JITTER in both axes, instead of a fully random
## anchor — biasing placement toward (without pinning it exactly onto)
## the mud path. `avoid_center` (per "Ponds... Not in the center of the
## map"): when true, any attempt whose footprint touches the grid's
## center zone (see _in_center_zone) is rejected same as an out-of-
## bounds/overlap failure. `avoid_mud` (per the follow-up request,
## "structures, rocks, fences not be placed on the mud path"): when
## true, any attempt whose footprint touches an already-scattered mud
## path square (see `mud` — only the winding path trails exist yet at
## this point, see _try_scatter_obstacles's own comment on call order)
## is rejected the same way. Combined with Fence's own near_squares bias
## above, this naturally reads as "fence runs alongside the path" rather
## than "fence stamped on top of it."
func _place_obstacle(type_name: String, size_class: String, shape: Array, ally_center: Vector2i, adversary_center: Vector2i, near_squares: Array = [], avoid_center: bool = false, avoid_mud: bool = false) -> bool:
	var props: Dictionary = OBSTACLE_TYPES[type_name]
	for attempt in range(OBSTACLE_PLACEMENT_ATTEMPTS):
		var anchor: Vector2i
		if not near_squares.is_empty():
			var base: Vector2i = near_squares[randi() % near_squares.size()]
			anchor = base + Vector2i(randi_range(-NEAR_PATH_JITTER, NEAR_PATH_JITTER), randi_range(-NEAR_PATH_JITTER, NEAR_PATH_JITTER))
		else:
			anchor = Vector2i(randi_range(0, COLS - 1), randi_range(0, ROWS - 1))
		var squares: Array = []
		var ok := true
		for rel in shape:
			var sq: Vector2i = anchor + rel
			if not is_in_bounds(sq) or impassable.has(sq) or obstacle_group.has(sq):
				ok = false
				break
			if distance_squares(sq, ally_center) < OBSTACLE_START_CLEARANCE or distance_squares(sq, adversary_center) < OBSTACLE_START_CLEARANCE:
				ok = false
				break
			if avoid_center and _in_center_zone(sq):
				ok = false
				break
			if avoid_mud and mud.has(sq):
				ok = false
				break
			squares.append(sq)
		if not ok:
			continue
		var idx := obstacles.size()
		var cover_level: String = props["cover"]
		var blocks_los_here: bool = props["blocks_los_at"].has(size_class)
		obstacles.append({
			"type": type_name, "size_class": size_class, "squares": squares,
			"cover": cover_level, "blocks_los": blocks_los_here,
		})
		for sq in squares:
			obstacle_group[sq] = idx
			obstacle_type[sq] = type_name
			if not props["passable"]:
				impassable[sq] = true
			if cover_level != "none":
				obstacle_cover[sq] = cover_level
			if blocks_los_here:
				blocks_los[sq] = true
		return true
	return false

## Per the request ("all types of cover need to be available"): every
## type gets one guaranteed instance, at its own most representative
## (first-weighted) size, before any random extras — so no single map
## can come up missing an entire category of cover. Extras on top are
## random type+size picks (weighted by OBSTACLE_TYPES' own sizes list)
## until the square budget's spent or the safety cap's hit.
##
## Per the follow-up request: Pond/BrokenCart/Structure/Fence are each
## subject to a per-map instance cap (see _roll_obstacle_max_counts) —
## once a capped type hits its roll, it drops out of the random-draw
## pool entirely (the guaranteed queue entry above never exceeds any
## cap, since every roll is >=1). Uncapped types (Boulder/Tree/Bush/
## HighGrass) simply receive whatever budget the capped types no longer
## soak up, which is exactly what reads as "more in number" for
## Bush/Tree/HighGrass without needing an explicit boost of their own.
## BrokenCart and Fence are additionally biased toward the mud path via
## `near_squares` (`mud` holds only path squares at this point in
## generate_from_terrain_snapshot's call order — _scatter_mud_patches()
## runs after obstacle scatter, see that function's own comment), and
## Pond is placed with `avoid_center` set (see _in_center_zone).
func _try_scatter_obstacles() -> void:
	## Forest trees first (see _scatter_forest_trees()'s own comment) —
	## every square they occupy is already in obstacle_group/impassable
	## by the time the general scatter below runs, so _place_obstacle's
	## own collision check naturally steers every other obstacle type
	## clear of them without any special-casing here.
	_scatter_forest_trees()
	var ally_center := Vector2i(ALLY_START_COL, ROWS / 2)
	var adversary_center := Vector2i(ADVERSARY_START_COL, ROWS / 2)
	var target_budget: int = randi_range(GROUND_BUDGET_MIN, GROUND_BUDGET_MAX)
	var placed_squares := 0
	var all_types: Array = OBSTACLE_TYPES.keys()
	var max_counts: Dictionary = _roll_obstacle_max_counts()
	var type_counts: Dictionary = {}
	for t in all_types:
		type_counts[t] = 0
	var path_squares: Array = mud.keys()
	var queue: Array = []
	for t in all_types:
		queue.append({"type": t, "size": OBSTACLE_TYPES[t]["sizes"][0]})
	## Per the follow-up request ("add more tree's, bushes and high
	## grass"): 2 extra guaranteed instances each on top of the one
	## every type already gets above (random size this time, not always
	## the representative sizes[0]) — so every map reliably reads as
	## more overgrown even before the weighted random draw below ever
	## gets a turn. Boulder/Pond/BrokenCart/Structure/Fence are
	## untouched here; they still get exactly their one guaranteed
	## instance same as before.
	for t in ["Tree", "Bush", "HighGrass"]:
		for i in range(2):
			queue.append({"type": t, "size": _pick_size(t)})
	var instances := 0
	while placed_squares < target_budget and instances < OBSTACLE_MAX_INSTANCES:
		var req: Dictionary
		if not queue.is_empty():
			req = queue.pop_front()
		else:
			var eligible: Array = all_types.filter(func(t): return not max_counts.has(t) or type_counts[t] < max_counts[t])
			if eligible.is_empty():
				break
			## Weighted, not a flat pick, per the same "more tree/bush/
			## high grass" request — Tree/Bush/HighGrass each appear 3x
			## as often as everything else in the pool once the capped
			## types (Pond/BrokenCart/Structure/Fence) drop out, so the
			## extra square budget those leave behind flows mostly to
			## vegetation instead of splitting evenly with Boulder. See
			## VEGETATION_DRAW_WEIGHT below.
			var weighted: Array = []
			for t in eligible:
				for i in range(VEGETATION_DRAW_WEIGHT.get(t, 1)):
					weighted.append(t)
			var t: String = weighted[randi() % weighted.size()]
			req = {"type": t, "size": _pick_size(t)}
		instances += 1
		var shape: Array = _shape_for(req["type"], req["size"])
		var near: Array = []
		if (req["type"] == "BrokenCart" or req["type"] == "Fence") and not path_squares.is_empty():
			near = path_squares
		var avoid_center: bool = req["type"] == "Pond"
		## Per the follow-up request ("structures, rocks, fences not be
		## placed on the mud path"), the further follow-up ("keep tree's
		## and bushes off the mud path too"), and the one after that
		## ("and the high grass"): every ground-clutter obstacle type
		## except BrokenCart now rejects any footprint touching a mud
		## path square — see _place_obstacle's own comment. BrokenCart is
		## deliberately still exempt: a cart broken down ON the road it
		## was travelling is exactly the point of biasing it toward the
		## path in the first place.
		var avoid_mud: bool = req["type"] != "BrokenCart"
		if _place_obstacle(req["type"], req["size"], shape, ally_center, adversary_center, near, avoid_center, avoid_mud):
			placed_squares += shape.size()
			type_counts[req["type"]] = type_counts.get(req["type"], 0) + 1

## --- Ground terrain dressing (per the follow-up request: "apply grass,
## mud and water tiles to the battle map like on the world maps") ------
## A purely cosmetic secondary ground type — irregular Mud patches
## scattered across otherwise-plain walkable ground, echoing the World
## Map's own grass/mud-path palette. No movement-cost or cover effect of
## its own (this project's movement doesn't model difficult ground yet —
## see this file's own Phase 1 comment at the top). "Water" isn't a
## third, separate ground layer here — the Pond obstacle above already
## renders real, impassable water and is now GUARANTEED at least once
## per map (see the queue in _try_scatter_obstacles), so this doesn't
## duplicate it with a second, competing patch of blue.
var mud: Dictionary = {}   ## Vector2i(square) -> true

## Patch COUNT scaled by the same ~2.25x area factor the obstacle budget
## above uses, so mud coverage stays proportionally the same on the
## larger map; patch SIZE is left as-is (a "handful of patches", not a
## few giant ones).
const MUD_PATCH_COUNT_MIN := 5
const MUD_PATCH_COUNT_MAX := 11
const MUD_PATCH_SIZE_MAX := 10

## Per the follow-up request ("form a few (upto 2) mud paths crossing
## the map from side the side, as well as some smaller patches dotted
## around"): 0-2 winding dirt trails, each running the full width or
## height of the map, IN ADDITION to the small dotted-around patches
## above — see _scatter_mud_path().
const MUD_PATH_COUNT_MIN := 0
const MUD_PATH_COUNT_MAX := 2

## Per the follow-up request ("BrokenCart... near the mud path" / "Fence
## ... a couple of segments along the mud path"): split out of the old
## single _scatter_ground_terrain() so the winding path trails exist
## BEFORE _scatter_obstacles() runs — _try_scatter_obstacles() reads
## `mud.keys()` as its own "place near here" pool for those two types.
## Clears `mud` (the small dotted patches below add to it later, in the
## same generation, so they must NOT also clear it).
func _scatter_mud_paths() -> void:
	mud.clear()
	for i in range(randi_range(MUD_PATH_COUNT_MIN, MUD_PATH_COUNT_MAX)):
		_scatter_mud_path()

## The small dotted-around mud patches — unchanged from the old
## _scatter_ground_terrain(), just renamed and now called separately
## AFTER _scatter_obstacles() (same ordering as before: it still needs
## obstacles to already exist so it can steer clear of them).
func _scatter_mud_patches() -> void:
	for i in range(randi_range(MUD_PATCH_COUNT_MIN, MUD_PATCH_COUNT_MAX)):
		var anchor := Vector2i(randi_range(0, COLS - 1), randi_range(0, ROWS - 1))
		for rel in _shape_clump(MUD_PATCH_SIZE_MAX):
			var sq: Vector2i = anchor + rel
			if is_in_bounds(sq) and not impassable.has(sq) and not obstacle_group.has(sq):
				mud[sq] = true

## One winding dirt path crossing the whole map from one side to the
## opposite side — a biased random walk starting on a random point along
## one edge (west or north, picked at random) and stepping mostly toward
## the FAR edge (east or south respectively) with a little lateral drift
## each step, so it wanders like a real trail rather than ruling a
## perfectly straight line. Occasionally widens by one square to a
## random side for the same reason. Steps straight through any obstacle/
## impassable square it crosses without marking it — a path interrupted
## by a boulder or a stand of trees reads as natural, not a bug, and
## this way the path never fights the existing "mud never overlaps an
## obstacle" rule the dotted patches above already follow.
func _scatter_mud_path() -> void:
	var horizontal := randf() < 0.5
	var pos: Vector2i = Vector2i(0, randi_range(0, ROWS - 1)) if horizontal else Vector2i(randi_range(0, COLS - 1), 0)
	var steps := 0
	var max_steps: int = (COLS + ROWS) * 2   ## generous -- a true straight crossing takes COLS or ROWS steps, wander adds some slack
	while steps < max_steps:
		steps += 1
		_mark_mud_if_clear(pos)
		if randf() < 0.4:
			var side: Vector2i
			if horizontal:
				side = Vector2i(0, 1) if randf() < 0.5 else Vector2i(0, -1)
			else:
				side = Vector2i(1, 0) if randf() < 0.5 else Vector2i(-1, 0)
			_mark_mud_if_clear(pos + side)
		var reached_far_edge: bool = (horizontal and pos.x >= COLS - 1) or (not horizontal and pos.y >= ROWS - 1)
		if reached_far_edge:
			return
		var advance: Vector2i = Vector2i(1, 0) if horizontal else Vector2i(0, 1)
		var lateral := Vector2i.ZERO
		if randf() < 0.5:
			if horizontal:
				lateral = Vector2i(0, 1) if randf() < 0.5 else Vector2i(0, -1)
			else:
				lateral = Vector2i(1, 0) if randf() < 0.5 else Vector2i(-1, 0)
		pos += advance + lateral
		pos.x = clampi(pos.x, 0, COLS - 1)
		pos.y = clampi(pos.y, 0, ROWS - 1)

func _mark_mud_if_clear(sq: Vector2i) -> void:
	if is_in_bounds(sq) and not impassable.has(sq) and not obstacle_group.has(sq):
		mud[sq] = true

## Sanity check after scattering: the two deployment zones must still be
## able to reach each other via SOME path — see _scatter_obstacles().
func _obstacles_leave_grid_connected() -> bool:
	var ally_center := Vector2i(ALLY_START_COL, ROWS / 2)
	var adversary_center := Vector2i(ADVERSARY_START_COL, ROWS / 2)
	var ally_open := find_open_square_near(ally_center, {})
	var adversary_open := find_open_square_near(adversary_center, {})
	if not is_walkable(ally_open) or not is_walkable(adversary_open):
		return false
	return not find_path(ally_open, adversary_open, {}).is_empty()

## Per the follow-up request ("never surround a character or monster
## with a obstacle more then 60% around them"): any OPEN square is
## somewhere a character or monster could end up standing (deployment,
## a later Move, a monster's own AI repositioning — nothing here is
## specific to where anyone's actually standing right now), so this
## walks every open square on the grid and, for whichever one is worst,
## removes an offending obstacle INSTANCE entirely until none of them
## has more than 60% of its in-bounds neighbours blocked. A thinning
## pass rather than another full `_scatter_obstacles()` reroll (see that
## function's own retry loop) — a global reroll risks needing many more
## attempts to satisfy this on top of the connectivity check, especially
## now that the enlarged map's obstacle budget is denser than before;
## surgically removing just the specific instance causing the worst
## pocket converges quickly and never has to fall back to "no obstacles
## at all" the way a failed reroll eventually would.
const MAX_IMPASSABLE_NEIGHBOR_FRACTION := 0.6
const OVERCROWD_THIN_SAFETY_CAP := 200   ## bounds the loop below — should never actually be hit; see the loop's own comment

## Per the follow-up request ("less separate ponds but bigger ones"): a
## widened Pond blob (see _shape_huge's own comment) naturally has a
## more irregular shoreline than the old 9-20 range did, which was
## tripping THIS pass — an open grass square tucked into a narrow spit
## of shoreline reads as "surrounded" by the exact same math as a
## character genuinely walled in by clustered obstacles, and since Pond
## is usually the single biggest instance touching that square, it was
## the one getting blamed and removed almost every time, defeating the
## "bigger ones" request outright (most maps were coming up with NO pond
## at all after thinning). A lake having a narrow peninsula is normal
## and desirable, not the clutter problem this pass exists to fix, so
## Pond is exempted from ever being blamed here — see the skip below.
func _thin_overcrowded_pockets() -> void:
	var iterations := 0
	var exempt_squares: Dictionary = {}   ## squares this pass already found nothing safe to do about -- skipped on later iterations so one unfixable pocket can't block thinning elsewhere on the map
	while iterations < OVERCROWD_THIN_SAFETY_CAP:
		iterations += 1
		var worst_sq := Vector2i(-1, -1)
		var worst_frac := MAX_IMPASSABLE_NEIGHBOR_FRACTION
		for y in range(ROWS):
			for x in range(COLS):
				var sq := Vector2i(x, y)
				if impassable.has(sq) or exempt_squares.has(sq):
					continue   ## only OPEN, not-yet-exempted squares matter -- nobody can ever be "surrounded" while standing on an impassable one
				var total := 0
				var blocked := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var n := sq + Vector2i(dx, dy)
						if not is_in_bounds(n):
							continue
						total += 1
						if impassable.has(n):
							blocked += 1
				if total == 0:
					continue
				var frac: float = float(blocked) / float(total)
				if frac > worst_frac:
					worst_frac = frac
					worst_sq = sq
		if worst_sq == Vector2i(-1, -1):
			return   ## nothing left over the threshold -- done
		## Blame whichever neighbouring obstacle INSTANCE is largest —
		## the biggest contributor to the pocket, and removing it clears
		## the most crowding per removal. Pond is skipped entirely (see
		## this function's own opening comment). A neighbour that's
		## impassable but ISN'T part of any obstacle_group entry is plain
		## terrain (a wall/water block from the encounter's own
		## snapshot) — there's nothing here safe to remove for that
		## either, so it's simply skipped; if every blocking neighbour
		## turns out to be plain terrain or Pond, this particular square
		## is marked exempt and left as-is rather than looping forever on
		## it — other genuinely-fixable pockets elsewhere still get
		## thinned on the next iteration.
		var worst_instance_idx := -1
		var worst_instance_size := -1
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var n := worst_sq + Vector2i(dx, dy)
				if obstacle_group.has(n):
					var idx: int = obstacle_group[n]
					if obstacles[idx]["type"] == "Pond":
						continue
					var inst_size: int = obstacles[idx]["squares"].size()
					if inst_size > worst_instance_size:
						worst_instance_size = inst_size
						worst_instance_idx = idx
		if worst_instance_idx == -1:
			exempt_squares[worst_sq] = true
			continue
		_remove_obstacle_instance(worst_instance_idx)

## Undoes one obstacle instance's placement (per _thin_overcrowded_pockets
## above). Clears its footprint's state but leaves its own slot in
## `obstacles` in place with an empty "squares" list rather than actually
## removing the array entry — actually removing it would shift every
## later instance's index, silently invalidating every obstacle_group
## value that still points at them by index. Every reader of `obstacles`
## elsewhere (BattleGridView's stretched-detail pass, BattleObstaclesTest)
## already skips an empty "squares" entry as a matter of course, so a
## "removed" slot is indistinguishable from one that simply never placed
## anything.
func _remove_obstacle_instance(idx: int) -> void:
	var inst: Dictionary = obstacles[idx]
	for sq in inst.get("squares", []):
		if obstacle_group.get(sq, -1) == idx:
			obstacle_group.erase(sq)
			obstacle_type.erase(sq)
			impassable.erase(sq)
			obstacle_cover.erase(sq)
			blocks_los.erase(sq)
	inst["squares"] = []

## True if nothing along the direct line between `a` and `b` (exclusive
## of `b`'s own square — standing IN cover doesn't block your sightline
## OUT of that same square, matching how is_covered() already treats a
## defender's own square separately from what's blocking further along;
## `a` is already excluded since direct_line() itself never includes its
## own start square) blocks line of sight. Used by Broken's "a full
## Round hidden out of line of sight" auto-recovery — see
## field_encounter_screen.gd's _is_hidden_from_enemies().
func has_line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	var line: Array = direct_line(a, b)
	for i in range(line.size() - 1):
		if blocks_los.has(line[i]):
			return false
	if _crosses_wall_edge(a, line):
		return false
	return true

func is_in_bounds(square: Vector2i) -> bool:
	return square.x >= 0 and square.x < cols and square.y >= 0 and square.y < rows

func is_walkable(square: Vector2i) -> bool:
	return is_in_bounds(square) and not impassable.has(square)

func is_covered(square: Vector2i) -> bool:
	return cover.has(square)

## Ranged cover + line-of-sight resolution between `attacker` and
## `target` squares (per the follow-up request: "Cover works against
## Ranged attack if the target is standing behind the obstacle from the
## line of sight of the attack... light -10/medium -20/hard -30... dont
## allow to shoot if there is no line of sight"). Walks the direct line
## between them, excluding both endpoints (standing on/in cover
## yourself doesn't block your own sightline out, same convention
## has_line_of_sight already uses), and returns the single WORST cover
## tier any intervening obstacle square grants — or `blocked = true`
## outright if anything genuinely sight-blocking (a Huge Boulder/
## Structure) is in the way, which refuses the shot entirely regardless
## of any lesser cover also along the same line.
## Returns {"blocked": bool, "penalty": int, "level": String}.
## Falls back to the older, unrelated terrain-forest "standing in it"
## cover (`cover` above, sourced from the encounter's own terrain
## snapshot, not the obstacle scatter) as a light-cover floor when the
## target's own square is tagged that way and nothing worse was found
## along the line — most obstacle types can no longer be stood ON at
## all (only High Grass is passable), so this is the one remaining case
## of "cover from the ground you're standing in" rather than "cover
## from what's standing between you and the shooter."
##
## Bug fix, per the request ("the target does not have any cover in
## this situation, ie when the only cover between them is one directly
## beside the attacker and there is no other cover between them"): an
## obstacle square within Chebyshev distance 1 of the ATTACKER's own
## square — e.g. a Tree standing right next to the shooter — no longer
## contributes cover to the target. Physically this is the same
## reasoning as standing next to a rock: it's beside YOU, not between
## you and something far away, so you simply look/shoot past it; the
## cover mechanic is meant to model the TARGET being obscured, not
## clutter at the shooter's own feet. This also happens to fix a
## Bresenham direct_line() quirk: a near-diagonal line's very first step
## can graze a cell touching the start point even though the true ray
## never meaningfully passes through it, which is exactly what made a
## Tree beside the attacker read as blocking a shot at a target well off
## to the side. Only affects the partial-cover check (obstacle_cover) —
## a genuinely sight-blocking Huge obstacle (blocks_los) still refuses
## the shot even at distance 1, since that's a real LOS block, not a
## cover-tier judgement call.
func get_ranged_cover(attacker: Vector2i, target: Vector2i) -> Dictionary:
	var line: Array = direct_line(attacker, target)
	if _crosses_wall_edge(attacker, line):
		return {"blocked": true, "penalty": 0, "level": "blocked"}
	var worst_level := "none"
	var worst_penalty := 0
	for i in range(line.size() - 1):
		var sq: Vector2i = line[i]
		if blocks_los.has(sq):
			return {"blocked": true, "penalty": 0, "level": "blocked"}
		if obstacle_cover.has(sq) and distance_squares(attacker, sq) > 1:
			var lvl: String = obstacle_cover[sq]
			var pen: int = COVER_PENALTY[lvl]
			if pen < worst_penalty:
				worst_penalty = pen
				worst_level = lvl
	if worst_level == "none" and cover.has(target):
		worst_level = "light"
		worst_penalty = COVER_PENALTY["light"]
	return {"blocked": false, "penalty": worst_penalty, "level": worst_level}

## Chebyshev distance in squares (diagonal movement costs the same as
## orthogonal — the standard convention for a square tactical grid, and
## the one this class uses everywhere else: find_path/reachable_squares
## below both cost every one of the 8 neighbor directions equally).
static func distance_squares(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

static func distance_yards(a: Vector2i, b: Vector2i) -> int:
	return distance_squares(a, b) * YARDS_PER_SQUARE

## --- Multi-square creature footprints (Large=2x2, Enormous=3x3,
## Monstrous=4x4, per Character.get_footprint_size()) -- every helper
## below defaults `size`/`footprint_size` to 1, which reduces every
## formula bit-for-bit to the original single-square behavior, so none
## of the pre-existing 1x1 call sites need to change.

## The NxN block of cells a `size`x`size` creature occupies, anchored at
## its top-left cell (the convention battle_positions already uses for
## every combatant, footprint or not). size<=1 is just [anchor], so this
## is a drop-in no-op wherever a caller hasn't been updated yet.
static func footprint_cells(anchor: Vector2i, size: int = 1) -> Array:
	if size <= 1:
		return [anchor]
	var cells: Array = []
	for dy in range(size):
		for dx in range(size):
			cells.append(anchor + Vector2i(dx, dy))
	return cells

func _footprint_walkable(anchor: Vector2i, size: int) -> bool:
	for sq in footprint_cells(anchor, size):
		if not is_walkable(sq):
			return false
	return true

## Whether a `size`x`size` footprint anchored at `anchor` has room to
## stand there: every cell of the footprint must be walkable, and every
## cell must also be free of `blocked` (other combatants' occupied
## squares) UNLESS `anchor` IS the destination footprint itself — mirrors
## find_path's original single-cell "sq != to" exemption (callers are
## allowed to path *toward* an occupied destination footprint; scaled up,
## the whole destination footprint is exempted only when standing exactly
## on it, not for any square merely overlapping it along the way).
func _footprint_clear(anchor: Vector2i, size: int, blocked: Dictionary, dest_anchor: Vector2i, dest_size: int) -> bool:
	if not _footprint_walkable(anchor, size):
		return false
	if anchor == dest_anchor and size == dest_size:
		return true
	for sq in footprint_cells(anchor, size):
		if blocked.has(sq):
			return false
	return true

## Closed-form gap (in squares) between two axis-aligned solid NxN
## footprints — the smallest number of steps one would need to move
## before the two footprints' edges touch. Reduces to distance_squares()
## when both sizes are 1. Used for melee/adjacency checks so a multi-
## square creature is correctly "in range" from whichever of its cells is
## nearest, not just its anchor.
static func footprint_distance(anchor_a: Vector2i, size_a: int, anchor_b: Vector2i, size_b: int) -> int:
	var a_min_x := anchor_a.x
	var a_max_x := anchor_a.x + size_a - 1
	var a_min_y := anchor_a.y
	var a_max_y := anchor_a.y + size_a - 1
	var b_min_x := anchor_b.x
	var b_max_x := anchor_b.x + size_b - 1
	var b_min_y := anchor_b.y
	var b_max_y := anchor_b.y + size_b - 1
	var dx := maxi(0, maxi(b_min_x - a_max_x, a_min_x - b_max_x))
	var dy := maxi(0, maxi(b_min_y - a_max_y, a_min_y - b_max_y))
	return maxi(dx, dy)

## A direct 8-directional line from `from` to `to` (Bresenham's line
## algorithm), always exactly distance_squares(from, to) steps long —
## consistent with this class's uniform per-step cost, but unlike the
## plain-BFS fallback below (whose neighbor-scan order tends to walk the
## whole diagonal component first and only straighten out afterward,
## reading as "moving at an angle" rather than heading straight for the
## clicked square) this interleaves diagonal and straight steps evenly,
## so it actually looks like the straight line it's approximating on a
## square grid. Walkability/blocking isn't checked here — see find_path,
## which uses this as its preferred route whenever nothing's in the way.
## Returned path excludes `from`, includes `to`.
static func direct_line(from: Vector2i, to: Vector2i) -> Array:
	var points: Array = []
	var x0 := from.x
	var y0 := from.y
	var x1 := to.x
	var y1 := to.y
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while x0 != x1 or y0 != y1:
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
		points.append(Vector2i(x0, y0))
	return points

## Shortest path (8-directional, uniform 1-square cost per step,
## consistent with distance_squares' own Chebyshev metric) from `from` to
## `to`, honoring impassable squares and `blocked` (other combatants'
## current squares — a square already occupied blocks passing through
## it, same as a real battle line, EXCEPT as the final destination
## itself, which callers are expected to have already excluded from
## `blocked` if `to` is meant to be reachable). Returns an empty array if
## no path exists. The returned path includes `to` but not `from`.
##
## Per the request ("the arrow takes the most direct path"): tries
## direct_line() first — if every square along it is walkable and
## unblocked, that's returned as-is (a genuinely straight line, not just
## *a* shortest path). Only falls back to the BFS below, which finds *a*
## shortest path but with no preference for how direct-looking it is,
## when something's actually in the way.
## Straight-line-only reachability check, reused by Charge (p.157) -- a
## Charge is a direct rush at the target, not a controlled Move that can
## detour around obstacles the way find_path() below deliberately does.
## Returns false if `from == to` or if anything along the direct line
## (impassable terrain, or an occupied square other than `to` itself) is
## in the way -- mirrors find_path()'s own internal "is the direct line
## clear" check, but exposed standalone so Charge-eligibility code can
## ask this question without needing a full path result back.
func has_clear_direct_path(from: Vector2i, to: Vector2i, blocked: Dictionary = {}, footprint_size: int = 1) -> bool:
	if from == to:
		return false
	var prev: Vector2i = from
	for sq in direct_line(from, to):
		if not _footprint_clear(sq, footprint_size, blocked, to, footprint_size):
			return false
		if footprint_size == 1 and (_edge_blocked(prev, sq) or _edge_blocked_diagonal(prev, sq)):
			return false
		prev = sq
	return true

## `avoid_cost` (Vector2i -> extra int cost), per the request ("Monsters
## need a movement-cost penalty so pathfinding prefers routes around
## burning squares"): a SOFT per-square surcharge on top of the normal
## cost of 1 to step onto that square -- unlike `blocked`, it never
## makes a square unreachable, it just makes routes through it look
## longer to the search below, so a real detour gets picked when one
## exists without ever leaving a mover stuck with nowhere to go if
## avoiding it entirely isn't possible. Defaults to {} (no penalty
## anywhere), which makes every existing caller's behavior identical to
## before this parameter existed.
func find_path(from: Vector2i, to: Vector2i, blocked: Dictionary = {}, footprint_size: int = 1, avoid_cost: Dictionary = {}) -> Array:
	if not _footprint_walkable(to, footprint_size):
		return []
	if from == to:
		return []
	var direct: Array = direct_line(from, to)
	## The direct-line shortcut below is only ever correct when nothing
	## on it is being avoided -- under uniform cost a straight line is
	## unbeatable, but once avoid_cost is in play, a longer detour around
	## a penalized square can genuinely cost less than barreling straight
	## through it, so this must fall through to the real weighted search
	## instead. avoid_cost is {} for every pre-existing caller, so this
	## adds no new behavior for any of them.
	var direct_avoided := false
	if not avoid_cost.is_empty():
		for sq in direct:
			if avoid_cost.has(sq):
				direct_avoided = true
				break
	if not direct_avoided:
		var direct_clear := true
		var direct_prev: Vector2i = from
		for sq in direct:
			if not _footprint_clear(sq, footprint_size, blocked, to, footprint_size):
				direct_clear = false
				break
			if footprint_size == 1 and (_edge_blocked(direct_prev, sq) or _edge_blocked_diagonal(direct_prev, sq)):
				direct_clear = false
				break
			direct_prev = sq
		if direct_clear:
			return direct
	## Per the follow-up request ("movement pathing always take the
	## direct straight path over angles"): the old approach recorded a
	## single `came_from` parent per cell -- whichever neighbor happened
	## to discover it FIRST, purely an artifact of the dy/dx scan order
	## below. That still finds *a* shortest path once the direct line
	## above is blocked, but with no preference for how direct it looks:
	## a detour around an obstacle tended to walk its whole diagonal
	## component first and only straighten out afterward, reading as a
	## sharp-angled dogleg rather than a taut line hugging the obstacle.
	##
	## Fixed by splitting into two passes. First, a flood fill recording
	## ONLY the shortest distance to every reachable cell (`dist` below),
	## no parent tracking at all. Then a separate backward reconstruction
	## from `to` to `from` that, at each step, considers EVERY neighbor
	## exactly one step closer (not just whichever discovered it first)
	## and picks whichever one sits closest to the straight line between
	## `from` and `to`. Still guaranteed shortest -- every step strictly
	## decreases `dist` by 1 -- just the straightest-looking one of the
	## possibly many equally-short paths.
	##
	## Per the follow-up request (avoid_cost, above): "shortest" is no
	## longer always "fewest steps" once a step can cost more than 1, so
	## the plain FIFO flood fill (correct only for uniform-cost BFS) is
	## now a Dijkstra-style expansion instead -- always settle the
	## closest still-unsettled square next, not just whatever was
	## discovered first. A plain linear-scan "extract min" rather than a
	## real priority queue: battle grids in this project are small
	## enough that this doesn't matter, same simplicity-over-asymptotic-
	## optimality tradeoff this class's other grid algorithms already
	## make. Degrades to exactly the old FIFO BFS's own result whenever
	## avoid_cost is empty, since every step costs exactly 1 either way.
	var dist: Dictionary = {from: 0}
	var settled: Dictionary = {}
	var frontier: Array = [from]
	while not frontier.is_empty():
		var best_i := 0
		for i in range(1, frontier.size()):
			if dist[frontier[i]] < dist[frontier[best_i]]:
				best_i = i
		var current: Vector2i = frontier[best_i]
		frontier.remove_at(best_i)
		if settled.has(current):
			continue
		settled[current] = true
		if current == to:
			break
		var current_dist: int = dist[current]
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var next: Vector2i = current + Vector2i(dx, dy)
				if settled.has(next):
					continue
				if not _footprint_clear(next, footprint_size, blocked, to, footprint_size):
					continue
				if footprint_size == 1 and (_edge_blocked(current, next) or _edge_blocked_diagonal(current, next)):
					continue
				var step_cost: int = 1 + int(avoid_cost.get(next, 0))
				var next_dist: int = current_dist + step_cost
				if not dist.has(next) or next_dist < dist[next]:
					dist[next] = next_dist
					frontier.append(next)
	if not dist.has(to):
		return []
	## Straight-line direction from `from` to `to`, used purely as a
	## tie-breaker below (it never changes which paths count as
	## shortest/cheapest, only which of several equally-cheap ones gets
	## chosen).
	var line_dir: Vector2 = Vector2(to - from)
	if line_dir.length() > 0.0:
		line_dir = line_dir.normalized()
	var path: Array = []
	var step: Vector2i = to
	while step != from:
		## Generalized from the old "any neighbor exactly 1 closer" check
		## -- with a non-uniform avoid_cost, the actual cost of the final
		## step INTO `step` varies per square, so the neighbor being
		## looked for is whichever one is cheaper by exactly that step's
		## own cost, not always exactly 1.
		var step_cost: int = 1 + int(avoid_cost.get(step, 0))
		var target_prev_dist: int = dist[step] - step_cost
		var best_prev: Vector2i = from
		var best_offset: float = INF
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var prev: Vector2i = step + Vector2i(dx, dy)
				if dist.get(prev, target_prev_dist - 1) != target_prev_dist:
					continue
				if footprint_size == 1 and (_edge_blocked(prev, step) or _edge_blocked_diagonal(prev, step)):
					continue
				## Perpendicular distance of `prev` from the from->to
				## line (cross product against the unit direction) --
				## smaller means closer to a straight line between the
				## two endpoints, i.e. a straighter-looking route.
				var rel: Vector2 = Vector2(prev - from)
				var offset: float = absf(rel.x * line_dir.y - rel.y * line_dir.x)
				if offset < best_offset:
					best_offset = offset
					best_prev = prev
		path.append(step)
		step = best_prev
	path.reverse()
	return path

## Every square reachable from `from` within `max_squares` steps (a
## flood fill capped at that depth — valid because every step, including
## diagonals, costs exactly 1 under this class's Chebyshev metric), for
## the UI to highlight as valid Move/Run destinations before the player
## clicks one. Honors impassable squares and `blocked` occupied squares.
## `from` itself is never included in the result.
func reachable_squares(from: Vector2i, max_squares: int, blocked: Dictionary = {}, footprint_size: int = 1) -> Array:
	var visited: Dictionary = {from: 0}
	var frontier: Array = [from]
	var head := 0
	var result: Array = []
	while head < frontier.size():
		var current: Vector2i = frontier[head]
		head += 1
		var dist: int = visited[current]
		if dist >= max_squares:
			continue
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var next: Vector2i = current + Vector2i(dx, dy)
				if visited.has(next):
					continue
				if not _footprint_walkable(next, footprint_size):
					continue
				if footprint_size == 1 and (_edge_blocked(current, next) or _edge_blocked_diagonal(current, next)):
					continue
				var blocked_here := false
				for sq in footprint_cells(next, footprint_size):
					if blocked.has(sq):
						blocked_here = true
						break
				if blocked_here:
					continue
				visited[next] = dist + 1
				frontier.append(next)
				result.append(next)
	return result

## --- Ranged range bands, relative to the weapon's own Range stat (yards) --
## This project's combat previously had no positional/yardage tracking
## at all (see weapon_definition.gd's own Reach comment) — this is a
## genuinely new mechanic layered on for the grid rework, modelled on
## the core rulebook's own "Calculating Range Bands" formula (Point
## Blank = Range ÷ 10, Short = Range ÷ 2, Long = Range x 2, Extreme =
## Range x 3) and its Ranged Weapons modifier table: Point Blank +40,
## Short +20, Long +0, Extreme -30. Beyond Extreme range, the target
## cannot be attacked with that weapon at all. Real bug fix: both the
## thresholds AND the modifiers here used to be wrong (Point Blank was
## computed as Range/2 instead of Range/10, Short as up to Range
## instead of Range/2, and the modifiers were a simplified +20/+10/
## -10/-20 that didn't match the book) — confirmed and corrected
## against the core rulebook's own pages while auditing the targeting UI.
enum RangeBand { POINT_BLANK, SHORT, LONG, EXTREME, OUT_OF_RANGE }

static func get_range_band(distance_yd: int, weapon_range_yd: int) -> RangeBand:
	if weapon_range_yd <= 0:
		return RangeBand.OUT_OF_RANGE
	if distance_yd <= weapon_range_yd / 10.0:
		return RangeBand.POINT_BLANK
	if distance_yd <= weapon_range_yd / 2.0:
		return RangeBand.SHORT
	if distance_yd <= weapon_range_yd * 2:
		return RangeBand.LONG
	if distance_yd <= weapon_range_yd * 3:
		return RangeBand.EXTREME
	return RangeBand.OUT_OF_RANGE

static func get_range_band_modifier(band: RangeBand) -> int:
	match band:
		RangeBand.POINT_BLANK:
			return 40
		RangeBand.SHORT:
			return 20
		RangeBand.LONG:
			return 0
		RangeBand.EXTREME:
			return -30
		_:
			return 0

static func get_range_band_name(band: RangeBand) -> String:
	match band:
		RangeBand.POINT_BLANK:
			return "Point Blank"
		RangeBand.SHORT:
			return "Short"
		RangeBand.LONG:
			return "Long"
		RangeBand.EXTREME:
			return "Extreme"
		_:
			return "Out of Range"

## Default placement blocks for a fresh encounter (per the request: start
## "about just out of average (Move 4) charge range" rather than at
## opposite ends of the battlefield). Charging (see field_encounter_
## screen.gd's _target_in_charge_range) allows a move up to
## movement_remaining squares, which starts each turn at
## Character.get_movement() * 2 — so an average Move-4 combatant's
## farthest chargeable path this Round is AVERAGE_MOVE * 2 = 8 squares.
## Since the charge path's destination is the square ADJACENT to the
## target (not the target's own square), a front-line-to-front-line
## Chebyshev distance of AVERAGE_CHARGE_SQUARES + 1 already puts that
## path one square past what a Move-4 charger could cover; +2 keeps it
## "just" out of range with a hair of margin either side of exact
## equality, rather than sitting right on the knife's edge.
const AVERAGE_MOVE := 4
const AVERAGE_CHARGE_SQUARES := AVERAGE_MOVE * 2
const START_DISTANCE_SQUARES := AVERAGE_CHARGE_SQUARES + 2
const ALLY_START_COL := COLS / 2 - START_DISTANCE_SQUARES / 2
const ADVERSARY_START_COL := COLS / 2 + START_DISTANCE_SQUARES / 2

## Ambush layout (per the follow-up request): when one side starts the
## encounter genuinely Surprised, the OTHER side ("the attackers")
## instead starts comfortably WITHIN charge range of them, and the
## surprised side starts clustered tightly together — "relatively
## grouped up" — rather than spread the grid's full height, since being
## caught by surprise means getting caught bunched up, not deployed.
## AMBUSH_DISTANCE_SQUARES is measured from the victim cluster's own
## center square, which the victims themselves occupy the squares
## nearest to — so the real gap to the nearest victim is a couple of
## squares less than this value once that cluster radius is accounted
## for. Sized to comfortably land the resulting Charge path inside an
## average Move-4 character's own chargeable band — [AVERAGE_MOVE,
## AVERAGE_CHARGE_SQUARES], i.e. 4 to 8 squares now that the Charge
## minimum is the mover's own current Movement value rather than a
## flat 3 (see field_encounter_screen.gd's _target_in_charge_range) —
## rather than right up against either edge of that band.
const AMBUSH_DISTANCE_SQUARES := 6

## Finds the nearest walkable, unblocked square to `preferred` (including
## `preferred` itself if it already qualifies) via an expanding ring
## search — used to place combatants at encounter start without ever
## stacking two combatants on the same square or dropping one on
## impassable ground, even if the naive preferred square happens to land
## on a wall/water block from the terrain snapshot.
## `footprint_size` (per the multi-square creature footprint feature):
## when placing a Large/Enormous/Monstrous combatant, the WHOLE `size`x
## `size` block anchored at the candidate must be clear, not just the one
## cell — otherwise a big creature could spawn with part of itself
## overlapping a wall or another combatant. Defaults to 1, so every
## pre-existing caller (all of which place ordinary 1x1 combatants) is
## unaffected.
func find_open_square_near(preferred: Vector2i, blocked: Dictionary, footprint_size: int = 1) -> Vector2i:
	if _footprint_clear(preferred, footprint_size, blocked, preferred, -1):
		return preferred
	for radius in range(1, cols + rows):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var candidate: Vector2i = preferred + Vector2i(dx, dy)
				if _footprint_clear(candidate, footprint_size, blocked, candidate, -1):
					return candidate
	return preferred   ## Should be unreachable on any grid with at least one open square.

## Bug fix: picks the open square immediately adjacent to `target` (one
## of its 8 neighbours, Chebyshev distance 1) that's CLOSEST to `from` —
## i.e. the side of the target the mover is actually approaching from.
## Used for Charge/melee-closing instead of find_open_square_near, which
## always answers "nearest open square to target" via a fixed ring-scan
## order that (for an open battlefield with every neighbour free) always
## returns the same one — the NW neighbour, since it's first in that
## scan order — regardless of which direction the mover approached from.
## That made every Charge/melee-close land the attacker on the target's
## NW side no matter where they started.
## Falls back to find_open_square_near (any open square near the target,
## not necessarily adjacent) only if the target is fully boxed in — every
## one of its 8 neighbours is either off-grid, impassable, or occupied.
## `target_size`/`footprint_size` (multi-square footprint feature):
## "adjacent" is generalized from "one of target's 8 single-cell
## neighbours" to "any footprint_size x footprint_size block whose edge
## touches target's own target_size x target_size footprint" — the
## search ring is widened accordingly (from target's footprint edge out
## to footprint_size cells beyond it), and the whole mover footprint at
## each candidate must be clear. Both default to 1, so this reduces
## exactly to the original single-cell 3x3-neighbour scan for every
## pre-existing caller.
func find_open_square_adjacent_to(target: Vector2i, from: Vector2i, blocked: Dictionary, target_size: int = 1, footprint_size: int = 1) -> Vector2i:
	var best: Vector2i = target
	var best_dist_sq := -1
	var lo := -footprint_size
	var hi := target_size + footprint_size - 1
	for dy in range(lo, hi + 1):
		for dx in range(lo, hi + 1):
			var candidate: Vector2i = target + Vector2i(dx, dy)
			if footprint_distance(candidate, footprint_size, target, target_size) != 1:
				continue
			if not _footprint_walkable(candidate, footprint_size):
				continue
			var blocked_here := false
			for sq in footprint_cells(candidate, footprint_size):
				if blocked.has(sq):
					blocked_here = true
					break
			if blocked_here:
				continue
			## Real (squared) Euclidean distance, not the Chebyshev metric
			## distance_squares() uses elsewhere for movement cost — ties
			## under Chebyshev are common along a cardinal approach (e.g.
			## due south, the S/SW/SE neighbours are all equally "1 step
			## away" by Chebyshev), which would just reintroduce a
			## directional bias via scan order. True distance correctly
			## prefers the neighbour actually in line with the approach.
			var delta: Vector2i = from - candidate
			var d_sq: int = delta.x * delta.x + delta.y * delta.y
			if best_dist_sq == -1 or d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best = candidate
	if best_dist_sq == -1:
		return find_open_square_near(target, blocked, footprint_size)
	return best

## Every in-bounds square within `radius` (Chebyshev distance, same
## metric as distance_squares) of `center`, inclusive of `center`
## itself — used for AoE spell/prayer targeting (Blast, Twin-tailed
## Comet): the player clicks a square, this is the set that effect's
## radius actually covers. Walkability isn't checked — an AoE affects
## whoever's standing there, walls don't block a blast's radius in this
## project's simplified model (the same simplification Soulfire's own
## "every living adversary" already makes). `radius <= 0` returns just
## `center` (still in-bounds-checked).
func squares_within_radius(center: Vector2i, radius: int) -> Array:
	var result: Array = []
	var r: int = max(0, radius)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var candidate: Vector2i = center + Vector2i(dx, dy)
			if is_in_bounds(candidate):
				result.append(candidate)
	return result
