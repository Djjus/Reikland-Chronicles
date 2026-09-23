extends Resource
class_name ProvinceDefinition
## A named province/region on the World Map, per the request — used
## both for the province name label shown on the map (positioned
## deliberately clear of any city's own label) and for the Lore
## radial-menu button's own lookup (right-clicking empty ground within
## a province's bounds shows that province's own lore).

@export var province_name: String = ""

## Where the province's own name label is drawn — deliberately a
## separate field from the bounds' own center, since the request
## specifically calls out avoiding overlap with city labels; the
## label position is hand-placed per province rather than derived.
@export var label_tile: Vector2i = Vector2i(-1, -1)

## The province's own rectangular bounds on the World Map grid, used
## to determine which province a given right-clicked tile belongs to.
@export var bounds: Rect2i = Rect2i()

## A few sentences of real flavor text — Lore button content.
@export var summary: String = ""
