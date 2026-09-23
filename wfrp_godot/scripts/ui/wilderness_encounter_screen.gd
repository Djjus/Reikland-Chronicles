extends Control
## Per the request: Wilderness Events are now resolved on their own
## real screen — a full scene transition, matching how Social and
## Field encounters already work — rather than a text popup on top of
## the World Map. Skill Tests are genuinely interactive: the player
## clicks the actual relevant skill button to attempt it, rather than
## the game rolling it automatically behind the scenes. A combat
## result (or a hostile sub-table roll) transitions on to the real
## FieldEncounter screen. Resolving an event (that doesn't escalate to
## combat) awards a flat 5 XP plus whatever gold/item reward the
## specific result already carried.

@onready var title_label: Label = %TitleLabel
@onready var roll_label: Label = %RollLabel
@onready var reward_label: Label = %RewardLabel
@onready var button_row: HFlowContainer = %ButtonRow
@onready var history_list: VBoxContainer = %HistoryList
@onready var history_scroll: ScrollContainer = %TextScroll

const REWARD_XP := 5
var event: Dictionary = {}
var character: Character = null
## Per the request: the party should always return to wherever the
## Wilderness Event actually happened, not wherever they might end up
## after a Combat sub-transition. Captured once, locally, right at
## the start — GameState.return_position was already set correctly by
## Overworld before this screen even opened, but re-asserting it
## explicitly from a stable local copy at every real exit point below
## is the actual robust fix, not just relying on nothing else in
## between ever touching the global value.
var encounter_tile: Vector2i = Vector2i(-1, -1)

## Per the request: real roll cards in a real accumulating log for
## every Test on this screen — matches SocialEncounter's own already-
## proven {"cards": [...], "notice": String} history entry shape.
const MAX_HISTORY_ENTRIES := 40
var history: Array = []

func _ready() -> void:
	character = GameState.player_character
	event = GameState.pending_wilderness_event.duplicate(true)
	GameState.pending_wilderness_event = {}
	encounter_tile = GameState.return_position
	_show_initial_event()

func _show_initial_event() -> void:
	_add_history_entry([], str(event.get("text", "")))
	## Per the request: always show the actual table roll behind this
	## event — which d10 came up, and which table it was rolled on
	## (since a low roll on non-plains terrain redirects to Table 1).
	if event.has("_roll"):
		roll_label.text = "Rolled %d on the %s table" % [int(event["_roll"]), str(event.get("_table", ""))]
	else:
		roll_label.text = ""
	_clear_buttons()
	match str(event.get("type", "flavor")):
		"flavor", "flavor_test":
			_add_button("Continue", func(): _finish_with_reward())
		"skill_test", "hazard":
			_build_skill_test_buttons()
		"combat":
			_add_button("Continue", func(): _go_to_combat(event.get("monster_pool", [])))
		"social_choice":
			_add_button("Approach", func(): _go_to_social())
			_add_button("Avoid them", func(): _finish_with_reward())
		"sub_table":
			_add_button("Investigate", func(): _resolve_sub_table())
			_add_button("Move on", func(): _finish_with_reward())

## --- Skill Tests: real, interactive — the player clicks the actual
## relevant skill/characteristic to attempt it, rather than an
## automatic roll happening off-screen. ---
func _build_skill_test_buttons() -> void:
	var skill_name: String = str(event.get("skill_name", ""))
	var label := skill_name if skill_name != "" else "Test"
	_add_button("Attempt (%s)" % label, func(): _resolve_skill_test_click())
	if event.has("fallback_skill"):
		_add_button("Attempt (%s)" % str(event["fallback_skill"]), func(): _resolve_fallback_test_click())

func _resolve_skill_test_click() -> void:
	var difficulty: int = int(event.get("difficulty", event.get("avoid_difficulty", 0)))
	var skill_name: String = str(event.get("skill_name", ""))
	var result := _resolve_char_or_skill_test(skill_name, str(event.get("specialisation", "")), difficulty)
	_add_test_roll_card(skill_name, result)
	_apply_test_result(result.success)

func _resolve_fallback_test_click() -> void:
	var skill_name: String = str(event["fallback_skill"])
	var result := _resolve_char_or_skill_test(skill_name, "", int(event.get("fallback_difficulty", 0)))
	_add_test_roll_card(skill_name, result)
	_apply_test_result(result.success)

## Per the request: a real roll card for this Test, the same visual
## card combat and Social Encounters already use, shown in the real
## accumulating log rather than only a plain pass/fail text.
func _add_test_roll_card(skill_name: String, result: TestResolver.TestResult) -> void:
	var card := {
		"character_name": character.character_name, "title": skill_name if skill_name != "" else "Test", "subtitle": "Skill Test",
		"side": "ally", "test": result, "effects": ([] as Array[String]),
	}
	_add_history_entry([card], "")

func _apply_test_result(passed: bool) -> void:
	var text := ""
	if passed:
		text = str(event.get("pass_text", ""))
	else:
		text = str(event.get("fail_text", ""))
		var fail_cond: String = str(event.get("fail_condition", ""))
		if fail_cond != "":
			character.add_condition(fail_cond, 1)
		if event.has("fail_damage"):
			var dmg := Dice.roll_dice_string(str(event["fail_damage"]))
			character.wounds_current = max(0, character.wounds_current - dmg)
	if event.has("delay_days"):
		GameState.advance_days(int(event["delay_days"]))
		text += "\n\nThe detour costs you %d extra day(s)." % int(event["delay_days"])
	if text != "":
		_add_history_entry([], text)
	_finish_with_reward()

