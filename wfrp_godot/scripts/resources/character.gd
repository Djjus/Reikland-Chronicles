extends Resource
class_name Character
## A complete character: identity, characteristics, skills, talents,
## career progress, and derived combat stats.

@export var character_name: String = ""
## "male" or "female" — same convention NPCNameGenerator.NameInfo already
## uses for randomly-generated NPCs. Per the request ("time to add
## female character option"): drives which of CareerPortraits' two art
## sets (assets/portraits/careers/ vs assets/portraits/careers_female/)
## this character's own portrait comes from — see
## CareerPortraits.get_portrait_for_character(). Defaults to "male" so
## every pre-existing save/character (and every NPC/monster Character
## built without ever touching this field) keeps showing exactly the
## portrait it always has.
@export var gender: String = "male"
@export var race: RaceDefinition
## Monsters have no Race (race stays null), so get_movement() can't
## fall back to race.movement for them — this holds a monster's own
## Movement stat instead. -1 means "not a monster, use race normally."
## Fixes a real pre-existing bug: MonsterDefinition.to_character()
## built a Character whose Movement silently defaulted to 4 regardless
## of the monster's own stat, since nothing ever set this before.
var monster_movement: int = -1
## Same pattern as monster_movement above: monsters have no career
## (career stays null), so the Attacker/Defender box's name line
## ("Name — Career") had nothing to show for one but "?". Per the
## request ("if the monster has no class show it's faction instead"),
## MonsterDefinition.to_character() copies its own faction (Beast,
## Greenskin, Undead, etc.) in here — empty string for a real player
## character or a career-templated Bandit/Outlaw (both already have a
## real career to show instead).
var monster_faction: String = ""
## Accumulator for creature traits whose stat_mod tag targets
## "movement" (Fast, Brute) — kept separate from monster_movement/
## race.movement so get_movement() can add it on top of either. Fixes
## a second real bug: creature_traits.gd tried to write directly to a
## Character.movement property that never existed.
var creature_movement_bonus: int = 0
@export var characteristics: CharacteristicSet
@export var career: CareerDefinition
@export var current_tier: int = 1
## Per the request: a record of every Career change (including tier
## advances within the same career) this character has gone through —
## populated by Advancement.change_career(), shown in the Character
## Menu's Career tab. Each entry: {from_career, from_tier, to_career,
## to_tier, day_of_year, imperial_year, cost}.
@export var career_history: Array[Dictionary] = []

## Skill advances: key = skill display name (e.g. "Melee (Basic)"),
## value = number of advances purchased (each advance = +1 to the skill).
@export var skill_advances: Dictionary = {}

## Characteristic advances purchased with XP: key = characteristic key
## (e.g. "strength"), value = number of advances purchased so far. This
## is tracked separately from the initial 2d10-roll value so advancement
## costs (which scale with advances *purchased*, not the raw score) are
## computed correctly (p.47).
@export var characteristic_advances: Dictionary = {}

## Talents taken: key = talent name, value = rank taken.
@export var talents_taken: Dictionary = {}

## Per the follow-up request ("Melee (Any) chosen for a previously
## learned Melee Skill, which should be an allowed option"): how many of
## a given "(Any)" skill qualifier's own grant slots (e.g. "Melee
## (Any)", possibly granted more than once across a career's tiers) have
## actually been spent through that qualifier's own picker — key =
## qualifier string, value = count. skill_advances alone can't answer
## this: it only tracks "does the character have advances in variant X,"
## which can't tell two separate slots that both resolved to the SAME
## already-known variant apart from only one slot ever having been used.
## Allowing a slot to resolve to a skill the character already knows (a
## real, legal choice, not just a UI quirk) needs this separate counter
## so every remaining slot for that qualifier can't just be "bought" for
## free by repeatedly re-picking whatever's already known.
@export var skill_any_purchases: Dictionary = {}

## Re-added per a confirmed regression (crash: "Invalid access to
## property or key 'skill_any_resolved'" opening the Character Menu's
## Skills tab on any character with a resolved "(Any)" skill) — this
## field existed from v0.3.51 (see that version's own writeup: "Selling
## an (Any) skill to 0 advances no longer removes it from the list")
## but was lost from this file at some later point while
## Advancement.gd's own reads of it were never touched, leaving four
## live `character.skill_any_resolved` accesses in advancement.gd with
## nothing on Character to actually read. A permanent record of every
## display name an "(Any)" skill qualifier (e.g. "Ride (Any)") has ever
## been resolved to, independent of skill_advances/the current advance
## count — nothing ever removes an entry once added, exactly like a
## concrete career skill's row never disappearing either.
## Advancement.purchase_skill_advance() appends to it whenever a
## purchase resolves an "(Any)" slot; find_chosen_skill_variant()/
## find_all_chosen_skill_variants() check it alongside
## skill_advances.has() so a resolved choice keeps showing even after
## being sold all the way back down to 0 advances.
@export var skill_any_resolved: Array[String] = []
## Creature Traits (p.338-343) — the monster/NPC-only equivalent of
## Talents. Never populated for a real player Character; only
## MonsterDefinition.to_character() sets this. A flat list of strings
## like "Bite (5)", "Fear (1)", "Bestial" — no advancement/ranks, since
## NPCs don't buy these with XP.
@export var creature_traits: Array[String] = []

@export var fate_points: int = 0
@export var fortune_points: int = 0
## Corruption points (p.184): accrued from Miscasts, Dark Deals, Chaos
## exposure, and similar. Crossing the Corruption Threshold (see
## get_corruption_threshold() below) rolls and applies a Mutation — see
## CorruptionResolver.check_and_apply_threshold().
@export var corruption_points: int = 0
## Named Mutations gained so far from crossing the Corruption
## Threshold — see CorruptionResolver. Narrative/tracking only, same
## treatment as creature_traits: no automatic characteristic/skill
## change is derived from a mutation's name.
@export var mutations_gained: Array[String] = []

## Where this character last made camp (an Overworld tile), so
## returning from the Camp screen — or reloading the game entirely —
## drops them back at the same spot rather than the map's default
## spawn. Vector2i(-1, -1) means "no camp set / not applicable" — the
## same sentinel convention GameState.return_position already uses.
## Persists across saves (unlike return_position, which is session-only
## and specifically for post-battle returns) and is cleared on death,
## sending a fresh spawn to the nearest safe town instead.
## Despite the name, this is also kept up to date on every single
## Overworld step (see Overworld._on_player_moved), not just when Camp
## is explicitly opened — otherwise it would only ever reflect the
## last deliberate camp, and quitting or switching characters without
## camping first would silently drop the player back at that stale
## spot (or the map's default) on the next load, rather than wherever
## they'd actually last been standing. A real bug this project used to
## have, fixed by keeping this field genuinely current at all times.
@export var camp_position: Vector2i = Vector2i(-1, -1)

## --- Journal / ongoing story, per the request ---------------------------
## An ongoing, per-character story — starting with a class/career-
## themed origin story shown once at the very start of play, then
## added to automatically for genuinely story-worthy events (a new
## location, a career change, a quest update, a new contact) — never
## for routine fights or encounters. Each entry: {day_of_year: int,
## imperial_year: int, category: String, title: String, body: String}.
## Deliberately a plain Array of Dictionaries rather than a typed
## Resource class, since it's simple key/value data with no behaviour
## of its own.
## Per the request: Quests and the Journal are shared for the whole
## party, not each member's own separate copy — the same low-risk
## computed-property pattern already proven for coin. This is also
## the real fix for a genuine bug: quest logic (start_scripted_quest,
## check_quest_timelines, setup_quest_monster_encounter, and others)
## all operate on GameState.player_character — whoever is currently
## active — while the Character Menu's own Quest/Journal tabs read
## from GameState.party[0] specifically. If those were two different
## characters (the player switched active member via Q/E at some
## point), quest state would split across them — a scripted quest's
## own timeline events or a quest monster's own tracked Wounds could
## silently stop firing, which is exactly the kind of bug this fixes
## at its actual root rather than patching every call site
## individually. A Character not currently part of a real party (a
## fresh character mid-creation, a monster, a standalone test) still
## gets its own private, independent Array.
var _journal_entries_backing: Array = []
var journal_entries: Array:
	get:
		if GameState.party.has(self) and GameState.party[0] != self:
			return GameState.party[0].journal_entries
		return _journal_entries_backing
	set(value):
		if GameState.party.has(self) and GameState.party[0] != self:
			GameState.party[0].journal_entries = value
		else:
			_journal_entries_backing = value
@export var has_seen_origin_story: bool = false
## Per-category "already recorded" tracking, so a repeatable trigger
## (e.g. re-entering an area) doesn't spam duplicate entries — keyed
## by a category-specific identifier (e.g. "location:Dark Forest").
@export var journal_recorded_keys: Array[String] = []

## Adds a new Journal entry stamped with the current in-game date. Per
## the request: used for real story beats only (see the category
## list above) — callers decide what counts, this just records it.
## unique_key, if given, is checked against journal_recorded_keys
## first; a duplicate is silently skipped (returns false) rather than
## logged twice — the mechanism future quest/career/contact systems
## should use to record "this happened once," matching how location
## visits already use it below.
func add_journal_entry(category: String, title: String, body: String, unique_key: String = "") -> bool:
	if unique_key != "" and journal_recorded_keys.has(unique_key):
		return false
	if unique_key != "":
		journal_recorded_keys.append(unique_key)
	journal_entries.append({
		"day_of_year": GameState.day_of_year,
		"imperial_year": GameState.imperial_year,
		"category": category,
		"title": title,
		"body": body,
	})
	return true

## --- Quests, per the request: their own tab, separate from the plain
## story Notes above, listing quests and tracking their completion.
## No quest-granting system exists in this project yet — this is the
## real, working infrastructure a future one should call, matching how
## journal_entries was built ahead of the systems that will eventually
## feed it. Each quest: {quest_id: String, title: String,
## description: String, status: String ("Active"/"Completed"/
## "Failed"), objectives: Array[Dictionary] — each
## {"text": String, "done": bool}}.
var _quests_backing: Array = []
var quests: Array:
	get:
		if GameState.party.has(self) and GameState.party[0] != self:
			return GameState.party[0].quests
		return _quests_backing
	set(value):
		if GameState.party.has(self) and GameState.party[0] != self:
			GameState.party[0].quests = value
		else:
			_quests_backing = value

func find_quest(quest_id: String) -> Dictionary:
	for q in quests:
		if q.get("quest_id", "") == quest_id:
			return q
	return {}

## Starts a new quest. Returns false (adds nothing) if a quest with
## this id already exists — quest_id is meant to be a stable,
## programmer-chosen identifier, not shown to the player, so a
## duplicate is almost certainly a bug in the caller, not an
## intentional restart.
func add_quest(quest_id: String, title: String, description: String, objective_texts: Array[String] = []) -> bool:
	if not find_quest(quest_id).is_empty():
		return false
	var objectives: Array = []
	for t in objective_texts:
		objectives.append({"text": t, "done": false})
	quests.append({
		"quest_id": quest_id, "title": title, "description": description,
		"status": "Active", "objectives": objectives,
	})
	add_journal_entry("Quest", "New Quest: %s" % title, description)
	return true

## Marks a single objective done (or, given false, un-does it — for a
## future caller that needs to walk a step back). Returns false if the
## quest or objective index doesn't exist.
func set_quest_objective_done(quest_id: String, objective_index: int, done: bool = true) -> bool:
	for q in quests:
		if q.get("quest_id", "") == quest_id:
			var objectives: Array = q.get("objectives", [])
			if objective_index < 0 or objective_index >= objectives.size():
				return false
			objectives[objective_index]["done"] = done
			return true
	return false

## Updates a quest's overall status (typically "Completed" or
## "Failed") — per the request, this also records a real Notes entry,
## the same "quest updates" category the earlier Journal work already
## established, so a finished quest leaves a mark on the ongoing story
## too, not just a status flag in its own tab.
func set_quest_status(quest_id: String, status: String) -> bool:
	for q in quests:
		if q.get("quest_id", "") == quest_id:
			q["status"] = status
			add_journal_entry("Quest", "%s: %s" % [status, q.get("title", quest_id)], "")
			return true
	return false

## --- The Village Elder's quest chain, per the request: a hand-built,
## 3-stage narrative quest (not a generic Task) — kill 8 creatures,
## help 4 locals, then recover a stolen idol from the Goblin Fort.
## elder_stage: 1 (kill), 2 (help), 3 (idol), 4 (complete). Stored as
## its own quest entry (quest_id ELDER_QUEST_ID) using extra fields the
## same way Tasks already layer extra fields onto the base Quest shape.
const ELDER_QUEST_ID := "village_elder_chain"

func get_elder_quest() -> Dictionary:
	return find_quest(ELDER_QUEST_ID)

## Starts the chain at Stage 1. Returns false if it's already running
## or already finished — the Elder doesn't repeat himself.
func start_elder_quest() -> bool:
	if not find_quest(ELDER_QUEST_ID).is_empty():
		return false
	quests.append({
		"quest_id": ELDER_QUEST_ID, "title": "The Elder's Favour", "status": "Active",
		"description": "Giessingen's Elder has asked for help culling the vermin plaguing the village's fields.",
		"objectives": [], "is_task": false,
		"elder_stage": 1, "elder_stage_ready": false,
		"elder_kill_progress": 0, "elder_help_progress": 0,
	})
	add_journal_entry("Quest", "The Elder's Favour", "Giessingen's Elder has asked you to help thin out the vermin plaguing the village's fields — at least 8 real kills before you're owed any thanks.")
	return true

## Called on every individual monster kill in a real fight (not per
## encounter/group — per the request's own "not groups of creatures")
## while Stage 1 is active. Marks the stage ready once 8 real kills
## are reached, without auto-advancing — the Elder himself delivers
## the next part of the story when next spoken to, per the request's
## own "talk to the Village Elder" trigger.
func progress_elder_kill() -> void:
	var q := get_elder_quest()
	if q.is_empty() or q.get("status", "") != "Active" or int(q.get("elder_stage", 0)) != 1:
		return
	for qq in quests:
		if qq.get("quest_id", "") == ELDER_QUEST_ID:
			qq["elder_kill_progress"] = int(qq.get("elder_kill_progress", 0)) + 1
			if int(qq["elder_kill_progress"]) >= 8:
				qq["elder_stage_ready"] = true
			return

## Called whenever a real social encounter is genuinely won (not the
## Elder's own story conversation itself) while Stage 2 is active.
func progress_elder_help() -> void:
	var q := get_elder_quest()
	if q.is_empty() or q.get("status", "") != "Active" or int(q.get("elder_stage", 0)) != 2:
		return
	for qq in quests:
		if qq.get("quest_id", "") == ELDER_QUEST_ID:
			qq["elder_help_progress"] = int(qq.get("elder_help_progress", 0)) + 1
			if int(qq["elder_help_progress"]) >= 4:
				qq["elder_stage_ready"] = true
			return

## Advances from the current (ready) stage to the next, resetting
## elder_stage_ready for the new stage. Returns false if the current
## stage genuinely isn't ready yet.
func advance_elder_quest_stage() -> bool:
	var q := get_elder_quest()
	if q.is_empty() or not bool(q.get("elder_stage_ready", false)):
		return false
	for qq in quests:
		if qq.get("quest_id", "") == ELDER_QUEST_ID:
			qq["elder_stage"] = int(qq["elder_stage"]) + 1
			qq["elder_stage_ready"] = false
			if int(qq["elder_stage"]) == 2:
				add_journal_entry("Quest", "The Elder's Favour: A Village in Need", "With the vermin dealt with, the Elder has asked you to help a few of Giessingen's own folk with more personal troubles — at least 4 of them.")
			elif int(qq["elder_stage"]) == 3:
				add_journal_entry("Quest", "The Elder's Favour: The Stolen Idol", "The Elder has told you of a small idol, sacred to the village, stolen by goblins from the East some weeks past. He suggested you might go looking for it.")
			return true
	return false

func complete_elder_quest() -> void:
	set_quest_status(ELDER_QUEST_ID, "Completed")
	for qq in quests:
		if qq.get("quest_id", "") == ELDER_QUEST_ID:
			qq["elder_stage"] = 4
			return

## --- Scripted-NPC quests, per the request: the generic, data-driven
## counterpart to the Village Elder's own hand-built chain above —
## for a QuestDefinition/QuestNPCDefinition-driven quest (see
## scripts/resources/quest_definition.gd), rather than a new set of
## bespoke Character fields for every adventure imported. Uses this
## same quests: Array the Elder's own quest and Tasks already use,
## with two extra fields layered on: npc_states (a Dictionary of
## npc_id -> "pass"/"fail") and npc_start_times (npc_id -> the real
## in-game minute, GameState.time_minutes-scale, an NPC was first
## encountered — used for a real Test's own real time limit).

## Starts tracking a scripted quest if it isn't already. Safe to call
## every time the quest's own trigger point is reached — a no-op if
## the quest is already active or completed.
func start_scripted_quest(quest_id: String, title: String, description: String = "") -> bool:
	if not find_quest(quest_id).is_empty():
		return false
	quests.append({
		"quest_id": quest_id, "title": title, "status": "Active",
		"description": description, "objectives": [], "is_task": false,
		"npc_states": {}, "npc_start_times": {},
		## Per the request: the quest's own ticking clock starts the
		## same moment the quest itself does — every timed event on
		## it is measured from here, and fired_timeline_events tracks
		## which have already gone off so none fire twice.
		"timeline_start_minutes": GameState.time_minutes_total(), "fired_timeline_events": [],
	})
	if description != "":
		add_journal_entry("Quest", title, description)
	return true

## "" means genuinely unresolved (not yet attempted); "pass"/"fail"
## once resolved either way.
func get_quest_npc_state(quest_id: String, npc_id: String) -> String:
	var q := find_quest(quest_id)
	if q.is_empty():
		return ""
	var states: Dictionary = q.get("npc_states", {})
	return str(states.get(npc_id, ""))

func set_quest_npc_state(quest_id: String, npc_id: String, state: String) -> void:
	for qq in quests:
		if qq.get("quest_id", "") == quest_id:
			var states: Dictionary = qq.get("npc_states", {})
			states[npc_id] = state
			qq["npc_states"] = states
			return

## -1 means this NPC has genuinely never been encountered yet — the
## real trigger for starting their own real time limit, if they have
## one (QuestNPCDefinition.timeout_minutes >= 0). Recording this only
## the first time (never overwriting an existing start time) means
## revisiting an NPC repeatedly can't reset their own clock.
func get_quest_npc_start_time(quest_id: String, npc_id: String) -> int:
	var q := find_quest(quest_id)
	if q.is_empty():
		return -1
	var times: Dictionary = q.get("npc_start_times", {})
	return int(times.get(npc_id, -1))

## Per the request: tracks whether the player has genuinely visited a
## given quest NPC at all — separate from get_quest_npc_state(), which
## tracks whether their crisis was actually resolved (pass/fail).
## Dynamic rerouting checks this rather than resolution state, since
## the source material's own example (visiting the temple unlocks
## Gerd's real information) only requires having been there, not
## necessarily having passed Martha's own Test.
func get_quest_npc_visited(quest_id: String, npc_id: String) -> bool:
	var q := find_quest(quest_id)
	if q.is_empty():
		return false
	var visited: Array = q.get("visited_npcs", [])
	return visited.has(npc_id)

func set_quest_npc_visited(quest_id: String, npc_id: String) -> void:
	for qq in quests:
		if qq.get("quest_id", "") == quest_id:
			var visited: Array = qq.get("visited_npcs", [])
			if not visited.has(npc_id):
				visited.append(npc_id)
				qq["visited_npcs"] = visited
			return

## Per the request: whether this NPC is genuinely gone from the map —
## dead, fled, or lost to the flood — as distinct from merely having
## failed a Test but still being physically present. A quest whose
## own flood has triggered removes every NPC at once, regardless of
## their own individual state.
func is_quest_npc_removed(quest_id: String, npc_id: String) -> bool:
	var q := find_quest(quest_id)
	if q.is_empty():
		return false
	if bool(q.get("flood_triggered", false)):
		return true
	var removed: Array = q.get("npcs_removed", [])
	return removed.has(npc_id)

func mark_quest_npc_removed(quest_id: String, npc_id: String) -> void:
	for qq in quests:
		if qq.get("quest_id", "") == quest_id:
			var removed: Array = qq.get("npcs_removed", [])
			if not removed.has(npc_id):
				removed.append(npc_id)
				qq["npcs_removed"] = removed
			return

func set_quest_npc_start_time_if_unset(quest_id: String, npc_id: String, minutes: int) -> void:
	for qq in quests:
		if qq.get("quest_id", "") == quest_id:
			var times: Dictionary = qq.get("npc_start_times", {})
			if not times.has(npc_id):
				times[npc_id] = minutes
				qq["npc_start_times"] = times
			return

## Per the request: a quest monster's own genuinely-current Wounds,
## as modified by any healing timeline events that have already
## fired — falls back to default_wounds (the QuestMonsterDefinition's
## own static starting_wounds) the first time this is ever read, so
## a monster nobody has fought yet, or whose quest has no healing
## events at all, still reports a sensible value.
func get_quest_monster_current_wounds(quest_id: String, monster_id: String, default_wounds: int) -> int:
	var q := find_quest(quest_id)
	if q.is_empty():
		return default_wounds
	var wounds_map: Dictionary = q.get("monster_current_wounds", {})
	return int(wounds_map.get(monster_id, default_wounds))

func set_quest_monster_current_wounds(quest_id: String, monster_id: String, wounds: int) -> void:
	for qq in quests:
		if qq.get("quest_id", "") == quest_id:
			var wounds_map: Dictionary = qq.get("monster_current_wounds", {})
			wounds_map[monster_id] = wounds
			qq["monster_current_wounds"] = wounds_map
			return

## Per the request: mirrors the wounds tracking above, but for
## Conditions — read at encounter setup instead of the static
## starting_conditions once anything has actually changed it, so the
## Jabberslythe's own healing timeline (removing Fatigued/Bleeding/
## Blinded stacks as specific injuries close) is genuinely reflected
## the next time the fight actually happens.
func get_quest_monster_current_conditions(quest_id: String, monster_id: String, default_conditions: Dictionary) -> Dictionary:
	var q := find_quest(quest_id)
	if q.is_empty():
		return default_conditions
	var conditions_map: Dictionary = q.get("monster_current_conditions", {})
	if not conditions_map.has(monster_id):
		return default_conditions
	return conditions_map[monster_id]

func remove_quest_monster_condition(quest_id: String, monster_id: String, condition_name: String, stacks: int) -> void:
	for qq in quests:
		if qq.get("quest_id", "") == quest_id:
			var conditions_map: Dictionary = qq.get("monster_current_conditions", {})
			var current: Dictionary = conditions_map.get(monster_id, {})
			if current.is_empty():
				## First real change — seed from this quest's own
				## static starting_conditions so later reads see the
				## full, real picture, not just this one reduction.
				var quest_def: QuestDefinition = load("res://data/quests/%s.tres" % quest_id) as QuestDefinition
				var mdef := quest_def.find_monster(monster_id) if quest_def != null else null
				current = mdef.starting_conditions.duplicate(true) if mdef != null else {}
			var existing: int = int(current.get(condition_name, 0))
			var reduced: int = maxi(0, existing - stacks)
			if reduced > 0:
				current[condition_name] = reduced
			else:
				current.erase(condition_name)
			conditions_map[monster_id] = current
			qq["monster_current_conditions"] = conditions_map
			return

## Per the request: a real, explicit "this quest monster was defeated
## in combat" flag — tracked separately from Wounds/healing, since a
## quest's own win condition needs a clean, direct answer rather than
## inferring defeat from a Wounds value that a healing timeline event
## might otherwise still be adjusting.
func set_quest_monster_defeated(quest_id: String, monster_id: String) -> void:
	for qq in quests:
		if qq.get("quest_id", "") == quest_id:
			var defeated: Dictionary = qq.get("monster_defeated", {})
			defeated[monster_id] = true
			qq["monster_defeated"] = defeated
			return

func get_quest_monster_defeated(quest_id: String, monster_id: String) -> bool:
	var q := find_quest(quest_id)
	if q.is_empty():
		return false
	var defeated: Dictionary = q.get("monster_defeated", {})
	return bool(defeated.get(monster_id, false))

