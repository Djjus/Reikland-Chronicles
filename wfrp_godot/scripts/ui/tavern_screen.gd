extends Control
## New Tavern screen, per the request: "Make this screen the same as the
## Camp screen but with no Camp endeavour, and hide the food. And
## sleeping requires paying for a room at the Tavern or Inn." Reached
## from a tavern-category CityLocationDefinition's own radial menu (the
## new "Stay" action alongside Lore/Travel — see CityMapView/city_screen.gd)
## rather than from the World Map like Camp is.
##
## Deliberately a fresh standalone copy of camp_screen.gd, NOT a shared
## refactor — same "don't share code across independently-working
## screens" convention this whole project already follows (see
## city_screen.gd's own header for the fuller rationale). The two
## screens overlap a lot (party status boxes, Heal Skill/Blessing of
## Healing actions, the short-nap/Full Night's Sleep shape, the Result
## popup) but diverge in exactly the two ways the request calls out:
##
## - No Camp Endeavour system at all here (Make Camp/Cook/Hunt/Trap/
##   Assist, and the "Camp Endeavours" column) — a paying guest doesn't
##   forage or cook their own food.
## - No Food row/requirement either — a room's price already includes
##   a meal (see the room-price image this was built from).
##
## In their place: a Room-for-the-Night picker (Common Room/Room/Large
## Room, priced per the source image) that both gates Full Night's
## Sleep (you have to be able to afford it) and sets the heal-roll
## modifier the same way a successful Make Camp used to on the Camp
## screen (Common Room: +0, Room/Large Room: +20).

@onready var close_button: Button = %CloseButton
@onready var status_label: Label = %StatusLabel
@onready var message_label: Label = %MessageLabel
@onready var content_box: VBoxContainer = %ContentBox

const BUTTON_FONT_SIZE := 12
const SMALL_FONT_SIZE := 10
const HEADER_FONT_SIZE := 14
const ROW_SEPARATION := 4

## Per the request ("use the new portraits in all Icon, in and out of
## combat"): the old wound-tier PLAYER_PORTRAITS table is gone — see
## _portrait_for() below, now backed by CareerPortraits instead.

## Heal Skill (not Magic/Prayer): "can only be used once every 4 hrs on
## each character" — see Character.last_heal_skill_time_minutes.
const HEAL_COOLDOWN_MINUTES := 4 * 60

## Room prices, per the source "Fair Price" table image this was built
## from:
##   Common Room (CR): 10d per night PER PERSON. Several simple single
##     beds sharing one room — no per-room capacity limit worth
##     modelling, everyone just pays their own way in.
##   Room (R): 10/- per night PER ROOM — "2 single beds or a double
##     bed", so one Room sleeps up to 2.
##   Large Room (L): 14/- per night PER ROOM — a Room plus 2 more beds,
##     so one Large Room sleeps up to 4.
## "d" = Brass Pennies, "/-" = Silver Shillings — see Character's own
## PENNIES_PER_SHILLING/PENNIES_PER_CROWN header comment for the coin
## conversion this project uses throughout.
const COMMON_ROOM_PENNIES_PER_PERSON := 10
const ROOM_PENNIES_PER_ROOM := 10 * Character.PENNIES_PER_SHILLING
const ROOM_CAPACITY := 2
const LARGE_ROOM_PENNIES_PER_ROOM := 14 * Character.PENNIES_PER_SHILLING
const LARGE_ROOM_CAPACITY := 4

## Per the request ("Common room has +0 modifier to the heal roll,
## while room/large rooms provide +20 bonus"): mirrors the same +20
## "Make Camp succeeded" bonus camp_screen.gd's own Endurance Test
## already applies on a Full Night's Sleep — a private Room buys the
## same undisturbed rest a well-made camp does; a shared Common Room
## bunk doesn't.
const ROOM_TIERS := [
	{"key": "common", "label": "Common Room", "heal_modifier": 0},
	{"key": "room", "label": "Room", "heal_modifier": 20},
	{"key": "large_room", "label": "Large Room", "heal_modifier": 20},
]

