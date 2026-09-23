extends CanvasLayer
## In-game character menu. Per the menu rework request: Stats / Equipment /
## Inventory / Spellbook / Career / Group / Journal, plus the pre-existing
## Switch Character tab (kept — the Pause Menu's own Switch button opens
## straight into it, see overworld.gd's SWITCH_CHARACTER_TAB_INDEX). A
## persistent header (name/race/career/tier/XP/Wounds/Fate/etc.) now sits
## above the tab bar so that summary information is always visible instead
## of being duplicated per-tab. Reads and acts on the real
## GameState.player_character rather than a throwaway test character.
## Toggled from the overworld with the "open_menu" action (C by default).
## Input (both C and Esc to close) is handled centrally by Overworld
## rather than here, since Esc is shared with the pause menu and having
## two nodes independently race to consume the same keypress is fragile.

signal closed

@onready var header_portrait: TextureRect = %HeaderPortrait
@onready var header_line1: RichTextLabel = %HeaderLine1
@onready var header_line2: RichTextLabel = %HeaderLine2
@onready var header_cheat_row: HBoxContainer = %HeaderCheatRow

@onready var characteristics_box: VBoxContainer = %CharacteristicsBox
@onready var skills_box: VBoxContainer = %SkillsBox
@onready var talents_box: VBoxContainer = %TalentsBox

@onready var weapons_box: VBoxContainer = %WeaponsBox
@onready var armor_box: VBoxContainer = %ArmorBox
@onready var container_box: VBoxContainer = %ContainerBox

@onready var inventory_box: VBoxContainer = %InventoryBox

@onready var spellbook_tabs: TabContainer = %SpellbookTabs
@onready var spells_box: VBoxContainer = %SpellsBox
@onready var blessings_miracles_box: VBoxContainer = %BlessingsMiraclesBox

@onready var career_box: VBoxContainer = %CareerBox

@onready var group_box: VBoxContainer = %GroupBox

## Shared yes/no confirmation overlay — used both for Group's Dismiss
## and Switch Character's Delete, per the request to add the same kind
## of warning check to the Delete button too. _pending_confirm_action
## holds whatever should run if the player clicks Yes; Cancel just
## hides the overlay and drops it.
@onready var confirm_overlay: Control = %ConfirmOverlay
@onready var confirm_title_label: Label = %ConfirmTitle
@onready var confirm_warning_label: Label = %ConfirmWarningLabel
@onready var confirm_yes_button: Button = %ConfirmYesButton
@onready var confirm_cancel_button: Button = %ConfirmCancelButton
var _pending_confirm_action: Callable = Callable()

@onready var journey_box: VBoxContainer = %JourneyBox
@onready var quests_box: VBoxContainer = %QuestsBox
@onready var save_load_box: VBoxContainer = %SaveLoadBox

@onready var close_button: Button = %CloseButton
@onready var tabs: TabContainer = %Tabs

var character: Character
## Per the request: reference to the hidden XP cheat button so
## _process() below can continuously show/hide it based on held keys —
## now shown/hidden purely by the key combo, not tied to a specific
## tab being focused, since it lives in the always-visible header
## rather than inside the old Experience tab.
var _xp_cheat_button: Button = null

## Per the request: this in-game Character menu is the "default view"
## players actually use — every Sell button built via _add_xp_row
## (Characteristics, Skills, Talents, the "(Any)" slot pickers) gets
## the same Test-mode gate as the Advancement screen's own copy: hidden
## during normal play, shown only while Shift+Control (the same
## gesture that reveals the XP cheat button above) is held. Tracked so
## _process can toggle visibility live without a full rebuild. Cleared
## at the top of _rebuild_all() (not per-tab) since every tab's own
## rebuild function appends to this same shared list.
var _gated_sell_buttons: Array = []

## Per the request: the Characteristics grid was stretching edge-to-edge
## across the whole window on wide displays — capped to 75% of the
## window width instead (see _rebuild_characteristics below). Kept as a
## reference here, rather than only set once at build time, so the
## `resized` handler below can re-cap it live if the window changes size
## without needing a full tab rebuild.
var _characteristics_grid_wrap: Control = null

func _ready() -> void:
	close_button.pressed.connect(close)
	confirm_yes_button.pressed.connect(_on_confirm_yes)
	confirm_cancel_button.pressed.connect(_on_confirm_cancel)
	get_viewport().size_changed.connect(_on_viewport_resized)
	visible = false

## See _characteristics_grid_wrap above.
##
## Real bug fix: this used to cap against get_viewport().get_visible_rect()
## — the full screen/window's own resolution — rather than the actual
## Character menu's own width, so on a wide display 75% of the FULL
## SCREEN was still comfortably wider than the menu itself, and the grid
## visibly overran the menu's right edge. `tabs` (%Tabs, the outermost
## TabContainer that IS the bordered "Character" window itself) is the
## right reference to measure 75% against instead.
func _on_viewport_resized() -> void:
	if _characteristics_grid_wrap != null and is_instance_valid(_characteristics_grid_wrap):
		_characteristics_grid_wrap.custom_minimum_size.x = tabs.size.x * 0.75

## Shows the shared confirmation overlay with the given title/warning
## text; `on_confirm` runs only if the player clicks Yes.
func _open_confirm(title: String, warning: String, on_confirm: Callable) -> void:
	confirm_title_label.text = title
	confirm_warning_label.text = warning
	_pending_confirm_action = on_confirm
	confirm_overlay.visible = true

func _on_confirm_yes() -> void:
	confirm_overlay.visible = false
	var action := _pending_confirm_action
	_pending_confirm_action = Callable()
	if action.is_valid():
		action.call()

func _on_confirm_cancel() -> void:
	confirm_overlay.visible = false
	_pending_confirm_action = Callable()

func _process(_delta: float) -> void:
	if not visible or _xp_cheat_button == null:
		return
	var keys_held: bool = Input.is_key_pressed(KEY_SHIFT) and Input.is_key_pressed(KEY_CTRL)
	_xp_cheat_button.visible = keys_held
	for btn in _gated_sell_buttons:
		if is_instance_valid(btn):
			btn.visible = keys_held

func open(tab_index: int = 0) -> void:
	character = GameState.player_character
	visible = true
	_rebuild_all()
	tabs.current_tab = tab_index

## Per the request: Q/E cycles which party member's own stats,
## equipment, inventory, spellbook, and career are shown here — a real,
## independent "who am I viewing" concept, separate from
## GameState.active_party_index, so browsing a teammate's gear in this
## menu doesn't also change who you're actively controlling out on
## the map. Group, Quests and the Journal are deliberately unaffected —
## see _rebuild_group()/_rebuild_journal()/_rebuild_quests(), which
## always read the party's own shared record regardless of who's being
## viewed here.
func cycle_displayed_character(direction: int) -> void:
	if GameState.party.size() <= 1:
		return
	var idx: int = GameState.party.find(character)
	if idx < 0:
		idx = 0
	idx = posmod(idx + direction, GameState.party.size())
	character = GameState.party[idx]
	_rebuild_all()

func close() -> void:
	visible = false
	closed.emit()

func _rebuild_all() -> void:
	## Every tab's own rebuild below calls _add_xp_row, which appends
	## any Sell button it creates to this shared list — cleared once
	## here rather than per-tab, since a full _rebuild_all() rebuilds
	## every tab's rows from scratch each time.
	_gated_sell_buttons.clear()
	_rebuild_header()
	_rebuild_characteristics()
	_rebuild_skills()
	_rebuild_talents()
	_rebuild_weapons()
	_rebuild_armor()
	_rebuild_containers()
	_rebuild_inventory()
	_rebuild_spellbook()
	_rebuild_career()
	_rebuild_group()
	_rebuild_journal()
	_rebuild_quests()
	_rebuild_save_load()

func _clear(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()

func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	l.add_theme_font_size_override("font_size", 18)
	return l

## --- Persistent header ------------------------------------------------------
## Per the request: name/class/career/XP info moved out of the
## per-tab content (previously duplicated across the old Stats and
## Experience tabs) so it's always visible no matter which tab is
## open. Wounds/Movement/Fate/Fortune/Resilience/Resolve/Sin (the old
## Stats tab's "Derived" line) live here too for the same reason.

func _rebuild_header() -> void:
	if character == null:
		header_line1.text = ""
		header_line2.text = ""
		header_portrait.texture = null
		return
	## Per the request: the character's full-size AI-generated Career
	## portrait (transparent background) now shows next to the header
	## text — see career_portraits.gd for the career_name -> art lookup,
	## now also used for every other party-member portrait in and out of
	## combat (Overworld/City top bar, Camp/Tavern rows, battle screen).
	header_portrait.texture = CareerPortraits.get_portrait_for_character(character)
	## Per the follow-up request ("move enc to the top row"): the
	## Encumbrance reading sits on the top header line (name/race/
	## career/XP), near the top-right, close to the Close button.
	## Per the later cleanup request ("remove the large gaps and
	## unnecessary spaces... show Group Coin after Enc in the top
	## row"): every field on this line is now separated by a single
	## " | " (the same separator this project's own battle-log notices
	## already use — see field_encounter_screen.gd's "Loot this
	## battle:"/"Final Round conditions:" lines) instead of runs of
	## several spaces, and the whole party's combined coin closes out
	## the line.
	var enc_current := character.get_current_encumbrance()
	var enc_capacity := character.get_carrying_capacity()
	var enc_penalty := character.get_encumbrance_penalty()
	var enc_color := "#d98a80" if enc_penalty["tier"] != "None" else "#99cc8c"
	## Per the follow-up request ("change all 'x / x' values, remove the
	## spaces"): every plain current/max ratio on this header now reads
	## "x/x" instead of "x / x" — this does NOT apply to "Walk X / Run
	## Y" below, which isn't a current/max ratio of the same value, just
	## two different labelled numbers sharing a slash separator.
	var enc_text := "[color=%s]Enc: %d/%d[/color]" % [enc_color, roundi(enc_current), enc_capacity]
	## Per the request: XP now shows just the total and what's still
	## unspent — the "spent" figure is redundant with total-minus-
	## unspent and was cluttering the line.
	header_line1.text = "[b]%s[/b] — %s %s, %s (Tier %d) | [b]XP:[/b] %d total, [b]%d unspent[/b] | %s | %s" % [
		character.character_name,
		character.race.race_name if character.race else "?",
		character.career.career_name if character.career else "?",
		character.career.get_level(character.current_tier).level_name if character.career else "?",
		character.current_tier,
		character.experience_total, character.get_experience_available(),
		enc_text,
		_gender_text(),
	]
	## Per the request: Movement gets the same "temporarily reduced" red
	## flagging as the Characteristics list — Crippled Leg's halving and
	## Encumbrance's reduction are exactly the kind of effect this is
	## meant to surface, and Movement is the one header stat either of
	## those can actually knock down.
	var current_move := character.get_movement()
	var base_move := character.get_unmodified_movement()
	var move_text := "Movement: %d (Walk %d / Run %d)" % [current_move, character.get_walk_distance(), character.get_run_distance()]
	if current_move < base_move:
		move_text = "[color=#d95a52]%s (base %d — reduced)[/color]" % [move_text, base_move]
	header_line2.text = "Wounds: %d/%d | %s | Fate: %d | Fortune: %d/%d | Resilience: %d | Resolve: %d/%d" % [
		character.wounds_current, character.wounds_max, move_text,
		character.fate_points, character.fortune_points, character.fate_points,
		character.resilience, character.resolve, character.resilience,
	]
	## Per the request ("move Sin and corruption to the next row and
	## place any active condition/critical wound data on selected
	## character next to them in that row"): Sin/Corruption used to
	## share the Wounds/Movement/Fate line above; now they're their own
	## row, with Conditions (Fatigued, Bleeding, etc.) and the running
	## Critical Wound count appended alongside them on that same row —
	## same "Name xN" / "K Critical Wound(s)" format the battle screen's
	## own party/enemy panels already use (_refresh_player_display /
	## _refresh_enemy_display in field_encounter_screen.gd), for
	## consistency across both screens.
	var ailment_parts: Array[String] = []
	for cond_name in character.conditions.keys():
		var stacks: int = character.conditions[cond_name]
		ailment_parts.append("%s x%d" % [cond_name, stacks] if stacks > 1 else cond_name)
	if character.active_critical_wound_count > 0:
		ailment_parts.append("%d Critical Wound(s)" % character.active_critical_wound_count)
	var sin_row := "Sin: %d | Corruption: %d/%d" % [character.sin_points, character.corruption_points, character.get_corruption_threshold()]
	if not ailment_parts.is_empty():
		sin_row += " | " + ", ".join(ailment_parts)
	header_line2.text += "\n" + sin_row

	## Per the request: Corruption tracked "in the Menu" — Mutations
	## gained (if any) shown right underneath the Derived line, same
	## RichTextLabel, rather than a whole new tab for what's likely a
	## short, rare list.
	if not character.mutations_gained.is_empty():
		header_line2.text += "\nMutations: " + ", ".join(character.mutations_gained)

	## A quick way to grant XP for testing, not a real game mechanic —
	## real XP comes from kills/rewards. Hidden by default, only
	## revealed while both Left Shift and Ctrl are held down at once —
	## a deliberate, hard-to-trigger-by-accident combination for
	## something this powerful, checked continuously in _process()
	## above rather than a one-off key press. Lives in the header now
	## (rather than gated to a specific tab) since there's no longer a
	## single "Experience" tab for it to be scoped to.
	for c in header_cheat_row.get_children():
		c.queue_free()
	var add_xp_btn := Button.new()
	add_xp_btn.text = "+100 XP (testing)"
	add_xp_btn.visible = false
	add_xp_btn.pressed.connect(func():
		character.experience_total += 100
		_rebuild_all()
	)
	_xp_cheat_button = add_xp_btn
	header_cheat_row.add_child(add_xp_btn)

	## Per the request ("lets now remove the Gender toggle button"): the
	## always-visible "Toggle Gender" button that used to live here is
	## gone. It existed only as a one-click self-correction for
	## characters caught by the old gender-not-persisted save/load bug
	## (see CharacterGenderPersistenceTest) — that bug is long fixed in
	## Character.to_save_dict()/from_save_dict(), so gender now persists
	## correctly on its own and this manual workaround is no longer
	## needed. The read-only "Gender: Male"/"Gender: Female" display
	## itself (_gender_text(), shown in the header's HeaderLine1) is
	## untouched — only the button that let a player flip it is removed.

## Per the follow-up request ("remove group coin from the menu header
## and display the character gender instead"): the header's own Group
## Coin reading (formerly _group_coin_text() here) is gone — nothing is
## actually lost, since the Inventory tab already shows the exact same
## shared-party total under its own "Coin (shared by the whole party)"
## header (see _rebuild_inventory) — and Gender takes its place instead,
## which previously had no display anywhere in the Character Menu.
func _gender_text() -> String:
	return "Gender: %s" % character.gender.capitalize()

## --- Stats tab: shared Characteristics/Skills/Talents grid ---------------------
## Per the follow-up request ("copy the grid format in Inventory tab to
## Characteristics and Skill subtabs. make the columns: Career
## (checkboxes, tick if available in the current career),
## Characteristic/Skill (modified values), Advances (purchased), Train
## (Buy buttons)"): all three Stats sub-tabs render the same boxed grid
## the Inventory tab already uses (_boxed_cell/_faint_row_style above).
##
## Per the follow-up request ("Separate stats name and values into
## separate columns"): the grid grew from 4 columns to 5 — Career / Name
## / Value / Advances / Train — splitting what used to be one combined
## "Name: Value" label (e.g. "WS: 28 (2)", "Athletics: 40") into its own
## Name and Value cells.
const _STAT_GRID_COLUMNS := 5

## Builds the Career-availability indicator for a grid row. Per the
## follow-up request ("replace the current Tick boxes in the Stats sub
## menus with one that looks just like the favourite button from the
## inventory screen, but with a tick instead of a star"): same Button
## type, same "filled vs hollow glyph + colour swap" language as the
## Inventory tab's own favourite star (_rebuild_inventory's star_btn —
## gold when set, muted grey when not), but with a checked/unchecked
## ballot-box glyph instead of a star, and genuinely inert — no
## `.pressed` connection at all — since Career availability reflects
## real Advancement state, not something the player sets by clicking
## here (the old CheckBox this replaces was `disabled = true` for the
## same reason; a plain unconnected Button reads visually identical to
## the star button while still doing nothing on click).
static func _career_tick_button(unlocked: bool) -> Button:
	var btn := Button.new()
	btn.text = "☑" if unlocked else "☐"
	btn.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35) if unlocked else Color(0.55, 0.5, 0.42))
	btn.tooltip_text = "" if unlocked else "Not currently available at your Career level"
	btn.focus_mode = Control.FOCUS_NONE
	## Per the request: this button was inheriting the global theme's
	## purple Button styleboxes and stretching to fill the whole Career
	## column — neither was ever intended (the comment above already says
	## it should look just like the Inventory tab's own favourite-star
	## button, glyph and colour only). An empty stylebox in every state
	## drops the background box entirely, and a small fixed size plus
	## SHRINK_CENTER keeps it a compact, centred square instead of a
	## full-width bar.
	var no_bg := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", no_bg)
	btn.add_theme_stylebox_override("hover", no_bg)
	btn.add_theme_stylebox_override("pressed", no_bg)
	btn.add_theme_stylebox_override("focus", no_bg)
	btn.add_theme_stylebox_override("disabled", no_bg)
	btn.custom_minimum_size = Vector2(28, 28)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return btn