## Per the request: evaluates a quest's own real win/loss outcome
## against N independent boolean conditions, combined per each
## group's own real rule — every group in QuestDefinition.win_conditions
## must itself be met (a plain AND across groups) for "won" to be
## true overall, and each group's own required_count decides how many
## of ITS checks must be true (-1 for "all of them", or any positive
## N for a genuine "at least N of these" threshold — a plain OR is
## just required_count = 1). Returns a full breakdown, not just the
## final bool, so a quest's own ending text can react to exactly which
## groups were and weren't met, not just whether the whole thing
## passed or failed.
func evaluate_quest_win_conditions(quest_id: String) -> Dictionary:
	var quest_def: QuestDefinition = load("res://data/quests/%s.tres" % quest_id) as QuestDefinition
	if quest_def == null or quest_def.win_conditions.is_empty():
		return {"won": false, "groups": []}
	var groups: Array = []
	var all_met := true
	for group in quest_def.win_conditions:
		var satisfied := 0
		for check in group.checks:
			if _evaluate_quest_check(quest_id, check):
				satisfied += 1
		var required: int = group.required_count if group.required_count >= 0 else group.checks.size()
		var met: bool = satisfied >= required
		if not met:
			all_met = false
		groups.append({
			"condition_id": group.condition_id, "label": group.group_label,
			"met": met, "satisfied_count": satisfied, "required_count": required,
			"total_checks": group.checks.size(),
		})
	return {"won": all_met, "groups": groups}

## Parses and evaluates a single "type:id:qualifier" check string — see
## QuestWinCondition's own header comment for the full recognized
## format list. An unrecognized type or malformed string is treated as
## false rather than raising an error, so a typo'd check quietly fails
## its own group instead of crashing the whole evaluation.
func _evaluate_quest_check(quest_id: String, check: String) -> bool:
	var parts := check.split(":")
	if parts.size() < 2:
		return false
	match parts[0]:
		"npc":
			if parts.size() < 3:
				return false
			var state := get_quest_npc_state(quest_id, parts[1])
			match parts[2]:
				"pass": return state == "pass"
				"fail": return state == "fail"
				"resolved": return state != ""
				_: return false
		"timeline":
			if parts.size() < 3:
				return false
			var q := find_quest(quest_id)
			if q.is_empty():
				return false
			var fired: Array = q.get("fired_timeline_events", [])
			match parts[2]:
				"fired": return fired.has(parts[1])
				"not_fired": return not fired.has(parts[1])
				_: return false
		"monster":
			if parts.size() < 3 or parts[2] != "defeated":
				return false
			return get_quest_monster_defeated(quest_id, parts[1])
		_:
			return false

## Sets up GameState's own pending encounter fields for a fight
## against a specific QuestMonsterDefinition, at its own genuinely-
## current state — any healing timeline events already fired are
## correctly reflected, rather than always using that Resource's own
## static starting_wounds. Appends to (rather than overwrites) any
## monster names/overrides already pending, so this can be combined
## with other monsters in the same fight if a quest ever needs that.
## Still leaves the actual scene transition to the caller.
func setup_quest_monster_encounter(quest_monster: QuestMonsterDefinition, quest_id: String) -> void:
	GameState.pending_encounter_monster_names.append(quest_monster.monster_name)
	var current_wounds := get_quest_monster_current_wounds(quest_id, quest_monster.monster_id, quest_monster.starting_wounds)
	if current_wounds >= 0:
		GameState.pending_encounter_wound_override[quest_monster.monster_name] = current_wounds
	var current_conditions := get_quest_monster_current_conditions(quest_id, quest_monster.monster_id, quest_monster.starting_conditions)
	if not current_conditions.is_empty():
		GameState.pending_encounter_condition_override[quest_monster.monster_name] = current_conditions.duplicate(true)

## Per the request: the generic ticking-clock check — called from
## GameState's own advance_minutes()/advance_days(), so it runs
## automatically every time real in-game time passes anywhere in the
## game (World Map travel, Camp's Sleep, anywhere else that already
## calls either of those two functions), rather than needing every
## individual time-advancing call site to remember to check it
## itself. For every Active scripted quest this Character has, loads
## that quest's own QuestDefinition (by convention at
## res://data/quests/<quest_id>.tres) and fires any timeline event
## whose trigger_minutes has now genuinely been reached — skipping
## any event already fired, and any event genuinely canceled by its
## own cancel_if_npc_id having reached cancel_if_npc_state.
func check_quest_timelines() -> void:
	for qq in quests:
		if qq.get("status", "") != "Active" or bool(qq.get("is_task", false)):
			continue
		var quest_id: String = qq.get("quest_id", "")
		if quest_id == "":
			continue
		var quest_def: QuestDefinition = load("res://data/quests/%s.tres" % quest_id) as QuestDefinition
		if quest_def == null or quest_def.timeline_events.is_empty():
			continue
		var start_minutes: int = int(qq.get("timeline_start_minutes", -1))
		if start_minutes < 0:
			continue
		var fired: Array = qq.get("fired_timeline_events", [])
		## Real bug fix: a canceled event was previously being added
		## to fired_timeline_events too, purely to avoid re-checking it
		## every subsequent time advance — but that conflated "fired"
		## with "canceled", so a win condition checking whether an
		## event genuinely fired would incorrectly see a canceled one
		## as having gone off. Tracked separately now — "processed and
		## should never be checked again" (fired OR cancelled) is
		## still handled once, but the two real outcomes stay distinct.
		var cancelled: Array = qq.get("cancelled_timeline_events", [])
		var elapsed := GameState.time_minutes_total() - start_minutes
		for event in quest_def.timeline_events:
			if fired.has(event.event_id) or cancelled.has(event.event_id):
				continue
			if elapsed < event.trigger_minutes:
				continue
			## Cancelable independently — per the request, an event
			## with its own named NPC that's already reached the
			## canceling state simply never fires, with no other
			## trace (no journal entry, no Condition) — the player's
			## own intervention genuinely prevented it, not just
			## delayed it.
			if event.cancel_if_npc_id != "":
				var npc_state := get_quest_npc_state(quest_id, event.cancel_if_npc_id)
				if npc_state == event.cancel_if_npc_state:
					cancelled.append(event.event_id)
					qq["cancelled_timeline_events"] = cancelled
					continue
			if event.description != "":
				add_journal_entry("Quest", qq.get("title", quest_id), event.description)
			if event.apply_condition != "":
				add_condition(event.apply_condition, event.apply_condition_stacks)
			if event.heal_monster_id != "":
				var mdef := quest_def.find_monster(event.heal_monster_id)
				var base_wounds: int = mdef.starting_wounds if mdef != null else 0
				var current := get_quest_monster_current_wounds(quest_id, event.heal_monster_id, base_wounds)
				## Per the request: an absolute target Wounds value
				## (the source's own timeline gives exact stages, not
				## increments) takes priority over the relative
				## heal_wounds_amount when set.
				var new_wounds: int = event.heal_monster_set_wounds if event.heal_monster_set_wounds >= 0 else current + event.heal_wounds_amount
				set_quest_monster_current_wounds(quest_id, event.heal_monster_id, new_wounds)
				if event.heal_monster_remove_condition != "":
					remove_quest_monster_condition(quest_id, event.heal_monster_id, event.heal_monster_remove_condition, event.heal_monster_remove_condition_stacks)
			## Per the request: any NPC named here is lost the moment
			## this event fires — marked "fail" so they stop being
			## visible/accessible, same real gating already used for
			## a normally-failed Test.
			for npc_id in event.kills_npc_ids:
				if get_quest_npc_state(quest_id, npc_id) == "":
					set_quest_npc_state(quest_id, npc_id, "fail")
				mark_quest_npc_removed(quest_id, npc_id)
			## Per the request: the flood itself is applied directly
			## by Overworld (a whole-map transformation, not a per-
			## Character concern) — this just records that it's now
			## due, checked and cleared there the next time the
			## Gotheim map is actually loaded or already active.
			if event.triggers_flood:
				qq["flood_triggered"] = true
			fired.append(event.event_id)
			qq["fired_timeline_events"] = fired

## --- Tasks, per the request: a lightweight, NPC-given mini-Quest —
## either gather a specific number of a specific trophy item, or find
## a specific, rare social encounter — offered whenever the player
## Talks to an NPC (see Overworld.gd's _on_talk_to_npc). Tracked in
## this same `quests` Array via a few extra fields layered on top of
## the normal Quest shape: is_task, task_type ("gather" or
## "find_encounter"), target_key (an item name or a
## SocialEncounterDefinition's own encounter_name), target_count, and
## progress. Per the request's own scope, only ever ONE active task at
## a time — talking to another NPC while one is already active is just
## small talk, no second task offered, which keeps "which task does
## this gold marker belong to" always unambiguous.

func get_active_task() -> Dictionary:
	for q in quests:
		if q.get("is_task", false) and q.get("status", "") == "Active":
			return q
	return {}

## Returns false (adds nothing) if a task is already active, or if
## task_id somehow collides with an existing quest/task — callers
## should check get_active_task().is_empty() first regardless.
func add_task(task_id: String, title: String, description: String, task_type: String, target_key: String, target_count: int = 1) -> bool:
	if not get_active_task().is_empty():
		return false
	if not find_quest(task_id).is_empty():
		return false
	quests.append({
		"quest_id": task_id, "title": title, "description": description,
		"status": "Active", "objectives": [], "is_task": true,
		"task_type": task_type, "target_key": target_key,
		"target_count": target_count, "progress": 0,
	})
	add_journal_entry("Quest", "New Task: %s" % title, description)
	return true

## Called whenever a trophy item is looted (see field_encounter_screen.gd's
## own _generate_loot) — advances the active gather task's progress if
## the item matches, completing it once the target count is reached.
func progress_task_gather(item_name: String) -> void:
	var task := get_active_task()
	if task.is_empty() or task.get("task_type", "") != "gather":
		return
	if task.get("target_key", "") != item_name:
		return
	for q in quests:
		if q.get("quest_id", "") == task.get("quest_id", ""):
			q["progress"] = int(q.get("progress", 0)) + 1
			if int(q["progress"]) >= int(q.get("target_count", 1)):
				set_quest_status(str(q["quest_id"]), "Completed")
			return

## Called whenever a social encounter actually starts (see
## social_encounter_screen.gd) — completes the active find-encounter
## task outright if this is the one it was looking for; "finding" it
## is what the task asked for, win or lose the exchange itself.
func progress_task_find_encounter(encounter_name: String) -> void:
	var task := get_active_task()
	if task.is_empty() or task.get("task_type", "") != "find_encounter":
		return
	if task.get("target_key", "") != encounter_name:
		return
	set_quest_status(str(task.get("quest_id", "")), "Completed")

## Currently-active mechanical penalties from Critical Wounds still
## afflicting the character — e.g. "-10 Agility for 1d10 days" from
## Bruised Ribs. Reuses the same {name, source, characteristic_bonuses,
## rounds_remaining, damage_bonus} shape as active_buffs (just negative
## characteristic_bonuses), tracked separately so healing a Critical
## Wound can remove its specific penalty without touching unrelated
## Blessing/Miracle buffs. "Rounds" here are actually days for most
## Critical Wound penalties (ticked at end of a Camp sleep of any
## length, not at combat's end of Round) — see tick_critical_wound_days().
@export var critical_wound_penalties: Array = []

## p.171: spending a Resolve point to "ignore all modifiers from all
## Critical Wounds until the beginning of the next round" — a Round-
## scoped flag rather than a stored Array entry (unlike active_buffs/
## critical_wound_penalties above) since it doesn't add or remove any
## specific penalty, it just blanks their effect for the rest of this
## Round. Reset every Round in CombatEncounter._on_round_end, the same
## place riposte_uses_this_round/furious_assault_used_this_round reset
## their own once-per-Round flags. See get_effective_characteristic_value().
var critical_wound_penalties_ignored_this_round: bool = false

## How many Critical Wounds are currently "live" (not yet healed) —
## this is what's compared against Toughness Bonus for the p.173
## accumulated-Critical-Wounds death rule.
@export var active_critical_wound_count: int = 0
@export var resilience: int = 1
@export var resolve: int = 1

@export var experience_total: int = 0
@export var experience_spent: int = 0

## Per the request: Prone specifically follows from reaching 0 Wounds
## (p.172) — a character healed back above 0 has no reason to still
## be lying down from that specific cause, so this setter removes it
## automatically the instant Wounds go positive again. A single
## property setter here catches every one of the many places across
## the codebase that assign wounds_current directly, rather than
## needing each of them to separately remember to check this.
## Follow-up request ("out of combat characters with the Prone
## Condition automatically lose it if they have 1+ HP; in combat they
## should have the option to Stand Up"): the auto-clear above now only
## fires outside a FieldEncounter (GameState.in_field_encounter false —
## world map, city, camp, Temple of Shallya, exactly as before).
## Genuinely inside a FieldEncounter (combat or exploration submode),
## healing back above 0 Wounds no longer silently clears Prone for
## free — Character.attempt_stand_up()/attempt_spend_resolve_remove_
## condition() (below) are the only way to actually stand back up
## there, giving the field_encounter_screen.gd Stand Up/Spend Resolve
## buttons something to do.
@export var wounds_current: int = 1:
	set(value):
		wounds_current = value
		if value > 0 and conditions != null and conditions.has("Prone") and not GameState.in_field_encounter:
			remove_condition("Prone")
@export var wounds_max: int = 1

## Social Combat's own depleting pool, per the design doc ("Social
## Combat — Design Doc v1", Section 1) — deliberately mirrors wounds_
## current/wounds_max exactly (same shape, no setter side effects
## needed here since Social Combat has no Prone-equivalent condition
## tied to Composure). composure_max is computed fresh at the start of
## each Social Combat encounter (Willpower + the character's own Cool
## skill value — see SocialCombatEncounter.compute_composure_max()),
## not persisted across encounters/saves the way Wounds is, so both
## default to 1 here purely as a safe placeholder before that first
## computation runs.
@export var composure_current: int = 1
@export var composure_max: int = 1

## Party-wipe/permadeath rework, per the request ("if a character dies
## he should lie on the floor where he was and simply be dead (skip his
## turn)... remove the old revive mechanic"): replaces the old Death.tscn
## permadeath scene entirely. A character who fails their final Fate
## save no longer ends the whole session — they're marked dead in place,
## stay exactly where they fell (battle_positions/turn_order both leave
## them alone, same as any other 0-Wounds character already does — see
## CombatEncounter.is_defeated()), and are simply skipped every turn from
## then on, same turn-skip machinery that already handles a merely-
## unconscious ally. Only a real Shallyan Priest visit (Healer.tscn's own
## Revive action) can clear this flag; ordinary field/camp Wound healing
## does not.
@export var is_dead: bool = false

## Camp rework, per the request: "The heal skill (not spells) can only
## be used once every 4 hrs on each character, this timer clears if a
## battle starts." Tracked per RECIPIENT (this character being healed),
## not per healer — any Heal Skill attempt by anyone against this
## character starts the cooldown. Stored as a GameState.time_minutes_
## total() reading (a real monotonically-increasing absolute-minutes
## value — see that function's own comment) so "4 hours" means 4 real
## in-game hours regardless of day/year boundaries. Defaults far enough
## in the past that a fresh character is immediately healable. Cleared
## back to this same default in field_encounter_screen.gd's
## _start_encounter() the moment a battle begins, per the request.
@export var last_heal_skill_time_minutes: int = -999999

@export var inventory: Array[String] = []
## Per the request ("add a favourite system to items in the inventory,
## this will work by clicking/unclicking a star icon in front of each
## item. When ticked remove the item completely from the shop sell
## list"): tracked by item NAME (not per physical copy — inventory
## stores duplicate string entries for stacked quantity, and there's no
## meaningful way to favourite "one of three Ropes" but not the others),
## so favouriting one copy favourites the whole stack. Toggleable from
## both character_menu_screen.gd's own Inventory tab AND
## shop_screen.gd's Party Inventory/sell list (each has its own Star
## button reading/writing this same field — see
## shop_screen.gd's _add_sell_grid_row). A favourited item is still
## fully shown and priced in the Shop's sell list, it just can't be
## sold (no Sell button) until un-favourited. Deliberately does NOT
## affect the Shop's separate Equipped list, or anything about
## equip/unequip.
@export var favourite_items: Array[String] = []
## Per the request: coin is shared across the whole party, not
## individual. gold_crowns/silver_shillings/brass_pennies below are
## computed properties delegating to the party's own first member
## (the canonical "purse holder") — the same low-risk pattern already
## proven for GameState.player_character in earlier work. Every one of
## the many existing places across the whole project that read or
## write a Character's own coin fields keeps working completely
## unchanged, transparently sharing the same value across every party
## member, with no rewrite needed anywhere else. A Character that
## isn't currently part of GameState.party (a fresh character being
## created, a monster, a standalone test) uses its own private backing
## field instead, so this never breaks outside a real party context.
var _gold_crowns_backing: int = 0
var _silver_shillings_backing: int = 0
var _brass_pennies_backing: int = 0

var gold_crowns: int:
	get:
		if GameState.party.has(self) and GameState.party[0] != self:
			return GameState.party[0].gold_crowns
		return _gold_crowns_backing
	set(value):
		if GameState.party.has(self) and GameState.party[0] != self:
			GameState.party[0].gold_crowns = value
		else:
			_gold_crowns_backing = value

var silver_shillings: int:
	get:
		if GameState.party.has(self) and GameState.party[0] != self:
			return GameState.party[0].silver_shillings
		return _silver_shillings_backing
	set(value):
		if GameState.party.has(self) and GameState.party[0] != self:
			GameState.party[0].silver_shillings = value
		else:
			_silver_shillings_backing = value

var brass_pennies: int:
	get:
		if GameState.party.has(self) and GameState.party[0] != self:
			return GameState.party[0].brass_pennies
		return _brass_pennies_backing
	set(value):
		if GameState.party.has(self) and GameState.party[0] != self:
			GameState.party[0].brass_pennies = value
		else:
			_brass_pennies_backing = value

## --- Combat state -----------------------------------------------------
## This project uses the Group Advantage Pool system exclusively (WFRP:
## Up in Arms, Appendix I, p.133-135) instead of the core rulebook's
## per-character Advantage (p.163) — one less system to juggle. Every
## character's Advantage gains/losses go through a shared
## GroupAdvantagePool (see scripts/core/group_advantage_pool.gd), routed
## by which side they're on.
@export_enum("ally", "adversary") var allegiance: String = "ally"
## Victory (Up in Arms p.133) — see MonsterDefinition for the full
## explanation. Always false for player/NPC-created characters; only
## set true via MonsterDefinition.to_character() for named threats.
@export var is_important: bool = false
@export var is_nemesis: bool = false
## Conditions currently affecting the character (Prone, Stunned,
## Surprised, Engaged, Bleeding, Unconscious, etc.) — key = condition
## name, value = stack count (most Conditions don't stack, but Bleeding
## does).
@export var conditions: Dictionary = {}

@export var equipped_weapon: String = ""       ## name into GameData.weapon_db (main hand)
## A genuinely separate off-hand slot (p.296) — a second one-handed
## weapon (for Dual Wielder) or a shield. Empty string means nothing
## equipped there. A two-handed main weapon can't be combined with an
## off-hand item — enforced where equipping happens (Equipment tab),
## not here, so this field alone doesn't need to re-validate on load.
@export var equipped_offhand: String = ""      ## name into GameData.weapon_db
@export var equipped_armour: Array[String] = [] ## names into GameData.armour_db

## Per the "packs and containers" request: three dedicated Container
## equip slots, each holding at most one item name (into
## GameData.item_db, an ItemDefinition whose own container_slot
## matches). "" means nothing worn there. See
## get_equipped_container()/set_equipped_container() for the shared
## by-slot-name accessors every screen uses instead of touching these
## three fields directly, and get_container_capacity_bonus() for the
## Carrying Capacity bonus they grant while worn.
@export var equipped_container_back: String = ""      ## e.g. a Backpack
@export var equipped_container_waist: String = ""     ## e.g. a Pouch
@export var equipped_container_shoulder: String = ""  ## e.g. a Sling Bag

## "off" | "on" | "low" — "low" is only reachable (see
## Overworld._toggle_light_source()) for a light source whose
## ItemDefinition.light_radius_tiles_low > 0. The toggle itself always
## works regardless of time of day/location, per the request; whether
## it actually does anything visible is decided separately by
## Overworld._light_source_effective() (night or a dark location).
@export var light_mode: String = "off"
## Remaining burn time, in minutes, of whatever's currently lit —
## meaningful while the equipped light source's own light_requires_oil
## is true (drawn from a Lamp Oil reserve, see LAMP_OIL_MINUTES/
## tick_light_fuel() below), or while its light_self_fuel_minutes is
## positive (a self-consuming source like Candle, which burns down its
## own currently-lit unit instead of a separate fuel item). Unused for
## a light source with neither set (burns indefinitely once lit).
@export var light_fuel_minutes: float = 0.0

## Per Lamp Oil's own item text: "enough fuel for 4 hours of standard
## use, or 8 hours of low flame equivalent to a candle" — one oil flask
## lasts this many minutes at "on" (full burn rate); tick_light_fuel()
## below burns it at half that rate while "low", so the same flask
## naturally stretches to 8 hours there instead.
const LAMP_OIL_MINUTES := 240.0

## Light (Petty spell, p.142): "You create a small light, roughly
## equivalent to a torch... Duration: Willpower minutes." Per the
## request ("make Light function like a Lamp... when cast add it to
## the top of the turn order with number of remaining turns (1 min per
## round), recasting will refresh the duration/counter"): rather than
## real-world minutes, this project has no wall-clock timer running
## during a Turn-based encounter, so the Round IS the unit here — 1
## Round = 1 minute, per the request's own framing — meaning this is
## simply the caster's own current Willpower value, ticked down by 1
## at the end of every Round (see tick_active_buffs() below, called
## once per Round per combatant by CombatEncounter._on_round_end()).
## Recasting overwrites this rather than adding to it, so the effect
## always reflects "however long is left since the MOST RECENT cast,"
## never stacking. No dedicated radius/mode fields of its own — see
## LIGHT_SPELL_RADIUS_TILES below and has_active_light_source()/
## get_active_light_radius_tiles()'s own updated bodies, which both
## treat an active Light spell exactly like a lit item-based source,
## so every existing lighting consumer (exploration vision reveal, the
## battle map's own lit-squares painting, Darkness combat penalties)
## picks this up automatically with no changes needed there. Not
## exported: like riposte_uses_this_round/drilled_beside_ally above,
## this is live per-encounter state that's never meaningful to persist
## across a save (an encounter's own Round count resets on reload
## anyway, so a saved "N Rounds left" would already be stale).
var light_spell_rounds_remaining: int = 0

## Per the follow-up request ("light (petty spell) should be 20 yards by
## default and should have the same bright/dim/out options as lamps"):
## independent of light_mode above (that field is for an EQUIPPED item —
## a character could have a lit Lantern AND an active Light spell at
## once, each with its own brightness setting). "bright" | "dim" | "out",
## deliberately spelled out rather than reusing lamps' own "on"/"low"/
## "off" strings, matching the exact button labels this is displayed
## with in the Magic / Prayers action column. "out" mirrors a lamp's
## "off": the spell keeps ticking down every Round exactly as normal
## (see tick_active_buffs() below) — a caster hooding the light doesn't
## end the spell early, just its glow — it simply emits no light while
## set this way. Reset to "bright" every time the spell is (re)cast (see
## field_encounter_screen.gd's _apply_cast_spell_outcome()), matching
## the duration counter's own "recasting always refreshes" rule.
var light_spell_mode: String = "bright"

## Per the follow-up request ("allow the light spell to be used on the
## overworld map the same way that lamp is used with the L button... use
## spell duration as normal and recast automatically if duration
## expires, it will just work forever"): light_spell_rounds_remaining
## above is spent by exactly 1 per Round in combat (tick_active_buffs()),
## but the overworld has no Rounds — Overworld._on_player_moved() ticks
## it by real elapsed minutes instead (GameState.minutes_per_tile_
## fraction(), the exact same fractional-minutes-per-tile-step approach
## light_fuel_minutes/tick_light_fuel() already uses), so this
## accumulates the leftover fraction between tile steps until a whole
## minute has genuinely passed. Purely a ticking aid — never exported,
## never meaningful on its own.
var light_spell_minutes_accum: float = 0.0

## Ticks the Light spell's own duration down by `minutes` of real
## overworld time — see light_spell_minutes_accum's own comment for why
## this exists alongside tick_active_buffs()'s per-Round version rather
## than reusing it outright (that also ticks combat-only buffs like
## flaming_sword_rounds_remaining, which have no business running down
## while just walking around town). A no-op while the spell isn't
## active at all. Per the explicit request ("recast automatically if
## duration expires... it will just work forever"): once enough real
## minutes have accumulated to exhaust the counter, this immediately
## refreshes it back to a fresh full Willpower value — exactly the same
## "recasting always refreshes, never stacks" rule an explicit recast
## already follows (see field_encounter_screen.gd's _apply_cast_spell_
## outcome()) — rather than letting the light actually go out, so an
## overworld caster who's turned it on never has to think about it
## again. Deliberately does NOT touch light_spell_mode — bright stays
## bright, dim stays dim, across every automatic refresh.
func tick_light_spell_duration(minutes: float) -> void:
	if light_spell_rounds_remaining <= 0:
		return
	light_spell_minutes_accum += minutes
	while light_spell_minutes_accum >= 1.0:
		light_spell_minutes_accum -= 1.0
		light_spell_rounds_remaining -= 1
		if light_spell_rounds_remaining <= 0:
			light_spell_rounds_remaining = max(get_effective_characteristic_value("willpower"), 1)

