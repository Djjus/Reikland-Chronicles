extends Control
class_name CityScreen
## New City Screen feature: a zoomable image-map screen for a town's
## own interior (Ubersreik, to start with) — a different paradigm from
## the tile-grid LocalMapDefinition system Giessingen/Gotheim use (see
## scripts/resources/city_location_definition.gd's own header for
## why). Reached from Overworld._offer_enter_location() via a
## LocationDefinition whose city_screen_scene_path is set.
##
## Deliberate, explicit design choice: this screen's own InfoBar/party
## panel code below is a fresh, standalone duplicate of Overworld.gd's
## equivalent functions rather than a shared refactor — Overworld.gd
## is a large, already-working 6700+ line file, and refactoring it to
## share code with a brand-new screen risked destabilizing it for no
## real benefit (both copies are individually simple enough to
## maintain). Visual language matches on purpose; the code doesn't.

const CHARACTER_MENU_SCENE := preload("res://scenes/CharacterMenu.tscn")
## Follow-up request ("allow saving on city maps"): this game has no
## manual Save — GameState.autosave() runs continuously and the Esc
## PauseMenu (Resume/Switch Character/Main Menu/Quit) is what actually
## triggers/guarantees it at the moments that matter (see
## pause_menu_screen.gd's own header). CityScreen never wired the
## pause menu in at all when it was first built — Esc did nothing here,
## and the same "autosave when the character menu closes" and periodic
## autosave-timer safety nets Overworld has were both missing too — so
## progress made purely on a City Screen visit (without ever traveling,
## which does already autosave — see _run_travel) could go unsaved
## until the player left back to the World Map. Same fix, same pattern,
## mirrored from overworld.gd's own _ready()/_unhandled_input().
const PAUSE_MENU_SCENE := preload("res://scenes/PauseMenu.tscn")
const SWITCH_CHARACTER_TAB_INDEX := 7   ## Stats, Equipment, Inventory, Spellbook, Career, Group, Journal, Switch Character — matches overworld.gd's own constant
const CITY_MAP_TEXTURE := preload("res://assets/maps/ubersreik_city_map.png")
const CITY_LOCATIONS := preload("res://data/maps/ubersreik_city_locations.tres")

## New follow-up request ("phase the ubersreik background map by time
## of day using these images, start phasing in gradually 2 hrs before
## the time of the image"): four keyframe background images at fixed
## hours of the day, blended into one another as GameState.time_minutes
## moves — see _update_time_of_day_background() below for the actual
## blend math. "hour" 8 reuses the pre-existing CITY_MAP_TEXTURE (the
## uploaded 8am source image is pixel-identical to it) rather than a
## second copy of the same art.
const CITY_MAP_TEXTURE_8PM := preload("res://assets/maps/ubersreik_city_map_8pm.jpg")
const TIME_OF_DAY_KEYFRAMES := [
	{"hour": 2, "texture": preload("res://assets/maps/ubersreik_city_map_2am.jpg")},
	{"hour": 8, "texture": preload("res://assets/maps/ubersreik_city_map.png")},
	{"hour": 14, "texture": preload("res://assets/maps/ubersreik_city_map_2pm.png")},
	{"hour": 20, "texture": CITY_MAP_TEXTURE_8PM},
]
## How far ahead of a keyframe's own hour it starts crossfading in.
const TIME_OF_DAY_BLEND_MINUTES := 120

## Per the request ("use the new portraits in all Icon, in and out of
## combat"): the old wound-tier PORTRAIT_SETS table (a duplicate of
## Overworld.gd's own) is gone — every portrait on this screen now comes
## from CareerPortraits (scripts/core/career_portraits.gd) instead. See
## _current_party_texture() and _refresh_party_panel() below.

const PARTY_PANEL_SIZE := Vector2(144, 44)
const PARTY_PANEL_HP_COLUMN_WIDTH := 96
const PARTY_NAME_MAX_FONT_SIZE := 10
const PARTY_NAME_MIN_FONT_SIZE := 7

## Measured directly off the source Gamemaster map's own "SCALE" box
## (0/100/200/300/400 yard marks spanning 355px of the 2340px-wide
## clean map image — see the City Screen data-prep work): real yards
## per background-image pixel, used to turn a marker-to-marker pixel
## distance into an actual walking distance. 400 yards / 355px.
const YARDS_PER_PIXEL := 400.0 / 355.0

## Real, on-foot walking pace in yards per minute, per point of
## Movement. Deliberately NOT a 1:1 reuse of GameState.
## minutes_per_tile_fraction()'s "1 tile per 1/Movement minute" —
## that formula's "tile" is a small, deliberately abstracted unit
## sized for turn-by-turn local-map movement, not a real yard, and
## reusing it verbatim against this screen's real yard-scale distances
## produced absurd results in testing (a Movement-4 character taking
## over two and a half hours to cross a few streets). Calibrated
## instead against a real, believable walking pace: an average human
## (Movement 4) covers roughly 3mph — about 88 yards/minute — so
## 88 / 4 = 22 yards/minute per point of Movement. Still honors the
## request's own "estimate distance and time by the scale on the map"
## and the party's-slowest-member convention; just anchored to a real
## walking speed instead of the tile-grid's own tuned-for-tactics pace.
##
## Per the follow-up request ("slow down moving a bit too, it should
## take about 3 times as long"): the base 22.0 pace above is now
## divided by 3 — a deliberate, separate slowdown on top of (not
## instead of) the real-road routing below, which on its own already
## lengthens most trips since a real route rarely runs in a straight
## line.
const YARDS_PER_MINUTE_PER_MOVEMENT := 22.0 / 3.0

@onready var map_view: CityMapView = %MapView
@onready var party_panel_row: HBoxContainer = %PartyPanelRow
@onready var xp_label: Label = %XPLabel
@onready var gold_label: Label = %GoldLabel
@onready var time_label: Label = %TimeLabel
@onready var date_label: Label = %DateLabel
@onready var legend_list: VBoxContainer = %LegendList
@onready var hud_label: Label = %HudLabel
@onready var encounter_box: PanelContainer = %EncounterBox
@onready var encounter_label: Label = %EncounterLabel
## Follow-up request ("allow user to click on travel confirmation pop
## ups option"): the Y/N choice used to be baked into encounter_label's
## own text (a plain Label, unclickable) — now a real two-button row,
## shown only while a Y/N confirm is actually up (see
## _start_confirm_prompt/_show_lore below, which toggle its visibility)
## so it stays hidden during a plain Lore readout (no choice to make
## there).
@onready var confirm_choice_row: HBoxContainer = %EncounterChoiceRow
@onready var confirm_yes_button: Button = %ConfirmYesButton
@onready var confirm_no_button: Button = %ConfirmNoButton
@onready var travel_progress_panel: VBoxContainer = %TravelProgressPanel
@onready var travel_stage_label: Label = %TravelStageLabel
@onready var travel_progress_bar: ProgressBar = %TravelProgressBar

var character_menu: CanvasLayer = null
var pause_menu: CanvasLayer = null

var city_id: String = "ubersreik"
var location_list: CityLocationList = null
var awaiting_travel_confirm: bool = false
var _travel_confirmed: bool = false
var _pending_travel_location: CityLocationDefinition = null
var _travel_in_progress: bool = false

