extends Resource
class_name SkillDatabase
## A flat list of SkillDefinition resources, loaded from one .tres file so
## the whole skill list can be bulk-edited without hunting through folders.

@export var skills: Array[SkillDefinition] = []

func find_by_name(skill_name: String) -> SkillDefinition:
	for s in skills:
		if s.skill_name == skill_name:
			return s
	return null