## Flaming Sword of Rhuin (Lore of Fire): a temporary weapon-enchant
## spell, per the explicit request ("wire it up... only allow casting
## it on swords, and temporarily replace the sword's normal stats").
## While this is > 0, get_equipped_weapon() below substitutes
## flaming_sword_weapon for whatever's actually equipped, so every
## existing combat consumer (Attack buttons, damage math, weapon-
## dependent Talent checks) picks up the enchant automatically with no
## changes needed there — same "one substitution point, everything else
## just reads through it" approach light_spell_rounds_remaining already
## established above. Ticks down once per Round in tick_active_buffs()
## below, same call site/timing as every other timed combat effect;
## reaching 0 ends the enchant with no further action needed, since
## get_equipped_weapon() simply stops returning the override. Not
## exported — live per-encounter state, same reasoning as
## light_spell_rounds_remaining's own comment just above.
var flaming_sword_rounds_remaining: int = 0
## Which equipped_weapon item name this enchantment is actually bound
## to — the override only applies while still holding this exact item,
## so switching to a different weapon mid-Duration correctly drops the
## enchant (it travels with the blade, not the character).
var flaming_sword_item_name: String = ""
## The actual enchanted clone (a real .duplicate(true), never the
## shared weapon_db original — see field_encounter_screen.gd's own
## "Flaming Sword of Rhuin" cast-outcome branch for how this gets
## built).
var flaming_sword_weapon: WeaponDefinition = null

## Sigmar's Fiery Hammer (Miracle): per the explicit request ("should
## rename the weapon while its active"), while the wielder is actually
## holding a Warhammer AND the "Sigmar's Fiery Hammer" active_buffs
## entry (see add_timed_buff()) is still live, get_equipped_weapon()
## below substitutes fiery_hammer_weapon for the real weapon, same
## substitution-point pattern flaming_sword_weapon establishes above.
## Deliberately does NOT carry its own rounds-remaining counter the way
## flaming_sword_rounds_remaining does — this rename is tied directly
## to the SAME active_buffs entry the Damage bonus already reads (see
## has_active_buff()/get_active_damage_bonus() below), so Overcast's
## Duration column (which rescales that one active_buffs entry's own
## "rounds_remaining" in place) can never desync a second, independent
## timer from the buff's real Duration. Only the clone's weapon_name
## changes — never its Damage/Qualities, since the +Fellowship Bonus
## Damage is already granted separately and generically through the
## active_buffs/get_active_damage_bonus(weapon) mechanism.
var fiery_hammer_item_name: String = ""
var fiery_hammer_weapon: WeaponDefinition = null

## The Light spell's own light radius, in yards, while `light_spell_mode`
## is "bright" — bumped from the old Candle-radius match (10) up to
## match a Lantern's own bright radius per the same follow-up request,
## since the spell now offers a genuine Lantern-style bright/dim choice
## rather than a single fixed candle-equivalent glow. LIGHT_SPELL_
## RADIUS_TILES_LOW is the "dim" radius, using the exact same 2:1 bright-
## to-dim ratio Lantern/Storm Lantern's own light_radius_tiles/
## light_radius_tiles_low pair already establishes (20/10) — "out" is
## radius 0, handled directly in get_active_light_radius_tiles() below
## rather than a third constant. Deliberately NOT the Channelling-Test-
## gated "increase to Lantern / decrease to Candle" option the spell's
## card text also offers — that's a documented gap, left for a future
## request rather than assumed here.
const LIGHT_SPELL_RADIUS_TILES := 20
const LIGHT_SPELL_RADIUS_TILES_LOW := 10

## Per the follow-up request ("lantern need to be held on either main
## or off hand, remove the extra lantern slot"): there's no dedicated
## light-source slot anymore — a Lantern/Candle/etc is held exactly
## like a weapon, occupying equipped_weapon (main hand) or
## equipped_offhand (off hand). Checks main hand first, matching
## get_equipped_weapon()'s own precedence for "what's this character
## primarily wielding."
func get_equipped_light_item() -> ItemDefinition:
	if GameData == null or GameData.item_db == null:
		return null
	var main := GameData.item_db.find_by_name(equipped_weapon)
	if main != null and main.light_radius_tiles > 0:
		return main
	var off := GameData.item_db.find_by_name(equipped_offhand)
	if off != null and off.light_radius_tiles > 0:
		return off
	return null

## True only while there's genuinely something to show for it: a real
## light source equipped, switched on (any mode but "off"), and — for
## an oil source — actual fuel left. Does NOT consider time of day or
## location; that's Overworld._light_source_effective()'s job, kept
## separate so the character's own toggle state never silently flips
## itself off just because the sun came up.
func has_active_light_source() -> bool:
	## Light (Petty spell) — see light_spell_rounds_remaining's own
	## comment: functions as its own light source, entirely independent
	## of whatever's (or isn't) equipped/switched on below. "out" (see
	## light_spell_mode's own comment) means the spell is still running
	## but genuinely emits nothing right now, same as a lamp switched
	## "off" — not a light source while set that way.
	if light_spell_rounds_remaining > 0 and light_spell_mode != "out":
		return true
	if light_mode == "off":
		return false
	var item := get_equipped_light_item()
	if item == null or item.light_radius_tiles <= 0:
		return false
	if item.light_requires_oil and light_fuel_minutes <= 0.0:
		return false
	return true

## The effective radius (in tiles) for whatever's currently switched
## on — 0 if nothing is. Falls back to the normal radius if "low" is
## somehow set on a source with no dedicated low radius, rather than
## going dark. Per the Light spell addition above: the spell and an
## equipped item-based source are independent light sources that can
## both be active at once (e.g. a lit Lantern AND an active Light
## spell) — this returns whichever reaches further, rather than one
## silently overriding the other.
func get_active_light_radius_tiles() -> int:
	if not has_active_light_source():
		return 0
	var best := 0
	if light_spell_rounds_remaining > 0 and light_spell_mode != "out":
		best = LIGHT_SPELL_RADIUS_TILES_LOW if light_spell_mode == "dim" else LIGHT_SPELL_RADIUS_TILES
	if light_mode != "off":
		var item := get_equipped_light_item()
		if item != null and item.light_radius_tiles > 0 and not (item.light_requires_oil and light_fuel_minutes <= 0.0):
			var item_radius: int = item.light_radius_tiles_low if (light_mode == "low" and item.light_radius_tiles_low > 0) else item.light_radius_tiles
			best = max(best, item_radius)
	return best

## Burns down whatever's currently lit by `minutes` of game time (at
## half rate while "low") — called only while the light is actually
## effective (see Overworld._light_source_effective()), so daylight
## hours spent with a light source switched "on" but not doing
## anything don't waste fuel. Two independent kinds of source:
## - Oil-requiring (Lantern, Storm Lantern, Davrich Lamp): draws down
##   light_fuel_minutes: light_fuel_minutes, and on hitting empty,
##   auto-reloads from a spare Lamp Oil in inventory if there is one;
##   otherwise extinguishes it (light_mode = "off") and returns true.
## - Self-fuel (Candle): the equipped unit itself burns down instead of
##   a separate fuel item. On hitting empty, that one spent unit is
##   erased from inventory; if another copy is still in stock, it's lit
##   fresh (silently, same as an oil auto-reload) — otherwise the
##   character is out, so equipped_weapon/equipped_offhand is cleared
##   (mirroring damage_weapon()'s own "nothing left to point at" rule
##   for a fully destroyed weapon) and light_mode = "off", returning
##   true so the caller can show a one-time "burned out" notice.
## A source with neither set burns indefinitely — returns false always.
func tick_light_fuel(minutes: float) -> bool:
	if light_mode == "off":
		return false
	var item := get_equipped_light_item()
	if item == null:
		return false
	if item.light_requires_oil:
		var burn_rate: float = 1.0 if light_mode == "on" else 0.5
		light_fuel_minutes -= minutes * burn_rate
		if light_fuel_minutes > 0.0:
			return false
		light_fuel_minutes = 0.0
		if inventory.has("Lamp Oil"):
			inventory.erase("Lamp Oil")
			light_fuel_minutes = LAMP_OIL_MINUTES
			return false
		light_mode = "off"
		return true
	if item.light_self_fuel_minutes > 0.0:
		var burn_rate2: float = 1.0 if light_mode == "on" else 0.5
		light_fuel_minutes -= minutes * burn_rate2
		if light_fuel_minutes > 0.0:
			return false
		light_fuel_minutes = 0.0
		inventory.erase(item.item_name)   ## this one unit is spent
		if inventory.has(item.item_name):
			light_fuel_minutes = item.light_self_fuel_minutes   ## light the next one from stock
			return false
		if equipped_weapon == item.item_name:
			equipped_weapon = ""
		if equipped_offhand == item.item_name:
			equipped_offhand = ""
		light_mode = "off"
		return true
	return false

## Accumulates when a Blessed character violates their deity's Cult
## Strictures; makes Wrath of the Gods rolls (see PrayerResolver) worse,
## and is reduced by 1 (minimum 0) each time Wrath is actually rolled
## (p.217-218). No upper limit.
@export var sin_points: int = 0

## Spells/Prayers this character has actually learned/memorised (names
## into GameData.spell_db / prayer_db) — distinct from the full
## compendium, which any character can browse but not necessarily cast.
@export var known_spells: Array[String] = []
@export var known_prayers: Array[String] = []

## --- Derived value helpers -------------------------------------------------

## Corruption Threshold (p.184): Willpower Bonus + Toughness Bonus.
## Corruption Points exceeding this triggers a Mutation roll — see
## CorruptionResolver.check_and_apply_threshold().
## Pure Soul (per its actual book text: "you may gain extra Corruption
## points equal to your level of Pure Soul before having to Test to see
## if you become corrupt") raises this Threshold by the character's
## Pure Soul rank — it does not modify the Test itself.
func get_corruption_threshold() -> int:
	return get_characteristic_bonus("willpower") + get_characteristic_bonus("toughness") + get_talent_rank("Pure Soul")

## Luck (p.??, per the book's own text — corrected from an earlier,
## wrong "reroll one failed Test per session" implementation this
## project shipped by mistake): "Your maximum Fortune Points now equal
## your current Fate points plus the number of times you've taken Luck."
## Not a separate reroll mechanic at all — every rank of Luck just adds
## +1 to the normal "max Fortune = current Fate" cap. Every place that
## resets fortune_points to the start-of-session/day value (Camp,
## death/respawn, Overworld's own daily reset) should route through this
## instead of reading fate_points directly.
func get_max_fortune_points() -> int:
	return fate_points + get_talent_rank("Luck")

func get_characteristic_bonus(key: String) -> int:
	var bonus := int(floor(get_effective_characteristic_value(key) / 10.0))
	## Frenzy (p.190): "you gain a bonus of +1 Strength Bonus, such is
	## your ferocity" — a bonus to the derived Strength Bonus itself,
	## not a raw Strength increase (which would also affect other
	## things Strength drives, like Wounds via Hardy).
	if key == "strength" and conditions.has("Frenzy"):
		bonus += 1
	return bonus

## --- Money (p.288-289) -----------------------------------------------
## "The Empire's coins are most commonly minted in 3 denominations:
## Brass Pennies (d), Silver Shillings (/), and Gold Crowns (GC)."
## 12 Brass Pennies = 1 Silver Shilling; 20 Silver Shillings = 1 Gold
## Crown (240 Brass Pennies), following the book's own worked example
## ("6 shillings and 8 pence... 80d... one third of a gold crown").

const PENNIES_PER_SHILLING := 12
const SHILLINGS_PER_CROWN := 20
const PENNIES_PER_CROWN := PENNIES_PER_SHILLING * SHILLINGS_PER_CROWN

func get_total_pennies() -> int:
	return brass_pennies + silver_shillings * PENNIES_PER_SHILLING + gold_crowns * PENNIES_PER_CROWN

## Adds pennies to the purse, then normalises back into GC/SS/BP so the
## display (and any future counting-every-coin bookkeeping) stays tidy
## rather than accumulating in whichever denomination happened to be
## added last.
func add_pennies(amount: int) -> void:
	var total := get_total_pennies() + amount
	_set_from_pennies(total)

## Returns false (and changes nothing) if the character can't afford it.
func spend_pennies(amount: int) -> bool:
	if get_total_pennies() < amount:
		return false
	_set_from_pennies(get_total_pennies() - amount)
	return true

func _set_from_pennies(total: int) -> void:
	total = max(total, 0)
	gold_crowns = int(total / PENNIES_PER_CROWN)
	total -= gold_crowns * PENNIES_PER_CROWN
	silver_shillings = int(total / PENNIES_PER_SHILLING)
	total -= silver_shillings * PENNIES_PER_SHILLING
	brass_pennies = total

## --- Encumbrance (p.293) -----------------------------------------------
## "The number of Encumbrance points you can carry without penalty is
## determined by your Strength Bonus + Toughness Bonus." Worn armour and
## the equipped weapon both count, on top of everything in inventory.
##
## Money's own weight, per the request: a flat 0.005 Enc per physical
## coin, regardless of denomination — not the book's own value-
## converted "1 per 200 coins" rate, which made even a modest starting
## purse contribute a surprisingly large chunk of Enc on its own. Coin
## count (not coin value) is what matters here, so 3 Gold Crowns and 3
## Brass Pennies weigh exactly the same: 6 coins × 0.005. Tracked as a
## real float internally so the fraction isn't lost to rounding until
## display time — see the request's own "don't show the fractions in
## the UI," handled in character_menu_screen.gd, not here.

const COIN_ENCUMBRANCE_PER_COIN := 0.005

## Beasts of Burden (p.294) will need a totally different capacity
## rule someday — draft animals ignore the SB+TB formula entirely and
## instead use a fixed Encumbrance capacity taken from their own stat
## block ("Encumbrance points for mules, horses, carts and wagons are
## listed in their descriptions"). Per the request, not building any
## Mount/Wagon system yet — but this override is a real, functional
## hook for that future work: leave it at -1 (unset) for every
## character that exists today, since SB+TB is correct for all of
## them, and a future mount/wagon Character (or whatever entity ends
## up representing one) can just set this directly instead of the
## formula needing to change at all.
@export var carrying_capacity_override: int = -1

## Shared by-slot-name accessors for the three Container equip slots
## above — every screen that equips/unequips/displays a container goes
## through these two rather than touching equipped_container_back/
## waist/shoulder directly, so a bad/unknown slot name (there
## shouldn't be one — ItemDefinition.container_slot is itself an
## @export_enum limited to these three plus "") is a safe no-op/empty
## read instead of silently doing nothing to the wrong field.
func get_equipped_container(slot: String) -> String:
	match slot:
		"Back": return equipped_container_back
		"Waist": return equipped_container_waist
		"Shoulder": return equipped_container_shoulder
		_: return ""

func set_equipped_container(slot: String, item_name: String) -> void:
	match slot:
		"Back": equipped_container_back = item_name
		"Waist": equipped_container_waist = item_name
		"Shoulder": equipped_container_shoulder = item_name

## Per the "packs and containers" request: "these containers when worn/
## equipped will add their Carries value minus their worn Enc value to
## the character's maximum Enc" — worn Enc is the same Worn Items -1
## discount (floored at 0) get_current_encumbrance() already applies to
## worn armour, applied here identically to whichever container is
## worn in each of the three slots.
func get_container_capacity_bonus() -> int:
	var bonus := 0
	if GameData == null or GameData.item_db == null:
		return bonus
	for slot in ["Back", "Waist", "Shoulder"]:
		var container_name: String = get_equipped_container(slot)
		if container_name == "":
			continue
		var it: ItemDefinition = GameData.item_db.find_by_name(container_name)
		if it != null:
			bonus += it.container_capacity - max(0, it.encumbrance - 1)
	return bonus

func get_carrying_capacity() -> int:
	if carrying_capacity_override >= 0:
		return carrying_capacity_override
	return get_characteristic_bonus("strength") + get_characteristic_bonus("toughness") + get_container_capacity_bonus()

func get_current_encumbrance() -> float:
	var total := 0.0
	if GameData == null:
		return total
	if equipped_weapon != "" and GameData.weapon_db != null:
		var w: WeaponDefinition = GameData.weapon_db.find_by_name(equipped_weapon)
		if w != null:
			## Lightweight (p.301): "Reduce Encumbrance points by 1" —
			## on top of, not instead of, the Worn Items discount armour
			## gets below (a weapon isn't "worn," so it has no such
			## discount to stack with).
			var lw_discount := 1 if ItemQualityRules.has(w.item_qualities, "Lightweight") else 0
			total += max(0, w.encumbrance - lw_discount)
	if equipped_offhand != "" and GameData.weapon_db != null:
		var ow: WeaponDefinition = GameData.weapon_db.find_by_name(equipped_offhand)
		if ow != null:
			var lw_discount2 := 1 if ItemQualityRules.has(ow.item_qualities, "Lightweight") else 0
			total += max(0, ow.encumbrance - lw_discount2)
	if GameData.armour_db != null:
		for armour_name in equipped_armour:
			var a: ArmourDefinition = GameData.armour_db.find_by_name(armour_name)
			if a != null:
				## Worn Items (p.293): "armour, clothing, and jewellery
				## all have their Encumbrance dropped by 1, which often
				## means they count as Encumbrance 0 when worn." This
				## project only separately tracks worn armour (no
				## distinct clothing/jewellery item types exist), so
				## the discount is applied here only, per equipped
				## piece — floored at 0 so a 0-1 result never goes
				## negative. Lightweight (p.301) stacks a further -1 on
				## top of that Worn Items discount.
				var lw_discount3 := 1 if ItemQualityRules.has(a.item_qualities, "Lightweight") else 0
				total += max(0, a.encumbrance - 1 - lw_discount3)
	if GameData.item_db != null:
		## Per the "packs and containers" request: a worn Container gets
		## the exact same Worn Items -1 discount as worn armour, above —
		## but unlike armour (a genuinely separate database from
		## item_db), a Container is itself an ItemDefinition sitting
		## right here in `inventory` alongside every other Trapping, so
		## it'd otherwise get counted a second time, at full price, by
		## the generic loop below. `worn_container_copies` tracks how
		## many of each equipped slot's own item name still owe the
		## discount — only that many physical copies from `inventory`
		## get it; any additional spare, unequipped copies of the same
		## name still count at full Enc, same as a spare unequipped
		## Sword/armour piece would.
		var worn_container_copies: Dictionary = {}
		for slot in ["Back", "Waist", "Shoulder"]:
			var worn_name: String = get_equipped_container(slot)
			if worn_name != "":
				worn_container_copies[worn_name] = int(worn_container_copies.get(worn_name, 0)) + 1
		for item_name in inventory:
			var it: ItemDefinition = GameData.item_db.find_by_name(item_name)
			if it != null:
				if int(worn_container_copies.get(item_name, 0)) > 0:
					total += max(0, it.encumbrance - 1)
					worn_container_copies[item_name] = int(worn_container_copies[item_name]) - 1
				else:
					total += it.encumbrance
	total += float(gold_crowns + silver_shillings + brass_pennies) * COIN_ENCUMBRANCE_PER_COIN
	return total

## Per the request: breaks the same total get_current_encumbrance()
## computes down into named categories (Weapons/Armour/Carried Items/
## Coin), rather than a single opaque number — built by mirroring that
## function's own logic exactly, category by category, so the four
## values here always sum to the same total that function returns.
## Only categories that actually contribute anything are included, so
## a character with no coin (for instance) doesn't show a pointless
## "Coin: 0" row.
func get_encumbrance_breakdown() -> Dictionary:
	var breakdown := {}
	if GameData == null:
		return breakdown
	var weapons_enc := 0
	if equipped_weapon != "" and GameData.weapon_db != null:
		var w: WeaponDefinition = GameData.weapon_db.find_by_name(equipped_weapon)
		if w != null:
			weapons_enc += w.encumbrance
	if equipped_offhand != "" and GameData.weapon_db != null:
		var ow: WeaponDefinition = GameData.weapon_db.find_by_name(equipped_offhand)
		if ow != null:
			weapons_enc += ow.encumbrance
	if weapons_enc > 0:
		breakdown["Weapons"] = weapons_enc

	var armour_enc := 0
	if GameData.armour_db != null:
		for armour_name in equipped_armour:
			var a: ArmourDefinition = GameData.armour_db.find_by_name(armour_name)
			if a != null:
				armour_enc += max(0, a.encumbrance - 1)   ## Worn Items -1 discount, matching get_current_encumbrance() above
	if armour_enc > 0:
		breakdown["Armour"] = armour_enc

	var items_enc := 0
	var containers_enc := 0
	if GameData.item_db != null:
		## Same worn-copy tracking as get_current_encumbrance() above, so
		## a worn container's own Enc lands in its own "Containers" row
		## (at the discounted worn value) rather than double-counting
		## into "Carried Items" at full price.
		var worn_container_copies: Dictionary = {}
		for slot in ["Back", "Waist", "Shoulder"]:
			var worn_name: String = get_equipped_container(slot)
			if worn_name != "":
				worn_container_copies[worn_name] = int(worn_container_copies.get(worn_name, 0)) + 1
		for item_name in inventory:
			var it: ItemDefinition = GameData.item_db.find_by_name(item_name)
			if it != null:
				if int(worn_container_copies.get(item_name, 0)) > 0:
					containers_enc += max(0, it.encumbrance - 1)
					worn_container_copies[item_name] = int(worn_container_copies[item_name]) - 1
				else:
					items_enc += it.encumbrance
	if items_enc > 0:
		breakdown["Carried Items"] = items_enc
	if containers_enc > 0:
		breakdown["Containers"] = containers_enc

	var coin_enc: float = float(gold_crowns + silver_shillings + brass_pennies) * COIN_ENCUMBRANCE_PER_COIN
	if coin_enc > 0:
		breakdown["Coin"] = coin_enc

	return breakdown

## The Encumbrance penalty table (p.293), as a simple lookup rather than
## four separate booleans. `tier` is a label for display; the numeric
## fields are actually applied now — see get_movement() and
## get_effective_characteristic_value() below, and
## _run_travel_day_loop() in overworld.gd for travel_fatigue.
## `movement_floor`/`agility_floor` are the book's own "(min: 3)" /
## "(min 10)" clauses — a floor on the RESULTING value after the
## penalty is applied, not a cap on the penalty itself. -1 means "no
## floor at this tier," per the book only actually specifying one for
## Movement at both middle tiers and for Agility at Heavily Encumbered
## only (not at plain Encumbered).
## Ordered None -> Encumbered -> Heavily Encumbered -> Overloaded, so the
## calling function below can pick a tier by INDEX — needed for
## Practical armour's own -1 tier-index shift.
const _ENCUMBRANCE_TIERS: Array[Dictionary] = [
	{"tier": "None", "movement_penalty": 0, "movement_floor": -1, "agility_penalty": 0, "agility_floor": -1, "travel_fatigue": 0, "immobile": false},
	{"tier": "Encumbered", "movement_penalty": 1, "movement_floor": 3, "agility_penalty": 10, "agility_floor": -1, "travel_fatigue": 1, "immobile": false},
	{"tier": "Heavily Encumbered", "movement_penalty": 2, "movement_floor": 2, "agility_penalty": 20, "agility_floor": 10, "travel_fatigue": 2, "immobile": false},
	## "More than 3x: You're not moving." — get_movement() reads
	## `immobile` directly for this tier rather than movement_penalty/
	## movement_floor, so those are just 0/-1 here as inert placeholders.
	{"tier": "Overloaded", "movement_penalty": 0, "movement_floor": -1, "agility_penalty": 0, "agility_floor": -1, "travel_fatigue": 0, "immobile": true},
]

func _has_practical_armour_equipped() -> bool:
	if GameData == null or GameData.armour_db == null:
		return false
	for armour_name in equipped_armour:
		var a: ArmourDefinition = GameData.armour_db.find_by_name(armour_name)
		if a != null and ItemQualityRules.has(a.item_qualities, "Practical"):
			return true
	return false

