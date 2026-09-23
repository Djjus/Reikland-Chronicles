extends Control
## Camp rework, per the request: a full party rest/recovery screen —
## every party member gets their own status box (Wounds/Fortune/
## Corruption/Conditions/Critical Wounds), any character with the Heal
## Skill can spend it on anybody in the group (4-real-hour cooldown per
## recipient, cleared the moment a battle starts — see Character's own
## last_heal_skill_time_minutes), and a Camp Endeavour system (Rough
## Nights & Hard Days-style: 1-hour sessions, every living party member
## picks one thing to do) drives Make Camp / Cook / Hunt / Trap. A Full
## Night's Sleep now requires Make Camp completed and a Meal per person
## rather than being unconditional, and recovers Wounds via a per-
## character Endurance Test (+ Toughness Bonus) instead of an automatic
## full heal.
##
## Per the follow-up layout request: two columns — Party on the left,
## Camp Endeavours on the right — built as a single GridContainer(2
## columns) so each character's Endeavour cell genuinely lines up
## (same row, matched row height) with that character's own status box
## rather than just sharing the same order. Item modifiers that would
## apply to the currently-selected Endeavour are shown as small
## colour-swatch chips before the player commits to a roll, and every
## selectable test shows its actual Target number right in the option
## text. Sleep moved to the bottom of the screen, under both columns,
## and shows explicit Make Camp / Food status chips rather than only a
## tooltip on the disabled button. Sleep and Heal outcomes now surface
## as a modal "Result" popup (Continue to dismiss) instead of only
## updating the small top-of-screen message label, since that label
## can easily scroll out of view now that Sleep lives at the bottom of
## a taller, scrollable screen.
##
## Every button on this screen is deliberately compact (smaller font,
## tighter padding) rather than using the default theme size — this
## screen packs in a lot more than the original single-character
## version did, so keeping every control small is what lets it all fit
## without turning into a wall of scrolling.

@onready var close_button: Button = %CloseButton
@onready var status_label: Label = %StatusLabel
@onready var message_label: Label = %MessageLabel
@onready var content_box: VBoxContainer = %ContentBox
@onready var scenery_rect: TextureRect = %SceneryRect

const FIRE_FRAMES := [
	preload("res://assets/sprites/camp_scene_1.png"),
	preload("res://assets/sprites/camp_scene_2.png"),
	preload("res://assets/sprites/camp_scene_3.png"),
]
var _fire_frame_index := 0
var _fire_timer := 0.0
const FIRE_FRAME_SECONDS := 0.35   ## a lively but not frantic flicker

const BUTTON_FONT_SIZE := 12
const SMALL_FONT_SIZE := 10
const HEADER_FONT_SIZE := 14
const ROW_SEPARATION := 4

## Per the request ("use the new portraits in all Icon, in and out of
## combat"): the old wound-tier PLAYER_PORTRAITS table is gone — see
## _portrait_for() below, now backed by CareerPortraits instead.

## Per the request: "make all in-game Food items (not drink) count as a
## meal for now" — computed from the real item database (category ==
## "Food") rather than a hardcoded list, minus the two Food-category
## items that are actually drinks. New Food items added to the database
## later automatically count too, without this screen needing an update.
const MEAL_EXCLUDE_ITEMS := ["Ale, pint", "Wine, bottle"]

## Heal Skill (not Magic/Prayer): "can only be used once every 4 hrs on
## each character" — see Character.last_heal_skill_time_minutes.
const HEAL_COOLDOWN_MINUTES := 4 * 60

## Hunting endeavour: grouped by Test Difficulty per the request ("group
## by Test Difficulty rather than treat them separately and allow the
## player to select the difficulty they want to hunt at") — collapses
## the source table's per-terrain rows into 4 selectable bands, named
## and re-keyed per the follow-up request (Small/Medium/Large/Very
## Large Game rather than the raw difficulty names). Terrain is
## deliberately not modelled — the request explicitly said to group
## past it. Rat was dropped from Small Game per the follow-up request
## (Grouse's Days of Food was bumped to 1 in VALUE_OF_GAME below to
## compensate for the lost easy catch).
const HUNTING_BANDS := [
	{"key": "small_game", "label": "Small Game (-0)", "modifier": 0,
		"animals": ["Badger", "Chicken", "Grouse", "Rabbit", "Beaver"]},
	{"key": "medium_game", "label": "Medium Game (-10)", "modifier": -10,
		"animals": ["Mountain Goat", "Wild Boar", "Wolf"]},
	{"key": "large_game", "label": "Large Game (-20)", "modifier": -20,
		"animals": ["Bear", "Small Deer"]},
	{"key": "very_large_game", "label": "Very Large Game (-30)", "modifier": -30,
		"animals": ["Large Deer"]},
]

## "THE VALUE OF GAME" table (Days of Food column) — a successful Hunt
## rolls a random animal from the chosen band's list per kill (see
## _resolve_hunt's animal_count), then grants that many Uncooked Meat
## (this project has no separate per-animal food item, so "Days of
## Food" converts directly into that many units of the one generic
## Uncooked Meat item — 1 unit == 1 person-day, same convention the
## Trap Endeavour uses).
const VALUE_OF_GAME := {
	"Grouse": 1.0, "Chicken": 1.0, "Rabbit": 1.0,
	"Beaver": 1.0, "Badger": 1.0,
	"Mountain Goat": 15.0, "Wild Boar": 15.0, "Wolf": 6.0,
	"Bear": 20.0, "Small Deer": 15.0, "Large Deer": 25.0,
}

var _heal_def: SkillDefinition
var _outdoor_survival_def: SkillDefinition
var _set_trap_def: SkillDefinition
var _trade_def: SkillDefinition
var _endurance_def: SkillDefinition
## Per the follow-up request: the Heal button now also appears for
## characters who know the "Blessing of Healing" prayer (in addition to
## the Heal skill) — cached the same way as _heal_def.
var _pray_def: SkillDefinition
var _blessing_of_healing: PrayerDefinition

## Per the follow-up request: short nap defaults to 1 hour (was 8,
## which happened to match the Full Night's Sleep threshold and made
## the short-nap button start out disabled).
var sleep_hours: int = 1

## Per-camp-visit state — deliberately NOT persisted (matches how
## sleep_hours above already behaves): a fresh camp session naturally
## starts every time this screen is opened, same as before.
## Per the follow-up request ("failing the make camp roll does not
## stop the camp from being made, it only removes the +20 for the
## Endurance test"): _make_camp_attempted just means "Make Camp was
## rolled this visit" (win or lose) — it's what gates re-selecting the
## Endeavour and what unblocks Full Night's Sleep. _make_camp_succeeded
## is the separate, stricter flag ("the roll actually succeeded") that
## only gates the +20 Endurance bonus.
var _make_camp_attempted := false
var _make_camp_succeeded := false
## Per the follow-up request: unlike Make Camp, Cook is NOT a once-per-
## visit action any more — it's available any hour there's Uncooked
## Meat on hand (see the picker's own condition below), so a party can
## Hunt more raw meat mid-visit and Cook it again. No completed-flag
## needed for it any more.
## Trap Endeavour reward is deferred ("the next morning") — accumulated
## here and only actually granted when a real Full Night's Sleep
## completes; lost if the party breaks camp without sleeping.
var _pending_trap_food_days := 0

## Character -> String ("rest"/"make_camp"/"cook"/"hunt"/"trap") or, for
## a Hunting assist, the literal Character being assisted.
var _endeavour_choice: Dictionary = {}
## Character -> hunting band key (only meaningful while _endeavour_
## choice[character] == "hunt").
var _hunt_band_choice: Dictionary = {}
## Per the follow-up request: the Heal button/selector now lives on
## the HEALER's own box (not the wounded target's), so this maps
## Healer Character -> chosen wounded-target Character instead of the
## other way around.
var _heal_target_choice: Dictionary = {}

## Per the follow-up request: "move endeavour results into the boxes
## they were made from" — each functional character's own Endeavour
## cell now shows the outcome of whatever THEY did last session,
## instead of one combined log line up in the shared MessageLabel.
## Character -> result text / whether it was a success (for colour).
## Reset (cleared) at the start of every _on_run_endeavour_session, so
## a character who Rests this hour doesn't keep showing a stale result
## from a previous one.
var _endeavour_result_text: Dictionary = {}
var _endeavour_result_good: Dictionary = {}

