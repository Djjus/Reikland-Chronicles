extends Control
## A Shallyan Priest healer service. Two distinct offerings:
## 1. Heal All Wounds — a flat, cheap 3 Brass Pennies restores Wounds
##    to full, regardless of how many are missing. Deliberately far
##    cheaper than the Condition cures below (3 BP vs 3 Shillings =
##    36 BP) — plain Wounds are common, minor, and Shallya's mercy for
##    them is correspondingly modest; lingering Conditions are the
##    real, lasting harm worth a proper offering.
## 2. Cures any single lingering Condition (Bleeding, Broken Bone, Torn
##    Muscle, Amputation, Blinded, Deafened, Stunned, Prone — whatever
##    the character is actually carrying) for a flat 3 Shillings per
##    condition-type, clearing every stack of it at once. This is a
##    real, working cure — not just a flavour interaction — since
##    these Conditions are exactly what this project's Critical Wound
##    tables actually apply.

const CURE_PRICE_PENNIES := 36   ## 3 Shillings = 3*12d
const WOUND_HEAL_PRICE_PENNIES := 3   ## 3 Brass Pennies, flat, regardless of how many Wounds are missing
## Per the request: Critical Wounds are more severe than a plain
## Condition — a real, lasting injury rather than a passing
## affliction — so treating one costs more than curing a Condition:
## double, 6 Shillings.
const CRITICAL_WOUND_CURE_PRICE_PENNIES := 72
## Party-wipe/permadeath rework, per the request ("If the entire party
## dies move them... to the Temple of Shallya... where they should be
## able to heal to revive"): calling someone back from real death (see
## Character.is_dead) is a far graver miracle than any of the above —
## priced a full order of magnitude past even a Critical Wound's own 6
## Shillings, at 12 Shillings flat.
const REVIVE_PRICE_PENNIES := 144   ## 12 Shillings = 12*12d

@onready var close_button: Button = %CloseButton
@onready var purse_label: Label = %PurseLabel
@onready var message_label: Label = %MessageLabel
@onready var conditions_box: VBoxContainer = %ConditionsBox
@onready var wounds_row: HBoxContainer = %WoundsRow
@onready var wounds_label: Label = %WoundsLabel
@onready var heal_wounds_button: Button = %HealWoundsButton
@onready var prev_char_button: Button = %PrevCharButton
@onready var char_name_label: Label = %CharNameLabel
@onready var next_char_button: Button = %NextCharButton
@onready var revive_row: HBoxContainer = %ReviveRow
@onready var revive_button: Button = %ReviveButton
## Party-wipe rework's own Shift+Ctrl "secret cheat button" request
## ("give healers the ability to get Fate points while holding the
## secret cheat button"): same held-Shift+Ctrl reveal-a-hidden-button
## convention already established in character_menu_screen.gd's own
## _xp_cheat_button and advancement_screen.gd's own _test_mode_active()
## — see _process() below.
@onready var fate_cheat_button: Button = %FateCheatButton

var character: Character

func _ready() -> void:
	close_button.pressed.connect(_on_close)
	heal_wounds_button.pressed.connect(_on_heal_wounds)
	prev_char_button.pressed.connect(func(): _cycle_character(-1))
	next_char_button.pressed.connect(func(): _cycle_character(1))
	revive_button.pressed.connect(_on_revive)
	fate_cheat_button.pressed.connect(_on_fate_cheat)
	GameState.ensure_player_character()
	character = GameState.player_character
	_rebuild_all()

## Same held-Shift+Ctrl "reveal a hidden testing button" pattern already
## established in character_menu_screen.gd/advancement_screen.gd — a
## continuously-polled visibility gate, not a one-shot key press, so the
## button appears/disappears live as the keys are held/released.
func _process(_delta: float) -> void:
	fate_cheat_button.visible = Input.is_key_pressed(KEY_SHIFT) and Input.is_key_pressed(KEY_CTRL)

## Per the request: treat any present party member, not just whoever's
## active on the map — same independent "who am I viewing" cycling as
## the Shop and Character Menu use, so switching who's on Shallya's
## table here doesn't also change who you're controlling outside.
func _cycle_character(direction: int) -> void:
	if GameState.party.size() <= 1:
		return
	var idx: int = GameState.party.find(character)
	if idx < 0:
		idx = 0
	idx = posmod(idx + direction, GameState.party.size())
	character = GameState.party[idx]
	_rebuild_all()

