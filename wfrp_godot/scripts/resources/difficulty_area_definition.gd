extends Resource
class_name DifficultyAreaDefinition
## One named sub-area of a map with its own Enemy/Monster Difficulty
## Tier, per the request: "This will apply by Area (entire map or sub
## areas on the same map)". A map's own `default_difficulty_tier`
## covers everywhere NOT inside one of these; areas are rectangular
## tile regions so a map can be carved into a few named zones (e.g. a
## safer starting village vs. a harder outlying forest) without
## needing per-tile authoring.
##
## Deliberately just a flat list checked in order, first match wins —
## the current map (see Overworld.gd) ships with an empty list and a
## Tier 0 default, per the request to "keep all enemies on the current
## map Tier 0 for now." This is the template other maps/areas will use
## once the world is built out further.

@export var area_name: String = ""
@export_range(0, 5) var tier: int = 0
## Optional: restricts field encounters within these bounds to only
## these monster names (falls back to the map's full random pool if
## empty, or if none of the named monsters actually exist in the
## database). Lets a themed sub-area — a goblin fort, a bear's cave —
## actually spawn what its name promises, not just decoration with the
## same generic random encounter table as everywhere else.
@export var monster_pool: Array[String] = []
## Location-appropriate spawning, per the request: when set, a random
## encounter here prefers monsters whose own MonsterDefinition.
## habitat_tags includes this value (e.g. "forest", "cave", "open") —
## checked alongside monster_pool, not instead of it; an area can use
## either, both, or neither. Empty means "no habitat preference,"
## matching every monster equally as far as this specific filter goes.
@export var habitat: String = ""
## Tile-space rectangle (not pixels) — e.g. Rect2i(10, 10, 20, 15)
## covers tiles x=10..29, y=10..24. An empty/zero-size Rect2i is
## treated as "invalid" and never matches anything, so a
## half-configured area can't accidentally swallow the whole map.
@export var bounds: Rect2i = Rect2i()

## Per the follow-up request: which kind of terrain this area
## represents, for the new faction-by-location spawn rules (see
## TileTypeRules) — "countryside", "village", "city", "woods",
## "mountains", "ruins", or "caves". Defaults to "countryside", the
## same default any tile outside every defined area also uses.
@export var tile_type: String = "countryside"

## Per the follow-up request: a Safe Area is a modifier that disables
## field-encounter spawning entirely within these bounds, independent
## of tier/monster_pool/tile_type — the starting village uses this so
## it stays genuinely safe to walk around in, not just statistically
## unlikely to get ambushed.
@export var is_safe_area: bool = false

func contains_tile(tile: Vector2i) -> bool:
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return false
	return bounds.has_point(tile)
