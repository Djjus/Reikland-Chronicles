extends RefCounted
class_name UbersreikRoadNetwork
## New City Screen feature (follow-up request: "Vector some rough
## walking paths between the main districts... try and use the main
## roads/Gates, so that travel across the map looks more realistic"):
## a rough hand-placed waypoint graph following Ubersreik's own main
## streets and the river crossing — used so a walk between two
## locations follows a plausible route through the districts in
## between (gate -> district junction -> the bridge -> the next
## district junction -> destination) rather than cutting a straight
## line through the middle of city blocks or straight across the
## river.
##
## Deliberately "rough", per the request — these are hand-eyeballed
## junction points along the map's own visible roads/bridge, not a
## precise street-by-street trace. Positions are normalized (0..1)
## fractions of the background map image, same convention as
## CityLocationDefinition.map_position, so this works at any zoom
## level exactly like the location markers do.

## Waypoint id -> normalized position. The four gate/bridge nodes
## reuse the exact same coordinates as their own CityLocationDefinition
## entries (North/East/Water/South Gate, Ubersreik Bridge) so a route
## that passes through a gate or the bridge visibly passes through its
## real marker position.
##
## Follow-up request ("review the Travel vector pathing again and
## improve it significantly, make sure that the character never
## crosses water directly or takes unnecessarily long paths"): pixel-
## sampled the actual map art (a connected-component flood-fill from a
## known river pixel, so only the real contiguous river body counts —
## not the similarly blue-gray rooftops in Artisan's Quarter/Teubrücke
## that a naive per-pixel color check falsely flagged) against every
## graph edge AND every one of the 71 real locations' own "walk to
## nearest waypoint" last-mile segment. Found the river itself is
## cleanly avoided everywhere except around "water_gate": that waypoint
## used to sit exactly on Water Gate's own map position, which the
## source art draws as the city WALL crossing directly over the river
## (a lock/floodgate built into the fortifications, not a footpath —
## there's no painted causeway the way the real bridge has one). With
## that waypoint sitting in the river bend, walks to/from it from
## either bank routed straight across open water. Fixed here two ways:
## "water_gate" is nudged onto dry land on the NORTH bank only (still
## right by the wall, just off the water), and the illegitimate
## south-bank edge to "teubrucke_west" is removed below — this graph
## now has exactly ONE way to cross the river (the bridge chain), same
## as the real map art only shows one. "teubrucke_west" also got a
## tiny nudge further from the bank so its edge to "bridge_south" no
## longer clips the river's southern edge. (Water Gate's own map
## marker in CityLocationDefinition was nudged the same small amount
## for the same reason — see ubersreik_city_locations.tres — though it
## remains unlocked/unreachable today.)
##
## Follow-up request ("improve the ubersreik POI travel vector path,
## give it more complexity"): the original graph had one hub node per
## district (15 waypoints total) — good enough to avoid cutting through
## city blocks, but every route through a given district bent at
## exactly the same single point regardless of which of that
## district's real locations (up to a dozen per district — see
## CityLocationDefinition's own map_position spread) it was actually
## headed to or from. Each larger district now gets 1-3 EXTRA sub-
## junction nodes, hand-placed near real clusters of that district's
## own locations (e.g. "artisans_north" sits by the Locksmith's/
## Carpenter's Guild cluster, not just anywhere in Artisan's Quarter) —
## still "rough"/hand-eyeballed per the original request, just at a
## finer grain, so a walk to a location on one side of a big district
## no longer takes the exact same bend as a walk to somewhere on the
## opposite side of it. `merchant`/`morgenseite` were also nudged
## slightly to sit closer to their own districts' real location
## clusters rather than the district label's own position.
const WAYPOINTS := {
	"north_gate": Vector2(0.4067, 0.2262),
	"east_gate": Vector2(0.646, 0.2521),
	"water_gate": Vector2(0.285, 0.455),
	"south_gate": Vector2(0.5439, 0.7886),
	"bridge": Vector2(0.5263, 0.49),

	## The Precinct — central hub near the Chapel of Ulric/Reiniger's
	## cluster, plus a northern sub-junction near Magnus's Tower/North
	## Temple of Sigmar, between it and North Gate.
	"precinct": Vector2(0.45, 0.335),
	"precinct_north": Vector2(0.46, 0.285),

	## Black Rock — the castle/park hub, plus a sub-junction along the
	## park's own labyrinth paths toward The Precinct.
	"black_rock": Vector2(0.32, 0.375),
	"black_rock_park": Vector2(0.37, 0.30),

	## Artisan's Quarter — a big, spread-out district (Wandiene Rookery
	## up by the north wall down to the Worshipful Guild of Cutlers by
	## the river); the single old hub sat in the middle of that spread.
	## Now: a central hub, a northern sub-junction near the Locksmith's/
	## Carpenter's Guild cluster (closer to North Gate/East Gate), and a
	## southern one near Wizard's Way/Cutlers (closer to the harbor).
	"artisans": Vector2(0.60, 0.375),
	"artisans_north": Vector2(0.575, 0.28),
	"artisans_south": Vector2(0.665, 0.40),

	## Teubrücke, north bank (harbor buildings below Black Rock/The
	## Precinct/Artisan's Quarter) — a west sub-junction near the Kat
	## House/Dockers' Arms cluster, a mid one near the Hog Pit/
	## Strohmann Markt cluster, then the bridge's own north landing.
	##
	## Follow-up request ("fix the travel path vectoring on bridge...
	## make it run straight over the bridge. try not to path visibly
	## through the water"): bridge_north/bridge_south used to sit at
	## their own hand-eyeballed x (0.50 / 0.515), noticeably off the
	## bridge deck's own real x — pixel-sampling the actual map art
	## found the deck (the paved strip between its two railings) runs a
	## perfectly straight vertical line at x≈0.5263 all the way across
	## the river, exactly matching "bridge"'s own x below. The old,
	## slightly-off x's meant the north_gate/south_gate->bridge->
	## district walk visibly kinked onto the water on both approaches
	## instead of running straight down the deck. Both landings now
	## share "bridge"'s exact x — y unchanged — so the whole
	## bridge_north->bridge->bridge_south run is one straight line
	## directly down the real deck, never touching the water.
	"teubrucke_nw": Vector2(0.365, 0.47),
	"teubrucke_n_mid": Vector2(0.465, 0.415),
	"bridge_north": Vector2(0.5263, 0.455),

	## Teubrücke, south bank (harbor buildings below Marktplatz/Merchant
	## Quarter) — the bridge's own south landing, the original west hub
	## near the Red Moon Inn, and a new east sub-junction near Rugger's/
	## Grail Chapel.
	"bridge_south": Vector2(0.5263, 0.525),
	"teubrucke_west": Vector2(0.40, 0.555),
	"teubrucke_se": Vector2(0.56, 0.535),

	## Dawihafen — the original hub, plus a southern sub-junction near
	## Harataken Hold, closer to South Gate.
	"dawihafen": Vector2(0.36, 0.63),
	"dawihafen_south": Vector2(0.385, 0.70),

	## Marktplatz — the plaza hub near Theatre Variete, a southern
	## sub-junction by the temple cluster (High Temple of Sigmar/
	## Shallya/Verena), and an eastern one near Town Hall/Watchstation.
	"marktplatz": Vector2(0.505, 0.605),
	"marktplatz_temples": Vector2(0.515, 0.69),
	"marktplatz_east": Vector2(0.545, 0.655),

	## Merchant Quarter — hub nudged onto the real Wahlund's/Saint
	## Bastian's cluster (was sitting closer to Morgenseite), plus a
	## southern sub-junction near the Old Granary/Furlisdottir's.
	"merchant": Vector2(0.585, 0.61),
	"merchant_south": Vector2(0.605, 0.73),

	## Morgenseite — hub nudged onto the real Madame Beaumarteau's/
	## Emperor's Rest cluster, plus a southern sub-junction near Wings
	## of the Pegasus/Karstadt Estate/Bruner Palace.
	"morgenseite": Vector2(0.665, 0.645),
	"morgenseite_south": Vector2(0.70, 0.71),
}

