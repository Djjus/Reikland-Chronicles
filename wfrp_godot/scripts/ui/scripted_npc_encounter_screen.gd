extends Control
## Per the request: the data-driven counterpart to the Village Elder's
## own hand-built quest chain — presents a single QuestNPCDefinition's
## dialogue and resolution Test, applies real pass/fail consequences
## and rewards, and checks a real time limit if the NPC has one,
## rather than every future adventure-import needing its own bespoke
## screen and Character fields the way the Elder's chain was built.

@onready var npc_name_label: Label = %NPCNameLabel
@onready var reward_label: Label = %RewardLabel
@onready var button_row: HFlowContainer = %ButtonRow
@onready var history_list: VBoxContainer = %HistoryList
@onready var history_scroll: ScrollContainer = %TextScroll

var quest_def: QuestDefinition = null
var npc_def: QuestNPCDefinition = null
var character: Character = null

## Per the request: real roll cards in a real accumulating log for
## every Test on this screen — matches SocialEncounter's own already-
## proven {"cards": [...], "notice": String} history entry shape, and
## the same RollCardBuilder combat's own cards use, rather than plain
## text that gets overwritten on every state change.
const MAX_HISTORY_ENTRIES := 40
var history: Array = []

func _ready() -> void:
	character = GameState.player_character
	var quest_id: String = GameState.pending_quest_id
	var npc_id: String = GameState.pending_quest_npc_id
	GameState.pending_quest_id = ""
	GameState.pending_quest_npc_id = ""

	if quest_id == "":
		_show_error("This screen was opened without a quest set — nothing to show.")
		return
	quest_def = load("res://data/quests/%s.tres" % quest_id) as QuestDefinition
	if quest_def == null:
		_show_error("This scripted encounter's own quest data (%s) couldn't be found." % quest_id)
		return
	npc_def = quest_def.find_npc(npc_id)
	if npc_def == null:
		_show_error("This scripted encounter's own NPC data (%s) couldn't be found." % npc_id)
		return

	character.start_scripted_quest(quest_def.quest_id, quest_def.quest_title, quest_def.quest_summary)
	npc_name_label.text = npc_def.npc_name

	character.set_quest_npc_visited(quest_def.quest_id, npc_def.npc_id)

	var existing_state := character.get_quest_npc_state(quest_def.quest_id, npc_def.npc_id)
	if existing_state != "":
		_show_already_resolved(existing_state)
		return

	## Per the request: dynamic rerouting — matches the source
	## material's own "if the party rushes to the lake before the
	## temple, Gerd forgets what he saw and points them to someone
	## else" GM advice. Checked every visit (not just the first) —
	## as soon as the prerequisite NPC has genuinely been visited,
	## this stops applying on its own, with no separate flag to clear.
	## The encounter hasn't really begun yet while rerouted, so no
	## start time is recorded and no Test is offered — just a way
	## back out.
	if npc_def.reroute_if_npc_id != "" and not character.get_quest_npc_visited(quest_def.quest_id, npc_def.reroute_if_npc_id):
		_add_history_entry([], npc_def.reroute_text)
		_clear_buttons()
		_add_button("Continue", func(): _return_to_world())
		return

	## Per the request: a real time limit — records the moment this
	## NPC is genuinely first encountered (only once; revisiting never
	## resets it), then checks whether that limit has already passed
	## RIGHT NOW, on this very visit, before showing anything else —
	## covers the case where the player spent time elsewhere first and
	## only now comes back to find the crisis already over.
	character.set_quest_npc_start_time_if_unset(quest_def.quest_id, npc_def.npc_id, GameState.time_minutes_total())
	if npc_def.timeout_minutes >= 0:
		var start_time := character.get_quest_npc_start_time(quest_def.quest_id, npc_def.npc_id)
		var elapsed := GameState.time_minutes_total() - start_time
		if elapsed >= npc_def.timeout_minutes:
			_apply_result(false, true)
			return

	_add_history_entry([], npc_def.intro_text)
	_build_action_buttons()