## Follow-up request ("put in a single box on the right side which
## will allow drinking... and Gossiping with the patrons"): the book's
## Consume Alcohol skill text says a Test is "modified by the strength
## of the drink" without giving a numeric table of its own (unlike
## Rooms, which the source price-table image did spell out) — this is
## a reasonable, clearly-invented Fair-Price-style tier list rather
## than a book-sourced one, priced the same way Rooms are (Brass
## Pennies, see _format_price).
const DRINKS := [
	{"key": "small_beer", "label": "Small Beer", "modifier": 20, "price": 2},
	{"key": "ale", "label": "Tankard of Ale", "modifier": 0, "price": 4},
	{"key": "wine", "label": "Cup of Wine", "modifier": -10, "price": 8},
	{"key": "spirits", "label": "Shot of Spirits", "modifier": -20, "price": 12},
]

## Flavour-only rumour pool for the Gossip action — no rumour-content
## system exists elsewhere in the project to draw from, so this is a
## small, clearly-invented set of Ubersreik-flavoured lines rather than
## anything with further mechanical hooks.
const GOSSIP_RUMOURS := [
	"a Watch patrol out of the Precinct found a locked strongbox washed up under Teubrücke, and nobody's claimed it yet.",
	"the miller out past North Gate swears his flour's been going missing a sack at a time — reckons it's Beastmen, though the Watch aren't so sure.",
	"a merchant in the Artisan's Quarter is paying well over the odds for anything with old Dwarfen make on it.",
	"there's talk of a black-cloaked stranger asking after 'the old tunnels' down by Dawihafen — nobody's seen where they went after.",
	"the Temple of Sigmar in the Precinct is quietly looking for someone willing to escort a shipment out to Lumenburg Vineyard.",
	"a bar-room brawl at another house left three men in the care of the Temple of Shallya, and the Watch are still asking questions about who started it.",
	"a trapper swears he saw lights moving in Jungfer Hill after dark, out past South Gate — most reckon it's just marsh-gas.",
	"a Halfling cook in Marktplatz is offering a warm meal to anyone who'll trade news from outside the walls.",
]

var _heal_def: SkillDefinition
var _endurance_def: SkillDefinition
## Per the follow-up request on camp_screen.gd this was copied from:
## the Heal button now also appears for characters who know the
## "Blessing of Healing" prayer (in addition to the Heal skill).
var _pray_def: SkillDefinition
var _blessing_of_healing: PrayerDefinition

## Consume Alcohol / Gossip — the Tavern Activities box's own two
## actions. See DRINKS/GOSSIP_RUMOURS above and Character.
## drink_alcohol()/tick_alcohol_hours() for the real Stinking Drunk
## mechanic this Drink button rolls against.
var _consume_alcohol_def: SkillDefinition
var _gossip_def: SkillDefinition
var _drink_choice_key: String = "ale"
var _drink_result_text: String = ""
var _drink_result_good: bool = true
var _gossip_result_text: String = ""
var _gossip_result_good: bool = true

## Per camp_screen.gd's own follow-up request: short nap defaults to 1
## hour, not 8 (which happened to match the Full Night's Sleep
## threshold and made the short-nap button start out disabled).
var sleep_hours: int = 1

## Which ROOM_TIERS entry is currently selected in the picker — not
## persisted (a fresh Tavern visit starts back on Common Room, same
## "no persistence across visits" precedent sleep_hours above already
## sets for this whole screen family).
var _room_tier_key: String = "common"

## Same "Heal button lives on the HEALER's own box" mapping
## camp_screen.gd uses — Healer Character -> chosen wounded-target
## Character.
var _heal_target_choice: Dictionary = {}

## Same "results render as persistent inline text, not just a one-shot
## label" convention camp_screen.gd uses for its own Sleep section.
var _sleep_result_text: String = ""
var _sleep_result_good: bool = true

## Root of the current modal "Result" popup, if one is showing — see
## _show_outcome_popup(). Tracked so _unhandled_input can gate Esc/
## Enter/Space to "dismiss the popup" instead of their normal meaning
## while it's up.
var _outcome_overlay: Control = null