## Undirected edges — pairs of WAYPOINTS keys. Follows the map's own
## visible road pattern: a spine down through The Precinct and over
## the bridge into Marktplatz/South Gate, side roads out to each other
## gate, and a riverside road linking Teubrücke (both banks) to Water
## Gate and Dawihafen. Deliberately keeps a few short loops (e.g.
## Artisan's Quarter's own north/south sub-junctions both reaching East
## Gate; Marktplatz having both a direct and a temple-cluster route to
## South Gate) rather than a single spanning tree — real Dijkstra then
## actually has a choice to make depending on which real location a
## walk starts/ends near, instead of every route through a district
## bending at the exact same single point.
const EDGES := [
	["north_gate", "precinct_north"],
	["precinct_north", "precinct"],
	["precinct", "black_rock_park"],
	["black_rock_park", "black_rock"],
	["black_rock", "water_gate"],
	["precinct", "artisans"],
	["precinct_north", "artisans_north"],
	["artisans_north", "artisans"],
	["artisans_north", "east_gate"],
	["artisans", "east_gate"],
	["artisans", "artisans_south"],
	["artisans_south", "teubrucke_n_mid"],
	["precinct", "bridge_north"],
	["black_rock", "teubrucke_nw"],
	["teubrucke_nw", "water_gate"],
	["teubrucke_nw", "teubrucke_n_mid"],
	["teubrucke_n_mid", "bridge_north"],
	["bridge_north", "bridge"],
	["bridge", "bridge_south"],
	["bridge_south", "teubrucke_west"],
	["bridge_south", "teubrucke_se"],
	["bridge_south", "marktplatz"],
	["teubrucke_se", "merchant"],
	## Follow-up request (water-crossing pathing review): the old edge
	## here to "water_gate" cut straight across the river to reach the
	## south bank from here — removed. The graph now has exactly one
	## legitimate river crossing (the bridge chain above), matching what
	## the map art itself shows.
	["teubrucke_west", "dawihafen"],
	["dawihafen", "dawihafen_south"],
	["dawihafen_south", "south_gate"],
	["marktplatz", "dawihafen"],
	["marktplatz", "south_gate"],
	["marktplatz", "marktplatz_temples"],
	["marktplatz_temples", "south_gate"],
	["marktplatz", "marktplatz_east"],
	["marktplatz_east", "merchant"],
	["marktplatz", "merchant"],
	["merchant", "merchant_south"],
	["merchant_south", "south_gate"],
	["merchant", "morgenseite"],
	["morgenseite", "morgenseite_south"],
	["morgenseite_south", "merchant_south"],
]

