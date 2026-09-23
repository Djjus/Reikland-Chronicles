extends Control
## Spend XP on Characteristic/Skill/Talent Advances and Career changes,
## using the Advancement rules module. Content is built programmatically
## since it's entirely dynamic per character — a hand-authored .tscn with
## dozens of repeating rows would be far more error-prone to write and
## review than generating them here.

@onready var header_label: RichTextLabel = %HeaderLabel
@onready var char_list: VBoxContainer = %CharacteristicList
@onready var skill_list: VBoxContainer = %SkillList
@onready var talent_list: VBoxContainer = %TalentList
@onready var career_label: RichTextLabel = %CareerLabel
@onready var advance_tier_button: Button = %AdvanceTierButton
@onready var message_label: Label = %MessageLabel
@onready var nav_button: Button = %NavButton
@onready var add_xp_button: Button = %AddXpButton

var character: Character

## Per the request ("I can still see Skill and talent sell buttons,
## hide these and only show in cheat mode"): every Advance —
## Characteristics, Skills, Talents, the "(Any)" slot pickers — can
## only be sold back in Test mode now, not during normal play; normal
## play is buy-only. Test mode is the same Shift+Control held-key gate
## CharacterMenu's own XP cheat button already uses elsewhere. Every
## Sell button built via _add_row/_add_sell_only_row is tracked here
## (rather than just toggled at build time) so holding/releasing
## Shift+Control shows/hides all of them live without needing a full
## rebuild.
var _gated_sell_buttons: Array = []

func _test_mode_active() -> bool:
	return Input.is_key_pressed(KEY_SHIFT) and Input.is_key_pressed(KEY_CTRL)

func _process(_delta: float) -> void:
	if not visible:
		return
	var test_mode := _test_mode_active()
	for btn in _gated_sell_buttons:
		if is_instance_valid(btn):
			btn.visible = test_mode

func _ready() -> void:
	nav_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/CharacterCreation.tscn"))
	advance_tier_button.pressed.connect(_on_advance_tier_pressed)
	## A quick way to grant XP for testing, not a real game mechanic —
	## real XP comes from kills/rewards.
	add_xp_button.pressed.connect(func():
		character.experience_total += 100
		_rebuild_all()
	)
	GameState.ensure_player_character()
	character = GameState.player_character
	_rebuild_all()

func _rebuild_all() -> void:
	## Every rebuild below calls _add_row/_add_sell_only_row, which
	## append any Sell button they create to this shared list — cleared
	## once here rather than per-section, since a full _rebuild_all()
	## rebuilds every section's rows from scratch each time.
	_gated_sell_buttons.clear()
	_render_header()
	_rebuild_characteristics()
	_rebuild_skills()
	_rebuild_talents()
	_render_career_section()

func _render_header() -> void:
	header_label.text = "[b]%s[/b] — %s %s, Tier %d\nXP: %d total, %d spent, [b]%d available[/b]" % [
		character.character_name, character.race.race_name if character.race else "?",
		character.career.career_name if character.career else "?", character.current_tier,
		character.experience_total, character.experience_spent, character.get_experience_available()
	]