## Follow-up request ("add The Exploding Pig as the 2nd Tavern, and make
## the tavern screens distinct by adding the tavern name to the Tavern
## (- Name) title"): the real tavern name for THIS visit, read once from
## GameState.pending_tavern_name in _ready() (same "read once, then
## clear" convention as ShopScreen's own settlement_name — see that
## field's own comment) and reused by every _rebuild_all() call
## afterward (this screen rebuilds its whole status_label repeatedly as
## the player takes actions, not just once on load). "" means unknown
## (e.g. some future entry point that doesn't go through CityScreen.
## _enter_tavern()) — _rebuild_all() falls back to the previous plain
## "The Tavern" title rather than showing a blank/redundant name.
var _tavern_name: String = ""

func _ready() -> void:
	close_button.pressed.connect(_on_close)
	GameState.ensure_player_character()
	if GameState.pending_tavern_name != "":
		_tavern_name = GameState.pending_tavern_name
		GameState.pending_tavern_name = ""
	_heal_def = GameData.skill_db.find_by_name("Heal")
	_endurance_def = GameData.skill_db.find_by_name("Endurance")
	_pray_def = GameData.skill_db.find_by_name("Pray")
	_blessing_of_healing = GameData.prayer_db.find_by_name("Blessing of Healing")
	_consume_alcohol_def = GameData.skill_db.find_by_name("Consume Alcohol")
	_gossip_def = GameData.skill_db.find_by_name("Gossip")
	content_box.add_theme_constant_override("separation", ROW_SEPARATION)
	_rebuild_all()

func _living_party() -> Array[Character]:
	var result: Array[Character] = []
	for member in GameState.party:
		if member.wounds_current > 0:
			result.append(member)
	return result

func _rebuild_all() -> void:
	## Follow-up request (distinct tavern titles): "The Tavern - <Name>"
	## once a real name is known, otherwise the previous plain "The
	## Tavern" — see _tavern_name's own declaration comment.
	var title_suffix: String = " - %s" % _tavern_name if _tavern_name != "" else ""
	status_label.text = "Time %s — The Tavern%s" % [GameState.get_time_string(), title_suffix]
	_clear(content_box)

	## Follow-up request ("half the width of the characters boxes and
	## put in a single box on the right side which will allow drinking
	## ...and Gossiping"): Party now shares a row with the new Tavern
	## Activities box instead of taking the full content width — both
	## columns get an equal SIZE_EXPAND_FILL stretch ratio (the
	## default, 1), so the character boxes end up exactly half as wide
	## as before.
	var party_row := HBoxContainer.new()
	party_row.add_theme_constant_override("separation", 10)
	party_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var party_col := VBoxContainer.new()
	party_col.add_theme_constant_override("separation", ROW_SEPARATION)
	party_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## Per the request ("no Camp endeavour, hide the food"): just a
	## single Party column, no second Camp Endeavours column and no
	## Food row above it — the room price already covers a meal, so
	## there's nothing here for the player to track before Sleep.
	party_col.add_child(_header("Party"))
	for member in GameState.party:
		var box := _build_character_box(member)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		party_col.add_child(box)
	party_row.add_child(party_col)

	var activities_col := VBoxContainer.new()
	activities_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	activities_col.add_child(_build_tavern_activities_box())
	party_row.add_child(activities_col)

	content_box.add_child(party_row)

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

## Same as _small_label but WITHOUT autowrap — see camp_screen.gd's own
## comment on this exact function for the render-screenshot bug this
## avoids (a wrapping Label's artificially tiny minimum width collapses
## a GridContainer column). Kept here even though this screen no longer
## has a multi-column grid, since _chip() and a couple of stat rows
## below still rely on it.
func _stat_label(text: String, color: Color = Color(0.75, 0.72, 0.66)) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	lbl.add_theme_color_override("font_color", color)
	return lbl