func get_encumbrance_penalty() -> Dictionary:
	var capacity: int = max(get_carrying_capacity(), 1)
	var current := get_current_encumbrance()
	var tier_index := 0
	if current <= capacity:
		tier_index = 0
	elif current <= capacity * 2:
		tier_index = 1
	elif current <= capacity * 3:
		tier_index = 2
	else:
		tier_index = 3
	## Practical (p.301, armour): "any penalties for wearing it are
	## reduced by one level (for example from -30 to -20)." This
	## project has no armour-specific penalty separate from the
	## generic Encumbrance-penalty table above (armour's Encumbrance
	## just feeds into get_current_encumbrance() like everything else
	## carried) — reducing the WHOLE Encumbrance-penalty tier by one
	## step while wearing a Practical piece is the closest real hook
	## this codebase has for that rule, and directly mirrors the
	## book's own worked example (a full tier step, e.g. Heavily
	## Encumbered's -20 Agility down to Encumbered's -10).
	if tier_index > 0 and _has_practical_armour_equipped():
		tier_index -= 1
	return _ENCUMBRANCE_TIERS[tier_index]

func get_skill_value(skill_def: SkillDefinition, specialisation: String = "") -> int:
	var char_value: int = get_effective_characteristic_value(skill_def.linked_characteristic)
	var name := skill_def.display_name(specialisation)
	var advances: int = skill_advances.get(name, 0)
	return char_value + advances

## Per the request: Basic skills can always be attempted, even
## completely untrained (get_skill_value() above already handles that
## correctly, falling back to the bare characteristic). Advanced
## skills genuinely cannot be attempted at all unless the character
## has actually learned them — skill_advances.get(name, 0) alone can't
## tell "trained at 0 advances" apart from "never trained," since both
## return 0, so this checks the key's own presence in the dictionary
## instead, not the value.
func has_skill(skill_def: SkillDefinition, specialisation: String = "") -> bool:
	if not skill_def.is_advanced:
		return true
	return skill_advances.has(skill_def.display_name(specialisation))

func get_movement() -> int:
	var base: int = monster_movement if monster_movement >= 0 else (race.movement if race else 4)
	base += creature_movement_bonus
	base += get_active_movement_bonus()
	if has_talent("Fleet Footed"):
		base += 1
	## Flee! (Up in Arms, p.140): Movement counts as 1 higher while
	## Fleeing or acting as the Quarry in a pursuit. Not automated here
	## since it depends on situation — callers handling flee/pursuit
	## logic should check `has_talent("Flee!")` and add 1 themselves.
	## Crippled Leg (a real functional effect from a leg-amputation
	## Critical Wound, p.83-86's various "leg is useless"/"leg never
	## works again" results): Movement is genuinely halved, not just a
	## flavour Condition, until the wound is healed.
	if conditions.has("Crippled Leg"):
		base = max(1, base / 2)
	## Encumbrance (p.293), applied last on top of every adjustment
	## above — "Movement reduction... incurred from Encumbrance stacks
	## with any Armour penalties." Overloaded (more than 3x capacity)
	## means "you're not moving" outright, so every other adjustment
	## above becomes moot in that case; this is the single choke point
	## every mover in the game (overworld free-walk, World Map travel,
	## combat's per-turn budget, monster AI) already reads through, so
	## one change here reaches all of them.
	var enc := get_encumbrance_penalty()
	if enc["immobile"]:
		return 0
	var pre_encumbrance := base
	base -= int(enc["movement_penalty"])
	var floor_val: int = int(enc["movement_floor"])
	## The floor only lifts a value THAT ENCUMBRANCE ITSELF just pushed
	## under it — it's not a guarantee that overrides an unrelated,
	## already-lower value (e.g. Crippled Leg having already halved
	## Movement to 1 stays at 1; Encumbrance's own floor doesn't un-cripple it).
	if floor_val > 0 and pre_encumbrance >= floor_val:
		base = max(base, floor_val)
	return max(base, 0)

## The Movement value before Crippled Leg's halving or Encumbrance's
## reduction — i.e. what get_movement() would return if neither
## temporary effect were currently active. Exists so callers that just
## want to know "is Movement currently reduced" (the Character Menu's
## red-text flagging, see character_menu_screen.gd's _rebuild_header())
## don't have to duplicate get_movement()'s own modifier chain.
func get_unmodified_movement() -> int:
	var base: int = monster_movement if monster_movement >= 0 else (race.movement if race else 4)
	base += creature_movement_bonus
	base += get_active_movement_bonus()
	if has_talent("Fleet Footed"):
		base += 1
	return base

## Per the book's own Movement table (p.164): Walk = Movement x2, Run =
## Movement x4 (e.g. Movement 4 -> Walk 8, Run 16) -- this previously
## multiplied by 3/6 instead, overstating both by 50%.
func get_walk_distance() -> int:
	return get_movement() * 2

func get_run_distance() -> int:
	return int(round(get_movement() * 4 * get_stride_multiplier()))

## Stride (Creature Trait, p.343): "Multiply Run Movement by 1.5 when
## Running." Deliberately NOT folded into get_movement() itself (which
## would also inflate get_walk_distance() above -- the book's own rule
## only touches Run, not Walk) or into apply_stat_modifiers()'s existing
## stat_mod:* tag handling (that path is add-only and applied once at
## creature-creation time, not a fit for a multiplicative, per-context
## Run value). Every call site that represents this project's own
## notion of a "Run" — get_run_distance() above (the non-combat
## character-sheet figure), field_encounter_screen.gd's combat Move/Run
## pool and Sprint bonus (both explicitly documented as covering "the
## full old Run range"), and monster AI's own per-turn movement cap
## (its one flat Movement-squares budget, the closest equivalent this
## simplified AI has to "Running") — multiplies by this instead of
## hand-rolling the same has_creature_trait("Stride") check everywhere.
func get_stride_multiplier() -> float:
	return 1.5 if has_creature_trait("Stride") else 1.0

func has_talent(talent_name: String) -> bool:
	return talents_taken.has(talent_name)

func get_talent_rank(talent_name: String) -> int:
	return talents_taken.get(talent_name, 0)

## Craftsman (Trade) (p.135): "Add the associated Trade Skill to any
## Career you enter. If the Trade Skill is already in your Career, you
## may instead purchase the Skill for 5 XP fewer per Advance." Each
## resolved "Craftsman (X)" entry in talents_taken names one Trade
## specialisation this unlocks/discounts -- a character can hold it
## more than once (Max: Dexterity Bonus) for different trades. Used by
## Advancement.unlocked_skills() (to grant the Trade regardless of
## Career) and Advancement.purchase_skill_advance() (for the discount).
func get_craftsman_trades() -> Array[String]:
	var trades: Array[String] = []
	for key in talents_taken.keys():
		if key.begins_with("Craftsman (") and key.ends_with(")"):
			trades.append(key.substr(len("Craftsman ("), key.length() - len("Craftsman (") - 1))
	return trades

## Ambidextrous (Max: 2): "You only suffer a penalty of -10 to Tests
## relying solely on your secondary hand, not -20. If you have this
## Talent twice, you suffer no penalty at all." Centralised here so
## every off-hand-penalty call site (the main off-hand attack, the
## Dual Wielder follow-up, the preview number, the off-hand Parry
## button/note, and get_defense_modifiers()) applies the exact same
## rank-scaled number rather than each re-deriving it (a previous pass
## had every site independently checking has_talent() — presence only,
## so rank 1 already fully removed the penalty instead of merely
## halving it).
func get_offhand_penalty() -> int:
	match get_talent_rank("Ambidextrous"):
		0:
			return -20
		1:
			return -10
		_:
			return 0

## Creature Traits (p.338-343): checks by base name, so
## has_creature_trait("Bite") matches a stored "Bite (5)" entry — the
## same base-name matching TalentDatabase.find_by_name() already does.
func has_creature_trait(base_name: String) -> bool:
	for t in creature_traits:
		if t == base_name or t.begins_with(base_name + " ("):
			return true
	return false

## Per the request: the Size Creature Trait (p.341) uses a text
## qualifier ("Size (Enormous)"), not a number, so it needs its own
## step lookup rather than get_creature_trait_rating() below (which
## only parses numeric qualifiers). Returns the step index (0=Tiny
## through 6=Monstrous); a character with no Size Trait at all is
## Average (3), the game's own default assumption — "roughly human
## sized" per the book's own wording.
const SIZE_STEPS: Array[String] = ["Tiny", "Little", "Small", "Average", "Large", "Enormous", "Monstrous"]
func get_size_step() -> int:
	for t in creature_traits:
		if t.begins_with("Size ("):
			var inner := t.substr(6, t.length() - 7)
			var idx := SIZE_STEPS.find(inner)
			if idx >= 0:
				return idx
	return 3   ## Average — no Size Trait means human-sized, per the book

## Per the request: bigger creatures get bigger battle-grid footprints
## — Large=2x2, Enormous=3x3, Monstrous=4x4 — everything Average and
## below stays the traditional single square. Indexed by get_size_step()
## (0=Tiny .. 6=Monstrous).
const FOOTPRINT_BY_SIZE_STEP: Array[int] = [1, 1, 1, 1, 2, 3, 4]
func get_footprint_size() -> int:
	return FOOTPRINT_BY_SIZE_STEP[get_size_step()]

## The numeric Rating parsed out of a stored "Name (Rating)" trait
## entry — e.g. get_creature_trait_rating("Bite") reads 5 out of a
## stored "Bite (5)". Returns 0 if the trait isn't present or its
## qualifier isn't numeric (e.g. "Hatred (Orcs)" — use
## has_creature_trait() plus the raw string for those instead).
func get_creature_trait_rating(base_name: String) -> int:
	for t in creature_traits:
		if t.begins_with(base_name + " ("):
			var inner := t.substr(base_name.length() + 2, t.length() - base_name.length() - 3)
			if inner.is_valid_int():
				return inner.to_int()
	return 0

## The god this character's Bless Talent is locked to, if any — reads
## the specific "Bless (God)" entry left in talents_taken by the (Any)
## qualifier picker. Empty string if no Bless Talent taken.
## Same pattern as get_bless_god()/get_invoke_god() — reads which Lore
## the character's Arcane Magic Talent covers, rather than storing it
## separately. "Under normal circumstances, you may not learn more
## than one Arcane Magic (Lore) Talent" (p.147), so there's only ever
## one to find.
func get_arcane_lore() -> String:
	for key in talents_taken.keys():
		if key.begins_with("Arcane Magic ("):
			return key.trim_prefix("Arcane Magic (").trim_suffix(")")
	return ""

## Same pattern as get_arcane_lore(), for the Chaos Magic (Lore) Talent
## (p.134): "you may not learn more than one Lore of Chaos Magic" — so,
## like Arcane Magic, there's only ever one to find.
func get_chaos_lore() -> String:
	for key in talents_taken.keys():
		if key.begins_with("Chaos Magic ("):
			return key.trim_prefix("Chaos Magic (").trim_suffix(")")
	return ""

func get_bless_god() -> String:
	for key in talents_taken.keys():
		if key.begins_with("Bless ("):
			return key.trim_prefix("Bless (").trim_suffix(")")
	return ""

## Same as get_bless_god() but for Invoke — "Blessings and Miracles must
## be from the same god," so both should normally agree, but this is
## tracked independently since a character could in principle have one
## without the other.
func get_invoke_god() -> String:
	for key in talents_taken.keys():
		if key.begins_with("Invoke ("):
			return key.trim_prefix("Invoke (").trim_suffix(")")
	return ""

## Blessings are auto-granted, not purchased — "a character with the
## Bless Talent receives all six Blessings for their cult" (p.221) —
## so this is computed fresh from the Bless Talent's god rather than
## stored. Combined with known_prayers (which holds purchased Miracles)
## by the caller for the full castable list.
func get_known_blessings() -> Array[String]:
	var god := get_bless_god()
	if god == "" or GameData == null or GameData.prayer_db == null:
		return []
	return GameData.prayer_db.get_blessings_for_god(god)

## The full list of prayers this character can actually cast right now:
## auto-granted Blessings plus whatever Miracles they've purchased
## (known_prayers). Use this instead of known_prayers directly anywhere
## the player picks a prayer to cast.
func get_effective_known_prayers() -> Array[String]:
	var result: Array[String] = []
	for b in get_known_blessings():
		result.append(b)
	for p in known_prayers:
		if not result.has(p):
			result.append(p)
	return result

func get_characteristic_advance_count(key: String) -> int:
	return characteristic_advances.get(key, 0)

## --- Combat helpers -----------------------------------------------------

func has_condition(condition_name: String) -> bool:
	return conditions.has(condition_name)

func add_condition(condition_name: String, stacks: int = 1) -> void:
	## Per the request: Prone can't stack — it's a binary state, not
	## something with a meaningful "how many times" count the way
	## Bleeding or Poisoned genuinely do.
	if condition_name == "Prone":
		conditions[condition_name] = 1
		return
	conditions[condition_name] = conditions.get(condition_name, 0) + stacks

func remove_condition(condition_name: String) -> void:
	conditions.erase(condition_name)

## --- Timed buffs (Blessings/Miracles/Spells with a Duration in Rounds)
## -----------------------------------------------------------------
## Most Blessings/Miracles/Spells with a numbered Duration ("6 Rounds",
## etc.) grant a temporary characteristic bonus rather than a named
## Condition — "+10 Weapon Skill for 6 Rounds," not a flag like Prone.
## Tracked separately from `conditions` for that reason: each entry
## here carries its own characteristic bonuses and remaining Round
## count, and actually feeds into get_effective_characteristic_value()
## below, which Tests/damage genuinely read from — this isn't just a
## label shown in a log, it changes real rolls while active.
## Each entry: {name, source, characteristic_bonuses: Dictionary,
## rounds_remaining: int, damage_bonus: int}
@export var active_buffs: Array = []
## Per the request's own clarification: the real Riposte Talent lets
## you deal your own weapon's normal damage to an attacker you just
## successfully Parried — usable up to your own Riposte rank times per
## Round, tracked here and reset at the start of each new Round (see
## CombatEncounter._on_round_end).
var riposte_uses_this_round: int = 0
## Per the request: Furious Assault — "once per Round, after hitting
## in close combat, spend an Advantage... to make an extra attack" —
## simplified per the request's own note that this project's combat
## doesn't track movement, so only the Advantage-spend option exists
## here (the book's alternative "or your Move" option is dropped).
## Reset each Round by CombatEncounter._on_round_end, same pattern as
## riposte_uses_this_round above.
var furious_assault_used_this_round: bool = false
## Distract (Up in Arms, p.142): "If you win, your opponent can gain no
## Advantage until the end of the next Round." Set to 2 the moment
## Distract succeeds against this character (see
## FieldEncounterScreen._on_distract) -- decremented by 1 at the end of
## EVERY Round from then on (CombatEncounter._on_round_end, same timing
## as riposte_uses_this_round's own reset), so it covers the rest of
## THIS Round (still >0 after the first decrement) and the whole of the
## next Round, reaching 0 exactly when that next Round ends. While >0,
## every Advantage-generation call site this character could trigger
## themselves (Winning, Outmaneuver, Surprise, Reversal, Assess) is
## skipped -- see is_advantage_denied() below.
var advantage_denied_rounds_remaining: int = 0

func is_advantage_denied() -> bool:
	return advantage_denied_rounds_remaining > 0

## Drilled (Up in Arms p.141) Bonus Tests gate: "Melee Tests when beside
## an ally with Drilled." True while this character is currently
## standing next to (live battle-grid adjacency, Chebyshev distance 1)
## another living character who also has Drilled — refreshed by
## FieldEncounterScreen._refresh_drilled_adjacency() (this Resource has
## no concept of grid position itself), consumed by
## get_test_success_level_breakdown() above. Not exported/persisted —
## purely a live, per-render flag, same as riposte_uses_this_round's own
## "reset by the owning screen" division of responsibility.
var drilled_beside_ally: bool = false

## `movement_bonus`, per Cordelia's Apothecary's Vitality Draught (spec:
## "grant... +2 Movement for 6 Rounds"): same {name, source,
## characteristic_bonuses, rounds_remaining, damage_bonus} shape every
## other timed buff already uses, just one more flat bonus field —
## summed by get_active_movement_bonus() below, which get_movement()/
## get_unmodified_movement() both now read, same choke-point pattern
## creature_movement_bonus already established.
func add_timed_buff(buff_name: String, source: String, characteristic_bonuses: Dictionary, rounds: int, damage_bonus: int = 0, movement_bonus: int = 0) -> void:
	active_buffs.append({
		"name": buff_name, "source": source, "characteristic_bonuses": characteristic_bonuses,
		"rounds_remaining": rounds, "damage_bonus": damage_bonus, "movement_bonus": movement_bonus,
	})

## Called once per Round (see field_encounter_screen.gd's round-advance
## logic) — counts down every active buff and drops any that expire.
func tick_active_buffs() -> void:
	var still_active: Array = []
	for buff in active_buffs:
		buff["rounds_remaining"] -= 1
		if buff["rounds_remaining"] > 0:
			still_active.append(buff)
	active_buffs = still_active
	## Light (Petty spell) — see light_spell_rounds_remaining's own
	## comment: ticks down by 1 Round right alongside every other timed
	## buff here, same call site (CombatEncounter._on_round_end(), once
	## per Round per combatant in turn_order).
	if light_spell_rounds_remaining > 0:
		light_spell_rounds_remaining -= 1
	## Flaming Sword of Rhuin — same per-Round tick, same reasoning as
	## Light just above. No cleanup needed beyond the counter itself:
	## get_equipped_weapon() already stops returning flaming_sword_weapon
	## the instant this hits 0, and field_encounter_screen.gd's own
	## _weapon_for() separately notices its cached copy went stale (see
	## that function's own comment) and refreshes itself on the very next
	## lookup — so nothing here needs to reach back into that screen's
	## weapons cache directly.
	if flaming_sword_rounds_remaining > 0:
		flaming_sword_rounds_remaining -= 1

## The actual value Tests/damage should use — base characteristic plus
## every active buff's bonus to that characteristic, summed. This is
## the real hook: get_skill_value() and get_characteristic_bonus() both
## read through this rather than the raw stored value, so an active
## Blessing of Battle genuinely raises your Melee target, not just your
## sheet.
func get_effective_characteristic_value(key: String) -> int:
	var value := characteristics.get_value(key)
	for buff in active_buffs:
		value += int(buff["characteristic_bonuses"].get(key, 0))
	## p.171 Resolve spend: "Ignore all modifiers from all Critical
	## Wounds until the beginning of the next round" — skipped entirely
	## while the flag is set, rather than zeroed penalty-by-penalty, so
	## it can't accidentally miss a future penalty shape.
	if not critical_wound_penalties_ignored_this_round:
		for penalty in critical_wound_penalties:
			value += int(penalty["characteristic_bonuses"].get(key, 0))
	## Talents like Suave/Very Strong ("a permanent +5 bonus to your
	## starting [X] Characteristic, doesn't count toward Advances") are
	## a flat bonus applied at read-time here — same convention as the
	## buffs/critical-wound penalties just above — rather than mutating
	## `characteristics` directly, so it's correctly excluded from
	## Advance-cost calculations (which read the raw stored value) while
	## still counting everywhere the effective value is actually used
	## (Skill targets, raw Characteristic Tests, the Stats tab display).
	## Fixed from an earlier bug where Suave was wired as a per-Test +1
	## Success Level bonus instead of this actual book effect. Driven
	## generically off each taken talent's own effect_tags (matching
	## GameData's own "permanent_starting_<key>_bonus" naming) rather
	## than a hardcoded per-talent list, so any future talent using the
	## same tag convention picks this up automatically.
	if GameData != null and GameData.talent_db != null:
		var wanted_tag := "permanent_starting_%s_bonus" % key
		for talent_name in talents_taken.keys():
			var td: TalentDefinition = GameData.talent_db.find_by_name(talent_name)
			if td != null and td.effect_tags.has(wanted_tag):
				value += 5
	## Consume Alcohol: "-10 penalty to WS, BS, Ag, Dex, and Int, to a
	## maximum of -30 per Characteristic" per failed Test — see
	## get_alcohol_characteristic_penalty()'s own comment. Applied here
	## (not through get_condition_test_penalty_breakdown()) since it's a
	## genuine Characteristic-level malus affecting every Skill/raw Test
	## that reads through this function, not a single "worst Condition
	## applies" competing penalty — stacks on top of everything else,
	## same reasoning as the Agility Encumbrance malus right below.
	if ALCOHOL_PENALTY_CHARACTERISTICS.has(key):
		value += get_alcohol_characteristic_penalty()
	if key == "agility":
		## Encumbrance (p.293): a direct Agility malus, not a Master
		## Condition List entry, so it's applied here rather than
		## through get_condition_test_penalty_breakdown() — this way it
		## quietly lowers every Agility-linked Skill Test, raw Agility
		## Test, and Initiative roll (all three read through here or
		## through get_skill_value(), which itself calls this), on top
		## of any Condition penalties, matching the book's own
		## "stacks with" language rather than competing with them for
		## "only the single worst applies."
		var enc := get_encumbrance_penalty()
		if not enc["immobile"]:
			var pre := value
			value -= int(enc["agility_penalty"])
			var floor_val: int = int(enc["agility_floor"])
			if floor_val > 0 and pre >= floor_val:
				value = max(value, floor_val)
	return value

## Critical Wound penalties tick in days, not combat Rounds — called
## whenever the world clock advances by a meaningful amount (Camp's
## Sleep action, in practice, since that's the only place time
## currently advances by hours rather than the Overworld's own
## 2-minutes-per-step). A day-scale penalty that reaches 0 is dropped
## automatically, same pattern as tick_active_buffs().
func tick_critical_wound_days(days: int) -> void:
	if days <= 0:
		return
	var still_active: Array = []
	for penalty in critical_wound_penalties:
		penalty["rounds_remaining"] -= days
		if penalty["rounds_remaining"] > 0:
			still_active.append(penalty)
	critical_wound_penalties = still_active

## Sum of any active buffs' flat damage bonus (e.g. Sigmar's Fiery
## Hammer's "+Fellowship Bonus Damage" while wielding a warhammer) —
## added on top of a weapon's normal damage in combat resolution.
## `weapon` (optional) is the weapon actually being used for THIS
## attack: Sigmar's Fiery Hammer's own Damage bonus is conditional on
## "if wielding a warhammer" (p.226), so its contribution is skipped
## unless `weapon` is a Warhammer — matched the same way Flaming Sword
## of Rhuin matches "Sword" family weapons, by name (contains
## "Warhammer" catches "Warhammer (1H)/(2H)" and their Fine variants;
## "Cavalry Hammer" doesn't contain that substring so it's correctly
## excluded), OR is this Miracle's own renamed clone (field_encounter_
## screen.gd's _apply_prayer_buff_effect() shortens the display name to
## just "Sigmar's Fiery Hammer (1H)"/"(2H)", which no longer contains
## "Warhammer" itself, so it's matched by its own fixed name prefix
## instead). Every other buff's damage_bonus is unconditional, same as
## before.
func get_active_damage_bonus(weapon: WeaponDefinition = null) -> int:
	var total := 0
	var wielding_warhammer := weapon != null and (weapon.weapon_name.contains("Warhammer") or weapon.weapon_name.begins_with("Sigmar's Fiery Hammer"))
	for buff in active_buffs:
		if buff.get("name", "") == "Sigmar's Fiery Hammer" and not wielding_warhammer:
			continue
		total += int(buff.get("damage_bonus", 0))
	return total

## True if this Character currently has an active timed buff with this
## exact name (see active_buffs/add_timed_buff) — e.g. gating Sigmar's
## Fiery Hammer's Ablaze+Prone-on-hit effect in
## field_encounter_screen.gd's _show_attack_cards().
func has_active_buff(buff_name: String) -> bool:
	for buff in active_buffs:
		if buff.get("name", "") == buff_name:
			return true
	return false

## Removes every active_buffs entry with this exact name, if any — a
## no-op if it isn't currently active. Used to force-clear Sigmar's
## Fiery Hammer (buff + its weapon rename) the instant a field
## encounter ends, per the explicit request ("clear out when the field
## encounter screen closes") — mirroring Flaming Sword of Rhuin's own
## force-clear in field_encounter_screen.gd's _end_battle(), since
## nothing else here reliably ticks active_buffs down to 0 for a fight
## that ends mid-Duration (tick_active_buffs() only ever runs once per
## Round inside a live encounter).
func remove_active_buff(buff_name: String) -> void:
	var still_active: Array = []
	for buff in active_buffs:
		if buff.get("name", "") != buff_name:
			still_active.append(buff)
	active_buffs = still_active

## Sums every active timed buff's own movement_bonus — see
## add_timed_buff()'s own comment. Read by get_movement()/
## get_unmodified_movement() below (Vitality Draught's "+2 Movement for
## 6 Rounds").
func get_active_movement_bonus() -> int:
	var total := 0
	for buff in active_buffs:
		total += int(buff.get("movement_bonus", 0))
	return total

