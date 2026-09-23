extends Resource
class_name LocalMapDefinition
## Phase 1 of the world-map plan: everything that used to be hardcoded
## directly in Overworld.gd (the map grid, its difficulty/encounter
## areas, and the one location-specific special tile the Village
## Elder quest chain needs) now lives in a swappable Resource instead.
## Overworld.gd loads one of these at _ready() rather than having the
## village permanently wired into its own script.
##
## This step is deliberately behavior-preserving: the village becomes
## the first *defined* LocalMapDefinition rather than the only
## possible one, but nothing about how it plays changes. NPC
## positions, the player's own start tile, and encounter markers all
## continue to be derived from map_rows itself (scanning for '@', 'N',
## 'H', 'S', 'Y') exactly as before — they were never separately
## hardcoded to begin with, so they didn't need their own fields here.
##
## Future local maps (a town, a ruin, a stretch of the World Map
## itself at a different scale) are simply additional
## LocalMapDefinition resources following this same shape.

## Human-readable identifier, e.g. "Giessingen Village" — not yet
## shown anywhere in the UI, but useful for save data and debugging
## once multiple locations exist.
@export var map_name: String = ""

## The map grid itself — each string is one row, each character maps
## through Overworld.TILE_ATLAS (a shared, global tile palette every
## local map draws from, not duplicated per-map here).
@export var map_rows: Array[String] = []

## Encounter/difficulty zones for this specific map, per
## DifficultyAreaDefinition's own existing shape (tier, monster pool,
## habitat, tile_type, bounds, is_safe_area).
@export var difficulty_areas: Array[DifficultyAreaDefinition] = []

## The Village Elder's own tile — Vector2i(-1, -1) for any map that
## doesn't have this NPC (i.e. every map except the starting village,
## for now). Kept as an explicit field rather than a map_rows
## character since the Elder quest chain is specifically tied to this
## one NPC, not a generic spawn type other locations would reuse.
@export var elder_tile: Vector2i = Vector2i(-1, -1)

## Per the request: the local map's own exit point back to the World
## Map — a plain, ordinary-looking tile (no special marker character
## needed in map_rows itself) that triggers the return-to-World-Map
## offer simply by the player standing on it, rather than needing to
## be clicked. Vector2i(-1, -1) means this map has no such exit (the
## World Map itself, for instance).
@export var world_map_exit_tile: Vector2i = Vector2i(-1, -1)

## Per the request: a completely redone, simplified return-to-World-
## Map spawn position for this local map — a fixed, explicit tile set
## directly on the map data itself, with zero dynamic computation
## involved (no adjacent-tile search, no session-state lookup, no
## reverse-searching the World Map's own location list). Whatever
## tile is set here is exactly where the player lands, every time,
## with nothing else able to interfere. Vector2i(-1, -1) means this
## map has no local exit and should fall back to the World Map's own
## default spawn.
@export var world_map_return_tile: Vector2i = Vector2i(-1, -1)

## Per the request: each map's own default Enemy/Monster Difficulty
## Tier (0-5) — was previously a fixed Overworld.gd scene export
## shared by every map, which didn't make sense once the World Map
## needed its own, different tier from Giessingen's.
@export_range(0, 5) var default_difficulty_tier: int = 0

## Per the request: an explicit default spawn position, independent
## of the '@' character's own visual appearance (which renders as the
## dirt/mud Path sprite — fine for an ordinary village centre, but
## wrong sitting next to a World Map city marker on open grass).
## Vector2i(-1, -1) means "use the '@' character scan as before,"
## keeping every existing map's own behavior unchanged unless this is
## explicitly set.
@export var default_spawn_tile: Vector2i = Vector2i(-1, -1)

## Per Phase 2 of the world-map plan: true for the one World Map
## itself (a much larger-scale map covering the Empire), false for
## every ordinary local map (a village, a town). When true, Overworld
## treats 'Z' tiles specially — stepping onto one starts a multi-day
## travel confirmation (see Overworld._begin_travel) instead of an
## ordinary interaction, and `locations` below is read to know which
## LocalMapDefinition to load on arrival.
@export var is_world_map: bool = false
@export var locations: Array[LocationDefinition] = []

## Per the light-source request: true for a map that's dark regardless
## of the in-game clock — an underground cave, a ruin's interior (to be
## added later) — so a carried light source (Lantern/Candle/etc, held
## in Character.equipped_weapon/equipped_offhand — see
## Character.get_equipped_light_item()) is mechanically active there
## even at high noon. False (the default) means this map follows the
## ordinary day/night darkness curve instead — see
## Overworld._light_source_effective().
@export var is_dark_location: bool = false

## Miles-per-day equivalent for travel-day calculation on the World
## Map specifically — travel days = ceil(tile distance / this value).
## Only meaningful when is_world_map is true.
@export var world_map_tiles_per_day: float = 6.0

## Per the request: each map can set its own default camera zoom —
## the World Map needs to show far more of the grid at once than an
## ordinary local map does.
@export var default_camera_zoom: float = 0.9375

## Per the request: named provinces (World Map only), each a simple
## rectangular region — used both for the province name labels shown
## on the map and for the Lore radial-menu button's own lookup.
@export var provinces: Array[ProvinceDefinition] = []

## Per the request: what actually connects this local map to a real
## QuestDefinition — specific tiles that open a scripted NPC encounter
## or a scripted monster fight when the player interacts with them.
## Empty on every local map that isn't part of an imported adventure.
@export var quest_npc_markers: Array[QuestNPCMapMarker] = []
@export var quest_monster_markers: Array[QuestMonsterMapMarker] = []

## Per the request: if set, entering this map for the first time
## automatically starts the named quest — matches "entering Gotheim"
## itself being the trigger, not requiring the player to have already
## talked to someone first. Empty means no auto-start (the ordinary
## case for every map that isn't a quest's own home base).
@export var auto_start_quest_id: String = ""

## Per the request: whether random combat/social encounters can occur
## at all while on this map — true for every ordinary map. Set false
## for a story-critical location like Gotheim, where every fight is
## meant to be a deliberate quest beat (the villagers, the
## Jabberslythe) rather than a random roll competing with them.
@export var allow_random_encounters: bool = true

## Per the request: the tile of this map's own Party Companion Maker
## NPC, if it has one — lets the player recruit up to the real 4-member
## party cap via the full Character Creator, the same wizard used to
## make the very first character. Vector2i(-1, -1) means this map has
## no such NPC.
@export var companion_maker_tile: Vector2i = Vector2i(-1, -1)

## Per the request: optional per-tile ground elevation — prep for a
## future stairs mechanic. Keyed by tile coordinate (Vector2i), value
## is the elevation index (0 = the base ground level, same as any tile
## that doesn't appear here at all — so every existing map needs zero
## changes to keep rendering exactly as before). Overworld.gd creates
## one real TileMapLayer per distinct elevation actually used on a
## given map (see _build_map()/ground_layers) rather than a fixed
## number, so a map can use as many or as few elevation levels as it
## actually needs. Only affects which of those layers a GROUND tile is
## drawn on — water and buildings/walls always route to their own
## single shared layer regardless of the elevation value here (see
## WATER_CHARS/BUILDING_CHARS in overworld.gd).
@export var elevation_overrides: Dictionary = {}

