extends Resource
class_name CreatureTemplateDatabase
## Holds every CreatureTemplateDefinition — see that class's own doc
## comment for what a template is and why this database is intentionally
## not yet registered in GameData.

@export var templates: Array[CreatureTemplateDefinition] = []

func find_by_name(name: String) -> CreatureTemplateDefinition:
	for t in templates:
		if t.template_name == name:
			return t
	return null