## Per the follow-up request: "move rest results to under the short
## nap button" — Sleep/Rest outcomes (both the short nap and either
## Full Night's Sleep option) now render as persistent inline text in
## the Sleep section itself instead of a modal popup, since that
## section is exactly where the player is already looking when they
## trigger one of these.
var _sleep_result_text: String = ""
var _sleep_result_good: bool = true

## Root of the current modal "Result" popup, if one is showing — see
## _show_outcome_popup(). Tracked so _unhandled_input can gate Esc/
## Enter/Space to "dismiss the popup" instead of their normal meaning
## (close the screen / run an Endeavour session) while it's up.
var _outcome_overlay: Control = null

func _ready() -> void:
	close_button.pressed.connect(_on_close)
	GameState.ensure_player_character()
	_heal_def = GameData.skill_db.find_by_name("Heal")
	_outdoor_survival_def = GameData.skill_db.find_by_name("Outdoor Survival")
	_set_trap_def = GameData.skill_db.find_by_name("Set Trap")
	_trade_def = GameData.skill_db.find_by_name("Trade")
	_endurance_def = GameData.skill_db.find_by_name("Endurance")
	_pray_def = GameData.skill_db.find_by_name("Pray")
	_blessing_of_healing = GameData.prayer_db.find_by_name("Blessing of Healing")
	scenery_rect.texture = FIRE_FRAMES[0]
	content_box.add_theme_constant_override("separation", ROW_SEPARATION)
	_rebuild_all()

func _process(delta: float) -> void:
	_fire_timer += delta
	if _fire_timer >= FIRE_FRAME_SECONDS:
		_fire_timer = 0.0
		_fire_frame_index = (_fire_frame_index + 1) % FIRE_FRAMES.size()
		scenery_rect.texture = FIRE_FRAMES[_fire_frame_index]

func _living_party() -> Array[Character]:
	var result: Array[Character] = []
	for member in GameState.party:
		if member.wounds_current > 0:
			result.append(member)
	return result

## Living AND able to act this hour — excludes Unconscious, which still
## shows up in the party boxes (and can still be a Heal target) but
## can't be assigned an Endeavour.
func _functional_party() -> Array[Character]:
	var result: Array[Character] = []
	for member in _living_party():
		if not member.conditions.has("Unconscious"):
			result.append(member)
	return result

func _rebuild_all() -> void:
	status_label.text = "Time %s — %s" % [
		GameState.get_time_string(),
		"In the wilds (Hunting/Trapping available)" if GameState.camp_is_outdoors else "In a settlement (no Hunting/Trapping here)",
	]
	_clear(content_box)

	## Per the follow-up request: available Food at a glance, between
	## the top status area and the Party column — useful context before
	## picking Cook/Hunt Endeavours or checking the Sleep section's Food
	## requirement, without digging into individual inventories. Pooled
	## the same way the Sleep/Cook logic already treats food (shared
	## across the whole party).
	content_box.add_child(_header("Food"))
	var food_row := HBoxContainer.new()
	food_row.add_theme_constant_override("separation", 6)
	food_row.add_child(_chip("Uncooked Meat: %d" % _party_item_count("Uncooked Meat"), Color(0.3, 0.22, 0.12), Color(0.55, 0.35, 0.2)))
	food_row.add_child(_chip("Cooked Meal: %d" % _party_item_count("Cooked Meal"), Color(0.16, 0.3, 0.15), Color(0.55, 0.42, 0.22)))
	content_box.add_child(food_row)

	## Per the follow-up request: a small page break between the Food
	## row and the Party/Camp Endeavours headers below it.
	var food_gap := Control.new()
	food_gap.custom_minimum_size = Vector2(0, 10)
	content_box.add_child(food_gap)

	## Per the follow-up layout request: 2 real columns — Party | Camp
	## Endeavours — via a GridContainer so each character's Endeavour
	## cell shares a row (and therefore a matched height) with that
	## character's own status box, rather than being merged into one
	## box or just sharing list order. Camp.tscn's own %ContentBox is
	## already wrapped in a ScrollContainer, so the whole stack (grid +
	## Run button + Sleep) scrolls as one unit.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	content_box.add_child(grid)

	var party_header := _header("Party")
	party_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_header.size_flags_stretch_ratio = 0.42
	grid.add_child(party_header)
	var endeavour_header := _header("Camp Endeavours (1 hour per session)")
	endeavour_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	endeavour_header.size_flags_stretch_ratio = 0.58
	grid.add_child(endeavour_header)

	var functional := _functional_party()
	## Per the follow-up request: Assist is no longer Hunt-only — any
	## endeavour can be assisted, as long as the assisting character
	## has the relevant skill trained. This buckets "who's actively
	## doing X this session" by endeavour type (excluding Rest and
	## excluding anyone who's themselves assisting, per the same
	## Character/String == guard used everywhere else in this file).
	var active_by_type: Dictionary = {"make_camp": [], "cook": [], "hunt": [], "trap": []}
	for member in functional:
		var member_choice = _endeavour_choice.get(member, "rest")
		if not (member_choice is Character) and active_by_type.has(member_choice):
			active_by_type[member_choice].append(member)

	for member in GameState.party:
		var box := _build_character_box(member)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.size_flags_stretch_ratio = 0.42
		grid.add_child(box)

		var cell := _build_endeavour_cell(member, functional.has(member), active_by_type)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_stretch_ratio = 0.58
		grid.add_child(cell)

	if functional.is_empty():
		content_box.add_child(_small_label("Nobody is able to act right now."))
	else:
		## Per the follow-up request: the Run Endeavour Session button
		## moves into the Camp Endeavours column itself (a trailing grid
		## row — the left cell stays an empty spacer purely to keep the
		## GridContainer's 2-column structure intact) rather than
		## stretching full width below both columns, and shrinks to its
		## natural text size (SIZE_SHRINK_CENTER) instead of filling the
		## whole column.
		var run_spacer := Control.new()
		run_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		run_spacer.size_flags_stretch_ratio = 0.42
		grid.add_child(run_spacer)

		var run_col := VBoxContainer.new()
		run_col.add_theme_constant_override("separation", 4)
		run_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		run_col.size_flags_stretch_ratio = 0.58
		var run_btn := _compact_button("Run Endeavour Session (1 Hour)  [Space]")
		run_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		run_btn.pressed.connect(_on_run_endeavour_session)
		run_col.add_child(run_btn)
		run_col.add_child(_small_label("Make Camp can only be completed once per camp visit. Cook, Hunting, and Trapping are always available — Cook needs Uncooked Meat on hand; Hunting/Trapping need to be somewhere outdoors."))
		grid.add_child(run_col)

	content_box.add_child(HSeparator.new())
	_build_sleep_section(content_box)

