extends RefCounted
class_name TaskGenerator
## Per the request: generates a random "Task" — a lightweight,
## NPC-given mini-Quest — either "gather N of a specific trophy item"
## or "find a specific, rare social encounter." Original writing for
## every title/description here.

## Item -> {title, description-verb} for gather tasks. Deliberately
## drawn from this project's own real trophy items (see the last two
## passes' worth of additions) rather than inventing new ones just for
## tasks — a gather task always asks for something a real monster
## somewhere can actually drop.
const GATHER_ITEMS := [
	"Rat Pelt", "Boar Tusks", "Wolf Pelt", "Bear Pelt", "Spider Fang",
	"Snake Skin", "Dog Pelt", "Greenskin Ear", "Skaven Teeth", "Undead Bones",
]

## Which social encounters can be the target of a "find" task — pulled
## from the real database at generation time, not hardcoded, so this
## automatically picks up any encounter added in the future.
static func random_task(npc_role: String) -> Dictionary:
	## Roughly 2-in-3 gather, 1-in-3 find-encounter — gather tasks are
	## simpler and more reliably completable (you control when to go
	## hunting), so weighting toward them keeps the average task
	## genuinely finishable in a reasonable session.
	var use_gather := randf() < 0.67
	if use_gather or GameData.social_encounter_db == null or GameData.social_encounter_db.encounters.is_empty():
		return _build_gather_task(npc_role)
	return _build_find_encounter_task(npc_role)

static func _build_gather_task(npc_role: String) -> Dictionary:
	var item: String = GATHER_ITEMS[randi() % GATHER_ITEMS.size()]
	var count: int = 2 + randi() % 3   ## 2-4
	var task_id := "gather_%s_%d" % [item.to_snake_case(), Time.get_ticks_msec()]
	var title := "Wanted: %s" % item
	var description := "%s asks you to bring back %d %s. Nothing fancy — just proof you've been earning your keep out there." % [
		_role_phrase(npc_role), count, item if count == 1 else (item + "s" if not item.ends_with("s") else item)
	]
	return {
		"task_id": task_id, "title": title, "description": description,
		"task_type": "gather", "target_key": item, "target_count": count,
	}

static func _build_find_encounter_task(npc_role: String) -> Dictionary:
	var enc: SocialEncounterDefinition = GameData.social_encounter_db.random_encounter()
	var task_id := "find_%s_%d" % [enc.encounter_name.to_snake_case(), Time.get_ticks_msec()]
	var title := "Rumour: %s" % enc.encounter_name
	var description := "%s has heard whispers of something out on the roads — keep your eyes open, and don't be surprised if it finds you before you find it." % _role_phrase(npc_role)
	return {
		"task_id": task_id, "title": title, "description": description,
		"task_type": "find_encounter", "target_key": enc.encounter_name, "target_count": 1,
	}

static func _role_phrase(role: String) -> String:
	match role:
		"shopkeeper":
			return "The merchant"
		"priest":
			return "The Sister"
		"trainer":
			return "The old hermit"
		_:
			return "The traveller"