## Follow-up request ("left clicking a visible POI in the city map
## should not trigger travel. Instead left clicking on a POI will
## select it, and show a radial menu around it... Lore... and
## Travel"): whether the bottom info box is currently showing a Lore
## readout rather than a Y/N confirm prompt — kept as its own flag
## (distinct from awaiting_travel_confirm) since it's dismissed
## differently (Space/Escape/clicking elsewhere, no Y/N choice).
var _lore_open: bool = false

## Short flavour text per CityLocationDefinition.category, shown by the
## radial menu's Lore button. The 71-location dataset (see
## city_location_definition.gd's own header) only has name/district/
## category fields, not a hand-written blurb per location — a full
## per-location lore pass wasn't part of this request's scope, so this
## gives every location a real, on-theme sentence without requiring 71
## new data entries.
const CATEGORY_LORE := {
	"gate": "A gate through the city walls, controlling who comes and goes.",
	"tavern": "A tavern — food, drink, lodging, and the latest rumours.",
	"guild": "A guildhall, home to one of the city's trades or professions.",
	"shop": "A shop trading in local goods and wares.",
	"temple": "A temple, a place of worship and pilgrimage.",
	"landmark": "A notable landmark of the city.",
	"watch": "A post of the city watch, keeping the peace.",
	"residence": "A private residence.",
	"castle": "A fortified stronghold overlooking the city.",
}

## Per the request ("always allow WASD movement and hotkey space to
## accept selected for these all these types of pop ups") — same
## WASD-selects/Space-accepts scheme as Overworld's own confirm
## prompts (see overworld.gd's own _confirm_selected_yes comment):
## Left/Up selects [Y], Right/Down selects [N], Space accepts
## whichever is highlighted. The Y/N keys keep working unchanged.
##
## Follow-up request ("allow user to click on travel confirmation pop
## ups option, and make the focused WASD option white in color to make
## it more distinct"): the Y/N choice is now two real Button nodes
## (confirm_yes_button/confirm_no_button) instead of text baked into
## encounter_label, so it can actually be clicked — see their
## pressed.connect() wiring in _ready(). The base prompt text alone
## stays on encounter_label; _render_confirm_prompt() below now colors
## whichever button WASD currently has focused pure white (unfocused
## stays the previous muted gold) instead of just prefixing an arrow,
## per the same request — the arrow prefix is kept too, on the button
## label itself, since the two cues together read more clearly than
## either alone.
const CONFIRM_FOCUSED_COLOR := Color(1, 1, 1, 1)
const CONFIRM_UNFOCUSED_COLOR := Color(0.78, 0.7, 0.55, 1)
var _confirm_selected_yes: bool = true
var _confirm_prompt_base: String = ""
var _confirm_prompt_yes_label: String = ""
var _confirm_prompt_no_label: String = ""

func _start_confirm_prompt(base: String, yes_label: String, no_label: String) -> void:
	_confirm_prompt_base = base
	_confirm_prompt_yes_label = yes_label
	_confirm_prompt_no_label = no_label
	_confirm_selected_yes = true
	confirm_choice_row.visible = true
	_render_confirm_prompt()

func _render_confirm_prompt() -> void:
	encounter_label.text = _confirm_prompt_base
	var yes_mark := "► " if _confirm_selected_yes else ""
	var no_mark := "► " if not _confirm_selected_yes else ""
	confirm_yes_button.text = "%s[Y] %s" % [yes_mark, _confirm_prompt_yes_label]
	confirm_no_button.text = "%s[N] %s" % [no_mark, _confirm_prompt_no_label]
	confirm_yes_button.add_theme_color_override("font_color", CONFIRM_FOCUSED_COLOR if _confirm_selected_yes else CONFIRM_UNFOCUSED_COLOR)
	confirm_no_button.add_theme_color_override("font_color", CONFIRM_UNFOCUSED_COLOR if _confirm_selected_yes else CONFIRM_FOCUSED_COLOR)

func _ready() -> void:
	city_id = GameState.pending_city_id if GameState.pending_city_id != "" else "ubersreik"
	GameState.pending_city_id = ""
	## Follow-up request's own reported bug ("its not saving the city
	## still, i always enter the game outside the city on the overworld
	## map"): marks this city as the currently-active one for as long
	## as this screen (or a Tavern/Shop reached from it) stays the
	## player's real location — see GameState.last_active_city_id's own
	## declaration comment. Cleared by _offer_leave_city() once a gate's
	## "Leave City" is actually confirmed.
	GameState.last_active_city_id = city_id

	location_list = CITY_LOCATIONS

	map_view.set_background_reference_size(CITY_MAP_TEXTURE.get_size())
	## Follow-up request ("give the Ubersreik 8pm map a slight animated
	## twinkle on the small doted lights around the map") — see
	## CityMapView.night_lights_texture's own declaration comment.
	map_view.night_lights_texture = CITY_MAP_TEXTURE_8PM
	map_view.night_lights_positions = UbersreikNightLights.POSITIONS
	_update_time_of_day_background()
	map_view.party_token_texture = _current_party_texture()
	map_view.party_token_modulate = CareerPortraits.wound_modulate_for_character(GameState.player_character)
	map_view.location_clicked.connect(_on_location_clicked)
	## Follow-up request (radial POI menu): background_clicked/right_clicked
	## both mean "deselect whatever's currently selected" — background_clicked
	## already existed (unused until now) for exactly this purpose.
	map_view.background_clicked.connect(_on_map_background_clicked)
	map_view.right_clicked.connect(_on_map_right_clicked)
	map_view.radial_action.connect(_on_radial_action)
	map_view.party_token_pos = _party_start_position()
	## Follow-up request ("always show... trigger it after travel
	## finishes"): also brings the home radial up from the very first
	## frame this screen is shown, not just after the first travel.
	_refresh_home_radial()

	character_menu = CHARACTER_MENU_SCENE.instantiate()
	add_child(character_menu)
	## Was a no-op (func(): pass) — see PAUSE_MENU_SCENE's own comment
	## above for why that meant progress could go unsaved on this
	## screen. Mirrors Overworld's own _on_character_menu_closed, minus
	## the sprite/HUD refresh calls that only make sense on the World
	## Map — CityScreen's own _update_info_bar() already covers the
	## equivalent (party portrait/HP refresh) here.
	character_menu.closed.connect(_on_character_menu_closed)

	pause_menu = PAUSE_MENU_SCENE.instantiate()
	add_child(pause_menu)
	pause_menu.switch_character_requested.connect(_on_switch_character_requested)

	## Follow-up request ("allow user to click on travel confirmation pop
	## ups option"): clicking either button commits that choice
	## immediately — same as pressing Y/N directly, regardless of which
	## one WASD currently has focused. Guarded on awaiting_travel_confirm
	## since the row is only ever visible while it's true, but a stray
	## click landing the same frame the confirm already resolved another
	## way (e.g. a key press) shouldn't double-resolve it.
	confirm_yes_button.pressed.connect(func():
		if not awaiting_travel_confirm:
			return
		_travel_confirmed = true
		awaiting_travel_confirm = false
	)
	confirm_no_button.pressed.connect(func():
		if not awaiting_travel_confirm:
			return
		_travel_confirmed = false
		awaiting_travel_confirm = false
	)

	## Same periodic safety-net autosave Overworld's own _ready() sets
	## up, so time spent purely browsing/panning this screen (no travel,
	## no menu close) still gets saved regularly.
	var autosave_timer := Timer.new()
	autosave_timer.wait_time = 6.0
	autosave_timer.autostart = true
	autosave_timer.timeout.connect(func(): GameState.autosave())
	add_child(autosave_timer)

	_rebuild_legend()
	_update_info_bar()

	## Deferred so the control has its real laid-out size (fit_to_view
	## reads `size`, which is still the scene's placeholder 0x0 during
	## _ready() itself).
	call_deferred("_initial_fit")

