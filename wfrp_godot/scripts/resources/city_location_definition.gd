extends Resource
class_name CityLocationDefinition
## New City Screen feature: one point of interest on an in-town map
## (Ubersreik, to start with — see data/maps/ubersreik_city_locations.tres).
## Deliberately NOT the same shape as LocationDefinition (a World Map
## travel destination) — a city location isn't a tile on a walkable
## grid, it's a normalized position on a big background map image, so
## it needs its own fields (map_position instead of world_tile).
##
## Per the request's own chosen scope ("All 71 now, only 4 unlocked"):
## every numbered location from the source map's legend gets an entry
## here up front, but most start locked (unlocked = false) — hidden,
## with no marker and not enterable — so later "discovering" a
## location is just flipping this one flag, with no further data
## entry needed at that point.

## The source map legend's own number (1-71) — kept even though the
## in-game UI never shows raw numbers (per the request: "corresponding
## makers markers (not numbers)"), purely so this data can always be
## cross-checked back against the original Gamemaster map if needed.
@export var location_id: int = 0

## Display name, e.g. "The Red Moon Inn".
@export var location_name: String = ""

## Which named district of the town this falls in (e.g. "Teubrücke",
## "Marktplatz") — not yet shown anywhere in the UI, reserved for a
## later district-grouped legend or travel-time flavour text.
@export var district: String = ""

## Normalized position on the background map image — (0,0) is the
## image's own top-left corner, (1,1) its bottom-right. Kept
## resolution-independent on purpose: CityMapView multiplies this by
## whatever pixel size it's actually drawing the background texture
## at, so the same data works at any zoom level or (if the map art is
## ever swapped for a higher-res version) any source resolution.
@export var map_position: Vector2 = Vector2.ZERO

## False for every location the party hasn't discovered yet — per the
## request's own spec, only 4 locations start true (South Gate, The
## Red Moon Inn, The High Temple of Sigmar, Watch Barracks). A locked
## location draws no marker and isn't enterable/travelable, exactly
## like the source map's numbered legend being invisible on the
## "clean" background map handed to the player.
@export var unlocked: bool = false

## Broad category, used to vary the marker icon/colour so the legend
## and map read at a glance (a gate looks different from a tavern).
## One of: "gate", "tavern", "guild", "shop", "temple", "landmark",
## "watch", "residence", "castle".
@export var category: String = ""