func _clear(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()

## Returns the Sell button it created (if any), or null, so callers
## that need to gate the Sell button behind Test mode (see
## _rebuild_characteristics) can track and toggle it live.
func _add_row(container: VBoxContainer, label_text: String, cost: int, on_press: Callable,
		sell_cost: int = -1, on_sell: Callable = Callable()) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var sell_button: Button = null
	if sell_cost >= 0 and on_sell.is_valid():
		sell_button = Button.new()
		sell_button.text = "Sell (+%d XP)" % sell_cost
		sell_button.pressed.connect(on_sell)
		sell_button.visible = _test_mode_active()
		row.add_child(sell_button)
		_gated_sell_buttons.append(sell_button)
	var button := Button.new()
	button.text = "Buy (%d XP)" % cost
	button.disabled = character.get_experience_available() < cost
	button.pressed.connect(on_press)
	row.add_child(button)
	container.add_child(row)
	return sell_button

func _rebuild_characteristics() -> void:
	_clear(char_list)
	for key in Advancement.unlocked_characteristics(character):
		var current: int = character.characteristics.get_value(key)
		var already: int = character.get_characteristic_advance_count(key)
		var cost := Advancement.get_characteristic_advance_cost(already)
		var label_text := "%s: %d (+%d purchased)" % [CharacteristicSet.SHORT_NAMES.get(key, key), current, already]
		var sell_cost := Advancement.get_characteristic_advance_cost(max(already - 1, 0)) if already > 0 else -1
		_add_row(char_list, label_text, cost, func(): _buy_characteristic(key),
			sell_cost, func(): _sell_characteristic(key))

func _buy_characteristic(key: String) -> void:
	var result := Advancement.purchase_characteristic_advance(character, key)
	_show_message(result)
	_rebuild_all()

func _sell_characteristic(key: String) -> void:
	var result := Advancement.sell_characteristic_advance(character, key)
	_show_message(result)
	_rebuild_all()

func _rebuild_skills() -> void:
	_clear(skill_list)
	var unlocked_names := Advancement.unlocked_skills(character)
	## See the identical set in character_menu_screen.gd's own
	## _rebuild_skills() for why this is needed: a resolved "(Any)"
	## variant can also be concretely listed by the current career, and
	## should only ever be shown once.
	var concrete_display_names: Dictionary = {}
	for display_name in unlocked_names:
		if not Advancement.is_any_qualifier(display_name):
			concrete_display_names[display_name] = true

	var any_skill_counts: Dictionary = {}
	for display_name in unlocked_names:
		if Advancement.is_any_qualifier(display_name):
			any_skill_counts[display_name] = any_skill_counts.get(display_name, 0) + 1
			continue
		var parsed := _parse_skill_display_name(display_name)
		var skill_def: SkillDefinition = parsed[0]
		var specialisation: String = parsed[1]
		if skill_def == null:
			continue
		var current := character.get_skill_value(skill_def, specialisation)
		var already: int = character.skill_advances.get(display_name, 0)
		var cost := Advancement.get_skill_advance_cost(already)
		var label_text := "%s: %d (+%d purchased)" % [display_name, current, already]
		var sell_cost := Advancement.get_skill_advance_cost(max(already - 1, 0)) if already > 0 else -1
		_add_row(skill_list, label_text, cost, func(): _buy_skill(skill_def, specialisation),
			sell_cost, func(): _sell_skill(skill_def, specialisation))
	for qualifier in any_skill_counts.keys():
		_add_any_skill_row(qualifier, any_skill_counts[qualifier], concrete_display_names)

## Renders every "(Any)" skill slot for this qualifier — see the
## identical helper in character_menu_screen.gd for the full
## explanation of why a career can grant the same qualifier more than
## once, and why each occurrence needs its own independent choice, why
## an already-known skill is now a legal pick for a fresh slot, and why
## `concrete_display_names` keeps a resolved variant from being shown
## twice.
func _add_any_skill_row(entry: String, slot_count: int = 1, concrete_display_names: Dictionary = {}) -> void:
	var chosen_list := Advancement.find_all_chosen_skill_variants(character, entry)
	for chosen in chosen_list:
		if concrete_display_names.has(chosen):
			continue
		var parsed := Advancement.parse_skill_entry(chosen)
		var skill_def: SkillDefinition = parsed[0]
		var specialisation: String = parsed[1]
		var current := character.get_skill_value(skill_def, specialisation)
		var already: int = character.skill_advances.get(chosen, 0)
		var cost := Advancement.get_skill_advance_cost(already)
		var sell_cost := Advancement.get_skill_advance_cost(max(already - 1, 0)) if already > 0 else -1
		_add_row(skill_list, "%s: %d (+%d purchased)" % [chosen, current, already],
			cost, func(): _buy_skill(skill_def, specialisation), sell_cost, func(): _sell_skill(skill_def, specialisation))

	## See the identical logic (and full explanation) in
	## character_menu_screen.gd's own _add_any_skill_row().
	var any_only_chosen := chosen_list.filter(func(c): return not concrete_display_names.has(c))
	var slots_spent: int = maxi(character.skill_any_purchases.get(entry, 0), any_only_chosen.size())
	var remaining_slots := slot_count - slots_spent
	for i in range(remaining_slots):
		var all_choices := Advancement.get_skill_situation_choices(entry)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.text = "%s — choose one:" % entry
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var picker := OptionButton.new()
		for choice in all_choices:
			picker.add_item(choice)
		row.add_child(picker)
		var parsed_entry := Advancement.parse_skill_entry(entry)
		var base_skill_def: SkillDefinition = parsed_entry[0]
		var buy_btn := Button.new()
		var refresh_buy_button := func():
			if picker.item_count == 0 or base_skill_def == null:
				buy_btn.text = "Buy"
				buy_btn.disabled = true
				return
			var selected_display := base_skill_def.display_name(picker.get_item_text(picker.selected))
			var selected_already: int = character.skill_advances.get(selected_display, 0)
			var live_cost := Advancement.get_skill_advance_cost(selected_already)
			buy_btn.text = "Buy (%d XP)" % live_cost
			buy_btn.disabled = character.get_experience_available() < live_cost
		picker.item_selected.connect(func(_idx): refresh_buy_button.call())
		refresh_buy_button.call()
		buy_btn.pressed.connect(func():
			if picker.item_count > 0 and base_skill_def != null:
				var result := Advancement.purchase_skill_advance(character, base_skill_def, picker.get_item_text(picker.selected), false, entry)
				_show_message(result)
				_rebuild_all()
		)
		row.add_child(buy_btn)
		skill_list.add_child(row)

func _buy_skill(skill_def: SkillDefinition, specialisation: String) -> void:
	var result := Advancement.purchase_skill_advance(character, skill_def, specialisation)
	_show_message(result)
	_rebuild_all()

func _sell_skill(skill_def: SkillDefinition, specialisation: String) -> void:
	var result := Advancement.sell_skill_advance(character, skill_def, specialisation)
	_show_message(result)
	_rebuild_all()

## Career skill lists store display strings like "Melee (Basic)" or plain
## "Charm" — this recovers the underlying SkillDefinition + specialisation.
func _parse_skill_display_name(display_name: String) -> Array:
	var base_name := display_name
	var specialisation := ""
	var paren := display_name.find(" (")
	if paren != -1:
		base_name = display_name.substr(0, paren)
		specialisation = display_name.substr(paren + 2, display_name.length() - paren - 3)
	var skill_def: SkillDefinition = GameData.skill_db.find_by_name(base_name)
	return [skill_def, specialisation]

func _rebuild_talents() -> void:
	_clear(talent_list)
	for talent_name in Advancement.unlocked_talents(character):
		if Advancement.is_any_qualifier(talent_name):
			_add_any_talent_row(talent_name)
			continue
		var td: TalentDefinition = GameData.talent_db.find_by_name(talent_name)
		if td == null:
			continue
		var rank := character.get_talent_rank(talent_name)
		var max_rank := td.get_max_rank(character)
		var label_text := "%s (rank %d / %d)" % [talent_name, rank, max_rank]
		var sell_cost := Advancement.get_talent_advance_cost(max(rank - 1, 0)) if rank > 0 else -1
		if rank >= max_rank:
			_add_sell_only_row(talent_list, label_text + " — maxed", sell_cost, func(): _sell_talent(talent_name))
		else:
			var cost := Advancement.get_talent_advance_cost(rank)
			_add_row(talent_list, label_text, cost, func(): _buy_talent(talent_name),
				sell_cost, func(): _sell_talent(talent_name))

## Renders one "(Any)" talent slot: a normal buy/sell row for the
## player's already-made choice, or a dropdown of valid options plus a
## Buy button if they haven't chosen yet — see the identical helper in
## character_menu_screen.gd for the full explanation.
func _add_any_talent_row(entry: String) -> void:
	var chosen := Advancement.find_chosen_variant(character, entry)
	if chosen != "":
		var td: TalentDefinition = GameData.talent_db.find_by_name(chosen)
		var rank := character.get_talent_rank(chosen)
		var max_rank := td.get_max_rank(character) if td else 1
		var label_text := "%s (rank %d / %d)" % [chosen, rank, max_rank]
		var sell_cost := Advancement.get_talent_advance_cost(max(rank - 1, 0)) if rank > 0 else -1
		if rank >= max_rank:
			_add_sell_only_row(talent_list, label_text + " — maxed", sell_cost, func(): _sell_talent(chosen))
		else:
			var cost := Advancement.get_talent_advance_cost(rank)
			_add_row(talent_list, label_text, cost, func(): _buy_talent(chosen), sell_cost, func(): _sell_talent(chosen))
		return

	var choices := Advancement.get_situation_choices(entry)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = "%s — choose one:" % entry
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var picker := OptionButton.new()
	for choice in choices:
		picker.add_item(choice)
	row.add_child(picker)
	var cost := Advancement.get_talent_advance_cost(0)
	var buy_btn := Button.new()
	buy_btn.text = "Buy (%d XP)" % cost
	buy_btn.disabled = character.get_experience_available() < cost or choices.is_empty()
	buy_btn.pressed.connect(func():
		if picker.item_count > 0:
			_buy_talent_choice(entry, picker.get_item_text(picker.selected))
	)
	row.add_child(buy_btn)
	talent_list.add_child(row)

func _buy_talent_choice(entry: String, chosen_situation: String) -> void:
	var result := Advancement.purchase_talent_advance(character, entry, chosen_situation)
	_show_message(result)
	_rebuild_all()

func _add_sell_only_row(container: VBoxContainer, label_text: String, sell_cost: int, on_sell: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if sell_cost >= 0:
		var sell_button := Button.new()
		sell_button.text = "Sell (+%d XP)" % sell_cost
		sell_button.pressed.connect(on_sell)
		sell_button.visible = _test_mode_active()
		row.add_child(sell_button)
		_gated_sell_buttons.append(sell_button)
	container.add_child(row)

func _buy_talent(talent_name: String) -> void:
	var result := Advancement.purchase_talent_advance(character, talent_name)
	_show_message(result)
	_rebuild_all()

func _sell_talent(talent_name: String) -> void:
	var result := Advancement.sell_talent_advance(character, talent_name)
	_show_message(result)
	_rebuild_all()

func _render_career_section() -> void:
	var completed := Advancement.has_completed_current_level(character)
	var next_level := character.career.get_level(character.current_tier + 1)
	career_label.text = "[b]Career completion (Tier %d):[/b] %s" % [
		character.current_tier, "Complete!" if completed else "Not yet complete"
	]
	if next_level:
		var cost := Advancement.get_change_career_cost(completed)
		advance_tier_button.text = "Advance to %s (Tier %d) — %d XP" % [
			next_level.level_name, character.current_tier + 1, cost
		]
		advance_tier_button.disabled = character.get_experience_available() < cost
		advance_tier_button.visible = true
	else:
		advance_tier_button.visible = false

func _on_advance_tier_pressed() -> void:
	var result := Advancement.change_career(character, character.career, character.current_tier + 1)
	_show_message(result)
	_rebuild_all()

func _show_message(result: Advancement.PurchaseResult) -> void:
	message_label.text = result.message
	message_label.modulate = Color(0.6, 1, 0.6) if result.success else Color(1, 0.6, 0.6)