func _initial_fit() -> void:
	map_view.fit_to_view()

func _on_character_menu_closed() -> void:
	GameState.autosave()
	map_view.party_token_texture = _current_party_texture()
	map_view.party_token_modulate = CareerPortraits.wound_modulate_for_character(GameState.player_character)
	_update_info_bar()

func _on_switch_character_requested() -> void:
	pause_menu.close()
	character_menu.open(SWITCH_CHARACTER_TAB_INDEX)

## Where the party's group token starts — resumes exactly where it was
## left on a previous visit (GameState.city_player_positions), or the
## South Gate (location 4 — the main road entrance from the World Map)
## the very first time this city is ever entered.
func _party_start_position() -> Vector2:
	if GameState.city_player_positions.has(city_id):
		return GameState.city_player_positions[city_id]
	for loc in location_list.locations:
		if loc.location_id == 4:
			return loc.map_position
	return Vector2(0.5, 0.5)

func _current_party_texture() -> Texture2D:
	## Per the request ("use the new portraits in all Icon, in and out of
	## combat"): the map token now shows the player's own Career
	## portrait instead of the old generic wound-tier art.
	return CareerPortraits.get_portrait_for_character(GameState.player_character)

## Left-hand transparent legend — per the request, only unlocked
## locations are ever listed (matching what has a real marker on the
## map itself). Each entry doubles as a map-marker click: selects the
## location and opens its radial menu (see _select_location).
##
## Follow-up request ("group the list by district, and down size the
## fonts... so it doesn't scroll sideways"): entries are now grouped
## under a header per CityLocationDefinition.district (alphabetical,
## "Other" for the rare unset case), and both the district headers and
## the location buttons use a smaller font with clipped/ellipsized text
## — see LegendScroll's own horizontal_scroll_mode in CityScreen.tscn,
## set to disabled as a hard backstop so an unusually long name can
## never force sideways scrolling again, just truncates instead.
func _rebuild_legend() -> void:
	for child in legend_list.get_children():
		legend_list.remove_child(child)
		child.queue_free()

	var unlocked: Array = []
	for loc in location_list.locations:
		if loc.unlocked:
			unlocked.append(loc)
	map_view.locations = unlocked

	var title := Label.new()
	title.text = "UBERSREIK"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	legend_list.add_child(title)

	var sep := HSeparator.new()
	legend_list.add_child(sep)

	var by_district: Dictionary = {}   ## String -> Array[CityLocationDefinition]
	for loc in unlocked:
		var d: String = loc.district if loc.district != "" else "Other"
		if not by_district.has(d):
			by_district[d] = []
		by_district[d].append(loc)
	var districts: Array = by_district.keys()
	districts.sort()

	for d in districts:
		var district_label := Label.new()
		district_label.text = String(d).to_upper()
		district_label.add_theme_font_size_override("font_size", 9)
		district_label.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
		district_label.clip_text = true
		legend_list.add_child(district_label)
		for loc in by_district[d]:
			var btn := Button.new()
			btn.text = loc.location_name
			btn.flat = true
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.clip_text = true
			btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			btn.add_theme_font_size_override("font_size", 10)
			btn.pressed.connect(_select_location.bind(loc, true))
			legend_list.add_child(btn)
	## Follow-up request ("remove that option from the legend list. the
	## only way to leave Ubersreik is now via the gates"): the legend's
	## always-visible "Leave for the World Map" button used to sit here,
	## reachable from anywhere on the map regardless of where the party
	## actually was — removed entirely; leaving now only ever happens
	## via a real gate's own "Leave City" radial action (see
	## _radial_actions_for/_offer_leave_city).

## True while any modal-ish UI (character/pause menu, an in-flight
## travel walk, or an awaiting Y/N confirm) should swallow map clicks —
## shared by every new selection/radial/deselect entry point below,
## same guard _on_location_clicked/_offer_leave_city already used
## inline before this follow-up request added more callers of it.
func _map_click_guard_active() -> bool:
	return character_menu.visible or pause_menu.visible or _travel_in_progress or awaiting_travel_confirm

func _on_location_clicked(loc: CityLocationDefinition) -> void:
	_select_location(loc, false)

## True while the party's own token is standing exactly on `loc` — the
## single condition that decides which of the two radial menus (home vs
## target) a given location belongs to. Same epsilon _offer_travel_to's
## own "already there" early-out uses.
func _is_party_here(loc: CityLocationDefinition) -> bool:
	return loc.map_position.distance_to(map_view.party_token_pos) < 0.001

## Follow-up request ("always show the Leave City, Stay and Enter
## radial options when the party is at a location... show click focused
## options Lore/Travel at the same time"): clicking a marker now only
## ever opens the TARGET radial (Lore/Travel) — the home radial (Lore +
## whichever of Stay/Enter/Leave City applies) is no longer opened by a
## click at all; it's kept up automatically by _refresh_home_radial()
## for as long as the party is actually standing there (see that
## function's own comment). Clicking the location the party is ALREADY
## at would just be a second, redundant copy of the same radial that's
## already showing, so that case is a no-op for the radial itself
## (still clears any other target that happened to be selected, and
## still recenters for a legend click).
## `recenter` is true only for legend clicks — a legend entry can be
## for a location currently panned off-screen, in which case its
## radial menu would open somewhere the player can't see or click;
## a direct marker click is, by definition, already on-screen, so it
## deliberately doesn't recenter (an unrequested camera jump on a
## precise click the player can already see would just be jarring).
func _select_location(loc: CityLocationDefinition, recenter: bool) -> void:
	if _map_click_guard_active():
		return
	if _is_party_here(loc):
		_deselect_target()
		if recenter:
			map_view.center_on_content_pos(loc.map_position)
		return
	map_view.target_location = loc
	map_view.target_actions = _radial_actions_for(loc)
	map_view.target_radial_open = true
	_lore_open = false
	encounter_box.visible = false
	if recenter:
		map_view.center_on_content_pos(loc.map_position)
	map_view.queue_redraw()

