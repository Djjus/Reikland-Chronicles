extends Resource
class_name ItemDatabase

@export var items: Array[ItemDefinition] = []

func find_by_name(name: String) -> ItemDefinition:
	for i in items:
		if i.item_name == name:
			return i
	return null

func by_availability(availability: String) -> Array[ItemDefinition]:
	var result: Array[ItemDefinition] = []
	for i in items:
		if i.availability == availability:
			result.append(i)
	return result
