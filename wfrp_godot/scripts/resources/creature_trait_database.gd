extends Resource
class_name CreatureTraitDatabase

@export var creature_traits: Array[CreatureTraitDefinition] = []

func find_by_name(trait_name: String) -> CreatureTraitDefinition:
	for t in creature_traits:
		if t.trait_name == trait_name:
			return t
	## Same "(Rating)"/"(Target)"/"(Type)" qualifier pattern as
	## TalentDatabase — "Bite (5)", "Fear (2)", "Hatred (Orcs)" etc.
	## store the full string on the monster, but the base name is what's
	## in this database.
	var paren := trait_name.find(" (")
	if paren != -1:
		var base_name := trait_name.substr(0, paren)
		for t in creature_traits:
			if t.trait_name == base_name:
				return t
	return null