func _rebuild_all() -> void:
	char_name_label.text = "Treating: %s" % character.character_name
	var multiple_members := GameState.party.size() > 1
	prev_char_button.disabled = not multiple_members
	next_char_button.disabled = not multiple_members
	purse_label.text = "Purse: %d GC   %d SS   %d BP" % [character.gold_crowns, character.silver_shillings, character.brass_pennies]

	## Party-wipe/permadeath rework: a genuinely dead character (see
	## Character.is_dead's own doc comment) isn't just badly hurt —
	## ordinary Wound-healing/Condition-curing/Critical-Wound-treating
	## don't apply to a corpse, so those rows are hidden entirely and
	## replaced with the one real option: a proper Revive. Reappears the
	## instant is_dead clears (see _on_revive below), same _rebuild_all()
	## refresh every other transaction here already does.
	revive_row.visible = character.is_dead
	revive_button.disabled = character.get_total_pennies() < REVIVE_PRICE_PENNIES
	wounds_row.visible = not character.is_dead
	if character.is_dead:
		_clear(conditions_box)
		return

	wounds_label.text = "Wounds: %d/%d" % [character.wounds_current, character.wounds_max]
	var fully_healed := character.wounds_current >= character.wounds_max
	heal_wounds_button.disabled = fully_healed or character.get_total_pennies() < WOUND_HEAL_PRICE_PENNIES
	heal_wounds_button.text = "Fully Healed" if fully_healed else "Heal All Wounds (3 BP)"
	_clear(conditions_box)
	var has_conditions := not character.conditions.is_empty()
	var has_critical_wounds := character.active_critical_wound_count > 0
	if not has_conditions and not has_critical_wounds:
		var none_lbl := Label.new()
		none_lbl.text = "You carry no lingering wounds or afflictions. Shallya smiles upon you."
		none_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
		conditions_box.add_child(none_lbl)
		return
	for cond_name in character.conditions.keys():
		var stacks: int = character.conditions[cond_name]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text = "%s x%d" % [cond_name, stacks] if stacks > 1 else cond_name
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "Cure for 3/–"
		btn.disabled = character.get_total_pennies() < CURE_PRICE_PENNIES
		btn.pressed.connect(func(): _on_cure(cond_name))
		row.add_child(btn)
		conditions_box.add_child(row)

	## Per the request: real Critical Wounds, treatable at cost — the
	## actual bug fix. Each entry in critical_wound_penalties gets its
	## own Treat button (removes that specific ongoing penalty and
	## counts down active_critical_wound_count by one); any remaining
	## active Critical Wounds beyond that (a real, valid state — not
	## every Critical Wound carries a stat penalty, but all of them
	## still count toward the Toughness Bonus death-threshold rule) get
	## a generic Treat option with the same real effect, just with no
	## specific penalty to name.
	if has_critical_wounds:
		var cw_header := Label.new()
		cw_header.text = "Critical Wounds:"
		cw_header.add_theme_color_override("font_color", Color(0.85, 0.55, 0.5))
		conditions_box.add_child(cw_header)
		for i in range(character.critical_wound_penalties.size()):
			var penalty: Dictionary = character.critical_wound_penalties[i]
			var char_key: String = (penalty["characteristic_bonuses"].keys() as Array)[0]
			var amount: int = penalty["characteristic_bonuses"][char_key]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var lbl := Label.new()
			lbl.text = "%s (%+d %s, %d day(s) left)" % [penalty["name"], amount, CharacteristicSet.SHORT_NAMES.get(char_key, char_key), penalty["rounds_remaining"]]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			var btn := Button.new()
			btn.text = "Treat for 6/–"
			btn.disabled = character.get_total_pennies() < CRITICAL_WOUND_CURE_PRICE_PENNIES
			btn.pressed.connect(func(): _on_treat_critical_wound(i))
			row.add_child(btn)
			conditions_box.add_child(row)
		var untreated_count: int = character.active_critical_wound_count - character.critical_wound_penalties.size()
		for i in range(untreated_count):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var lbl := Label.new()
			lbl.text = "An old wound, healed crooked but no longer paining you day to day"
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			var btn := Button.new()
			btn.text = "Treat for 6/–"
			btn.disabled = character.get_total_pennies() < CRITICAL_WOUND_CURE_PRICE_PENNIES
			btn.pressed.connect(_on_treat_untracked_critical_wound)
			row.add_child(btn)
			conditions_box.add_child(row)

## Party-wipe/permadeath rework's own real revive action: the ONLY way a
## genuinely dead character (Character.is_dead) ever comes back — no
## in-field healing, spell, or the old free auto-revive-on-defeat
## mechanic touches this flag anymore, only a real Shallyan Priest
## visit. Brings them back at 1 Wound (same "battered, but alive" floor
## Fate's own Die Another Day/How Did That Miss? options already use —
## see field_encounter_screen.gd's _handle_fatal_moment()), not a full
## heal; getting the rest of the way back to full health is an ordinary
## Heal All Wounds purchase like anyone else's, once is_dead is cleared
## and the normal Wounds row reappears.
func _on_revive() -> void:
	if not character.is_dead:
		return
	if not character.spend_pennies(REVIVE_PRICE_PENNIES):
		message_label.text = "Calling a soul back from death is beyond what you can currently offer Shallya."
		message_label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.55))
		return
	character.is_dead = false
	character.wounds_current = 1
	message_label.text = "The Priest kneels beside %s a long while in prayer. \"...Rise. Shallya has not finished with you yet.\"" % character.character_name
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	GameState.autosave()
	_rebuild_all()