## New Tavern Screen follow-up ("reached via a Tavern/Inn POI's radial
## menu"): a third "Stay" button, for tavern-category locations.
## New City Shop follow-up ("copy the giessingen shop and put it into
## ubersreik... allow access via travel in the city"): same treatment
## for shop-category locations — an "Enter" button (a location is never
## more than one category at once, so there's never a case needing more
## than one of these).
##
## Follow-up request ("show option at the location the player is at,
## move stay/enter to this radial, remove these while travelling —
## active POI target will still show Lore and Travel"): Stay/Enter used
## to appear on ANY click of a tavern/shop marker, even one the party
## hadn't actually walked to yet — you could rent a room or shop at a
## location from clear across the city. Now they only ever appear on
## the radial for the location the party's own token is CURRENTLY
## standing on (`is_here` below); every other, not-yet-travelled-to
## location keeps exactly Lore + Travel, regardless of its category.
## Travel itself is dropped from the current-location radial instead —
## walking to where you already are was always a silent no-op (see
## _offer_travel_to's own early-out), so there's nothing useful left
## for that button to do there.
##
## Follow-up request ("add a Leave City option to the north east and
## south gates... remove that option from the legend list. the only
## way to leave Ubersreik is now via the gates"): same is_here-gated
## treatment as Stay/Enter, for gate-category locations — "Leave City"
## only ever appears once the party has actually walked to a real gate,
## same as every other category-specific action here. Applies to any
## gate (not hand-picked per gate name), so Water Gate gets it too the
## moment it's ever unlocked, with no further code changes needed.
##
## Follow-up request ("have the shops (including future ones in the
## city) close at 8pm and open at 8am, gray out the Enter option and
## change it to Closed... show tool tip: Opening hours 8am-8pm" —
## explicitly NOT taverns/inns, which stay open around the clock): a
## shop's own "Enter" entry is swapped for a disabled "Closed" one
## outside SHOP_OPEN_MINUTES..SHOP_CLOSE_MINUTES — see _is_shop_open()'s
## own comment. Gated purely on loc.category == "shop", same as the
## Enter button itself, so any future shop-category location picks this
## up automatically with no further code changes needed, same as the
## gate-only Leave City treatment above.
func _radial_actions_for(loc: CityLocationDefinition) -> Array:
	var actions: Array = [{"key": "lore", "label": "Lore"}]
	if _is_party_here(loc):
		if loc.category == "tavern":
			actions.append({"key": "stay", "label": "Stay"})
		elif loc.category == "shop":
			if _is_shop_open():
				actions.append({"key": "enter_shop", "label": "Enter"})
			else:
				actions.append({"key": "enter_shop", "label": "Closed", "disabled": true, "tooltip": "Opening hours 8am-8pm"})
		elif loc.category == "gate":
			actions.append({"key": "leave_city", "label": "Leave City"})
		elif loc.category == "guild":
			## Per the Dungeon Encounter Screen request ("hook up the
			## Rat Catcher Guild in Ubersreik, and give him a Quest
			## option that will trigger the Dungeon encounter"): gated
			## purely on loc.category == "guild", same as every other
			## branch here -- a future second guild-category location
			## would also get a "Talk" option automatically, though
			## only the Rat Catcher's Guild itself (see ubersreik_
			## city_locations.tres) actually offers the dungeon quest
			## right now (RatCatcherGuildScreen is a single hardcoded
			## guild, not yet parameterized by which one).
			actions.append({"key": "talk", "label": "Talk"})
		elif loc.category == "temple" and loc.location_name == "The Temple of Shallya":
			## Per the request ("hook up The Temple of Shallya in
			## Ubersreik, copy the priestess from Giessingen"): gated
			## on BOTH category AND the exact location name, unlike
			## every other branch above -- Ubersreik has three
			## temple-category locations (Shallya, Sigmar, Verena, see
			## ubersreik_city_locations.tres), each meant for a
			## different god, so pure category-gating here would
			## incorrectly hand Sigmar/Verena the same Shallyan-Priest
			## healer action too. Healer.tscn/healer_screen.gd is the
			## same generic healer screen Giessingen's own map tile
			## already leads to -- this project's NPCs are role-based,
			## not individually named (see npc_flavor_text.gd's own
			## header comment), so "copy the priestess" means reusing
			## that same screen/role, not building a second one.
			actions.append({"key": "pray", "label": "Enter"})
	else:
		actions.append({"key": "travel", "label": "Travel"})
	return actions

## Follow-up request (shop hours): shops (every "shop"-category
## location, present or future — see _radial_actions_for's own comment)
## are open 8am-8pm game time and closed the other 12 hours, deliberately
## NOT touching taverns/inns (which stay open around the clock — the
## request called this out explicitly) or anything else. 8pm (20*60) is
## itself CLOSED, not open — a shop's last real minute of business is
## 19:59, matching how "closes at 8pm" reads in plain English.
const SHOP_OPEN_MINUTES := 8 * 60
const SHOP_CLOSE_MINUTES := 20 * 60
func _is_shop_open() -> bool:
	var t: int = GameState.time_minutes
	return t >= SHOP_OPEN_MINUTES and t < SHOP_CLOSE_MINUTES

## Follow-up request (dual home/target radial menus): finds whichever
## unlocked location the party's own token is currently standing
## exactly on, if any — the home radial always tracks THIS, never
## whatever was last clicked. Returns null on the (normally impossible)
## case of the token sitting somewhere that isn't a real location's own
## map_position, in which case the home radial simply doesn't show
## anything, same as having no home actions at all.
func _location_at_party_pos() -> CityLocationDefinition:
	for loc in location_list.locations:
		if loc.unlocked and _is_party_here(loc):
			return loc
	return null

## Follow-up request ("always show the Leave City, Stay and Enter
## radial options when the party is at a location and they are
## available, trigger it after travel finishes"): (re)opens the home
## radial for wherever the party is actually standing right now — the
## single source of truth CityMapView draws/hit-tests as home_location.
## Called once from _ready() (so it's up from the very first frame, not
## just after the first travel) and again at the end of _run_travel()
## (arrival). _run_travel()'s own START is the only place that clears
## home_location — see that function — matching "only remove it when
## travel starts again to another location".
func _refresh_home_radial() -> void:
	var loc := _location_at_party_pos()
	map_view.home_location = loc
	map_view.home_actions = _radial_actions_for(loc) if loc != null else []
	map_view.queue_redraw()

## Per the request ("left or right click anywhere else on the map will
## deselect current POI"): clears the currently-selected TARGET (not
## the home radial, which persists regardless — see
## _refresh_home_radial()'s own comment) and closes the Lore box if it
## was open.
func _deselect_target() -> void:
	if map_view.target_location == null and not _lore_open:
		return
	map_view.target_location = null
	map_view.target_radial_open = false
	_lore_open = false
	encounter_box.visible = false
	map_view.queue_redraw()

func _on_map_background_clicked(_content_pos: Vector2) -> void:
	if _map_click_guard_active():
		return
	_deselect_target()

func _on_map_right_clicked() -> void:
	if _map_click_guard_active():
		return
	_deselect_target()

## Per the request ("2 buttons: Lore... and Travel"): routes a radial
## button click to the matching behaviour — `loc` may belong to either
## the home or the target radial (CityMapView reports whichever one was
## actually clicked; see its own radial_action signal comment), but the
## action key alone is enough to know what to do with it. Travel closes
## the TARGET radial first (the target marker itself stays highlighted
## through the Y/N confirm that follows — see _offer_travel_to) so its
## own buttons aren't still sitting there, clickable, over the confirm
## prompt; the home radial deliberately stays up through that same
## confirm (see _run_travel's own comment for exactly where it finally
## clears).
func _on_radial_action(loc: CityLocationDefinition, action: String) -> void:
	if _map_click_guard_active():
		return
	if loc == null:
		return
	if action == "lore":
		_show_lore(loc)
	elif action == "travel":
		map_view.target_radial_open = false
		map_view.target_location = null
		_lore_open = false
		encounter_box.visible = false
		map_view.queue_redraw()
		_offer_travel_to(loc)
	elif action == "stay":
		_lore_open = false
		encounter_box.visible = false
		map_view.queue_redraw()
		_enter_tavern(loc)
	elif action == "enter_shop":
		## Defensive no-op if the shop is actually closed — CityMapView's
		## own _radial_hit_at already refuses to report a click on a
		## disabled button at all (see its own comment), so this should
		## be unreachable in practice; kept anyway per this file's own
		## established "guard even what shouldn't be reachable" pattern
		## (see _offer_travel_to's own already-there early-out).
		if not _is_shop_open():
			return
		_lore_open = false
		encounter_box.visible = false
		map_view.queue_redraw()
		_enter_shop(loc)
	elif action == "leave_city":
		_lore_open = false
		encounter_box.visible = false
		map_view.queue_redraw()
		_offer_leave_city()
	elif action == "talk":
		_lore_open = false
		encounter_box.visible = false
		map_view.queue_redraw()
		_enter_guild(loc)
	elif action == "pray":
		_lore_open = false
		encounter_box.visible = false
		map_view.queue_redraw()
		_enter_temple(loc)