## Builds the grid's own header row: Career / name_column_title (either
## "Characteristic", "Skill", or "Talent") / value_column_title ("Value"
## or "Rank") / Advances / Train.
## Per the follow-up request ("make sure the skill submenu does not
## scroll sideways, make it less wide if required"): a real, long-played
## character's Skills grid (many rows, some with long specialisation
## names like "Language (Bretonnian)") measurably overflowed its panel
## by a small but real margin once a vertical scrollbar also appeared
## (which itself eats a few pixels of width) — "Advances" alone was
## costing 96px of fixed header width per column, times two columns.
## `compact` shortens the Career/Value/Advances headers to "Car"/"Val"/
## "Adv" (with the full word still on hover via tooltip_text) to claw
## that back; only the two-column Skills grid passes compact=true —
## Characteristics and Talents stay full-width, single-column, and keep
## the full words.
static func _stat_grid_header_row(grid: GridContainer, name_column_title: String, value_column_title: String = "Value", compact: bool = false) -> void:
	var career_header := Label.new()
	career_header.text = "Car" if compact else "Career"
	if compact:
		career_header.tooltip_text = "Career"
		career_header.mouse_filter = Control.MOUSE_FILTER_STOP
	career_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	career_header.add_theme_font_size_override("font_size", 12)
	career_header.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
	grid.add_child(_header_cell(career_header))

	var name_header := Label.new()
	name_header.text = name_column_title
	name_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_header.add_theme_font_size_override("font_size", 12)
	name_header.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
	grid.add_child(_header_cell(name_header, true))

	var value_header := Label.new()
	value_header.text = "Val" if compact else value_column_title
	if compact:
		value_header.tooltip_text = value_column_title
		value_header.mouse_filter = Control.MOUSE_FILTER_STOP
	value_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_header.add_theme_font_size_override("font_size", 12)
	value_header.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
	grid.add_child(_header_cell(value_header))

	var adv_header := Label.new()
	adv_header.text = "Adv" if compact else "Advances"
	if compact:
		adv_header.tooltip_text = "Advances"
		adv_header.mouse_filter = Control.MOUSE_FILTER_STOP
	adv_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	adv_header.add_theme_font_size_override("font_size", 12)
	adv_header.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
	grid.add_child(_header_cell(adv_header))

	var train_header := Label.new()
	train_header.text = "Train"
	train_header.add_theme_font_size_override("font_size", 12)
	train_header.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
	grid.add_child(_header_cell(train_header))

## Builds one ordinary row of the grid: a Career-availability tick
## button, the Characteristic/Skill/Talent's own Name and Value in their
## own separate columns (per the follow-up request "Separate stats name
## and values into separate columns" — these used to be one combined
## "Name: Value" label), its purchased Advances count, and a Train cell
## with Buy/Sell buttons — either omitted by passing an invalid
## Callable, same convention _add_xp_row already used (e.g. a "not
## currently in Career, Sell-only" row passes an invalid on_buy).
## `parked_reason`, when non-empty, means this row's Talent is
## mechanically parked (TalentDefinition.mechanically_parked — see that
## field's own doc comment): the Buy button is still built and shown
## (unlike the maxed-rank case, which omits it via an invalid Callable)
## but forced disabled, with this text as its tooltip instead of the
## normal "N XP" one, so the reason is visible on hover.
func _add_stat_grid_row(grid: GridContainer, unlocked: bool, name_text: String, value_text: String, advances: int,
		cost: int, on_buy: Callable, sell_cost: int, on_sell: Callable, red: bool = false, tooltip_text: String = "",
		compact: bool = false, parked_reason: String = "") -> void:
	## --- Career column ---------------------------------------------------
	grid.add_child(_boxed_cell(_career_tick_button(unlocked), 0, _STAT_GRID_COLUMNS))

	## --- Name column ---------------------------------------------------
	var name_label := Label.new()
	name_label.text = name_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if red:
		name_label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
	elif not unlocked:
		name_label.add_theme_color_override("font_color", Color(0.6, 0.55, 0.48))
	if tooltip_text != "":
		name_label.tooltip_text = tooltip_text
		name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	grid.add_child(_boxed_cell(name_label, 1, _STAT_GRID_COLUMNS, true))

	## --- Value column ---------------------------------------------------
	## Per the follow-up request ("Separate stats name and values into
	## separate columns"): the live modified value (e.g. "28 (2)" for a
	## Characteristic, "40" for a Skill, "rank 2 / 3" for a Talent) gets
	## its own cell instead of being crammed into the Name column behind
	## a colon. Same red/dim colour treatment and tooltip as the Name
	## column, since both halves of the old combined label described the
	## same row and should read consistently.
	var value_label := Label.new()
	value_label.text = value_text
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if red:
		value_label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
	elif not unlocked:
		value_label.add_theme_color_override("font_color", Color(0.6, 0.55, 0.48))
	if tooltip_text != "":
		value_label.tooltip_text = tooltip_text
		value_label.mouse_filter = Control.MOUSE_FILTER_STOP
	grid.add_child(_boxed_cell(value_label, 2, _STAT_GRID_COLUMNS))

	## --- Advances column ------------------------------------------------------
	var adv_label := Label.new()
	adv_label.text = "+%d" % advances if advances > 0 else "0"
	adv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(_boxed_cell(adv_label, 3, _STAT_GRID_COLUMNS))

	## --- Train column: same Shift+Ctrl Sell gate _add_xp_row always used ---
	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 6)
	## Per the follow-up request ("split basic and advanced skills into
	## separate columns side by side, each using 50% of the width"): two
	## of these grids now sit side by side in half the space one used to
	## have. Measured at runtime: the full "Sell (+N XP)"/"Buy (N XP)"
	## labels' own natural (unclipped) width alone pushes the two
	## columns' combined minimum width past the panel's available width,
	## forcing a horizontal scrollbar. Two wrong fixes tried first:
	## setting clip_text alone (with the full-length label) shrinks
	## Godot's *reported minimum size* for the button down to just its
	## icon/stylebox padding — regardless of the text's actual length —
	## so the button renders at that tiny size with its label entirely
	## invisible; shortening the label text ALONE doesn't help either,
	## since clip_text ignores text length for minimum-size purposes no
	## matter how short the string is. The real fix needs both pieces
	## together: an explicit custom_minimum_size wide enough for the
	## short "Sell"/"Buy" label to actually render, with clip_text left
	## on purely as a safety net (so if it ever doesn't quite fit, it
	## clips instead of re-forcing the whole grid wider).
	## Per the follow-up request ("remove the word Buy, and only leave
	## the XP cost, eg. 15 XP"): the Train column's own purchase button
	## across Characteristics/Skills/Talents now shows just "%d XP"
	## instead of "Buy (%d XP)" — in both compact and full modes.
	## compact_button_min_width bumped slightly (64 -> 72) since "999 XP"
	## runs a touch longer than the old bare "Buy" label this width was
	## originally sized for; clip_text stays on as the same safety net
	## either way.
	var compact_button_min_width := 72
	if sell_cost >= 0 and on_sell.is_valid():
		var sell_button := Button.new()
		sell_button.text = "Sell" if compact else "Sell (+%d XP)" % sell_cost
		## clip_text (and its compensating custom_minimum_size) is only
		## ever applied in compact mode. This matters, not just for
		## tidiness: clip_text discards a Button's text-length
		## contribution to its own reported minimum size UNCONDITIONALLY
		## — leaving it on for the full, non-compact "Sell (+N XP)"/
		## "N XP" label with no custom_minimum_size to compensate
		## (a real regression this fix corrects) collapses the button
		## down to just its icon/stylebox padding, rendering it as an
		## empty box with no visible text at all, exactly like the bug
		## compact mode itself was built to avoid — it just now hit the
		## single-column Characteristics/Talents grids too, which were
		## never meant to shrink their button text in the first place.
		if compact:
			sell_button.tooltip_text = "Sell (+%d XP)" % sell_cost
			sell_button.custom_minimum_size.x = compact_button_min_width
			sell_button.clip_text = true
		sell_button.pressed.connect(on_sell)
		sell_button.visible = Input.is_key_pressed(KEY_SHIFT) and Input.is_key_pressed(KEY_CTRL)
		actions_row.add_child(sell_button)
		_gated_sell_buttons.append(sell_button)
	if on_buy.is_valid():
		var buy_button := Button.new()
		buy_button.text = "%d XP" % cost
		if compact:
			buy_button.tooltip_text = "%d XP" % cost
			buy_button.custom_minimum_size.x = compact_button_min_width
			buy_button.clip_text = true
		buy_button.disabled = character.get_experience_available() < cost
		if parked_reason != "":
			buy_button.disabled = true
			buy_button.tooltip_text = parked_reason
			buy_button.mouse_filter = Control.MOUSE_FILTER_STOP
		buy_button.pressed.connect(on_buy)
		actions_row.add_child(buy_button)
	grid.add_child(_boxed_cell(actions_row, 4, _STAT_GRID_COLUMNS))

## --- Stats tab: Characteristics sub-tab --------------------------------------

func _rebuild_characteristics() -> void:
	_clear(characteristics_box)
	if character == null:
		return
	characteristics_box.add_child(_header("Characteristics"))
	var unlocked := Advancement.unlocked_characteristics(character)

	var grid := GridContainer.new()
	grid.columns = _STAT_GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 2)
	_stat_grid_header_row(grid, "Characteristic")

	for key in CharacteristicSet.KEYS:
		## Per the request: shows the character's actual right-now value
		## (base + whatever's currently modifying it — a Critical Wound
		## penalty, Encumbrance's Agility malus, an active buff/debuff —
		## same effective value everything else in the game already Tests
		## against) rather than the untouched base number, and flags it in
		## red whenever a temporary effect has knocked it below base. A
		## positive-only buff still shows the raised number, just not in
		## red — this is specifically a "you're weaker than your sheet
		## says right now" warning, not a general "something changed" cue.
		var base_value: int = character.characteristics.get_value(key)
		var effective_value: int = character.get_effective_characteristic_value(key)
		var bonus: int = character.get_characteristic_bonus(key)
		var already: int = character.get_characteristic_advance_count(key)
		var is_reduced := effective_value < base_value
		var is_unlocked := unlocked.has(key)
		## Per the request: full characteristic names (not WS/BS/S…
		## abbreviations) in the Characteristics grid itself — the
		## Critical Wound penalty lines below still use SHORT_NAMES since
		## those are a compact single-line summary, not a per-row grid.
		var name_text: String = CharacteristicSet.FULL_NAMES[key]
		var value_text := "%d (%d)" % [effective_value, bonus]
		if is_reduced:
			value_text += "  (base %d — reduced)" % base_value
		var cost := -1
		var sell_cost := -1
		var on_buy := Callable()
		var on_sell := Callable()
		## Per the pre-existing behaviour this grid replaces: Buy/Sell are
		## both only ever offered while the Characteristic is genuinely
		## unlocked at the current Career level — there's no "sell an
		## advance you can no longer train" path for Characteristics the
		## way Skills has one (see the "outside current Career" section of
		## _rebuild_skills below), so this isn't changed here.
		if is_unlocked:
			cost = Advancement.get_characteristic_advance_cost(already, true)
			on_buy = func(): _buy_characteristic(key)
			if already > 0:
				sell_cost = Advancement.get_characteristic_advance_cost(max(already - 1, 0), true)
				on_sell = func(): _sell_characteristic(key)
		_add_stat_grid_row(grid, is_unlocked, name_text, value_text, already, cost, on_buy, sell_cost, on_sell, is_reduced)

	## Per the request: cap the Characteristics grid to 75% of the window
	## width rather than letting it stretch edge-to-edge — wrapped in its
	## own MarginContainer (instead of resizing characteristics_box
	## itself, which would also squeeze the Critical Wounds text below
	## it) so only the grid is width-limited and left-aligned within the
	## remaining space. custom_minimum_size is a floor, not a ceiling, but
	## since this wrap doesn't expand-fill its VBoxContainer parent, it
	## never grows past that floor either — see _on_viewport_resized above
	## for keeping this in sync if the window is resized afterwards.
	_characteristics_grid_wrap = MarginContainer.new()
	_characteristics_grid_wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	## Real bug fix (see _on_viewport_resized): measure against the
	## Character menu window's own width (%Tabs), not the full screen —
	## `tabs` is guaranteed valid here since this only runs while the
	## Character menu itself is open and rebuilding its Stats tab.
	_characteristics_grid_wrap.custom_minimum_size.x = tabs.size.x * 0.75
	_characteristics_grid_wrap.add_child(grid)
	characteristics_box.add_child(_characteristics_grid_wrap)

	## Critical Wounds — currently active count and any still-in-effect
	## penalties. Kept here (rather than a tab of its own) since it's
	## Toughness-derived, same reasoning as the old Stats tab.
	characteristics_box.add_child(_header("Critical Wounds"))
	var cw_summary := Label.new()
	cw_summary.text = "%d currently active (Toughness Bonus: %d — more than this and you risk death when Wounds reach 0)" % [
		character.active_critical_wound_count, character.get_characteristic_bonus("toughness")
	]
	cw_summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	characteristics_box.add_child(cw_summary)
	if not character.critical_wound_penalties.is_empty():
		var pen_header := Label.new()
		pen_header.text = "Active penalties:"
		pen_header.add_theme_font_size_override("font_size", 12)
		pen_header.add_theme_color_override("font_color", Color(0.85, 0.6, 0.55))
		characteristics_box.add_child(pen_header)
		for penalty in character.critical_wound_penalties:
			var pen_row := Label.new()
			var char_key: String = (penalty["characteristic_bonuses"].keys() as Array)[0]
			var amount: int = penalty["characteristic_bonuses"][char_key]
			pen_row.text = "%s: %+d %s (%d day(s) left)" % [penalty["name"], amount, CharacteristicSet.SHORT_NAMES.get(char_key, char_key), penalty["rounds_remaining"]]
			pen_row.add_theme_font_size_override("font_size", 12)
			characteristics_box.add_child(pen_row)

## --- Stats tab: Skills sub-tab ------------------------------------------------
## Per the request: Experience spending now lives directly in the Skills
## list itself, replacing the old read-only "Skill Advances" summary —
## every unlocked Skill shows its current value alongside Buy/Sell.

## Per the request ("on the skill submenu, let split basic and advanced
## skills into separate columns side by side, each using 50% of the
## width"): Basic skills (SkillDefinition.is_advanced == false — "can
## be tested untrained") and Advanced skills each get their own boxed
## grid, side by side in a shared HBoxContainer, both with an equal
## SIZE_EXPAND_FILL stretch ratio so they genuinely split the available
## width 50/50 rather than one crowding out the other.
func _rebuild_skills() -> void:
	_clear(skills_box)
	if character == null:
		return
	skills_box.add_child(_header("Skills"))
	var unlocked_names := Advancement.unlocked_skills(character)

	var columns_row := HBoxContainer.new()
	## Per the follow-up request ("make sure the skill submenu does not
	## scroll sideways, make it less wide if required"): trimmed from 12
	## to 6 — every pixel here is real overflow margin once a long,
	## real-play skill list also needs a vertical scrollbar (see
	## _stat_grid_header_row's own comment on this same fix).
	columns_row.add_theme_constant_override("separation", 6)
	columns_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var make_column := func(title: String) -> GridContainer:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_stretch_ratio = 1.0
		column.add_child(_header(title))
		var column_grid := GridContainer.new()
		column_grid.columns = _STAT_GRID_COLUMNS
		column_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column_grid.add_theme_constant_override("h_separation", 0)
		column_grid.add_theme_constant_override("v_separation", 2)
		_stat_grid_header_row(column_grid, "Skill", "Value", true)
		column.add_child(column_grid)
		columns_row.add_child(column)
		return column_grid

	var basic_grid: GridContainer = make_column.call("Basic")
	var advanced_grid: GridContainer = make_column.call("Advanced")

	## Real bug fix ("never show the same stat twice... this happened
	## because the character entered a new class which also has Melee
	## (Brawling)"): every skill display_name that's going to be shown
	## via a route OTHER than the "(Any)" section below — the current
	## Career listing it directly, or it carrying over from a previous
	## one out of scope. A career change can grant a skill concretely
	## that an earlier "(Any)" slot had already been resolved to (e.g. an
	## older career's "Melee (Any)" picked "Brawling", and the new
	## career's own Tier 1 lists "Melee (Brawling)" directly) — same
	## underlying skill, same shared skill_advances entry either way, so
	## it only needs to be shown once. Computed up front so the "(Any)"
	## section further down can skip re-showing anything already covered
	## here.
	##
	## Real bug fix ("changed career to Pit Fighter, after selecting
	## Melee (Any) -> Basic the skill moved down to the outside current
	## Career section when it shouldn't have"): a resolved variant of one
	## of the CURRENT career's own still-unlocked "(Any)" qualifiers (here,
	## "Melee (Any)" resolved to "Melee (Basic)") never appears literally
	## in unlocked_names itself — only the bare qualifier string
	## ("Melee (Any)") does — so the loop below used to treat it as if it
	## had fallen out of the current career's scope entirely the instant
	## it was bought, moving it straight into the read-only "outside
	## current Career" section instead of staying in the Skills list' own
	## living "(Any)" section where it belongs (still buyable, right where
	## the player just picked it). current_any_resolved collects every
	## such legitimately-current resolved variant up front — from every
	## "(Any)" qualifier the CURRENT career still grants, at every tier —
	## so both this loop and the "outside current Career" loop further
	## down can tell it apart from a genuinely stale skill carried over
	## from a past career (which should still fall through to that
	## section, unchanged from before).
	var current_any_resolved: Dictionary = {}
	for display_name in unlocked_names:
		if Advancement.is_any_qualifier(display_name):
			for chosen in Advancement.find_all_chosen_skill_variants(character, display_name):
				current_any_resolved[chosen] = true

	var concrete_display_names: Dictionary = {}
	for display_name in unlocked_names:
		if not Advancement.is_any_qualifier(display_name):
			concrete_display_names[display_name] = true
	for display_name in character.skill_advances.keys():
		if not unlocked_names.has(display_name) and not current_any_resolved.has(display_name):
			concrete_display_names[display_name] = true

	## Per the follow-up request ("make sure you list skills
	## alphabetically in both columns"): every row/row-group below is
	## queued here as {sort_key, build} instead of being added to a
	## grid immediately, since the three source loops (concrete
	## unlocked skills, "(Any)" qualifiers, outside-Career skills) each
	## iterate in their own unrelated order. Once every entry destined
	## for a given column is known, that column's own list is sorted by
	## sort_key (the display name, so e.g. "Melee (Any)" and "Melee
	## (Brawling)" sort together) and only THEN actually built —
	## keeping each column alphabetical regardless of which of the
	## three sources a row came from.
	var basic_entries: Array = []
	var advanced_entries: Array = []
	var queue_row := func(display_name: String, skill_def: SkillDefinition, build: Callable) -> void:
		var entry := {"sort_key": display_name, "build": build}
		if skill_def != null and skill_def.is_advanced:
			advanced_entries.append(entry)
		else:
			basic_entries.append(entry)

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
		var sell_cost := Advancement.get_skill_advance_cost(max(already - 1, 0)) if already > 0 else -1
		queue_row.call(display_name, skill_def, func(target_grid: GridContainer):
			_add_stat_grid_row(target_grid, true, display_name, "%d" % current, already,
				cost, func(): _buy_skill(skill_def, specialisation), sell_cost, func(): _sell_skill(skill_def, specialisation),
				false, "", true))
	for display_name in any_skill_counts.keys():
		var parsed_any := _parse_skill_display_name(display_name)
		var any_skill_def: SkillDefinition = parsed_any[0]
		var slot_count: int = any_skill_counts[display_name]
		queue_row.call(display_name, any_skill_def, func(target_grid: GridContainer):
			_add_any_skill_grid_rows(target_grid, display_name, slot_count, concrete_display_names))

	## Skill advances purchased outside the character's CURRENT Career
	## scope (typically carried over from a previous Career after a
	## Change Career) still show here too, read-only aside from Sell —
	## the book has no "buy more of a non-Career skill" flow from this
	## screen once it's out of scope, but a past purchase shouldn't
	## just disappear from view. A resolved variant of one of the
	## CURRENT career's own "(Any)" qualifiers (current_any_resolved,
	## built above) is excluded here too — it's still in scope, just
	## shown via the "(Any)" section instead, not this read-only one.
	for display_name in character.skill_advances.keys():
		if unlocked_names.has(display_name) or current_any_resolved.has(display_name):
			continue
		var parsed2 := _parse_skill_display_name(display_name)
		var skill_def2: SkillDefinition = parsed2[0]
		var specialisation2: String = parsed2[1]
		if skill_def2 == null:
			continue
		var current2 := character.get_skill_value(skill_def2, specialisation2)
		var already2: int = character.skill_advances[display_name]
		var sell_cost2 := Advancement.get_skill_advance_cost(max(already2 - 1, 0))
		queue_row.call(display_name, skill_def2, func(target_grid: GridContainer):
			_add_stat_grid_row(target_grid, false, display_name, "%d" % current2, already2,
				-1, Callable(), sell_cost2, func(): _sell_skill(skill_def2, specialisation2), false,
				"Outside your current Career — advances kept, but you can't train it further until it's back in your Career", true))

	var by_sort_key := func(a: Dictionary, b: Dictionary) -> bool:
		return (a["sort_key"] as String).naturalnocasecmp_to(b["sort_key"] as String) < 0
	basic_entries.sort_custom(by_sort_key)
	advanced_entries.sort_custom(by_sort_key)
	for entry in basic_entries:
		(entry["build"] as Callable).call(basic_grid)
	for entry in advanced_entries:
		(entry["build"] as Callable).call(advanced_grid)

	skills_box.add_child(columns_row)

