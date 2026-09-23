extends Resource
class_name CityLocationList
## New City Screen feature: the top-level resource a data file like
## data/maps/ubersreik_city_locations.tres actually saves as — just a
## flat array of every CityLocationDefinition for one city (both
## unlocked and still-locked/hidden ones; see CityLocationDefinition's
## own comment on the "all data now, most locked" scope). A thin
## wrapper rather than saving a bare Array directly, since a plain
## .tres file needs some [resource] script to attach to.

@export var locations: Array[CityLocationDefinition] = []
