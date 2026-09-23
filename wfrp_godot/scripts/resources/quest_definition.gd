extends Resource
class_name QuestDefinition
## Per the request: the container an adventure-import pipeline would
## populate one of per book adventure — a stable quest_id (used
## directly with Character's own existing generic quests: Array
## system — find_quest()/set_quest_status(), already proven by the
## Village Elder's own quest chain), a display title, and the list of
## scripted NPCs that quest contains.

@export var quest_id: String = ""
@export var quest_title: String = ""
@export_multiline var quest_summary: String = ""
@export var npcs: Array[QuestNPCDefinition] = []
## Per the request: a generic ticking-clock system — multiple
## independent timed events, each on its own schedule, each
## individually cancelable (see QuestTimelineEvent's own
## cancel_if_npc_id).
@export var timeline_events: Array[QuestTimelineEvent] = []
## Per the request: monsters with a scripted, non-default starting
## state — a real spawn-override rather than always full health.
@export var monsters: Array[QuestMonsterDefinition] = []
## Per the request: multi-criteria win/loss evaluation — every group
## here must be met (a plain AND across groups) for the quest as a
## whole to count as won; each group's own required_count controls
## how it combines its own checks internally.
@export var win_conditions: Array[QuestWinCondition] = []

func find_monster(monster_id: String) -> QuestMonsterDefinition:
	for m in monsters:
		if m.monster_id == monster_id:
			return m
	return null

func find_timeline_event(event_id: String) -> QuestTimelineEvent:
	for e in timeline_events:
		if e.event_id == event_id:
			return e
	return null

func find_npc(npc_id: String) -> QuestNPCDefinition:
	for n in npcs:
		if n.npc_id == npc_id:
			return n
	return null