## --- Stats tab: Talents sub-tab -----------------------------------------------

## Per the follow-up request ("lets move to the talents tab, and apply the
## same stats grid format again"): Talents now renders through the same
## boxed 4-column GridContainer (_add_stat_grid_row/_boxed_cell) as the
## Characteristics and Skills sub-tabs, replacing the old one-
## HBoxContainer-per-row _add_xp_row layout and the even older bare
## RichTextLabel bullet rows the "outside current Career" section used.
## Unlike Skills, Talents has no natural Basic/Advanced split, so this
## stays a single full-width grid, matching Characteristics' own layout
## rather than Skills' two-column one.
func _rebuild_talents() -> void:
	_clear(talents_box)
	if character == null:
		return
	talents_box.add_child(_header("Talents"))

	var grid := GridContainer.new()
	grid.columns = _STAT_GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 2)
	_stat_grid_header_row(grid, "Talent", "Rank")

	for talent_name in Advancement.unlocked_talents(character):
		if Advancement.is_any_qualifier(talent_name):
			_add_any_talent_grid_row(grid, talent_name)
			continue
		var td: TalentDefinition = GameData.talent_db.find_by_name(talent_name)
		if td == null:
			continue
		var rank := character.get_talent_rank(talent_name)
		var max_rank := td.get_max_rank(character)
		## Per the original request this row style itself came from: the
		## row shows name + rank, with the full rules description moved
		## into a hover tooltip (see the tooltip_text param below) rather
		## than crammed into the visible label text.
		var value_text := "rank %d / %d" % [rank, max_rank]
		var sell_cost := Advancement.get_talent_advance_cost(max(rank - 1, 0)) if rank > 0 else -1
		if rank >= max_rank:
			_add_stat_grid_row(grid, true, talent_name, value_text, rank, -1, Callable(), sell_cost,
				func(): _sell_talent(talent_name), false, td.summary)
		else:
			var cost := Advancement.get_talent_advance_cost(rank)
			var parked_reason := td.parked_reason if td.mechanically_parked else ""
			_add_stat_grid_row(grid, true, talent_name, value_text, rank, cost, func(): _buy_talent(talent_name), sell_cost,
				func(): _sell_talent(talent_name), false, td.summary, false, parked_reason)

	## Talents already taken but no longer offered at the current tier
	## (from a previous Career, or an earlier tier of this one) — shown
	## read-only aside from Sell, same reasoning as Skills' own "outside
	## current Career" section.
	var unlocked_names := Advancement.unlocked_talents(character)
	for talent_name in character.talents_taken.keys():
		if unlocked_names.has(talent_name):
			continue
		var already_shown := false
		for u in unlocked_names:
			if Advancement.is_any_qualifier(u) and Advancement.find_chosen_variant(character, u) == talent_name:
				already_shown = true
				break
		if already_shown:
			continue
		var td2: TalentDefinition = GameData.talent_db.find_by_name(talent_name)
		var rank2: int = character.talents_taken[talent_name]
		var max_rank2 := td2.get_max_rank(character) if td2 != null else rank2
		var sell_cost2 := Advancement.get_talent_advance_cost(max(rank2 - 1, 0))
		var tooltip2 := "Outside your current Career — kept, but not further trainable until it's back in your Career."
		if td2 != null:
			tooltip2 = td2.summary + "\n\n" + tooltip2
		_add_stat_grid_row(grid, false, talent_name, "rank %d / %d" % [rank2, max_rank2], rank2,
			-1, Callable(), sell_cost2, func(): _sell_talent(talent_name), false, tooltip2)

	talents_box.add_child(grid)

## --- Inventory tab ---------------------------------------------------------

## Per the request: destroys one item at a time from a stack, rather
## than the whole stack at once — Array.erase() only removes the
## FIRST matching entry, which is exactly that. If this was the last
## copy of something currently equipped, it's also unequipped cleanly
## rather than leaving equipped_weapon/equipped_armour pointing at an
## item the character no longer actually carries.
func _on_drop_item(item_name: String) -> void:
	if character == null:
		return
	character.inventory.erase(item_name)
	if not character.inventory.has(item_name):
		## Per the follow-up request: a light source now shares these
		## same two hand slots rather than its own — dropping the last
		## copy of whatever's currently lit also turns it off, so
		## light_mode doesn't stay "on" pointing at nothing. Checked
		## before either slot is cleared below, since
		## get_equipped_light_item() only resolves while the name is
		## still actually sitting in one of them.
		var dropped_light := character.get_equipped_light_item()
		if dropped_light != null and dropped_light.item_name == item_name:
			character.light_mode = "off"
		if character.equipped_weapon == item_name:
			character.equipped_weapon = ""
		## Per the bug report: this was only ever clearing equipped_weapon
		## (main hand) — equipped_offhand held onto the same item name
		## forever once the last physical copy was gone, so it kept
		## showing as equipped even though it no longer existed anywhere.
		if character.equipped_offhand == item_name:
			character.equipped_offhand = ""
		character.equipped_armour.erase(item_name)
		## Per the "packs and containers" request: same "last copy gone
		## -> unequip" treatment as every other equip slot above.
		for slot in ["Back", "Waist", "Shoulder"]:
			if character.get_equipped_container(slot) == item_name:
				character.set_equipped_container(slot, "")
	_rebuild_all()

## Per the request: sends one copy of an item from the currently-
## viewed character's own inventory to a chosen other party member —
## removes it from the sender the same way Drop does (unequipping if
## it was their last copy of something worn/wielded), and adds it
## directly to the recipient's own inventory.
func _on_send_item(item_name: String, recipient: Character) -> void:
	if character == null or recipient == null or recipient == character:
		return
	character.inventory.erase(item_name)
	if not character.inventory.has(item_name):
		var sent_light := character.get_equipped_light_item()
		if sent_light != null and sent_light.item_name == item_name:
			character.light_mode = "off"
		if character.equipped_weapon == item_name:
			character.equipped_weapon = ""
		if character.equipped_offhand == item_name:
			character.equipped_offhand = ""
		character.equipped_armour.erase(item_name)
		for slot in ["Back", "Waist", "Shoulder"]:
			if character.get_equipped_container(slot) == item_name:
				character.set_equipped_container(slot, "")
	recipient.inventory.append(item_name)
	_rebuild_all()

## Opens a real popup listing every other present party member, per
## the request — chosen from the same button the Drop button sits
## next to. A party of just 1 has no one to send to, so the caller
## simply doesn't show the button in that case.
func _open_send_menu(item_name: String, anchor_button: Button) -> void:
	var menu := PopupMenu.new()
	add_child(menu)
	var recipients: Array[Character] = []
	for member in GameState.party:
		if member != character:
			menu.add_item(member.character_name)
			recipients.append(member)
	menu.id_pressed.connect(func(id: int): _on_send_item(item_name, recipients[id]))
	menu.popup_hide.connect(func(): menu.queue_free())
	var pos: Vector2 = anchor_button.global_position + Vector2(0, anchor_button.size.y)
	menu.popup(Rect2i(Vector2i(pos), Vector2i(160, 0)))

## Per the request: item Encumbrance shown per-row is the item's own
## real rating (with the standard Worn Items -1 discount if it's
## currently equipped as Armour) — not necessarily what
## Character.get_current_encumbrance() currently counts toward the
## header/breakdown total, since that function only ever counts
## EQUIPPED weapons/armour plus item_db-registered Trappings (a
## pre-existing gap, not something this request asked to fix). A
## spare, unequipped sword still shows its own real Enc rating here —
## that's what the number printed on the item actually is.
func _item_row_encumbrance(item_name: String) -> float:
	var w: WeaponDefinition = GameData.weapon_db.find_by_name(item_name)
	if w != null:
		return w.encumbrance
	var a: ArmourDefinition = GameData.armour_db.find_by_name(item_name)
	if a != null:
		return max(0, a.encumbrance - 1) if character.equipped_armour.has(item_name) else a.encumbrance
	if GameData.item_db != null:
		var it: ItemDefinition = GameData.item_db.find_by_name(item_name)
		if it != null:
			## Per the "packs and containers" request: the same Worn
			## Items -1 discount armour gets above, shown here whenever
			## THIS item is the one actually worn in its own container
			## slot — matching Character.get_current_encumbrance()'s own
			## worn-copy treatment, not just "any item with this name is
			## worn somewhere" (a spare, unequipped second copy still
			## shows its full, undiscounted Enc).
			if it.container_slot != "" and character.get_equipped_container(it.container_slot) == item_name:
				return max(0, it.encumbrance - 1)
			return it.encumbrance
	return 0.0

## Per the request: "add a grid layout to the list and clearly list
## Item name..., quantity and Enc values in neat columns with header
## titles above columns" — a real GridContainer (5 columns: Star / Item
## / Qty / Enc / Actions) so column widths are computed from EVERY
## row's content at once, the same way a spreadsheet would, rather than
## fixed guessed widths that drift out of alignment once one row's
## Actions cell happens to hold more buttons than another's (that was
## tried first and didn't actually stay aligned — a wider Actions cell
## on one row ate into how much space that row's own Name column had
## left to expand into, shifting Qty/Enc sideways relative to every
## other row).
const _INV_GRID_COLUMNS := 5

## Per the request: "surround each item line and its buttons in a
## faint box so the lines are clearer" — every cell in a row shares the
## same subtle background tint and a border on just the top/bottom
## edges (never left/right), so five adjacent GridContainer cells read
## as one continuous boxed line with no doubled-up vertical seams
## between columns. The two actual edge cells (Star on the left,
## Actions on the right) also get a matching left/right border so the
## row reads as a real enclosed box, not just top/bottom rules.
static func _faint_row_style(is_left_edge: bool, is_right_edge: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.025)
	style.border_color = Color(0.6, 0.55, 0.45, 0.35)
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1 if is_left_edge else 0
	style.border_width_right = 1 if is_right_edge else 0
	if is_left_edge:
		style.corner_radius_top_left = 3
		style.corner_radius_bottom_left = 3
	if is_right_edge:
		style.corner_radius_top_right = 3
		style.corner_radius_bottom_right = 3
	style.set_content_margin_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	return style

## Wraps `control` as one boxed grid cell — `column` says which of the
## grid's own `total_columns` it is, so the edge cells (first/last) get
## the enclosing left/right border and the middle ones don't.
## `total_columns` defaults to the Inventory grid's own 5 so every
## existing Inventory call site (which never passes it) keeps behaving
## exactly as before. Per the follow-up request ("copy the grid format
## in Inventory tab to Characteristics and Skill subtabs"): the shared
## Characteristics/Skills grid (see _add_stat_grid_row below) instead
## passes its own `total_columns=4` and, for its wider middle column,
## `expand=true` so that column actually soaks up the grid's spare
## width — the Inventory grid never sets this and simply leaves any
## spare width as blank space to the right (verified with a real
## runtime measurement, not assumed), which is fine for Inventory's
## already-wide Item column but would leave the Characteristics/Skills
## grid's much shorter Characteristic/Skill column looking cramped.
static func _boxed_cell(control: Control, column: int, total_columns: int = _INV_GRID_COLUMNS, expand: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _faint_row_style(column == 0, column == total_columns - 1))
	if expand:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(control)
	return panel

## The header row's own cells aren't boxed (see the comment where
## they're built), but still need the SAME left/right padding the
## boxed item-row cells get from their PanelContainer's content_margin
## — otherwise, with the grid's h_separation at 0 (needed so adjacent
## item-row cells touch and read as one continuous box), the header
## labels would run straight into each other ("QtyEncActions") with no
## visible gap at all. `expand` mirrors _boxed_cell's own — see there.
static func _header_cell(control: Control, expand: bool = false) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	if expand:
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(control)
	return margin

