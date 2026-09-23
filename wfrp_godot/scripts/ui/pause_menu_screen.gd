extends CanvasLayer
## The Esc menu: resume, switch to a different character, or leave the
## current playthrough entirely and return to the start screen (or quit
## outright). There's no manual "Save" anymore — the game autosaves
## continuously (every step, and whenever the character menu closes; see
## GameState.autosave) — so none of these lose progress. The confirming
## second click on Main Menu/Quit is just to guard against a stray
## misclick, not because anything would be lost.

signal closed
signal switch_character_requested   ## Overworld opens the character menu's Switch Character tab on this

@onready var resume_button: Button = %ResumeButton
@onready var switch_button: Button = %SwitchButton
@onready var main_menu_button: Button = %MainMenuButton
@onready var quit_button: Button = %QuitButton

var _pending_main_menu_confirm: bool = false
var _pending_quit_confirm: bool = false

func _ready() -> void:
	resume_button.pressed.connect(close)
	switch_button.pressed.connect(_on_switch_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	visible = false

func open() -> void:
	visible = true
	_pending_main_menu_confirm = false
	_pending_quit_confirm = false
	main_menu_button.text = "Return to Main Menu"
	quit_button.text = "Quit to Desktop"

func close() -> void:
	visible = false
	closed.emit()

func _on_switch_pressed() -> void:
	switch_character_requested.emit()

func _on_main_menu_pressed() -> void:
	if not _pending_main_menu_confirm:
		_pending_main_menu_confirm = true
		main_menu_button.text = "Click again to confirm"
		return
	GameState.autosave()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_quit_pressed() -> void:
	if not _pending_quit_confirm:
		_pending_quit_confirm = true
		quit_button.text = "Click again to confirm"
		return
	GameState.autosave()
	get_tree().quit()