func _header(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	return lbl

func _compact_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	btn.custom_minimum_size = Vector2(0, 26)
	return btn

func _small_label(text: String, color: Color = Color(0.75, 0.72, 0.66)) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	return lbl

## Same as _small_label but WITHOUT autowrap — real bug found via a
## render screenshot: a word-wrapping Label reports an artificially
## tiny minimum width (it can always wrap down further), so putting
## one in each cell of a GridContainer let the column-width
## computation collapse toward 0, and the un-wrapped text of
## neighbouring cells then rendered on top of each other instead of
## side by side. Use this for any label that lives inside a
## multi-column grid and is short enough it was never going to wrap.
func _stat_label(text: String, color: Color = Color(0.75, 0.72, 0.66)) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	lbl.add_theme_color_override("font_color", color)
	return lbl

## Small colour-tagged pill used for "modifier before you roll" and
## "requirement met/missing" previews — a stand-in for real item/status
## icons (this project has no per-item icon assets), a colour swatch
## plus short text reads as a compact "icon and text" at a glance
## without needing new art or relying on emoji glyph support from the
## pixel font.
func _chip(text: String, bg_color: Color, swatch_color: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", style)
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	chip.add_child(inner)
	if swatch_color.a > 0.0:
		var swatch := ColorRect.new()
		swatch.color = swatch_color
		swatch.custom_minimum_size = Vector2(8, 8)
		inner.add_child(swatch)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	inner.add_child(lbl)
	return chip

func _portrait_for(member: Character) -> Texture2D:
	## Per the request ("use the new portraits in all Icon, in and out of
	## combat"): this member's own Career portrait, not the old generic
	## wound-tier art PLAYER_PORTRAITS held.
	return CareerPortraits.get_portrait_for_character(member)

## --- Party status boxes -------------------------------------------------

func _build_character_box(member: Character) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.11, 0.08)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	if member.wounds_current <= 0:
		panel.modulate = Color(0.55, 0.55, 0.55, 1)
	panel.add_theme_stylebox_override("panel", style)

	## Per the follow-up request: the portrait now fills the entire left
	## side of the box (full height) instead of a small icon up in the
	## header row. Everything else — name, HP bar, and the rest of the
	## character's data — lives in a column to its right.
	var outer_hbox := HBoxContainer.new()
	outer_hbox.add_theme_constant_override("separation", 8)
	panel.add_child(outer_hbox)

	var portrait := TextureRect.new()
	portrait.texture = _portrait_for(member)
	## Per the follow-up request ("add a red tint at low health").
	portrait.modulate = CareerPortraits.wound_modulate_for_character(member)
	portrait.custom_minimum_size = Vector2(60, 0)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	## KEEP_ASPECT_COVERED so the portrait fills the full column height
	## (whatever height the rest of the box's content ends up needing)
	## without distorting the art, cropping any excess instead.
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_hbox.add_child(portrait)

	## Per the follow-up request: "space the info out better" — a wider
	## gap between rows than the original cramped 3px, now that the box
	## also carries Fate/Fortune/Resilience/Resolve.
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_hbox.add_child(vbox)

	## Per the follow-up request: HP bar moved to its own row under the
	## name (instead of sharing the top row with it) and made longer,
	## now that it has the whole row's width to itself. The wound count
	## stays embedded as text inside the bar (a Label layered on top of
	## the ProgressBar, centered, ignoring mouse input).
	var name_lbl := Label.new()
	name_lbl.text = "%s — %s" % [member.character_name, member.career.career_name if member.career else "?"]
	name_lbl.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	name_lbl.clip_text = true
	vbox.add_child(name_lbl)

	## Per the follow-up request: the bar was made too long by simply
	## filling the whole row — now it's exactly 25% of the box's width.
	## hp_wrap spans the full row (so it has a real width to measure
	## against); hp_bar_box sits inside it sized via ANCHORS (0%-25%),
	## a fraction of hp_wrap's own rect — this is exact regardless of
	## any child minimum-size quirks, unlike stretch-ratio sizing in a
	## BoxContainer.
	var hp_wrap := Control.new()
	hp_wrap.custom_minimum_size = Vector2(0, 16)
	hp_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(hp_wrap)

	var hp_bar_box := Control.new()
	hp_bar_box.anchor_left = 0.0
	hp_bar_box.anchor_top = 0.0
	hp_bar_box.anchor_right = 0.25
	hp_bar_box.anchor_bottom = 1.0
	hp_wrap.add_child(hp_bar_box)

	var hp_bar := ProgressBar.new()
	hp_bar.max_value = max(member.wounds_max, 1)
	hp_bar.value = member.wounds_current
	hp_bar.show_percentage = false
	hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pct: float = float(member.wounds_current) / float(max(member.wounds_max, 1))
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.2, 0.75, 0.25) if pct > 0.5 else (Color(0.85, 0.65, 0.15) if pct > 0.25 else Color(0.75, 0.15, 0.15))
	fill.corner_radius_top_left = 2
	fill.corner_radius_top_right = 2
	fill.corner_radius_bottom_left = 2
	fill.corner_radius_bottom_right = 2
	hp_bar.add_theme_stylebox_override("fill", fill)
	## Per the follow-up request: an outline around the bar — now that
	## it's short (25% width), a clear border makes its full extent
	## (and therefore how "full" it reads) easier to see at a glance.
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.07, 0.06)
	bg.border_width_left = 1
	bg.border_width_top = 1
	bg.border_width_right = 1
	bg.border_width_bottom = 1
	bg.border_color = Color(0.6, 0.55, 0.4)
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	hp_bar.add_theme_stylebox_override("background", bg)
	hp_bar_box.add_child(hp_bar)
	var wound_lbl := Label.new()
	wound_lbl.text = "%d/%d" % [member.wounds_current, member.wounds_max]
	wound_lbl.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	wound_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	wound_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	wound_lbl.add_theme_constant_override("outline_size", 2)
	wound_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wound_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wound_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	wound_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar_box.add_child(wound_lbl)

	## --- Heal action (this character healing a wounded ally) ---
	## Per the follow-up request: only characters who can actually heal
	## (the Heal skill, or the "Blessing of Healing" prayer) get this
	## control at all — it lives on THEIR OWN box now (not the wounded
	## target's), with a selector to choose which wounded party member
	## to treat.
	##
	## Per the follow-up request ("make the heal buttons float... so
	## they do not interrupt the text to the left of them"): this row
	## is added as a SIBLING of outer_hbox directly on `panel`, not as
	## a vbox child — PanelContainer gives every direct child the same
	## full content rect, so heal_row and outer_hbox overlap rather
	## than stack. SIZE_SHRINK_END/SIZE_SHRINK_BEGIN then dock it to
	## that shared rect's top-right corner, floating over whatever's
	## there instead of pushing the stats/corruption/conditions text
	## below it downward.
	var can_heal_skill: bool = member.has_skill(_heal_def)
	var can_heal_prayer: bool = _blessing_of_healing != null and member.get_effective_known_prayers().has(_blessing_of_healing.prayer_name)
	if can_heal_skill or can_heal_prayer:
		var wounded_targets: Array = []
		for p in _living_party():
			if p.wounds_current < p.wounds_max:
				wounded_targets.append(p)
		if not wounded_targets.is_empty():
			var chosen_target: Character = _heal_target_choice.get(member, wounded_targets[0])
			if not wounded_targets.has(chosen_target):
				chosen_target = wounded_targets[0]

			var heal_row := HBoxContainer.new()
			heal_row.add_theme_constant_override("separation", 6)
			heal_row.size_flags_horizontal = Control.SIZE_SHRINK_END
			heal_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

			if wounded_targets.size() > 1:
				var picker := OptionButton.new()
				picker.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
				for t in wounded_targets:
					picker.add_item(t.character_name)
				picker.selected = wounded_targets.find(chosen_target)
				picker.item_selected.connect(func(idx: int):
					_heal_target_choice[member] = wounded_targets[idx]
					_rebuild_all()
				)
				heal_row.add_child(picker)
			else:
				## _stat_label (non-wrapping) — a wrapping label here
				## collapses to a near-0 width, same overlap bug fixed
				## elsewhere in this box.
				heal_row.add_child(_stat_label("Heal %s:" % chosen_target.character_name))

			## Heal Skill button — subject to the existing per-RECIPIENT
			## 4-hour cooldown (see last_heal_skill_time_minutes's own
			## comment). That original design note explicitly scoped the
			## cooldown to "the heal skill (not spells)", so Blessing of
			## Healing below is NOT subject to it.
			if can_heal_skill:
				var remaining_minutes: int = HEAL_COOLDOWN_MINUTES - (GameState.time_minutes_total() - chosen_target.last_heal_skill_time_minutes)
				if remaining_minutes > 0:
					heal_row.add_child(_stat_label("(cooldown %dh%02dm)" % [remaining_minutes / 60, remaining_minutes % 60], Color(0.7, 0.6, 0.55)))
				else:
					## Per the follow-up request: shortened to just "Heal
					## {target}" — the number already reflects the +20
					## "take their time" bonus (see _on_heal's own
					## resolve call).
					var heal_target_num: int = member.get_skill_value(_heal_def) + 20
					var heal_btn := _compact_button("Heal %d" % heal_target_num)
					heal_btn.pressed.connect(func(): _on_heal(chosen_target, member))
					heal_row.add_child(heal_btn)

			if can_heal_prayer:
				var bless_target_num: int = member.get_skill_value(_pray_def)
				var bless_btn := _compact_button("Bless %d" % bless_target_num)
				bless_btn.pressed.connect(func(): _on_bless_heal(chosen_target, member))
				heal_row.add_child(bless_btn)

			panel.add_child(heal_row)

	## --- Rest of the character's data goes below the name/HP row ---

	## Per the follow-up request: Fate/Fortune/Resilience/Resolve now
	## shown too (previously only Fortune and Corruption) — laid out as
	## a small 2-column grid rather than crammed onto one line, per the
	## "space the info out better" request. Fate and Resilience are the
	## fixed pools (Fate is spent permanently; Resilience is the max
	## Resolve refreshes to); Fortune and Resolve are the day-to-day
	## spendable current/max pair for each.
	## Per the follow-up request: "space out the stats a bit better" —
	## wider gaps both between the two columns and between the two rows.
	## Fortune/Resolve are coloured red when fully spent (0 remaining)
	## since that's the state a player most needs to notice at a glance.
	const STAT_COLOR := Color(0.75, 0.72, 0.66)
	const DEPLETED_COLOR := Color(0.85, 0.35, 0.3)
	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 20)
	stats_grid.add_theme_constant_override("v_separation", 6)
	stats_grid.add_child(_stat_label("Fate %d" % member.fate_points))
	stats_grid.add_child(_stat_label("Fortune %d/%d" % [member.fortune_points, member.get_max_fortune_points()],
		DEPLETED_COLOR if member.fortune_points <= 0 else STAT_COLOR))
	stats_grid.add_child(_stat_label("Resilience %d" % member.resilience))
	stats_grid.add_child(_stat_label("Resolve %d/%d" % [member.resolve, member.resilience],
		DEPLETED_COLOR if member.resolve <= 0 else STAT_COLOR))
	vbox.add_child(stats_grid)

	## Per the follow-up request: Corruption coloured light purple once
	## it's above 0, darkening as it approaches the character's
	## threshold — a quick "how close to trouble" read at a glance.
	## Stays the normal text colour at exactly 0.
	var corruption_threshold: int = member.get_corruption_threshold()
	var corruption_color := Color(0.75, 0.72, 0.66)
	if member.corruption_points > 0:
		var corruption_ratio: float = clamp(float(member.corruption_points) / float(max(corruption_threshold, 1)), 0.0, 1.0)
		corruption_color = Color(0.78, 0.6, 0.88).lerp(Color(0.32, 0.14, 0.4), corruption_ratio)
	vbox.add_child(_small_label("Corruption %d/%d" % [member.corruption_points, corruption_threshold], corruption_color))

	var cond_parts: Array[String] = []
	for cond_name in member.conditions.keys():
		var stacks: int = member.conditions[cond_name]
		cond_parts.append("%s x%d" % [cond_name, stacks] if stacks > 1 else cond_name)
	if not cond_parts.is_empty():
		vbox.add_child(_small_label(", ".join(cond_parts), Color(0.85, 0.75, 0.5)))

	if member.active_critical_wound_count > 0:
		vbox.add_child(_small_label("%d Critical Wound(s):" % member.active_critical_wound_count, Color(0.85, 0.55, 0.5)))
		for penalty in member.critical_wound_penalties:
			var char_keys: Array = penalty["characteristic_bonuses"].keys()
			var detail := ""
			if not char_keys.is_empty():
				var char_key: String = char_keys[0]
				var amount: int = penalty["characteristic_bonuses"][char_key]
				detail = " (%+d %s, %d day(s) left)" % [amount, CharacteristicSet.SHORT_NAMES.get(char_key, char_key), penalty["rounds_remaining"]]
			vbox.add_child(_small_label("  %s%s" % [penalty["name"], detail], Color(0.85, 0.55, 0.5)))
		var untracked: int = member.active_critical_wound_count - member.critical_wound_penalties.size()
		if untracked > 0:
			vbox.add_child(_small_label("  %d other old wound(s), no ongoing penalty" % untracked, Color(0.85, 0.55, 0.5)))

	return panel

