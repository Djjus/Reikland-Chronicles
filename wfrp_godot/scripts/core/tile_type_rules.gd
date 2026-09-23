extends RefCounted
class_name TileTypeRules
## Per the request: which factions can spawn on which kind of
## overworld tile — a real classification layered on top of the
## existing per-area Difficulty Tier and monster_pool/habitat system,
## not a replacement for either. An area with no explicit tile_type
## defaults to "countryside" (see DifficultyAreaDefinition), matching
## open, unremarkable terrain.

const FACTIONS_BY_TILE_TYPE := {
	"countryside": ["Beast", "Human", "Cultist"],
	"village": ["Human", "Cultist"],
	"city": ["Skaven", "Cultist"],
	"woods": ["Greenskin", "Beast", "Beastmen", "Cultist", "Chaos"],
	"mountains": ["Greenskin", "Beast", "Chaos"],
	"ruins": ["Undead", "Cultist", "Chaos"],
	"caves": ["Undead", "Beast"],
}

## Every recognised tile type — used to validate area authoring rather
## than silently accepting a typo'd tile_type that would match nothing.
static func is_valid_tile_type(tile_type: String) -> bool:
	return FACTIONS_BY_TILE_TYPE.has(tile_type)

static func allowed_factions_for(tile_type: String) -> Array:
	return FACTIONS_BY_TILE_TYPE.get(tile_type, FACTIONS_BY_TILE_TYPE["countryside"])