## New Tavern Screen follow-up: hands off to the standalone Tavern.tscn
## scene, same "pending id + autosave + change_scene_to_file" pattern
## Overworld._offer_enter_location() already uses to hand off to this
## very CityScreen — GameState.pending_tavern_city_id is read back into
## pending_city_id by TavernScreen._on_close() right before it changes
## back, so returning from the Tavern lands on this exact same city
## (CityScreen._ready() already knows how to consume pending_city_id).
## The party's own current map position isn't touched here at all —
## it's still exactly where it was standing when Stay was chosen, same
## as leaving any other screen and coming back.
##
## Follow-up request ("add The Exploding Pig as the 2nd Tavern, and make
## the tavern screens distinct by adding the tavern name..."): also
## hands over `loc`'s own real name via pending_tavern_name — see that
## field's own declaration comment — so TavernScreen's title reads which
## real tavern this is instead of a generic "The Tavern" for every one.
## Driven purely by whichever tavern-category loc the "Stay" action was
## actually clicked on, so a third tavern picks this up automatically
## with no further code changes needed here.
func _enter_tavern(loc: CityLocationDefinition) -> void:
	GameState.pending_tavern_city_id = city_id
	GameState.pending_tavern_name = loc.location_name
	GameState.autosave()
	get_tree().change_scene_to_file("res://scenes/Tavern.tscn")

## New City Shop follow-up ("copy the giessingen shop and put it into
## ubersreik... use city level availability chances for items"): hands
## off to the SAME shared Shop.tscn Overworld's Giessingen shopkeeper
## tile already uses — not a new scene/script, per this project's own
## "don't duplicate a whole screen when the existing one already takes
## a parameter for this" judgment (ShopScreen's settlement_tier/
## settlement_name were already designed for exactly this, just never
## wired up to a second source before now). Three pending fields
## instead of Tavern's one, since ShopScreen also needs to know WHICH
## settlement tier/name to roll stock for — see their own declaration
## comments on GameState. "City" is hardcoded rather than derived from
## anything on CityScreen itself since only one city (Ubersreik) exists
## right now; a future second city would need this to actually vary.
func _enter_shop(loc: CityLocationDefinition) -> void:
	GameState.pending_shop_city_id = city_id
	GameState.pending_shop_settlement_tier = "City"
	GameState.pending_shop_settlement_name = "Ubersreik"
	## Cordelia's Apothecary feature: set for EVERY shop visit (see the
	## field's own declaration comment) so ShopScreen can tell which
	## specific shop this is — only "Cordelia's Apothecary" changes
	## behavior, every other shop name is a no-op here.
	GameState.pending_shop_location_name = loc.location_name
	GameState.autosave()
	get_tree().change_scene_to_file("res://scenes/Shop.tscn")

## Rat Catcher's Guild feature (spec: "hook up the Rat Catcher Guild in
## Ubersreik, and give him a Quest option that will trigger the Dungeon
## encounter"): hands off to a new standalone RatCatcherGuildScreen.tscn,
## same "pending id + autosave + change_scene_to_file" hand-off Tavern
## above already uses — GameState.pending_guild_city_id is read back
## into pending_city_id by RatCatcherGuildScreen._on_close() right
## before it changes back, so returning from the guild lands on this
## exact same city. Only one guild screen exists so far (no per-guild
## name/id parameter, unlike Tavern's pending_tavern_name) — every
## "guild"-category location's own "Talk" action currently opens this
## same screen; a second, distinct guild would need its own pending
## field the same way a second Tavern needed pending_tavern_name.
func _enter_guild(loc: CityLocationDefinition) -> void:
	GameState.pending_guild_city_id = city_id
	GameState.autosave()
	get_tree().change_scene_to_file("res://scenes/RatCatcherGuildScreen.tscn")

## Temple of Shallya feature ("hook up The Temple of Shallya in
## Ubersreik, copy the priestess from Giessingen"): hands off to the
## SAME shared Healer.tscn/healer_screen.gd Giessingen's own map tile
## already reaches (see overworld.gd's priest_coords) — not a new
## scene/script, same "reuse the existing role-based screen" judgment
## as Guild/Tavern above. Only "The Temple of Shallya" itself reaches
## this (see _radial_actions_for's own name-gated "pray" branch), even
## though Ubersreik has two other temple-category locations for other
## gods with no healer service of their own yet.
func _enter_temple(loc: CityLocationDefinition) -> void:
	GameState.pending_healer_city_id = city_id
	GameState.autosave()
	get_tree().change_scene_to_file("res://scenes/Healer.tscn")

func _show_lore(loc: CityLocationDefinition) -> void:
	_lore_open = true
	encounter_label.text = _lore_text(loc)
	## No Y/N choice on a Lore readout — hide the confirm button row so
	## a previous confirm prompt's buttons don't linger visible here.
	confirm_choice_row.visible = false
	encounter_box.visible = true

func _close_lore() -> void:
	_lore_open = false
	encounter_box.visible = false

func _lore_text(loc: CityLocationDefinition) -> String:
	var flavor: String = CATEGORY_LORE.get(loc.category, "A place of interest in the city.")
	var lines: Array = [loc.location_name]
	if loc.district != "":
		lines.append("District: %s" % loc.district)
	lines.append(flavor)
	lines.append("[Space] Close")
	return "\n".join(lines)

## Real road-routed pixel distance from the party's current map
## position to `loc` — per the follow-up request ("vector some rough
## walking paths... use the main roads/Gates, so travel looks more
## realistic"), this now sums the length of an actual multi-segment
## route through UbersreikRoadNetwork's own waypoint graph (gates,
## district junctions, the bridge) instead of a straight line cut
## through city blocks/the river. Converted to real yards via
## YARDS_PER_PIXEL, then to whole walking minutes via the party's own
## slowest member's Movement and YARDS_PER_MINUTE_PER_MOVEMENT — same
## "party can only move as fast as its slowest member" convention
## GameState.minutes_per_tile_fraction() already uses for local-map
## walking. A real route is very rarely a straight line, so this
## alone already means farther/less-direct destinations cost
## noticeably more time than the old straight-line estimate did — on
## top of (not instead of) YARDS_PER_MINUTE_PER_MOVEMENT's own
## separate slowdown.
func _travel_path_and_minutes(loc: CityLocationDefinition) -> Array:
	var path: Array = UbersreikRoadNetwork.route(map_view.party_token_pos, loc.map_position)
	var content: Vector2 = CITY_MAP_TEXTURE.get_size()
	var pixel_distance: float = 0.0
	for i in range(path.size() - 1):
		var a_px: Vector2 = Vector2(path[i].x * content.x, path[i].y * content.y)
		var b_px: Vector2 = Vector2(path[i + 1].x * content.x, path[i + 1].y * content.y)
		pixel_distance += a_px.distance_to(b_px)
	var yards: float = pixel_distance * YARDS_PER_PIXEL
	var slowest: int = 999
	for member in GameState.party:
		slowest = mini(slowest, floori(member.get_movement()))
	if slowest >= 999:
		var pc := GameState.player_character
		slowest = floori(pc.get_movement()) if pc != null else 4
	var movement: int = maxi(slowest, 1)
	var minutes: int = maxi(ceili(yards / (float(movement) * YARDS_PER_MINUTE_PER_MOVEMENT)), 1)
	return [path, yards, minutes]