## Builds the Camp Endeavours column's cell for one character — a
## panel styled to match that character's own status box so the two
## columns read as a matched pair, per the follow-up request ("i still
## wanted 2 columns, party and camp endeavours"). Placed in the same
## GridContainer row as that character's box (see _rebuild_all), so
## Godot lines the two up by matching that row's height automatically
## — a non-functional member still gets a (shorter) cell here so the
## row count, and therefore the alignment, never drifts out of sync.
func _build_endeavour_cell(member: Character, is_functional: bool, active_by_type: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.08)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	if member.wounds_current <= 0:
		panel.modulate = Color(0.55, 0.55, 0.55, 1)
	panel.add_theme_stylebox_override("panel", style)

	if member.wounds_current <= 0:
		panel.add_child(_small_label("%s: —" % member.character_name))
	elif is_functional:
		panel.add_child(_build_endeavour_picker(member, active_by_type))
	elif member.conditions.has("Unconscious"):
		panel.add_child(_small_label("%s: Unconscious — can't act this hour." % member.character_name, Color(0.7, 0.55, 0.5)))
	else:
		panel.add_child(_small_label("%s: —" % member.character_name))

	return panel

func _on_heal(target: Character, healer: Character) -> void:
	var test := TestResolver.resolve_skill_test(healer, _heal_def, "", 20)
	target.last_heal_skill_time_minutes = GameState.time_minutes_total()
	if test.success:
		var healed: int = max(1, test.success_levels)
		var before := target.wounds_current
		target.wounds_current = min(target.wounds_max, target.wounds_current + healed)
		_show_outcome_popup("%s tends %s's wounds — healed %d Wound(s) (now %d/%d)." % [healer.character_name, target.character_name, target.wounds_current - before, target.wounds_current, target.wounds_max], true)
	else:
		_show_outcome_popup("%s tends %s's wounds, but there's no improvement." % [healer.character_name, target.character_name], false)
	GameState.autosave()
	_rebuild_all()

## Per the follow-up request: characters who know the "Blessing of
## Healing" prayer can also heal an ally — a Pray Test (p.217), same
## resolver used everywhere else prayers are cast, then the prayer's
## own listed effect (+1 Wound, Instant, Touch range) on success.
## Deliberately NOT subject to the Heal Skill's per-recipient 4-hour
## cooldown — that cooldown was scoped to "the heal skill (not spells)"
## from the start (see last_heal_skill_time_minutes's own comment).
func _on_bless_heal(target: Character, healer: Character) -> void:
	var pray_result := PrayerResolver.pray(healer, _blessing_of_healing, 0)
	if pray_result.success:
		var before := target.wounds_current
		target.wounds_current = min(target.wounds_max, target.wounds_current + 1)
		_show_outcome_popup("%s calls on the Blessing of Healing for %s — healed %d Wound(s) (now %d/%d)." % [healer.character_name, target.character_name, target.wounds_current - before, target.wounds_current, target.wounds_max], true)
	else:
		var msg := "%s's prayer for %s goes unanswered." % [healer.character_name, target.character_name]
		if pray_result.fumble and not pray_result.wrath.is_empty():
			var wrath_lines := PrayerResolver.apply_wrath_tags(healer, pray_result.wrath.get("tags", []))
			msg += " Wrath of the Gods: %s" % pray_result.wrath.get("text", "")
			for line in wrath_lines:
				msg += " " + line
		_show_outcome_popup(msg, false)
	GameState.autosave()
	_rebuild_all()

## --- Camp Endeavours ------------------------------------------------

func _party_item_count(item_name: String) -> int:
	var total := 0
	for member in GameState.party:
		total += member.inventory.count(item_name)
	return total

## Removes one instance of `item_name` from wherever it's actually held
## across the whole party — food/supplies are treated as a shared pool
## for Endeavour purposes, same as the reward side (a Hunt's catch just
## goes into whichever character actually did the hunting).
func _consume_party_item(item_name: String) -> bool:
	for member in GameState.party:
		if member.inventory.has(item_name):
			member.inventory.erase(item_name)
			return true
	return false

func _meal_item_names() -> Array[String]:
	var result: Array[String] = []
	for item in GameData.item_db.items:
		if item.category == "Food" and not MEAL_EXCLUDE_ITEMS.has(item.item_name):
			result.append(item.item_name)
	return result