## Small colour-tagged pill — see camp_screen.gd's own _chip() comment.
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
## Identical to camp_screen.gd's own _build_character_box() — the Heal
## Skill/Blessing of Healing actions and every stat/condition/critical-
## wound readout below aren't Camp Endeavours, so none of it was in
## scope to remove per this request.

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
	## Per the follow-up request ("highlight the active character"): now
	## that Q/E genuinely switches GameState.player_character on this
	## screen (see _unhandled_input), the Party list needs its own
	## visual cue for which box that currently is — a gold border and a
	## slightly lighter background, the same gold accent colour the
	## Tavern Activities box's own "As <Name> — [Q/E] to switch" label
	## already uses for this exact character, so it's obvious at a
	## glance without having to go read that label every time.
	var is_active := member == GameState.player_character
	if is_active:
		style.bg_color = Color(0.19, 0.155, 0.1)
		style.border_color = Color(0.85, 0.7, 0.35)
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
	if member.wounds_current <= 0:
		panel.modulate = Color(0.55, 0.55, 0.55, 1)
	panel.add_theme_stylebox_override("panel", style)

	var outer_hbox := HBoxContainer.new()
	outer_hbox.add_theme_constant_override("separation", 8)
	panel.add_child(outer_hbox)

	var portrait := TextureRect.new()
	portrait.texture = _portrait_for(member)
	## Per the follow-up request ("add a red tint at low health").
	portrait.modulate = CareerPortraits.wound_modulate_for_character(member)
	portrait.custom_minimum_size = Vector2(60, 0)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_hbox.add_child(portrait)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_hbox.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = "%s — %s" % [member.character_name, member.career.career_name if member.career else "?"]
	name_lbl.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5) if is_active else Color(0.9, 0.85, 0.7))
	name_lbl.clip_text = true
	vbox.add_child(name_lbl)

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
				heal_row.add_child(_stat_label("Heal %s:" % chosen_target.character_name))

			if can_heal_skill:
				var remaining_minutes: int = HEAL_COOLDOWN_MINUTES - (GameState.time_minutes_total() - chosen_target.last_heal_skill_time_minutes)
				if remaining_minutes > 0:
					heal_row.add_child(_stat_label("(cooldown %dh%02dm)" % [remaining_minutes / 60, remaining_minutes % 60], Color(0.7, 0.6, 0.55)))
				else:
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

	for line in _drunk_status_lines(member):
		vbox.add_child(_small_label(line, Color(0.65, 0.85, 0.95)))

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

## --- Tavern Activities (Drink / Gossip) ----------------------------------

## Status lines shown on a character's own box while any Consume
## Alcohol state is active — the cumulative Characteristic penalty,
## the Stinking Drunk table effect (if triggered), whether they're
## currently sobering up, and any locked-in hangover. See Character.
## drink_alcohol()/tick_alcohol_hours() for the mechanic itself.
func _drunk_status_lines(member: Character) -> Array[String]:
	var lines: Array[String] = []
	if member.is_drunk():
		lines.append("Drunk (%d WS/BS/Ag/Dex/Int)" % member.get_alcohol_characteristic_penalty())
		if member.is_stinking_drunk:
			var row: Dictionary = member.stinking_drunk_table_entry()
			if not row.is_empty():
				lines.append("Stinking Drunk — \"%s\" %s" % [row["name"], row["text"]])
		if member.is_sobering_up():
			lines.append("Sobering up (clears in ~%dh)" % int(ceil(member.alcohol_recovery_hours_remaining)))
	if member.hangover_lock_hours_remaining > 0.0:
		lines.append("Hungover (Fatigued, ~%dh before it can be slept off)" % int(ceil(member.hangover_lock_hours_remaining)))
	return lines