## --- Consume Alcohol / Stinking Drunk (Consume Alcohol Basic Skill) ---
## Per the request ("make sure Consume Alcohol and drunk mechanic are
## really implemented, if not do it"): the book's own drinking-and-
## recovery loop, verbatim rules text this was built from:
##   "After each alcoholic drink make a Consume Alcohol Test, modified
##   by the strength of the drink. For each Test you fail, you suffer
##   a -10 penalty to WS, BS, Ag, Dex, and Int, to a maximum of -30 per
##   Characteristic. After you fail a number of Tests equal to your
##   Toughness Bonus, you are Stinking Drunk. Roll on the following
##   table..." (1d10 STINKING_DRUNK_TABLE below) "...After not drinking
##   for an hour, enact a Challenging (+0) Consume Alcohol Test. The
##   effects of being drunk will wear off after 10-SL hours, with any
##   Characteristic modifiers for being drunk lost over that time.
##   After all effects wear off, enact another Challenging (+0) Consume
##   Alcohol Test. You now gain a hangover, which is a Fatigued
##   Condition that cannot be removed for 5-SL hours."
##
## Modelled as real, persisted game state — not just flavour text — via
## tick_alcohol_hours() below, called from GameState.advance_minutes()
## so the whole sober-up/hangover arc fires correctly no matter how
## game time actually passes (a short nap, a full night's Sleep, or
## just walking around town), the same generic hook every other
## real-hours mechanic in this project (critical wound day-ticking,
## world-map fatigue) already relies on.
##
## Two of the table's five results (3-4 "ignore Prejudices/
## Animosities", 7-8 "gain Animosity (Everybody!)") and half of a third
## (5-6's "Move or Action, not both") describe systems this project
## doesn't model at all (there's no Prejudice/Animosity data anywhere,
## and no combat action-economy split of Move vs Action) — building
## those out is a much larger feature than this request's scope, so
## those three are surfaced as real, visible status text (see
## stinking_drunk_table_entry(), shown on the Tavern screen) for the
## player/GM to actually role-play and enforce by hand, same as they'd
## adjudicate it at a real table. The other two (1-2's Cool +20, and
## 9-10's Poisoned-on-a-failed-Test) ARE wired into real mechanics
## below (get_drunk_test_modifier_breakdown(), _roll_stinking_drunk()).
@export var alcohol_fail_count: int = 0
@export var is_stinking_drunk: bool = false
## Which STINKING_DRUNK_TABLE row (1-10) is currently in effect, 0 =
## none/not currently Stinking Drunk. Stays set for as long as
## is_drunk() does (see tick_alcohol_hours() — cleared together once
## alcohol_recovery_hours_remaining reaches 0), not just for the one
## instant the 1d10 was rolled.
@export var stinking_drunk_result: int = 0
## True once the "after not drinking for an hour" sobering Test has
## been rolled for the CURRENT bout of drunkenness — guards
## tick_alcohol_hours() against re-rolling it on every single tick
## once the hour has passed.
@export var _alcohol_sobering_test_done: bool = false
## Hours remaining until "the effects of being drunk" (the -10/fail
## characteristic penalty AND the Stinking Drunk table effect) wear
## off — 0 until the sobering Test above sets it, then counts down to
## 0 via tick_alcohol_hours().
@export var alcohol_recovery_hours_remaining: float = 0.0
## GameState.time_minutes_total() at this character's last drink — the
## "after not drinking for an hour" clause reads off this.
@export var last_drink_time_minutes: int = -1000000
## Hours remaining before the hangover's own Fatigued stack can be
## removed by resting — Sleep (Tavern/Camp) checks this before
## decrementing Fatigued, same "locked until real time passes" idea as
## critical wound penalties ticking in days rather than being cleared
## by Sleep outright.
@export var hangover_lock_hours_remaining: float = 0.0

## Cauterise (Lore of Fire, p.243-ish): a target without the Arcane
## Magic (Fire) Talent who fails their own Cool Test by 6+ SL "gains the
## Unconscious Condition... waking up 1d10 hours later" — a real-hours
## duration, not a combat-Round one, same shape alcohol_recovery_hours_
## remaining above already established for exactly this kind of timer.
## Ticked down by tick_cauterise_recovery() below, called from
## GameState.advance_minutes() alongside tick_alcohol_hours() so it
## counts down for however time actually passes (travel, Sleep, camp),
## not just a dedicated "wait" action.
@export var cauterise_recovery_hours_remaining: float = 0.0
## "...and is permanently scarred" — a lasting, non-clearing flag (kept
## off the `conditions` Dictionary on purpose, since several places in
## this project clear Conditions wholesale at points like battle-end;
## a genuine "permanently" effect needs its own field that nothing else
## ever touches). Purely a flavor/record flag for now — no other code
## reads it yet, same honest treatment other unmodelled-consequence
## flags get elsewhere in this project.
@export var permanently_scarred: bool = false

const ALCOHOL_PENALTY_CHARACTERISTICS := ["weapon_skill", "ballistic_skill", "agility", "dexterity", "intelligence"]

## 1d10 Stinking Drunk table, verbatim from the book.
const STINKING_DRUNK_TABLE := [
	{"min": 1, "max": 2, "name": "Marienburgher's Courage!", "text": "Gain a bonus of +20 to your Cool Skill."},
	{"min": 3, "max": 4, "name": "You're My Besht Mate!", "text": "Ignore all your existing Prejudices and Animosities."},
	{"min": 5, "max": 6, "name": "Why's Everything Wobbling!", "text": "On your Turn, you can either Move or take an Action, but not both."},
	{"min": 7, "max": 8, "name": "I'll Take Yer All On!", "text": "Gain Animosity (Everybody!)."},
	{"min": 9, "max": 10, "name": "How Did I Get Here?", "text": "You wake up the next day, massively hungover, with little memory of what transpired."},
]

## The current cumulative Characteristic penalty from failed Consume
## Alcohol Tests — -10 per fail, capped at -30 (3 fails' worth), even
## if alcohol_fail_count itself keeps climbing past 3 (it still counts
## toward the Toughness Bonus Stinking Drunk threshold below).
func get_alcohol_characteristic_penalty() -> int:
	return -10 * mini(alcohol_fail_count, 3)

func is_drunk() -> bool:
	return alcohol_fail_count > 0

func stinking_drunk_table_entry() -> Dictionary:
	for row in STINKING_DRUNK_TABLE:
		if stinking_drunk_result >= row["min"] and stinking_drunk_result <= row["max"]:
			return row
	return {}

## A scoped Test-target bonus, same shape/pipeline as
## get_condition_test_penalty_breakdown() (see TestResolver.
## resolve_skill_test, which folds both in automatically) — currently
## only the Stinking Drunk table's own 1-2 result ("Marienburgher's
## Courage!"), a real +20 to Cool Tests specifically, for as long as
## the character is still Stinking Drunk.
func get_drunk_test_modifier_breakdown(scopes: Array) -> Array:
	if is_stinking_drunk and stinking_drunk_result > 0 and stinking_drunk_result <= 2 and scopes.has("Cool"):
		return [{"name": "Marienburgher's Courage! (Stinking Drunk)", "amount": 20}]
	return []

## Resolves one alcoholic drink's own Consume Alcohol Test (modified by
## the drink's own strength — see TavernScreen.DRINKS) — called by the
## Tavern screen's Drink action. A fresh drink always resets the "an
## hour since your last drink" sobering clock, even mid-recovery (you
## can't sober up while still actively drinking). On a failed Test,
## the cumulative -10 penalty grows and, once alcohol_fail_count
## reaches this character's own Toughness Bonus, a real Stinking Drunk
## 1d10 is rolled — including immediately resolving the 9-10 result's
## own "pass a Consume Alcohol Test or also gain a Poisoned Condition"
## clause right here, since that's tied to the moment of becoming
## Stinking Drunk, not the later sober-up arc tick_alcohol_hours()
## handles.
func drink_alcohol(consume_alcohol_def: SkillDefinition, drink_modifier: int, now_minutes: int) -> TestResolver.TestResult:
	last_drink_time_minutes = now_minutes
	_alcohol_sobering_test_done = false
	alcohol_recovery_hours_remaining = 0.0
	var result := TestResolver.resolve_skill_test(self, consume_alcohol_def, "", drink_modifier)
	if not result.success:
		alcohol_fail_count += 1
		var tb: int = get_characteristic_bonus("toughness")
		if not is_stinking_drunk and alcohol_fail_count >= max(tb, 1):
			is_stinking_drunk = true
			stinking_drunk_result = (randi() % 10) + 1
			if stinking_drunk_result >= 9:
				var memory_test := TestResolver.resolve_skill_test(self, consume_alcohol_def, "")
				if not memory_test.success:
					conditions["Poisoned"] = int(conditions.get("Poisoned", 0)) + 1
	return result

## Called from GameState.advance_minutes() for every party member, any
## time the game clock moves for any reason (travel, Sleep, camp) —
## the same generic "however time passes" hook this whole recovery arc
## needs, since the rules are written in real elapsed hours ("after
## not drinking for an hour," "wear off after 10-SL hours," "cannot be
## removed for 5-SL hours"), not "the next time you do X."
##
## Simplification, clearly flagged rather than hidden: a single call
## can span a large jump (an 8-hour Full Night's Sleep, say) that
## crosses more than one of this arc's own thresholds at once — the
## same elapsed span that pushes minutes-since-last-drink past the
## 1-hour sobering trigger is then also counted toward the recovery
## countdown in that same call, rather than only the leftover time
## after the threshold. At the coarse, whole-hour granularity this
## project's clock actually advances in, that's at most about an
## hour's worth of slop per bout of drinking — not worth the extra
## bookkeeping a fully sub-hour-precise version would need.
func tick_alcohol_hours(minutes_elapsed: int, now_minutes: int, consume_alcohol_def: SkillDefinition) -> void:
	if minutes_elapsed <= 0:
		return
	var hours_elapsed: float = float(minutes_elapsed) / 60.0

	if hangover_lock_hours_remaining > 0.0:
		hangover_lock_hours_remaining = maxf(0.0, hangover_lock_hours_remaining - hours_elapsed)

	if not is_drunk():
		return
	if consume_alcohol_def == null:
		return

	## Step A ("after not drinking for an hour, enact a Challenging (+0)
	## Consume Alcohol Test") — fires once per bout, the first tick
	## where at least 60 minutes have passed since the last drink.
	if not _alcohol_sobering_test_done:
		var minutes_since_drink: int = now_minutes - last_drink_time_minutes
		if minutes_since_drink >= 60:
			_alcohol_sobering_test_done = true
			var sober_test := TestResolver.resolve_skill_test(self, consume_alcohol_def, "")
			alcohol_recovery_hours_remaining = maxf(1.0, 10.0 - float(sober_test.success_levels))

	## Step B: the wear-off countdown itself, and Step C ("after all
	## effects wear off, enact another Challenging (+0) Consume Alcohol
	## Test. You now gain a hangover...") once it reaches 0.
	if _alcohol_sobering_test_done and alcohol_recovery_hours_remaining > 0.0:
		alcohol_recovery_hours_remaining = maxf(0.0, alcohol_recovery_hours_remaining - hours_elapsed)
		if alcohol_recovery_hours_remaining <= 0.0:
			alcohol_fail_count = 0
			is_stinking_drunk = false
			stinking_drunk_result = 0
			_alcohol_sobering_test_done = false
			var hangover_test := TestResolver.resolve_skill_test(self, consume_alcohol_def, "")
			var hangover_hours: float = maxf(0.0, 5.0 - float(hangover_test.success_levels))
			if hangover_hours > 0.0:
				conditions["Fatigued"] = int(conditions.get("Fatigued", 0)) + 1
				hangover_lock_hours_remaining = maxf(hangover_lock_hours_remaining, hangover_hours)

## True while the sobering Test has fired (Step A) but the wear-off
## countdown it started hasn't reached 0 yet (Step B) — a small public
## accessor so UI code (TavernScreen) doesn't need to reach into the
## underscore-prefixed _alcohol_sobering_test_done field directly.
func is_sobering_up() -> bool:
	return _alcohol_sobering_test_done and alcohol_recovery_hours_remaining > 0.0

## Counts down cauterise_recovery_hours_remaining and wakes this
## character back up once it reaches 0 — see that field's own comment.
## Guarded on wounds_current > 0 so this never falsely wakes someone who
## is ALSO Unconscious for the ordinary, unrelated reason (0 Wounds) —
## this timer expiring only ever clears the Condition it itself caused;
## if they're still at 0 Wounds for some other reason, they rightly stay
## Unconscious until healed, same as anyone else in that state.
func tick_cauterise_recovery(minutes_elapsed: int) -> void:
	if cauterise_recovery_hours_remaining <= 0.0:
		return
	var hours_elapsed: float = float(minutes_elapsed) / 60.0
	cauterise_recovery_hours_remaining = maxf(0.0, cauterise_recovery_hours_remaining - hours_elapsed)
	if cauterise_recovery_hours_remaining <= 0.0 and wounds_current > 0 and conditions.has("Unconscious"):
		remove_condition("Unconscious")

## Applies Wounds lost from an attack.
func take_wounds(amount: int) -> void:
	if amount <= 0:
		return
	wounds_current = max(0, wounds_current - amount)

## Master Condition List (p.167-169) end-of-Round effects for the three
## Conditions that cause ongoing Wound loss: Bleeding (1 Wound per
## stack, ignoring all modifiers; falls Unconscious instead of further
## loss at 0 Wounds; a 10%-per-stack death chance while Unconscious AND
## Bleeding), Ablaze (1d10 Wounds, +1 per additional stack, modified by
## Toughness Bonus and the least-armoured location's AP), and Poisoned
## (1 Wound per stack, ignoring all modifiers). Returns a summary
## Dictionary for the UI to log, rather than printing/logging directly
## from a Resource class.
## `broken_recovery_modifier` (per the request, implementing Broken
## fully): the book scales the end-of-Round Broken recovery Test by
## circumstance — "Average (+20) if safe, Very Hard (-30) if still in
## danger" — rather than a flat Challenging (+0) every time. The
## caller (field_encounter_screen.gd, which actually knows battlefield
## distances) works out which applies and passes it in here, same
## division of responsibility as `is_engaged` above.
## `was_hidden` (Broken, p.168: "a full Round spent hidden and out of
## line of sight of the enemy" removes 1 Broken automatically): also
## caller-supplied, since line-of-sight lives on the battle grid, not
## the Character. When true, this replaces the Cool Test entirely for
## this Round (a guaranteed recovery, no roll needed) rather than
## stacking on top of it.
func tick_end_of_round_conditions(is_engaged: bool = false, broken_recovery_modifier: int = 0, was_hidden: bool = false) -> Dictionary:
	var summary := {"wounds_lost": 0, "fell_unconscious": false, "died_from_bleeding": false, "notes": []}
	var bleeding: int = int(conditions.get("Bleeding", 0))
	if bleeding > 0:
		if wounds_current > 0:
			## Implacable (p.137): "ignore the Wound loss from a Bleeding
			## Condition, one extra Bleeding Condition ignored per level"
			## — reduces the effective stacks actually applied as Wound
			## loss THIS Round, not the raw Bleeding count itself (which
			## still needs a real Heal Test to clear, and still governs
			## the Unconscious death-chance/clotting roll in the other
			## branch below, unmodified — Implacable is about surviving
			## the ongoing bleed, not making it easier to treat).
			var effective_bleeding: int = max(0, bleeding - get_talent_rank("Implacable"))
			if effective_bleeding > 0:
				var before := wounds_current
				wounds_current = max(0, wounds_current - effective_bleeding)
				summary["wounds_lost"] += before - wounds_current
				if wounds_current == 0:
					add_condition("Unconscious", 1)
					summary["fell_unconscious"] = true
		elif conditions.has("Unconscious"):
			## 10% death chance per Bleeding Condition while Unconscious
			## and still Bleeding (p.167): rolled as a d100, doubles
			## clot the wound instead (lose 1 Bleeding Condition).
			var roll := Dice.d100()
			if roll <= bleeding * 10:
				summary["died_from_bleeding"] = true
			elif (roll % 11) == 0:   ## a double (11, 22, 33...)
				conditions["Bleeding"] = max(0, bleeding - 1)
				if conditions["Bleeding"] == 0:
					conditions.erase("Bleeding")
					## Bleeding (p.167): "Once all Bleeding Conditions are
					## removed, gain one Fatigued Condition" — applies no
					## matter which of Bleeding's several removal paths
					## (this clotting roll, or the Heal Test in
					## attempt_heal_condition() below) actually cleared it.
					add_condition("Fatigued", 1)
				summary["notes"].append("wound clots a little")
	var ablaze: int = int(conditions.get("Ablaze", 0))
	if ablaze > 0:
		var least_armoured_ap := 999
		for loc in ["Head", "Body", "Left Arm", "Right Arm", "Left Leg", "Right Leg"]:
			least_armoured_ap = min(least_armoured_ap, get_armour_points(loc))
		if least_armoured_ap == 999:
			least_armoured_ap = 0
		var ablaze_dmg: int = max(1, Dice.d10() + (ablaze - 1) - get_characteristic_bonus("toughness") - least_armoured_ap)
		var before := wounds_current
		wounds_current = max(0, wounds_current - ablaze_dmg)
		summary["wounds_lost"] += before - wounds_current
	var poisoned: int = int(conditions.get("Poisoned", 0))
	if poisoned > 0 and wounds_current > 0:
		var before := wounds_current
		wounds_current = max(0, wounds_current - poisoned)
		summary["wounds_lost"] += before - wounds_current

	## Recovery attempts (p.167-169) — each Condition heals itself back
	## given time, on its own schedule, not just via a Healer visit:
	## Stunned/Poisoned via a Challenging Endurance Test (each SL beyond
	## the first removes an extra stack); Blinded/Deafened lift on their
	## own every OTHER Round (approximated here as a 50% chance per
	## Round, since this project doesn't track a Round-parity counter
	## per-Condition); Broken via a Cool Test, but only while unengaged
	## in melee (checked by the caller, since engagement state lives on
	## the encounter, not the Character).
	var recovered: Array[String] = []
	if int(conditions.get("Stunned", 0)) > 0:
		var endurance: SkillDefinition = GameData.skill_db.find_by_name("Endurance")
		## Iron Jaw (p.139): "+10 per rank to any Test made to resist or
		## recover from being Stunned" — a famously stubborn constitution.
		## Unlike Broken's own recovery modifier (which needs situational
		## input — distance to the nearest enemy, whether the Round was
		## spent hidden — computed by the caller and threaded in as a
		## parameter, see broken_recovery_modifier below), this bonus is
		## purely intrinsic to the character, so it's read directly off
		## talents_taken right here rather than needing any new
		## parameter/threading through CombatEncounter.
		var iron_jaw_bonus := get_talent_rank("Iron Jaw") * 10
		var iron_jaw_breakdown: Array = [{"name": "Iron Jaw", "amount": iron_jaw_bonus}] if iron_jaw_bonus > 0 else []
		var test := TestResolver.resolve_skill_test(self, endurance, "", iron_jaw_bonus, iron_jaw_breakdown)
		if test.success:
			var removed: int = max(1, test.success_levels)
			var remaining: int = max(0, int(conditions.get("Stunned", 0)) - removed)
			if remaining <= 0:
				conditions.erase("Stunned")
				add_condition("Fatigued", 1)
				recovered.append("Stunned (fully — now Fatigued)")
			else:
				conditions["Stunned"] = remaining
				recovered.append("Stunned (-%d)" % removed)
	if int(conditions.get("Poisoned", 0)) > 0:
		var endurance2: SkillDefinition = GameData.skill_db.find_by_name("Endurance")
		var test2 := TestResolver.resolve_skill_test(self, endurance2, "", 0)
		if test2.success:
			var removed2: int = max(1, test2.success_levels)
			var remaining2: int = max(0, int(conditions.get("Poisoned", 0)) - removed2)
			if remaining2 <= 0:
				conditions.erase("Poisoned")
				add_condition("Fatigued", 1)
				recovered.append("Poisoned (fully — now Fatigued)")
			else:
				conditions["Poisoned"] = remaining2
				recovered.append("Poisoned (-%d)" % removed2)
	if conditions.has("Blinded") and randf() < 0.5:
		var remaining3: int = max(0, int(conditions.get("Blinded", 0)) - 1)
		if remaining3 <= 0:
			conditions.erase("Blinded")
		else:
			conditions["Blinded"] = remaining3
		recovered.append("Blinded (-1)")
	if conditions.has("Deafened") and randf() < 0.5:
		var remaining4: int = max(0, int(conditions.get("Deafened", 0)) - 1)
		if remaining4 <= 0:
			conditions.erase("Deafened")
		else:
			conditions["Deafened"] = remaining4
		recovered.append("Deafened (-1)")
	## Broken (p.168): "You cannot Test to rally from being Broken if
	## you are Engaged with an enemy... at the end of each Round, you
	## may attempt a Cool Test to remove a Broken Condition."
	if conditions.has("Broken") and not is_engaged:
		if was_hidden:
			## Guaranteed -1, no roll — spending the whole Round genuinely
			## out of sight is strictly better than a Cool Test could ever
			## be, matching the book's own "or" phrasing (hidden OR pass a
			## Test), not an additional bonus stacked on top of one.
			var remaining_h: int = max(0, int(conditions.get("Broken", 0)) - 1)
			if remaining_h <= 0:
				conditions.erase("Broken")
				add_condition("Fatigued", 1)
				recovered.append("Broken (fully, spent the Round hidden — now Fatigued)")
			else:
				conditions["Broken"] = remaining_h
				recovered.append("Broken (-1, spent the Round hidden)")
		else:
			var cool: SkillDefinition = GameData.skill_db.find_by_name("Cool")
			var broken_test := TestResolver.resolve_skill_test(self, cool, "", broken_recovery_modifier)
			if broken_test.success:
				var removed5: int = max(1, broken_test.success_levels)
				var remaining5: int = max(0, int(conditions.get("Broken", 0)) - removed5)
				if remaining5 <= 0:
					conditions.erase("Broken")
					add_condition("Fatigued", 1)
					recovered.append("Broken (fully — now Fatigued)")
				else:
					conditions["Broken"] = remaining5
					recovered.append("Broken (-%d)" % removed5)
	if not recovered.is_empty():
		summary["notes"].append("recovers from " + ", ".join(recovered))
	return summary

## Bleeding (p.167) and Poisoned (p.169) can each ALSO be removed via a
## successful Heal Test — "A Heal Test provides the same results [as the
## Endurance Test]" — on top of their own automatic end-of-Round recovery
## attempt above. `healer` is whoever spends the Action to tend the
## Condition (this character themselves, or an ally) — each SL beyond
## the first removes an extra stack, same as every other Condition's own
## recovery Test. Returns null (no-op, no roll made) if `condition_name`
## isn't one of these two, or if there's no stack of it left to remove.
func attempt_heal_condition(healer: Character, condition_name: String) -> TestResolver.TestResult:
	if condition_name != "Bleeding" and condition_name != "Poisoned":
		return null
	if int(conditions.get(condition_name, 0)) <= 0 or healer == null:
		return null
	var heal_skill: SkillDefinition = GameData.skill_db.find_by_name("Heal")
	var test := TestResolver.resolve_skill_test(healer, heal_skill, "")
	if test.success:
		var removed: int = max(1, test.success_levels)
		var remaining: int = max(0, int(conditions.get(condition_name, 0)) - removed)
		if remaining <= 0:
			conditions.erase(condition_name)
			add_condition("Fatigued", 1)   ## both Bleeding and Poisoned grant this once fully cleared, p.167/169
		else:
			conditions[condition_name] = remaining
	return test

## Ablaze (p.167): "One Ablaze Condition can be removed with a successful
## Athletics Test, with each SL removing an extra Ablaze Condition." A
## self-directed Action (stop, drop, and roll), same shape as Entangled's
## own Struggle Free — see _on_struggle_free() in field_encounter_screen.gd
## for the UI side of this. No Fatigued follow-on: unlike Bleeding/
## Poisoned/Stunned/Broken, the book doesn't grant one for Ablaze.
func attempt_douse_ablaze() -> TestResolver.TestResult:
	if int(conditions.get("Ablaze", 0)) <= 0:
		return null
	var athletics: SkillDefinition = GameData.skill_db.find_by_name("Athletics")
	var test := TestResolver.resolve_skill_test(self, athletics, "")
	if test.success:
		var removed: int = max(1, test.success_levels)
		var remaining: int = max(0, int(conditions.get("Ablaze", 0)) - removed)
		if remaining <= 0:
			conditions.erase("Ablaze")
		else:
			conditions["Ablaze"] = remaining
	return test

## Prone (p.169): "You lose the Prone Condition when you stand up" — a
## free choice on your Move, not a Test, EXCEPT "if you have 0 Wounds
## remaining, you can only crawl" (i.e. you cannot stand up at all, only
## move at half Movement while staying Prone). Returns false (no-op) if
## not actually Prone, or currently at 0 Wounds.
func attempt_stand_up() -> bool:
	if int(conditions.get("Prone", 0)) <= 0:
		return false
	if wounds_current <= 0:
		return false
	conditions.erase("Prone")
	return true