func _pooled_meal_count() -> int:
	var total := 0
	for food_name in _meal_item_names():
		total += _party_item_count(food_name)
	return total

func _consume_one_meal() -> bool:
	for food_name in _meal_item_names():
		if _consume_party_item(food_name):
			return true
	return false

func _band_for_key(key: String) -> Dictionary:
	for b in HUNTING_BANDS:
		if b["key"] == key:
			return b
	return HUNTING_BANDS[0]

## Per the follow-up request: "allow assisting on any endeavour as long
## as the assisting character has a skill learned" — the relevant
## skill depends on which endeavour is being assisted. Cook can be
## rolled with either Outdoor Survival or Trade (Cook) (see
## _resolve_cook), so either qualifies a would-be assister.
func _assist_skill_ok(member: Character, endeavour_key: String) -> bool:
	match endeavour_key:
		"make_camp", "hunt":
			return member.skill_advances.has(_outdoor_survival_def.display_name())
		"cook":
			return member.skill_advances.has(_outdoor_survival_def.display_name()) or member.has_skill(_trade_def, "Cook")
		"trap":
			return member.has_skill(_set_trap_def)
		_:
			return false

func _endeavour_label(endeavour_key: String) -> String:
	match endeavour_key:
		"make_camp":
			return "Make Camp"
		"cook":
			return "Cook"
		"hunt":
			return "Hunt"
		"trap":
			return "Set Trap"
		_:
			return endeavour_key

