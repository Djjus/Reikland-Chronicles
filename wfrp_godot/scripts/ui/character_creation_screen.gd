extends Control
## The game's actual starting screen: create a persistent character (or
## continue an existing one) and begin playing in The Oldworld.
##
## Follows the book's own Character Creation step order (p.24): 1)
## Species, 2) Class and Career, 3) Attributes, 4) Skills and Talents,
## 5) Trappings — rather than one flat "generate everything at once"
## form. At each of the first three steps the player can choose to
## accept a random result for Bonus XP instead of picking manually
## (p.24/33) — a real book mechanic, not a made-up incentive: +20 XP
## for a random Species, +50/+25 XP for keeping a random Career roll
## (first roll vs one of three re-rolled options), +50/+25 XP for
## keeping vs rearranging random Characteristic rolls.

@onready var name_edit_placeholder: Control = null   ## replaced by a dynamically-built LineEdit each step needs it
@onready var back_button: Button = %BackButton
@onready var continue_header: Label = %ContinueHeader
@onready var continue_box: VBoxContainer = %ContinueBox
@onready var continue_sep: HSeparator = %ContinueSep
@onready var step_label: Label = %StepLabel
@onready var step_container: VBoxContainer = %StepContainer
@onready var summary_portrait: TextureRect = %SummaryPortrait
@onready var summary_name_line: Label = %SummaryNameLine
@onready var summary_race_career_line: Label = %SummaryRaceCareerLine
@onready var summary_stats_line: Label = %SummaryStatsLine
@onready var summary_vitals_line: Label = %SummaryVitalsLine
@onready var begin_header: Label = %BeginHeader
@onready var begin_box: HFlowContainer = %BeginBox
@onready var output_label: RichTextLabel = %OutputLabel
@onready var overwrite_confirm_overlay: Control = %OverwriteConfirmOverlay
@onready var overwrite_warning_label: Label = %WarningLabel
@onready var overwrite_confirm_button: Button = %ConfirmButton
@onready var overwrite_cancel_button: Button = %CancelButton

const STEP_NAMES := ["Species", "Class and Career", "Attributes", "Skills and Talents", "Trappings"]

var current_character: Character
var _pending_overwrite_slot: int = -1   ## slot awaiting confirmation in the overlay above
## Per the request: true when reached via the Party Companion Maker
## NPC rather than the main menu's own "New Game" — skips the
## Continue/new-game-only UI, and the final step adds the finished
## character straight to the current real party instead of starting
## a fresh game.
var _is_companion_mode: bool = false

## --- Wizard state, accumulated across steps ------------------------------
var current_step: int = 0
var char_name: String = ""
## "male" or "female" (Character.gender's own convention) — per the
## request ("time to add female character option"), chosen alongside
## Name/Species in Step 1 and carried onto current_character in
## _on_finalize_character(). Drives portrait art only (CareerPortraits.
## get_portrait_for_character()); no mechanical effect.
var char_gender: String = "male"
var selected_race: RaceDefinition = null
var selected_career: CareerDefinition = null
var _available_careers: Array[CareerDefinition] = []
## Advance Characteristics (Attributes step, p.33's Advance Scheme):
## {characteristic_key: advances_spent}, only ever keyed by
## CharacterCreator.get_advance_characteristics(selected_career) — the
## universal, all-Races replacement for the old Human-only "Bonus +1 to
## 2 Characteristics" mechanic (see CharacterCreator.apply_advance_characteristics).
var advance_choices: Dictionary = {}
var rolled_stats: CharacteristicSet = null
var bonus_xp_species: int = 0
var bonus_xp_career: int = 0
var bonus_xp_attributes: int = 0

## --- Step 4 (Skills and Talents) state ------------------------------------
## Species Skills: resolved display strings (e.g. "Trade (Cook)", not
## the raw pool entry "Trade (any one)") the player has picked for the
## +5 / +3 Advance tiers — see CharacterCreator.SPECIES_*_PICK_*.
var species_skill_high_picks: Array = []
var species_skill_low_picks: Array = []
## raw pool entry ("(any)" qualifiers only) -> chosen specialisation.
var _species_skill_resolutions: Dictionary = {}
## One pick per race.racial_talent_choice_groups[i] (index-aligned).
var species_talent_group_picks: Array = []
## Resolved names already rolled on the Random Talents table this
## creation (reroll-on-duplicate and any sub-choice already applied).
var species_random_talents: Array = []
## Set mid-roll when the just-rolled base name needs a further pick
## (Acute Sense/Craftsman/Resistance) — "" once resolved or idle.
var _species_pending_sub_choice_base: String = ""
var _species_pending_sub_choice_options: Array = []
## {skill_display_name: advances}. Career Skills 40-point allocation.
var career_skill_allocations: Dictionary = {}
## raw career skill pool entry ("(Any)" qualifiers only) -> chosen
## specialisation — mirrors _species_skill_resolutions above, same
## reasoning: a Career's own skill list can grant a grouped skill like
## "Entertain (Any)"/"Perform (Any)"/"Play (Any)" without saying which
## specialisation, exactly the same shape Species Skills already solved
## (see _resolved_species_skill_entry). Real bug fix, not just a missing
## picker: before this, the +/- stepper stored Advances directly under
## the literal raw string "Entertain (Any)" — not a real skill any
## concrete Test ever rolls against (real entries look like "Entertain
## (Comedy)") — so every Advance a player put into one of these three
## skills during creation was silently wasted, the exact same "(Any)"
## bucket bug Advancement.gd's own comment describes already being
## fixed for Skills/Talents bought post-creation.
var _career_skill_resolutions: Dictionary = {}
var career_talent_pick: String = ""
var _step4_defaults_race: RaceDefinition = null
var _step4_defaults_career: CareerDefinition = null

## --- Step 5 (Trappings) state ----------------------------------------------
## Class Trappings, pre-resolved (dice already rolled) except for the
## Rogue's Hood-or-Mask pick, which is always the last entry when
## present — see ClassTrappingsTable.grant_to's own Rogue ordering.
var class_trappings_rolled: Array = []
var rogue_hood_or_mask: String = "Hood"
var _trappings_race: RaceDefinition = null
var _trappings_career: CareerDefinition = null
var _career_reroll_pool: Array[CareerDefinition] = []   ## the up-to-3 random rolls offered at the Career step
## Per the request: how many of the current race's own Extra Points
## the player has put toward Fate vs Resilience — reset whenever the
## race changes (see the Species step below), since a different race
## has a different total to spend.
var extra_points_fate: int = 0
var extra_points_resilience: int = 0
## Per the follow-up request: the book's Attributes step (p.33) offers
## "keep as rolled" (+50 XP) OR "rearrange the same 10 values among
## different Characteristics" (+25 XP) as two distinct alternatives —
## only the first existed before. `_rearrange_active` toggles the
## step's display into a click-two-to-swap grid (see
## _build_rearrange_grid); `_rearrange_pending_key` holds the first of
## a pending swap pair, "" when nothing's selected yet.
var _rearrange_active: bool = false
var _rearrange_pending_key: String = ""
## Per the follow-up request: Rearrange (and its "Reroll & Rearrange"
## variant, which uses the same swap-grid) may only be used once per
## character — true from the moment either button is pressed, locking
## both out of the button row for the rest of this creation (short of a
## race change, which invalidates the whole roll anyway — see the
## Species step below).
var _rearrange_used: bool = false
## Attributes Step 3's other alternative (p.33): "allocate 100 points
## across the 10 Characteristics ... minimum of 4 and a maximum of 18
## ... no XP bonus." `_point_buy_allocations` holds each Characteristic's
## spend ABOVE the mandatory floor of CharacterCreator.POINT_BUY_MIN
## (0..POINT_BUY_MAX-POINT_BUY_MIN) — the raw value actually used is
## POINT_BUY_MIN + that spend, same convention CAREER_SKILL_ADVANCE_POOL
## uses for its own remaining-pool tracking.
var _point_buy_active: bool = false
var _point_buy_allocations: Dictionary = {}

func _ready() -> void:
	## Per the request: reached via the Party Companion Maker NPC —
	## the Continue/new-game screen doesn't apply here at all, since
	## there's already a real game in progress.
	_is_companion_mode = GameState.pending_companion_creation
	GameState.pending_companion_creation = false
	continue_header.visible = false
	continue_box.visible = false
	continue_sep.visible = false
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn" if not _is_companion_mode else "res://scenes/Overworld.tscn"))
	overwrite_confirm_button.pressed.connect(_on_overwrite_confirmed)
	overwrite_cancel_button.pressed.connect(_on_overwrite_cancelled)
	_render_step()

## --- Continue (load an existing save) --------------------------------------

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
		lbl.text = "Slot %d: %s, Wounds %d/%d" % [
			slot + 1, ", ".join(summary["party_names"]),
			summary["wounds_current"], summary["wounds_max"],
		]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "Continue →"
		btn.pressed.connect(func(): _on_continue_pressed(slot))
		row.add_child(btn)
		continue_box.add_child(row)
	continue_header.visible = any_saves
	continue_sep.visible = any_saves