## p.171 Spending Resolve, option 3: "Remove one Condition; if you
## removed the Prone Condition, regain 1 Wound as you surge to your
## feet." Per the request's own explicit override of that book wording:
## Wounds are set to max(wounds_current, 1) instead — exactly 1 if they
## were genuinely at 0, left completely untouched if already higher
## (not a flat "+1" that would let this be stacked for free healing).
## A free (no-Test) choice, same shape as attempt_stand_up()
## above but spending a Resolve point instead of a Move, and usable on
## ANY currently-held Condition rather than only Prone. Removes a
## single STACK of the named Condition (not every stack at once) —
## matching this project's own established convention for what "one
## Condition" means elsewhere (e.g. attempt_douse_ablaze() removes 1
## Ablaze stack per success, the Bleeding/Poisoned recovery Test
## removes 1 stack per SL); Prone/Unconscious/Surprised never stack
## past 1 anyway, so this still fully removes those in one call.
## Returns false (no Resolve spent) if the Condition isn't actually
## held or there's no Resolve left to spend.
func attempt_spend_resolve_remove_condition(condition_name: String) -> bool:
	if resolve <= 0:
		return false
	if not conditions.has(condition_name):
		return false
	resolve -= 1
	var remaining: int = max(0, int(conditions.get(condition_name, 0)) - 1)
	if remaining <= 0:
		conditions.erase(condition_name)
	else:
		conditions[condition_name] = remaining
	if condition_name == "Prone":
		wounds_current = max(wounds_current, 1)
	return true

## p.171 Spending Resolve, option 2: "Ignore all modifiers from all
## Critical Wounds until the beginning of the next round." Sets the
## Round-scoped flag get_effective_characteristic_value() reads —
## CombatEncounter._on_round_end resets it, mirroring
## riposte_uses_this_round/furious_assault_used_this_round.
func attempt_spend_resolve_ignore_critical_wound_penalties() -> bool:
	if resolve <= 0:
		return false
	if critical_wound_penalties.is_empty():
		return false
	resolve -= 1
	critical_wound_penalties_ignored_this_round = true
	return true

## Sums Armour Points from every equipped armour piece that covers the
## given Hit Location (one of "Head", "Body", "Left Arm", "Right Arm",
## "Left Leg", "Right Leg").
## Layering (house rule, per the request): up to 3 pieces can cover the
## same location at once — one per tier (Light/Medium/Heavy) — so their
## APs are genuinely summed together here, each reduced by its OWN
## accumulated damage.
## Armour Damage (p.299): "Whenever you are instructed to damage a
## piece of armour, the APs in the location damaged are reduced by 1."
## Tracked per-specific-piece (by name) on the character rather than
## mutating the shared ArmourDefinition resource (which every character
## wearing that same armour type points at) — AND, per the RAW wording
## above and a real bug-report correction ("a Leather Jack has 3
## locations, Body, Left Arm, Right Arm, each with its own 1 AP — for it
## to be completely destroyed all 3 locations need to be at 0 AP, not
## just the one that got hit"), genuinely per-LOCATION within that one
## piece too: piece_name -> {location: String -> points_spent: int}.
## A piece's flat `armour_points` rating (see ArmourDefinition) still
## applies independently to EVERY location it covers — damaging it at
## Body doesn't touch its own separate pool at Left Arm. An earlier pass
## of this project tracked damage per-location-only (with no piece
## dimension) and was changed to per-piece-only when armour layering
## (up to 3 distinct pieces covering one location at once) was added,
## reasoning that "damage has to land on one specific piece, not a
## shared location-wide pool" — true, but that only decides WHICH piece
## absorbs a hit (still resolved by _pick_armour_to_damage below); it
## doesn't mean that one piece's own damage has to be a single pool
## across every location it happens to cover. This dict nests both:
## piece first (to keep layering correct), location second (to keep
## each of that piece's own locations correct). Old saves may still have
## a flat piece_name -> int here from before this fix — see
## _normalized_armour_damage() below for the one-time migration.
@export var armour_damage: Dictionary = {}

## Broken armour (per the request: "a piece of Armor need[s] to go to
## AP 0 on all locations before it is destroyed, if that happens
## unequip it and note it as Broken. Broken item[s] can not be repaired
## and have only 10% their original value."): piece_name -> how many
## Broken copies this character currently owns. Now that armour_damage
## (above) is genuinely tracked per-location, reaching this state means
## every location the piece covers has independently hit AP 0 — see
## damage_armour_piece()'s own destruction check. A Broken piece leaves
## `inventory` and `equipped_armour` entirely (it can no longer be worn
## or repaired), but isn't deleted outright — it's tracked here instead
## so it can still be sold for salvage (see shop_screen.gd's
## BROKEN_SELL_FRACTION), same as any other owned item.
@export var broken_armour: Dictionary = {}

## Returns armour_damage[piece_name] as a genuine {location: int} dict,
## migrating it in place if it's still the old flat int format from
## before per-location tracking (a save made before this fix, or a
## piece never touched at all -> defaults to an empty dict). Migration
## applies the old single count to every location the piece covers,
## since the old format couldn't distinguish where the damage actually
## landed — an approximation, but far better than crashing on `int(Dictionary)`
## or silently discarding the character's existing damage state.
func _normalized_armour_damage(piece_name: String) -> Dictionary:
	var raw = armour_damage.get(piece_name, {})
	if typeof(raw) == TYPE_DICTIONARY:
		return raw
	var migrated: Dictionary = {}
	var old_count := int(raw)
	if old_count > 0 and GameData != null and GameData.armour_db != null:
		var ad: ArmourDefinition = GameData.armour_db.find_by_name(piece_name)
		if ad != null:
			for loc in ad.locations:
				migrated[loc] = old_count
	armour_damage[piece_name] = migrated
	return migrated

func _armour_damage_at(piece_name: String, location: String) -> int:
	return int(_normalized_armour_damage(piece_name).get(location, 0))

## Total Armour Damage points spent on this piece across every location
## it covers — used where a single "how banged up is this?" number is
## wanted (Repair tab condition/cost), as opposed to the per-location
## figure combat itself cares about.
func get_total_armour_damage(piece_name: String) -> int:
	var total := 0
	for v in _normalized_armour_damage(piece_name).values():
		total += int(v)
	return total

## Public per-location accessor for _armour_damage_at() above — used by
## character_menu_screen.gd's Inventory and Equipment tabs (per the
## request: "show damaged items, mark them red and reduce dmg/ap on the
## appropriate location") to display a piece's effective remaining AP at
## one specific covered location, the same figure get_armour_points()
## already factors into combat.
func get_armour_damage_at(piece_name: String, location: String) -> int:
	return _armour_damage_at(piece_name, location)

## Weapon Damage durability — a real fumble result ("your weapon takes
## 1 point of damage") tracked per-character, per-weapon-name, same
## reasoning as armour_damage: mutating the shared WeaponDefinition
## would lower everyone else's copy of that weapon too.
@export var weapon_damage_taken: Dictionary = {}

## Applies 1 point of durability damage to a specific, named equipped
## weapon. Indestructible weapons ignore this entirely. Destruction is
## judged against the weapon's own damage_flat rating reaching 0 — not
## the total Damage including Strength Bonus, since SB isn't part of
## the weapon itself and a strong character's weapon shouldn't seem
## immune just because SB alone keeps the total positive.
func damage_weapon(weapon_name: String) -> bool:
	if GameData == null or GameData.weapon_db == null:
		return false
	var wd: WeaponDefinition = GameData.weapon_db.find_by_name(weapon_name)
	## Unbreakable (p.298): "This weapon cannot be broken or destroyed by
	## any means" — exempts it from ordinary Weapon Damage the same way
	## is_indestructible (a magic item) already does.
	if wd == null or wd.is_indestructible or wd.qualities.has("Unbreakable"):
		return false
	weapon_damage_taken[weapon_name] = int(weapon_damage_taken.get(weapon_name, 0)) + 1
	## Durable (p.301): "+Durable Damage points before it suffers any
	## negatives" — raises the ordinary damage_flat breakage threshold by
	## the item's own Durable rating (0 if it doesn't have the Quality).
	var threshold: int = wd.damage_flat + ItemQualityRules.extra_durability_points(wd.item_qualities)
	if int(weapon_damage_taken.get(weapon_name, 0)) >= threshold:
		if equipped_weapon == weapon_name:
			equipped_weapon = ""
		if equipped_offhand == weapon_name:
			equipped_offhand = ""
		inventory.erase(weapon_name)
		weapon_damage_taken.erase(weapon_name)
		return true   ## destroyed
	return true   ## damaged but survives

## Outright destruction — distinct from damage_weapon()'s gradual 1-point
## durability loss. Used by Trap Blade's Astounding Success (p.298: "the
## weapon is broken outright") and by the Shoddy Flaw (p.302: "breaks
## when used in any failed Test rolling a double"), both of which snap
## the weapon in one go rather than chipping away at it. Still respects
## is_indestructible/Unbreakable (checked by the caller before this is
## ever invoked, same as every other destruction path in this project)
## but doesn't re-check them itself, since a caller-side check lets Trap
## Blade's own "unless Unbreakable" wording stay visible at the call
## site rather than buried in here.
##
## Durable (p.301) grants a genuine saving throw against exactly this
## kind of instant breakage — "9+ on a 1d10 roll... improves by 1 each
## time [Durable is] taken" — rolled here (not caller-side) so every
## instant-break source gets it uniformly. `forced_roll` lets tests
## pin the die the same way TestResolver.resolve()'s own forced_roll
## does. Returns true if the weapon was actually destroyed, false if a
## Durable save spared it.
func destroy_weapon(weapon_name: String, forced_roll: int = -1) -> bool:
	if GameData != null and GameData.weapon_db != null:
		var wd: WeaponDefinition = GameData.weapon_db.find_by_name(weapon_name)
		if wd != null:
			var durable_rating := ItemQualityRules.rating_of(wd.item_qualities, "Durable")
			if durable_rating > 0:
				var roll: int = forced_roll if forced_roll >= 1 else Dice.d10()
				if roll >= ItemQualityRules.durable_save_target(durable_rating):
					return false   ## Durable saving throw succeeded — survives
	if equipped_weapon == weapon_name:
		equipped_weapon = ""
	if equipped_offhand == weapon_name:
		equipped_offhand = ""
	inventory.erase(weapon_name)
	weapon_damage_taken.erase(weapon_name)
	return true

## Parry (p.296): "Any one-handed weapon with the Defensive Quality can
## be used with Melee (Parry)" — a genuine player choice, not automatic
## (some players would rather keep defending with the weapon's own
## Group, e.g. if they have more Advances there than in Parry itself).
## Set from the Character Menu's Weapons sub-tab (see
## character_menu_screen.gd's "Use Melee (Parry)" checkbox on an
## eligible equipped weapon) and keyed by weapon NAME rather than
## equip slot, so unequipping and later re-equipping that same weapon
## remembers the choice automatically. Defaults to false (use the
## weapon's own Group) for anything never explicitly toggled.
@export var parry_preference: Dictionary = {}

## Whether this character currently wants to defend with `weapon` using
## Melee (Parry) instead of the weapon's own skill_group — only
## meaningful (and only ever offered in the UI) for a one-handed
## Defensive weapon; anything else always defends with its own Group
## regardless of what's stored here.
func wants_parry_skill(weapon: WeaponDefinition) -> bool:
	if weapon == null:
		return false
	return bool(parry_preference.get(weapon.weapon_name, false))

## Per the "implement Ammunition fully... allow switching ammo" request:
## which Ammunition-category item this character has selected to load
## into a given ranged weapon, keyed by weapon NAME (same convention as
## parry_preference above, for the same "survives unequip/re-equip"
## reason). Set from the Character Menu's equipment-menu ammo selector
## and the mid-combat "Switch Ammo" Free Action (field_encounter_screen
## .gd's _apply_ammo_switch()). A weapon with no entry here — or whose
## selected ammo has run out — simply falls back to AmmoLookup's own
## fixed preference order, exactly like every save from before this
## feature existed; see get_active_ammo_item() below.
@export var active_ammo: Dictionary = {}

func get_armour_points(location: String) -> int:
	var total := 0
	## Armour Creature Trait (p.338): "Rating Armour Points on all Hit
	## Locations" — a natural hide/carapace, not equipped gear, so it
	## applies everywhere regardless of location and stacks with any
	## actual armour equipped on top of it.
	total += get_creature_trait_rating("Armour")
	if GameData == null or GameData.armour_db == null:
		return total
	for piece_name in equipped_armour:
		var ad: ArmourDefinition = GameData.armour_db.find_by_name(piece_name)
		if ad and ad.locations.has(location):
			var piece_ap: int = ad.armour_points - _armour_damage_at(piece_name, location)
			total += max(0, piece_ap)
	return total

## Penetrating Quality (p.297): "Non-metal APs are ignored, and the
## first point of all other armour is ignored." Light tier (Leather)
## counts as non-metal and contributes nothing at all here; Medium
## (Mail) and Heavy (Plate) each lose 1 AP off their own contribution
## — per piece, not off the combined total, since "the first point" is
## most naturally read as applying once per piece of armour struck.
func get_armour_points_penetrating(location: String) -> int:
	## Real bug fix: the Armour Creature Trait (a natural hide/carapace,
	## not equipped gear) was being omitted entirely here, meaning any
	## armoured monster (Clanrat, Stormvermin, Troll, Ogre, Gor, etc.)
	## hit by a Penetrating weapon lost its entire natural armour
	## instead of just having its EQUIPPED armour reduced. Penetrating's
	## own wording ("the first point of all OTHER armour is ignored")
	## specifically targets worn armour — a creature's own hide isn't
	## equipment, so it stays unaffected by Penetrating, same as
	## get_armour_points() above.
	var total := get_creature_trait_rating("Armour")
	if GameData == null or GameData.armour_db == null:
		return total
	for piece_name in equipped_armour:
		var ad: ArmourDefinition = GameData.armour_db.find_by_name(piece_name)
		if ad and ad.locations.has(location) and ad.armor_tier != "Light":
			var piece_ap: int = ad.armour_points - _armour_damage_at(piece_name, location) - 1
			total += max(0, piece_ap)
	return total

## Attack-aware Armour Points at `location`, folding in Penetrating
## (p.297, per-piece, same rule as get_armour_points_penetrating() above)
## plus the two per-piece Armour Flaws (p.300):
## - Partial: "An even roll to hit, or any Critical Hit, ignores this
##   piece's AP entirely" at the struck location.
## - Weakpoints: "An Impale weapon that scores a Critical ignores this
##   piece's AP entirely" at the struck location.
## Used only by CombatResolver._apply_hit's own soak calculation — every
## other caller (AI target-weighting, riposte soak, Critical Deflection,
## etc.) keeps using the plain get_armour_points()/
## get_armour_points_penetrating() above, unaffected by a specific
## attack's roll. `is_penetrating`/`is_impale` are passed in by the
## caller (already computed from the attacker's own effective, training-
## gated Qualities) rather than re-derived here, since Character has no
## reason to know which weapon Quality-gating rules apply to the
## ATTACKER's own training.
func get_armour_points_for_attack(location: String, hitting_roll: int, is_critical: bool, is_penetrating: bool, is_impale: bool) -> int:
	var total := get_creature_trait_rating("Armour")
	if GameData == null or GameData.armour_db == null:
		return total
	var hit_roll_is_even: bool = (hitting_roll % 2) == 0
	for piece_name in equipped_armour:
		var ad: ArmourDefinition = GameData.armour_db.find_by_name(piece_name)
		if ad == null or not ad.locations.has(location):
			continue
		if ad.qualities.has("Partial") and (hit_roll_is_even or is_critical):
			continue   ## this piece's AP is ignored entirely for this hit
		if ad.qualities.has("Weakpoints") and is_impale and is_critical:
			continue   ## this piece's AP is ignored entirely for this hit
		if is_penetrating and ad.armor_tier == "Light":
			continue   ## Penetrating: non-metal APs are ignored outright
		var piece_ap: int = ad.armour_points - _armour_damage_at(piece_name, location)
		if is_penetrating:
			piece_ap -= 1   ## Penetrating: the first point of all other armour is ignored
		total += max(0, piece_ap)
	return total

## Impenetrable (p.300): "This location cannot suffer a Critical Wound
## triggered by an odd double (11/33/55/77/99)" while covered by an
## Impenetrable piece — checked by CombatResolver._apply_hit, which owns
## the actual "was this specific roll an odd double" logic (this method
## only answers "is the location covered," not "does this hit qualify").
func has_impenetrable_armour_at(location: String) -> bool:
	if GameData == null or GameData.armour_db == null:
		return false
	for piece_name in equipped_armour:
		var ad: ArmourDefinition = GameData.armour_db.find_by_name(piece_name)
		if ad and ad.locations.has(location) and ad.qualities.has("Impenetrable"):
			return true
	return false

## Which equipped pieces actually cover this location, worst-damaged
## (soonest to break) first if `prefer_most_damaged` else best-AP
## (heaviest tier) first — used to pick which single piece absorbs a
## point of Armour Damage, since several can now cover one location.
func get_equipped_armour_at_location(location: String) -> Array[ArmourDefinition]:
	var pieces: Array[ArmourDefinition] = []
	if GameData == null or GameData.armour_db == null:
		return pieces
	for piece_name in equipped_armour:
		var ad: ArmourDefinition = GameData.armour_db.find_by_name(piece_name)
		if ad and ad.locations.has(location):
			pieces.append(ad)
	return pieces

## Critical Deflection (p.299): "You still suffer all normal Wounds...
## but you avoid the Critical Wound effects as the blow is absorbed by
## your now-damaged armour." Requires actual armour with AP > 0 at that
## location — nothing to damage otherwise. Indestructible (magic) items
## can still absorb the blow narratively but are never the ones chosen
## to take the damage if a mundane alternative is available; if every
## piece there is indestructible, deflection has nothing to spend and
## fails, same as having no armour there at all.
func can_deflect_critical_wound(location: String) -> bool:
	return _pick_armour_to_damage(location) != null

func deflect_critical_wound(location: String) -> bool:
	var target_piece := _pick_armour_to_damage(location)
	if target_piece == null:
		return false
	return damage_armour_piece(target_piece.armour_name, location)

## Applies 1 point of Armour Damage to a specific, named equipped piece
## AT A SPECIFIC LOCATION — shared by Critical Deflection and the Hack
## weapon Quality (p.298: "If you hit an opponent, you Damage a struck
## piece of armour... by 1 point"). Indestructible pieces silently
## ignore this (no damage, no destruction) — real, book-and-request-
## consistent behaviour, not a missing case. Only once EVERY location
## this piece covers has independently reached its own AP cap (per the
## correction: "a Leather Jack has 3 locations... for it to be
## completely destroyed all 3 locations need to be at 0 AP") does the
## whole piece finally break — it's then unequipped and moved into
## broken_armour instead of being deleted outright, see that field's
## own comment for why.
func damage_armour_piece(piece_name: String, location: String) -> bool:
	if GameData == null or GameData.armour_db == null:
		return false
	var ad: ArmourDefinition = GameData.armour_db.find_by_name(piece_name)
	if ad == null or ad.is_indestructible:
		return false
	var per_location := _normalized_armour_damage(piece_name)
	per_location[location] = int(per_location.get(location, 0)) + 1
	armour_damage[piece_name] = per_location

	## Durable (p.301): extra points of damage this piece can take at
	## EACH location before that location counts toward being fully
	## destroyed, same "+Durable Damage points before it suffers any
	## negatives" rule as weapons (see damage_weapon() above).
	var threshold: int = ad.armour_points + ItemQualityRules.extra_durability_points(ad.item_qualities)
	var fully_destroyed := true
	for loc in ad.locations:
		if int(per_location.get(loc, 0)) < threshold:
			fully_destroyed = false
			break
	if fully_destroyed:
		equipped_armour.erase(piece_name)
		inventory.erase(piece_name)
		armour_damage.erase(piece_name)
		broken_armour[piece_name] = int(broken_armour.get(piece_name, 0)) + 1
		return true   ## destroyed -> now Broken
	return true   ## damaged but survives (at least one other location it covers is still intact)

## Outright destruction of an armour piece — the armour equivalent of
## destroy_weapon(), used by the Shoddy Flaw (p.302: "Shoddy armour
## breaks if any Critical Hit is sustained to a Hit Location it
## protects"), an instant break rather than damage_armour_piece()'s
## gradual per-location tally. Respects is_indestructible and grants the
## same Durable saving throw as destroy_weapon() (9+ on a 1d10,
## improving with a higher Durable rating). Returns true if the piece
## was actually destroyed, false if it was exempt or a Durable save
## spared it.
func destroy_armour_piece(piece_name: String, forced_roll: int = -1) -> bool:
	if GameData == null or GameData.armour_db == null:
		return false
	var ad: ArmourDefinition = GameData.armour_db.find_by_name(piece_name)
	if ad == null or ad.is_indestructible:
		return false
	var durable_rating := ItemQualityRules.rating_of(ad.item_qualities, "Durable")
	if durable_rating > 0:
		var roll: int = forced_roll if forced_roll >= 1 else Dice.d10()
		if roll >= ItemQualityRules.durable_save_target(durable_rating):
			return false   ## Durable saving throw succeeded — survives
	equipped_armour.erase(piece_name)
	inventory.erase(piece_name)
	armour_damage.erase(piece_name)
	broken_armour[piece_name] = int(broken_armour.get(piece_name, 0)) + 1
	return true

## Picks which equipped piece at `location` should absorb a point of
## Armour Damage: the piece with the most AP remaining AT THIS LOCATION
## specifically (the heaviest, outermost layer is the one actually
## taking the brunt of a blow), skipping indestructible pieces entirely
## since they're never the ones damaged. Returns null if nothing
## eligible covers the location (including a piece that still has AP
## left at OTHER locations it covers, but is already used up at this
## one specifically).
func _pick_armour_to_damage(location: String) -> ArmourDefinition:
	var best: ArmourDefinition = null
	var best_remaining := -1
	for ad in get_equipped_armour_at_location(location):
		if ad.is_indestructible:
			continue
		var remaining: int = ad.armour_points - _armour_damage_at(ad.armour_name, location)
		if remaining > 0 and remaining > best_remaining:
			best = ad
			best_remaining = remaining
	return best

func get_equipped_weapon() -> WeaponDefinition:
	## CORRECTED per the report ("Elrohir currently still has Flaming
	## sword out of combat and can not clear it... Unequipping it turns
	## it into a sword, but re-equipping to the main hand turns it back
	## into flaming sword"): flaming_sword_rounds_remaining only ever
	## ticks down once per Round via CombatEncounter._on_round_end() —
	## nothing decrements it out in the overworld, so any fight that
	## ended mid-Duration (including, before this same build's own
	## _end_battle() fix existed, literally any fight at all) left it
	## stuck permanently > 0 on the Character. Unequipping just changes
	## `equipped_weapon` so it briefly stops matching flaming_sword_
	## item_name — it never actually clears the stuck timer, so
	## re-equipping the very same Sword immediately re-triggers the
	## override. Fixed by treating the enchant as unconditionally
	## expired the instant there's no live field encounter running at
	## all (GameState.in_field_encounter) — town, the overworld map, a
	## dungeon corridor between fights — and clearing it for good right
	## here, so simply being out of combat self-heals even an
	## already-stuck Character the very next time this is called, with
	## no save/reload and no need to wait for a fresh fight to run
	## enough Rounds to burn the stale counter down.
	if flaming_sword_rounds_remaining > 0 and not GameState.in_field_encounter:
		flaming_sword_rounds_remaining = 0
		flaming_sword_weapon = null
		flaming_sword_item_name = ""
	## Flaming Sword of Rhuin's own enchant — see flaming_sword_
	## rounds_remaining's own comment. Checked first, and requires the
	## exact item this enchant is bound to still be equipped, so
	## switching away from the enchanted blade correctly falls through
	## to that new item's own normal stats instead.
	if flaming_sword_rounds_remaining > 0 and flaming_sword_weapon != null and equipped_weapon == flaming_sword_item_name:
		return flaming_sword_weapon
	## Sigmar's Fiery Hammer — same "self-heal the instant there's no
	## live field encounter at all" fix as Flaming Sword of Rhuin just
	## above, plus its own extra condition: the rename is tied to the
	## "Sigmar's Fiery Hammer" active_buffs entry rather than a separate
	## counter (see fiery_hammer_weapon's own comment), so it also clears
	## the moment that specific buff itself is gone (naturally expired,
	## or removed early by remove_active_buff()) even mid-encounter.
	if fiery_hammer_weapon != null and (not GameState.in_field_encounter or not has_active_buff("Sigmar's Fiery Hammer")):
		fiery_hammer_weapon = null
		fiery_hammer_item_name = ""
	if fiery_hammer_weapon != null and equipped_weapon == fiery_hammer_item_name:
		return fiery_hammer_weapon
	if GameData == null or GameData.weapon_db == null or equipped_weapon == "":
		return null
	return GameData.weapon_db.find_by_name(equipped_weapon)

