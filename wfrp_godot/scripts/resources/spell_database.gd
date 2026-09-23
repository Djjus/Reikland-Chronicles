extends Resource
class_name SpellDatabase

@export var spells: Array[SpellDefinition] = []

func find_by_name(name: String) -> SpellDefinition:
	for s in spells:
		if s.spell_name == name:
			return s
	return null

func find_by_type(spell_type: String) -> Array[SpellDefinition]:
	var result: Array[SpellDefinition] = []
	for s in spells:
		if s.spell_type == spell_type:
			result.append(s)
	return result