## Follow-up request ("put in a single box on the right side which
## will allow drinking (ie see table) and Gossiping with the
## patrons"): a single PanelContainer, same visual language as a
## character box, holding both actions — always for GameState.
## player_character, the same single "currently active/controlled
## character" every other single-target convenience action in this
## project (Q/E Switch Character) already centres on, rather than
## adding a whole extra target picker just for this.
func _build_tavern_activities_box() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.11, 0.08)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	vbox.add_child(_header("Tavern"))

	var active: Character = GameState.player_character
	if active == null:
		vbox.add_child(_small_label("No active character."))
		return panel

	vbox.add_child(_small_label("As %s — [Q/E] to switch" % active.character_name))

	## --- Drink ---
	vbox.add_child(_small_label("Drink", Color(0.85, 0.7, 0.35)))
	if _consume_alcohol_def == null:
		vbox.add_child(_small_label("(no Consume Alcohol skill data found)"))
	else:
		var drink_row := HBoxContainer.new()
		drink_row.add_theme_constant_override("separation", 6)
		var drink_picker := OptionButton.new()
		drink_picker.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
		var drink_index := 0
		for i in range(DRINKS.size()):
			var d: Dictionary = DRINKS[i]
			drink_picker.add_item("%s (%s)" % [d["label"], _format_price(d["price"])])
			if d["key"] == _drink_choice_key:
				drink_index = i
		drink_picker.selected = drink_index
		drink_picker.item_selected.connect(func(idx: int):
			_drink_choice_key = DRINKS[idx]["key"]
			_rebuild_all())
		drink_row.add_child(drink_picker)
		vbox.add_child(drink_row)

		var chosen_drink: Dictionary = DRINKS[drink_index]
		var purse: int = active.get_total_pennies()
		var drink_target: int = active.get_skill_value(_consume_alcohol_def) + int(chosen_drink["modifier"])
		var drink_affordable: bool = purse >= int(chosen_drink["price"])
		var drink_btn := _compact_button("Drink (%d, %s)" % [drink_target, _format_price(chosen_drink["price"])])
		## Per the follow-up request ("alot of buttons in the tavern
		## screen are much bigger then the text inside them, shrink them
		## down to their text sizes"): _compact_button() on its own only
		## sets font size/min height, not width — a VBoxContainer child
		## fills the container's own width by default unless told
		## otherwise, same SIZE_SHRINK_BEGIN convention the Sleep
		## section's own buttons below already use.
		drink_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		drink_btn.disabled = not drink_affordable
		if not drink_affordable:
			drink_btn.tooltip_text = "Can't afford a %s (%s needed, have %s)." % [chosen_drink["label"], _format_price(chosen_drink["price"]), _format_price(purse)]
		drink_btn.pressed.connect(func(): _on_drink(active, chosen_drink))
		vbox.add_child(drink_btn)

		if not _drink_result_text.is_empty():
			vbox.add_child(_small_label(_drink_result_text, Color(0.75, 0.9, 0.7) if _drink_result_good else Color(0.9, 0.7, 0.65)))

	var gap1 := Control.new()
	gap1.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(gap1)

	## --- Gossip ---
	vbox.add_child(_small_label("Gossip with the Patrons", Color(0.85, 0.7, 0.35)))
	if _gossip_def == null:
		vbox.add_child(_small_label("(no Gossip skill data found)"))
	else:
		var gossip_target: int = active.get_skill_value(_gossip_def)
		var gossip_btn := _compact_button("Gossip (%d)" % gossip_target)
		gossip_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		gossip_btn.pressed.connect(func(): _on_gossip(active))
		vbox.add_child(gossip_btn)
		if not _gossip_result_text.is_empty():
			vbox.add_child(_small_label(_gossip_result_text, Color(0.75, 0.9, 0.7) if _gossip_result_good else Color(0.9, 0.7, 0.65)))

	return panel

func _on_drink(active: Character, chosen_drink: Dictionary) -> void:
	if not active.spend_pennies(int(chosen_drink["price"])):
		_drink_result_text = "Can't afford that."
		_drink_result_good = false
		_rebuild_all()
		return
	var result := active.drink_alcohol(_consume_alcohol_def, int(chosen_drink["modifier"]), GameState.time_minutes_total())
	if result.success:
		_drink_result_text = "%s enjoys a %s (SL %+d)." % [active.character_name, chosen_drink["label"], result.success_levels]
		_drink_result_good = true
	else:
		var penalty := active.get_alcohol_characteristic_penalty()
		var msg := "%s knocks back a %s and it hits hard (SL %+d) — %d WS/BS/Ag/Dex/Int now." % [active.character_name, chosen_drink["label"], result.success_levels, penalty]
		if active.is_stinking_drunk and active.stinking_drunk_result > 0:
			var row: Dictionary = active.stinking_drunk_table_entry()
			if not row.is_empty():
				msg += "\nStinking Drunk! \"%s\" — %s" % [row["name"], row["text"]]
		_drink_result_text = msg
		_drink_result_good = false
	GameState.autosave()
	_rebuild_all()

func _on_gossip(active: Character) -> void:
	var result := TestResolver.resolve_skill_test(active, _gossip_def, "")
	if result.success:
		var rumour: String = GOSSIP_RUMOURS[randi() % GOSSIP_RUMOURS.size()]
		_gossip_result_text = "%s picks up a rumour: \"...%s\"" % [active.character_name, rumour]
		_gossip_result_good = true
	else:
		_gossip_result_text = "%s doesn't hear anything worth repeating." % active.character_name
		_gossip_result_good = false
	GameState.autosave()
	_rebuild_all()

