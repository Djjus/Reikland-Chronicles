extends Resource
class_name SkillDefinition
## A single skill. "Grouped" skills (e.g. Melee, Lore, Trade) represent a
## family where each specialisation is advanced separately.

@export var skill_name: String = ""
@export var linked_characteristic: String = "weapon_skill" # key into CharacteristicSet
@export var is_advanced: bool = false   # Basic skills can be tested untrained; Advanced cannot.
@export var is_grouped: bool = false    # e.g. "Melee (Basic)", "Lore (Something)"
@export var group_options: Array[String] = [] # possible specialisations if grouped
@export var summary: String = ""        # short original description

func display_name(specialisation: String = "") -> String:
	if is_grouped and specialisation != "":
		return "%s (%s)" % [skill_name, specialisation]
	return skill_name