func get_offhand_weapon() -> WeaponDefinition:
	if GameData == null or GameData.weapon_db == null or equipped_offhand == "":
		return null
	return GameData.weapon_db.find_by_name(equipped_offhand)

## A two-handed main weapon (p.293's Weapon Group format: "(2H)" —
## tracked here via skill_group, since that's how this project already
## distinguishes them) can't be combined with anything in the off-hand.
func main_weapon_is_two_handed() -> bool:
	var w := get_equipped_weapon()
	return w != null and w.is_two_handed

## --- Weapon Groups (p.296) -----------------------------------------------
## "All melee weapons are assigned to a Weapon Group. Each Weapon Group
## requires a separate skill to master its use... If you use a weapon
## from a Group where you have no Advances, you Test your Weapon Skill
## to hit with the weapon." Whether a given weapon is genuinely trained
## for THIS character — same "is Melee (Basic) exempt" semantics
## shop_screen.gd's own _is_weapon_trained already established (Melee
## itself is not an Advanced skill, so "Melee (Basic)" alone stays
## usable at full effect with zero Advances, unlike every other Melee
## group and every Ranged group). Extracted here so the real combat
## math (see get_effective_weapon_qualities/can_use_ranged_weapon below)
## and the Shop's own display both read off one single source of truth.
func is_trained_in_weapon_group(weapon: WeaponDefinition) -> bool:
	if weapon == null:
		return true
	if not weapon.is_ranged and weapon.skill_group == "Basic":
		return true
	var skill_def: SkillDefinition = GameData.skill_db.find_by_name("Ranged" if weapon.is_ranged else "Melee")
	if skill_def == null:
		return true
	return skill_advances.has(skill_def.display_name(weapon.skill_group))

## "Ranged weapons are difficult to master. You cannot attempt a Ranged
## Test for a weapon you do not have the correct speciality for..."
## unlike Melee (which always falls back to a Weapon Skill Test), an
## untrained Ranged group is a genuine hard block — UNLESS one of the
## book's own named exceptions applies:
## - Crossbows and Throwing (p.296): "relatively simple to use... attempt
##   a Ranged (Crossbow) or Ranged (Throwing) Test using your Ballistic
##   Skill" — always attemptable (Qualities lost regardless, see
##   get_effective_weapon_qualities).
## - Blackpowder and Explosives (p.296): "Those with Ranged (Engineering)
##   can use Blackpowder and Explosive weapons without penalty."
## - Engineering (p.296): "All Engineering weapons can be used by
##   characters with Ranged (Blackpowder)" (Qualities lost — the
##   Engineering<->Blackpowder exception is asymmetric, see
##   get_effective_weapon_qualities for which direction keeps them).
func can_use_ranged_weapon(weapon: WeaponDefinition) -> bool:
	if weapon == null or not weapon.is_ranged:
		return true
	if is_trained_in_weapon_group(weapon):
		return true
	if weapon.skill_group == "Crossbow" or weapon.skill_group == "Throwing":
		return true
	var ranged_skill: SkillDefinition = GameData.skill_db.find_by_name("Ranged")
	if ranged_skill == null:
		return false
	if weapon.skill_group == "Engineering":
		return skill_advances.has(ranged_skill.display_name("Blackpowder"))
	if weapon.skill_group == "Blackpowder" or weapon.skill_group == "Explosives":
		return skill_advances.has(ranged_skill.display_name("Engineering"))
	return false

## "While you still suffer all the weapon's Flaws, you cannot use any of
## its Qualities." The effective Qualities+Flaws list this character
## actually fights with, for a weapon whose group they may or may not be
## trained in — see WeaponDefinition.WEAPON_FLAWS for which of a
## weapon's `qualities` entries are Flaws (always kept) vs. Qualities
## (lost when untrained/using a fallback skill).
##
## Two named exceptions layer on top of the plain untrained case:
## - Flail (p.296): "Unskilled characters add the Dangerous Weapon Flaw
##   to their Flails" — added even when the weapon's own data doesn't
##   already list it.
## - Blackpowder/Explosives via Ranged (Engineering) (p.296): used
##   "without penalty" — i.e. full Qualities, not stripped, unlike every
##   other untrained/fallback case.
##
## Per the "implement Ammunition fully" request: whatever Ammunition
## item is currently loaded (see get_active_ammo_item below) unions its
## own ammo_added_qualities in at the very end, on top of whichever of
## the above cases applied — restructured to build into a local
## `effective` var instead of early-returning `weapon.qualities`
## directly, so there's always a single array to union ammo onto.
## round_number is only needed to resolve the free Sling Round-1 shot
## (see get_active_ammo_item/has_ammo_for) and defaults to -1 ("not
## Round 1") for any caller that doesn't track rounds.
func get_effective_weapon_qualities(weapon: WeaponDefinition, round_number: int = -1) -> Array[String]:
	if weapon == null:
		return []
	var effective: Array[String] = []
	var full_qualities := is_trained_in_weapon_group(weapon)
	if not full_qualities and weapon.is_ranged and (weapon.skill_group == "Blackpowder" or weapon.skill_group == "Explosives"):
		var ranged_skill: SkillDefinition = GameData.skill_db.find_by_name("Ranged")
		if ranged_skill != null and skill_advances.has(ranged_skill.display_name("Engineering")):
			full_qualities = true
	if full_qualities:
		effective = weapon.qualities.duplicate()
	else:
		for q in weapon.qualities:
			## "Reload N" is a rated Flaw (like "Shield N" is a rated
			## Quality elsewhere) — matched by prefix since the fixed
			## WEAPON_FLAWS list can't hold every rating's own string.
			if WeaponDefinition.WEAPON_FLAWS.has(q) or q.begins_with("Reload "):
				effective.append(q)
		if not weapon.is_ranged and weapon.skill_group == "Flail" and not effective.has("Dangerous"):
			effective.append("Dangerous")
	var active_ammo_item: ItemDefinition = get_active_ammo_item(weapon, round_number)
	if active_ammo_item != null:
		for bonus in active_ammo_item.ammo_added_qualities:
			effective = _apply_ammo_quality_bonus(effective, bonus)
	return effective

## Unions one entry from an ammo item's ammo_added_qualities onto
## `effective` (the weapon's own effective-qualities array so far),
## returning the updated array. Plain quality names (e.g. "Impale",
## "Accurate", "Penetrating", "Pummel") are added if not already
## present. The one special case is a rated "Blast +N" string (only
## Small Shot and Powder uses this today) — that increments the
## weapon's existing "Blast"/"Blast N" rating by N instead of being
## unioned in literally (adding a fresh "Blast N" entry if the weapon
## had no Blast Quality of its own at all). combat_resolver.gd's own
## Blast handling only ever checks for the Quality's presence, never
## reads the numeric rating, so this is mostly for correct display/
## future-proofing rather than changing Blast's actual mechanics today.
static func _apply_ammo_quality_bonus(effective: Array[String], bonus: String) -> Array[String]:
	var result: Array[String] = effective.duplicate()
	if bonus.begins_with("Blast +"):
		var add_amount: int = int(bonus.substr(7).strip_edges())
		var idx := -1
		var current := 0
		for i in result.size():
			if result[i] == "Blast":
				idx = i
				current = 1
				break
			elif result[i].begins_with("Blast "):
				idx = i
				current = int(result[i].substr(6).strip_edges())
				break
		var new_rating: int = current + add_amount
		if idx >= 0:
			result[idx] = "Blast %d" % new_rating
		else:
			result.append("Blast %d" % new_rating)
		return result
	if not result.has(bonus):
		result.append(bonus)
	return result

## `weapon`'s range_yards, adjusted by whichever ammo is currently
## loaded (see get_active_ammo_item) — halved first if the ammo's
## ammo_range_halves is set (e.g. Improvised Shot and Powder), then
## offset by ammo_range_bonus (e.g. Elf Arrow's +50, Lead Bullet's
## -10), clamped so it never goes negative. Melee/Throwing weapons and
## a ranged weapon with no matching ammo currently in stock just return
## the weapon's own range_yards unchanged.
func get_effective_weapon_range(weapon: WeaponDefinition) -> int:
	if weapon == null:
		return 0
	var r: int = weapon.range_yards
	var active_ammo_item: ItemDefinition = get_active_ammo_item(weapon)
	if active_ammo_item != null:
		if active_ammo_item.ammo_range_halves:
			r = int(r / 2.0)
		r += active_ammo_item.ammo_range_bonus
	return maxi(0, r)

## --- Ammunition (p.294) --------------------------------------------------
## "Without it you can't shoot" — Bow/Crossbow/Sling/Blackpowder all need
## a matching Ammunition-category item in `inventory`; see AmmoLookup for
## which item name(s) count for which weapon. Melee and Throwing weapons
## always report true here (AmmoLookup.needs_ammo returns false for
## them), so callers that check "can this weapon actually fire" don't
## need their own separate melee/Throwing special case.

## How many rounds of ammo this weapon could currently fire, counting
## every acceptable ammo name's own stock in inventory together (a Sling
## with both Lead Bullet and Stone Bullet on hand can fire either, so
## both counts add up). Melee/Throwing weapons return -1 ("not tracked/
## not applicable" — distinct from 0, which would misleadingly read as
## "out of ammo").
func get_ammo_count_for(weapon: WeaponDefinition) -> int:
	if not AmmoLookup.needs_ammo(weapon):
		return -1
	var total := 0
	for ammo_name in AmmoLookup.required_ammo_names(weapon):
		total += inventory.count(ammo_name)
	return total

## True if `weapon` can actually be fired right now — either it needs no
## ammo at all, real ammo is stocked, or (Sling only) it's genuinely
## Round 1 of the fight, where a free improvised rock is always assumed
## on hand even with zero Stone/Lead Bullet in inventory. `round_number`
## is passed in rather than read from a global, since Character has no
## direct reference to the current CombatEncounter.
func has_ammo_for(weapon: WeaponDefinition, round_number: int = -1) -> bool:
	if not AmmoLookup.needs_ammo(weapon):
		return true
	if get_ammo_count_for(weapon) > 0:
		return true
	return AmmoLookup.is_sling(weapon) and round_number == 1

## The ItemDefinition for whichever Ammunition this character actually
## has loaded into `weapon` right now — the type explicitly selected via
## `active_ammo` (equipment menu / mid-combat Switch Ammo) if it's still
## in stock, otherwise falling back to AmmoLookup's own fixed preference
## order (same order consume_ammo_for uses), so a save with no
## selection at all — or one whose selected type just ran out —
## degrades gracefully to "whatever's on hand" exactly like this
## project's pre-Ammunition-feature behavior. Returns null for melee/
## Throwing weapons (AmmoLookup.needs_ammo is false, no ammo concept at
## all) and whenever nothing acceptable is actually in inventory —
## including the free Sling Round-1 shot, which has no physical item to
## read Range/Damage/Qualities bonuses from.
func get_active_ammo_item(weapon: WeaponDefinition, round_number: int = -1) -> ItemDefinition:
	if weapon == null or not AmmoLookup.needs_ammo(weapon):
		return null
	var acceptable: Array[String] = AmmoLookup.required_ammo_names(weapon)
	var selected: String = String(active_ammo.get(weapon.weapon_name, ""))
	if selected != "" and acceptable.has(selected) and inventory.has(selected):
		return GameData.item_db.find_by_name(selected)
	for ammo_name in acceptable:
		if inventory.has(ammo_name):
			return GameData.item_db.find_by_name(ammo_name)
	return null

## Consumes one unit of whichever acceptable ammo `weapon` actually has
## in stock, returning the item name consumed — or "" if nothing was
## consumed (no ammo needed, or the free Sling Round-1 shot, which has
## no physical item to remove). Prefers this character's explicit
## `active_ammo` selection (see get_active_ammo_item) when it's still in
## stock, falling back to AmmoLookup's own fixed preference order
## otherwise — identical fallback behavior to every save from before
## the ammo-switching feature existed. Callers should call this exactly
## once per shot fired, regardless of hit/miss — and NOT again on a
## Fortune-spend reroll of the same shot, since a reroll re-resolves the
## same Test rather than firing a second time.
func consume_ammo_for(weapon: WeaponDefinition, round_number: int = -1) -> String:
	if not AmmoLookup.needs_ammo(weapon):
		return ""
	var acceptable: Array[String] = AmmoLookup.required_ammo_names(weapon)
	var selected: String = String(active_ammo.get(weapon.weapon_name, ""))
	if selected != "" and acceptable.has(selected) and inventory.has(selected):
		inventory.erase(selected)
		return selected
	for ammo_name in acceptable:
		if inventory.has(ammo_name):
			inventory.erase(ammo_name)
			return ammo_name
	## Nothing in inventory — only reachable via the free Sling Round-1
	## allowance (has_ammo_for already blocks every other no-ammo case
	## before a caller would ever get here).
	return ""

## --- Repeater (Rating) / Reload (Rating) shot-and-reload tracking
## -----------------------------------------------------------------
## Repeater (Rating) (p.298): "This weapon can fire Rating times before
## it needs to be reloaded." Reload (Rating) (p.299, a Flaw): "After
## firing, this weapon requires an Extended (Ranged) Test — Rating
## Success Levels — to reload before it can be fired again." A weapon
## can have either, both (a Repeater weapon that also needs a real
## reload once its magazine empties, e.g. Repeater Handgun), or neither
## (fires and is ready again immediately, no tracking needed at all).
## Entirely separate from the AmmoLookup/consume_ammo_for system above:
## that tracks physical ammo stock (do you have arrows left at all),
## this tracks the weapon's own firing mechanism (is it currently ready
## to go off) — a Bow needs both checked, a Sling only the former, a
## Repeater Handgun both plus this section.
##
## The book's own "an interrupted reload starts over from scratch"
## penalty isn't enforced here — there's no reliable way in this project
## to detect a genuine interruption (an incoming attack mid-reload, etc.)
## without a turn-order/opportunity model this combat system doesn't
## have; reload progress simply persists Round to Round instead, a
## documented simplification.
@export var weapon_shots_remaining: Dictionary = {}   ## weapon_name -> shots left in a Repeater's magazine
@export var weapon_unloaded: Dictionary = {}           ## weapon_name -> bool, true while it needs a Reload Test before firing again
@export var weapon_reload_progress: Dictionary = {}    ## weapon_name -> accumulated SL toward its Reload rating

## The numeric N in a "Repeater N"/"Reload N" Quality/Flaw string on
## `weapon` — 0 if it doesn't have that Quality/Flaw at all. Shared
## parsing helper so record_shot_fired()/attempt_reload() (and any
## future UI code) don't each re-implement the same "find the entry,
## strip the prefix, parse the int" scan.
static func _rated_weapon_value(weapon: WeaponDefinition, prefix: String) -> int:
	if weapon == null:
		return 0
	for q in weapon.qualities:
		if q.begins_with(prefix):
			var rating_str := q.trim_prefix(prefix)
			if rating_str.is_valid_int():
				return int(rating_str)
	return 0

## True if `weapon` is currently ready to fire — false only while it's
## mid-reload (weapon_unloaded). Purely about the firing mechanism;
## physical ammo stock is a separate check (has_ammo_for above) — a
## caller normally wants both to be true before allowing a shot.
func can_fire_weapon(weapon: WeaponDefinition) -> bool:
	if weapon == null:
		return false
	return not bool(weapon_unloaded.get(weapon.weapon_name, false))

## Called once per shot actually fired (hit or miss, same cadence as
## consume_ammo_for above) — advances a Repeater's magazine and/or marks
## a Reload-flawed weapon as needing to reload before its next shot.
func record_shot_fired(weapon: WeaponDefinition) -> void:
	if weapon == null:
		return
	var repeater_rating := _rated_weapon_value(weapon, "Repeater ")
	var reload_rating := _rated_weapon_value(weapon, "Reload ")
	if repeater_rating > 0:
		var remaining: int = int(weapon_shots_remaining.get(weapon.weapon_name, repeater_rating))
		remaining = max(0, remaining - 1)
		if remaining <= 0:
			if reload_rating > 0:
				weapon_unloaded[weapon.weapon_name] = true
				weapon_reload_progress[weapon.weapon_name] = 0
			else:
				## No accompanying Reload Flaw — the magazine simply
				## refills for free (nothing in the book gates a bare
				## Repeater with no Reload rating of its own).
				remaining = repeater_rating
		weapon_shots_remaining[weapon.weapon_name] = remaining
	elif reload_rating > 0:
		weapon_unloaded[weapon.weapon_name] = true
		weapon_reload_progress[weapon.weapon_name] = 0

## Spends the caller's Action on a Reload attempt: an Extended
## (Ranged) Test, accumulating Success Levels in weapon_reload_progress
## until they reach the weapon's own Reload rating, at which point it's
## ready to fire again (and a Repeater's magazine is refilled to full).
## Returns the TestResult so the caller can show a roll card — or null
## if `weapon` has no Reload Flaw at all (nothing to reload).
func attempt_reload(weapon: WeaponDefinition) -> TestResolver.TestResult:
	var reload_rating := _rated_weapon_value(weapon, "Reload ")
	if reload_rating <= 0 or GameData == null or GameData.skill_db == null:
		return null
	var ranged_skill: SkillDefinition = GameData.skill_db.find_by_name("Ranged")
	## Gunner (p.138, Up in Arms): "add SL equal to your rank in Gunner
	## to any Extended Test to reload" a blackpowder weapon specifically
	## — not any Reload-flawed weapon in general (a bow with Reload
	## doesn't qualify).
	var extra_sl: Array = []
	if weapon.qualities.has("Blackpowder"):
		var gunner_rank := get_talent_rank("Gunner")
		if gunner_rank > 0:
			extra_sl.append({"name": "Gunner", "amount": gunner_rank})
	var test := TestResolver.resolve_skill_test(self, ranged_skill, weapon.skill_group, 0, [], -1, extra_sl)
	var progress: int = int(weapon_reload_progress.get(weapon.weapon_name, 0)) + max(0, test.success_levels)
	if progress >= reload_rating:
		weapon_unloaded[weapon.weapon_name] = false
		weapon_reload_progress[weapon.weapon_name] = 0
		var repeater_rating := _rated_weapon_value(weapon, "Repeater ")
		weapon_shots_remaining[weapon.weapon_name] = max(repeater_rating, 1)
	else:
		weapon_reload_progress[weapon.weapon_name] = progress
	return test

## Layering (house rule, per the request): a character may wear up to
## 3 armour pieces covering the same location at once — one per tier
## (Light/Medium/Heavy) — so two pieces only conflict if they're the
## SAME tier AND share a location (e.g. Leather Jack and Leather
## Jerkin, both Light, both covering Body). A Light + a Medium + a
## Heavy piece can all cover Body simultaneously. Returns the names of
## any already-equipped pieces that conflict with `candidate_name`, so
## the caller can block the equip and explain exactly why.
func get_conflicting_equipped_armour(candidate_name: String) -> Array[String]:
	var conflicts: Array[String] = []
	if GameData == null or GameData.armour_db == null:
		return conflicts
	var candidate: ArmourDefinition = GameData.armour_db.find_by_name(candidate_name)
	if candidate == null:
		return conflicts
	for piece_name in equipped_armour:
		if piece_name == candidate_name:
			continue   ## already equipped, not a conflict with itself
		var other: ArmourDefinition = GameData.armour_db.find_by_name(piece_name)
		if other == null or other.armor_tier != candidate.armor_tier:
			continue   ## different tiers layer together — no conflict
		for loc in candidate.locations:
			if other.locations.has(loc):
				conflicts.append(piece_name)
				break
	return conflicts

## --- Save/Load --------------------------------------------------------
## Serialises to a plain, JSON-friendly Dictionary rather than using
## Godot's native resource serialization — race/career are stored as
## name strings and re-linked against GameData on load, so save files
## stay small, human-readable, and robust to future data changes (no
## risk of a save embedding a stale copy of a RaceDefinition/
## CareerDefinition). See SaveManager for the actual file I/O.

func to_save_dict() -> Dictionary:
	var char_values := {}
	for key in CharacteristicSet.KEYS:
		char_values[key] = characteristics.get_value(key)
	return {
		"version": 1,
		"character_name": character_name,
		"gender": gender,
		"race_name": race.race_name if race else "",
		"career_name": career.career_name if career else "",
		"current_tier": current_tier,
		"career_history": career_history,
		"carrying_capacity_override": carrying_capacity_override,
		"characteristics": char_values,
		"characteristic_advances": characteristic_advances,
		"skill_advances": skill_advances,
		## Re-added alongside skill_any_resolved's own crash fix: this
		## counter (how many of a given "(Any)" qualifier's grant slots
		## have been spent) was also silently missing from save/load —
		## every reload reset it to empty, which would have let an
		## already-spent "(Any)" slot be repurchased for free after a
		## save/load round trip. Included here now for the same
		## permanence skill_advances/talents_taken already get.
		"skill_any_purchases": skill_any_purchases,
		"skill_any_resolved": skill_any_resolved,
		"talents_taken": talents_taken,
		"creature_traits": creature_traits,
		"fate_points": fate_points,
		"fortune_points": fortune_points,
		"corruption_points": corruption_points,
		"mutations_gained": mutations_gained,
		"camp_position": [camp_position.x, camp_position.y],
		"armour_damage": armour_damage,
		"broken_armour": broken_armour,
		"weapon_damage_taken": weapon_damage_taken,
		"critical_wound_penalties": critical_wound_penalties,
		"active_critical_wound_count": active_critical_wound_count,
		"resilience": resilience,
		"resolve": resolve,
		"experience_total": experience_total,
		"experience_spent": experience_spent,
		"wounds_current": wounds_current,
		"wounds_max": wounds_max,
		"is_dead": is_dead,
		"inventory": inventory,
		## Per the request: favourited items (starred in the Inventory
		## grid to protect them from the Shop's sell list) were never
		## written to the save file at all — favourite_items existed
		## as a real Character field, read/written correctly by the
		## Inventory and Shop screens, but simply omitted from this
		## dict, so every reload silently reset it back to empty.
		"favourite_items": favourite_items,
		## Per the request ("make sure this remembers this choice when
		## unequipping and reequipping the same weapon"): keyed by
		## weapon name (see wants_parry_skill()), so it survives a
		## save/load round-trip the same way weapon_damage_taken does.
		"parry_preference": parry_preference,
		## Per the "allow switching ammo" request: keyed by weapon name
		## (see get_active_ammo_item()), same survives-unequip/reequip
		## convention as parry_preference just above.
		"active_ammo": active_ammo,
		"gold_crowns": gold_crowns,
		"silver_shillings": silver_shillings,
		"brass_pennies": brass_pennies,
		"allegiance": allegiance,
		"conditions": conditions,
		## Consume Alcohol / Stinking Drunk state — see this same file's
		## alcohol_fail_count declaration comment for the full mechanic.
		"alcohol_fail_count": alcohol_fail_count,
		"is_stinking_drunk": is_stinking_drunk,
		"stinking_drunk_result": stinking_drunk_result,
		"_alcohol_sobering_test_done": _alcohol_sobering_test_done,
		"alcohol_recovery_hours_remaining": alcohol_recovery_hours_remaining,
		"last_drink_time_minutes": last_drink_time_minutes,
		"hangover_lock_hours_remaining": hangover_lock_hours_remaining,
		"cauterise_recovery_hours_remaining": cauterise_recovery_hours_remaining,
		"permanently_scarred": permanently_scarred,
		"equipped_weapon": equipped_weapon,
		"equipped_offhand": equipped_offhand,
		"equipped_armour": equipped_armour,
		"equipped_container_back": equipped_container_back,
		"equipped_container_waist": equipped_container_waist,
		"equipped_container_shoulder": equipped_container_shoulder,
		"sin_points": sin_points,
		"known_spells": known_spells,
		"known_prayers": known_prayers,
		"has_seen_origin_story": has_seen_origin_story,
		"journal_entries": journal_entries,
		"journal_recorded_keys": journal_recorded_keys,
		"quests": quests,
		## Per the request: the in-game clock and calendar previously
		## reset every session — GameState.time_minutes/imperial_year/
		## day_of_year were never actually written to a save file at
		## all, only ever read from them (to stamp Journal entries).
		## Character-scoped rather than a single global save, since
		## multiple save slots should each keep their own character's
		## own point in time.
		"time_minutes": GameState.time_minutes,
		"time_minutes_fraction": GameState.time_minutes_fraction,
		"imperial_year": GameState.imperial_year,
		"day_of_year": GameState.day_of_year,
		## Per the request: which map (and, if it's the World Map,
		## exactly where on it) was actually active gets saved now
		## too — this was previously never written at all (see
		## SaveManager's own now-outdated header comment), which is
		## exactly why reloading always dropped the player back at
		## Giessingen's own local exit tile regardless of where they
		## actually saved from.
		"last_active_map_path": GameState.last_active_map_path,
		"world_map_player_position": [GameState.world_map_player_position.x, GameState.world_map_player_position.y],
		## Follow-up request's own reported bug ("its not saving the
		## city still, i always enter the game outside the city on the
		## overworld map"): see GameState.last_active_city_id's own
		## declaration comment for the full story — same pattern as
		## last_active_map_path just above.
		"last_active_city_id": GameState.last_active_city_id,
		## Per the request ("add a Crafting page to shops..."): pending
		## Crafting orders (see GameState.pending_craft_orders' own
		## comment) — same character-scoped "redundant across every
		## party member's own save dict, restored idempotently" pattern
		## as the clock/calendar fields above, so an order survives a
		## save/load instead of silently vanishing.
		"pending_craft_orders": GameState.pending_craft_orders,
		## Persisted alongside pending_craft_orders itself so order ids
		## stay unique across a save/load (see GameState._next_craft_
		## order_id's own comment) — without this, reloading a save and
		## placing a new order could mint an id that collides with one
		## already sitting in a still-pending order from before the save.
		"next_craft_order_id": GameState._next_craft_order_id,
		## Dungeon Encounter Screen (spec §6): flattened via
		## DungeonGenerator.to_save_data() into plain JSON-safe
		## primitives — the live dungeon_state Dictionary holds real
		## Vector2i/Rect2i values, which Godot's JSON encoder doesn't
		## round-trip on its own. Empty ({}) whenever the party isn't
		## currently inside a dungeon.
		"dungeon_state": DungeonGenerator.to_save_data(GameState.dungeon_state),
	}

