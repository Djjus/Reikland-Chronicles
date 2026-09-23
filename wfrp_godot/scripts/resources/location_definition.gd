extends Resource
class_name LocationDefinition
## One travelable location on the World Map — a city marked with the
## 'Z' tile in a LocalMapDefinition whose is_world_map flag is true.
## Phase 2 of the world-map plan: selecting one of these starts a
## multi-day journey (see Overworld._begin_travel) rather than an
## ordinary local-map interaction.

## Display name, e.g. "Altdorf". Matches the name used in map_rows'
## own placement, but kept here explicitly rather than derived, since
## multiple LocationDefinitions could theoretically share a tile
## layout in different World Map revisions later.
@export var location_name: String = ""

## World Map tile coordinate this location's own 'Z' marker sits at.
@export var world_tile: Vector2i = Vector2i(-1, -1)

## Path to this location's own LocalMapDefinition — the actual town/
## city map the player arrives at. Empty string means "not yet built"
## (per the request's own phased approach: only Giessingen has a real
## local map so far; other Empire cities are travelable destinations
## on the World Map already, ready for their own local maps later).
@export var local_map_path: String = ""

## True for the one location representing "home" in some sense
## (currently just Giessingen) — not yet used for anything mechanical,
## reserved for later (e.g. a "return home" shortcut).
@export var is_starting_location: bool = false

## New City Screen feature: path to this location's own City Screen
## scene (an image-map, zoomable, marker-based screen — see
## scripts/game/city_screen.gd), for locations too large/detailed for
## the ordinary tile-grid LocalMapDefinition system local_map_path
## above points at. Checked FIRST in Overworld._offer_enter_location()
## — empty means "no City Screen, fall back to local_map_path exactly
## as before" — so this is purely additive and doesn't touch the
## existing Giessingen/Gotheim tile-grid flow at all.
@export var city_screen_scene_path: String = ""

## New City Screen feature: which city's own location/position data
## this maps to (e.g. "ubersreik" — matches CityLocationDefinition
## data file naming and GameState.city_player_positions' own keys).
## Only meaningful when city_screen_scene_path is set.
@export var city_id: String = ""
