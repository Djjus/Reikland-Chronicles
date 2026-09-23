extends Resource
class_name SocialEncounterDatabase

@export var encounters: Array[SocialEncounterDefinition] = []

func random_encounter() -> SocialEncounterDefinition:
	if encounters.is_empty():
		return null
	return encounters[randi() % encounters.size()]

func find_by_name(encounter_name: String) -> SocialEncounterDefinition:
	for e in encounters:
		if e.encounter_name == encounter_name:
			return e
	return null