## Builds the "This Hour:" picker embedded in a functional character's
## own status box — per the follow-up request, each selectable test
## now shows its actual Target number right in the option text, and
## the currently-selected choice shows any item modifiers that would
## apply as small chips before the player commits to a roll. Target
## numbers here are the character's skill value plus item/band
## modifiers only — they deliberately don't duplicate every situational
## Condition penalty (Fatigued, etc.), which the actual roll still
## applies automatically via TestResolver; this is a "what you'd
## expect going in" preview, not a guarantee of the exact roll target.
func _build_endeavour_picker(member: Character, active_by_type: Dictionary) -> VBoxContainer:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 3)
	## Named here (rather than just "This Hour:") since this cell now
	## sits in its own column, separate from the character's own status
	## box in the Party column — per the follow-up request restoring 2
	## real columns instead of one merged box.
	var name_lbl := Label.new()
	name_lbl.text = "%s — This Hour:" % member.character_name
	name_lbl.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	container.add_child(name_lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var picker := OptionButton.new()
	picker.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var option_values: Array = []

	picker.add_item("Rest (no Endeavour)")
	option_values.append("rest")

	if not _make_camp_attempted:
		var bedroll_bonus: int = 5 * _party_item_count("Bedroll")
		var tent_bonus: int = 10 if _party_item_count("Tent") > 0 else 0
		var camp_target: int = member.get_skill_value(_outdoor_survival_def) + bedroll_bonus + tent_bonus
		picker.add_item("Make Camp (Outdoor Survival) — Target %d" % camp_target)
		option_values.append("make_camp")

	## Per the follow-up request: "cook should be available if there is
	## any uncooked food" — no once-per-visit gate any more, unlike Make
	## Camp; Cook simply needs raw meat on hand, whenever that happens
	## to be true.
	if _party_item_count("Uncooked Meat") > 0:
		var pot_bonus: int = 10 if _party_item_count("Cooking Pot") > 0 else 0
		var os_target: int = member.get_skill_value(_outdoor_survival_def) + pot_bonus
		var cook_skill_label := "Outdoor Survival"
		var cook_target := os_target
		if member.has_skill(_trade_def, "Cook"):
			var trade_target: int = member.get_skill_value(_trade_def, "Cook") + 20 + pot_bonus
			if trade_target > os_target:
				cook_target = trade_target
				cook_skill_label = "Trade (Cook)"
		picker.add_item("Cook (%s) — Target %d" % [cook_skill_label, cook_target])
		option_values.append("cook")

	if GameState.camp_is_outdoors:
		picker.add_item("Hunt (Outdoor Survival)")
		option_values.append("hunt")
		if member.has_skill(_set_trap_def):
			var trap_target: int = member.get_skill_value(_set_trap_def)
			picker.add_item("Set Trap (Set Trap) — Target %d" % trap_target)
			option_values.append("trap")

	## Per the follow-up request: "allow assisting on any endeavour as
	## long as the assisting character has a skill learned" — Assist is
	## no longer Hunt-only. Offered for every endeavour someone else is
	## actively doing this session, gated only on the assister having
	## the relevant skill trained (see _assist_skill_ok) — no test of
	## their own, just a flat +10 to the target's roll (see
	## _resolve_make_camp/_resolve_cook/_resolve_hunt/_resolve_trap).
	for endeavour_key in ["make_camp", "cook", "hunt", "trap"]:
		for target in active_by_type.get(endeavour_key, []):
			if target == member:
				continue
			if _assist_skill_ok(member, endeavour_key):
				picker.add_item("Assist %s's %s (+10)" % [target.character_name, _endeavour_label(endeavour_key)])
				option_values.append(target)

	var current_choice = _endeavour_choice.get(member, "rest")
	var selected_index := option_values.find(current_choice)
	if selected_index < 0:
		selected_index = 0
		_endeavour_choice[member] = "rest"
	picker.selected = selected_index
	picker.item_selected.connect(func(idx: int):
		_endeavour_choice[member] = option_values[idx]
		_rebuild_all()
	)
	row.add_child(picker)

	## Comparing a Character (an Assist choice) to the String "hunt"
	## with == throws "Invalid operands" in GDScript rather than just
	## returning false — `is Character` must be ruled out first (see
	## the near-identical guard in _rebuild_all above).
	if not (current_choice is Character) and current_choice == "hunt":
		var band_picker := OptionButton.new()
		band_picker.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
		for band in HUNTING_BANDS:
			var band_target: int = member.get_skill_value(_outdoor_survival_def) + band["modifier"]
			band_picker.add_item("%s — Target %d" % [band["label"], band_target])
		var band_key: String = _hunt_band_choice.get(member, HUNTING_BANDS[0]["key"])
		var band_index := 0
		for i in range(HUNTING_BANDS.size()):
			if HUNTING_BANDS[i]["key"] == band_key:
				band_index = i
				break
		band_picker.selected = band_index
		band_picker.item_selected.connect(func(idx: int):
			_hunt_band_choice[member] = HUNTING_BANDS[idx]["key"]
			_rebuild_all()
		)
		row.add_child(band_picker)

	container.add_child(row)

	if current_choice is Character:
		var target_choice = _endeavour_choice.get(current_choice, "rest")
		var target_label: String = _endeavour_label(target_choice) if not (target_choice is Character) else "?"
		container.add_child(_small_label("Assisting %s's %s — gives +10, no test needed." % [current_choice.character_name, target_label]))
	else:
		var chips := _build_modifier_chips(member, current_choice)
		if chips != null:
			container.add_child(chips)

	## Per the follow-up request: "move endeavour results into the
	## boxes they were made from" — this character's own last-session
	## result (if any) shows right here rather than in a shared
	## top-of-screen message.
	if _endeavour_result_text.has(member):
		container.add_child(_small_label(_endeavour_result_text[member],
			Color(0.75, 0.9, 0.7) if _endeavour_result_good.get(member, true) else Color(0.9, 0.7, 0.65)))

	return container

## Item (and Assist) modifiers that would currently apply to `choice` —
## shown as small chips so the player sees them before rolling, per the
## follow-up request.
func _build_modifier_chips(member: Character, choice) -> Control:
	var chips: Array = []   ## Array of [text, bg_color, swatch_color]
	match choice:
		"make_camp":
			var bedrolls := _party_item_count("Bedroll")
			if bedrolls > 0:
				chips.append(["Bedroll x%d (+%d)" % [bedrolls, bedrolls * 5], Color(0.16, 0.3, 0.15), Color(0.55, 0.42, 0.22)])
			if _party_item_count("Tent") > 0:
				chips.append(["Tent (+10)", Color(0.16, 0.3, 0.15), Color(0.6, 0.55, 0.35)])
		"cook":
			if _party_item_count("Cooking Pot") > 0:
				chips.append(["Cooking Pot (+10)", Color(0.16, 0.3, 0.15), Color(0.4, 0.4, 0.45)])

	## Per the follow-up request: "allow assisting on any endeavour" —
	## the Assisted chip is no longer Hunt-only, it applies to whichever
	## of the 4 active endeavour types `choice` is. Assisting always
	## gives +10 per assisting character, regardless of whether they'd
	## succeed at anything themselves — no "if they succeed" caveat.
	if choice == "make_camp" or choice == "cook" or choice == "hunt" or choice == "trap":
		var assist_count := 0
		for other in GameState.party:
			## Comparing a String choice ("rest"/"make_camp"/...) to a
			## Character with == throws "Invalid operands" in GDScript
			## rather than just returning false — the `is Character`
			## check has to come first so mismatched types short-
			## circuit before the == is ever evaluated.
			var other_choice = _endeavour_choice.get(other)
			if other_choice is Character and other_choice == member:
				assist_count += 1
		if assist_count > 0:
			chips.append(["Assisted x%d (+%d)" % [assist_count, assist_count * 10], Color(0.14, 0.26, 0.32), Color(0.4, 0.6, 0.7)])
	if chips.is_empty():
		return null
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for c in chips:
		row.add_child(_chip(c[0], c[1], c[2]))
	return row

func _on_run_endeavour_session() -> void:
	var functional := _functional_party()

	## Per the follow-up request: Assist works on any of the 4
	## endeavour types now, not just Hunt — assisters are resolved as
	## part of their target's own entry below, not as independent
	## Endeavours, so this just buckets them by who they're helping,
	## same as before.
	var assisters_by_target: Dictionary = {}
	for member in functional:
		var choice = _endeavour_choice.get(member, "rest")
		if choice is Character:
			if not assisters_by_target.has(choice):
				assisters_by_target[choice] = []
			assisters_by_target[choice].append(member)

	## Per the follow-up request: "move endeavour results into the
	## boxes they were made from" — cleared every session so a
	## character who Rests (or is only assisting) this hour doesn't
	## keep showing a stale result from a previous one.
	_endeavour_result_text.clear()
	_endeavour_result_good.clear()

	for member in functional:
		var choice = _endeavour_choice.get(member, "rest")
		var result: Dictionary = {}
		match choice:
			"rest":
				pass
			"make_camp":
				result = _resolve_make_camp(member, assisters_by_target.get(member, []))
			"cook":
				result = _resolve_cook(member, assisters_by_target.get(member, []))
			"hunt":
				result = _resolve_hunt(member, assisters_by_target.get(member, []))
			"trap":
				result = _resolve_trap(member, assisters_by_target.get(member, []))
			_:
				pass   ## a Character value here means "assisting" — handled inside the target's own _resolve_* call above
		if not result.is_empty():
			_endeavour_result_text[member] = result["text"]
			_endeavour_result_good[member] = result["success"]

	## Everyone's choice is spent for this session — reset to Rest so
	## the next session starts fresh rather than silently repeating
	## whatever was picked last time.
	_endeavour_choice.clear()

	GameState.advance_minutes(60)
	GameState.autosave()
	_rebuild_all()

## Per the follow-up request: Assisting always gives +10 per assisting
## character, regardless of whether they'd succeed at anything
## themselves — no separate test for the assisters, just a flat bonus
## to the target's own roll. Shared by all 4 endeavour resolvers below.
func _assist_suffix(assisters: Array) -> String:
	if assisters.is_empty():
		return ""
	var names: Array[String] = []
	for assister in assisters:
		names.append("assisted by %s" % assister.character_name)
	return " (" + ", ".join(names) + ")"

## Per the follow-up request ("move endeavour results into the boxes
## they were made from"): each _resolve_* function below now returns a
## {"text": String, "success": bool} Dictionary instead of a bare
## String, so the caller (_on_run_endeavour_session) can colour the
## result it stores per-character without re-parsing the message text.
func _resolve_make_camp(member: Character, assisters: Array = []) -> Dictionary:
	var bedroll_count: int = _party_item_count("Bedroll")
	var bedroll_bonus: int = 5 * bedroll_count
	var has_tent: bool = _party_item_count("Tent") > 0
	var tent_bonus: int = 10 if has_tent else 0
	var assist_bonus: int = assisters.size() * 10
	var assist_suffix := _assist_suffix(assisters)
	var test := TestResolver.resolve_skill_test(member, _outdoor_survival_def, "", bedroll_bonus + tent_bonus + assist_bonus)

	## Per the follow-up request: a failed roll no longer blocks Sleep
	## at all — camp still gets physically made either way. Attempting
	## it (win or lose) is what gates re-selecting the Endeavour and
	## unblocks Full Night's Sleep; only an actual SUCCESS grants the
	## +20 Endurance bonus (see _on_sleep's own modifier calculation).
	_make_camp_attempted = true

	if test.success:
		_make_camp_succeeded = true
		return {"text": "%s makes camp successfully (SL %+d)%s — ready for a Full Night's Sleep." % [member.character_name, test.success_levels, assist_suffix], "success": true}

	## Per the follow-up request: "a -6 SL or worse on the make camp
	## roll will destroy one of the Make Camp items used if any where
	## used for the roll" — build the list of item COPIES that actually
	## contributed a bonus this attempt (one entry per Bedroll that
	## contributed its own +5, one entry for the Tent if it contributed
	## its +10) and destroy a random one of them on a bad enough miss.
	var destroyed_note := ""
	if test.success_levels <= -6:
		var contributing_items: Array[String] = []
		for i in range(bedroll_count):
			contributing_items.append("Bedroll")
		if has_tent:
			contributing_items.append("Tent")
		if not contributing_items.is_empty():
			var destroyed_item: String = contributing_items[randi() % contributing_items.size()]
			_consume_party_item(destroyed_item)
			destroyed_note = " A %s is ruined in the process." % destroyed_item

	return {"text": "%s tries to make camp, but doesn't find good enough shelter (SL %+d)%s.%s" % [member.character_name, test.success_levels, assist_suffix, destroyed_note], "success": false}

func _resolve_cook(member: Character, assisters: Array = []) -> Dictionary:
	var pot_bonus: int = 10 if _party_item_count("Cooking Pot") > 0 else 0
	var assist_bonus: int = assisters.size() * 10
	var assist_suffix := _assist_suffix(assisters)
	var os_target: int = member.get_skill_value(_outdoor_survival_def) + pot_bonus
	var use_trade := false
	if member.has_skill(_trade_def, "Cook"):
		var trade_target: int = member.get_skill_value(_trade_def, "Cook") + 20 + pot_bonus
		use_trade = trade_target > os_target
	var test: TestResolver.TestResult
	if use_trade:
		test = TestResolver.resolve_skill_test(member, _trade_def, "Cook", 20 + pot_bonus + assist_bonus)
	else:
		test = TestResolver.resolve_skill_test(member, _outdoor_survival_def, "", pot_bonus + assist_bonus)
	if not test.success:
		return {"text": "%s tries to cook the day's meat, but it comes out badly (SL %+d)%s." % [member.character_name, test.success_levels, assist_suffix], "success": false}
	var raw_count: int = _party_item_count("Uncooked Meat")
	for i in range(raw_count):
		_consume_party_item("Uncooked Meat")
		member.inventory.append("Cooked Meal")
	return {"text": "%s cooks %d Uncooked Meat into %d Cooked Meal(s) (SL %+d)%s." % [member.character_name, raw_count, raw_count, test.success_levels, assist_suffix], "success": true}

func _resolve_hunt(hunter: Character, assisters: Array = []) -> Dictionary:
	var band: Dictionary = _band_for_key(_hunt_band_choice.get(hunter, HUNTING_BANDS[0]["key"]))

	var assist_bonus: int = assisters.size() * 10
	var assist_suffix := _assist_suffix(assisters)

	var test := TestResolver.resolve_skill_test(hunter, _outdoor_survival_def, "", band["modifier"] + assist_bonus)
	if not test.success:
		return {"text": "%s hunts for %s but finds nothing (SL %+d)%s." % [hunter.character_name, band["label"], test.success_levels, assist_suffix], "success": false}

	## Per the follow-up request: Small/Medium Game hunts can bag more
	## than one animal on a strong roll — 1 for the success itself, +1
	## more per every additional 2 SL. Large/Very Large Game stays
	## capped at a single kill regardless of SL — you don't bring down
	## two bears in an hour.
	var animal_count := 1
	if band["key"] == "small_game" or band["key"] == "medium_game":
		animal_count += test.success_levels / 2

	var catch_counts: Dictionary = {}
	var total_days := 0.0
	for i in range(animal_count):
		var animal: String = band["animals"][randi() % band["animals"].size()]
		catch_counts[animal] = catch_counts.get(animal, 0) + 1
		total_days += VALUE_OF_GAME.get(animal, 1.0)

	var qty: int = max(1, int(round(total_days)))
	for i in range(qty):
		hunter.inventory.append("Uncooked Meat")

	var catch_parts: Array[String] = []
	for animal in catch_counts.keys():
		var n: int = catch_counts[animal]
		catch_parts.append("%dx %s" % [n, animal] if n > 1 else animal)

	return {"text": "%s hunts for %s and brings back %s — %d Uncooked Meat (SL %+d)%s." % [hunter.character_name, band["label"], ", ".join(catch_parts), qty, test.success_levels, assist_suffix], "success": true}

func _resolve_trap(member: Character, assisters: Array = []) -> Dictionary:
	var assist_bonus: int = assisters.size() * 10
	var assist_suffix := _assist_suffix(assisters)
	var test := TestResolver.resolve_skill_test(member, _set_trap_def, "", assist_bonus)
	if not test.success:
		return {"text": "%s sets traps, but they'll likely turn up empty (SL %+d)%s." % [member.character_name, test.success_levels, assist_suffix], "success": false}
	var days: int = max(1, test.success_levels)
	_pending_trap_food_days += days
	return {"text": "%s sets traps — expect %d day(s) worth of food in the morning (SL %+d)%s." % [member.character_name, days, test.success_levels, assist_suffix], "success": true}

## --- Sleep (moved to the bottom of the screen, per the follow-up request) ----

func _build_sleep_section(container: VBoxContainer) -> void:
	container.add_child(_header("Sleep"))
	var hours_row := HBoxContainer.new()
	hours_row.add_theme_constant_override("separation", 8)
	var minus_btn := _compact_button("−1 hr")
	minus_btn.disabled = sleep_hours <= 1
	minus_btn.pressed.connect(func(): sleep_hours = max(1, sleep_hours - 1); _rebuild_all())
	hours_row.add_child(minus_btn)
	var hours_lbl := Label.new()
	hours_lbl.text = "%d hour%s" % [sleep_hours, "s" if sleep_hours != 1 else ""]
	hours_lbl.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	hours_lbl.custom_minimum_size = Vector2(70, 0)
	hours_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hours_row.add_child(hours_lbl)
	var plus_btn := _compact_button("+1 hr")
	plus_btn.disabled = sleep_hours >= 24
	plus_btn.pressed.connect(func(): sleep_hours = min(24, sleep_hours + 1); _rebuild_all())
	hours_row.add_child(plus_btn)
	container.add_child(hours_row)

	## Per the follow-up request: every button in this section shrinks to
	## its natural text size (SIZE_SHRINK_BEGIN) instead of stretching
	## full width — matches the Run Endeavour Session button's own
	## shrink treatment above.
	var sleep_btn := _compact_button("Sleep %d Hour%s (short nap)" % [sleep_hours, "s" if sleep_hours != 1 else ""])
	sleep_btn.disabled = sleep_hours >= 8
	sleep_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sleep_btn.pressed.connect(func(): _on_sleep(sleep_hours * 60, false))
	container.add_child(sleep_btn)

	## Per the follow-up request: "move rest results to under the short
	## nap button" — the outcome of the last Sleep/Rest action (short
	## nap or either Full Night's Sleep option) now shows right here as
	## persistent inline text instead of a modal popup.
	if not _sleep_result_text.is_empty():
		container.add_child(_small_label(_sleep_result_text, Color(0.75, 0.9, 0.7) if _sleep_result_good else Color(0.9, 0.7, 0.65)))

	## Per the follow-up request: a small page break after the short nap
	## button — separates the "do this now" action from the status
	## chips/Full Night's Sleep block below it.
	var sleep_gap := Control.new()
	sleep_gap.custom_minimum_size = Vector2(0, 10)
	container.add_child(sleep_gap)

	var meals_needed: int = _functional_party().size()
	## Per the request: a Full Night's Sleep now requires Make Camp
	## completed and a Meal — "make all in-game food items (not drink)
	## count as a meal for now" — one per living party member, pooled
	## from the whole party's combined inventory.
	var meals_available: int = _pooled_meal_count()

	## Per the follow-up request: show what's actually missing for a
	## Full Night's Sleep as always-visible status chips, not just a
	## tooltip on the disabled button (easy to miss). Per the follow-up
	## request ("failing the make camp roll does not stop the camp from
	## being made"), this chip now has 3 states, not 2 — a FAILED
	## attempt still counts as "camp made" for Sleep purposes, it just
	## doesn't earn the Endurance bonus, so it gets its own distinct
	## middle state rather than reading as "Missing".
	var make_camp_chip_text := "Make Camp: Missing"
	var make_camp_chip_color := Color(0.35, 0.16, 0.14)
	if _make_camp_succeeded:
		make_camp_chip_text = "Make Camp: Done"
		make_camp_chip_color = Color(0.16, 0.3, 0.15)
	elif _make_camp_attempted:
		make_camp_chip_text = "Make Camp: Attempted (no bonus)"
		make_camp_chip_color = Color(0.4, 0.34, 0.14)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 6)
	status_row.add_child(_chip(make_camp_chip_text, make_camp_chip_color))
	status_row.add_child(_chip(
		"Food: %d/%d" % [meals_available, meals_needed],
		Color(0.16, 0.3, 0.15) if meals_available >= meals_needed else Color(0.35, 0.16, 0.14)))
	container.add_child(status_row)

	var blockers: Array[String] = []
	if not _make_camp_attempted:
		blockers.append("Make Camp not attempted yet")
	if meals_available < meals_needed:
		blockers.append("need %d Meal(s), have %d" % [meals_needed, meals_available])
	var blocked_tooltip := ""
	if not blockers.is_empty():
		blocked_tooltip = "Can't settle in for the night: " + "; ".join(blockers) + "."

	## Per the follow-up request: shows the actual wake-up clock time
	## ("until HH:MM"), not just the flat duration — wraps past
	## midnight correctly via modulo.
	var wake_clock_8h: int = (GameState.time_minutes + 8 * 60) % (24 * 60)
	var full_sleep_btn := _compact_button("Full Night's Sleep (8 Hours, until %02d:%02d)  [Space]" % [wake_clock_8h / 60, wake_clock_8h % 60])
	full_sleep_btn.disabled = not blockers.is_empty()
	full_sleep_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if not blocked_tooltip.is_empty():
		full_sleep_btn.tooltip_text = blocked_tooltip
	full_sleep_btn.pressed.connect(func(): _on_sleep(8 * 60, true))
	container.add_child(full_sleep_btn)

	## Per the follow-up request: a second Full Night's Sleep option
	## that sleeps until 7am the next morning instead of a flat 8
	## hours — same requirements (Make Camp + Food) and same mechanics
	## (Endurance Test, Fortune/Resolve refresh, etc.) as the 8-hour
	## option above, just a variable duration. "Next morning" means the
	## next time the clock reads 7:00 strictly after right now — so at
	## 22:00 that's a 9-hour sleep, but at 03:00 it's only 4 hours; if
	## it's already exactly 7:00, it rolls over to 7:00 the following
	## day rather than a 0-minute no-op.
	const WAKE_TIME_MINUTES := 7 * 60
	var minutes_until_wake: int = WAKE_TIME_MINUTES - GameState.time_minutes
	if minutes_until_wake <= 0:
		minutes_until_wake += 24 * 60
	var wake_hours := minutes_until_wake / 60
	var wake_minutes := minutes_until_wake % 60
	var wake_duration_text := "%d Hour%s" % [wake_hours, "s" if wake_hours != 1 else ""]
	if wake_minutes > 0:
		wake_duration_text += " %d Min" % wake_minutes
	var sleep_until_7am_btn := _compact_button("Sleep Until 7am (%s)" % wake_duration_text)
	sleep_until_7am_btn.disabled = not blockers.is_empty()
	sleep_until_7am_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if not blocked_tooltip.is_empty():
		sleep_until_7am_btn.tooltip_text = blocked_tooltip
	sleep_until_7am_btn.pressed.connect(func(): _on_sleep(minutes_until_wake, true))
	container.add_child(sleep_until_7am_btn)

	container.add_child(_small_label("Each character then rolls an Endurance Test (+20 if Make Camp succeeded) and recovers SL + Toughness Bonus Wounds, plus loses 1 Fatigue. Shorter naps just pass time."))

