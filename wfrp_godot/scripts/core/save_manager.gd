extends RefCounted
class_name SaveManager
## Handles save/load file I/O. Saves are plain JSON files under
## user://saves/, one per slot, so they're easy to inspect/debug and
## robust to future data changes (see Character.to_save_dict for why
## race/career are stored as names rather than embedded resources).
##
## Per the request: the player's own last active map (and, if it was
## the World Map, their exact position there) is now saved and
## restored too — see Character.to_save_dict()/from_save_dict() for
## the actual fields, and Overworld._build_map() for how a restored
## World Map position is used as the spawn point. Local-map position
## still isn't saved (loading a local map always drops the player at
## its own spawn point) — that remains a real scope cut, not an
## oversight.

const SAVE_DIR := "user://saves"
const SLOT_COUNT := 3

static func _slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]

static func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

static func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))

## Saves the full party (`characters`, 1-4 members) plus which one is
## currently active. Returns true on success. Per the request: up to
## 4 controllable party members — the save format is now
## {"party": [...], "active_party_index": N, "saved_at": ...} rather
## than one flat character dict.
## `dismissed`: party members dismissed via the Character Menu's Group
## tab (see GameState.dismissed_companions) — saved alongside the party
## so they're still there to re-recruit at the Giessingen companion
## maker after a Continue/Switch Character, not just for the rest of
## the current session.
static func save_game(characters: Array[Character], active_index: int, slot: int, dismissed: Array[Character] = []) -> bool:
	_ensure_dir()
	var party_data: Array = []
	for c in characters:
		party_data.append(c.to_save_dict())
	var dismissed_data: Array = []
	for c in dismissed:
		dismissed_data.append(c.to_save_dict())
	var data := {
		"party": party_data,
		"active_party_index": active_index,
		"dismissed_companions": dismissed_data,
		"saved_at": Time.get_datetime_string_from_system(false, true),
	}
	var json_text := JSON.stringify(data, "\t")

	var f := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: could not open %s for writing (error %d)" % [_slot_path(slot), FileAccess.get_open_error()])
		return false
	f.store_string(json_text)
	f.close()
	return true

## Loads and reconstructs the full party in `slot` as an Array of
## Characters (1-4), or an empty array if the slot is empty,
## unreadable, or references data that no longer exists.
## `out_active_index`, if given, is set to the saved active index.
## `out_dismissed`, if given, is set to the saved list of dismissed
## companions (see save_game above) — empty for a save predating that
## feature, same "missing means none yet" convention used elsewhere.
static func load_party(slot: int, out_active_index: Array = [], out_dismissed: Array = []) -> Array[Character]:
	var empty: Array[Character] = []
	if not has_save(slot):
		return empty
	var f := FileAccess.open(_slot_path(slot), FileAccess.READ)
	if f == null:
		return empty
	var text := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return empty

	var result: Array[Character] = []
	if parsed.has("party"):
		for member_data in parsed["party"]:
			var c := Character.from_save_dict(member_data)
			if c != null:
				result.append(c)
		if not out_active_index.is_empty():
			out_active_index[0] = int(parsed.get("active_party_index", 0))
		if not out_dismissed.is_empty():
			var dismissed_list: Array[Character] = []
			for member_data in parsed.get("dismissed_companions", []):
				var dc := Character.from_save_dict(member_data)
				if dc != null:
					dismissed_list.append(dc)
			out_dismissed[0] = dismissed_list
	else:
		## Backward compatibility: an old save file is one flat
		## character dict with no "party" wrapper at all — load it as
		## a party of one, same as it always behaved.
		var c := Character.from_save_dict(parsed)
		if c != null:
			result.append(c)
		if not out_active_index.is_empty():
			out_active_index[0] = 0
		if not out_dismissed.is_empty():
			out_dismissed[0] = []
	return result

## Lightweight summary for UI display without fully reconstructing the
## Character (race/career objects, etc.) — just the raw JSON fields.
## Returns {} if the slot is empty or unreadable.
static func get_save_summary(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var f := FileAccess.open(_slot_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return {}

	## Per the request: restores the save name that went missing when
	## party support changed the save format out from underneath this
	## function — it was still reading a top-level "character_name"
	## field that hasn't existed since saves became
	## {"party": [...], "active_party_index": N}. Now genuinely lists
	## every party member's own name, not just one, and drops the Tier
	## per the request — a save with several characters in it doesn't
	## have one single Tier to show anyway.
	var party_names: Array[String] = []
	var wounds_current := 0
	var wounds_max := 0
	if parsed.has("party"):
		var party_data: Array = parsed["party"]
		for member_data in party_data:
			party_names.append(str(member_data.get("character_name", "?")))
		var active_idx: int = int(parsed.get("active_party_index", 0))
		if active_idx >= 0 and active_idx < party_data.size():
			wounds_current = int(party_data[active_idx].get("wounds_current", 0))
			wounds_max = int(party_data[active_idx].get("wounds_max", 0))
	else:
		## Backward compatibility: an old save file is one flat
		## character dict with no "party" wrapper at all.
		party_names.append(str(parsed.get("character_name", "?")))
		wounds_current = int(parsed.get("wounds_current", 0))
		wounds_max = int(parsed.get("wounds_max", 0))

	return {
		"party_names": party_names,
		"wounds_current": wounds_current,
		"wounds_max": wounds_max,
		"saved_at": str(parsed.get("saved_at", "?")),
	}

static func delete_save(slot: int) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(_slot_path(slot))