func _rebuild_inventory() -> void:
	_clear(inventory_box)
	if character == null:
		return
	inventory_box.add_child(_header("Carried Items"))
	if character.inventory.is_empty():
		inventory_box.add_child(Label.new())
	else:
		var counts: Dictionary = {}
		var order: Array[String] = []
		for item_name in character.inventory:
			if not counts.has(item_name):
				order.append(item_name)
			counts[item_name] = counts.get(item_name, 0) + 1

		var grid := GridContainer.new()
		grid.columns = _INV_GRID_COLUMNS
		grid.add_theme_constant_override("h_separation", 0)
		grid.add_theme_constant_override("v_separation", 2)

		## Per the request: "header titles above columns" — plain,
		## unboxed labels as the grid's own first row, so they share
		## the exact same computed column widths as every item row
		## below (a separate HBoxContainer header wouldn't necessarily
		## line up with a GridContainer's own auto-sized columns).
		var star_header := Label.new()
		grid.add_child(_header_cell(star_header))
		var name_header := Label.new()
		name_header.text = "Item"
		name_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_header.add_theme_font_size_override("font_size", 12)
		name_header.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
		## Per the request: the Item column was wrapping onto two lines —
		## the comment above _boxed_cell assumed this column was "already
		## wide enough" without `expand`, but real item names (with the
		## weapon-skill-group suffix appended) run wider than that, so it
		## now opts into `expand` just like the Characteristics/Skills
		## grid's own wide column does, leaving Qty/Enc/Actions narrow.
		grid.add_child(_header_cell(name_header, true))
		var qty_header := Label.new()
		qty_header.text = "Qty"
		qty_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty_header.add_theme_font_size_override("font_size", 12)
		qty_header.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
		grid.add_child(_header_cell(qty_header))
		var enc_header := Label.new()
		enc_header.text = "Enc"
		enc_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		enc_header.add_theme_font_size_override("font_size", 12)
		enc_header.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
		grid.add_child(_header_cell(enc_header))
		var actions_header := Label.new()
		actions_header.text = "Actions"
		actions_header.add_theme_font_size_override("font_size", 12)
		actions_header.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
		grid.add_child(_header_cell(actions_header))

		for item_name in order:
			## Per the request: a star icon per item — click to favourite,
			## which protects it from being sold in the Shop's sell list
			## (see Character.favourite_items and shop_screen.gd's own
			## _add_sell_grid_row, which has its own matching Star button
			## reading/writing this same field) without touching equip
			## state at all.
			var is_favourite: bool = character.favourite_items.has(item_name)
			var star_btn := Button.new()
			star_btn.text = "★" if is_favourite else "☆"
			star_btn.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35) if is_favourite else Color(0.55, 0.5, 0.42))
			star_btn.tooltip_text = "Favourited — protected from being sold (click to un-favourite)" if is_favourite else "Favourite this item (protects it from being sold)"
			star_btn.pressed.connect(func():
				if character.favourite_items.has(item_name):
					character.favourite_items.erase(item_name)
				else:
					character.favourite_items.append(item_name)
				_rebuild_inventory()
			)
			grid.add_child(_boxed_cell(star_btn, 0))

			## Per the request: equip/unequip is now available directly
			## from the Inventory tab too, not just the Equipment tab —
			## reuses the exact same helpers/logic so behavior (and
			## conflict/two-handed disabling) matches everywhere.
			var inv_weapon: WeaponDefinition = GameData.weapon_db.find_by_name(item_name)
			var inv_armour: ArmourDefinition = GameData.armour_db.find_by_name(item_name)
			## Per the follow-up request ("lantern need to be held on
			## either main or off hand, remove the extra lantern slot"):
			## a light source (Lantern, Storm Lantern, Candle (dozen),
			## Davrich Lamp) is held exactly like a weapon — it occupies
			## equipped_weapon/equipped_offhand, not a separate slot. See
			## _light_equip_buttons() below, which mirrors
			## _weapon_equip_buttons() for these two shared hand slots.
			var inv_light: ItemDefinition = GameData.item_db.find_by_name(item_name) if GameData.item_db != null else null
			if inv_light != null and inv_light.light_radius_tiles <= 0:
				inv_light = null
			## Per the "packs and containers" request: a wearable
			## Container (Backpack/Pouch/Sling Bag — Saddlebags has no
			## container_slot at all, per the request's own 3-slot
			## scope, so it never matches here and just stays a plain
			## Trapping) gets its own Equip/Unequip actions below,
			## mirroring the weapon/armour/light branches exactly.
			var inv_container: ItemDefinition = GameData.item_db.find_by_name(item_name) if GameData.item_db != null else null
			if inv_container != null and inv_container.container_slot == "":
				inv_container = null

			## Per the request: "add skill type for Weapons and colour
			## red if unlearned" — the Skill (Melee/Ranged) plus
			## specialisation this weapon actually rolls against, shown
			## next to its name; red whenever the character has never
			## actually trained that specific specialisation (checked
			## against skill_advances directly, not has_skill() — Melee
			## itself is usable fully untrained per the book, but this
			## is flagging "no real training in THIS weapon group",
			## which skill_advances' own presence/absence answers
			## directly regardless of whether the parent skill is Basic
			## or Advanced).
			var name_label := Label.new()
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			var qty_text := (" x%d" % counts[item_name]) if counts[item_name] > 1 else ""
			if inv_weapon != null:
				var weapon_skill: SkillDefinition = GameData.skill_db.find_by_name("Ranged" if inv_weapon.is_ranged else "Melee")
				var specialisation_display := weapon_skill.display_name(inv_weapon.skill_group) if weapon_skill != null else inv_weapon.skill_group
				var is_learned: bool = weapon_skill != null and character.skill_advances.has(specialisation_display)
				name_label.text = "• %s (%s)%s" % [item_name, inv_weapon.skill_group, qty_text]
				## Per the request ("show damaged items, mark them red and
				## reduce dmg/ap on the appropriate location"): the
				## Inventory tab has no dedicated Damage column of its own
				## (unlike the Equipment tab's Weapons sub-tab — see
				## _add_weapon_grid_row), so a wear-damaged weapon's
				## already-reduced figure (get_weapon_damage() nets wear
				## out automatically) is surfaced inline here instead,
				## with the same red flag used everywhere else damage is
				## shown.
				var wear: int = int(character.weapon_damage_taken.get(item_name, 0))
				if wear > 0:
					name_label.text += " [Dmg %d/%d]" % [inv_weapon.get_weapon_damage(character), inv_weapon.damage_flat]
					name_label.add_theme_color_override("font_color", Color(0.82, 0.35, 0.32))
					name_label.tooltip_text = "-%d Damage from wear — repair at the shop." % wear
				elif not is_learned:
					name_label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
			elif inv_armour != null:
				name_label.text = "• %s%s" % [item_name, qty_text]
				## Same treatment as the weapon branch above, at the
				## specific location(s) actually damaged — armour damage
				## is tracked per location (see Character.armour_damage),
				## so more than one may need listing for a single piece.
				var total_dmg: int = character.get_total_armour_damage(item_name)
				if total_dmg > 0:
					var breakdown: Array[String] = []
					for loc in inv_armour.locations:
						var loc_dmg: int = character.get_armour_damage_at(item_name, loc)
						if loc_dmg > 0:
							breakdown.append("%s %d/%d" % [loc, max(0, inv_armour.armour_points - loc_dmg), inv_armour.armour_points])
					name_label.text += " [%s]" % ", ".join(breakdown)
					name_label.add_theme_color_override("font_color", Color(0.82, 0.35, 0.32))
					name_label.tooltip_text = "Damaged — repair at the shop."
			else:
				name_label.text = "• %s%s" % [item_name, qty_text]
			## expand=true so this cell actually claims the extra width
			## the header cell above now also claims (see _header_cell
			## call above) — without it the name still wraps regardless
			## of how wide the header row is, since each row's own cell
			## sizing is what GridContainer actually measures per column.
			grid.add_child(_boxed_cell(name_label, 1, _INV_GRID_COLUMNS, true))

			var qty_label := Label.new()
			qty_label.text = str(counts[item_name])
			qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(_boxed_cell(qty_label, 2))

			var enc_label := Label.new()
			var per_item_enc := _item_row_encumbrance(item_name)
			var total_row_enc: float = per_item_enc * int(counts[item_name])
			enc_label.text = str(roundi(total_row_enc)) if is_equal_approx(total_row_enc, roundi(total_row_enc)) else "%.1f" % total_row_enc
			enc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(_boxed_cell(enc_label, 3))

			var actions_row := HBoxContainer.new()
			actions_row.add_theme_constant_override("separation", 6)
			## Per the follow-up request ("rename Equip (Main) to Eqp
			## (Main)... follow the same logic for all other
			## Equip/Unequip buttons in this tab"): the Inventory tab's
			## own buttons use the short Eqp/Unqp form — the Equipment
			## tab's own Weapons/Armor/Containers sub-tabs (which call
			## these same shared helpers with their own inline Unequip
			## buttons) are untouched, so `short` defaults to false
			## there and only this tab opts in.
			if inv_weapon != null:
				if item_name == character.equipped_weapon:
					var unequip_main_btn := Button.new()
					unequip_main_btn.text = "Unqp (Main)"
					unequip_main_btn.pressed.connect(func():
						character.equipped_weapon = ""
						_rebuild_all()
					)
					actions_row.add_child(unequip_main_btn)
				if item_name == character.equipped_offhand:
					var unequip_off_btn2 := Button.new()
					unequip_off_btn2.text = "Unqp (Off)"
					unequip_off_btn2.pressed.connect(func():
						character.equipped_offhand = ""
						_rebuild_all()
					)
					actions_row.add_child(unequip_off_btn2)
				for btn in _weapon_equip_buttons(item_name, inv_weapon, counts, true):
					actions_row.add_child(btn)
			elif inv_armour != null:
				if character.equipped_armour.has(item_name):
					var unequip_armour_btn := Button.new()
					unequip_armour_btn.text = "Unqp"
					unequip_armour_btn.pressed.connect(func():
						character.equipped_armour.erase(item_name)
						_rebuild_all()
					)
					actions_row.add_child(unequip_armour_btn)
				else:
					actions_row.add_child(_armour_equip_button(item_name, true))
			elif inv_light != null:
				if item_name == character.equipped_weapon:
					var unequip_light_main_btn := Button.new()
					unequip_light_main_btn.text = "Unqp (Main)"
					unequip_light_main_btn.pressed.connect(func():
						character.equipped_weapon = ""
						_rebuild_all()
					)
					actions_row.add_child(unequip_light_main_btn)
				if item_name == character.equipped_offhand:
					var unequip_light_off_btn := Button.new()
					unequip_light_off_btn.text = "Unqp (Off)"
					unequip_light_off_btn.pressed.connect(func():
						character.equipped_offhand = ""
						_rebuild_all()
					)
					actions_row.add_child(unequip_light_off_btn)
				for btn in _light_equip_buttons(item_name, counts, true):
					actions_row.add_child(btn)
			elif inv_container != null:
				if character.get_equipped_container(inv_container.container_slot) == item_name:
					var unequip_container_btn := Button.new()
					unequip_container_btn.text = "Unqp"
					unequip_container_btn.pressed.connect(func():
						character.set_equipped_container(inv_container.container_slot, "")
						_rebuild_all()
					)
					actions_row.add_child(unequip_container_btn)
				else:
					actions_row.add_child(_container_equip_button(item_name, inv_container, true))
			var drop_btn := Button.new()
			drop_btn.text = "Drop"
			## Per the request: favouriting an item already protects it
			## from being sold in the Shop to guard against selling it by
			## accident — dropping it is just as permanent, so it gets
			## the same guard: the Drop button is disabled outright
			## while the item is favourited, rather than only warning
			## after the fact. Un-favouriting (the star toggle above)
			## re-enables it immediately, same as any other disabled
			## state in this screen.
			drop_btn.disabled = is_favourite
			drop_btn.tooltip_text = "Un-favourite this item first to drop it" if is_favourite else ""
			drop_btn.pressed.connect(func(): _on_drop_item(item_name))
			actions_row.add_child(drop_btn)
			## Per the request: a Send button right next to Drop —
			## only shown when there's actually someone else present
			## to send an item to.
			if GameState.party.size() > 1:
				var send_btn := Button.new()
				send_btn.text = "Send"
				send_btn.pressed.connect(func(): _open_send_menu(item_name, send_btn))
				actions_row.add_child(send_btn)
			grid.add_child(_boxed_cell(actions_row, 4))

		inventory_box.add_child(grid)

	inventory_box.add_child(_header("Coin (shared by the whole party)"))
	var coin := Label.new()
	coin.text = "%d GC   %d SS   %d BP" % [character.gold_crowns, character.silver_shillings, character.brass_pennies]
	inventory_box.add_child(coin)

	## Encumbrance (p.293) — shown for visibility even though most
	## Movement/Agility penalties aren't yet applied anywhere in play
	## (see the README). Per the request, coin weight is tracked
	## precisely as a fraction internally (0.005 Enc per physical
	## coin) but rounded for display here — roundi(), not truncation,
	## so e.g. 3.7 Enc genuinely displays as 4, not 3.
	inventory_box.add_child(_header("Encumbrance"))
	var enc := Label.new()
	var current := character.get_current_encumbrance()
	var capacity := character.get_carrying_capacity()
	var penalty := character.get_encumbrance_penalty()
	enc.text = "%d / %d  (%s)" % [roundi(current), capacity, penalty["tier"]]
	enc.add_theme_color_override("font_color", Color(0.85, 0.55, 0.5) if penalty["tier"] != "None" else Color(0.6, 0.8, 0.55))
	inventory_box.add_child(enc)

	## Per the request: broken down by where it's actually coming from,
	## not just the single total above. Category order is fixed
	## (Weapons, Armour, Carried Items, Coin) rather than dictionary
	## iteration order, so it reads the same way every time regardless
	## of which categories happen to be present. A category whose own
	## rounded value is 0 (e.g. a handful of coins, genuinely
	## negligible at 0.005 Enc each) is skipped entirely here — showing
	## "Coin: 0" would just be confusing next to the whole-number rows
	## above it.
	var breakdown: Dictionary = character.get_encumbrance_breakdown()
	if not breakdown.is_empty():
		var breakdown_order := ["Weapons", "Armour", "Containers", "Carried Items", "Coin"]
		for category in breakdown_order:
			if not breakdown.has(category):
				continue
			var rounded_value: int = roundi(breakdown[category])
			if rounded_value <= 0:
				continue
			var cat_label := Label.new()
			cat_label.text = "   %s: %d" % [category, rounded_value]
			cat_label.add_theme_font_size_override("font_size", 12)
			cat_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
			inventory_box.add_child(cat_label)

## Per the request ("apply a similar grid format to [Weapons/Armor/
## Containers], ... add a column for qualities and flaws for Armor and
## Weapons"): shared grid-column constants and helpers for the three
## Equipment sub-tabs, following the exact same "one shared boxed
## GridContainer, spreadsheet-style" convention as _INV_GRID_COLUMNS/
## _boxed_cell/_header_cell above (see their own comments) and the
## Characteristics/Skills grid further up. Column counts differ per
## sub-tab since each shows different data, but all three reuse the
## same _boxed_cell/_header_cell machinery.
const _WEAPON_GRID_COLUMNS := 6
const _ARMOUR_GRID_COLUMNS := 5
const _CONTAINER_GRID_COLUMNS := 4

## Canonical armour-location order for the Worn Armour section's own
## grouping (per the request: "Re-order the grouping in Worn Armor
## section from Light/Medium/Heavy, to Head/Body/Left Arm/Right
## Arm/Left Leg/Right Leg") — matches the same order Character itself
## already iterates armour locations in elsewhere.
const _ARMOUR_LOCATION_ORDER: Array[String] = ["Head", "Body", "Left Arm", "Right Arm", "Left Leg", "Right Leg"]

## --- Weapons grid: Slot / Name / Skill / Damage / Qualities and Flaws / Actions

static func _weapon_grid_header_row(grid: GridContainer) -> void:
	var titles := ["Slot", "Name", "Skill", "Damage", "Qualities and Flaws", "Actions"]
	var aligns := [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_LEFT,
		HORIZONTAL_ALIGNMENT_RIGHT, HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_LEFT]
	var expand_cols := [1, 4]
	for i in range(titles.size()):
		var lbl := Label.new()
		lbl.text = titles[i]
		lbl.horizontal_alignment = aligns[i]
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
		grid.add_child(_header_cell(lbl, expand_cols.has(i)))

## Builds one row for either the Equipped Weapons grid (slot_text =
## "Main Hand"/"Off-Hand", weapon may be null for an empty slot) or the
## Equip From Inventory grid (slot_text = "", weapon always non-null,
## placeholder_text doubles as the item's own name there, name_suffix
## carries the " xN" quantity tag). Needs `character` for the Skill
## column's is-learned check and the Damage column's real computed
## value (get_weapon_damage() already folds in Strength Bonus and
## wear), so — unlike the header-row/section-row builders above — this
## can't be static.
## Per the follow-up request ("all Lantern types should be visible in
## the Weapons Sub tab, and equipable to main/off hand"): a light
## source (Lantern, Storm Lantern, Candle (dozen), Davrich Lamp) is
## already held in the exact same equipped_weapon/equipped_offhand
## hand slots as a real weapon (see character.gd's own
## get_equipped_light_item()/_light_equip_buttons() above) — but this
## grid used to only ever know how to render a WeaponDefinition, so an
## equipped Lantern showed as "(unarmed)"/"(empty)" here even while
## genuinely equipped. The optional `light_item` param renders a light
## source's own Name/Qualities in place of a weapon's, with "-" for
## the Skill/Damage columns a light source has no equivalent of.
func _add_weapon_grid_row(grid: GridContainer, slot_text: String, weapon: WeaponDefinition, placeholder_text: String, tooltip_extra: String, actions: Array, name_suffix: String = "", light_item: ItemDefinition = null) -> void:
	var slot_label := Label.new()
	slot_label.text = slot_text
	grid.add_child(_boxed_cell(slot_label, 0, _WEAPON_GRID_COLUMNS))

	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	if weapon:
		name_label.text = weapon.weapon_name + name_suffix
		if tooltip_extra != "":
			name_label.tooltip_text = tooltip_extra
	elif light_item:
		name_label.text = light_item.item_name + name_suffix
		name_label.tooltip_text = light_item.summary
	else:
		name_label.text = placeholder_text
	grid.add_child(_boxed_cell(name_label, 1, _WEAPON_GRID_COLUMNS, true))

	var skill_label := Label.new()
	if weapon:
		var weapon_skill: SkillDefinition = GameData.skill_db.find_by_name("Ranged" if weapon.is_ranged else "Melee")
		var specialisation_display := weapon_skill.display_name(weapon.skill_group) if weapon_skill != null else weapon.skill_group
		var is_learned: bool = weapon_skill != null and character.skill_advances.has(specialisation_display)
		skill_label.text = weapon.skill_group
		if not is_learned:
			skill_label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
	else:
		## A light source has no Weapon Group/Skill of its own — same
		## "-" placeholder the empty-slot case already used.
		skill_label.text = "-"
	grid.add_child(_boxed_cell(skill_label, 2, _WEAPON_GRID_COLUMNS))

	var dmg_label := Label.new()
	dmg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dmg_label.text = str(weapon.get_weapon_damage(character)) if weapon else "-"
	## Per the request ("show damaged items, mark them red and reduce
	## dmg/ap on the appropriate location"): get_weapon_damage() above
	## already nets wear damage out of the flat rating (see
	## WeaponDefinition.get_weapon_damage), so the figure shown was
	## already reduced — this just adds the red "needs attention" flag
	## itself, same treatment the Shop's own Repair tab uses.
	if weapon and character and int(character.weapon_damage_taken.get(weapon.weapon_name, 0)) > 0:
		dmg_label.add_theme_color_override("font_color", Color(0.82, 0.35, 0.32))
		name_label.add_theme_color_override("font_color", Color(0.82, 0.35, 0.32))
	grid.add_child(_boxed_cell(dmg_label, 3, _WEAPON_GRID_COLUMNS))

	var qual_label := Label.new()
	qual_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qual_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	## item_qualities/item_flaws (Fine, Durable, Lightweight, Practical /
	## Ugly, Shoddy — see ItemQualityRules) are a separate system from
	## the combat `qualities` above and shown alongside it, per the
	## request ("Weapons/Armor Qualities, live side by side with these
	## Item Qualities").
	if weapon and (not weapon.qualities.is_empty() or not weapon.item_qualities.is_empty() or not weapon.item_flaws.is_empty()):
		qual_label.text = ItemQualityRules.combined_display(weapon.qualities, weapon.item_qualities, weapon.item_flaws)
	elif light_item:
		## The Qualities and Flaws column has nothing of its own to show
		## for a light source — its own item summary ("Provides
		## illumination for 20 yards") is far more useful here than a
		## bare "-" would be.
		qual_label.text = light_item.summary
	else:
		qual_label.text = "-"
	grid.add_child(_boxed_cell(qual_label, 4, _WEAPON_GRID_COLUMNS, true))

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 6)
	for btn in actions:
		actions_row.add_child(btn)
	grid.add_child(_boxed_cell(actions_row, 5, _WEAPON_GRID_COLUMNS))

## --- Armour grid: Location / Name / AP / Qualities and Flaws / Actions

static func _armour_grid_header_row(grid: GridContainer) -> void:
	var titles := ["Location", "Name", "AP", "Qualities and Flaws", "Actions"]
	var aligns := [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER,
		HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_LEFT]
	var expand_cols := [1, 3]
	for i in range(titles.size()):
		var lbl := Label.new()
		lbl.text = titles[i]
		lbl.horizontal_alignment = aligns[i]
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
		grid.add_child(_header_cell(lbl, expand_cols.has(i)))