## --- Rooms/Sleep ---------------------------------------------------------

func _room_tier(key: String) -> Dictionary:
	for t in ROOM_TIERS:
		if t["key"] == key:
			return t
	return ROOM_TIERS[0]

## Cost in Brass Pennies to book `tier_key` for `party_size` people
## tonight. Common Room is priced per person (no capacity limit); Room/
## Large Room are priced per ROOM, so a party bigger than one room's
## capacity needs (and pays for) more than one, rounded up.
func _room_cost_pennies(tier_key: String, party_size: int) -> int:
	if party_size <= 0:
		return 0
	match tier_key:
		"common":
			return COMMON_ROOM_PENNIES_PER_PERSON * party_size
		"room":
			return ceili(float(party_size) / float(ROOM_CAPACITY)) * ROOM_PENNIES_PER_ROOM
		"large_room":
			return ceili(float(party_size) / float(LARGE_ROOM_CAPACITY)) * LARGE_ROOM_PENNIES_PER_ROOM
		_:
			return 0

## Same coin-formatting convention as shop_screen.gd's own
## _format_price() — duplicated rather than shared, per this project's
## established "independently-working screens" convention.
func _format_price(pennies: int) -> String:
	if pennies >= Character.PENNIES_PER_CROWN:
		var gc := pennies / float(Character.PENNIES_PER_CROWN)
		return "%.1f GC" % gc if pennies % Character.PENNIES_PER_CROWN != 0 else "%d GC" % int(gc)
	elif pennies >= Character.PENNIES_PER_SHILLING:
		var ss := int(pennies / Character.PENNIES_PER_SHILLING)
		var rem := pennies % Character.PENNIES_PER_SHILLING
		return "%d/%d" % [ss, rem] if rem > 0 else "%d/–" % ss
	else:
		return "%dd" % pennies

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

	## Short nap — free, no room needed (you're resting in the taproom,
	## not renting a bed), same as Camp's own short nap: passes time,
	## grants no recovery. Only a Full Night's Sleep below requires
	## paying for a room, per the request. Per the follow-up request
	## ("rename the short nap to Resting"): the button's own label now
	## reads "(Resting)" instead of "(short nap)" — purely a display
	## text change, the mechanic itself (_on_sleep with is_full_night =
	## false) is untouched.
	var sleep_btn := _compact_button("Sleep %d Hour%s (Resting)" % [sleep_hours, "s" if sleep_hours != 1 else ""])
	sleep_btn.disabled = sleep_hours >= 8
	sleep_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sleep_btn.pressed.connect(func(): _on_sleep(sleep_hours * 60, false))
	container.add_child(sleep_btn)

	if not _sleep_result_text.is_empty():
		container.add_child(_small_label(_sleep_result_text, Color(0.75, 0.9, 0.7) if _sleep_result_good else Color(0.9, 0.7, 0.65)))

	var sleep_gap := Control.new()
	sleep_gap.custom_minimum_size = Vector2(0, 10)
	container.add_child(sleep_gap)

	## Room-for-the-night picker — replaces Camp's Make Camp/Food gating
	## entirely. Priced for the whole living party at once (an
	## Unconscious member still needs a bed, so this uses the full
	## living party, not just those able to act — Camp's own
	## "functional party" concept doesn't apply here since there's no
	## Endeavour to be functional FOR).
	container.add_child(_header("Room for the Night"))
	var living: Array[Character] = _living_party()
	var living_count: int = living.size()

	var room_picker := OptionButton.new()
	room_picker.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	var tier_index := 0
	for i in range(ROOM_TIERS.size()):
		var t: Dictionary = ROOM_TIERS[i]
		var cost: int = _room_cost_pennies(t["key"], living_count)
		room_picker.add_item("%s — %s/night" % [t["label"], _format_price(cost)])
		if t["key"] == _room_tier_key:
			tier_index = i
	room_picker.selected = tier_index
	room_picker.item_selected.connect(func(idx: int):
		_room_tier_key = ROOM_TIERS[idx]["key"]
		_rebuild_all()
	)
	container.add_child(room_picker)

	var chosen_tier: Dictionary = _room_tier(_room_tier_key)
	var cost: int = _room_cost_pennies(chosen_tier["key"], living_count)
	var purse: int = GameState.player_character.get_total_pennies() if GameState.player_character != null else 0
	var affordable: bool = purse >= cost

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 6)
	status_row.add_child(_chip(
		"%s: %s" % [chosen_tier["label"], _format_price(cost)],
		Color(0.16, 0.3, 0.15) if affordable else Color(0.35, 0.16, 0.14)))
	status_row.add_child(_chip(
		"Heal bonus: %s" % ("+%d" % chosen_tier["heal_modifier"] if chosen_tier["heal_modifier"] > 0 else "+0"),
		Color(0.14, 0.26, 0.32), Color(0.4, 0.6, 0.7)))
	container.add_child(status_row)

	var blockers: Array[String] = []
	if not affordable:
		blockers.append("can't afford a %s tonight (%s needed, have %s)" % [chosen_tier["label"], _format_price(cost), _format_price(purse)])
	var blocked_tooltip := ""
	if not blockers.is_empty():
		blocked_tooltip = "Can't settle in for the night: " + "; ".join(blockers) + "."

	var wake_clock_8h: int = (GameState.time_minutes + 8 * 60) % (24 * 60)
	var full_sleep_btn := _compact_button("Full Night's Sleep (8 Hours, until %02d:%02d)  [Space]" % [wake_clock_8h / 60, wake_clock_8h % 60])
	full_sleep_btn.disabled = not blockers.is_empty()
	full_sleep_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if not blocked_tooltip.is_empty():
		full_sleep_btn.tooltip_text = blocked_tooltip
	full_sleep_btn.pressed.connect(func(): _on_sleep(8 * 60, true))
	container.add_child(full_sleep_btn)

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

	container.add_child(_small_label("A room's price includes a bed and a meal for everyone staying. Each character then rolls an Endurance Test (+20 for a Room/Large Room, +0 for a Common Room) and recovers SL + Toughness Bonus Wounds, plus loses 1 Fatigue. Shorter naps just pass time and don't need a room."))

	## Follow-up request ("show the party coin purse while in tavern
	## screen at the bottom under rooms"): the purse was already read
	## here (as `purse`, for the room-affordability check above) but
	## never actually shown to the player anywhere on this screen —
	## same GC/SS/BP format shop_screen.gd's own PurseLabel uses.
	var purse_gap := Control.new()
	purse_gap.custom_minimum_size = Vector2(0, 6)
	container.add_child(purse_gap)
	if GameState.player_character != null:
		var pc: Character = GameState.player_character
		container.add_child(_small_label("Purse: %d GC   %d SS   %d BP" % [pc.gold_crowns, pc.silver_shillings, pc.brass_pennies], Color(0.85, 0.7, 0.35)))

