extends CanvasLayer
## A small radial-style context menu, its options depending on what
## was right-clicked. Per the Radial Menu rework request, the Menu and
## Camp buttons are gone entirely (both menus stay reachable via their
## own keyboard shortcuts instead) — the new default target context
## ("default") always shows Perception (info about whatever tile was
## clicked), plus Gossip and Talk when the target is a friendly NPC
## who can speak, plus Attack when the target is an enemy that can be
## fought. Separately: an encounter marker shows Perception alone; a
## lootable world container (see the request) shows Open (if unlocked)
## XOR Break (if locked), Perception (to check for a trap), and Pick
## Lock (if locked and the player has learned it); the World Map shows
## Lore/Travel. Only ever one context at a time. Opens on right-click,
## closes on any other click (inside or outside it) or Escape.

signal menu_selected(option: String)

@onready var backdrop: Control = %Backdrop
@onready var perception_button: Button = %PerceptionButton
@onready var gossip_button: Button = %GossipButton
@onready var talk_button: Button = %TalkButton
@onready var attack_button: Button = %AttackButton
@onready var open_button: Button = %OpenButton
@onready var break_button: Button = %BreakButton
@onready var pick_lock_button: Button = %PickLockButton
@onready var lore_button: Button = %LoreButton
@onready var travel_button: Button = %TravelButton

func _ready() -> void:
	perception_button.pressed.connect(func(): _select("perception"))
	gossip_button.pressed.connect(func(): _select("gossip"))
	talk_button.pressed.connect(func(): _select("talk"))
	attack_button.pressed.connect(func(): _select("attack"))
	open_button.pressed.connect(func(): _select("open"))
	break_button.pressed.connect(func(): _select("break"))
	pick_lock_button.pressed.connect(func(): _select("pick_lock"))
	lore_button.pressed.connect(func(): _select("lore"))
	travel_button.pressed.connect(func(): _select("travel"))
	backdrop.gui_input.connect(_on_backdrop_input)

## context: "default" (the new default — Perception always, plus
## Gossip/Talk/Attack per target_flags below), "marker" (Perception
## alone), "container" (Open XOR Break, Perception, and optionally
## Pick Lock — see target_flags below), or "lore" (World Map only — a
## single Lore + Travel pair, per the request).
## target_flags:
## - context == "default": {"can_talk": bool, "can_attack": bool} —
##   "can_talk" shows Gossip + Talk (a friendly target who can speak),
##   "can_attack" shows Attack (a live enemy that can be fought).
##   Mutually exclusive in practice (nothing is both an NPC and a live
##   quest monster marker on the same tile), but not enforced here.
## - context == "container": {"is_locked": bool, "can_pick_lock": bool}.
## Per the request: a future "Quest" button belongs alongside
## Perception/Gossip/Talk in the "default" context once a real
## bigger-Quest system exists — deliberately not added here.
func open_at(screen_pos: Vector2, context: String = "default", target_flags: Dictionary = {}) -> void:
	backdrop.visible = true
	var can_talk: bool = bool(target_flags.get("can_talk", false))
	var can_attack: bool = bool(target_flags.get("can_attack", false))
	perception_button.visible = context == "marker" or context == "default" or context == "container"
	gossip_button.visible = context == "default" and can_talk
	talk_button.visible = context == "default" and can_talk
	attack_button.visible = context == "default" and can_attack
	var is_locked: bool = bool(target_flags.get("is_locked", false))
	var can_pick_lock: bool = bool(target_flags.get("can_pick_lock", false))
	open_button.visible = context == "container" and not is_locked
	break_button.visible = context == "container" and is_locked
	pick_lock_button.visible = context == "container" and is_locked and can_pick_lock
	lore_button.visible = context == "lore"
	travel_button.visible = context == "lore"

	var buttons: Array[Button] = []
	match context:
		"marker":
			perception_button.position = screen_pos - perception_button.custom_minimum_size / 2.0
			buttons = [perception_button]
		"lore":
			lore_button.position = screen_pos + Vector2(-90, -20)
			travel_button.position = screen_pos + Vector2(6, -20)
			buttons = [lore_button, travel_button]
		"container":
			open_button.position = screen_pos + Vector2(-90, -20)
			break_button.position = screen_pos + Vector2(-90, -20)
			perception_button.position = screen_pos + Vector2(6, -20)
			pick_lock_button.position = screen_pos + Vector2(-42, 30)
			buttons = [perception_button]
			if open_button.visible:
				buttons.append(open_button)
			if break_button.visible:
				buttons.append(break_button)
			if pick_lock_button.visible:
				buttons.append(pick_lock_button)
		_:
			## "default" — Perception is centered above the cursor when
			## it's the only option (a plain tile); Gossip/Talk or
			## Attack take the slots below it when the target allows.
			perception_button.position = screen_pos + Vector2(-42, -20)
			gossip_button.position = screen_pos + Vector2(-90, 30)
			talk_button.position = screen_pos + Vector2(6, 30)
			attack_button.position = screen_pos + Vector2(-42, 30)
			buttons = [perception_button]
			if gossip_button.visible:
				buttons.append(gossip_button)
			if talk_button.visible:
				buttons.append(talk_button)
			if attack_button.visible:
				buttons.append(attack_button)

	## Keep every visible button fully on screen even if the click was near an edge.
	var vp_size := get_viewport().get_visible_rect().size
	for btn in buttons:
		btn.position.x = clamp(btn.position.x, 4, vp_size.x - btn.size.x - 4)
		btn.position.y = clamp(btn.position.y, 4, vp_size.y - btn.size.y - 4)

func close() -> void:
	backdrop.visible = false
	perception_button.visible = false
	gossip_button.visible = false
	talk_button.visible = false
	attack_button.visible = false
	open_button.visible = false
	break_button.visible = false
	pick_lock_button.visible = false
	lore_button.visible = false
	travel_button.visible = false

func _select(option: String) -> void:
	close()
	menu_selected.emit(option)

## Any click that reaches the backdrop itself (not one of the
## buttons, which handle their own presses) means the player clicked
## outside the menu's options — dismiss without selecting anything.
func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if backdrop.visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
