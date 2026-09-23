extends Control
## The Rat Catcher's Guild, Ubersreik — spec §10 ("hook up the Rat
## Catcher Guild in Ubersreik, and give him a Quest option that will
## trigger the Dungeon encounter"). Deliberately the simplest possible
## NPC screen in the project: a portrait, flavour dialogue, and one
## button — NOT ScriptedNPCEncounterScreen (built around
## QuestNPCMapMarker, a walkable-local-map tile marker CityScreen's
## own image-map locations don't use) and not a new dialogue system.
## Structurally cloned from Hermit.tscn/hermit_screen.gd (this
## project's own closest "portrait, flavour text, one button" screen),
## with a TextureRect portrait added — no existing screen had one to
## copy from (see this feature's own build notes).
##
## Reached only from CityScreen's "Talk" radial action on a
## guild-category location (see city_screen.gd's own _enter_guild()) —
## returning here always means GameState.pending_guild_city_id is set,
## same "read once into pending_city_id" round-trip Tavern/Shop already
## use to get back to the exact same CityScreen.

@onready var close_button: Button = %CloseButton
@onready var quest_button: Button = %QuestButton
@onready var message_label: Label = %MessageLabel

func _ready() -> void:
	close_button.pressed.connect(_on_close)
	quest_button.pressed.connect(_on_quest_pressed)
	_refresh()
	quest_button.grab_focus()

## The dungeon persists across a visit (spec §6 — "the Dungeon will
## only exist while they are in it... make sure saving works inside the
## dungeon"), so a party that left mid-delve and comes back to the
## Guild before finishing should be offered to RETURN to that same
## sewer rather than being told this is a fresh quest offer.
func _refresh() -> void:
	if not GameState.dungeon_state.is_empty() and GameState.dungeon_state.get("theme_id", "") == "sewer":
		quest_button.text = "Return to the Sewers"
		message_label.text = "\"Still down there, are they? Mind the dark.\""
	else:
		quest_button.text = "Quest: Clear the Sewers"
		message_label.text = ""

func _on_quest_pressed() -> void:
	## No new dungeon_state to generate if one's already in progress —
	## FieldEncounterScreen's own _load_or_generate_dungeon() (part of its
	## exploration-mode support — see field_encounter_screen.gd's own
	## header comment on that section) already prefers a non-empty
	## GameState.dungeon_state over pending_dungeon_theme_id on its own,
	## so setting the pending id here is harmless either way, but skip it
	## for clarity when simply resuming.
	if GameState.dungeon_state.is_empty():
		GameState.pending_dungeon_theme_id = "sewer"
	## Real bug fix ("all outdoor field combat encounters jump to the
	## Goblin Fort dungeon" — the same latent issue applies here too):
	## see GameState.dungeon_entry_requested's own header comment for why
	## this flag, not raw dungeon_state presence, has to be what decides
	## whether the FieldEncounter.tscn load below resumes exploration.
	GameState.dungeon_entry_requested = true
	GameState.autosave()
	## FieldEncounter.tscn itself, not a separate DungeonScreen.tscn —
	## exploration mode is now a first-class capability of the normal
	## combat screen (see field_encounter_screen.gd), activated
	## automatically because GameState.pending_dungeon_theme_id/
	## dungeon_state is set above.
	get_tree().change_scene_to_file("res://scenes/FieldEncounter.tscn")

## Same "read pending_guild_city_id back into pending_city_id" round
## trip Tavern's own _on_close() uses (see that script's own comment) —
## the party's own position in the city was never touched by entering
## this screen, so they resume exactly where they left off.
func _on_close() -> void:
	GameState.pending_city_id = GameState.pending_guild_city_id
	GameState.autosave()
	get_tree().change_scene_to_file("res://scenes/CityScreen.tscn")

## Same WASD-selects/Space-accepts scheme this project's other pop-up
## screens use (per the standing project instruction that Space is the
## main way to accept a choice menu) — with only one real action button
## here, Space simply activates whichever button currently has focus.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_close()
		elif event.keycode == KEY_SPACE:
			var focused := get_viewport().gui_get_focus_owner()
			if focused is Button:
				get_viewport().set_input_as_handled()
				focused.emit_signal("pressed")