func _on_sleep(minutes: int, is_full_night: bool) -> void:
	GameState.advance_minutes(minutes)
	var duration_text := "%d hour%s" % [minutes / 60, "s" if minutes / 60 != 1 else ""]
	if minutes % 60 > 0:
		duration_text += " %d minute%s" % [minutes % 60, "s" if minutes % 60 != 1 else ""]
	if is_full_night:
		var living: Array[Character] = _living_party()
		var tier: Dictionary = _room_tier(_room_tier_key)
		var cost: int = _room_cost_pennies(tier["key"], living.size())
		var payer: Character = GameState.player_character
		## Defensive re-check — the buttons should already be disabled
		## otherwise, but a stale click (e.g. purse changed between
		## renders) shouldn't silently grant a free stay.
		if payer == null or not payer.spend_pennies(cost):
			_sleep_result_text = "You can't afford a %s tonight (%s needed)." % [tier["label"], _format_price(cost)]
			_sleep_result_good = false
			GameState.autosave()
			_rebuild_all()
			return

		var recovery_notes: Array[String] = []
		for member in living:
			var modifier: int = tier["heal_modifier"]
			var test := TestResolver.resolve_skill_test(member, _endurance_def, "", modifier)
			var toughness_bonus: int = member.get_characteristic_bonus("toughness")
			var recovered: int = max(0, test.success_levels + toughness_bonus)
			var before: int = member.wounds_current
			member.wounds_current = min(member.wounds_max, member.wounds_current + recovered)
			var actual: int = member.wounds_current - before
			if actual > 0:
				recovery_notes.append("%s recovers %d Wound(s) (now %d/%d)" % [member.character_name, actual, member.wounds_current, member.wounds_max])

			member.fortune_points = member.get_max_fortune_points()
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

		## Same "a genuine full night's rest resets the World Map's own
		## 8-hour travel cap" as camp_screen.gd.
		GameState.world_map_hours_since_rest = 0.0
		GameState.world_map_fatigue_warned_today = false
		GameState.world_map_fatigue_applied_today = false

		_sleep_result_text = "The party rents a %s for %s (%s) and sleeps soundly.\n%s" % [tier["label"], _format_price(cost), duration_text, "\n".join(recovery_notes) if not recovery_notes.is_empty() else "Nobody had Wounds left to recover."]
		_sleep_result_good = true
	else:
		_sleep_result_text = "The party rests for %s, but it's not enough for a full recovery." % duration_text
		_sleep_result_good = true
	GameState.autosave()
	_rebuild_all()