## Per the follow-up request ("hide the grouping names (red lines), and
## change the locations column to display only the grouping location"):
## the red per-location _equipment_section_row headers are gone, so the
## Location column is now the only thing telling the player which
## location a Worn Armour row is grouped under — the caller passes the
## single loop location in as `section_location` for that list. Equip
## From Inventory has no such grouping (it's one flat alphabetical
## list, per the comment where it's built), so it leaves
## `section_location` empty and falls back to the old shop_screen.gd-
## style full joined list, same as before.
##
## Location is left un-expanded (unlike Name/Qualities below) so
## GridContainer sizes it to its own shortest-possible content — now
## a single location word instead of a comma-joined list — and the
## qual_label column's higher stretch ratio (see below) claims most of
## the width that frees up, per the request's own "add the freed up
## space to the Qualities column" ask.
static func _add_armour_grid_row(grid: GridContainer, ad: ArmourDefinition, item_name: String, name_suffix: String, actions: Array, section_location: String = "", owner: Character = null) -> void:
	var loc_label := Label.new()
	if section_location != "":
		loc_label.text = section_location
	else:
		loc_label.text = ", ".join(ad.locations) if ad and not ad.locations.is_empty() else "-"
	grid.add_child(_boxed_cell(loc_label, 0, _ARMOUR_GRID_COLUMNS))

	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.text = (ad.armour_name if ad else item_name) + name_suffix
	grid.add_child(_boxed_cell(name_label, 1, _ARMOUR_GRID_COLUMNS, true))

	var ap_label := Label.new()
	ap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ap_label.text = str(ad.armour_points) if ad else "-"
	## Per the request ("show damaged items, mark them red and reduce
	## dmg/ap on the appropriate location"): mirrors the Shop's own
	## Repair-tab red flag, but reduces the actual displayed AP figure
	## too. A Worn row has one exact `section_location` (matches what
	## Character.get_armour_points() actually applies in combat); an
	## unworn "Equip From Inventory" row covers several locations at
	## once with no single one to pick, so the worst-damaged of them
	## drives the headline AP figure, with every damaged location
	## spelled out in the name's own tooltip.
	if ad and owner:
		if section_location != "":
			var loc_damage: int = owner.get_armour_damage_at(item_name, section_location)
			if loc_damage > 0:
				ap_label.text = "%d/%d" % [max(0, ad.armour_points - loc_damage), ad.armour_points]
				ap_label.add_theme_color_override("font_color", Color(0.82, 0.35, 0.32))
				name_label.add_theme_color_override("font_color", Color(0.82, 0.35, 0.32))
				name_label.tooltip_text = "%d/%d AP damaged at %s — repair at the shop." % [loc_damage, ad.armour_points, section_location]
		else:
			var worst_damage := 0
			var breakdown: Array[String] = []
			for loc in ad.locations:
				var d: int = owner.get_armour_damage_at(item_name, loc)
				if d > 0:
					worst_damage = max(worst_damage, d)
					breakdown.append("%s %d/%d" % [loc, max(0, ad.armour_points - d), ad.armour_points])
			if worst_damage > 0:
				ap_label.text = "%d/%d" % [max(0, ad.armour_points - worst_damage), ad.armour_points]
				ap_label.add_theme_color_override("font_color", Color(0.82, 0.35, 0.32))
				name_label.add_theme_color_override("font_color", Color(0.82, 0.35, 0.32))
				name_label.tooltip_text = "Damaged: %s — repair at the shop." % ", ".join(breakdown)
	grid.add_child(_boxed_cell(ap_label, 2, _ARMOUR_GRID_COLUMNS))

	var qual_label := Label.new()
	qual_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qual_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	qual_label.text = ItemQualityRules.combined_display(ad.qualities, ad.item_qualities, ad.item_flaws) if ad else "-"
	var qual_cell := _boxed_cell(qual_label, 3, _ARMOUR_GRID_COLUMNS, true)
	## Weighted 3x over Name's default 1x stretch ratio, so most (not
	## all — Name still needs some breathing room) of the space freed
	## by shrinking the Location column lands here.
	qual_cell.size_flags_stretch_ratio = 3.0
	grid.add_child(qual_cell)

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 6)
	for btn in actions:
		actions_row.add_child(btn)
	grid.add_child(_boxed_cell(actions_row, 4, _ARMOUR_GRID_COLUMNS))

## --- Containers grid: Slot / Name / Capacity / Actions

static func _container_grid_header_row(grid: GridContainer) -> void:
	var titles := ["Slot", "Name", "Capacity", "Actions"]
	var aligns := [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_RIGHT, HORIZONTAL_ALIGNMENT_LEFT]
	var expand_cols := [1]
	for i in range(titles.size()):
		var lbl := Label.new()
		lbl.text = titles[i]
		lbl.horizontal_alignment = aligns[i]
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
		grid.add_child(_header_cell(lbl, expand_cols.has(i)))

static func _add_container_grid_row(grid: GridContainer, slot_text: String, item_name: String, it: ItemDefinition, name_suffix: String, actions: Array) -> void:
	var slot_label := Label.new()
	slot_label.text = slot_text
	grid.add_child(_boxed_cell(slot_label, 0, _CONTAINER_GRID_COLUMNS))

	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.text = item_name + name_suffix
	grid.add_child(_boxed_cell(name_label, 1, _CONTAINER_GRID_COLUMNS, true))

	var cap_label := Label.new()
	cap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cap_label.text = ("+%d Enc" % (it.container_capacity - max(0, it.encumbrance - 1))) if it else "-"
	grid.add_child(_boxed_cell(cap_label, 2, _CONTAINER_GRID_COLUMNS))

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 6)
	for btn in actions:
		actions_row.add_child(btn)
	grid.add_child(_boxed_cell(actions_row, 3, _CONTAINER_GRID_COLUMNS))

## --- Equipment tab: Weapons sub-tab -------------------------------------------

func _rebuild_weapons() -> void:
	_clear(weapons_box)
	if character == null:
		return

	weapons_box.add_child(_header("Equipped Weapons"))
	var grid := GridContainer.new()
	grid.columns = _WEAPON_GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 2)
	_weapon_grid_header_row(grid)

	var weapon := character.get_equipped_weapon()
	## Per the follow-up request ("all Lantern types should be visible
	## in the Weapons Sub tab, and equipable to main/off hand"): a light
	## source (Lantern, Storm Lantern, Candle (dozen), Davrich Lamp)
	## already lives in this same equipped_weapon slot (see
	## character.gd's own get_equipped_light_item()) but isn't a
	## WeaponDefinition, so get_equipped_weapon() alone can't see it —
	## this used to render as a bare "(unarmed)" Main Hand row even
	## while a Lantern was genuinely equipped. Resolved separately here
	## via the item DB so the row can show it instead.
	var main_light: ItemDefinition = null
	if weapon == null and character.equipped_weapon != "" and GameData.item_db != null:
		var main_li: ItemDefinition = GameData.item_db.find_by_name(character.equipped_weapon)
		if main_li != null and main_li.light_radius_tiles > 0:
			main_light = main_li
	## Per the request: durability damage from a fumbled "your weapon
	## takes 1 point of damage" Oops! result used to be invisible
	## everywhere except a one-time combat-log line — now shown here as
	## a tooltip on the Name cell, same as a damaged armour piece
	## already shows on the shop's repair list, so it's obvious this
	## weapon is worth repairing.
	var main_tooltip := ""
	if weapon and not weapon.is_indestructible:
		var main_dmg := int(character.weapon_damage_taken.get(weapon.weapon_name, 0))
		if main_dmg > 0:
			main_tooltip = "-%d Damage from wear — %d/%d points until destroyed; repair at the shop." % [main_dmg, main_dmg, weapon.damage_flat]
	if weapon and weapon.is_two_handed:
		if main_tooltip != "":
			main_tooltip += "\n"
		main_tooltip += "Two-handed — no off-hand item can be equipped alongside it."
	## Per the request: Unequip now lives right here with the worn item
	## itself, instead of being buried in a duplicate "Equip From
	## Inventory" row further down.
	var main_actions: Array = []
	if weapon or main_light:
		var unequip_main_btn := Button.new()
		unequip_main_btn.text = "Unqp (Main)"
		unequip_main_btn.pressed.connect(func():
			character.equipped_weapon = ""
			_rebuild_all()
		)
		main_actions.append(unequip_main_btn)
	_add_weapon_grid_row(grid, "Main Hand", weapon, "(unarmed)", main_tooltip, main_actions, "", main_light)

	## Off-hand (p.296): a genuinely separate slot from the main weapon —
	## a second one-handed weapon (for Dual Wielder) or a shield.
	var offhand := character.get_offhand_weapon()
	var is_two_handed_main := character.main_weapon_is_two_handed()
	var offhand_placeholder := "(empty)"
	var offhand_to_show: WeaponDefinition = null
	## Same "a light source occupies this hand slot too" resolution as
	## main_light above, for the off-hand.
	var off_light: ItemDefinition = null
	if is_two_handed_main:
		## Per the follow-up request ("The offhand name ... is too long
		## and is pushing the button out of the window and making it
		## scroll sideways when Equipping 2h weapons ... shorten that
		## name too"): trimmed way down from the old full-sentence
		## placeholder. The Main Hand row's own tooltip already spells
		## out the "two-handed — no off-hand item" reasoning in full.
		offhand_placeholder = "(two-handed)"
	elif offhand:
		offhand_to_show = offhand
	elif character.equipped_offhand != "" and GameData.item_db != null:
		var off_li: ItemDefinition = GameData.item_db.find_by_name(character.equipped_offhand)
		if off_li != null and off_li.light_radius_tiles > 0:
			off_light = off_li
	var off_tooltip := ""
	if offhand_to_show and not offhand_to_show.is_indestructible:
		var off_dmg := int(character.weapon_damage_taken.get(offhand_to_show.weapon_name, 0))
		if off_dmg > 0:
			off_tooltip = "-%d Damage from wear — %d/%d points until destroyed; repair at the shop." % [off_dmg, off_dmg, offhand_to_show.damage_flat]
	var off_actions: Array = []
	if offhand_to_show or off_light:
		var unequip_off_btn := Button.new()
		unequip_off_btn.text = "Unqp (Off)"
		unequip_off_btn.pressed.connect(func():
			character.equipped_offhand = ""
			_rebuild_all()
		)
		off_actions.append(unequip_off_btn)
	_add_weapon_grid_row(grid, "Off-Hand", offhand_to_show, offhand_placeholder, off_tooltip, off_actions, "", off_light)

	weapons_box.add_child(grid)
	_add_parry_toggle(weapons_box, weapon)
	if not is_two_handed_main:
		_add_parry_toggle(weapons_box, offhand_to_show)
	_add_ammo_selector(weapons_box, weapon)
	if not is_two_handed_main:
		_add_ammo_selector(weapons_box, offhand_to_show)

	weapons_box.add_child(_header("Equip From Inventory"))
	var counts: Dictionary = {}
	var order: Array[String] = []
	for item_name in character.inventory:
		if not counts.has(item_name):
			order.append(item_name)
		counts[item_name] = counts.get(item_name, 0) + 1

	## Per the request: items already equipped no longer get a row
	## here at all — this list is only "what's left in the bag that
	## could still be equipped somewhere." A weapon with every
	## physical copy already worn (main, off-hand, or both) has
	## nothing left to offer, so it's skipped entirely.
	##
	## Per the follow-up request ("all Lantern types should be visible
	## in the Weapons Sub tab, and equipable to main/off hand"): a
	## light source is offered here too now, alongside real weapons —
	## same shared equipped_weapon/equipped_offhand hand slots, using
	## the exact same _light_equip_buttons() the Inventory tab already
	## uses for this. Each entry carries a 4th slot (the light
	## ItemDefinition, or null for a real weapon row) so the render
	## loop below knows which one it's building a row for.
	var equippable: Array = []
	for item_name in order:
		var w: WeaponDefinition = GameData.weapon_db.find_by_name(item_name)
		if w != null:
			var buttons := _weapon_equip_buttons(item_name, w, counts, true)
			if not buttons.is_empty():
				equippable.append([item_name, w, buttons, null])
			continue
		var li: ItemDefinition = GameData.item_db.find_by_name(item_name) if GameData.item_db != null else null
		if li != null and li.light_radius_tiles > 0:
			var light_buttons := _light_equip_buttons(item_name, counts, true)
			if not light_buttons.is_empty():
				equippable.append([item_name, null, light_buttons, li])

	if equippable.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "(no weapons or light sources in your inventory to equip)"
		weapons_box.add_child(none_lbl)
	else:
		var inv_grid := GridContainer.new()
		inv_grid.columns = _WEAPON_GRID_COLUMNS
		inv_grid.add_theme_constant_override("h_separation", 0)
		inv_grid.add_theme_constant_override("v_separation", 2)
		_weapon_grid_header_row(inv_grid)
		for entry in equippable:
			var item_name: String = entry[0]
			var w: WeaponDefinition = entry[1]
			var buttons: Array = entry[2]
			var li_entry: ItemDefinition = entry[3]
			var qty_text := (" x%d" % counts[item_name]) if counts[item_name] > 1 else ""
			_add_weapon_grid_row(inv_grid, "", w, item_name, "", buttons, qty_text, li_entry)
		weapons_box.add_child(inv_grid)

## Parry (p.296): "Any one-handed weapon with the Defensive Quality can
## be used with Melee (Parry)" — a real player choice, not automatic,
## since defending with the weapon's own Group might actually be the
## better roll if that's where the Advances are. Only offered for a
## currently-equipped, one-handed, genuinely Defensive weapon (matching
## the rule's own wording exactly); anything else gets no row at all.
## The choice itself lives on Character.parry_preference, keyed by
## weapon NAME (see wants_parry_skill()) rather than by slot, so
## unequipping this weapon and re-equipping it later — same name, even
## in the other hand — remembers whatever was last chosen for it.
func _add_parry_toggle(container: VBoxContainer, weapon: WeaponDefinition) -> void:
	if weapon == null or weapon.is_two_handed or not weapon.qualities.has("Defensive"):
		return
	## Per the follow-up request ("hide this option if the character
	## has no training in Melee (Parry)"): the choice only makes sense
	## to offer once there's a real reason to prefer it over the
	## weapon's own Group — with zero Advances in Melee (Parry) itself,
	## picking it would just be another untrained Weapon Skill Test,
	## same as leaving it on the weapon's own Group already gives.
	var melee_skill: SkillDefinition = GameData.skill_db.find_by_name("Melee")
	if melee_skill == null or not character.skill_advances.has(melee_skill.display_name("Parry")):
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var toggle := CheckBox.new()
	toggle.text = "Use Melee (Parry) to defend with %s" % weapon.weapon_name
	toggle.button_pressed = character.wants_parry_skill(weapon)
	toggle.toggled.connect(func(pressed: bool):
		character.parry_preference[weapon.weapon_name] = pressed
	)
	row.add_child(toggle)
	container.add_child(row)

## Ammunition (p.294): per the "implement Ammunition fully... show these
## in the shop and equipment menu" request — lets the player choose
## which Ammunition type is currently loaded into a ranged weapon that
## needs ammo, whenever there's a genuine choice to make (2+ different
## acceptable ammo types actually sitting in inventory; a single type on
## hand has nothing to switch to, so no row is shown at all). The choice
## itself lives on Character.active_ammo, keyed by weapon NAME — see
## get_active_ammo_item() — same "survives unequip/re-equip" convention
## _add_parry_toggle()'s own parry_preference uses just above, whose
## shape/gating this mirrors.
func _add_ammo_selector(container: VBoxContainer, weapon: WeaponDefinition) -> void:
	if weapon == null or not weapon.is_ranged or not AmmoLookup.needs_ammo(weapon):
		return
	var owned_ammo_names: Array[String] = []
	for ammo_name in AmmoLookup.required_ammo_names(weapon):
		if character.inventory.has(ammo_name):
			owned_ammo_names.append(ammo_name)
	if owned_ammo_names.size() < 2:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = "Ammo for %s:" % weapon.weapon_name
	row.add_child(label)
	var option := OptionButton.new()
	var current_ammo: ItemDefinition = character.get_active_ammo_item(weapon)
	var current_name: String = current_ammo.item_name if current_ammo != null else ""
	for i in owned_ammo_names.size():
		option.add_item(owned_ammo_names[i])
		if owned_ammo_names[i] == current_name:
			option.select(i)
	option.item_selected.connect(func(idx: int):
		character.active_ammo[weapon.weapon_name] = owned_ammo_names[idx]
		_rebuild_all()
	)
	row.add_child(option)
	container.add_child(row)

## Per the request ("allow equipping and unequipping from the inventory
## menu" too): shared between the Weapons sub-tab's "Equip From
## Inventory" list and the Inventory tab, so both offer identical
## Equip (Main)/Equip (Off-hand) actions. Returns an empty array when
## there's nothing left to offer for this item_name — i.e. every
## physical copy owned is already equipped in some slot — since that
## item's Unequip action lives with the worn display instead (Main
## Hand/Off-Hand here, or its own row's Unequip in the Inventory tab).
func _weapon_equip_buttons(item_name: String, w: WeaponDefinition, counts: Dictionary, short: bool = false) -> Array[Button]:
	var buttons: Array[Button] = []
	var is_main := character.equipped_weapon == item_name
	var is_off := character.equipped_offhand == item_name
	## Per the bug report: a single physical item can't be wielded in
	## both hands at once. Putting the same item_name in both slots is
	## only legitimate if there are actually two copies of it to split
	## between the hands (genuine Dual Wielder use of two identical
	## weapons) — with only one copy, offering it to the other hand
	## too is left off entirely.
	var have_two_copies: bool = counts.get(item_name, 0) >= 2
	if not is_main and not (is_off and not have_two_copies):
		var main_btn := Button.new()
		main_btn.text = "Eqp (Main)" if short else "Equip (Main)"
		main_btn.pressed.connect(func():
			character.equipped_weapon = item_name
			## A two-handed weapon can't share a hand with anything
			## else — clear the off-hand rather than leave an illegal
			## combination on the sheet.
			if w.is_two_handed:
				character.equipped_offhand = ""
			_rebuild_all()
		)
		buttons.append(main_btn)
	if not is_off and not character.main_weapon_is_two_handed() and not (is_main and not have_two_copies):
		var off_btn := Button.new()
		off_btn.text = "Eqp (Off)" if short else "Equip (Off-hand)"
		off_btn.pressed.connect(func():
			character.equipped_offhand = item_name
			_rebuild_all()
		)
		buttons.append(off_btn)
	return buttons

## Per the follow-up request ("lantern need to be held on either main
## or off hand, remove the extra lantern slot"): mirrors
## _weapon_equip_buttons() above for a light-source item (Lantern,
## Storm Lantern, Candle (dozen), Davrich Lamp) — same shared
## equipped_weapon/equipped_offhand hand slots, just with no two-handed
## concept of its own to worry about (a light source is always
## one-handed). Still respects an already-equipped two-handed WEAPON in
## the main hand blocking the off-hand, via
## character.main_weapon_is_two_handed(), same as a real off-hand
## weapon/shield would be blocked.
func _light_equip_buttons(item_name: String, counts: Dictionary, short: bool = false) -> Array[Button]:
	var buttons: Array[Button] = []
	var is_main := character.equipped_weapon == item_name
	var is_off := character.equipped_offhand == item_name
	## Same "only offer both hands if there are genuinely two copies"
	## rule as _weapon_equip_buttons() — one Lantern can't be held in
	## both hands at once.
	var have_two_copies: bool = counts.get(item_name, 0) >= 2
	if not is_main and not (is_off and not have_two_copies):
		var main_btn := Button.new()
		main_btn.text = "Eqp (Main)" if short else "Equip (Main)"
		main_btn.pressed.connect(func():
			character.equipped_weapon = item_name
			_rebuild_all()
		)
		buttons.append(main_btn)
	if not is_off and not character.main_weapon_is_two_handed() and not (is_main and not have_two_copies):
		var off_btn := Button.new()
		off_btn.text = "Eqp (Off)" if short else "Equip (Off-hand)"
		off_btn.pressed.connect(func():
			character.equipped_offhand = item_name
			_rebuild_all()
		)
		buttons.append(off_btn)
	return buttons