func _offer_travel_to(loc: CityLocationDefinition) -> void:
	if loc.map_position.distance_to(map_view.party_token_pos) < 0.001:
		return
	var result := _travel_path_and_minutes(loc)
	var path: Array = result[0]
	var yards: float = result[1]
	var minutes: int = result[2]
	_pending_travel_location = loc
	_start_confirm_prompt("Walk to %s?\n~%d yards, about %d minute%s." % [loc.location_name, int(round(yards)), minutes, "" if minutes == 1 else "s"], "Go", "Cancel")
	encounter_box.visible = true
	## The route is shown on the map the moment it's offered, not just
	## once travel is confirmed — lets the player see the actual road
	## the walk would take before committing to it.
	map_view.travel_path = path
	map_view.queue_redraw()
	awaiting_travel_confirm = true
	while awaiting_travel_confirm:
		await get_tree().process_frame
	encounter_box.visible = false
	if _travel_confirmed:
		_travel_confirmed = false
		await _run_travel(loc, path, minutes)
	else:
		map_view.travel_path = []
	_pending_travel_location = null
	## Already cleared the moment Travel was clicked (see
	## _on_radial_action's own "travel" branch) — defensive no-op here
	## for the cancelled path too, in case some future caller ever
	## reaches _offer_travel_to without going through that branch first.
	map_view.target_location = null
	map_view.target_radial_open = false
	map_view.queue_redraw()

## Follow-up request ("always show the Leave City, Stay and Enter
## radial options... trigger it after travel finishes... only remove it
## when travel starts again to another location"): home_location is
## cleared right HERE, at the genuine start of a real walk — not when
## Travel is merely clicked, and not while its own Y/N confirm is up
## (see _offer_travel_to, which never touches it) — so a cancelled
## offer leaves the home radial exactly as it was. _refresh_home_radial()
## at the very end brings it back for wherever the party actually ends
## up.
func _run_travel(loc: CityLocationDefinition, path: Array, minutes: int) -> void:
	_travel_in_progress = true
	map_view.home_location = null
	map_view.home_actions = []
	travel_stage_label.text = "Walking to %s..." % loc.location_name
	travel_progress_bar.value = 0.0
	travel_progress_panel.visible = true
	map_view.travel_path = path

	## Walks the real multi-segment route (gates/junctions/bridge, not
	## a straight line — see _travel_path_and_minutes) rather than a
	## single lerp from start to end, so the token visibly follows the
	## same road the distance/time estimate was based on. Segment
	## lengths vary, so time is distributed across steps proportional
	## to each segment's own share of the total route length — the
	## token moves at a roughly constant visual speed along the whole
	## path instead of jumping between waypoints at uneven rates.
	var seg_lengths: Array = []
	var total_length: float = 0.0
	for i in range(path.size() - 1):
		var seg_len: float = path[i].distance_to(path[i + 1])
		seg_lengths.append(seg_len)
		total_length += seg_len
	if total_length <= 0.0:
		total_length = 1.0

	## Follow-up request ("make time progress smoothly rather than a
	## jump at the end of the journey, map light phasing should change
	## during travel"): the full `minutes` cost used to land in one
	## GameState.advance_minutes() call after the walk animation
	## finished — a single visible jump of the clock (and, now that the
	## background phases by time of day, of the lighting too) right at
	## the end. Spread across the same STEPS the token walks over
	## instead, via a cumulative "minutes advanced so far" compared
	## against each step's own target (round(progress * minutes)) —
	## not a flat minutes/STEPS division, so short walks (fewer total
	## minutes than STEPS) still land their whole-minute advances at
	## the right moments instead of losing them all to truncation, and
	## the total across every step always comes out to exactly
	## `minutes`. _update_info_bar() (which also drives the time-of-day
	## background crossfade — see _update_time_of_day_background()) is
	## only called on the steps that actually advanced the clock, not
	## every single animation frame.
	const STEPS := 40
	## Follow-up request ("slow down travel on the city map by 30%"):
	## the walk animation's real-world pacing — not the in-fiction
	## yards/minutes cost (YARDS_PER_MINUTE_PER_MOVEMENT, a genuine WFRP
	## Movement-based rule, left untouched) — since the ask came right
	## alongside a complaint about being able to actually SEE the path/
	## progress bar while it plays out. Same STEPS count (still a
	## smooth 40-step walk), each step's own real-time delay just
	## stretched by 30%: 0.02s -> 0.026s, so the whole animation now
	## takes 30% longer wall-clock time to play, giving more time to
	## watch the (now much more visible — see city_map_view.gd's own
	## PATH_COLOR comment) route unfold.
	const STEP_DELAY_SECONDS := 0.02 * 1.3
	var minutes_advanced: int = 0
	for i in range(STEPS + 1):
		var progress: float = float(i) / float(STEPS)
		var target_dist: float = progress * total_length
		map_view.party_token_pos = _point_along_path(path, seg_lengths, target_dist)
		travel_progress_bar.value = progress * 100.0
		var target_minutes: int = int(round(progress * minutes))
		if target_minutes > minutes_advanced:
			GameState.advance_minutes(target_minutes - minutes_advanced)
			minutes_advanced = target_minutes
			_update_info_bar()
		map_view.queue_redraw()
		await get_tree().create_timer(STEP_DELAY_SECONDS).timeout

	map_view.party_token_pos = loc.map_position
	GameState.city_player_positions[city_id] = loc.map_position
	GameState.autosave()
	_update_info_bar()

	map_view.travel_path = []
	travel_progress_panel.visible = false
	_travel_in_progress = false
	## Arrival: bring the home radial back up for wherever the party
	## actually ended up (see this function's own header comment).
	_refresh_home_radial()

## Finds the point `target_dist` pixels along `path` (a normalized-
## coordinate polyline), given each segment's own pre-computed length
## in the same normalized units — walks segments in order, consuming
## `target_dist` as it goes, and lerps within whichever segment it
## lands in. Used to move the party token at a constant pace along a
## multi-segment route (see _run_travel).
func _point_along_path(path: Array, seg_lengths: Array, target_dist: float) -> Vector2:
	var remaining: float = target_dist
	for i in range(seg_lengths.size()):
		var seg_len: float = seg_lengths[i]
		if remaining <= seg_len or i == seg_lengths.size() - 1:
			var t: float = clampf(remaining / seg_len, 0.0, 1.0) if seg_len > 0.0 else 1.0
			return path[i].lerp(path[i + 1], t)
		remaining -= seg_len
	return path[-1]

