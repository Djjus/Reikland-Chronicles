extends Resource
class_name QuestNPCMapMarker
## Per the request: the physical map-side half of the quest-NPC
## system — a specific tile on a specific LocalMapDefinition that,
## when the player interacts with it, opens ScriptedNPCEncounter for
## the named NPC. This is what actually connects "the place" (the
## hand-authored local map) to "the story" (QuestDefinition/
## QuestNPCDefinition) — without this, a quest's own NPC data has no
## way to be reached by simply playing the game.

@export var tile: Vector2i = Vector2i(-1, -1)
@export var quest_id: String = ""
@export var npc_id: String = ""
