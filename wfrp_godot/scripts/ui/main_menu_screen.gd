extends Control
## The game's actual starting screen now (see project.godot's
## run/main_scene) — Continue an existing character, start a New
## Character (which still leads to the full Character Creation screen,
## dev tools and all), adjust Settings, or Quit.

@onready var title_label: Label = %TitleLabel
@onready var continue_header: Label = %ContinueHeader
@onready var continue_box: VBoxContainer = %ContinueBox
@onready var continue_sep: HSeparator = %ContinueSep
@onready var new_character_button: Button = %NewCharacterButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var version_label: Label = %VersionLabel

func _ready() -> void:
	title_label.add_theme_color_override("font_color", SettingsManager.get_accent_color())
	version_label.text = "%s (%s)" % [BuildInfo.VERSION, BuildInfo.BUILD_DATE]
	new_character_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/CharacterCreation.tscn"))
	settings_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Settings.tscn"))
	quit_button.pressed.connect(func(): get_tree().quit())
	_populate_continue_box()

func _populate_continue_box() -> void:
	for child in continue_box.get_children():
		child.queue_free()
	var any_saves := false
	for slot in range(SaveManager.SLOT_COUNT):
		var summary := SaveManager.get_save_summary(slot)
		if summary.is_empty():
			continue
		any_saves = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text = "%s, Wounds %d/%d" % [
			", ".join(summary["party_names"]),
			summary["wounds_current"], summary["wounds_max"],
		]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(lbl)
		var btn := Button.new()
		## Per the request: a [1]/[2]/[3] hotkey per slot — tied to the
		## slot's own index (not its position among visible rows), so
		## a given number always opens the same slot even if an
		## earlier slot is empty or gets deleted later.
		btn.text = "[%d] Continue →" % (slot + 1)
		btn.pressed.connect(func(): _on_continue_pressed(slot))
		row.add_child(btn)
		continue_box.add_child(row)
	continue_header.visible = any_saves
	continue_sep.visible = any_saves

## Per the request: number keys 1/2/3 trigger the matching save
## slot's own Continue button, same as clicking it — a no-op if that
## slot has no save (nothing to continue), matching the button not
## existing in the UI at all for an empty slot.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	var slot := -1
	match event.keycode:
		KEY_1: slot = 0
		KEY_2: slot = 1
		KEY_3: slot = 2
	if slot < 0 or slot >= SaveManager.SLOT_COUNT:
		return
	if SaveManager.get_save_summary(slot).is_empty():
		return
	_on_continue_pressed(slot)

func _on_continue_pressed(slot: int) -> void:
	var out_index: Array = [0]
	var out_dismissed: Array = [[]]
	var loaded_party := SaveManager.load_party(slot, out_index, out_dismissed)
	if loaded_party.is_empty():
		var err_lbl := Label.new()
		err_lbl.text = "Couldn't load that slot — the save may reference data that no longer exists."
		err_lbl.add_theme_color_override("font_color", Color(0.85, 0.5, 0.5))
		continue_box.add_child(err_lbl)
		return
	GameState.party = loaded_party
	GameState.active_party_index = clampi(out_index[0], 0, loaded_party.size() - 1)
	GameState.dismissed_companions = out_dismissed[0]
	GameState.reset_session_state()
	GameState.current_slot = slot
	## Follow-up request's own reported bug ("its not saving the city
	## still, i always enter the game outside the city on the overworld
	## map"): load_party() above already restored last_active_city_id
	## as a side effect (see Character.from_save_dict()) — route
	## straight back into that city's own CityScreen instead of always
	## defaulting to Overworld, which is exactly what "always enter the
	## game outside the city" looked like from the outside. "" (the
	## overwhelmingly common case — not saved from inside any city)
	## keeps the exact previous behaviour, unchanged.
	if GameState.last_active_city_id != "":
		GameState.pending_city_id = GameState.last_active_city_id
		get_tree().change_scene_to_file("res://scenes/CityScreen.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Overworld.tscn")