func _on_continue_pressed(slot: int) -> void:
	var out_index: Array = [0]
	var out_dismissed: Array = [[]]
	var loaded_party := SaveManager.load_party(slot, out_index, out_dismissed)
	if loaded_party.is_empty():
		output_label.visible = true
		output_label.text = "[color=red]Couldn't load Slot %d — the save may reference data that no longer exists.[/color]" % (slot + 1)
		return
	GameState.party = loaded_party
	GameState.active_party_index = clampi(out_index[0], 0, loaded_party.size() - 1)
	GameState.dismissed_companions = out_dismissed[0]
	GameState.reset_session_state()
	GameState.current_slot = slot
	get_tree().change_scene_to_file("res://scenes/Overworld.tscn")

## --- Step wizard shell ------------------------------------------------------

func _clear_step() -> void:
	for child in step_container.get_children():
		child.queue_free()

func _render_step() -> void:
	_clear_step()
	begin_header.visible = false
	begin_box.visible = false
	for child in begin_box.get_children():
		child.queue_free()
	output_label.visible = false
	step_label.text = "Step %d of 5: %s" % [current_step + 1, STEP_NAMES[current_step]]
	_render_summary_header()
	match current_step:
		0: _render_step_species()
		1: _render_step_career()
		2: _render_step_attributes()
		3: _render_step_skills_talents()
		4: _render_step_trappings()

## Per the request: a persistent record of the choices already made,
## staying visible above the current step's own content (unlike
## step_container, this is never cleared by _render_step()) — Name and
## Species/Career update live/on confirm the same way `selected_race`/
## `selected_career` themselves do, the Portrait mirrors the exact same
## CareerPortraits lookup the rest of the game uses for this Career (see
## career_portraits.gd), and Characteristics shows the current rolled
## values PLUS whatever's currently allocated in the Attributes step's
## own Advance Characteristics picker — the same math that step's own
## per-stat rows already show, kept in sync here too.
func _render_summary_header() -> void:
	var shown_name := char_name.strip_edges()
	summary_name_line.text = shown_name if shown_name != "" else "Unnamed Wanderer"

	var species_text := "Species: %s" % selected_race.race_name if selected_race != null else "Species: (not yet chosen)"
	var career_text := "Career: %s" % selected_career.career_name if selected_career != null else "Career: (not yet chosen)"
	summary_race_career_line.text = "%s    %s" % [species_text, career_text]

	var portrait_tex: Texture2D = null
	if selected_career != null:
		portrait_tex = CareerPortraits.get_portrait(selected_career.career_name, char_gender)
	if portrait_tex == null:
		portrait_tex = load(CareerPortraits.FALLBACK_PATH) as Texture2D
	summary_portrait.texture = portrait_tex

	if rolled_stats == null:
		summary_stats_line.text = "Characteristics: (not yet rolled)"
	else:
		var parts: Array[String] = []
		for key in CharacteristicSet.KEYS:
			var val: int = rolled_stats.get_value(key) + int(advance_choices.get(key, 0))
			parts.append("%s %d" % [CharacteristicSet.SHORT_NAMES[key], val])
		summary_stats_line.text = "Characteristics: " + "  ".join(parts)

	## Per the follow-up request: Wounds/Movement/Fate/Resilience (the
	## rest of the Attributes Table, p.33) plus the cumulative Bonus XP
	## earned so far — same formula _build_secondary_stats_preview() uses
	## in the Attributes step itself (see _compute_secondary_stats),
	## kept in sync here too. Bonus XP is always computable; the
	## Characteristic-derived vitals need a real roll first.
	var xp_total := bonus_xp_species + bonus_xp_career + bonus_xp_attributes
	var vitals := _compute_secondary_stats()
	if vitals.is_empty():
		summary_vitals_line.text = "Wounds / Movement / Fate / Resilience: (not yet available)    Bonus XP: %d" % xp_total
	else:
		summary_vitals_line.text = "Wounds: %d    Movement: %d (Walk %d / Run %d)    Fate: %d    Resilience: %d    Bonus XP: %d" % [
			vitals.wounds, vitals.movement, vitals.movement * 3, vitals.movement * 6, vitals.fate, vitals.resilience, xp_total]

func _section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	return lbl