## Follow-up request ("add a Leave City option to the north east and
## south gates... the only way to leave Ubersreik is now via the
## gates, we will always enter from the south gate"): now reached
## exclusively via a gate's own "Leave City" radial action (see
## _radial_actions_for/_on_radial_action above) rather than the
## legend's own always-visible button, which is gone — leaving the
## city is now something the party does AT a gate, not from anywhere
## on the map.
func _offer_leave_city() -> void:
	if character_menu.visible or pause_menu.visible or _travel_in_progress or awaiting_travel_confirm:
		return
	_start_confirm_prompt("Leave for the open road?", "Confirm", "Cancel")
	encounter_box.visible = true
	awaiting_travel_confirm = true
	_pending_travel_location = null
	while awaiting_travel_confirm:
		await get_tree().process_frame
	encounter_box.visible = false
	if _travel_confirmed:
		_travel_confirmed = false
		GameState.pending_map_path = "res://data/maps/empire_world_map.tres"
		## Follow-up request's own reported bug ("its not saving the
		## city still") + "we will always enter from the south gate":
		## no longer "in" this city at all once the gate is actually
		## used, and the next fresh entry should start clean at the
		## South Gate rather than resuming wherever the party happened
		## to leave from — see both fields' own declaration comments on
		## GameState.
		GameState.last_active_city_id = ""
		GameState.city_player_positions.erase(city_id)
		GameState.autosave()
		get_tree().change_scene_to_file("res://scenes/Overworld.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if character_menu == null or pause_menu == null:
		return
	if awaiting_travel_confirm:
		## Per the request ("always allow WASD movement and hotkey space
		## to accept selected for these all these types of pop ups"):
		## same WASD-selects/Space-accepts scheme as Overworld's own
		## confirm prompts — Left/Up selects [Y], Right/Down selects
		## [N], Space accepts whichever is highlighted. Direct Y/N keys
		## keep working unchanged.
		if event.is_action_pressed("move_left") or event.is_action_pressed("move_up"):
			get_viewport().set_input_as_handled()
			_confirm_selected_yes = true
			_render_confirm_prompt()
			return
		if event.is_action_pressed("move_right") or event.is_action_pressed("move_down"):
			get_viewport().set_input_as_handled()
			_confirm_selected_yes = false
			_render_confirm_prompt()
			return
		if event is InputEventKey and event.pressed and not event.is_echo():
			if event.keycode == KEY_Y:
				get_viewport().set_input_as_handled()
				_travel_confirmed = true
				awaiting_travel_confirm = false
			elif event.keycode == KEY_N or event.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_travel_confirmed = false
				awaiting_travel_confirm = false
			elif event.keycode == KEY_SPACE:
				get_viewport().set_input_as_handled()
				_travel_confirmed = _confirm_selected_yes
				awaiting_travel_confirm = false
		return
	## Follow-up request (radial POI menu, Lore button): the Lore readout
	## is a lightweight modal, same "swallow input until dismissed"
	## shape as the awaiting_travel_confirm block above but with no Y/N
	## choice to make — Space or Escape closes it, everything else is
	## just ignored while it's open (matches this file's existing
	## precedent of not handling keys the current modal doesn't care
	## about, rather than letting them fall through to Q/E/M/Esc below).
	if _lore_open:
		if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_SPACE):
			get_viewport().set_input_as_handled()
			_close_lore()
		return
	## Follow-up request ("always Auto focus (outline in red) and Space
	## hotkey the travel option when its available"): the target radial
	## is always exactly [Lore, Travel] and Travel is the only entry
	## CityMapView ever draws with the red focus outline (see its own
	## _draw_radial_menu), so there's no separate "which item is
	## focused" state to track here — Space just fires Travel directly
	## whenever a target is actually selected. Routes through
	## _on_radial_action exactly like a real click would, so it picks
	## up the same click-guard/cleanup behaviour for free.
	if map_view.target_radial_open and map_view.target_location != null and not _map_click_guard_active():
		if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()
			_on_radial_action(map_view.target_location, "travel")
			return
	if event.is_action_pressed("open_menu"):
		if character_menu.visible:
			character_menu.close()
		elif not pause_menu.visible:
			character_menu.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		## Was previously unhandled here — Esc did nothing at all on
		## this screen (see PAUSE_MENU_SCENE's own declaration comment
		## above). Same three-way toggle as Overworld's own ui_cancel
		## branch.
		if character_menu.visible:
			character_menu.close()
		elif pause_menu.visible:
			pause_menu.close()
		else:
			pause_menu.open()
		get_viewport().set_input_as_handled()
	## Follow-up request ("Allow Q/E character switching on city map
	## screens") — this screen never had it at all before; same
	## Q-cycles-left/E-cycles-right scheme as Overworld's own
	## _unhandled_input, duplicated rather than shared per this file's
	## header convention. When the character menu is open, Q/E instead
	## cycles which member's own stats/inventory/etc it's showing —
	## same as Overworld. Guarded off during an in-flight travel walk
	## for the same reason Overworld guards it: switching who you're
	## controlling mid-animation would be confusing.
	elif event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_Q:
		if character_menu.visible:
			get_viewport().set_input_as_handled()
			character_menu.cycle_displayed_character(-1)
		elif not pause_menu.visible and not _travel_in_progress:
			get_viewport().set_input_as_handled()
			GameState.cycle_active_party_member(-1)
			map_view.party_token_texture = _current_party_texture()
			map_view.party_token_modulate = CareerPortraits.wound_modulate_for_character(GameState.player_character)
			_update_info_bar()
	elif event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_E:
		if character_menu.visible:
			get_viewport().set_input_as_handled()
			character_menu.cycle_displayed_character(1)
		elif not pause_menu.visible and not _travel_in_progress:
			get_viewport().set_input_as_handled()
			GameState.cycle_active_party_member(1)
			map_view.party_token_texture = _current_party_texture()
			map_view.party_token_modulate = CareerPortraits.wound_modulate_for_character(GameState.player_character)
			_update_info_bar()

## Populates the top info bar — same fields as Overworld's own, minus
## the World Map-only hint text (see hud_label's own default below).
func _update_info_bar() -> void:
	var c := GameState.player_character
	if c == null:
		return
	_update_party_panels()
	xp_label.text = "XP: %d" % c.experience_total
	gold_label.text = "%d GC %d SS %d BP" % [c.gold_crowns, c.silver_shillings, c.brass_pennies]
	time_label.text = GameState.get_time_string()
	date_label.text = GameState.get_date_string()
	hud_label.text = "%s — click a marker or the legend to select it. [M] Party Menu  [Q/E] Switch Character" % c.character_name
	map_view.party_token_texture = _current_party_texture()
	map_view.party_token_modulate = CareerPortraits.wound_modulate_for_character(GameState.player_character)
	_update_time_of_day_background()