## Mirrors Overworld._resolve_char_or_skill_test — resolves a real
## Skill Test if skill_name matches a known skill, or a real raw
## Characteristic Test if it matches a characteristic name instead.
## Returns the full TestResolver.TestResult now (not just a bool), so
## the caller can build a real roll card from it.
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

## --- Sub-table (Barrow/Monolith/Ruin) — simplified per the earlier
## documented scope note; a representative outcome rather than the
## full source sub-tables. ---
func _resolve_sub_table() -> void:
	var sub_type: String = str(event.get("sub_type", ""))
	var text: String = str(event["text"])
	var roll := randi_range(1, 10)
	roll_label.text = "Rolled %d on the %s table" % [roll, sub_type.capitalize()]
	var hostile_pool: Array = []
	match sub_type:
		"barrow":
			if roll <= 6:
				text += "\n\nIt's long undisturbed — just old stone and older silence."
			elif roll <= 8:
				text += "\n\nSomething stirs within. Best not to linger."
				hostile_pool = ["Skeleton", "Skeleton"]
			else:
				var gc := randi_range(1, 10)
				text += "\n\nA half-collapsed entrance yields a handful of old coin — %d GC worth." % gc
				character.gold_crowns += gc
		"monolith":
			if roll <= 5:
				text += "\n\nJust an old boundary marker or ritual site — nothing peculiar about it, on closer look."
			elif roll <= 8:
				text += "\n\nThe carvings are ancient and unfamiliar. You feel watched, and decide not to linger to find out why."
			else:
				text += "\n\nA nearby, half-hidden entrance suggests this stone marks somebody's grave — and a tomb besides."
				hostile_pool = ["Zombie"]
		"ruin":
			if roll <= 7:
				text += "\n\nJust scattered stone — whatever stood here is long gone."
			elif roll <= 9:
				var gc2 := randi_range(1, 10)
				text += "\n\nAmong the rubble, %d GC worth of old coin and trinkets, missed by anyone before you." % gc2
				character.gold_crowns += gc2
			else:
				text += "\n\nThe ruin isn't as abandoned as it looks."
				hostile_pool = ["Outlaw", "Outlaw"]
	_add_history_entry([], text)
	if not hostile_pool.is_empty():
		_clear_buttons()
		_add_button("Continue", func(): _go_to_combat(hostile_pool))
	else:
		_finish_with_reward()

func _go_to_social() -> void:
	GameState.pending_social_encounter_name = ""
	GameState.pending_social_npc_name = ""
	GameState.pending_social_npc_gender = ""
	GameState.pending_social_situation_index = -1
	GameState.pending_social_opening_flavor_index = -1
	## Per the request: explicitly re-asserted from the local copy
	## captured at _ready(), rather than assuming the global value
	## survived untouched.
	GameState.return_position = encounter_tile
	GameState.autosave()
	get_tree().change_scene_to_file("res://scenes/SocialEncounter.tscn")

func _go_to_combat(pool: Array) -> void:
	var monster_names: Array[String] = []
	for m in pool:
		monster_names.append(str(m))
	GameState.pending_encounter_monster_names = monster_names
	GameState.pending_encounter_is_player_ambush = false
	## Per the request: same explicit re-assertion — the party should
	## return to wherever this Wilderness Event actually happened,
	## not wherever they might otherwise end up after the fight.
	GameState.return_position = encounter_tile
	GameState.autosave()
	get_tree().change_scene_to_file("res://scenes/FieldEncounter.tscn")

## Per the request: resolving a Wilderness Event (that doesn't
## escalate to combat) genuinely rewards a flat 5 XP, on top of
## whatever gold the specific result already carried — shown plainly
## rather than silently applied.
func _finish_with_reward() -> void:
	character.experience_total += REWARD_XP
	reward_label.text = "+%d XP" % REWARD_XP
	reward_label.visible = true
	GameState.autosave()
	_clear_buttons()
	_add_button("Continue  [Space]", func(): _return_to_world_map())

func _return_to_world_map() -> void:
	## Per the request: same explicit re-assertion as the other two
	## exit points, for the same reason.
	GameState.return_position = encounter_tile
	get_tree().change_scene_to_file("res://scenes/Overworld.tscn")

func _clear_buttons() -> void:
	for child in button_row.get_children():
		child.queue_free()

func _add_button(text: String, on_press: Callable) -> void:
	var btn := Button.new()
	btn.add_theme_font_size_override("font_size", 14)
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
			lbl.add_theme_font_size_override("font_size", 17)
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
				## Real bug fix: this must be marked handled BEFORE
				## emitting the button's own press signal, not after —
				## several of these buttons change scenes (combat,
				## social, returning to the World Map), which detaches
				## this node from its viewport. Calling
				## get_viewport() on an already-detached node crashes,
				## which is exactly what "Space crashes the game" was.
				get_viewport().set_input_as_handled()
				child.emit_signal("pressed")
				return