## Per the follow-up request (a second Full Night's Sleep option that
## sleeps until 7am rather than a flat 8 hours): this now takes real
## minutes rather than whole hours, plus an explicit `is_full_night`
## flag — the old "hours >= 8" check can't tell a full night apart
## from a short nap once a night's sleep can be e.g. 4 hours (already
## close to 7am) or 9 hours (just gone to bed), so the caller says
## which kind of rest this is instead.
func _on_sleep(minutes: int, is_full_night: bool) -> void:
	GameState.advance_minutes(minutes)
	var duration_text := "%d hour%s" % [minutes / 60, "s" if minutes / 60 != 1 else ""]
	if minutes % 60 > 0:
		duration_text += " %d minute%s" % [minutes % 60, "s" if minutes % 60 != 1 else ""]
	if is_full_night:
		## Defensive re-check — the button should already be disabled
		## otherwise, but a stale click (e.g. state changed between
		## renders) shouldn't silently grant a free full rest.
		var functional := _functional_party()
		var meals_needed: int = functional.size()
		if not _make_camp_attempted or _pooled_meal_count() < meals_needed:
			_sleep_result_text = "You try to settle in, but conditions aren't right for a proper night's rest."
			_sleep_result_good = false
			GameState.autosave()
			_rebuild_all()
			return
		for i in range(meals_needed):
			_consume_one_meal()

		var recovery_notes: Array[String] = []
		for member in _living_party():
			## Per the request: "Instead of getting full Health for a
			## good nights sleep every character in the group makes a
			## roll a Endurance test (+20 if the Make Camp roll was a
			## success), and add the SL outcome + Toughness bonus
			## recovered HP." Floored at 0 recovered — a bad roll never
			## costs Wounds, it just doesn't help much. Per the
			## follow-up request, this bonus is scoped to an actual
			## SUCCESS — a merely-attempted-but-failed Make Camp still
			## lets the party sleep (see the blockers check above), it
			## just doesn't earn this bonus.
			var modifier: int = 20 if _make_camp_succeeded else 0
			var test := TestResolver.resolve_skill_test(member, _endurance_def, "", modifier)
			var toughness_bonus: int = member.get_characteristic_bonus("toughness")
			var recovered: int = max(0, test.success_levels + toughness_bonus)
			var before: int = member.wounds_current
			member.wounds_current = min(member.wounds_max, member.wounds_current + recovered)
			var actual: int = member.wounds_current - before
			if actual > 0:
				recovery_notes.append("%s recovers %d Wound(s) (now %d/%d)" % [member.character_name, actual, member.wounds_current, member.wounds_max])

			## Luck (p.??): folded into the same refresh every character
			## already gets here (see Character.get_max_fortune_points).
			member.fortune_points = member.get_max_fortune_points()
			## p.171: RAW regains Resolve "whenever you act according to
			## your Motivation" — approximated the same way Fortune's
			## own regen already approximates "start of a gaming
			## session" as "a full night's rest."
			member.resolve = member.resilience
			member.tick_critical_wound_days(1)

			## Per the Consume Alcohol follow-up request: a hangover's own
			## Fatigued stack (see Character.hangover_lock_hours_remaining)
			## "cannot be removed" until real hours pass, even by an
			## otherwise-full night's rest — skip the removal below while
			## any lock is still counting down (GameState.advance_minutes
			## -> tick_alcohol_hours already ticked it down by this same
			## Sleep's own duration moments ago).
			if member.hangover_lock_hours_remaining <= 0.0:
				var fatigue_before: int = int(member.conditions.get("Fatigued", 0))
				if fatigue_before > 0:
					if fatigue_before <= 1:
						member.conditions.erase("Fatigued")
					else:
						member.conditions["Fatigued"] = fatigue_before - 1
				## Rattled (a lost Social Combat's own lingering -10 Test
				## penalty — see social_encounter_screen.gd's
				## _resolve_social_combat_loss_consequences()): clears on a
				## proper night's rest, same lifecycle as Fatigued above.
				member.conditions.erase("Rattled")

		## Per the request: Trap Endeavour food arrives "the next
		## morning" — i.e. right here, the only place a morning
		## genuinely happens.
		if _pending_trap_food_days > 0 and not GameState.party.is_empty():
			for i in range(_pending_trap_food_days):
				GameState.party[0].inventory.append("Uncooked Meat")
			recovery_notes.append("Your traps yielded %d day(s) worth of Uncooked Meat." % _pending_trap_food_days)
			_pending_trap_food_days = 0

		## Per the request: a genuine full night's rest resets the World
		## Map's own 8-hour travel cap for a new day.
		GameState.world_map_hours_since_rest = 0.0
		GameState.world_map_fatigue_warned_today = false
		GameState.world_map_fatigue_applied_today = false

		## A new night starts fresh — Make Camp becomes available again
		## for tomorrow (Cook no longer needs this reset — see its own
		## follow-up comment above, it's gated purely on having raw meat
		## on hand now).
		_make_camp_attempted = false
		_make_camp_succeeded = false

		_sleep_result_text = "The party sleeps soundly for %s.\n%s" % [duration_text, "\n".join(recovery_notes) if not recovery_notes.is_empty() else "Nobody had Wounds left to recover."]
		_sleep_result_good = true
	else:
		_sleep_result_text = "The party rests for %s, but it's not enough for a full recovery." % duration_text
		_sleep_result_good = true
	GameState.autosave()
	_rebuild_all()