## Picks the two adjacent TIME_OF_DAY_KEYFRAMES entries that bracket
## GameState.time_minutes and hands map_view the "current" one as its
## base background plus, once within TIME_OF_DAY_BLEND_MINUTES of the
## next keyframe's own hour, that next image as a crossfading overlay.
## Keyframes are sorted by hour ascending and treated as a wrapping
## 24-hour cycle (the 8pm->2am and 2am->8am gaps both work the same
## way as any other pair).
func _update_time_of_day_background() -> void:
	var count: int = TIME_OF_DAY_KEYFRAMES.size()
	if count == 0:
		return
	var now: int = GameState.time_minutes
	## Find the keyframe whose hour is the most recent one at/before
	## `now` (wrapping past midnight) — that's the current base image.
	## Starts at the LAST keyframe (not 0): if `now` is earlier than
	## every keyframe's own hour (e.g. 1:40am with keyframes at
	## 2/8/14/20), the "current" one is still yesterday's last
	## keyframe (20:00), not index 0.
	var current_index: int = count - 1
	for i in range(count):
		if TIME_OF_DAY_KEYFRAMES[i]["hour"] * 60 <= now:
			current_index = i
	var next_index: int = (current_index + 1) % count
	var next_hour: int = TIME_OF_DAY_KEYFRAMES[next_index]["hour"]
	var next_minutes: int = next_hour * 60
	if next_minutes <= TIME_OF_DAY_KEYFRAMES[current_index]["hour"] * 60:
		## Next keyframe wraps past midnight (e.g. current=20:00,
		## next=02:00) — push it a full day ahead for the subtraction
		## below so "minutes until next" comes out positive.
		next_minutes += 24 * 60
	var now_unwrapped: int = now
	if now_unwrapped < TIME_OF_DAY_KEYFRAMES[current_index]["hour"] * 60:
		now_unwrapped += 24 * 60

	map_view.background = TIME_OF_DAY_KEYFRAMES[current_index]["texture"]
	var minutes_until_next: int = next_minutes - now_unwrapped
	if minutes_until_next <= TIME_OF_DAY_BLEND_MINUTES:
		map_view.background_next = TIME_OF_DAY_KEYFRAMES[next_index]["texture"]
		var blended_in: int = TIME_OF_DAY_BLEND_MINUTES - minutes_until_next
		map_view.background_blend = clampf(float(blended_in) / float(TIME_OF_DAY_BLEND_MINUTES), 0.0, 1.0)
	else:
		map_view.background_next = null
		map_view.background_blend = 0.0
	map_view.queue_redraw()

func _update_party_panels() -> void:
	if party_panel_row.get_child_count() != GameState.party.size():
		for child in party_panel_row.get_children():
			party_panel_row.remove_child(child)
			child.queue_free()
		for i in range(GameState.party.size()):
			party_panel_row.add_child(_build_party_panel(i))
	for i in range(GameState.party.size()):
		_refresh_party_panel(party_panel_row.get_child(i), GameState.party[i], i == GameState.active_party_index)

func _build_party_panel(index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "PartyPanel%d" % index
	panel.custom_minimum_size = PARTY_PANEL_SIZE
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			GameState.active_party_index = index
			_update_party_panels()
	)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	var portrait_stack := Control.new()
	portrait_stack.name = "PortraitStack"
	portrait_stack.custom_minimum_size = Vector2(32, 32)
	portrait_stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(portrait_stack)

	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.clip_contents = true
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	## Per the request ("use the new portraits in all Icon"): crop-to-fill
	## instead of stretch, since the new Career portraits aren't square
	## like the old wound-tier art was — see overworld.gd's identical
	## panel for the same change.
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_stack.add_child(portrait)

	var hp_box := VBoxContainer.new()
	hp_box.name = "HPBox"
	hp_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_box.add_theme_constant_override("separation", 2)
	row.add_child(hp_box)

	var hp_label_node := Label.new()
	hp_label_node.name = "HPLabel"
	hp_label_node.add_theme_font_size_override("font_size", PARTY_NAME_MAX_FONT_SIZE)
	hp_label_node.custom_minimum_size = Vector2(PARTY_PANEL_HP_COLUMN_WIDTH, 0)
	hp_label_node.clip_text = true
	hp_label_node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hp_box.add_child(hp_label_node)

	var hp_bar_node := ProgressBar.new()
	hp_bar_node.name = "HPBar"
	hp_bar_node.custom_minimum_size = Vector2(PARTY_PANEL_HP_COLUMN_WIDTH, 10)
	hp_bar_node.show_percentage = false
	hp_box.add_child(hp_bar_node)

	var wound_lbl := Label.new()
	wound_lbl.name = "WoundLabel"
	wound_lbl.add_theme_font_size_override("font_size", 9)
	wound_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	wound_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	wound_lbl.add_theme_constant_override("outline_size", 2)
	wound_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wound_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wound_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	wound_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar_node.add_child(wound_lbl)

	return panel

func _fit_party_name_label(label: Label, text: String, max_width: float) -> void:
	label.text = text
	var font: Font = label.get_theme_font("font")
	if font == null:
		label.add_theme_font_size_override("font_size", PARTY_NAME_MAX_FONT_SIZE)
		return
	var chosen_size := PARTY_NAME_MIN_FONT_SIZE
	for fsize in range(PARTY_NAME_MAX_FONT_SIZE, PARTY_NAME_MIN_FONT_SIZE - 1, -1):
		var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		if text_width <= max_width:
			chosen_size = fsize
			break
	label.add_theme_font_size_override("font_size", chosen_size)

func _refresh_party_panel(panel: Node, c: Character, is_active: bool) -> void:
	var row: HBoxContainer = panel.get_node("Row")
	var portrait: TextureRect = row.get_node("PortraitStack/Portrait")
	var hp_box: VBoxContainer = row.get_node("HPBox")
	var hp_label_node: Label = hp_box.get_node("HPLabel")
	var hp_bar_node: ProgressBar = hp_box.get_node("HPBar")
	var wound_lbl: Label = hp_bar_node.get_node("WoundLabel")

	_fit_party_name_label(hp_label_node, c.character_name, PARTY_PANEL_HP_COLUMN_WIDTH)
	wound_lbl.text = "%d/%d" % [c.wounds_current, c.wounds_max]
	hp_bar_node.max_value = max(c.wounds_max, 1)
	hp_bar_node.value = c.wounds_current
	var pct: float = float(c.wounds_current) / float(max(c.wounds_max, 1))
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.2, 0.75, 0.25) if pct > 0.5 else (Color(0.85, 0.65, 0.15) if pct > 0.25 else Color(0.75, 0.15, 0.15))
	bar_fill.corner_radius_top_left = 3
	bar_fill.corner_radius_top_right = 3
	bar_fill.corner_radius_bottom_left = 3
	bar_fill.corner_radius_bottom_right = 3
	hp_bar_node.add_theme_stylebox_override("fill", bar_fill)

	## Per the request ("use the new portraits in all Icon, in and out of
	## combat"): this Character's own full Career portrait, not the old
	## generic career_class/wound-tier art.
	portrait.texture = CareerPortraits.get_portrait_for_character(c)
	## Per the follow-up request ("add a red tint at low health") — see
	## overworld.gd's identical panel for the same change.
	portrait.modulate = CareerPortraits.wound_modulate_for_character(c)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.14, 0.14, 0.12, 0.9)
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	if is_active:
		panel_style.border_width_left = 2
		panel_style.border_width_top = 2
		panel_style.border_width_right = 2
		panel_style.border_width_bottom = 2
		panel_style.border_color = Color(0.9, 0.8, 0.35, 1)
	panel.add_theme_stylebox_override("panel", panel_style)