func _nav_row(back_enabled: bool, next_text: String, next_enabled: bool, on_next: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if back_enabled:
		var back_btn := Button.new()
		back_btn.text = "← Back"
		back_btn.pressed.connect(func():
			current_step -= 1
			_render_step()
		)
		row.add_child(back_btn)
	var next_btn := Button.new()
	next_btn.text = next_text
	next_btn.disabled = not next_enabled
	next_btn.pressed.connect(on_next)
	row.add_child(next_btn)
	return row

## --- Step 1: Species (p.24) -------------------------------------------------

func _render_step_species() -> void:
	step_container.add_child(_section_label("Choose your character's name and Species."))

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	var name_lbl := Label.new()
	name_lbl.text = "Name:"
	name_row.add_child(name_lbl)
	var name_edit := LineEdit.new()
	name_edit.text = char_name
	name_edit.placeholder_text = "Character name"
	name_edit.custom_minimum_size = Vector2(240, 0)
	name_edit.text_changed.connect(func(t):
		char_name = t
		_render_summary_header()   ## live update, without a full _render_step() that would steal focus mid-type
	)
	name_row.add_child(name_edit)
	step_container.add_child(name_row)

	## Per the request ("time to add female character option"): picked
	## here alongside Name/Species since it's the same kind of one-off
	## identity choice, made once before Career. Only affects which of
	## CareerPortraits' two art sets this character's portrait comes
	## from (see _render_summary_header() and _update_career_preview()
	## below) — no mechanical effect on stats/skills/etc.
	var gender_row := HBoxContainer.new()
	gender_row.add_theme_constant_override("separation", 8)
	var gender_lbl := Label.new()
	gender_lbl.text = "Gender:"
	gender_row.add_child(gender_lbl)
	var gender_picker := OptionButton.new()
	gender_picker.add_item("Male")
	gender_picker.add_item("Female")
	gender_picker.selected = 1 if char_gender == "female" else 0
	gender_picker.item_selected.connect(func(idx):
		char_gender = "female" if idx == 1 else "male"
		_render_summary_header()   ## live-updates the preview portrait
	)
	gender_row.add_child(gender_picker)
	step_container.add_child(gender_row)

	var race_row := HBoxContainer.new()
	race_row.add_theme_constant_override("separation", 8)
	var race_lbl := Label.new()
	race_lbl.text = "Species:"
	race_row.add_child(race_lbl)
	var race_picker := OptionButton.new()
	var selected_idx := 0
	for i in range(GameData.races.size()):
		race_picker.add_item(GameData.races[i].race_name)
		if selected_race != null and GameData.races[i] == selected_race:
			selected_idx = i
	race_picker.selected = selected_idx
	race_row.add_child(race_picker)
	step_container.add_child(race_row)

	## Random Species option (p.24): "roll 1d100, consult the Random
	## Species Table, and gain +20 XP if you accept the result."
	var random_row := HBoxContainer.new()
	random_row.add_theme_constant_override("separation", 8)
	var random_note := Label.new()
	random_note.text = "Or, per the book: roll randomly for +20 Bonus XP."
	random_note.add_theme_font_size_override("font_size", 12)
	random_note.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
	random_row.add_child(random_note)
	var random_btn := Button.new()
	random_btn.text = "Roll Randomly (+20 XP)"
	random_btn.pressed.connect(func():
		## Random Species Table (p.24): 01-90 Human, 91-94 Halfling,
		## 95-98 Dwarf, 99 High Elf, 00 Wood Elf.
		var roll := Dice.d100()
		var race_name := "Human"
		if roll <= 90:
			race_name = "Human"
		elif roll <= 94:
			race_name = "Halfling"
		elif roll <= 98:
			race_name = "Dwarf"
		elif roll <= 99:
			race_name = "High Elf"
		else:
			race_name = "Wood Elf"
		for i in range(GameData.races.size()):
			if GameData.races[i].race_name == race_name:
				race_picker.selected = i
		bonus_xp_species = 20
		output_label.visible = true
		output_label.text = "[color=#8fbf6a]Rolled %d: %s! +20 Bonus XP.[/color]" % [roll, race_name]
	)
	random_row.add_child(random_btn)
	step_container.add_child(random_row)

	step_container.add_child(_nav_row(false, "Next: Class and Career →", true, func():
		var new_race: RaceDefinition = GameData.races[race_picker.selected]
		if new_race != selected_race:
			extra_points_fate = 0
			extra_points_resilience = 0
			## Per the follow-up request: `rolled_stats` was never reset on
			## a species change — going back from Attributes to Species
			## (e.g. to try a different race) and returning left the OLD
			## species' rolled Characteristics in place, rolled against
			## the wrong race's characteristic_bases entirely. Everything
			## tied to that roll gets reset here too, since it's now
			## invalid for the new race.
			rolled_stats = null
			bonus_xp_attributes = 0
			_rearrange_active = false
			_rearrange_pending_key = ""
			_rearrange_used = false
			_point_buy_active = false
			_point_buy_allocations.clear()
		selected_race = new_race
		if char_name.strip_edges() == "":
			char_name = "Unnamed Wanderer"
		current_step = 1
		_render_step()
	))

## --- Step 2: Class and Career (p.30) ----------------------------------------

func _render_step_career() -> void:
	step_container.add_child(_section_label("Choose a Career %s can take." % selected_race.race_name))

	_available_careers.clear()
	for c in GameData.careers:
		if c.valid_races.is_empty() or c.valid_races.has(selected_race.race_name):
			_available_careers.append(c)

	## Per the request: the career's full-size AI-generated portrait
	## (transparent background) now previews next to the picker, updating
	## live as the player changes their pick or rolls randomly. Keyed off
	## CareerPortraits (career_name -> res://assets/portraits/careers/
	## <key>.png) — see that file for the naming rule. Careers with no
	## matching art (shouldn't happen for the current 64, but kept safe
	## for any future addition) just leave the preview blank instead of
	## erroring.
	var career_preview := TextureRect.new()
	career_preview.custom_minimum_size = Vector2(130, 130)
	## Real bug fix, same class as CharacterMenu.tscn's own HeaderPortrait
	## (spotted while fixing that one): without EXPAND_IGNORE_SIZE, a
	## TextureRect's effective minimum size is max(custom_minimum_size,
	## texture size) — since these portraits are up to 512px, the preview
	## would size itself to the full source image instead of the intended
	## 130x130 thumbnail. Every other portrait TextureRect in the project
	## already sets this; this one was just missed.
	career_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	career_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var career_preview_frame := PanelContainer.new()
	career_preview_frame.add_child(career_preview)

	var career_top_row := HBoxContainer.new()
	career_top_row.add_theme_constant_override("separation", 12)

	var career_row := VBoxContainer.new()
	career_row.add_theme_constant_override("separation", 8)
	career_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var career_picker_row := HBoxContainer.new()
	career_picker_row.add_theme_constant_override("separation", 8)
	var career_lbl := Label.new()
	career_lbl.text = "Career:"
	career_picker_row.add_child(career_lbl)
	var career_picker := OptionButton.new()
	var selected_idx := 0
	for i in range(_available_careers.size()):
		career_picker.add_item(_available_careers[i].career_name)
		if selected_career != null and _available_careers[i] == selected_career:
			selected_idx = i
	if career_picker.item_count > 0:
		career_picker.selected = selected_idx
	career_picker_row.add_child(career_picker)
	career_row.add_child(career_picker_row)

	var _update_career_preview := func():
		if career_picker.item_count > 0 and career_picker.selected >= 0:
			career_preview.texture = CareerPortraits.get_portrait(_available_careers[career_picker.selected].career_name, char_gender)
		else:
			career_preview.texture = null
	_update_career_preview.call()
	career_picker.item_selected.connect(func(_idx): _update_career_preview.call())

	career_top_row.add_child(career_row)
	career_top_row.add_child(career_preview_frame)
	step_container.add_child(career_top_row)

	## Random Class and Career (p.30): the book's real procedure is TWO
	## separate rolls, not one — first a Class (Academic/Burgher/
	## Courtier/Peasant/Ranger/Riverfolk/Rogue/Warrior), then a Career
	## within that Class off a separate per-Class table. This used to
	## collapse both rolls into a single flat pick from every career the
	## race can take at all, regardless of Class — simpler, but not the
	## book's actual two-step structure, and it meant a race with (say)
	## eight valid Warrior careers but only one valid Academic career
	## had wildly uneven odds per Class purely as a side effect of how
	## many careers happened to exist in each, rather than every Class
	## getting a fair roll of its own. This project doesn't have the
	## book's own exact 1d10-per-Class odds on hand, so the Class roll
	## here is a uniform pick among whichever of the 8 Classes actually
	## has at least one career this race can take, THEN a uniform pick
	## of the Career within that Class — faithful to the book's two-step
	## STRUCTURE even where it can't reproduce the precise table skew.
	## First roll kept is worth +50 XP, or reroll twice more (3 total)
	## and keep one of those for +25 XP, same as before.
	var random_row := HBoxContainer.new()
	random_row.add_theme_constant_override("separation", 8)
	var random_note := Label.new()
	random_note.text = "Or roll randomly (Class, then Career within it): +50 XP for the first result, +25 XP if you reroll up to twice more."
	random_note.add_theme_font_size_override("font_size", 12)
	random_note.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
	random_row.add_child(random_note)
	var reroll_btn := Button.new()
	reroll_btn.text = "Roll Randomly"
	reroll_btn.pressed.connect(func():
		if _available_careers.is_empty():
			return
		var classes_available: Array[String] = []
		for c in _available_careers:
			if not classes_available.has(c.career_class):
				classes_available.append(c.career_class)
		var rolled_class: String = classes_available[randi() % classes_available.size()]
		var careers_in_class: Array[CareerDefinition] = []
		for c in _available_careers:
			if c.career_class == rolled_class:
				careers_in_class.append(c)
		var pick: CareerDefinition = careers_in_class[randi() % careers_in_class.size()]
		for i in range(_available_careers.size()):
			if _available_careers[i] == pick:
				career_picker.selected = i
		_update_career_preview.call()
		_career_reroll_pool.append(pick)
		var xp := 50 if _career_reroll_pool.size() == 1 else 25
		bonus_xp_career = xp
		output_label.visible = true
		output_label.text = "[color=#8fbf6a]Rolled Class: %s → Career: %s! Keep it for +%d Bonus XP, or roll again (rerolling more than twice drops the bonus).[/color]" % [rolled_class, pick.career_name, xp]
		if _career_reroll_pool.size() >= 3:
			reroll_btn.disabled = true
	)
	random_row.add_child(reroll_btn)
	step_container.add_child(random_row)

	## Manually changing the picker after a random roll forfeits the bonus.
	career_picker.item_selected.connect(func(_idx): bonus_xp_career = 0)

	step_container.add_child(_nav_row(true, "Next: Attributes →", career_picker.item_count > 0, func():
		var new_career: CareerDefinition = _available_careers[career_picker.selected]
		if new_career != selected_career:
			## Advance Characteristics (Attributes step) is keyed off the
			## chosen Career's own Tier 1 Advance Scheme (see
			## CharacterCreator.get_advance_characteristics) — a different
			## Career means a different 3 Characteristics, so any prior
			## allocation no longer applies.
			advance_choices = {}
		selected_career = new_career
		current_step = 2
		_render_step()
	))

## --- Step 3: Attributes (p.33) -----------------------------------------------

func _render_step_attributes() -> void:
	if rolled_stats == null:
		rolled_stats = CharacterCreator.roll_characteristics(selected_race)

	step_container.add_child(_section_label("Allocate your Characteristics:" if _point_buy_active else "Your rolled Characteristics:"))
	if _rearrange_active:
		step_container.add_child(_build_rearrange_grid())
		var hint := Label.new()
		hint.text = "Click two Characteristics to swap their rolled values, then move on when you're happy with the arrangement."
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD
		step_container.add_child(hint)
	elif _point_buy_active:
		step_container.add_child(_build_point_buy_section())
	else:
		var stats_lbl := RichTextLabel.new()
		stats_lbl.bbcode_enabled = true
		stats_lbl.fit_content = true
		stats_lbl.custom_minimum_size = Vector2(0, 40)
		var line := ""
		for key in CharacteristicSet.KEYS:
			line += "%s: %d   " % [CharacteristicSet.SHORT_NAMES[key], rolled_stats.get_value(key)]
		stats_lbl.text = line
		step_container.add_child(stats_lbl)

	## Per the request: the Attributes Table (p.33) isn't just the ten
	## Characteristics — Wounds, Movement/Walk/Run, and Fate/Resilience/
	## Fortune/Resolve are all part of the same table, and previously
	## didn't show anywhere until AFTER "Create Character" was pressed
	## (on the final summary), so the player was choosing whether to
	## keep/rearrange/spend Extra Points blind to their actual effect.
	## Recomputed live off `rolled_stats` (not a real Character yet), so
	## it updates immediately as the player rerolls, rearranges, or
	## spends Extra Points below.
	step_container.add_child(_build_secondary_stats_preview())

	## Advance Characteristics (p.33's Advance Scheme): replaces the old
	## Human-only "Bonus +1 to 2 Characteristics" mechanic — every Race
	## gets this, because the book ties it to the chosen Career, not the
	## Species (see CharacterCreator.get_advance_characteristics/
	## apply_advance_characteristics for where the 3 eligible
	## Characteristics come from).
	var advance_keys: Array = CharacterCreator.get_advance_characteristics(selected_career)
	if not advance_keys.is_empty():
		step_container.add_child(_build_advance_characteristics_section(advance_keys))

	## The book's own 3-step Attributes decision tree (p.33), offered
	## here as 4 buttons rather than a strict forced sequence: Step 1
	## keep as rolled (+50 XP); Step 2 rearrange the SAME 10 rolled
	## values among different Characteristics, no rerolling (+25 XP);
	## Step 3's two no-bonus alternatives — reroll fresh and (optionally)
	## rearrange those, OR ignore the dice entirely and Point Buy 100
	## points across the 10 Characteristics (min 4, max 18 each).
	## Manually rerolling/adjusting via the race's own picks above
	## forfeits all of these, same as before.
	var random_row := HBoxContainer.new()
	random_row.add_theme_constant_override("separation", 8)
	var point_buy_remaining := _point_buy_remaining() if _point_buy_active else 0
	if _rearrange_active or _point_buy_active:
		var done_btn := Button.new()
		done_btn.text = "Done Rearranging" if _rearrange_active else "Done Allocating"
		## Per the follow-up request ("spend all relevant options before
		## Next"): Point Buy's own 100 points must be fully allocated
		## before Done can be pressed — Rearrange has nothing to "spend"
		## (it's a permutation of the same 10 rolled values), so it stays
		## always-clickable once entered.
		done_btn.disabled = _point_buy_active and point_buy_remaining != 0
		done_btn.pressed.connect(func():
			_rearrange_active = false
			_point_buy_active = false
			_render_step()
		)
		random_row.add_child(done_btn)
		if _point_buy_active and point_buy_remaining != 0:
			var point_buy_hint := Label.new()
			point_buy_hint.text = "Allocate all 100 points before finishing Point Buy (%d remaining)." % point_buy_remaining
			point_buy_hint.add_theme_font_size_override("font_size", 11)
			point_buy_hint.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
			point_buy_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
			random_row.add_child(point_buy_hint)
	else:
		var keep_btn := Button.new()
		keep_btn.text = "Keep As Rolled (+50 XP)"
		keep_btn.disabled = bonus_xp_attributes == 50
		keep_btn.pressed.connect(func():
			bonus_xp_attributes = 50
			output_label.visible = true
			output_label.text = "[color=#8fbf6a]Kept your Characteristics exactly as rolled — +50 Bonus XP.[/color]"
			_render_step()
		)
		random_row.add_child(keep_btn)

		## Per the follow-up request: Rearrange (and Reroll & Rearrange,
		## just below — same swap-grid mechanic) may only be used once;
		## _rearrange_used is set the moment either is pressed and never
		## cleared except by a race change, so both stay disabled for the
		## rest of this creation once either has fired.
		var rearrange_btn := Button.new()
		rearrange_btn.text = "Rearrange (+25 XP)"
		rearrange_btn.disabled = _rearrange_used
		rearrange_btn.pressed.connect(func():
			bonus_xp_attributes = 25
			_rearrange_active = true
			_rearrange_used = true
			_rearrange_pending_key = ""
			output_label.visible = true
			output_label.text = "[color=#8fbf6a]Rearranging — click two Characteristics below to swap their values. +25 Bonus XP for rearranging instead of keeping the original rolls.[/color]"
			_render_step()
		)
		random_row.add_child(rearrange_btn)

		var reroll_rearrange_btn := Button.new()
		reroll_rearrange_btn.text = "Reroll & Rearrange (no XP)"
		reroll_rearrange_btn.disabled = _rearrange_used
		reroll_rearrange_btn.pressed.connect(func():
			rolled_stats = CharacterCreator.roll_characteristics(selected_race)
			bonus_xp_attributes = 0
			_rearrange_active = true
			_rearrange_used = true
			_rearrange_pending_key = ""
			output_label.visible = true
			output_label.text = "[color=#8fbf6a]Rolled a fresh set of Characteristics — click two below to swap their values if you like. No Bonus XP for this option.[/color]"
			_render_step()
		)
		random_row.add_child(reroll_rearrange_btn)

		var point_buy_btn := Button.new()
		point_buy_btn.text = "Point Buy — 100 Points (no XP)"
		point_buy_btn.pressed.connect(func():
			bonus_xp_attributes = 0
			_point_buy_active = true
			_init_point_buy()
			output_label.visible = true
			output_label.text = "[color=#8fbf6a]Allocating 100 points across your Characteristics (min 4, max 18 each) instead of rolling. No Bonus XP for this option.[/color]"
			_render_step()
		)
		random_row.add_child(point_buy_btn)
	step_container.add_child(random_row)
	if _rearrange_used and not (_rearrange_active or _point_buy_active):
		var rearrange_hint := Label.new()
		rearrange_hint.text = "Rearrange already used for this character — it (and Reroll & Rearrange) can only be used once."
		rearrange_hint.add_theme_font_size_override("font_size", 11)
		rearrange_hint.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
		rearrange_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
		step_container.add_child(rearrange_hint)

	## Per the request: Extra Points (the Attributes Table's own row)
	## are spendable here on Fate and/or Resilience — a real choice,
	## not a fixed race-only value. Rebuilds the whole step on every
	## +/- press so the remaining-points count and each button's own
	## disabled state always reflect the current allocation.
	var total_extra: int = selected_race.extra_points
	var spent: int = extra_points_fate + extra_points_resilience
	var remaining: int = total_extra - spent
	step_container.add_child(_section_label("Extra Points: %d / %d remaining" % [remaining, total_extra]))
	var extra_row := HFlowContainer.new()
	extra_row.add_theme_constant_override("h_separation", 10)

	var fate_label := Label.new()
	fate_label.text = "Fate: %d (+%d)" % [selected_race.starting_fate + extra_points_fate, extra_points_fate]
	extra_row.add_child(fate_label)
	var fate_minus := Button.new()
	fate_minus.text = "-"
	fate_minus.disabled = extra_points_fate <= 0
	fate_minus.pressed.connect(func():
		extra_points_fate = max(0, extra_points_fate - 1)
		_render_step()
	)
	extra_row.add_child(fate_minus)
	var fate_plus := Button.new()
	fate_plus.text = "+"
	fate_plus.disabled = remaining <= 0
	fate_plus.pressed.connect(func():
		if remaining > 0:
			extra_points_fate += 1
		_render_step()
	)
	extra_row.add_child(fate_plus)

	var resilience_label := Label.new()
	resilience_label.text = "Resilience: %d (+%d)" % [selected_race.starting_resilience + extra_points_resilience, extra_points_resilience]
	extra_row.add_child(resilience_label)
	var resilience_minus := Button.new()
	resilience_minus.text = "-"
	resilience_minus.disabled = extra_points_resilience <= 0
	resilience_minus.pressed.connect(func():
		extra_points_resilience = max(0, extra_points_resilience - 1)
		_render_step()
	)
	extra_row.add_child(resilience_minus)
	var resilience_plus := Button.new()
	resilience_plus.text = "+"
	resilience_plus.disabled = remaining <= 0
	resilience_plus.pressed.connect(func():
		if remaining > 0:
			extra_points_resilience += 1
		_render_step()
	)
	extra_row.add_child(resilience_plus)
	step_container.add_child(extra_row)

	## Per the follow-up request ("user has to spend and select all
	## relevant options in each section to be able to click Next ...
	## Ie. spend available points/advances"): Rearrange/Point Buy must be
	## finished (the "Done" button clicked, which Point Buy itself now
	## gates on full spend — see above), the 5 Advance Characteristics
	## must be fully allocated, and the race's own Extra Points must be
	## fully allocated too, all before moving on.
	var advance_remaining := _advance_characteristics_remaining()
	var attrs_can_advance := not (_rearrange_active or _point_buy_active) and advance_remaining <= 0 and remaining <= 0
	step_container.add_child(_nav_row(true, "Next: Skills and Talents →", attrs_can_advance, func():
		current_step = 3
		_render_step()
	))
	if not attrs_can_advance:
		var reasons: Array[String] = []
		if _rearrange_active or _point_buy_active:
			reasons.append("finish rearranging/allocating your Characteristics")
		if advance_remaining > 0:
			reasons.append("allocate all %d Advance Characteristics points (%d remaining)" % [CharacterCreator.ADVANCE_CHARACTERISTICS_POOL, advance_remaining])
		if remaining > 0:
			reasons.append("spend all %d Extra Points (%d remaining)" % [total_extra, remaining])
		var attrs_hint := Label.new()
		attrs_hint.text = "Before continuing: " + "; ".join(reasons) + "."
		attrs_hint.add_theme_font_size_override("font_size", 11)
		attrs_hint.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
		attrs_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
		step_container.add_child(attrs_hint)

## Advance Characteristics (p.33's Advance Scheme): allocate
## CharacterCreator.ADVANCE_CHARACTERISTICS_POOL (5) Advances across
## `keys` (the chosen Career's own Tier 1 Characteristics — see
## CharacterCreator.get_advance_characteristics). Mirrors the Extra
## Points allocator's own label + remaining-count + per-stat +/- pattern
## just below in this same step.
## How many of the current Career's 5 Advance Characteristics points are
## still unspent — shared by the step's own allocator UI and the Next-
## button gate (_render_step_attributes) so both always agree.
func _advance_characteristics_remaining() -> int:
	var keys: Array = CharacterCreator.get_advance_characteristics(selected_career)
	var spent := 0
	for key in keys:
		spent += int(advance_choices.get(key, 0))
	return CharacterCreator.ADVANCE_CHARACTERISTICS_POOL - spent

func _build_advance_characteristics_section(keys: Array) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var remaining: int = _advance_characteristics_remaining()
	var lbl := Label.new()
	lbl.text = "Advance Characteristics (%s) — allocate %d Advances: %d remaining" % [
		selected_career.career_name, CharacterCreator.ADVANCE_CHARACTERISTICS_POOL, remaining]
	box.add_child(lbl)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	for key in keys:
		row.add_child(_build_advance_characteristic_control(key, remaining))
	box.add_child(row)
	return box

func _build_advance_characteristic_control(key: String, remaining: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var spent: int = int(advance_choices.get(key, 0))
	var stat_lbl := Label.new()
	stat_lbl.text = "%s: %d (+%d)" % [CharacteristicSet.SHORT_NAMES[key], rolled_stats.get_value(key) + spent, spent]
	row.add_child(stat_lbl)
	var minus := Button.new()
	minus.text = "-"
	minus.disabled = spent <= 0
	minus.pressed.connect(func():
		advance_choices[key] = maxi(0, spent - 1)
		_render_step()
	)
	row.add_child(minus)
	var plus := Button.new()
	plus.text = "+"
	plus.disabled = remaining <= 0
	plus.pressed.connect(func():
		if remaining > 0:
			advance_choices[key] = spent + 1
		_render_step()
	)
	row.add_child(plus)
	return row

## Attributes Step 3's "Point Buy" alternative (p.33): 100 points across
## the 10 Characteristics, minimum 4/maximum 18 each. Mirrors the
## Career Skills allocator's own +/- pattern — a floor of POINT_BUY_MIN
## is "free" on every Characteristic, and _point_buy_allocations tracks
## only the spend ABOVE that floor, capped at POINT_BUY_MAX - MIN.
func _init_point_buy() -> void:
	_point_buy_allocations.clear()
	for key in CharacteristicSet.KEYS:
		_point_buy_allocations[key] = 0
		var base: int = selected_race.characteristic_bases.get(key, 20)
		rolled_stats.set_value(key, base + CharacterCreator.POINT_BUY_MIN)

## How many of the 100 Point Buy points are still unspent — shared by
## the step's own allocator UI, the "Done Allocating" gate, and the
## Next-button gate.
func _point_buy_remaining() -> int:
	var floor_total: int = CharacteristicSet.KEYS.size() * CharacterCreator.POINT_BUY_MIN
	var spent := 0
	for key in CharacteristicSet.KEYS:
		spent += _point_buy_allocations.get(key, 0)
	return CharacterCreator.POINT_BUY_TOTAL - floor_total - spent

func _build_point_buy_section() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var remaining: int = _point_buy_remaining()
	var lbl := Label.new()
	lbl.text = "Allocate %d points across the ten Characteristics (min %d, max %d each): %d remaining" % [
		CharacterCreator.POINT_BUY_TOTAL, CharacterCreator.POINT_BUY_MIN, CharacterCreator.POINT_BUY_MAX, remaining]
	box.add_child(lbl)
	for key in CharacteristicSet.KEYS:
		box.add_child(_build_point_buy_row(key, remaining))
	return box

func _build_point_buy_row(key: String, remaining: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var base: int = selected_race.characteristic_bases.get(key, 20)
	var extra: int = _point_buy_allocations.get(key, 0)
	var raw: int = CharacterCreator.POINT_BUY_MIN + extra
	var lbl := Label.new()
	lbl.text = "%s: %d (raw %d + base %d)" % [CharacteristicSet.SHORT_NAMES[key], base + raw, raw, base]
	lbl.custom_minimum_size = Vector2(220, 0)
	row.add_child(lbl)
	var minus := Button.new()
	minus.text = "-"
	minus.disabled = extra <= 0
	minus.pressed.connect(func():
		_point_buy_allocations[key] = maxi(0, extra - 1)
		rolled_stats.set_value(key, base + CharacterCreator.POINT_BUY_MIN + _point_buy_allocations[key])
		_render_step()
	)
	row.add_child(minus)
	var plus := Button.new()
	plus.text = "+"
	plus.disabled = raw >= CharacterCreator.POINT_BUY_MAX or remaining <= 0
	plus.pressed.connect(func():
		_point_buy_allocations[key] = extra + 1
		rolled_stats.set_value(key, base + CharacterCreator.POINT_BUY_MIN + _point_buy_allocations[key])
		_render_step()
	)
	row.add_child(plus)
	return row

## Per the follow-up request: the "Rearrange (+25 XP)" alternative to
## "Keep As Rolled" — a click-two-to-swap grid over the same 10 rolled
## values (no rerolling, just reassigning which value lands on which
## Characteristic). First click marks a Characteristic as the pending
## swap partner (shown bracketed); a second click on a DIFFERENT one
## swaps their values in `rolled_stats` directly and clears the pending
## mark; a second click on the SAME one just cancels the pending mark.
func _build_rearrange_grid() -> HFlowContainer:
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for key in CharacteristicSet.KEYS:
		var btn := Button.new()
		var value_text := "%s: %d" % [CharacteristicSet.SHORT_NAMES[key], rolled_stats.get_value(key)]
		btn.text = "[ %s ]" % value_text if key == _rearrange_pending_key else value_text
		btn.pressed.connect(func():
			if _rearrange_pending_key == "":
				_rearrange_pending_key = key
			elif _rearrange_pending_key == key:
				_rearrange_pending_key = ""
			else:
				var a := rolled_stats.get_value(_rearrange_pending_key)
				var b := rolled_stats.get_value(key)
				rolled_stats.set_value(_rearrange_pending_key, b)
				rolled_stats.set_value(key, a)
				_rearrange_pending_key = ""
			_render_step()
		)
		grid.add_child(btn)
	return grid

## Per the follow-up request: shows the rest of the book's Attributes
## Table (p.33) live during this step — Wounds (SB + 2×TB + WPB +
## race's Extra Wounds, same formula as Character.recompute_max_wounds),
## Movement/Walk/Run (race's base Movement, ×3/×6 — same formula as
## Character.get_walk_distance/get_run_distance), and Fate/Resilience
## (race's starting value + whatever Extra Points are currently
## allocated below) with Fortune/Resolve called out as starting equal
## to Fate/Resilience, exactly as Character.gd sets them at creation.
## Reads straight off `rolled_stats`/`selected_race` rather than a real
## Character, since one doesn't exist yet at this step. Factored out of
## the RichTextLabel builder below so the persistent Summary Header can
## show the same numbers — {} if there's no roll/Species yet to compute
## from.
func _compute_secondary_stats() -> Dictionary:
	if rolled_stats == null or selected_race == null:
		return {}
	var sb := rolled_stats.get_bonus("strength")
	var tb := rolled_stats.get_bonus("toughness")
	var wpb := rolled_stats.get_bonus("willpower")
	return {
		"wounds": sb + (tb * 2) + wpb + selected_race.starting_extra_wounds,
		"movement": selected_race.movement,
		"fate": selected_race.starting_fate + extra_points_fate,
		"resilience": selected_race.starting_resilience + extra_points_resilience,
	}

func _build_secondary_stats_preview() -> RichTextLabel:
	var vitals := _compute_secondary_stats()
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.custom_minimum_size = Vector2(0, 24)
	lbl.text = "[b]Wounds:[/b] %d   [b]Movement:[/b] %d (Walk %d / Run %d)   [b]Fate:[/b] %d   [b]Resilience:[/b] %d   [b]Fortune:[/b] %d   [b]Resolve:[/b] %d" % [
		vitals.wounds, vitals.movement, vitals.movement * 3, vitals.movement * 6, vitals.fate, vitals.resilience, vitals.fate, vitals.resilience
	]
	return lbl

## --- Step 4: Skills and Talents (p.35) ---------------------------------------
## The book's real structure: Species Skills and Talents (choose 3
## pool Skills for +5 Advances, 3 more for +3; any fixed Talents plus
## one pick per independent choice group; N rolls on the Random
## Talents table) AND Career Skills and Talents (40 Advances across the
## Career's 8 Tier-1 Skills, max 10 each; one Talent of the 4 offered)
## both happen at THIS step — not at Species/Career selection time.

func _render_step_skills_talents() -> void:
	if _step4_defaults_race != selected_race or _step4_defaults_career != selected_career:
		_init_step4_defaults()

	var total_bonus_xp := bonus_xp_species + bonus_xp_career + bonus_xp_attributes

	_render_species_skills_section()
	step_container.add_child(HSeparator.new())
	_render_species_talents_section()
	step_container.add_child(HSeparator.new())
	_render_career_skills_section()
	step_container.add_child(HSeparator.new())
	_render_career_talent_section()

	if total_bonus_xp > 0:
		step_container.add_child(HSeparator.new())
		var xp_lbl := Label.new()
		xp_lbl.text = "You've earned %d Bonus XP from this creation (Species %d + Career %d + Attributes %d). Spend it on Skills, Talents, and Characteristic advances from the Advancement screen once your character exists." % [
			total_bonus_xp, bonus_xp_species, bonus_xp_career, bonus_xp_attributes]
		xp_lbl.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
		xp_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		step_container.add_child(xp_lbl)

	var pool: Array = selected_race.racial_skill_pool
	var skills_done := true
	if CharacterCreator.species_pool_needs_choice(pool):
		var expected_high: int = mini(CharacterCreator.SPECIES_HIGH_PICK_COUNT, pool.size())
		var expected_low: int = mini(CharacterCreator.SPECIES_LOW_PICK_COUNT, pool.size() - expected_high)
		skills_done = species_skill_high_picks.size() >= expected_high and species_skill_low_picks.size() >= expected_low
	var random_talents_done := species_random_talents.size() >= selected_race.racial_random_talent_count
	## Per the follow-up request ("spend available points/advances"):
	## the Career Skills 40-Advance pool must be fully allocated too —
	## previously the player could leave any amount of it unspent.
	var career_skills_remaining := _career_skills_remaining()
	var can_advance := skills_done and random_talents_done and _species_pending_sub_choice_base == "" and career_skills_remaining <= 0
	step_container.add_child(_nav_row(true, "Next: Trappings →", can_advance, func():
		current_step = 4
		_render_step()
	))
	if not can_advance:
		var hint := Label.new()
		if not skills_done:
			hint.text = "Finish choosing your Species Skills before continuing."
		elif not random_talents_done:
			hint.text = "Finish rolling this Species' Random Talents before continuing."
		elif _species_pending_sub_choice_base != "":
			hint.text = "Resolve the pending Random Talent's choice before continuing."
		else:
			hint.text = "Allocate all %d Career Skills Advances before continuing (%d remaining)." % [CharacterCreator.CAREER_SKILL_ADVANCE_POOL, career_skills_remaining]
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
		step_container.add_child(hint)

## Sets sensible defaults so the step is immediately usable without any
## clicks (same convention the old single racial-talent picker used) —
## except the Species Skill pool itself, per the follow-up request:
## every pool entry starts Unpicked so the player actively chooses
## their 3-for-+5/3-for-+3 rather than finding them pre-filled. Talent
## choice groups still default to their first option, and the first
## Career Talent, same as before. Random Talent rolls are NOT
## auto-rolled — every other random roll in this wizard is an explicit
## opt-in button, and these are no different.
func _init_step4_defaults() -> void:
	_step4_defaults_race = selected_race
	_step4_defaults_career = selected_career

	species_skill_high_picks.clear()
	species_skill_low_picks.clear()
	_species_skill_resolutions.clear()

	species_talent_group_picks.clear()
	for group in selected_race.racial_talent_choice_groups:
		species_talent_group_picks.append(group[0] if not group.is_empty() else "")
	species_random_talents.clear()
	_species_pending_sub_choice_base = ""
	_species_pending_sub_choice_options = []

	career_skill_allocations.clear()
	_career_skill_resolutions.clear()
	career_talent_pick = ""
	var level := selected_career.get_level(1)
	if level and not level.talents.is_empty():
		career_talent_pick = level.talents[0]

## Resolves a raw Species Skill pool entry to its display string —
## itself unchanged if it isn't an "(any)" qualifier, otherwise the
## skill's own display_name() with whatever specialisation the player
## has picked (defaulting to, and caching, the first option). Reuses
## Advancement's existing "(Any)" helpers rather than a second parallel
## resolution mechanism.
func _resolved_species_skill_entry(raw_entry: String) -> String:
	if not Advancement.is_any_qualifier(raw_entry):
		return raw_entry
	var choices := Advancement.get_skill_situation_choices(raw_entry)
	if choices.is_empty():
		return raw_entry
	var spec: String = _species_skill_resolutions.get(raw_entry, "")
	if spec == "" or not choices.has(spec):
		spec = choices[0]
		_species_skill_resolutions[raw_entry] = spec
	var parsed := Advancement.parse_skill_entry(raw_entry)
	var skill_def: SkillDefinition = parsed[0]
	return skill_def.display_name(spec) if skill_def else raw_entry

func _render_species_skills_section() -> void:
	step_container.add_child(_section_label("Species Skills (%s) — choose %d for +%d Advances, then %d more for +%d." % [
		selected_race.race_name, CharacterCreator.SPECIES_HIGH_PICK_COUNT, CharacterCreator.SPECIES_HIGH_PICK_AMOUNT,
		CharacterCreator.SPECIES_LOW_PICK_COUNT, CharacterCreator.SPECIES_LOW_PICK_AMOUNT]))
	var pool: Array = selected_race.racial_skill_pool
	if not CharacterCreator.species_pool_needs_choice(pool):
		var note := Label.new()
		note.text = "%s's Skill pool has only %d entries — all granted +%d Advances." % [
			selected_race.race_name, pool.size(), CharacterCreator.SPECIES_HIGH_PICK_AMOUNT]
		note.autowrap_mode = TextServer.AUTOWRAP_WORD
		step_container.add_child(note)
		return
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 2)
	for raw_entry in pool:
		grid.add_child(_build_species_skill_row(raw_entry))
	step_container.add_child(grid)

func _build_species_skill_row(raw_entry: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var resolved := _resolved_species_skill_entry(raw_entry)

	var lbl := Label.new()
	lbl.text = resolved
	lbl.custom_minimum_size = Vector2(230, 0)
	row.add_child(lbl)

	if Advancement.is_any_qualifier(raw_entry):
		var choices := Advancement.get_skill_situation_choices(raw_entry)
		if not choices.is_empty():
			var spec_picker := OptionButton.new()
			for c in choices:
				spec_picker.add_item(c)
			var cur_idx: int = choices.find(_species_skill_resolutions.get(raw_entry, choices[0]))
			spec_picker.selected = maxi(0, cur_idx)
			spec_picker.item_selected.connect(func(idx):
				var old_resolved := _resolved_species_skill_entry(raw_entry)
				_species_skill_resolutions[raw_entry] = choices[idx]
				var new_resolved := _resolved_species_skill_entry(raw_entry)
				var hi := species_skill_high_picks.find(old_resolved)
				if hi != -1:
					species_skill_high_picks[hi] = new_resolved
				var lo := species_skill_low_picks.find(old_resolved)
				if lo != -1:
					species_skill_low_picks[lo] = new_resolved
				_render_step()
			)
			row.add_child(spec_picker)

	## Cycles none -> high (+5, if room) -> low (+3, if room) -> none,
	## skipping straight past any tier that's already full rather than
	## getting stuck.
	var state := "high" if species_skill_high_picks.has(resolved) else ("low" if species_skill_low_picks.has(resolved) else "none")
	var state_btn := Button.new()
	var state_text := {"none": "Unpicked", "high": "+%d Advances" % CharacterCreator.SPECIES_HIGH_PICK_AMOUNT, "low": "+%d Advances" % CharacterCreator.SPECIES_LOW_PICK_AMOUNT}
	state_btn.text = state_text[state]
	state_btn.custom_minimum_size = Vector2(110, 0)
	state_btn.pressed.connect(func():
		var cur_resolved := _resolved_species_skill_entry(raw_entry)
		var order := ["none", "high", "low"]
		var idx := order.find(state)
		var next_state := "none"
		for step in range(1, 3):
			var candidate: String = order[(idx + step) % 3]
			if candidate == "none":
				break
			if candidate == "high" and species_skill_high_picks.size() < CharacterCreator.SPECIES_HIGH_PICK_COUNT:
				next_state = "high"
				break
			if candidate == "low" and species_skill_low_picks.size() < CharacterCreator.SPECIES_LOW_PICK_COUNT:
				next_state = "low"
				break
		species_skill_high_picks.erase(cur_resolved)
		species_skill_low_picks.erase(cur_resolved)
		if next_state == "high":
			species_skill_high_picks.append(cur_resolved)
		elif next_state == "low":
			species_skill_low_picks.append(cur_resolved)
		_render_step()
	)
	row.add_child(state_btn)
	return row

func _render_species_talents_section() -> void:
	step_container.add_child(_section_label("Species Talents (%s)" % selected_race.race_name))
	if not selected_race.racial_talents.is_empty():
		var fixed_lbl := Label.new()
		fixed_lbl.text = "Fixed: " + ", ".join(selected_race.racial_talents)
		fixed_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		step_container.add_child(fixed_lbl)

	for i in range(selected_race.racial_talent_choice_groups.size()):
		var group: Array = selected_race.racial_talent_choice_groups[i]
		if group.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text = "Choose 1:"
		row.add_child(lbl)
		var picker := OptionButton.new()
		for opt in group:
			picker.add_item(opt)
		while species_talent_group_picks.size() <= i:
			species_talent_group_picks.append("")
		if species_talent_group_picks[i] == "" or not group.has(species_talent_group_picks[i]):
			species_talent_group_picks[i] = group[0]
		picker.selected = group.find(species_talent_group_picks[i])
		picker.item_selected.connect(func(idx): species_talent_group_picks[i] = group[idx])
		row.add_child(picker)
		step_container.add_child(row)

	if selected_race.racial_random_talent_count > 0:
		step_container.add_child(_build_random_talents_box())

func _build_random_talents_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = "Random Talents: %d / %d rolled" % [species_random_talents.size(), selected_race.racial_random_talent_count]
	box.add_child(lbl)
	if not species_random_talents.is_empty():
		var rolled_lbl := Label.new()
		rolled_lbl.text = ", ".join(species_random_talents)
		rolled_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		box.add_child(rolled_lbl)

	if _species_pending_sub_choice_base != "":
		var pick_row := HBoxContainer.new()
		pick_row.add_theme_constant_override("separation", 8)
		var pick_lbl := Label.new()
		pick_lbl.text = "%s — choose:" % _species_pending_sub_choice_base
		pick_row.add_child(pick_lbl)
		var opt := OptionButton.new()
		for o in _species_pending_sub_choice_options:
			opt.add_item(o)
		pick_row.add_child(opt)
		var confirm := Button.new()
		confirm.text = "Confirm"
		confirm.pressed.connect(func():
			var choice: String = _species_pending_sub_choice_options[opt.selected]
			var final_name := "%s (%s)" % [_species_pending_sub_choice_base, choice]
			_species_pending_sub_choice_base = ""
			_species_pending_sub_choice_options = []
			if _already_has_species_talent(final_name):
				output_label.visible = true
				output_label.text = "[color=#c9995f]You already have %s — roll again.[/color]" % final_name
			else:
				species_random_talents.append(final_name)
			_render_step()
		)
		pick_row.add_child(confirm)
		box.add_child(pick_row)
	elif species_random_talents.size() < selected_race.racial_random_talent_count:
		var roll_btn := Button.new()
		roll_btn.text = "Roll Random Talent"
		roll_btn.pressed.connect(func():
			_roll_one_species_random_talent()
			_render_step()
		)
		box.add_child(roll_btn)
	return box

func _already_has_species_talent(name: String) -> bool:
	return selected_race.racial_talents.has(name) or species_talent_group_picks.has(name) or species_random_talents.has(name)

## Rolls once on RandomTalentsTable, following its own "reroll on
## duplicate" note automatically for the plain (no sub-choice) case; if
## the roll needs a further sub-choice (Acute Sense/Craftsman/
## Resistance) with real options to offer, pauses in
## _species_pending_sub_choice_base for the player to resolve via the
## Confirm button built in _build_random_talents_box above.
func _roll_one_species_random_talent() -> void:
	var attempts := 0
	while attempts < 200:
		attempts += 1
		var base_name := RandomTalentsTable.roll_name()
		if RandomTalentsTable.needs_sub_choice(base_name):
			var td: TalentDefinition = GameData.talent_db.find_by_name(base_name)
			var options: Array = td.situation_options if td else []
			if not options.is_empty():
				_species_pending_sub_choice_base = base_name
				_species_pending_sub_choice_options = options
				return
			## No options in this project's data for this base name
			## (Acute Sense/Resistance currently) — granted as-is rather
			## than fabricating a choice list.
		if _already_has_species_talent(base_name):
			continue
		species_random_talents.append(base_name)
		return

## Resolves a raw Career Skill list entry to its display string — itself
## unchanged if it isn't an "(any)" qualifier, otherwise the skill's own
## display_name() with whatever specialisation the player has picked
## (defaulting to, and caching, the first option). Identical shape to
## _resolved_species_skill_entry() above — deliberately not shared with
## it despite the duplication, since the two caches
## (_career_skill_resolutions vs _species_skill_resolutions) are reset
## independently by _init_step4_defaults() and a career/race change
## shouldn't accidentally cross-contaminate the other's picks.
func _resolved_career_skill_entry(raw_entry: String) -> String:
	if not Advancement.is_any_qualifier(raw_entry):
		return raw_entry
	var choices := Advancement.get_skill_situation_choices(raw_entry)
	if choices.is_empty():
		return raw_entry
	var spec: String = _career_skill_resolutions.get(raw_entry, "")
	if spec == "" or not choices.has(spec):
		spec = choices[0]
		_career_skill_resolutions[raw_entry] = spec
	var parsed := Advancement.parse_skill_entry(raw_entry)
	var skill_def: SkillDefinition = parsed[0]
	return skill_def.display_name(spec) if skill_def else raw_entry

## How many of the Career Skills 40-Advance pool are still unspent —
## shared by the step's own allocator UI and the Next-button gate
## (_render_step_skills_talents) so both always agree.
func _career_skills_remaining() -> int:
	var level := selected_career.get_level(1)
	var skills: Array = level.skills if level else []
	var spent := 0
	for s in skills:
		spent += career_skill_allocations.get(_resolved_career_skill_entry(s), 0)
	return CharacterCreator.CAREER_SKILL_ADVANCE_POOL - spent

func _render_career_skills_section() -> void:
	var level := selected_career.get_level(1)
	var skills: Array = level.skills if level else []
	var remaining: int = _career_skills_remaining()
	step_container.add_child(_section_label("Career Skills (%s) — allocate %d Advances (max %d per Skill): %d remaining" % [
		selected_career.career_name, CharacterCreator.CAREER_SKILL_ADVANCE_POOL, CharacterCreator.CAREER_SKILL_ADVANCE_CAP, remaining]))
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 2)
	for s in skills:
		grid.add_child(_build_career_skill_row(s, remaining))
	step_container.add_child(grid)

## `raw_entry` is exactly as it appears in the Career's own skill list —
## a plain skill name ("Athletics"), or a grouped skill's "(Any)"
## qualifier ("Entertain (Any)", "Perform (Any)", "Play (Any)", ...).
## Real bug fix, per the request ("add the specialisations for group
## skills with (any) labels like Entertain Perform and Play"): the
## stepper below used to allocate Advances directly under the literal
## raw_entry string, including the un-resolved "(Any)" ones — a real,
## silent bug (see _career_skill_resolutions' own declaration comment),
## since "Entertain (Any)" itself was never a real skill any Test could
## ever roll against. Now mirrors _build_species_skill_row(): an "(Any)"
## entry gets its own specialisation dropdown alongside the usual +/-
## stepper, and every allocation is read from/written to the RESOLVED
## concrete name (e.g. "Entertain (Comedy)") — `career_skill_allocations`
## only ever holds real, purchasable skill names once this runs.
func _build_career_skill_row(raw_entry: String, remaining: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var resolved := _resolved_career_skill_entry(raw_entry)

	var lbl := Label.new()
	lbl.text = resolved
	lbl.custom_minimum_size = Vector2(230, 0)
	row.add_child(lbl)

	if Advancement.is_any_qualifier(raw_entry):
		var choices := Advancement.get_skill_situation_choices(raw_entry)
		if not choices.is_empty():
			var spec_picker := OptionButton.new()
			for c in choices:
				spec_picker.add_item(c)
			var cur_idx: int = choices.find(_career_skill_resolutions.get(raw_entry, choices[0]))
			spec_picker.selected = maxi(0, cur_idx)
			spec_picker.item_selected.connect(func(idx):
				## Moves any Advances already spent under the old
				## specialisation over to the newly-picked one, rather
				## than silently orphaning them under a key nothing else
				## will ever look up again — the player changing their
				## mind about "Fiddle" vs "Lute" shouldn't cost them the
				## points they'd already put in.
				var old_key := _resolved_career_skill_entry(raw_entry)
				_career_skill_resolutions[raw_entry] = choices[idx]
				var new_key := _resolved_career_skill_entry(raw_entry)
				if old_key != new_key:
					var moved: int = career_skill_allocations.get(old_key, 0)
					if moved > 0:
						career_skill_allocations.erase(old_key)
						career_skill_allocations[new_key] = moved
				_render_step()
			)
			row.add_child(spec_picker)

	var current: int = career_skill_allocations.get(resolved, 0)
	var val_lbl := Label.new()
	val_lbl.text = "+%d" % current
	val_lbl.custom_minimum_size = Vector2(36, 0)
	row.add_child(val_lbl)
	var minus := Button.new()
	minus.text = "-"
	minus.disabled = current <= 0
	minus.pressed.connect(func():
		career_skill_allocations[resolved] = maxi(0, current - 1)
		_render_step()
	)
	row.add_child(minus)
	var plus := Button.new()
	plus.text = "+"
	plus.disabled = current >= CharacterCreator.CAREER_SKILL_ADVANCE_CAP or remaining <= 0
	plus.pressed.connect(func():
		career_skill_allocations[resolved] = current + 1
		_render_step()
	)
	row.add_child(plus)
	return row

func _render_career_talent_section() -> void:
	var level := selected_career.get_level(1)
	var talents: Array = level.talents if level else []
	if talents.is_empty():
		return
	step_container.add_child(_section_label("Career Talent (%s) — choose 1" % selected_career.career_name))
	var picker := OptionButton.new()
	for t in talents:
		picker.add_item(t)
	if career_talent_pick == "" or not talents.has(career_talent_pick):
		career_talent_pick = talents[0]
	picker.selected = talents.find(career_talent_pick)
	picker.item_selected.connect(func(idx): career_talent_pick = talents[idx])
	step_container.add_child(picker)

## --- Step 5: Trappings (p.37) -------------------------------------------------
## Two separate grants, per the book: Class Trappings (by
## career_class — general kit every member of that Class starts with)
## ON TOP OF the Career's own Tier-1 Trappings (level.trappings) — not
## a replacement for it.

func _render_step_trappings() -> void:
	if _trappings_race != selected_race or _trappings_career != selected_career:
		_init_trappings()

	step_container.add_child(_section_label("Class Trappings (%s)" % selected_career.career_class))
	var class_lbl := RichTextLabel.new()
	class_lbl.bbcode_enabled = true
	class_lbl.fit_content = true
	class_lbl.custom_minimum_size = Vector2(0, 40)
	var class_display: Array = class_trappings_rolled.duplicate()
	if selected_career.career_class == "Rogue":
		class_display.append(rogue_hood_or_mask)
	class_lbl.text = ", ".join(class_display) if not class_display.is_empty() else "(none)"
	step_container.add_child(class_lbl)

	if selected_career.career_class == "Rogue":
		var hood_row := HBoxContainer.new()
		hood_row.add_theme_constant_override("separation", 8)
		var hood_lbl := Label.new()
		hood_lbl.text = "Hood or Mask:"
		hood_row.add_child(hood_lbl)
		var hood_picker := OptionButton.new()
		for o in ClassTrappingsTable.ROGUE_HOOD_OR_MASK_OPTIONS:
			hood_picker.add_item(o)
		hood_picker.selected = ClassTrappingsTable.ROGUE_HOOD_OR_MASK_OPTIONS.find(rogue_hood_or_mask)
		hood_picker.item_selected.connect(func(idx):
			rogue_hood_or_mask = ClassTrappingsTable.ROGUE_HOOD_OR_MASK_OPTIONS[idx]
			_render_step()
		)
		hood_row.add_child(hood_picker)
		step_container.add_child(hood_row)

	step_container.add_child(HSeparator.new())
	step_container.add_child(_section_label("Career Trappings (%s)" % selected_career.career_name))
	var level := selected_career.get_level(1)
	var trap_lbl := RichTextLabel.new()
	trap_lbl.bbcode_enabled = true
	trap_lbl.fit_content = true
	trap_lbl.custom_minimum_size = Vector2(0, 40)
	var trappings: Array = level.trappings if level else []
	trap_lbl.text = (", ".join(trappings) if not trappings.is_empty() else "(none)") + ", Healing Draught"
	step_container.add_child(trap_lbl)

	step_container.add_child(_nav_row(true, "Create Character", true, _on_finalize_character))

## Rolls the Class's dice-quantity Trappings (Academics' Parchment,
## Rogues' Matches) ONCE and caches them, so what's shown here is
## exactly what gets granted at finalize — rerolling on every re-render
## (e.g. from picking Hood vs Mask) would show the player one quantity
## and grant a different one. The Rogue Hood-or-Mask choice itself is
## NOT cached here — it's re-appended fresh from rogue_hood_or_mask
## wherever it's needed, since the player can change their mind freely.
func _init_trappings() -> void:
	_trappings_race = selected_race
	_trappings_career = selected_career
	class_trappings_rolled.clear()
	## grant_to() appends the Hood/Mask pick as the LAST entry for
	## Rogues — pop it back off immediately so class_trappings_rolled
	## only ever holds the dice-resolved/fixed portion; the picker
	## above re-appends the player's current choice for display, and
	## _on_finalize_character does the same for the final grant.
	ClassTrappingsTable.grant_to(selected_career.career_class, class_trappings_rolled, rogue_hood_or_mask)
	if selected_career.career_class == "Rogue" and not class_trappings_rolled.is_empty():
		class_trappings_rolled.remove_at(class_trappings_rolled.size() - 1)

func _on_finalize_character() -> void:
	var total_bonus_xp := bonus_xp_species + bonus_xp_career + bonus_xp_attributes
	var final_class_trappings: Array = class_trappings_rolled.duplicate()
	if selected_career.career_class == "Rogue":
		final_class_trappings.append(rogue_hood_or_mask)
	## advance_choices is deliberately NOT passed to create_character()
	## here (left {}) — it rolls its own throwaway base Characteristics
	## internally, which the very next line replaces wholesale with
	## rolled_stats anyway, so applying the allocation before that
	## overwrite would both waste it AND double-count it into
	## character.characteristic_advances once the real application
	## happens below.
	current_character = CharacterCreator.create_character(
		char_name, selected_race, selected_career, {},
		species_talent_group_picks, total_bonus_xp, species_skill_high_picks, species_skill_low_picks,
		species_random_talents, career_skill_allocations, career_talent_pick, final_class_trappings
	)
	current_character.gender = char_gender
	## Overwrite the random roll with the same stats already shown to
	## the player during the Attributes step, rather than rolling a
	## fresh, different set now — create_character() rolls its own by
	## default, which would silently discard what was actually shown
	## and (if applicable) rewarded Bonus XP for keeping. Reapply the
	## Advance Characteristics allocation on top of that canonical
	## displayed roll, same reasoning.
	current_character.characteristics = rolled_stats
	CharacterCreator.apply_advance_characteristics(current_character, advance_choices)
	current_character.recompute_max_wounds()
	current_character.wounds_current = current_character.wounds_max

	## Per the request: Extra Points spent on Fate/Resilience during
	## the Attributes step — added on top of the race's own base
	## starting_fate/starting_resilience (already applied inside
	## create_character() above), never replacing them.
	current_character.fate_points += extra_points_fate
	current_character.fortune_points += extra_points_fate
	current_character.resilience += extra_points_resilience
	current_character.resolve += extra_points_resilience

	if current_character.equipped_weapon == "":
		current_character.equipped_weapon = "Sword"
	if current_character.equipped_armour.is_empty():
		current_character.equipped_armour = ["Leather Jack"]

	_pending_overwrite_slot = -1
	_render_character_summary()
	_populate_begin_box()

func _render_character_summary() -> void:
	var c := current_character
	var s := c.characteristics
	var lines: Array[String] = []
	lines.append("[b]%s[/b] — %s %s" % [c.character_name, c.race.race_name, c.career.career_name])
	lines.append("")
	var char_line := "[b]Characteristics[/b]  "
	for key in CharacteristicSet.KEYS:
		char_line += "%s: %d   " % [CharacteristicSet.SHORT_NAMES[key], s.get_value(key)]
	lines.append(char_line)
	lines.append("Wounds: %d/%d   Fate: %d   Resilience: %d   XP: %d" % [
		c.wounds_current, c.wounds_max, c.fate_points, c.resilience, c.experience_total])
	lines.append("Trappings: " + (", ".join(c.inventory) if not c.inventory.is_empty() else "(none)"))
	step_container.add_child(HSeparator.new())
	var summary_lbl := RichTextLabel.new()
	summary_lbl.bbcode_enabled = true
	summary_lbl.fit_content = true
	summary_lbl.custom_minimum_size = Vector2(0, 80)
	summary_lbl.text = "\n".join(lines)
	step_container.add_child(summary_lbl)

## Shows one button per save slot so the player picks where their new,
## persistent character will live. Occupied slots pop the centered
## OverwriteConfirmOverlay (see _on_begin_pressed) rather than
## overwriting silently.
func _populate_begin_box() -> void:
	for child in begin_box.get_children():
		child.queue_free()
	begin_header.visible = true
	begin_box.visible = true
	## Per the request: reached via the Party Companion Maker — no
	## slot to choose, since there's already a real game in progress.
	## One button, straight into the current active party.
	if _is_companion_mode:
		begin_header.text = "Ready to Join"
		var btn := Button.new()
		btn.text = "Add %s to the Party" % current_character.character_name
		btn.pressed.connect(_on_add_companion_pressed)
		begin_box.add_child(btn)
		return
	for slot in range(SaveManager.SLOT_COUNT):
		var summary := SaveManager.get_save_summary(slot)
		var btn := Button.new()
		if summary.is_empty():
			btn.text = "Begin in Slot %d (empty)" % (slot + 1)
		else:
			btn.text = "Begin in Slot %d — overwrites %s" % [slot + 1, ", ".join(summary["party_names"])]
		btn.pressed.connect(func(): _on_begin_pressed(slot, not summary.is_empty()))
		begin_box.add_child(btn)

## Per the request: overwriting an occupied slot now pops a centered
## warning overlay (OverwriteConfirmOverlay, built in CharacterCreation.
## tscn — same Dim+CenterContainer+PanelContainer pattern PauseMenu.tscn
## already uses for its own modal) instead of the old "click the same
## button again" in-place confirmation, so the warning is impossible to
## miss and names exactly what's about to be deleted.
func _on_begin_pressed(slot: int, occupied: bool) -> void:
	if not occupied:
		_begin_adventure(slot)
		return
	var summary := SaveManager.get_save_summary(slot)
	_pending_overwrite_slot = slot
	overwrite_warning_label.text = "Slot %d already has a save (%s). Starting here will permanently delete it — this can't be undone." % [
		slot + 1, ", ".join(summary.get("party_names", []))]
	overwrite_confirm_overlay.visible = true

func _on_overwrite_confirmed() -> void:
	overwrite_confirm_overlay.visible = false
	var slot := _pending_overwrite_slot
	_pending_overwrite_slot = -1
	if slot != -1:
		_begin_adventure(slot)

func _on_overwrite_cancelled() -> void:
	overwrite_confirm_overlay.visible = false
	_pending_overwrite_slot = -1

## Per the request: the actual completion of the Party Companion
## Maker flow — adds the finished character straight to the current
## real party (the 4-member cap is already enforced by the NPC before
## this screen was ever opened) and returns to the game in progress.
func _on_add_companion_pressed() -> void:
	if current_character == null:
		return
	current_character.allegiance = "ally"
	GameState.add_party_member(current_character)
	GameState.autosave()
	get_tree().change_scene_to_file("res://scenes/Overworld.tscn")

func _begin_adventure(slot: int) -> void:
	if current_character == null:
		return
	var starting_party: Array[Character] = [current_character]
	SaveManager.save_game(starting_party, 0, slot)
	## Per the reported bug: GameState.player_character's setter (see
	## game_state.gd) only replaces whichever party slot is currently
	## active — it does NOT clear the rest of the array. If the player
	## had previously loaded/played a multi-member party (Slot 1, say)
	## and then came back here to create a brand new character for a
	## different slot, that old party.clear()-less assignment left the
	## other members from the earlier session still in GameState.party,
	## so the new character "started with the group" a totally
	## different save had built. A fresh adventure must always start
	## from a clean one-member party — assign GameState.party directly,
	## exactly like the Continue flow above already does.
	GameState.party = starting_party
	GameState.active_party_index = 0
	## A brand new adventure in this slot starts with no one waiting to
	## be re-recruited either — same reasoning as the party.clear() fix
	## above, just for the dismissed-companions half of GameState.
	GameState.dismissed_companions = []
	GameState.reset_world_state()
	GameState.current_slot = slot
	get_tree().change_scene_to_file("res://scenes/Overworld.tscn")