## Reconstructs a Character from a Dictionary produced by to_save_dict().
## Returns null if the referenced race/career/etc. can't be found (e.g.
## a save from a version of the data that's since changed).
##
## Note: Godot's JSON parser returns float for every JSON number, even
## ones that were written as plain integers — every numeric field below
## is explicitly wrapped in int()/_int_dict() rather than assigned
## directly, or a later "%d"-formatted display or typed-int assignment
## would silently misbehave.
static func from_save_dict(data: Dictionary) -> Character:
	var c := Character.new()
	c.character_name = str(data.get("character_name", "Unnamed"))
	## Backward compatible: saves written before this bug was fixed have
	## no "gender" key at all, so get() falls back to "male" -- matching
	## a freshly created Character's own default and the pre-fix
	## (accidental) behaviour, rather than guessing.
	c.gender = str(data.get("gender", "male"))
	c.race = GameData.find_race(str(data.get("race_name", "")))
	c.career = GameData.find_career(str(data.get("career_name", "")))
	if c.race == null or c.career == null:
		return null
	c.current_tier = int(data.get("current_tier", 1))
	var loaded_history: Array[Dictionary] = []
	for entry in data.get("career_history", []):
		if entry is Dictionary:
			loaded_history.append(entry)
	c.career_history = loaded_history
	## Backward compatible: any save from before this field existed
	## simply has no key here, and get() falls back to -1 — "unset,
	## use the normal SB+TB formula" — exactly matching a freshly
	## created Character's own default.
	c.carrying_capacity_override = int(data.get("carrying_capacity_override", -1))

	c.characteristics = CharacteristicSet.new()
	var char_values: Dictionary = data.get("characteristics", {})
	for key in CharacteristicSet.KEYS:
		if char_values.has(key):
			c.characteristics.set_value(key, int(char_values[key]))

	c.characteristic_advances = _int_dict(data.get("characteristic_advances", {}))
	c.skill_advances = _int_dict(data.get("skill_advances", {}))
	## Backward compatible: a save from before either field existed (or
	## from the window where they were silently dropped from save/load —
	## see this field's own declaration comment) simply has no key here,
	## and get() falls back to {}/[] — "no (Any) slots recorded yet,"
	## which for skill_any_resolved specifically also matches
	## find_all_chosen_skill_variants()'s own documented fallback to
	## skill_advances.has() alone for anything not in this list.
	c.skill_any_purchases = _int_dict(data.get("skill_any_purchases", {}))
	var loaded_skill_any_resolved: Array[String] = []
	for s in data.get("skill_any_resolved", []):
		loaded_skill_any_resolved.append(str(s))
	c.skill_any_resolved = loaded_skill_any_resolved
	c.talents_taken = _int_dict(data.get("talents_taken", {}))
	var loaded_creature_traits: Array[String] = []
	for t in data.get("creature_traits", []):
		loaded_creature_traits.append(str(t))
	c.creature_traits = loaded_creature_traits
	c.fate_points = int(data.get("fate_points", 0))
	c.fortune_points = int(data.get("fortune_points", 0))
	c.corruption_points = int(data.get("corruption_points", 0))
	var loaded_mutations: Array[String] = []
	for m in data.get("mutations_gained", []):
		loaded_mutations.append(str(m))
	c.mutations_gained = loaded_mutations
	var camp_pos_arr: Array = data.get("camp_position", [-1, -1])
	c.camp_position = Vector2i(int(camp_pos_arr[0]), int(camp_pos_arr[1]))
	c.armour_damage = data.get("armour_damage", {})
	c.broken_armour = data.get("broken_armour", {})
	c.weapon_damage_taken = data.get("weapon_damage_taken", {})
	## A save with no parry_preference key at all (older save file) must
	## still load cleanly to an empty Dictionary, not null — same
	## data.get() default pattern as every other dict field here.
	c.parry_preference = data.get("parry_preference", {})
	## Same "older save with no key at all" fallback as parry_preference
	## just above — an empty Dictionary means every weapon just falls
	## back to AmmoLookup's fixed order, identical to pre-feature behavior.
	c.active_ammo = data.get("active_ammo", {})
	c.critical_wound_penalties = data.get("critical_wound_penalties", [])
	c.active_critical_wound_count = int(data.get("active_critical_wound_count", 0))
	c.resilience = int(data.get("resilience", 1))
	c.resolve = int(data.get("resolve", 1))
	c.experience_total = int(data.get("experience_total", 0))
	c.experience_spent = int(data.get("experience_spent", 0))
	c.wounds_current = int(data.get("wounds_current", 1))
	c.wounds_max = int(data.get("wounds_max", 1))
	c.is_dead = bool(data.get("is_dead", false))

	## Per the request ("make the solution fix any current unusable
	## items if possible"): every loaded item is run back through
	## AmmoLookup.resolve_trapping() so a character saved before the
	## "<Container> containing <contents...>" splitting fix (or before
	## any earlier compound-trapping fix, e.g. "Storm Lantern and Oil")
	## gets migrated automatically the next time their save loads — not
	## just newly-created characters. This is safe to run unconditionally
	## on every load: an already-resolved plain item name (a real
	## ItemDefinition/WeaponDefinition name, or any ordinary shop/loot
	## item) matches none of resolve_trapping()'s known-broken patterns
	## and is returned completely unchanged.
	var inv: Array[String] = []
	for item in data.get("inventory", []):
		inv.append_array(AmmoLookup.resolve_trapping(str(item)))
	c.inventory = inv

	var loaded_favourites: Array[String] = []
	for item in data.get("favourite_items", []):
		loaded_favourites.append(str(item))
	c.favourite_items = loaded_favourites

	c.gold_crowns = int(data.get("gold_crowns", 0))
	c.silver_shillings = int(data.get("silver_shillings", 0))
	c.brass_pennies = int(data.get("brass_pennies", 0))
	c.allegiance = str(data.get("allegiance", "ally"))
	c.conditions = _int_dict(data.get("conditions", {}))
	c.alcohol_fail_count = int(data.get("alcohol_fail_count", 0))
	c.is_stinking_drunk = bool(data.get("is_stinking_drunk", false))
	c.stinking_drunk_result = int(data.get("stinking_drunk_result", 0))
	c._alcohol_sobering_test_done = bool(data.get("_alcohol_sobering_test_done", false))
	c.alcohol_recovery_hours_remaining = float(data.get("alcohol_recovery_hours_remaining", 0.0))
	c.last_drink_time_minutes = int(data.get("last_drink_time_minutes", -1000000))
	c.hangover_lock_hours_remaining = float(data.get("hangover_lock_hours_remaining", 0.0))
	c.cauterise_recovery_hours_remaining = float(data.get("cauterise_recovery_hours_remaining", 0.0))
	c.permanently_scarred = bool(data.get("permanently_scarred", false))
	c.equipped_weapon = str(data.get("equipped_weapon", ""))
	c.equipped_offhand = str(data.get("equipped_offhand", ""))
	c.equipped_container_back = str(data.get("equipped_container_back", ""))
	c.equipped_container_waist = str(data.get("equipped_container_waist", ""))
	c.equipped_container_shoulder = str(data.get("equipped_container_shoulder", ""))

	var armour: Array[String] = []
	for item in data.get("equipped_armour", []):
		armour.append(str(item))
	c.equipped_armour = armour

	c.sin_points = int(data.get("sin_points", 0))

	var spells: Array[String] = []
	for item in data.get("known_spells", []):
		spells.append(str(item))
	c.known_spells = spells

	var prayers: Array[String] = []
	for item in data.get("known_prayers", []):
		prayers.append(str(item))
	c.known_prayers = prayers

	c.has_seen_origin_story = bool(data.get("has_seen_origin_story", false))
	c.journal_entries = data.get("journal_entries", [])
	var journal_keys: Array[String] = []
	for key in data.get("journal_recorded_keys", []):
		journal_keys.append(str(key))
	c.journal_recorded_keys = journal_keys
	c.quests = data.get("quests", [])

	## Per the request: restores the real in-game clock and calendar
	## this character was actually at when last saved, rather than
	## always resetting to the fresh-character defaults (8am,
	## Sigmarzeit 1). Falls back to those same defaults only if this
	## save predates the fix (an old save file with no time fields at
	## all) — a missing value here means "never saved," not "actually
	## midnight."
	GameState.time_minutes = int(data.get("time_minutes", 8 * 60))
	GameState.time_minutes_fraction = float(data.get("time_minutes_fraction", 0.0))
	GameState.imperial_year = int(data.get("imperial_year", 2512))
	GameState.day_of_year = int(data.get("day_of_year", WarhammerCalendar.CHARACTER_CREATION_START_DAY))
	## Per the request: restores which map was actually active — an
	## old save predating this fix has no such field, and Overworld's
	## own _load_map_definition() already falls back correctly to its
	## own default (Giessingen) when this is left empty, so a missing
	## value here doesn't need a special sentinel the way the time
	## fields above do.
	GameState.last_active_map_path = str(data.get("last_active_map_path", ""))
	var world_pos_arr: Array = data.get("world_map_player_position", [-1, -1])
	GameState.world_map_player_position = Vector2i(int(world_pos_arr[0]), int(world_pos_arr[1]))
	## Per the request ("add a Crafting page to shops..."): restores any
	## Crafting orders still awaiting delivery — an old save predating
	## this feature simply has none, same "missing means none yet"
	## convention as dismissed_companions in SaveManager above.
	GameState.pending_craft_orders = data.get("pending_craft_orders", [])
	## Old saves predating the order_id field (or predating this field's
	## own introduction) fall back to 1 — worst case a freshly-placed
	## order's id collides with an old pre-order_id entry that has no
	## "order_id" key at all, which collect_craft_order() simply never
	## matches (int(order.get("order_id", -1)) is -1 for those), so
	## there's no real ambiguity even in that edge case.
	GameState._next_craft_order_id = int(data.get("next_craft_order_id", 1))
	## Follow-up request's own reported bug: restores which city's own
	## CityScreen was actually active, if any — an old save predating
	## this fix has no such field, "" (Overworld) is the correct
	## fallback, same "missing means unset, use the normal default"
	## convention as last_active_map_path just above.
	GameState.last_active_city_id = str(data.get("last_active_city_id", ""))
	## Dungeon Encounter Screen (spec §6) — see to_save_dict()'s own
	## comment on this same field.
	GameState.dungeon_state = DungeonGenerator.from_save_data(data.get("dungeon_state", {}))

	return c

## Converts every value in a Dictionary to int — used for dicts loaded
## from JSON (see the note on from_save_dict above).
static func _int_dict(source: Dictionary) -> Dictionary:
	var result := {}
	for key in source.keys():
		result[key] = int(source[key])
	return result

## Sums up the Success-Level bonus from every talent the character has
## whose "Tests" field matches any of the given scopes (skill name,
## specialisation display name, or linked characteristic key) — the
## ruleset's default rule of +1 SL per rank on a successful Test. Talents
## flagged `overrides_default_test_effect` are skipped here since their
## effect is bespoke (handled elsewhere via effect_tags), not this default.
func get_test_success_level_bonus(scopes: Array) -> int:
	var total := 0
	for entry in get_test_success_level_breakdown(scopes):
		total += entry["amount"]
	return total

## Same matching logic as get_test_success_level_bonus, but returns the
## itemised sources instead of just the total — e.g.
## [{"name": "Berserk Charge", "amount": 2}, {"name": "Battle Rage", "amount": 2}]
## — for UI that wants to show where each point of a modified Success
## Level actually came from, not just the final number.
func get_test_success_level_breakdown(scopes: Array) -> Array:
	var breakdown: Array = []
	if GameData == null or GameData.talent_db == null:
		return breakdown
	for talent_name in talents_taken.keys():
		var td: TalentDefinition = GameData.talent_db.find_by_name(talent_name)
		if td == null or td.overrides_default_test_effect or td.tests.is_empty():
			continue
		## Drilled (Up in Arms p.141): its Bonus Tests line is explicitly
		## scoped ("Melee Tests when beside an ally with Drilled") unlike
		## most Tests-tied Talents, which this project otherwise applies
		## as a flat, unscoped bonus (see Argumentative/Cardsharp's own
		## broadened "when arguing"/"when playing cards" precedent) —
		## this one specifically needed the real adjacency check, so it's
		## gated on drilled_beside_ally, refreshed live by
		## FieldEncounterScreen._refresh_drilled_adjacency() rather than
		## always-on like every other scoped Talent here.
		if talent_name == "Drilled" and not drilled_beside_ally:
			continue
		var matches := false
		for t in td.tests:
			if scopes.has(t):
				matches = true
				break
		if not matches:
			continue
		var rank: int = talents_taken[talent_name]
		breakdown.append({"name": talent_name, "amount": max(rank, 1)})
	return breakdown

## Whether any Talent this character has grants the "reverse the dice of
## a failed Test to see if it would succeed" option for a Test matching
## `scopes` -- e.g. Alley Cat (p.132, Stealth (Urban)), Carouser (p.134,
## Consume Alcohol). These Talents use `overrides_default_test_effect =
## true` (the reversed-roll retry replaces normal resolution rather than
## adding a flat SL bonus), so get_test_success_level_breakdown() above
## -- which explicitly skips override=true Talents -- can't be reused
## for this; matched by `effect_tags` instead.
func has_reverse_dice_on_fail(scopes: Array) -> bool:
	if GameData == null or GameData.talent_db == null:
		return false
	for talent_name in talents_taken.keys():
		var td: TalentDefinition = GameData.talent_db.find_by_name(talent_name)
		if td == null or not td.effect_tags.has("reverse_dice_on_fail"):
			continue
		for t in td.tests:
			if scopes.has(t):
				return true
	return false

## Whether any Talent grants "use the roll's units digit as your Success
## Level instead, if that's better" for a Test matching `scopes` -- e.g.
## Argumentative (p.133, Charm), Cardsharp (p.134, Gamble/Sleight of
## Hand). Same reasoning as has_reverse_dice_on_fail() above for why this
## can't reuse get_test_success_level_breakdown().
func has_units_digit_as_sl(scopes: Array) -> bool:
	if GameData == null or GameData.talent_db == null:
		return false
	for talent_name in talents_taken.keys():
		var td: TalentDefinition = GameData.talent_db.find_by_name(talent_name)
		if td == null or not td.effect_tags.has("units_digit_as_sl"):
			continue
		for t in td.tests:
			if scopes.has(t):
				return true
	return false

## Whether any Talent this character has makes a Test matching `scopes`
## fully unopposed -- e.g. Cat-tongued (p.135): when lying via Charm, the
## listener doesn't get to oppose with Intuition to detect it. This
## project has no general opposed-Test framework outside Social Combat
## for "unopposed" to plug into generically the way the two checks above
## do (there's no equivalent of get_test_success_level_breakdown() for
## "skip the other side's roll entirely"), so this is checked directly
## by the one caller that has an opposed roll to skip -- see
## SocialEncounterScreen._attempt_social_attack()'s own Cat-tongued
## handling -- rather than wired through TestResolver itself.
func has_unopposed_test(scopes: Array) -> bool:
	if GameData == null or GameData.talent_db == null:
		return false
	for talent_name in talents_taken.keys():
		var td: TalentDefinition = GameData.talent_db.find_by_name(talent_name)
		if td == null or not td.effect_tags.has("suppress_intuition_opposition_when_lying"):
			continue
		for t in td.tests:
			if scopes.has(t):
				return true
	return false

## A simple Brass < Silver < Gold ordinal for the character's CURRENT
## Career Level's Status Tier (p.44) -- used by Talents like Beneath
## Notice (p.133) that compare one character's Status against another's.
## Returns 1 (Brass) if the character has no career/level set, matching
## the lowest real Status Tier rather than 0, so an unset character never
## wrongly reads as "higher Status than everyone."
func get_status_ordinal() -> int:
	const ORDER := {"Brass": 1, "Silver": 2, "Gold": 3}
	if career == null:
		return 1
	var level := career.get_level(current_tier)
	if level == null:
		return 1
	return ORDER.get(level.status_tier, 1)

func get_experience_available() -> int:
	return experience_total - experience_spent

## Master Condition List (p.167-169) test penalties — the broad,
## always-apply-to-everything ones (Fatigued/Stunned/Poisoned, -10 per
## stack each) plus the narrower, scope-matched ones (Blinded/Deafened
## approximated onto Perception-linked tests since this project
## doesn't split sight from hearing sub-Tests; Prone/Entangled onto
## movement-flavoured Skills; Broken onto everything except Athletics/
## Stealth, matching "not involving running and hiding"). Returns a
## single-entry breakdown — same shape as
## get_test_success_level_breakdown, for UI that wants to show where
## the penalty came from — since only one Condition's own penalty
## ever actually applies to a given roll. Per the request: multiple
## stacks of the SAME Condition still stack with each other (Fatigued
## x3 is genuinely -30), but different Conditions never stack with one
## another — only the single worst one among everything currently
## applicable is used, not their sum.
func get_condition_test_penalty_breakdown(scopes: Array) -> Array:
	var candidates: Array = []
	var fatigued: int = int(conditions.get("Fatigued", 0))
	if fatigued > 0:
		candidates.append({"name": "Fatigued", "amount": -10 * fatigued})
	var stunned: int = int(conditions.get("Stunned", 0))
	if stunned > 0:
		candidates.append({"name": "Stunned", "amount": -10 * stunned})
	var poisoned: int = int(conditions.get("Poisoned", 0))
	if poisoned > 0:
		candidates.append({"name": "Poisoned", "amount": -10 * poisoned})
	var broken: int = int(conditions.get("Broken", 0))
	if broken > 0 and not scopes.has("Athletics") and not scopes.has("Stealth"):
		candidates.append({"name": "Broken", "amount": -10})
	var sight_or_hearing_scope := scopes.has("Perception") or scopes.has("perception")
	var blinded: int = int(conditions.get("Blinded", 0))
	if blinded > 0 and sight_or_hearing_scope:
		candidates.append({"name": "Blinded", "amount": -10 * blinded})
	var deafened: int = int(conditions.get("Deafened", 0))
	if deafened > 0 and sight_or_hearing_scope:
		## Real bug fix: this used to apply a flat -10 "regardless of
		## stacks, per the book" — but the book's own "this bonus does not
		## increase with multiple Deafened Conditions" clause (p.168) is
		## specifically about the ATTACKER's +10-to-hit bonus against a
		## Deafened target (see combat_resolver.gd), not the Deafened
		## character's OWN -10 Test penalty here. The Test penalty follows
		## the general Multiple Conditions rule (p.167) like every other
		## stacking Condition (Fatigued, Poisoned, Blinded, Entangled).
		candidates.append({"name": "Deafened", "amount": -10 * deafened})
	var movement_scope := scopes.has("Athletics") or scopes.has("Ride") or scopes.has("Swim") or scopes.has("Climb") or scopes.has("agility")
	if int(conditions.get("Prone", 0)) > 0 and movement_scope:
		candidates.append({"name": "Prone", "amount": -20})   ## doesn't stack, per the book
	var entangled: int = int(conditions.get("Entangled", 0))
	if entangled > 0 and movement_scope:
		candidates.append({"name": "Entangled", "amount": -10 * entangled})
	## Rattled (per the request "losing a social encounter needs to carry
	## some consequence" — social_encounter_screen.gd's own
	## _resolve_social_combat_loss_consequences()): a flat -10 to every
	## Skill Test, not scope-gated (unlike most of the Conditions above,
	## being rattled from a bad social exchange doesn't only throw off
	## your Perception or your footing). Not stack-counted like Fatigued/
	## Poisoned/etc. above — losing badly twice in a row before resting
	## doesn't compound the penalty, it's the same -10 either way. Clears
	## on a proper rest (camp_screen.gd/overworld.gd's own Sleep flows),
	## same lifecycle as Fatigued.
	if conditions.get("Rattled", 0) > 0:
		candidates.append({"name": "Rattled", "amount": -10})

	if candidates.is_empty():
		return []
	var worst: Dictionary = candidates[0]
	for c in candidates:
		if c["amount"] < worst["amount"]:
			worst = c
	return [worst]

## Ugly (p.302, general Item Flaw — see ItemQualityRules): "related
## Fellowship Tests might even suffer a -10 penalty." Modelled here as a
## real, deterministic -10 (a video game can't defer to GM discretion)
## on any Test whose scopes include "fellowship" — i.e. every raw
## Fellowship Test (resolve_characteristic_test(character, "fellowship",
## ...)) and every Fellowship-linked skill Test (Charm, Guile, Haggle,
## etc., which fold "fellowship" into their own scopes via
## skill_def.linked_characteristic) — while wearing or wielding at
## least one Ugly item. Doesn't stack with itself: several Ugly items
## still cost a single -10, same as the book's own "a" penalty implies,
## matching the single-worst-candidate pattern
## get_condition_test_penalty_breakdown() above already uses for its
## own non-stacking Conditions.
func get_item_test_modifier_breakdown(scopes: Array) -> Array:
	if not scopes.has("fellowship"):
		return []
	if GameData == null:
		return []
	var equipped_names: Array[String] = []
	if equipped_weapon != "":
		equipped_names.append(equipped_weapon)
	if equipped_offhand != "":
		equipped_names.append(equipped_offhand)
	equipped_names.append_array(equipped_armour)
	for item_name in equipped_names:
		var wd: WeaponDefinition = GameData.weapon_db.find_by_name(item_name) if GameData.weapon_db else null
		if wd != null and ItemQualityRules.has(wd.item_flaws, "Ugly"):
			return [{"name": "Ugly (%s)" % item_name, "amount": -10}]
		var ad: ArmourDefinition = GameData.armour_db.find_by_name(item_name) if GameData.armour_db else null
		if ad != null and ItemQualityRules.has(ad.item_flaws, "Ugly"):
			return [{"name": "Ugly (%s)" % item_name, "amount": -10}]
	return []

## Recomputes max wounds using the core book's Size table (p.341) Average-row
## formula, SB + 2*TB + WPB (+race bonus) — player characters are Average
## size. Previously this halved the SB term (SB/2 + 2*TB + WPB), which
## doesn't match the book's Wounds-by-Size table anywhere; corrected to the
## exact book formula.
func recompute_max_wounds() -> void:
	var sb := get_characteristic_bonus("strength")
	var tb := get_characteristic_bonus("toughness")
	var wpb := get_characteristic_bonus("willpower")
	var extra := race.starting_extra_wounds if race else 0
	## Hardy (Max: Toughness Bonus): "a permanent addition to your
	## Wounds, equal to your Toughness Bonus [per rank]. If your
	## Toughness Bonus should increase, then the number of Wounds Hardy
	## provides also increases." Computed fresh here (rank * current TB)
	## rather than snapshotted once, so it genuinely tracks TB the way
	## the book requires -- recompute_max_wounds() is already called
	## whenever a Characteristic Advance changes, same as every other
	## term above.
	var hardy_bonus := get_talent_rank("Hardy") * tb
	wounds_max = sb + (tb * 2) + wpb + extra + hardy_bonus
	wounds_current = min(wounds_current, wounds_max)
	if wounds_current <= 0:
		wounds_current = wounds_max