## --- Equipment tab: Armor sub-tab ----------------------------------------------
## Per the request: grouped by tier (Light/Medium/Heavy), with equip
## available directly here for each location, rather than one flat list.

func _rebuild_armor() -> void:
	_clear(armor_box)
	if character == null:
		return

	armor_box.add_child(_header("Worn Armour"))
	## Per the request ("Re-order the grouping in Worn Armor section
	## from Light/Medium/Heavy, to Head/Body/Left Arm/Right Arm/Left
	## Leg/Right Leg"): a piece covering more than one location (e.g.
	## most Body armour also lists an Arm) now appears under EVERY
	## location it covers, not just one — there's no single "primary"
	## location to pick, and the player looking under any location it
	## actually protects should see it listed there.
	var worn_by_location: Dictionary = {}
	for loc in _ARMOUR_LOCATION_ORDER:
		worn_by_location[loc] = []
	for piece_name in character.equipped_armour:
		var ad: ArmourDefinition = GameData.armour_db.find_by_name(piece_name)
		var locs: Array = ad.locations if ad and not ad.locations.is_empty() else ["Body"]
		for loc in locs:
			if not worn_by_location.has(loc):
				worn_by_location[loc] = []
			worn_by_location[loc].append(piece_name)

	var any_worn := false
	var grid := GridContainer.new()
	grid.columns = _ARMOUR_GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 2)
	## Per the follow-up request ("remove the column header from inside
	## the location groups and put a single header at the top, between
	## Worn Armor and Head"): one shared column-header row for the
	## whole grid instead of one repeated per location section.
	_armour_grid_header_row(grid)
	## Per the follow-up request ("hide the grouping names (red lines)"):
	## the per-location red section-header rows are gone — the location
	## a row is grouped under is now shown in that row's own Location
	## column instead (see _add_armour_grid_row's `section_location`),
	## so the per-location loop below still groups the rows, it just no
	## longer renders a header row for each group.
	for loc in _ARMOUR_LOCATION_ORDER:
		if worn_by_location[loc].is_empty():
			continue
		any_worn = true
		for piece_name in worn_by_location[loc]:
			var ad2: ArmourDefinition = GameData.armour_db.find_by_name(piece_name)
			## Per the request: the Unequip action now lives right here
			## with the worn piece itself, instead of a duplicate row
			## further down in "Equip From Inventory".
			var unequip_btn := Button.new()
			unequip_btn.text = "Unqp"
			unequip_btn.pressed.connect(func():
				character.equipped_armour.erase(piece_name)
				_rebuild_all()
			)
			_add_armour_grid_row(grid, ad2, piece_name, "", [unequip_btn], loc, character)
	if any_worn:
		armor_box.add_child(grid)
	else:
		armor_box.add_child(Label.new())

	armor_box.add_child(_header("Equip From Inventory"))
	var counts: Dictionary = {}
	var order: Array[String] = []
	for item_name in character.inventory:
		if not counts.has(item_name):
			order.append(item_name)
		counts[item_name] = counts.get(item_name, 0) + 1

	## Per the follow-up request ("remove grouping from the Equip from
	## Inventory section, just list those alphabetically"): unlike Worn
	## Armour above, this list is now flat — no tier or location
	## grouping at all — sorted alphabetically instead of inventory
	## order, same naturalnocasecmp_to() idiom the Skills grid already
	## uses for its own alphabetical sort.
	var candidates: Array[String] = []
	for item_name in order:
		if character.equipped_armour.has(item_name):
			continue
		var cand_def: ArmourDefinition = GameData.armour_db.find_by_name(item_name)
		if cand_def == null:
			continue
		candidates.append(item_name)
	candidates.sort_custom(func(a, b): return (a as String).naturalnocasecmp_to(b as String) < 0)

	if candidates.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "(no armour in your inventory to equip)"
		armor_box.add_child(none_lbl)
	else:
		var inv_grid := GridContainer.new()
		inv_grid.columns = _ARMOUR_GRID_COLUMNS
		inv_grid.add_theme_constant_override("h_separation", 0)
		inv_grid.add_theme_constant_override("v_separation", 2)
		_armour_grid_header_row(inv_grid)
		for item_name in candidates:
			var ad3: ArmourDefinition = GameData.armour_db.find_by_name(item_name)
			var qty_text := (" x%d" % counts[item_name]) if counts[item_name] > 1 else ""
			_add_armour_grid_row(inv_grid, ad3, item_name, qty_text, [_armour_equip_button(item_name, true)], "", character)
		armor_box.add_child(inv_grid)

## Per the request ("allow equipping and unequipping from the inventory
## menu" too): shared between the Armor sub-tab's "Equip From Inventory"
## list and the Inventory tab, so both offer the identical Equip action
## for a not-currently-worn armour piece — including the same
## conflicting-location disable/tooltip. Only ever called for an
## item_name that isn't already worn (see the caller in each tab); a
## worn piece's Unequip button is built inline where it's shown instead,
## since that action doesn't need any of this conflict-checking.
func _armour_equip_button(item_name: String, short: bool = false) -> Button:
	var conflicts := character.get_conflicting_equipped_armour(item_name)
	var btn := Button.new()
	btn.text = "Eqp" if short else "Equip"
	btn.disabled = not conflicts.is_empty()
	if not conflicts.is_empty():
		btn.tooltip_text = "Covers the same location as your equipped %s — unequip that first." % ", ".join(conflicts)
	btn.pressed.connect(func():
		character.equipped_armour.append(item_name)
		_rebuild_all()
	)
	return btn

## --- Equipment tab: Containers sub-tab -----------------------------------------
## Per the "packs and containers" request: three dedicated Container
## equip slots (Back/Waist/Shoulder) — mirrors the Armor sub-tab just
## above (Worn, then Equip From Inventory), but by slot rather than by
## armour tier, since each slot only ever holds one specific kind of
## container.

func _rebuild_containers() -> void:
	_clear(container_box)
	if character == null:
		return

	container_box.add_child(_header("Worn Containers"))
	var any_worn := false
	var worn_grid := GridContainer.new()
	worn_grid.columns = _CONTAINER_GRID_COLUMNS
	worn_grid.add_theme_constant_override("h_separation", 0)
	worn_grid.add_theme_constant_override("v_separation", 2)
	_container_grid_header_row(worn_grid)
	for slot in ["Back", "Waist", "Shoulder"]:
		var worn_name: String = character.get_equipped_container(slot)
		if worn_name == "":
			continue
		any_worn = true
		var it: ItemDefinition = GameData.item_db.find_by_name(worn_name) if GameData.item_db != null else null
		var unequip_btn := Button.new()
		unequip_btn.text = "Unqp"
		unequip_btn.pressed.connect(func():
			character.set_equipped_container(slot, "")
			_rebuild_all()
		)
		_add_container_grid_row(worn_grid, slot, worn_name, it, "", [unequip_btn])
	if any_worn:
		container_box.add_child(worn_grid)
	else:
		container_box.add_child(Label.new())

	container_box.add_child(_header("Equip From Inventory"))
	var counts: Dictionary = {}
	var order: Array[String] = []
	for item_name in character.inventory:
		if not counts.has(item_name):
			order.append(item_name)
		counts[item_name] = counts.get(item_name, 0) + 1

	var candidates: Array = []
	for item_name in order:
		var it2: ItemDefinition = GameData.item_db.find_by_name(item_name) if GameData.item_db != null else null
		if it2 == null or it2.container_slot == "":
			continue
		if character.get_equipped_container(it2.container_slot) == item_name:
			continue   ## already shown, worn, above
		candidates.append([item_name, it2])

	if candidates.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "(no Backpack/Pouch/Sling Bag in your inventory to equip)"
		container_box.add_child(none_lbl)
	else:
		var inv_grid := GridContainer.new()
		inv_grid.columns = _CONTAINER_GRID_COLUMNS
		inv_grid.add_theme_constant_override("h_separation", 0)
		inv_grid.add_theme_constant_override("v_separation", 2)
		_container_grid_header_row(inv_grid)
		for entry in candidates:
			var item_name: String = entry[0]
			var it2: ItemDefinition = entry[1]
			var qty_text := (" x%d" % counts[item_name]) if counts[item_name] > 1 else ""
			_add_container_grid_row(inv_grid, it2.container_slot, item_name, it2, qty_text, [_container_equip_button(item_name, it2, true)])
		container_box.add_child(inv_grid)

## Per the request ("allow equipping and unequipping from the
## inventory menu" too, same convention _armour_equip_button already
## follows): shared between the Containers sub-tab's "Equip From
## Inventory" list and the Inventory tab, so both offer the identical
## Equip action. Disabled (with a tooltip) whenever that container's
## own slot is already occupied by a DIFFERENT item — unlike armour's
## overlapping-locations conflict list, a container slot only ever
## holds the one thing, so this is a simple occupied/not check.
func _container_equip_button(item_name: String, it: ItemDefinition, short: bool = false) -> Button:
	var btn := Button.new()
	btn.text = "Eqp (%s)" % it.container_slot if short else "Equip (%s)" % it.container_slot
	var currently_worn: String = character.get_equipped_container(it.container_slot)
	if currently_worn != "" and currently_worn != item_name:
		btn.disabled = true
		btn.tooltip_text = "Your %s slot is already carrying %s — unequip that first." % [it.container_slot, currently_worn]
	btn.pressed.connect(func():
		character.set_equipped_container(it.container_slot, item_name)
		_rebuild_all()
	)
	return btn

## --- Spellbook tab ----------------------------------------------------------
## Per the request: the Spells sub-tab only shows once the character
## has Petty Magic or an Arcane Magic (Lore) Talent; Blessings and
## Miracles only once they have a Bless/Invoke Talent — each sub-tab
## also now offers learning new spells/blessings/miracles from the
## available list for whichever Lore/god the character already has,
## rather than requiring a trip to the Hermit trainer NPC (spells) or
## keeping Miracle-learning off in the old Experience tab.
## Casting here (out of combat) uses the same MagicResolver/PrayerResolver
## as combat does — self-targeted use: healing yourself, buffing
## yourself before a fight, etc.

func _rebuild_spellbook() -> void:
	if character == null:
		return
	var has_spells_talent := character.has_talent("Petty Magic") or character.get_arcane_lore() != ""
	var has_prayers_talent := character.get_bless_god() != "" or character.get_invoke_god() != ""
	spellbook_tabs.set_tab_hidden(0, not has_spells_talent)
	spellbook_tabs.set_tab_hidden(1, not has_prayers_talent)
	if has_spells_talent:
		_rebuild_spells_subtab()
	else:
		_clear(spells_box)
	if has_prayers_talent:
		_rebuild_blessings_miracles_subtab()
	else:
		_clear(blessings_miracles_box)
	## If the currently-selected sub-tab just got hidden (e.g. switched
	## to viewing a party member with neither Talent), fall back to
	## whichever sub-tab is still visible rather than leaving the
	## TabContainer showing a blank hidden tab.
	if spellbook_tabs.current_tab >= 0 and spellbook_tabs.current_tab < spellbook_tabs.get_tab_count() and spellbook_tabs.is_tab_hidden(spellbook_tabs.current_tab):
		for i in range(spellbook_tabs.get_tab_count()):
			if not spellbook_tabs.is_tab_hidden(i):
				spellbook_tabs.current_tab = i
				break

func _rebuild_spells_subtab() -> void:
	_clear(spells_box)
	spells_box.add_child(_header("Known Spells"))
	if character.known_spells.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "(none yet — learn some below)"
		spells_box.add_child(none_lbl)
	for spell_name in character.known_spells:
		var sp: SpellDefinition = GameData.spell_db.find_by_name(spell_name)
		if sp == null:
			continue
		spells_box.add_child(_spell_page(sp))

	if character.has_talent("Petty Magic"):
		spells_box.add_child(_header("Learn a Petty Spell"))
		var known_count := 0
		for s in character.known_spells:
			var sd: SpellDefinition = GameData.spell_db.find_by_name(s)
			if sd != null and sd.spell_type == "Petty":
				known_count += 1
		var wpb := character.get_characteristic_bonus("willpower")
		var next_cost := Advancement._tiered_spell_cost(known_count, wpb, 50)
		var available: Array[SpellDefinition] = []
		for sp in GameData.spell_db.find_by_type("Petty"):
			if not character.known_spells.has(sp.spell_name):
				available.append(sp)
		if available.is_empty():
			var all_known := Label.new()
			all_known.text = "(you already know every Petty spell)"
			spells_box.add_child(all_known)
		else:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var picker := OptionButton.new()
			var any_implemented := false
			for i in range(available.size()):
				var sp := available[i]
				var implemented := sp.is_mechanically_implemented()
				## Per the explicit request ("grey out and disable all
				## spells which are not implemented... re-enable them as
				## we implement them"): every book spell still shows up
				## here — nothing is hidden — but one that currently does
				## nothing beyond its own flavor text (see
				## SpellDefinition.is_mechanically_implemented) is
				## disabled right in the dropdown (Godot greys a disabled
				## OptionButton item automatically) and labelled so it's
				## clear WHY it can't be picked, rather than silently
				## unselectable.
				picker.add_item(sp.spell_name if implemented else "%s (Not Yet Implemented)" % sp.spell_name)
				if not implemented:
					picker.set_item_disabled(i, true)
				else:
					any_implemented = true
			## Default the visible selection to the first genuinely
			## learnable spell rather than whatever sorts first — index 0
			## defaults selected even when it's a disabled item, which
			## would otherwise show a not-yet-implemented spell as the
			## picker's own resting state.
			for i in range(available.size()):
				if not picker.is_item_disabled(i):
					picker.select(i)
					break
			row.add_child(picker)
			var btn := Button.new()
			btn.text = "Learn (%d XP)" % next_cost
			btn.disabled = character.get_experience_available() < next_cost or not any_implemented
			btn.pressed.connect(func():
				if picker.is_item_disabled(picker.selected):
					return   ## defensive guard — the picker's own menu already refuses to select a disabled item
				var chosen := available[picker.selected].spell_name
				Advancement.purchase_petty_spell(character, chosen)
				_rebuild_all()
			)
			row.add_child(btn)
			spells_box.add_child(row)

	var lore := character.get_arcane_lore()
	if lore != "":
		spells_box.add_child(_header("Learn an Arcane Spell (%s)" % lore))
		## Per Advancement.purchase_arcane_spell's own comment: generic
		## Arcane spells and this Lore's own signature spells share one
		## combined known_count/XP tier, since the book prices them
		## identically -- counted the same way here so the previewed
		## cost always matches what purchase_arcane_spell will actually
		## charge.
		var known_count2 := 0
		for s in character.known_spells:
			var sd2: SpellDefinition = GameData.spell_db.find_by_name(s)
			if sd2 != null and (sd2.spell_type == "Arcane" or sd2.spell_type == "Lore"):
				known_count2 += 1
		var int_bonus := character.get_characteristic_bonus("intelligence")
		var next_cost2 := Advancement._tiered_spell_cost(known_count2, int_bonus, 100)
		## Real bug fix: this dropdown only ever listed the generic,
		## any-Lore Arcane spells -- it never included the 8 signature
		## spells belonging to the character's OWN Lore (e.g. a Fire
		## Lore wizard could never actually learn Crown of Flame, Purge,
		## etc. through this screen even though
		## Advancement.purchase_arcane_spell has always been willing to
		## sell them). Lore spells are a separate spell_type from
		## generic Arcane ones (see SpellDefinition's own schema), so
		## find_by_type("Arcane") alone was never going to surface them.
		var available2: Array[SpellDefinition] = []
		for sp in GameData.spell_db.find_by_type("Arcane"):
			if not character.known_spells.has(sp.spell_name):
				available2.append(sp)
		for sp in GameData.spell_db.find_by_type("Lore"):
			if sp.lore == lore and not character.known_spells.has(sp.spell_name):
				available2.append(sp)
		if available2.is_empty():
			var all_known2 := Label.new()
			all_known2.text = "(you already know every Arcane spell)"
			spells_box.add_child(all_known2)
		else:
			var row2 := HBoxContainer.new()
			row2.add_theme_constant_override("separation", 8)
			var picker2 := OptionButton.new()
			var any_implemented2 := false
			for i in range(available2.size()):
				var sp2 := available2[i]
				var implemented2 := sp2.is_mechanically_implemented()
				## Same grey-out-if-unimplemented treatment as the Petty
				## picker just above — see its own comment. Covers both
				## the generic Arcane list and this Lore's own signature
				## spells in one pass, since available2 already merges
				## both (see the comment above this dropdown's own
				## construction).
				picker2.add_item(sp2.spell_name if implemented2 else "%s (Not Yet Implemented)" % sp2.spell_name)
				if not implemented2:
					picker2.set_item_disabled(i, true)
				else:
					any_implemented2 = true
			for i in range(available2.size()):
				if not picker2.is_item_disabled(i):
					picker2.select(i)
					break
			row2.add_child(picker2)
			var btn2 := Button.new()
			btn2.text = "Learn (%d XP)" % next_cost2
			btn2.disabled = character.get_experience_available() < next_cost2 or not any_implemented2
			btn2.pressed.connect(func():
				if picker2.is_item_disabled(picker2.selected):
					return   ## defensive guard — the picker's own menu already refuses to select a disabled item
				var chosen2 := available2[picker2.selected].spell_name
				Advancement.purchase_arcane_spell(character, chosen2)
				_rebuild_all()
			)
			row2.add_child(btn2)
			spells_box.add_child(row2)

