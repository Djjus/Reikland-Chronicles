extends Resource
class_name DungeonLayoutParams
## Tunable knobs for DungeonGenerator, per the Dungeon Encounter Screen
## spec (see the project doc "Dungeon Encounter Screen Spec v1" for the
## full design this implements). Kept separate from DungeonThemeDefinition
## so a future dungeon can reuse the same theme (art/monsters) with a
## different layout, or the same layout shape with a different theme.
##
## The one floor shipped so far (the Sewer) always uses exactly
## branch_count=2, matching the request's own fixed shape: an entrance,
## one T-junction, two branches, each ending in one large room. Randomness
## lives in HOW each branch bends and how long it runs (see
## DungeonGenerator._carve_branch), not in the topology itself.

## How many branches fan out from the single T-junction. The current
## Sewer preset always uses 2 (matching the request precisely); kept as a
## real parameter rather than a hardcoded constant so a later, bigger
## floor can ask for 3+ without new generator code.
@export_range(2, 4) var branch_count: int = 2

## Random length range (inclusive) of the short entry corridor, walked
## straight from the entrance to the T-junction.
@export var entry_corridor_length_range: Vector2i = Vector2i(2, 4)

## Random length range (inclusive) of each branch corridor, walked from
## the T-junction to that branch's own room door.
@export var branch_corridor_length_range: Vector2i = Vector2i(4, 8)

## Per-step chance a straight run bends into a corner instead of
## continuing straight, while carving a branch. This is where the "real
## random, not pregen" requirement actually lives — see DungeonGenerator.
@export_range(0.0, 1.0) var turn_chance: float = 0.35

## Each large room's width/height (independently) is drawn from this
## range — square-ish rooms, not a fixed size every time.
@export var room_size_range: Vector2i = Vector2i(6, 8)