func _show_message(text: String, good: bool) -> void:
	message_label.text = text
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55) if good else Color(0.85, 0.6, 0.55))

## Same modal Result popup as camp_screen.gd's own — see that file's
## comment on why Heal/Bless outcomes need one now that Sleep (and the
## button that would've triggered it) can live well below the fold.
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
	ok_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ok_btn.pressed.connect(_dismiss_outcome_popup)
	vbox.add_child(ok_btn)
	ok_btn.grab_focus()

func _dismiss_outcome_popup() -> void:
	if _outcome_overlay != null:
		_outcome_overlay.queue_free()
		_outcome_overlay = null

## Per the request, reached from a CityScreen POI's radial menu (not
## the World Map like Camp) — Esc/Close returns to that same
## CityScreen, at the same city, rather than to Overworld. Setting
## pending_city_id before the scene change mirrors exactly how
## Overworld itself first enters CityScreen (see city_screen.gd's own
## _ready()); the party's on-map position was already remembered in
## GameState.city_player_positions before the player ever left for
## this screen, so they resume in the same spot automatically.
func _on_close() -> void:
	GameState.pending_city_id = GameState.pending_tavern_city_id
	GameState.autosave()
	get_tree().change_scene_to_file("res://scenes/CityScreen.tscn")

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
		## Per the bug report ("switching character in Tavern's is not
		## working right now"): the Tavern Activities box's own "As %s —
		## [Q/E] to switch" label (_build_tavern_activities_box) has
		## always advertised this, but this screen's _unhandled_input
		## never actually implemented the Q/E keys themselves — every
		## OTHER screen with this same convention (city_screen.gd,
		## overworld.gd, shop_screen.gd, healer_screen.gd,
		## field_encounter_screen.gd) wires its own Q/E handling, and
		## this one was simply missing it. Same GameState.
		## cycle_active_party_member() the Overworld's own Q/E uses (this
		## screen's "active character" IS GameState.player_character
		## directly, not a separate screen-local target like Shop/
		## Healer's own `character` — see _build_tavern_activities_box's
		## comment), then a full rebuild so the Activities box, its Drink/
		## Gossip actions, and the purse reading (which also reads
		## GameState.player_character) all reflect the newly-active
		## character immediately.
		elif event.keycode == KEY_Q:
			get_viewport().set_input_as_handled()
			GameState.cycle_active_party_member(-1)
			_rebuild_all()
		elif event.keycode == KEY_E:
			get_viewport().set_input_as_handled()
			GameState.cycle_active_party_member(1)
			_rebuild_all()
		elif event.keycode == KEY_SPACE:
			## Same "[Space]" quick-key the Full Night's Sleep button's
			## own label already advertises — camp_screen.gd's Space
			## triggers its Run Endeavour Session instead, since that
			## screen has no equivalent single primary action.
			get_viewport().set_input_as_handled()
			var living: Array[Character] = _living_party()
			var tier: Dictionary = _room_tier(_room_tier_key)
			var cost: int = _room_cost_pennies(tier["key"], living.size())
			var purse: int = GameState.player_character.get_total_pennies() if GameState.player_character != null else 0
			if purse >= cost:
				_on_sleep(8 * 60, true)

func _clear(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()
