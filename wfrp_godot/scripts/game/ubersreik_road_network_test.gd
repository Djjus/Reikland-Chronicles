extends RefCounted
class_name UbersreikRoadNetworkTest
## Regression/functional test for the follow-up request ("review the
## Travel vector pathing again and improve it significantly, make sure
## that the character never crosses water directly or takes
## unnecessarily long paths").
##
## The actual "does this line cross the river" verification was done
## offline against the real map art (a connected-component flood-fill
## from a known river pixel, run in Python/PIL/scipy — GDScript has no
## equivalent pixel-analysis tooling available at runtime) — see this
## file's sibling doc in the project for the full methodology. What
## CAN run permanently in-engine is the structural invariant that
## analysis proved out: the map's river separates the city into
## exactly two banks, and the ONLY legitimate way across is the real
## bridge (bridge_north -> bridge -> bridge_south). This test encodes
## that as a hand-verified bank partition of every WAYPOINTS entry
## (cross-checked against the same pixel analysis) and asserts no
## EDGE ever joins two different-bank waypoints except that one
## sanctioned chain — so if a future edit ever reintroduces a second
## "ford" (the exact bug this follow-up fixed, via the old water_gate
## south-bank edge), this test catches it immediately without needing
## the map art at all. It also sanity-checks route length (the
## "unnecessarily long paths" half of the request) against a spread of
## real cross-district journeys.

## Hand-verified against the pixel-sampled river mask: which side of
## the Teufel every waypoint sits on. "bridge" itself is the neutral
## midpoint of the one sanctioned crossing.
const NORTH_BANK := [
	"north_gate", "east_gate", "water_gate", "precinct", "precinct_north",
	"black_rock", "black_rock_park", "artisans", "artisans_north",
	"artisans_south", "teubrucke_nw", "teubrucke_n_mid", "bridge_north",
]
const SOUTH_BANK := [
	"south_gate", "bridge_south", "teubrucke_west", "teubrucke_se",
	"dawihafen", "dawihafen_south", "marktplatz", "marktplatz_temples",
	"marktplatz_east", "merchant", "merchant_south", "morgenseite",
	"morgenseite_south",
]
## The one sanctioned river-crossing chain — any edge touching "bridge"
## itself, or directly joining bridge_north/bridge_south to their own
## bank, is exempt from the "same bank only" rule below.
const BRIDGE_CHAIN := [
	["bridge_north", "bridge"],
	["bridge", "bridge_south"],
]

static func run_test() -> bool:
	var checks: Array = []

	## Every WAYPOINTS key must be accounted for in exactly one bank —
	## otherwise the invariant below is silently incomplete.
	var all_waypoints: Array = UbersreikRoadNetwork.WAYPOINTS.keys()
	var banked: Array = NORTH_BANK + SOUTH_BANK + ["bridge"]
	var missing: Array = []
	for wp_id in all_waypoints:
		if not banked.has(wp_id):
			missing.append(wp_id)
	checks.append(["every waypoint is assigned to a bank (or is the bridge midpoint) — unassigned: %s" % [missing], missing.is_empty()])
	var extra: Array = []
	for wp_id in banked:
		if not all_waypoints.has(wp_id):
			extra.append(wp_id)
	checks.append(["bank lists don't reference any waypoint that no longer exists — stale: %s" % [extra], extra.is_empty()])

	## The core invariant: no edge crosses banks except the sanctioned
	## bridge chain. This is exactly the shape of bug the old
	## ["teubrucke_west", "water_gate"] edge was — a second illegitimate
	## "ford" alongside the real bridge.
	var illegitimate_crossings: Array = []
	for edge in UbersreikRoadNetwork.EDGES:
		var a: String = edge[0]
		var b: String = edge[1]
		if BRIDGE_CHAIN.has([a, b]) or BRIDGE_CHAIN.has([b, a]):
			continue
		var a_is_north: bool = NORTH_BANK.has(a)
		var a_is_south: bool = SOUTH_BANK.has(a)
		var b_is_north: bool = NORTH_BANK.has(b)
		var b_is_south: bool = SOUTH_BANK.has(b)
		if (a_is_north and b_is_south) or (a_is_south and b_is_north):
			illegitimate_crossings.append("%s <-> %s" % [a, b])
	checks.append(["no EDGE joins opposite banks except the real bridge chain — found: %s" % [illegitimate_crossings], illegitimate_crossings.is_empty()])

	## water_gate specifically: the root cause of the bug this follow-up
	## fixed. It must sit on dry land (north bank, per the pixel
	## analysis) and must NOT be reachable from the south bank at all
	## any more — any south-bank neighbor there would recreate the
	## exact "wall crosses the open river" issue the map art shows.
	var water_gate_neighbors: Array = []
	for edge in UbersreikRoadNetwork.EDGES:
		if edge[0] == "water_gate":
			water_gate_neighbors.append(edge[1])
		elif edge[1] == "water_gate":
			water_gate_neighbors.append(edge[0])
	var water_gate_has_south_neighbor := false
	for n in water_gate_neighbors:
		if SOUTH_BANK.has(n):
			water_gate_has_south_neighbor = true
	checks.append(["water_gate has no south-bank neighbor (neighbors: %s)" % [water_gate_neighbors], not water_gate_has_south_neighbor])
	checks.append(["water_gate itself is classified north bank", NORTH_BANK.has("water_gate")])

	## "unnecessarily long paths" sanity check: a real route between two
	## points should never balloon far past the straight-line distance
	## between them just because of graph quirks. A generous ceiling
	## (3x) still catches a genuinely broken/disconnected-feeling route
	## while allowing for the real, expected detour every cross-river
	## journey now takes to reach the one legitimate bridge.
	var sample_pairs := [
		["north_gate", "south_gate"], ["east_gate", "water_gate"],
		["black_rock", "morgenseite"], ["artisans", "dawihafen"],
		["teubrucke_nw", "teubrucke_se"], ["black_rock", "south_gate"],
	]
	var long_routes: Array = []
	for pair in sample_pairs:
		var from_pos: Vector2 = UbersreikRoadNetwork.WAYPOINTS[pair[0]]
		var to_pos: Vector2 = UbersreikRoadNetwork.WAYPOINTS[pair[1]]
		var route: Array = UbersreikRoadNetwork.route(from_pos, to_pos)
		var route_len := 0.0
		for i in range(route.size() - 1):
			route_len += route[i].distance_to(route[i + 1])
		var straight: float = from_pos.distance_to(to_pos)
		var ratio: float = route_len / straight if straight > 0.0 else 1.0
		if ratio > 3.0:
			long_routes.append("%s -> %s (ratio %.2f)" % [pair[0], pair[1], ratio])
	checks.append(["no sampled route is unreasonably long vs straight-line distance — offenders: %s" % [long_routes], long_routes.is_empty()])

	## route() itself, for a real cross-river pair, must actually pass
	## through the bridge chain (not just "not cross water" in theory —
	## confirms the fix is live in the actual pathing function callers
	## use, not just in the static data).
	var cross_route: Array = UbersreikRoadNetwork.route(UbersreikRoadNetwork.WAYPOINTS["black_rock"], UbersreikRoadNetwork.WAYPOINTS["dawihafen"])
	var passes_through_bridge := false
	for pos in cross_route:
		if pos.distance_to(UbersreikRoadNetwork.WAYPOINTS["bridge"]) < 0.001:
			passes_through_bridge = true
	checks.append(["a real north-bank -> south-bank route() call actually passes through the bridge waypoint", passes_through_bridge])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Ubersreik Road Network): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