## Builds a full walking route (normalized positions, start and end
## included) from `from` to `to` — snaps onto the nearest waypoint at
## each end, runs Dijkstra across WAYPOINTS/EDGES between those two
## entry points, and returns the whole polyline in order. Falls back
## to a straight line if either endpoint can't reach the graph (never
## happens in practice — WAYPOINTS is never empty — but keeps this
## safe to call unconditionally).
static func route(from: Vector2, to: Vector2) -> Array:
	if WAYPOINTS.is_empty():
		return [from, to]
	var entry: String = _nearest_waypoint(from)
	var exit: String = _nearest_waypoint(to)
	var path_ids: Array = _shortest_path(entry, exit)
	## Follow-up request (denser waypoint graph): a walk starting or
	## ending exactly ON a waypoint's own position (e.g. from a gate
	## itself, now more likely with more waypoints packed closer
	## together) used to duplicate that point — `from`/`to` plus the
	## snapped entry/exit waypoint at the identical coordinate — which
	## drew a harmless but pointless zero-length dash segment. Skipped
	## by a tiny epsilon check instead of relying on exact equality, so
	## "close enough to be the same point" collapses too.
	const DEDUPE_EPSILON := 0.0005
	var result: Array = [from]
	for wp_id in path_ids:
		var wp_pos: Vector2 = WAYPOINTS[wp_id]
		if result[-1].distance_to(wp_pos) > DEDUPE_EPSILON:
			result.append(wp_pos)
	if result[-1].distance_to(to) > DEDUPE_EPSILON:
		result.append(to)
	return result

static func _nearest_waypoint(pos: Vector2) -> String:
	var best_id: String = WAYPOINTS.keys()[0]
	var best_dist: float = INF
	for wp_id in WAYPOINTS:
		var d: float = WAYPOINTS[wp_id].distance_to(pos)
		if d < best_dist:
			best_dist = d
			best_id = wp_id
	return best_id

## Plain Dijkstra over the small hand-authored graph above — WAYPOINTS
## never has more than a couple dozen entries, so there's no need for
## anything fancier.
static func _shortest_path(start_id: String, end_id: String) -> Array:
	if start_id == end_id:
		return [start_id]
	var adjacency: Dictionary = {}
	for wp_id in WAYPOINTS:
		adjacency[wp_id] = []
	for edge in EDGES:
		var a: String = edge[0]
		var b: String = edge[1]
		adjacency[a].append(b)
		adjacency[b].append(a)

	var dist: Dictionary = {}
	var prev: Dictionary = {}
	var visited: Dictionary = {}
	for wp_id in WAYPOINTS:
		dist[wp_id] = INF
	dist[start_id] = 0.0

	while true:
		var current: String = ""
		var current_dist: float = INF
		for wp_id in WAYPOINTS:
			if not visited.get(wp_id, false) and dist[wp_id] < current_dist:
				current = wp_id
				current_dist = dist[wp_id]
		if current == "":
			break
		if current == end_id:
			break
		visited[current] = true
		for neighbor in adjacency[current]:
			var w: float = WAYPOINTS[current].distance_to(WAYPOINTS[neighbor])
			var alt: float = current_dist + w
			if alt < dist[neighbor]:
				dist[neighbor] = alt
				prev[neighbor] = current

	if dist.get(end_id, INF) == INF:
		## No path found (graph is disconnected somehow) — just a
		## direct hop between the two nearest waypoints rather than
		## leaving the caller with nothing.
		return [start_id, end_id]

	var path: Array = [end_id]
	var node: String = end_id
	while node != start_id:
		node = prev[node]
		path.push_front(node)
	return path