func _show_message(text: String, good: bool) -> void:
	message_label.text = text
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55) if good else Color(0.85, 0.6, 0.55))

## Per the follow-up request: "show the outcome of the Sleep/heal test
## before closing the camp window" — Sleep now lives at the bottom of a
## taller, scrollable screen, so the small top-of-screen MessageLabel
## alone could go unseen if the player triggered the roll from all the
## way down there. This shows the same text as a modal popup that must
## be dismissed (Continue / Enter / Space / Esc) before anything else
## on the screen — including the Close button — can be interacted with,
## so the result is always actually seen.
func _show_outcome_popup(text: String, good: bool) -> void:
	_show_message(text, good)
	_dismiss_outcome_popup()

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_outcome_overlay = root

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.1, 0.07)
	style.border_color = Color(0.85, 0.7, 0.35)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	vbox.add_child(_header("Result"))

	var body_lbl := Label.new()
	body_lbl.text = text
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	body_lbl.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	body_lbl.add_theme_color_override("font_color", Color(0.75, 0.9, 0.7) if good else Color(0.9, 0.7, 0.65))
	body_lbl.custom_minimum_size = Vector2(524, 0)
	vbox.add_child(body_lbl)

	var ok_btn := _compact_button("Continue  [Enter]")
	ok_btn.pressed.connect(_dismiss_outcome_popup)
	vbox.add_child(ok_btn)
	ok_btn.grab_focus()

func _dismiss_outcome_popup() -> void:
	if _outcome_overlay != null:
		_outcome_overlay.queue_free()
		_outcome_overlay = null

func _on_close() -> void:
	get_tree().change_scene_to_file("res://scenes/Overworld.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if _outcome_overlay != null:
			if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE or event.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_dismiss_outcome_popup()
			return
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_close()
		elif event.keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()
			if not _functional_party().is_empty():
				_on_run_endeavour_session()

func _clear(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()
