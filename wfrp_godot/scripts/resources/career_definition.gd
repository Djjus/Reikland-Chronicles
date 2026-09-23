extends Resource
class_name CareerDefinition
## A career/"class" made of up to four sequential CareerLevel tiers.

@export var career_name: String = ""
@export var career_class: String = "Warrior" # Academic, Burgher, Courtier, Peasant, Ranger, Riverfolk, Rogue, Warrior
## Which Races can take this career, per the book's own list printed
## under each career's name (e.g. "Physician: Dwarf, Halfling, High
## Elf, Human"). Empty means unrestricted — used for the 48 careers
## whose skill/talent/trapping data hasn't been individually audited
## against the book yet (see the Warrior/Academic class audits), so
## this project doesn't invent a restriction it hasn't actually
## verified.
@export var valid_races: Array[String] = []
@export var levels: Array[CareerLevel] = []
@export var summary: String = ""

func get_level(tier: int) -> CareerLevel:
	for lvl in levels:
		if lvl.tier == tier:
			return lvl
	return null
