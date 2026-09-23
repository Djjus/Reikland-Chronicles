extends Resource
class_name QuestMonsterMapMarker
## The monster-side counterpart to QuestNPCMapMarker — a specific tile
## that, when the player interacts with it, launches a real combat
## encounter against a specific QuestMonsterDefinition (reading its
## own genuinely-current Wounds/healing state via
## Character.setup_quest_monster_encounter(), exactly as already
## proven end-to-end in earlier work).

@export var tile: Vector2i = Vector2i(-1, -1)
@export var quest_id: String = ""
@export var monster_id: String = ""