func _show_already_resolved(state: String) -> void:
	## Per the request: an NPC is aware the whole quest has actually
	## concluded, not just that this one conversation already
	## happened — a different message once the quest's own status is
	## Completed or Failed (checked directly, now that
	## evaluate_quest_win_conditions() is actually ever called).
	var quest_status := ""
	var q := character.find_quest(quest_def.quest_id)
	if not q.is_empty():
		quest_status = str(q.get("status", ""))
	var text := ""
	if (quest_status == "Completed" or quest_status == "Failed") and npc_def.quest_concluded_text != "":
		text = npc_def.quest_concluded_text
	else:
		text = npc_def.already_resolved_text
	if text == "":
		text = "%s has nothing more to say." % npc_def.npc_name if state == "pass" else "There is nothing more to be done here."
	_add_history_entry([], text)
	_clear_buttons()
	_add_button("Continue", func(): _return_to_world())

func _show_error(text: String) -> void:
	npc_name_label.text = "Error"
	_add_history_entry([], text)
	_clear_buttons()
	_add_button("Continue", func(): _return_to_world())

func _build_action_buttons() -> void:
	_clear_buttons()
	if npc_def.skill_name == "":
		_add_button("Speak with %s" % npc_def.npc_name, func(): _apply_result(true, false))
	else:
		var label := "Attempt (%s)" % npc_def.skill_name
		_add_button(label, func(): _resolve_test())

func _resolve_test() -> void:
	var result := _resolve_char_or_skill_test(npc_def.skill_name, npc_def.specialisation, npc_def.difficulty)
	## Per the request: a real roll card for this Test, the same
	## visual card combat and Social Encounters already use, shown in
	## the real accumulating log rather than only a plain pass/fail
	## text.
	var card := {
		"character_name": character.character_name, "title": npc_def.skill_name, "subtitle": "Skill Test",
		"side": "ally", "test": result, "effects": ([] as Array[String]),
	}
	_add_history_entry([card], "")
	_apply_result(result.success, false)

## Mirrors WildernessEncounter's own _resolve_char_or_skill_test —
## resolves a real Skill Test if skill_name matches a known skill, or
## a real raw Characteristic Test if it matches a characteristic name
## instead. Returns the full TestResolver.TestResult now (not just a
## bool), so the caller can build a real roll card from it.
func _resolve_char_or_skill_test(skill_name: String, specialisation: String, difficulty: int) -> TestResolver.TestResult:
	var char_keys := ["weapon_skill", "ballistic_skill", "strength", "toughness", "initiative", "agility", "dexterity", "intelligence", "willpower", "fellowship"]
	var lname := skill_name.to_lower()
	for key in char_keys:
		if key == lname or key.replace("_", " ") == lname:
			return TestResolver.resolve_characteristic_test(character, key, difficulty)
	var skill_def: SkillDefinition = GameData.skill_db.find_by_name(skill_name)
	if skill_def == null:
		return TestResolver.resolve(100)   ## always succeeds — no real skill data to test against
	return TestResolver.resolve_skill_test(character, skill_def, specialisation, difficulty)

func _apply_result(passed: bool, was_timeout: bool) -> void:
	var text: String
	if was_timeout:
		text = npc_def.timeout_text if npc_def.timeout_text != "" else npc_def.fail_text
	else:
		text = npc_def.pass_text if passed else npc_def.fail_text
	_add_history_entry([], text)

	character.set_quest_npc_state(quest_def.quest_id, npc_def.npc_id, "pass" if passed else "fail")
	if not passed and npc_def.fail_removes_npc:
		character.mark_quest_npc_removed(quest_def.quest_id, npc_def.npc_id)

	if passed:
		if npc_def.pass_condition != "":
			character.add_condition(npc_def.pass_condition, npc_def.pass_condition_stacks)
		if npc_def.reward_xp > 0:
			character.experience_total += npc_def.reward_xp
		if npc_def.reward_gold > 0:
			character.gold_crowns += npc_def.reward_gold
		if npc_def.reward_item != "":
			character.inventory.append(npc_def.reward_item)
		var reward_bits: Array[String] = []
		if npc_def.reward_xp > 0:
			reward_bits.append("+%d XP" % npc_def.reward_xp)
		if npc_def.reward_gold > 0:
			reward_bits.append("+%d GC" % npc_def.reward_gold)
		if npc_def.reward_item != "":
			reward_bits.append("+%s" % npc_def.reward_item)
		if not reward_bits.is_empty():
			reward_label.text = "  ".join(reward_bits)
			reward_label.visible = true
	else:
		if npc_def.fail_condition != "":
			character.add_condition(npc_def.fail_condition, npc_def.fail_condition_stacks)

	## Per the request: the same real fix as the monster-defeat path —
	## a win condition based on an NPC outcome (e.g. Gotheim's own
	## "at least one villager saved") needs to be checked here too,
	## not just after combat.
	var win_eval: Dictionary = character.evaluate_quest_win_conditions(quest_def.quest_id)
	if win_eval.get("won", false):
		var q := character.find_quest(quest_def.quest_id)
		if not q.is_empty() and q.get("status", "") == "Active":
			q["status"] = "Completed"

	GameState.autosave()
	_clear_buttons()
	_add_button("Continue", func(): _return_to_world())