func _rebuild_blessings_miracles_subtab() -> void:
	_clear(blessings_miracles_box)
	blessings_miracles_box.add_child(_header("Known Blessings & Miracles"))
	var effective_prayers := character.get_effective_known_prayers()
	if effective_prayers.is_empty():
		var none_lbl2 := Label.new()
		none_lbl2.text = "(none yet)"
		blessings_miracles_box.add_child(none_lbl2)
	for prayer_name in effective_prayers:
		var pr: PrayerDefinition = GameData.prayer_db.find_by_name(prayer_name)
		if pr == null:
			continue
		blessings_miracles_box.add_child(_prayer_page(pr))

	## Blessings & Miracles (p.220-226): Blessings are free and automatic
	## the moment Bless(god) is taken — already included in
	## get_effective_known_prayers() above, nothing to buy. Miracles need
	## Invoke(god) first; the first one is free, further ones cost 100 XP
	## per Miracle already known, and all must be from that same god.
	var invoke_god := character.get_invoke_god()
	if invoke_god != "":
		blessings_miracles_box.add_child(_header("Learn a Miracle of %s" % invoke_god))
		var known_miracle_count := 0
		for p in character.known_prayers:
			var pd2: PrayerDefinition = GameData.prayer_db.find_by_name(p)
			if pd2 != null and pd2.prayer_type == "Miracle":
				known_miracle_count += 1
		var next_cost := 0 if known_miracle_count == 0 else 100 * known_miracle_count

		var available_miracles: Array[PrayerDefinition] = []
		for m in GameData.prayer_db.get_miracles_for_god(invoke_god):
			if not character.known_prayers.has(m.prayer_name):
				available_miracles.append(m)
		if not available_miracles.is_empty():
			var miracle_row := HBoxContainer.new()
			miracle_row.add_theme_constant_override("separation", 8)
			var miracle_picker := OptionButton.new()
			for m in available_miracles:
				miracle_picker.add_item(m.prayer_name)
			miracle_row.add_child(miracle_picker)
			var miracle_btn := Button.new()
			miracle_btn.text = "Learn (Free)" if known_miracle_count == 0 else "Learn (%d XP)" % next_cost
			miracle_btn.disabled = character.get_experience_available() < next_cost
			miracle_btn.pressed.connect(func():
				var chosen := available_miracles[miracle_picker.selected].prayer_name
				Advancement.purchase_miracle(character, chosen)
				_rebuild_all()
			)
			miracle_row.add_child(miracle_btn)
			blessings_miracles_box.add_child(miracle_row)
		elif GameData.prayer_db.get_miracles_for_god(invoke_god).is_empty():
			var no_data_label := Label.new()
			no_data_label.text = "(Miracles for %s aren't in the data yet — only Sigmar's are populated so far.)" % invoke_god
			no_data_label.add_theme_font_size_override("font_size", 11)
			no_data_label.add_theme_color_override("font_color", Color(0.6, 0.55, 0.48))
			blessings_miracles_box.add_child(no_data_label)

func _spell_page(sp: SpellDefinition) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(0, 70)
	rt.text = "[b]%s[/b]  [i](%s%s)[/i]\nCN: %d   Range: %s   Target: %s   Duration: %s\n%s" % [
		sp.spell_name, sp.spell_type, (" — " + sp.lore) if sp.lore != "" else "",
		sp.casting_number, sp.range_text, sp.target_text, sp.duration_text, sp.summary
	]
	box.add_child(rt)
	var result_label := Label.new()
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(result_label)
	var cast_btn := Button.new()
	cast_btn.text = "Cast"
	cast_btn.pressed.connect(func(): _cast_spell_out_of_combat(sp, result_label))
	box.add_child(cast_btn)
	panel.add_child(box)
	return panel

func _prayer_page(pr: PrayerDefinition) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(0, 70)
	rt.text = "[b]%s[/b]  [i](%s — %s)[/i]\nRange: %s   Target: %s   Duration: %s\n%s" % [
		pr.prayer_name, pr.prayer_type, pr.god, pr.range_text, pr.target_text, pr.duration_text, pr.summary
	]
	box.add_child(rt)
	var result_label := Label.new()
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(result_label)
	var pray_btn := Button.new()
	pray_btn.text = "Pray"
	pray_btn.pressed.connect(func(): _pray_out_of_combat(pr, result_label))
	box.add_child(pray_btn)
	panel.add_child(box)
	return panel

## Self-targeted casting outside combat. Drain (heals) gets its real
## mechanical effect, matching combat; everything else resolves the
## Test and reports success/failure plus its summary — a fair "does it
## work" answer even for effects (buffs, attack spells) this simplified
## out-of-combat flow doesn't fully play out mechanically.
func _cast_spell_out_of_combat(sp: SpellDefinition, result_label: Label) -> void:
	var cast_result := MagicResolver.cast(character, sp, 0)
	if cast_result.success:
		if sp.spell_name == "Drain":
			character.wounds_current = min(character.wounds_max, character.wounds_current + 1)
			result_label.text = "Cast successfully — healed 1 Wound (now %d/%d)." % [character.wounds_current, character.wounds_max]
		else:
			result_label.text = "Cast successfully (CN %d)." % sp.casting_number
		result_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	else:
		result_label.text = "The spell fails to take hold."
		result_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.55))
	if cast_result.fumble and not cast_result.miscast.is_empty():
		result_label.text += " Miscast: " + cast_result.miscast.get("text", "")
	_rebuild_header()

func _pray_out_of_combat(pr: PrayerDefinition, result_label: Label) -> void:
	var pray_result := PrayerResolver.pray(character, pr, 0)
	if pray_result.success:
		if pr.prayer_name == "Blessing of Healing":
			character.wounds_current = min(character.wounds_max, character.wounds_current + 1)
			result_label.text = "Prayer answered — healed 1 Wound (now %d/%d)." % [character.wounds_current, character.wounds_max]
		else:
			result_label.text = "Prayer answered."
		result_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	else:
		result_label.text = "Your god does not answer this time."
		result_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.55))
	if pray_result.fumble and not pray_result.wrath.is_empty():
		result_label.text += " Wrath of the Gods: " + pray_result.wrath.get("text", "")
	_rebuild_header()

## --- Career tab ---------------------------------------------------------------
## Per the request: Class/Career advancement and change (moved out of
## the old Experience tab — not Skill/Talent XP spending, which stays
## in Stats) plus a running record of every past change.

func _rebuild_career() -> void:
	_clear(career_box)
	if character == null:
		return

	career_box.add_child(_header("Current Career"))
	var completed := Advancement.has_completed_current_level(character)
	var career_status := Label.new()
	var level_name := character.career.get_level(character.current_tier).level_name if character.career else "?"
	career_status.text = "%s, Tier %d — %s — %s" % [
		character.career.career_name if character.career else "?", character.current_tier,
		level_name, "level complete" if completed else "not yet complete",
	]
	career_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	career_box.add_child(career_status)

	var next_level := character.career.get_level(character.current_tier + 1) if character.career else null
	if next_level:
		var cost := Advancement.get_change_career_cost(completed)
		_add_xp_row(career_box, "Advance to %s (Tier %d, same career)" % [next_level.level_name, character.current_tier + 1],
			cost, func(): _change_career(character.career, character.current_tier + 1))
	else:
		var maxed_lbl := Label.new()
		maxed_lbl.text = "(already at the top tier of this career)"
		career_box.add_child(maxed_lbl)

	career_box.add_child(_header("Change to a Different Career"))
	var switch_row := HBoxContainer.new()
	switch_row.add_theme_constant_override("separation", 8)
	var career_picker := OptionButton.new()
	for c in GameData.careers:
		career_picker.add_item(c.career_name)
	switch_row.add_child(career_picker)
	var switch_btn := Button.new()
	var _update_switch_button := func():
		var target: CareerDefinition = GameData.careers[career_picker.selected]
		var changing_class := character.career != null and character.career.career_class != target.career_class
		var cost := Advancement.get_change_career_cost(completed, changing_class)
		switch_btn.text = "Switch (Tier 1%s) — %d XP" % [", different Class" if changing_class else "", cost]
		switch_btn.disabled = character.get_experience_available() < cost
	career_picker.item_selected.connect(func(_idx): _update_switch_button.call())
	_update_switch_button.call()
	switch_btn.pressed.connect(func():
		var target: CareerDefinition = GameData.careers[career_picker.selected]
		_change_career(target, 1)
	)
	switch_row.add_child(switch_btn)
	career_box.add_child(switch_row)
	var switch_note := Label.new()
	switch_note.text = "Moving to an entirely different career always starts at its Tier 1, per the rules. Entering a career from a different Class costs an extra 100 XP on top."
	switch_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	switch_note.add_theme_font_size_override("font_size", 12)
	switch_note.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
	career_box.add_child(switch_note)

	career_box.add_child(_header("Career History"))
	if character.career_history.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "No career changes recorded yet — still on the career they started with."
		career_box.add_child(none_lbl)
	else:
		## Newest first, so the most recent change is the one immediately
		## visible without scrolling.
		for i in range(character.career_history.size() - 1, -1, -1):
			var entry: Dictionary = character.career_history[i]
			var date_info := WarhammerCalendar.decode(int(entry.get("day_of_year", 0)))
			var date_str: String = date_info.display_string() if not date_info.is_intercalary else date_info.holiday_name
			var year: int = int(entry.get("imperial_year", 0))
			var row := RichTextLabel.new()
			row.bbcode_enabled = true
			row.fit_content = true
			row.custom_minimum_size = Vector2(0, 20)
			var from_text: String = "%s (Tier %d)" % [str(entry.get("from_career", "?")), int(entry.get("from_tier", 0))]
			var to_text: String = "%s (Tier %d)" % [str(entry.get("to_career", "?")), int(entry.get("to_tier", 0))]
			row.text = "%s, %d — [b]%s[/b] → [b]%s[/b] (%d XP)" % [date_str, year, from_text, to_text, int(entry.get("cost", 0))]
			career_box.add_child(row)

## --- Group tab ------------------------------------------------------------
## Per the request: every current party member's HP/EXP/Class/Level at
## a glance, plus a Dismiss option (with a confirmation dialog) — a
## dismissed companion leaves with everything they currently have, and
## can be recruited again later at the Party Companion Maker in
## Giessingen (see overworld.gd's _open_companion_maker).

func _rebuild_group() -> void:
	_clear(group_box)
	if GameState.party.is_empty():
		return
	group_box.add_child(_header("Your Party"))
	for member in GameState.party:
		var panel := PanelContainer.new()
		group_box.add_child(panel)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_top", 8)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_bottom", 8)
		panel.add_child(margin)
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		margin.add_child(vbox)

		var top_row := HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 8)
		vbox.add_child(top_row)
		var name_label := RichTextLabel.new()
		name_label.bbcode_enabled = true
		name_label.fit_content = true
		name_label.custom_minimum_size = Vector2(0, 22)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var active_tag := "  [color=#8fbf6a](active)[/color]" if member == GameState.player_character else ""
		var level_name := member.career.get_level(member.current_tier).level_name if member.career else "?"
		name_label.text = "[b]%s[/b]%s  —  %s %s, %s (Tier %d)" % [
			member.character_name, active_tag,
			member.race.race_name if member.race else "?",
			member.career.career_name if member.career else "?",
			level_name, member.current_tier,
		]
		top_row.add_child(name_label)

		var dismiss_btn := Button.new()
		dismiss_btn.text = "Dismiss"
		dismiss_btn.disabled = GameState.party.size() <= 1
		dismiss_btn.tooltip_text = "" if GameState.party.size() > 1 else "You can't dismiss your only remaining party member."
		dismiss_btn.pressed.connect(func(): _on_dismiss_pressed(member))
		top_row.add_child(dismiss_btn)

		var stats_label := Label.new()
		stats_label.text = "HP: %d / %d      XP: %d total, %d available" % [
			member.wounds_current, member.wounds_max, member.experience_total, member.get_experience_available()
		]
		stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(stats_label)

func _on_dismiss_pressed(member: Character) -> void:
	_open_confirm("Dismiss Companion?",
		"Dismiss %s from the party? They'll leave with everything they currently have — you'll be able to recruit them again later at the Party Companion Maker in Giessingen." % member.character_name,
		func(): _do_dismiss(member))

func _do_dismiss(member: Character) -> void:
	var idx := GameState.party.find(member)
	if idx == -1:
		return
	GameState.party.remove_at(idx)
	GameState.dismissed_companions.append(member)
	if GameState.active_party_index >= GameState.party.size():
		GameState.active_party_index = max(0, GameState.party.size() - 1)
	if character == member:
		character = GameState.player_character
	GameState.autosave()
	_rebuild_all()

## --- Journal tab: Notes sub-tab -------------------------------------------
## Per the request: the character's ongoing story — the origin story
## plus every automatically-recorded major event since (a new
## location, a career change, a quest update, a new contact — never
## routine fights). Shown oldest-first, since it reads as a story from
## the beginning rather than a log with the newest thing on top.
func _rebuild_journal() -> void:
	_clear(journey_box)
	## Per the request: Quests and the Journal are shared for the
	## whole group, not each member's own separate copy — always reads
	## the party's own canonical record (its first-ever member) rather
	## than whichever character Q/E is currently browsing for the
	## other tabs.
	var shared: Character = GameState.party[0] if not GameState.party.is_empty() else character
	if shared == null:
		return
	journey_box.add_child(_header("The Journey So Far"))
	if shared.journal_entries.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "Nothing recorded yet."
		journey_box.add_child(none_lbl)
		return
	for i in range(shared.journal_entries.size()):
		var entry: Dictionary = shared.journal_entries[i]
		var date_info := WarhammerCalendar.decode(int(entry.get("day_of_year", 0)))
		var date_str: String = date_info.display_string() if not date_info.is_intercalary else date_info.holiday_name
		var year: int = int(entry.get("imperial_year", 0))

		var entry_panel := PanelContainer.new()
		journey_box.add_child(entry_panel)
		var entry_margin := MarginContainer.new()
		entry_margin.add_theme_constant_override("margin_left", 10)
		entry_margin.add_theme_constant_override("margin_top", 8)
		entry_margin.add_theme_constant_override("margin_right", 10)
		entry_margin.add_theme_constant_override("margin_bottom", 8)
		entry_panel.add_child(entry_margin)
		var entry_vbox := VBoxContainer.new()
		entry_vbox.add_theme_constant_override("separation", 4)
		entry_margin.add_child(entry_vbox)

		var date_label := Label.new()
		date_label.text = "%s, %d — %s" % [date_str, year, str(entry.get("category", ""))]
		date_label.add_theme_font_size_override("font_size", 11)
		date_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
		entry_vbox.add_child(date_label)

		var title_label := Label.new()
		title_label.text = str(entry.get("title", ""))
		title_label.add_theme_font_size_override("font_size", 15)
		title_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
		title_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		entry_vbox.add_child(title_label)

		var body_label := Label.new()
		body_label.text = str(entry.get("body", ""))
		body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		entry_vbox.add_child(body_label)

		if i < shared.journal_entries.size() - 1:
			journey_box.add_child(HSeparator.new())

## --- Journal tab: Quests sub-tab -----------------------------------------------
## Per the request: a second sub-tab within Journal, separate from the
## story Notes — lists quests and tracks their completion.
func _rebuild_quests() -> void:
	_clear(quests_box)
	## Per the request: Quests and the Journal are shared for the whole
	## group — same shared record the Journal tab above reads from.
	var shared: Character = GameState.party[0] if not GameState.party.is_empty() else character
	if shared == null:
		return
	quests_box.add_child(_header("Quests"))
	if shared.quests.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "No quests yet."
		quests_box.add_child(none_lbl)
		return
	for i in range(shared.quests.size()):
		var quest: Dictionary = shared.quests[i]
		var status: String = str(quest.get("status", "Active"))
		var status_color := Color(0.6, 0.8, 0.55) if status == "Completed" else (Color(0.85, 0.55, 0.5) if status == "Failed" else Color(0.85, 0.7, 0.35))

		var quest_panel := PanelContainer.new()
		quests_box.add_child(quest_panel)
		var quest_margin := MarginContainer.new()
		quest_margin.add_theme_constant_override("margin_left", 10)
		quest_margin.add_theme_constant_override("margin_top", 8)
		quest_margin.add_theme_constant_override("margin_right", 10)
		quest_margin.add_theme_constant_override("margin_bottom", 8)
		quest_panel.add_child(quest_margin)
		var quest_vbox := VBoxContainer.new()
		quest_vbox.add_theme_constant_override("separation", 4)
		quest_margin.add_child(quest_vbox)

		var title_row := HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 8)
		quest_vbox.add_child(title_row)
		var title_label := Label.new()
		title_label.text = str(quest.get("title", "Untitled Quest"))
		title_label.add_theme_font_size_override("font_size", 15)
		title_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_row.add_child(title_label)
		var status_label := Label.new()
		status_label.text = status
		status_label.add_theme_font_size_override("font_size", 12)
		status_label.add_theme_color_override("font_color", status_color)
		title_row.add_child(status_label)

		var desc: String = str(quest.get("description", ""))
		if desc != "":
			var desc_label := Label.new()
			desc_label.text = desc
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			quest_vbox.add_child(desc_label)

		var objectives: Array = quest.get("objectives", [])
		for obj in objectives:
			var obj_label := Label.new()
			var done: bool = bool(obj.get("done", false))
			obj_label.text = "%s %s" % ["✓" if done else "☐", str(obj.get("text", ""))]
			obj_label.add_theme_font_size_override("font_size", 12)
			obj_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55) if done else Color(0.75, 0.7, 0.65))
			quest_vbox.add_child(obj_label)

		## Per the request: Task-specific progress, separate from the
		## generic objectives list above (Tasks don't use objectives at
		## all — see Character.add_task).
		if quest.get("is_task", false):
			var task_label := Label.new()
			var task_type: String = str(quest.get("task_type", ""))
			if task_type == "gather":
				task_label.text = "Progress: %d / %d %s" % [int(quest.get("progress", 0)), int(quest.get("target_count", 1)), str(quest.get("target_key", ""))]
			elif task_type == "find_encounter":
				task_label.text = "Looking for: %s" % str(quest.get("target_key", ""))
			if task_label.text != "":
				task_label.add_theme_font_size_override("font_size", 12)
				task_label.add_theme_color_override("font_color", Color(0.75, 0.7, 0.4))
				quest_vbox.add_child(task_label)

		## Per the request: the Village Elder's own 3-stage chain shows
		## its current stage and that stage's own real progress count.
		if quest.get("quest_id", "") == Character.ELDER_QUEST_ID:
			var stage: int = int(quest.get("elder_stage", 1))
			var stage_label := Label.new()
			stage_label.add_theme_font_size_override("font_size", 12)
			stage_label.add_theme_color_override("font_color", Color(0.75, 0.7, 0.4))
			match stage:
				1:
					stage_label.text = "Stage 1 — Cull the vermin: %d / 8" % int(quest.get("elder_kill_progress", 0))
				2:
					stage_label.text = "Stage 2 — Lend a hand: %d / 4" % int(quest.get("elder_help_progress", 0))
				3:
					stage_label.text = "Stage 3 — Recover the stolen idol"
				_:
					stage_label.text = ""
			if stage_label.text != "":
				quest_vbox.add_child(stage_label)

		if i < shared.quests.size() - 1:
			quests_box.add_child(HSeparator.new())

