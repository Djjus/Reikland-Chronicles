extends Control
## A Hermit Wizard trainer, offering two distinct magic-related
## services, both priced in XP rather than money:
##
## 1. Teaching the Petty Magic Talent itself (p.142) to a character who
##    doesn't have it — a one-time grant, at the normal 100 XP Talent
##    price rather than the doubled Non-Career rate, per the book's
##    Training Endeavour for learning a Talent your own Career doesn't
##    offer. Already implemented before this pass
##    (Advancement.learn_petty_magic_from_trainer) — this screen is
##    just where it's now offered, instead of a single dialogue popup.
##
## 2. Buying individual Petty or Arcane spells with XP, at the book's
##    own tiered cost (Advancement.purchase_petty_spell /
##    purchase_arcane_spell) — mirroring the same picker-plus-button
##    pattern Blessings/Miracles already use in the Character Menu,
##    per the request, just relocated to this dedicated trainer.

@onready var close_button: Button = %CloseButton
@onready var xp_label: Label = %XpLabel
@onready var message_label: Label = %MessageLabel
@onready var petty_magic_row: HBoxContainer = %PettyMagicRow
@onready var petty_spells_box: VBoxContainer = %PettySpellsBox
@onready var arcane_spells_box: VBoxContainer = %ArcaneSpellsBox

var character: Character

func _ready() -> void:
	close_button.pressed.connect(_on_close)
	GameState.ensure_player_character()
	character = GameState.player_character
	_rebuild_all()

func _rebuild_all() -> void:
	xp_label.text = "XP available: %d" % character.get_experience_available()
	_rebuild_petty_magic_row()
	_rebuild_petty_spells_box()
	_rebuild_arcane_spells_box()

## Learning the Talent itself — a one-time grant, not a repeatable
## purchase, so it's its own small row rather than a picker.
func _rebuild_petty_magic_row() -> void:
	for c in petty_magic_row.get_children():
		c.queue_free()
	if character.has_talent("Petty Magic"):
		var lbl := Label.new()
		lbl.text = "✓ You already carry the spark of Petty Magic."
		lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
		petty_magic_row.add_child(lbl)
		return
	var lbl := Label.new()
	lbl.text = "Learn the Petty Magic Talent:"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	petty_magic_row.add_child(lbl)
	var btn := Button.new()
	btn.text = "Learn (100 XP)"
	btn.disabled = character.get_experience_available() < 100
	btn.pressed.connect(func():
		var result := Advancement.learn_petty_magic_from_trainer(character)
		message_label.text = result.message
		message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55) if result.success else Color(0.85, 0.6, 0.55))
		if result.success:
			GameState.autosave()
		_rebuild_all()
	)
	petty_magic_row.add_child(btn)

## Petty spells — only shown once the character actually has the
## Petty Magic Talent, matching purchase_petty_spell's own requirement.
func _rebuild_petty_spells_box() -> void:
	for c in petty_spells_box.get_children():
		c.queue_free()
	if not character.has_talent("Petty Magic"):
		return
	petty_spells_box.add_child(_header("Petty Spells"))
	for known_name in character.known_spells:
		var sd: SpellDefinition = GameData.spell_db.find_by_name(known_name)
		if sd == null or sd.spell_type != "Petty":
			continue
		var known_label := Label.new()
		known_label.text = "✓ " + known_name
		known_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
		petty_spells_box.add_child(known_label)

	var known_count := 0
	for s in character.known_spells:
		var sd2: SpellDefinition = GameData.spell_db.find_by_name(s)
		if sd2 != null and sd2.spell_type == "Petty":
			known_count += 1
	var wpb := character.get_characteristic_bonus("willpower")
	var next_cost := Advancement._tiered_spell_cost(known_count, wpb, 50)

	var available: Array[SpellDefinition] = []
	for sp in GameData.spell_db.find_by_type("Petty"):
		if not character.known_spells.has(sp.spell_name):
			available.append(sp)
	if not available.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var picker := OptionButton.new()
		for sp in available:
			picker.add_item(sp.spell_name)
		row.add_child(picker)
		var btn := Button.new()
		btn.text = "Learn (%d XP)" % next_cost
		btn.disabled = character.get_experience_available() < next_cost
		btn.pressed.connect(func():
			var chosen := available[picker.selected].spell_name
			var result := Advancement.purchase_petty_spell(character, chosen)
			message_label.text = result.message
			message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55) if result.success else Color(0.85, 0.6, 0.55))
			if result.success:
				GameState.autosave()
			_rebuild_all()
		)
		row.add_child(btn)
		petty_spells_box.add_child(row)

## Arcane spells — only shown once the character has an Arcane Magic
## (Lore) Talent, matching purchase_arcane_spell's own requirement.
## Per the book's own "Arcane Spells" rule (p.242), every Arcane Magic
## holder draws from the same shared spell pool regardless of which
## specific Lore they picked — not filtered by Lore here, matching
## that rule.
func _rebuild_arcane_spells_box() -> void:
	for c in arcane_spells_box.get_children():
		c.queue_free()
	var lore := character.get_arcane_lore()
	if lore == "":
		return
	arcane_spells_box.add_child(_header("Arcane Spells (%s)" % lore))
	for known_name in character.known_spells:
		var sd: SpellDefinition = GameData.spell_db.find_by_name(known_name)
		if sd == null or sd.spell_type != "Arcane":
			continue
		var known_label := Label.new()
		known_label.text = "✓ " + known_name
		known_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
		arcane_spells_box.add_child(known_label)

	var known_count := 0
	for s in character.known_spells:
		var sd2: SpellDefinition = GameData.spell_db.find_by_name(s)
		if sd2 != null and sd2.spell_type == "Arcane":
			known_count += 1
	var int_bonus := character.get_characteristic_bonus("intelligence")
	var next_cost := Advancement._tiered_spell_cost(known_count, int_bonus, 100)

	var available: Array[SpellDefinition] = []
	for sp in GameData.spell_db.find_by_type("Arcane"):
		if not character.known_spells.has(sp.spell_name):
			available.append(sp)
	if not available.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var picker := OptionButton.new()
		for sp in available:
			picker.add_item(sp.spell_name)
		row.add_child(picker)
		var btn := Button.new()
		btn.text = "Learn (%d XP)" % next_cost
		btn.disabled = character.get_experience_available() < next_cost
		btn.pressed.connect(func():
			var chosen := available[picker.selected].spell_name
			var result := Advancement.purchase_arcane_spell(character, chosen)
			message_label.text = result.message
			message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55) if result.success else Color(0.85, 0.6, 0.55))
			if result.success:
				GameState.autosave()
			_rebuild_all()
		)
		row.add_child(btn)
		arcane_spells_box.add_child(row)

func _header(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.55, 0.85))
	return lbl

func _on_close() -> void:
	get_tree().change_scene_to_file("res://scenes/Overworld.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_close()