func _return_to_world() -> void:
	get_tree().change_scene_to_file("res://scenes/Overworld.tscn")

func _clear_buttons() -> void:
	for child in button_row.get_children():
		child.queue_free()

func _add_button(text: String, on_press: Callable) -> void:
	var btn := Button.new()
	btn.add_theme_font_size_override("font_size", 18)
	btn.text = text
	btn.pressed.connect(on_press)
	button_row.add_child(btn)

## Per the request: adds one real entry to the accumulating log —
## `cards` is a list of the same {character_name, title, subtitle,
## side, test, effects} dicts RollCardBuilder already renders
## elsewhere; `notice` is plain narrative text, shown alongside or
## instead of the cards. Mirrors SocialEncounter's own already-proven
## _add_history_entry/_rebuild_history_display pair.
func _add_history_entry(cards: Array, notice: String) -> void:
	history.push_front({"cards": cards, "notice": notice})
	if history.size() > MAX_HISTORY_ENTRIES:
		history.resize(MAX_HISTORY_ENTRIES)
	_rebuild_history_display()

func _rebuild_history_display() -> void:
	for child in history_list.get_children():
		child.queue_free()
	## Rendered oldest-first, newest-last, matching FieldEncounter and
	## SocialEncounter's own logs. history[] itself still stores
	## newest at index 0 internally.
	for i in range(history.size() - 1, -1, -1):
		var entry: Dictionary = history[i]
		var is_latest := i == 0
		var entry_box := VBoxContainer.new()
		entry_box.add_theme_constant_override("separation", 4)

		var cards: Array = entry.get("cards", [])
		if not cards.is_empty():
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 10)
			row.add_theme_constant_override("v_separation", 10)
			for card_data in cards:
				row.add_child(RollCardBuilder.build_roll_card(card_data, not is_latest))
			entry_box.add_child(row)

		var notice: String = entry.get("notice", "")
		if notice != "":
			var lbl := Label.new()
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.add_theme_font_size_override("font_size", 21)
			lbl.add_theme_color_override("font_color", Color(0.85, 0.83, 0.78, 1))
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			lbl.text = notice
			entry_box.add_child(lbl)

		history_list.add_child(entry_box)
		if i > 0:
			history_list.add_child(HSeparator.new())
	## Scroll to the newest entry, at the bottom.
	await get_tree().process_frame
	if is_instance_valid(history_scroll) and history_list.get_child_count() > 0:
		history_scroll.ensure_control_visible(history_list.get_child(history_list.get_child_count() - 1))

func _unhandled_input(input_event: InputEvent) -> void:
	if input_event is InputEventKey and input_event.pressed and not input_event.is_echo() and input_event.keycode == KEY_SPACE:
		for child in button_row.get_children():
			if child is Button and child.visible:
				## Marked handled before emitting — several of these
				## buttons change scenes, which would otherwise crash
				## on a stale viewport (see the identical, already-
				## fixed bug in WildernessEncounter's own history).
				get_viewport().set_input_as_handled()
				child.emit_signal("pressed")
				return