## Same held-Shift+Ctrl testing convention as _xp_cheat_button
## (character_menu_screen.gd) — grants the character currently being
## treated one Fate Point, free, no purse cost. Its own visibility
## (Shift+Ctrl held, see _process() above) is independent of
## revive_row's — both can show together on a dead character, since
## granting Fate doesn't depend on being alive; it's purely a testing
## aid, not a purchase.
func _on_fate_cheat() -> void:
	character.fate_points += 1
	message_label.text = "[testing] %s gains a Fate Point (%d total)." % [character.character_name, character.fate_points]
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	GameState.autosave()
	_rebuild_all()

func _on_heal_wounds() -> void:
	if character.wounds_current >= character.wounds_max:
		return
	if not character.spend_pennies(WOUND_HEAL_PRICE_PENNIES):
		message_label.text = "You can't even afford Shallya's modest offering right now."
		message_label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.55))
		return
	character.wounds_current = character.wounds_max
	message_label.text = "The Priest lays hands on your wounds. \"Rise, and go with Shallya's blessing.\""
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	GameState.autosave()
	_rebuild_all()

func _on_cure(condition_name: String) -> void:
	if not character.spend_pennies(CURE_PRICE_PENNIES):
		message_label.text = "You can't afford Shallya's mercy right now."
		message_label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.55))
		return
	character.remove_condition(condition_name)
	message_label.text = "The Priest tends to your %s. \"Rest easy now.\"" % condition_name
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	GameState.autosave()
	_rebuild_all()

## Treats one specific Critical Wound that has a real, ongoing stat
## penalty — removes that exact penalty entry and reduces
## active_critical_wound_count by one, since that wound is now healed.
func _on_treat_critical_wound(index: int) -> void:
	if index < 0 or index >= character.critical_wound_penalties.size():
		return
	if not character.spend_pennies(CRITICAL_WOUND_CURE_PRICE_PENNIES):
		message_label.text = "You can't afford Shallya's mercy for a wound this deep."
		message_label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.55))
		return
	var penalty_name: String = character.critical_wound_penalties[index].get("name", "wound")
	character.critical_wound_penalties.remove_at(index)
	character.active_critical_wound_count = max(0, character.active_critical_wound_count - 1)
	message_label.text = "The Priest tends carefully to your %s. \"That will trouble you no longer.\"" % penalty_name
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	GameState.autosave()
	_rebuild_all()

## Per the request's own real bug: treats a Critical Wound that never
## had a visible stat penalty attached to it at all — these still
## count toward active_critical_wound_count (relevant to the
## Toughness Bonus death-threshold rule), but had no matching entry in
## critical_wound_penalties for the old, penalty-only cure path to
## find, so the Healer couldn't see or treat them.
func _on_treat_untracked_critical_wound() -> void:
	if character.active_critical_wound_count <= character.critical_wound_penalties.size():
		return
	if not character.spend_pennies(CRITICAL_WOUND_CURE_PRICE_PENNIES):
		message_label.text = "You can't afford Shallya's mercy for a wound this deep."
		message_label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.55))
		return
	character.active_critical_wound_count = max(0, character.active_critical_wound_count - 1)
	message_label.text = "The Priest tends to your old wound. \"Healed, if not forgotten.\""
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	GameState.autosave()
	_rebuild_all()

## Temple of Shallya feature ("hook up The Temple of Shallya in
## Ubersreik, copy the priestess from Giessingen"): this screen now has
## two distinct entry points -- Giessingen's own map tile (priest_coords
## in overworld.gd, unchanged, no pending id set) and Ubersreik's new
## "Enter" radial action on The Temple of Shallya (CityScreen's own
## _enter_temple(), which sets pending_healer_city_id first). Same
## "pending id -> pending_city_id -> CityScreen.tscn" hand-off
## RatCatcherGuildScreen._on_close() already uses. An empty
## pending_healer_city_id means "reached via Giessingen's own map tile,"
## which keeps returning straight to Overworld.tscn exactly as it always
## has.
func _on_close() -> void:
	if GameState.pending_healer_city_id != "":
		GameState.pending_city_id = GameState.pending_healer_city_id
		GameState.pending_healer_city_id = ""
		GameState.autosave()
		get_tree().change_scene_to_file("res://scenes/CityScreen.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Overworld.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_close()
		## Per the request: Q/E cycle which party member Shallya is
		## currently treating, same direction/keys convention and same
		## no-op-below-2-members guard as the Prev/Next buttons
		## _cycle_character() already handles.
		elif event.keycode == KEY_Q:
			get_viewport().set_input_as_handled()
			_cycle_character(-1)
		elif event.keycode == KEY_E:
			get_viewport().set_input_as_handled()
			_cycle_character(1)

func _clear(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()