## --- Shared XP row helper ---------------------------------------------------

## `tooltip_text`, per the request: lets a caller (Talents, below) keep
## the row's own visible label down to just the name/rank, moving a
## longer description into a real hover tooltip instead of cramming it
## into the label text itself. Left blank, this behaves exactly as
## before — no tooltip, default mouse_filter — so every other existing
## caller (Skills, Characteristics) is unaffected.
## Returns the Sell button it created (if any), or null — lets a
## caller that needs to gate Sell behind Test mode (see
## _rebuild_characteristics) track and toggle it live. Every other
## caller (Skills, Talents) just ignores the return value and keeps
## selling normally in the default view.
## Per the request ("I can still see Skill and talent sell buttons,
## hide these and only show in cheat mode"): every Sell button this
## builds — Characteristics, Skills, Talents, the "(Any)" slot
## pickers, all of it — is gated behind Test mode here, in one place,
## rather than requiring each caller to opt in individually the way
## Characteristics alone used to. Hidden during normal play, shown
## only while Shift+Control (the same gesture that reveals the XP
## cheat button) is held; tracked in _gated_sell_buttons so _process
## can toggle them live without a rebuild.
## Per the request: `red` marks a stat currently reduced below its own
## base value by a temporary effect (a Critical Wound penalty,
## Encumbrance's Agility malus, or any other source that runs through
## Character.get_effective_characteristic_value()) — a clear "this isn't
## really your full stat right now" cue, distinct from the unrelated
## "can't afford this" red the Buy button's own disabled state already
## conveys some other way.
func _add_xp_row(container: VBoxContainer, label_text: String, cost: int, on_press: Callable,
		sell_cost: int = -1, on_sell: Callable = Callable(), tooltip_text: String = "", red: bool = false) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if red:
		label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
	if tooltip_text != "":
		label.tooltip_text = tooltip_text
		## Label defaults to MOUSE_FILTER_IGNORE, which never receives
		## hover events at all — needed here so the tooltip actually
		## triggers on mouseover.
		label.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(label)
	var sell_button: Button = null
	if sell_cost >= 0 and on_sell.is_valid():
		sell_button = Button.new()
		sell_button.text = "Sell (+%d XP)" % sell_cost
		sell_button.pressed.connect(on_sell)
		sell_button.visible = Input.is_key_pressed(KEY_SHIFT) and Input.is_key_pressed(KEY_CTRL)
		row.add_child(sell_button)
		_gated_sell_buttons.append(sell_button)
	if on_press.is_valid():
		var button := Button.new()
		button.text = "Buy (%d XP)" % cost
		button.disabled = character.get_experience_available() < cost
		button.pressed.connect(on_press)
		row.add_child(button)
	container.add_child(row)
	return sell_button

func _parse_skill_display_name(display_name: String) -> Array:
	var base_name := display_name
	var specialisation := ""
	var paren := display_name.find(" (")
	if paren != -1:
		base_name = display_name.substr(0, paren)
		specialisation = display_name.substr(paren + 2, display_name.length() - paren - 3)
	var skill_def: SkillDefinition = GameData.skill_db.find_by_name(base_name)
	return [skill_def, specialisation]

func _buy_characteristic(key: String) -> void:
	Advancement.purchase_characteristic_advance(character, key)
	_rebuild_all()

func _sell_characteristic(key: String) -> void:
	Advancement.sell_characteristic_advance(character, key)
	_rebuild_all()

func _buy_skill(skill_def: SkillDefinition, specialisation: String) -> void:
	Advancement.purchase_skill_advance(character, skill_def, specialisation)
	_rebuild_all()

## Renders every "(Any)" skill slot for this qualifier — a career can
## grant the same one (e.g. "Melee (Any)") more than once across
## different Career Levels (Warrior Priest gets it at both Tier 1 and
## Tier 2), and each occurrence is a genuinely separate one-time
## choice, not a repeat of the same slot. Shows one normal buy/sell row
## per distinct choice the player has already made, plus one fresh
## picker for each slot still unfilled.
## `concrete_display_names` (built by _rebuild_skills): skips re-showing
## a resolved variant here if it's already being shown as an ordinary
## row elsewhere (the current Career lists it directly, or it carried
## over from a past one) — same underlying skill, same shared
## skill_advances entry, so one row is enough.
## Per the follow-up request ("Melee (Any) chosen for a previous
## learned Melee Skill, which should be an allowed option"): a slot's
## picker used to exclude every choice the character had ANY existing
## advances in at all, including ones known through a totally unrelated
## route — silently blocking a real, legal choice ("pick the Melee
## skill you already know"). Every choice is offered now; what actually
## keeps multiple slots of the same qualifier from trivially "buying"
## themselves for free by repeatedly re-picking an already-known variant
## is skill_any_purchases (a real per-qualifier spent-slot counter, see
## Character's own comment on it), not picker exclusion.
## Per the follow-up request ("copy the grid format in Inventory tab to
## Characteristics and Skill subtabs"): targets the shared Skills grid
## (see _add_stat_grid_row) instead of a plain VBoxContainer — a
## resolved choice renders as a normal grid row, and a still-open slot
## renders its own grid row with an HBoxContainer(label + picker) in
## the Skill column and a live-updating Buy button in the Train column,
## same 4 boxed cells as every other row so it lines up with the rest
## of the grid.
func _add_any_skill_grid_rows(grid: GridContainer, entry: String, slot_count: int = 1, concrete_display_names: Dictionary = {}) -> void:
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
		## Per _add_stat_grid_row's own compact-mode comment: this helper
		## is only ever called from the two-column Skills sub-tab (see
		## its sole call site above in _rebuild_skills), so compact=true
		## unconditionally here — same reasoning as the other Skills rows.
		_add_stat_grid_row(grid, true, chosen, "%d" % current, already,
			cost, func(): _buy_skill(skill_def, specialisation), sell_cost, func(): _sell_skill(skill_def, specialisation),
			false, "", true)

	## How many of this qualifier's own slots are actually still open
	## can't just be "how many distinct group-variants have advances" —
	## a variant that's concretely known through a totally different
	## route (this exact scenario: Pit Fighter's own Tier 1 lists both
	## "Melee (Any)" and "Melee (Brawling)" at once) would otherwise look
	## like this qualifier's own slot got auto-spent the moment the
	## player buys ordinary Brawling advances, silently taking the slot
	## away before the player ever got to choose anything with it.
	## any_only_chosen strips those out, counting only variants that
	## genuinely came from resolving one of THIS qualifier's own slots.
	## slots_spent then also takes skill_any_purchases (the real
	## per-qualifier Buy-click counter) as a floor, since two separate
	## slots can legitimately both resolve to the SAME already-known
	## skill now — any_only_chosen's distinct-variant count alone
	## wouldn't tell those apart from just one slot having been used.
	var any_only_chosen := chosen_list.filter(func(c): return not concrete_display_names.has(c))
	var slots_spent: int = maxi(character.skill_any_purchases.get(entry, 0), any_only_chosen.size())
	var remaining_slots := slot_count - slots_spent
	for i in range(remaining_slots):
		var all_choices := Advancement.get_skill_situation_choices(entry)

		## --- Career column: an open "(Any)" slot is always available. --
		grid.add_child(_boxed_cell(_career_tick_button(true), 0, _STAT_GRID_COLUMNS))

		## --- Name column: the qualifier's own label. --------------------
		## Per the request: drop the redundant "— choose one:" suffix —
		## the OptionButton picker right next to it already makes clear
		## a choice is being made, so the label just names the slot.
		var label := Label.new()
		label.text = entry
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(_boxed_cell(label, 1, _STAT_GRID_COLUMNS, true))

		## --- Value column: the picker itself. ----------------------------
		var picker := OptionButton.new()
		for choice in all_choices:
			picker.add_item(choice)
		grid.add_child(_boxed_cell(picker, 2, _STAT_GRID_COLUMNS))

		## --- Advances column: nothing purchased yet for an open slot. --
		var adv_label := Label.new()
		adv_label.text = "—"
		adv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(_boxed_cell(adv_label, 3, _STAT_GRID_COLUMNS))

		## --- Train column: Buy tracks whichever choice is selected. ----
		var parsed_entry := Advancement.parse_skill_entry(entry)
		var base_skill_def: SkillDefinition = parsed_entry[0]
		var buy_btn := Button.new()
		## Per the same follow-up request: the Buy button's own cost now
		## tracks whichever choice is actually selected — picking an
		## already-known skill correctly shows (and charges) that
		## skill's real next-advance price instead of always assuming a
		## brand new skill starting from 0 advances.
		var refresh_buy_button := func():
			if picker.item_count == 0 or base_skill_def == null:
				buy_btn.text = "N/A"
				buy_btn.disabled = true
				return
			var selected_display := base_skill_def.display_name(picker.get_item_text(picker.selected))
			var selected_already: int = character.skill_advances.get(selected_display, 0)
			var live_cost := Advancement.get_skill_advance_cost(selected_already)
			## Per the request: just the XP cost, no "Buy" prefix — see
			## _add_stat_grid_row's own matching comment.
			buy_btn.text = "%d XP" % live_cost
			buy_btn.disabled = character.get_experience_available() < live_cost
		picker.item_selected.connect(func(_idx): refresh_buy_button.call())
		refresh_buy_button.call()
		buy_btn.pressed.connect(func():
			if picker.item_count > 0 and base_skill_def != null:
				Advancement.purchase_skill_advance(character, base_skill_def, picker.get_item_text(picker.selected), false, entry)
				_rebuild_all()
		)
		var train_row := HBoxContainer.new()
		train_row.add_child(buy_btn)
		grid.add_child(_boxed_cell(train_row, 4, _STAT_GRID_COLUMNS))

func _sell_skill(skill_def: SkillDefinition, specialisation: String) -> void:
	Advancement.sell_skill_advance(character, skill_def, specialisation)
	_rebuild_all()

func _buy_talent(talent_name: String) -> void:
	Advancement.purchase_talent_advance(character, talent_name)
	_rebuild_all()

## Renders one "(Any)" talent slot into the Talents grid: if the player
## already picked a specific qualifier for it, shows a normal grid row
## for that exact choice (same as any other talent row). If not, shows
## its own grid row with an HBoxContainer(label + picker) in the Talent
## column and a live-updating Buy button in the Train column — same
## shape as _add_any_skill_grid_rows' own still-open-slot row, but
## simpler: a talent "(Any)" qualifier only ever tracks ONE choice
## (find_chosen_variant returns a single String, not a list), unlike
## Skills' own qualifiers which can grant several slots of the same
## entry across different Career Levels.
func _add_any_talent_grid_row(grid: GridContainer, entry: String) -> void:
	var chosen := Advancement.find_chosen_variant(character, entry)
	if chosen != "":
		var td: TalentDefinition = GameData.talent_db.find_by_name(chosen)
		var rank := character.get_talent_rank(chosen)
		var max_rank := td.get_max_rank(character) if td else 1
		var value_text := "rank %d / %d" % [rank, max_rank]
		var tooltip := td.summary if td else ""
		var sell_cost := Advancement.get_talent_advance_cost(max(rank - 1, 0)) if rank > 0 else -1
		if rank >= max_rank:
			_add_stat_grid_row(grid, true, chosen, value_text, rank, -1, Callable(), sell_cost, func(): _sell_talent(chosen), false, tooltip)
		else:
			var cost := Advancement.get_talent_advance_cost(rank)
			var parked_reason := td.parked_reason if td != null and td.mechanically_parked else ""
			_add_stat_grid_row(grid, true, chosen, value_text, rank, cost, func(): _buy_talent(chosen), sell_cost, func(): _sell_talent(chosen), false, tooltip, false, parked_reason)
		return

	var choices := Advancement.get_situation_choices(entry)

	## --- Career column: an open "(Any)" slot is always available. -------
	grid.add_child(_boxed_cell(_career_tick_button(true), 0, _STAT_GRID_COLUMNS))

	## --- Name column: the qualifier's own label. -------------------------
	## Per the request: drop the redundant "— choose one:" suffix — see
	## the matching comment in _add_any_skill_grid_rows above.
	var label := Label.new()
	label.text = entry
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_boxed_cell(label, 1, _STAT_GRID_COLUMNS, true))

	## --- Value column: the picker itself. --------------------------------
	var picker := OptionButton.new()
	for choice in choices:
		picker.add_item(choice)
	grid.add_child(_boxed_cell(picker, 2, _STAT_GRID_COLUMNS))

	## --- Advances column: nothing purchased yet for an open slot. -------
	var adv_label := Label.new()
	adv_label.text = "—"
	adv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(_boxed_cell(adv_label, 3, _STAT_GRID_COLUMNS))

	## --- Train column: a flat-cost Buy (talent's own first-rank price). -
	## Per the request: just the XP cost, no "Buy" prefix.
	var cost := Advancement.get_talent_advance_cost(0)
	var buy_btn := Button.new()
	buy_btn.text = "%d XP" % cost
	buy_btn.disabled = character.get_experience_available() < cost or choices.is_empty()
	## A parked base Talent (mechanically_parked -- see that field's doc
	## comment) still shows its "(Any)" picker (so the qualifier choices
	## stay visible/documented) but the Buy button stays forced-disabled
	## with an explanatory tooltip, same as the resolved-choice path above.
	var base_td: TalentDefinition = GameData.talent_db.find_by_name(entry)
	if base_td != null and base_td.mechanically_parked:
		buy_btn.disabled = true
		buy_btn.tooltip_text = base_td.parked_reason
		buy_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	buy_btn.pressed.connect(func():
		if picker.item_count > 0:
			_buy_talent_choice(entry, picker.get_item_text(picker.selected))
	)
	var train_row := HBoxContainer.new()
	train_row.add_child(buy_btn)
	grid.add_child(_boxed_cell(train_row, 4, _STAT_GRID_COLUMNS))

func _buy_talent_choice(entry: String, chosen_situation: String) -> void:
	Advancement.purchase_talent_advance(character, entry, chosen_situation)
	_rebuild_all()

func _sell_talent(talent_name: String) -> void:
	Advancement.sell_talent_advance(character, talent_name)
	_rebuild_all()

func _change_career(target_career: CareerDefinition, target_tier: int) -> void:
	Advancement.change_career(character, target_career, target_tier)
	_rebuild_all()

## --- Switch Character tab ----------------------------------------------------
## No manual "Save" anymore — the game autosaves continuously (every
## step in the overworld, and whenever this menu closes; see
## GameState.autosave). This tab is purely for switching to a different
## saved character, or deleting one. Kept as its own tab (rather than
## folded into Group, which is about the CURRENT playthrough's party)
## since the Pause Menu's own Switch button opens straight into it —
## see overworld.gd's SWITCH_CHARACTER_TAB_INDEX.

func _rebuild_save_load() -> void:
	_clear(save_load_box)
	if character == null:
		return
	var note := Label.new()
	note.text = "Your progress is saved automatically as you play — there's no manual Save anymore. Switching characters saves your current one first."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	save_load_box.add_child(note)

	for slot in range(SaveManager.SLOT_COUNT):
		save_load_box.add_child(HSeparator.new())
		var is_current := slot == GameState.current_slot
		save_load_box.add_child(_header("Slot %d%s" % [slot + 1, " (current)" if is_current else ""]))
		var summary := SaveManager.get_save_summary(slot)
		var info := Label.new()
		if summary.is_empty():
			info.text = "(empty — create a new character from the start screen)"
		else:
			info.text = "%s, Wounds %d/%d — saved %s" % [
				", ".join(summary["party_names"]), summary["wounds_current"], summary["wounds_max"],
				summary["saved_at"],
			]
		save_load_box.add_child(info)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var switch_btn := Button.new()
		switch_btn.text = "Currently Playing" if is_current else "Switch to This Character"
		switch_btn.disabled = summary.is_empty() or is_current
		switch_btn.pressed.connect(func(): _on_switch_pressed(slot))
		row.add_child(switch_btn)

		var delete_btn := Button.new()
		delete_btn.text = "Delete"
		delete_btn.disabled = summary.is_empty() or is_current
		delete_btn.pressed.connect(func(): _on_delete_pressed(slot))
		row.add_child(delete_btn)

		save_load_box.add_child(row)

func _on_switch_pressed(slot: int) -> void:
	## Autosave the character we're leaving before switching away — the
	## per-step/menu-close autosave should already cover this, but a
	## deliberate switch is a natural checkpoint worth saving at
	## explicitly too.
	GameState.autosave()
	var out_index: Array = [0]
	var out_dismissed: Array = [[]]
	var loaded_party := SaveManager.load_party(slot, out_index, out_dismissed)
	if loaded_party.is_empty():
		return
	GameState.party = loaded_party
	GameState.active_party_index = clampi(out_index[0], 0, loaded_party.size() - 1)
	GameState.dismissed_companions = out_dismissed[0]
	GameState.current_slot = slot
	GameState.reset_session_state()
	close()
	## Follow-up request's own reported bug ("its not saving the city
	## still") — same fix as MainMenu's own _on_continue_pressed: route
	## into the switched-to character's own last active city (just
	## restored by load_party() above) instead of always defaulting to
	## Overworld. See that function's own comment for the full story.
	if GameState.last_active_city_id != "":
		GameState.pending_city_id = GameState.last_active_city_id
		get_tree().change_scene_to_file("res://scenes/CityScreen.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Overworld.tscn")

## Per the request: Delete now warns before it actually deletes,
## matching the same confirm-overlay pattern the Group tab's Dismiss
## and the Trappings step's overwrite warning already use — a
## permanent deletion is exactly the kind of action that shouldn't be
## one accidental misclick away.
func _on_delete_pressed(slot: int) -> void:
	var summary := SaveManager.get_save_summary(slot)
	var names: String = ", ".join(summary.get("party_names", []))
	_open_confirm("Delete Save?",
		"Delete Slot %d (%s)? This can't be undone." % [slot + 1, names],
		func(): _do_delete(slot))

func _do_delete(slot: int) -> void:
	SaveManager.delete_save(slot)
	_rebuild_save_load()
