extends Node2D
## The overworld: a small test map built from an ASCII layout at runtime
## (rather than hand-painted in the editor, since that's far more
## reliable to author as text). Handles walkability, NPC dialogue on
## interact, and a simple step-based random encounter chance on grass
## tiles that hands off to FieldEncounter.tscn.

## Per the request: quadrupled from the original 16px so the richer,
## more painterly village tileset art has room to show its detail —
## tileset.png/tileset.tres were regenerated at 64x64 per tile to
## match (same column order/count as before, just 4x the pixels per
## tile). Dungeon scenes are entirely unaffected — they use their own
## grid system (see battle_grid.gd / DungeonThemeDefinition), not this
## constant.
const TILE_SIZE := 64

## Legend: T=tree(walkable, 25% slower — see Player._move_to)
## M=mountain(blocked) #=wall(blocked) ~=water(blocked)
## .=grass(walkable, encounters) ,=flowers(walkable, safe) P=path(walkable, safe)
## @=player start (path underneath)  N=NPC start (path underneath)
## H=Hermit Wizard, a Petty Magic trainer (path underneath)
## Y=Shallyan Priest healer, cures Critical Wound effects for coin (path underneath)
## Per the request: a bridge crosses the river at row 19; everything
## east of the river (see difficulty_areas below) is a Tier 1 zone with
## a walled cave in the north and a dark forest + walled goblin fort in
## the south, both reachable via guaranteed clear trails from the
## bridge's east landing so the denser tree cover can never accidentally
## seal either landmark off. Per a later request, the map's own outer
## edge is now a ring of Mountains (impassable) instead of Trees
## (walkable-but-slow) — Trees inside the map (village grove, the dark
## forest, the cave's approach) can now be walked through directly.
## The map grid — loaded at runtime from a LocalMapDefinition Resource
## (see scripts/resources/local_map_definition.gd) rather than
## hardcoded here. Phase 1 of the world-map plan: this makes the
## village the first *defined* location instead of the only possible
## one, with no behavior change yet — see _load_map_definition().
var map_rows: Array[String] = []
## Which LocalMapDefinition to load. A plain @export path for now
## (always the village) rather than anything dynamic — later phases
## will set this based on which location the player is actually
## travelling to/from.
@export var map_definition_path: String = "res://data/maps/giessingen_village.tres"
var current_map_def: LocalMapDefinition = null
## Replaces the old const VILLAGE_ELDER_TILE — now loaded per-map from
## the LocalMapDefinition, Vector2i(-1, -1) for any map without this NPC.
var elder_tile: Vector2i = Vector2i(-1, -1)
var world_map_exit_tile: Vector2i = Vector2i(-1, -1)

func _load_map_definition() -> void:
	var path := map_definition_path
	if GameState.pending_map_path != "":
		path = GameState.pending_map_path
		GameState.pending_map_path = ""
	elif GameState.last_active_map_path != "":
		## Per the follow-up request's own reported bug: returning from
		## an encounter (or anywhere else that doesn't set
		## pending_map_path) should land back on whichever map was
		## actually active before leaving — the World Map, if that's
		## where the player was — not always reset to Giessingen.
		path = GameState.last_active_map_path
	current_map_def = load(path)
	GameState.last_active_map_path = path
	map_rows = current_map_def.map_rows
	difficulty_areas = current_map_def.difficulty_areas
	elder_tile = current_map_def.elder_tile
	world_map_exit_tile = current_map_def.world_map_exit_tile
	default_difficulty_tier = current_map_def.default_difficulty_tier

## Per Phase 2 of the world-map plan: finds the LocationDefinition (if
## any) whose own world_tile matches the given tile — null if none
## (e.g. clicking ordinary terrain).
func _get_location_at(tile: Vector2i) -> LocationDefinition:
	if current_map_def == null:
		return null
	for loc in current_map_def.locations:
		if loc.world_tile == tile:
			return loc
	return null

## Per the request: finds which province (if any) a given World Map
## tile falls within — a city marker's own tile also always falls
## within some province, so a city click shows city info specifically
## (checked first by the caller), while an ordinary tile falls back
## to whichever province contains it.
func _get_province_at(tile: Vector2i) -> ProvinceDefinition:
	if current_map_def == null:
		return null
	for prov in current_map_def.provinces:
		if prov.bounds.has_point(tile):
			return prov
	return null

## Per the request: the real "Travel Stages and Distances" table
## (Miles per 8-Hour Stage), keyed by Movement then terrain category.
## An 8-hour stage is treated as one travel day here, matching this
## project's own existing day-based travel system. Movement above 10
## clamps to the table's own top row rather than extrapolating beyond
## data the table doesn't actually provide.
const TRAVEL_STAGE_MILES := {
	"plains": [0.0, 6.5, 12.0, 18.5, 24.0, 30.5, 36.0, 42.5, 48.0, 54.5, 60.0],
	"forest": [0.0, 4.5, 9.0, 13.5, 18.0, 22.5, 27.0, 31.5, 36.0, 40.5, 45.0],
	"difficult": [0.0, 3.0, 6.0, 9.0, 12.0, 15.0, 18.0, 21.0, 24.0, 27.0, 30.0],
}
const WORLD_MAP_MILES_PER_TILE := 11.0

## Per the request: which of the table's own three terrain categories
## a given World Map tile counts as. Roads/paths/farmland/plain grass
## count as Hills or Plains (fastest); ordinary and snowy trees count
## as Forest or Deep Woodland; mountains, water, and snow count as
## Wetland or Mountains (slowest) — snow specifically grouped here
## since deep, difficult snowfields are the closest real match the
## table offers, not a fourth category the table doesn't have.
func _terrain_category(ch: String) -> String:
	if ch in ["M", "~", "s"]:
		return "difficult"
	if ch in ["T", "f"]:
		return "forest"
	return "plains"

## Per the request: which Wilderness Travel Events table applies at a
## given tile — distinct from _terrain_category() above (which only
## needs three buckets for travel-speed purposes), since the source
## material keeps Mountains and Wetlands as two entirely separate
## tables despite both being "difficult" terrain for travel speed.
func _wilderness_table_category(ch: String) -> String:
	if ch == "M":
		return "difficult_mountain"
	if ch in ["~", "s"]:
		return "difficult_wetland"
	if ch in ["T", "f"]:
		return "forest"
	return "plains"

## Per the request: real Movement- and terrain-based travel time,
## replacing the previous flat tiles-per-day rate. Walks the actual
## pathfound route between the two tiles (not a straight-line
## estimate) and sums each tile's own real terrain-appropriate travel
## cost, so a route crossing forest or difficult ground genuinely
## takes longer than the same distance over open plains or road.
## Per the request: travel time is always determined by the party's
## own slowest member, not whoever happens to be the active/controlled
## one — a group can only move as fast as its slowest member allows.
## Falls back to the active character's own Movement if the party is
## somehow empty, so this never breaks the single-character case.
func _party_travel_movement() -> int:
	if GameState.party.is_empty():
		return floori(GameState.player_character.get_movement()) if GameState.player_character != null else 0
	var slowest: int = 999
	for member in GameState.party:
		slowest = mini(slowest, floori(member.get_movement()))
	return slowest

## Per the user's bug report ("now i'm standing outside giessingen and it
## say its a 999 days journey to anywhere i try to go... reenter and
## leave again but it stays the same"): _compute_travel_days' own 999
## sentinel (below) means Movement 0 — genuinely can't travel at all,
## most commonly because someone in the party is Overloaded (carrying
## more than 3x their capacity, p.293: "you're not moving"). That's a
## real, persistent state (tied to inventory weight, not to being
## inside/outside a city), which is exactly why re-entering and leaving
## Giessingen never changed anything — nothing about that carried weight
## changed either. The bug wasn't the block itself; it was that every
## travel prompt just showed the raw "999 day(s) travel" sentinel with a
## [Confirm] button, instead of ever explaining WHY. This is read by
## every travel-offer call site to show a clear reason and skip the
## nonsensical Confirm/Cancel prompt entirely when travel is genuinely
## blocked. Returns "" when the party can travel normally.
func _travel_blocked_reason() -> String:
	if _party_travel_movement() > 0:
		return ""
	var members: Array = GameState.party
	if members.is_empty() and GameState.player_character != null:
		members = [GameState.player_character]
	var overloaded_names: Array[String] = []
	for m in members:
		if m != null and bool(m.get_encumbrance_penalty().get("immobile", false)):
			overloaded_names.append(m.character_name)
	if not overloaded_names.is_empty():
		return "%s carrying far too much to travel (Overloaded) — drop or stow some gear before setting out." % (
			"%s is" % overloaded_names[0] if overloaded_names.size() == 1 else "%s are" % ", ".join(overloaded_names)
		)
	return "Your party can't travel right now."

func _compute_travel_days(from_tile: Vector2i, to_tile: Vector2i) -> int:
	if from_tile == to_tile:
		return 0
	## Per v0.2.525 ("stuck outside Giessingen" follow-up): floors
	## Movement at 1 for THIS rate-table lookup only — Character.
	## get_movement() itself is untouched and still correctly returns 0
	## when Overloaded everywhere else (combat, local-map movement).
	## _offer_travel/_offer_travel_to_tile no longer block on
	## _travel_blocked_reason() at all (see their own comments — blocking
	## every World Map step while Overloaded was an unrecoverable
	## soft-lock), so this is what stops that from just reintroducing the
	## old nonsensical "999 day(s) travel" prompt instead: a real, if very
	## slow, day count from the existing Travel Stages table. The actual
	## rule ("you're not moving" while Overloaded) is still enforced for
	## real at the one place that matters — _offer_return_to_world_map(),
	## the actual point of setting out — not here.
	var movement: int = clampi(_party_travel_movement(), 1, 10)
	var path: Array = astar_grid.get_id_path(from_tile, to_tile)
	if path.is_empty():
		## No real walkable route — fall back to a straight-line
		## plains-rate estimate rather than claiming the journey is
		## impossible; the World Map's own mountains/water aren't
		## meant to be a hard travel blocker at this scale.
		var straight_dist: float = Vector2(from_tile - to_tile).length()
		var plains_rate: float = TRAVEL_STAGE_MILES["plains"][movement]
		return max(1, ceili((straight_dist * WORLD_MAP_MILES_PER_TILE) / plains_rate))
	var total_stages := 0.0
	for i in range(1, path.size()):
		var tile: Vector2i = path[i]
		var cat := _terrain_category(tile_chars.get(tile, "."))
		var rate: float = TRAVEL_STAGE_MILES[cat][movement]
		if rate <= 0.0:
			continue
		total_stages += WORLD_MAP_MILES_PER_TILE / rate
	return max(1, ceili(total_stages))

## Per the request: real per-tile time cost on the World Map, using
## the same Travel Stages table _compute_travel_days() above uses for
## the multi-day confirmation — each tile genuinely costs real
## in-game minutes based on the traveller's own Movement and the
## terrain of the tile just reached, rather than the flat local-map
## "Movement = tiles per minute" system, which doesn't make sense at
## an 11-miles-per-tile scale.
##
## Also enforces the source's own real 8-hour-per-day travel cap (one
## Stage): the first tile that pushes the day's own running total past
## 8 hours triggers a clear one-time warning; any further tile moved
## the same day without a genuine full night's Camp sleep costs a real
## Fatigued Condition (once per over-extended day, not once per tile).
func _advance_world_map_step_time(new_tile: Vector2i) -> void:
	var movement: int = clampi(_party_travel_movement(), 0, 10)
	if movement <= 0:
		return
	var cat := _terrain_category(tile_chars.get(new_tile, "."))
	var rate: float = TRAVEL_STAGE_MILES[cat][movement]
	if rate <= 0.0:
		return
	var hours_for_tile: float = (WORLD_MAP_MILES_PER_TILE / rate) * 8.0
	var minutes_for_tile: int = maxi(1, int(round(hours_for_tile * 60.0)))

	var was_over := GameState.world_map_hours_since_rest >= 8.0
	GameState.world_map_hours_since_rest += hours_for_tile
	GameState.advance_minutes(minutes_for_tile)
	GameState.autosave()

	if GameState.world_map_hours_since_rest >= 8.0 and not was_over:
		GameState.world_map_fatigue_warned_today = true
		_show_wilderness_text("You've been travelling for a full day (8 hours) — time to make camp for a full night's rest.\nPushing on further today will cost you Fatigue.")
	elif was_over and not GameState.world_map_fatigue_applied_today:
		GameState.world_map_fatigue_applied_today = true
		GameState.player_character.add_condition("Fatigued", 1)
		_show_wilderness_text("Exhaustion catches up with you from travelling too long without rest.\n(Fatigued)")

## Per the request: the Lore radial-menu button's own content — city
## info if the clicked tile is a real location marker, otherwise
## whichever province contains it, plus real current distance and
## travel time from the player's own actual position, now using the
## real WFRP Travel Stages table above rather than a flat rate.
func _show_lore_box() -> void:
	var tile := _radial_menu_target_lore_tile
	var title := ""
	var body := ""
	var loc := _get_location_at(tile)
	if loc != null:
		title = loc.location_name
		body = "A city of the Empire."
	else:
		var prov := _get_province_at(tile)
		if prov != null:
			title = prov.province_name
			body = prov.summary
		else:
			title = "Uncharted"
			body = "No records of this stretch of land."

	var dist_tiles: float = Vector2(player.grid_pos - tile).length()
	var miles: float = dist_tiles * WORLD_MAP_MILES_PER_TILE
	var days: int = _compute_travel_days(player.grid_pos, tile)
	## Per the same fix as _offer_travel/_offer_travel_to_tile above:
	## don't surface the raw 999-day sentinel here either.
	var blocked_reason := _travel_blocked_reason()
	var travel_line: String
	if dist_tiles == 0:
		travel_line = "You are already here."
	elif not blocked_reason.is_empty():
		travel_line = blocked_reason
	else:
		travel_line = "%d miles away — about %d day(s) travel." % [int(round(miles)), days]

	_build_lore_popup(title, body, travel_line)

## Builds and shows the actual Lore popup — a real screen-space panel,
## code-built rather than a pre-authored scene node, dismissed by its
## own Close button or Escape.
var _lore_popup: CanvasLayer = null
func _build_lore_popup(title: String, body: String, travel_line: String) -> void:
	if is_instance_valid(_lore_popup):
		_lore_popup.queue_free()
	_lore_popup = CanvasLayer.new()
	_lore_popup.layer = 60
	add_child(_lore_popup)

	var backdrop := Control.new()
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_lore_popup.add_child(backdrop)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5; panel.anchor_top = 0.5
	panel.anchor_right = 0.5; panel.anchor_bottom = 0.5
	panel.offset_left = -180; panel.offset_top = -110
	panel.offset_right = 180; panel.offset_bottom = 110
	backdrop.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title_label)

	var body_label := Label.new()
	body_label.text = body
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(body_label)

	var travel_label := Label.new()
	travel_label.text = travel_line
	travel_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	travel_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.65))
	vbox.add_child(travel_label)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): _lore_popup.queue_free())
	vbox.add_child(close_btn)

var awaiting_travel_confirm: bool = false
var _pending_travel_location: LocationDefinition = null
var _pending_travel_tile: Vector2i = Vector2i(-1, -1)
## Per the request: forces a real camp-or-continue choice after every
## completed Stage of World Map travel.
var _awaiting_stage_choice: bool = false
var _stage_choice_continue: bool = true

## Per the request ("always allow WASD movement and hotkey space to
## accept selected for these all these types of pop ups"): every real
## Y/N confirmation prompt (_offer_travel, _offer_travel_to_tile,
## _offer_enter_location, _offer_return_to_world_map,
## _offer_stage_choice, _show_wilderness_choice) now shows a real
## selectable highlight between its two options — Left/Up (or the
## project's own move_left/move_up actions, i.e. WASD's A/W) selects
## the [Y] option, Right/Down (D/S) selects [N], and Space accepts
## whichever is currently selected. The direct Y/N keys keep working
## exactly as before (unchanged, for muscle memory) — this is purely
## an additional way to answer the same prompt. Defaults to [Y]
## selected, matching every prompt's own existing "Y is the more
## common/expected answer" convention (Confirm/Enter/Push on).
var _confirm_selected_yes: bool = true
## The current prompt's own text, split into its three components so
## _render_confirm_prompt() can redraw it with the selection highlight
## live (on every WASD toggle) without each call site needing to know
## about the highlight itself — they just set these three and call
## _render_confirm_prompt() once, exactly where they used to set
## encounter_label_text.text directly.
var _confirm_prompt_base: String = ""
var _confirm_prompt_yes_label: String = ""
var _confirm_prompt_no_label: String = ""

## True while ANY of the Y/N prompts above is actually up — used by
## _unhandled_input's own WASD-select/Space-accept handling below so
## it doesn't need to know which specific prompt is currently showing.
func _any_yn_prompt_awaiting() -> bool:
	return _awaiting_stage_choice or awaiting_travel_confirm or _awaiting_wilderness_choice or _awaiting_ambush_choice

## Composes `_confirm_prompt_base/yes_label/no_label` into the actual
## displayed string, with a "►" marker in front of whichever option
## `_confirm_selected_yes` currently points at — called once when a
## prompt first opens, and again every time WASD toggles the
## selection, so the highlight is always genuinely live.
func _render_confirm_prompt() -> void:
	var yes_mark := "►" if _confirm_selected_yes else "  "
	var no_mark := "►" if not _confirm_selected_yes else "  "
	encounter_label_text.text = "%s\n%s[Y] %s   %s[N] %s" % [_confirm_prompt_base, yes_mark, _confirm_prompt_yes_label, no_mark, _confirm_prompt_no_label]

## Sets up and shows a Y/N prompt's text (used by every _offer_*/
## _show_wilderness_choice call site below in place of directly
## assigning encounter_label_text.text) — resets the selection back to
## [Y] every time a fresh prompt opens, same as before this feature
## (each prompt used to always show as if Y were the "default").
func _start_confirm_prompt(base: String, yes_label: String, no_label: String) -> void:
	_confirm_prompt_base = base
	_confirm_prompt_yes_label = yes_label
	_confirm_prompt_no_label = no_label
	_confirm_selected_yes = true
	_render_confirm_prompt()

## The real "what happens on Y" / "what happens on N" logic for
## whichever prompt is currently open — factored out of the KEY_Y/
## KEY_N branches in _unhandled_input so Space (accepting whichever
## option _confirm_selected_yes points at) can call the exact same
## code, guaranteeing it behaves identically to pressing the
## corresponding letter key rather than becoming a second, drifting
## copy of the same branching logic.
func _confirm_prompt_press_yes() -> void:
	if _awaiting_stage_choice:
		## Per the request ("swap this prompt around, Yes to make Camp,
		## No to Push on. Default on Yes"): [Y] now means "make camp"
		## (continue = false), [N] means "push on" (continue = true) —
		## the reverse of this prompt's original Y/N mapping.
		_stage_choice_continue = false
		_awaiting_stage_choice = false
	elif awaiting_travel_confirm:
		awaiting_travel_confirm = false
		if _pending_enter_location != null:
			_entered_confirmed = true
		elif _pending_enter_goblin_fort:
			_entered_confirmed = true
		elif _pending_enter_cave_dungeon:
			_entered_confirmed = true
		else:
			_confirm_travel()
	elif _awaiting_wilderness_choice:
		_wilderness_choice_result = true
		_awaiting_wilderness_choice = false
	elif _awaiting_ambush_choice:
		_ambush_choice_result = true
		_awaiting_ambush_choice = false

func _confirm_prompt_press_no() -> void:
	if _awaiting_stage_choice:
		## See _confirm_prompt_press_yes()'s own comment above — [N] is
		## now "push on" (continue = true), the swapped mapping.
		_stage_choice_continue = true
		_awaiting_stage_choice = false
	elif awaiting_travel_confirm:
		awaiting_travel_confirm = false
		## Real bug fix (kept, unchanged from before this feature): none
		## of these were ever reset on cancel, so a cancelled offer's
		## stale state could incorrectly drive the next real
		## _confirm_travel() call.
		_pending_travel_tile = Vector2i(-1, -1)
		_pending_travel_location = null
		_pending_enter_location = null
		_pending_enter_goblin_fort = false
		_pending_enter_cave_dungeon = false
	elif _awaiting_wilderness_choice:
		_wilderness_choice_result = false
		_awaiting_wilderness_choice = false
	elif _awaiting_ambush_choice:
		_ambush_choice_result = false
		_awaiting_ambush_choice = false
## Per the request: lets the player stop travelling at any point via
## Esc or Space while a journey is actually in progress — checked
## between Stages in the travel loop itself, not consumed instantly,
## since the loop is mid-await when this gets set.
var _travel_cancel_requested: bool = false
## True only for the actual duration of a journey (set/cleared by
## _run_travel_day_loop) — distinguishes "currently animating between
## Stages, nothing else showing" from every other moment, so Esc/Space
## can safely mean "stop travelling" only then, without stealing the
## same keys from an active sub-prompt (a Wilderness Event, the Stage
## choice itself, etc.).
var _travel_in_progress: bool = false
## Per the request: left-click drag panning on the World Map (WASD and
## click-to-move are both disabled there, so this is the only way to
## look around without actually travelling). The camera stays a child
## of the player (so it snaps straight back to following them the
## moment they warp anywhere), and this is a real position OFFSET
## applied on top of that — reset whenever the World Map is left or
## the player's own position changes, so a pan never persists into
## somewhere it doesn't make sense.
var _is_dragging_camera: bool = false
var _drag_confirmed: bool = false
var _drag_start_mouse_pos: Vector2 = Vector2.ZERO
var _drag_start_camera_offset: Vector2 = Vector2.ZERO
var _world_map_camera_offset: Vector2 = Vector2.ZERO
const CAMERA_DRAG_THRESHOLD := 6.0
var _pending_enter_location: LocationDefinition = null
var _entered_confirmed: bool = false
## Per the Goblin Fort rework: same "confirm, then act" shape as
## _pending_enter_location/_entered_confirmed above, but for stepping
## onto the fort's own gate tile ("j") rather than a world-map
## LocationDefinition — see _offer_enter_goblin_fort_dungeon().
var _pending_enter_goblin_fort: bool = false
## Per the NE Cave rework: same shape again, but for the new cave
## entrance tile ("y") — see _offer_enter_cave_dungeon().
var _pending_enter_cave_dungeon: bool = false
## Per the request: tracks the last tile a standing-trigger prompt
## (enter city / leave for World Map) fired on, so simply standing
## still after answering "no" doesn't immediately re-ask every frame
## — only actually moving to the tile again re-triggers it.
var _last_standing_prompt_tile: Vector2i = Vector2i(-999, -999)
var _pending_travel_days: int = 0

## Per Phase 2 of the world-map plan: offers a multi-day journey to
## the given location, computed by real tile distance on the World Map
## (Chebyshev, matching this project's own 4-directional/diagonal-free
## movement elsewhere isn't quite right here since this is a distance
## estimate, not a walked path — straight-line distance is the more
## honest approximation for "as the crow flies" travel time) divided
## by the map's own world_map_tiles_per_day. Standing on the location
## already (0 tiles away) still costs a minimum of 1 day, since
## "arriving instantly at your own current tile" isn't a real journey.
## Real bug fix: none of the four offer functions below reset every
## pending-travel field at their own start — only the ones each one
## happened to use. Stale state from an earlier offer (especially one
## cancelled with N) could then leak into a later, unrelated one — for
## example, leaving a local map for the World Map while a stale
## _pending_travel_tile was still set from an earlier cancelled
## "Travel to this tile" offer would make _confirm_travel() wrongly
## treat the return trip as a tile-travel instead, using the wrong
## map's own coordinate data. Every offer function now calls this
## first, unconditionally.
func _reset_pending_travel_state() -> void:
	_pending_travel_tile = Vector2i(-1, -1)
	_pending_travel_location = null
	_pending_enter_location = null
	_pending_travel_days = 0

func _offer_travel(loc: LocationDefinition) -> void:
	_reset_pending_travel_state()
	## Real bug fix (user report: "now i'm stuck outside Giessingen, let
	## do the block only when leaving the village"): this used to check
	## _travel_blocked_reason() and refuse the offer outright whenever
	## Overloaded — but the World Map has no free WASD/click-to-move at
	## all, every single step (including re-entering a city you're
	## already standing right next to) routes through this same function,
	## so blocking it here left an Overloaded party with no way to do
	## ANYTHING on the World Map, including stepping back into a city to
	## drop gear and fix the problem — a genuine soft-lock. The real
	## enforcement point is _offer_return_to_world_map() below (leaving a
	## local map for the road) — see its own comment.
	var days: int = _compute_travel_days(player.grid_pos, loc.world_tile)
	_pending_travel_location = loc
	_pending_travel_days = days
	_start_confirm_prompt("Travel to %s? %d day(s) travel." % [loc.location_name, days], "Confirm", "Cancel")
	encounter_label.visible = true
	awaiting_travel_confirm = true
	while awaiting_travel_confirm:
		await get_tree().process_frame
	encounter_label.visible = false

## Per the request: the Travel radial-menu button's own generic
## version of _offer_travel() above — for any right-clicked World Map
## tile, not just a city marker. Reuses the exact same day
## calculation, confirmation prompt, and Wilderness Event resolution.
func _offer_travel_to_tile(tile: Vector2i) -> void:
	_reset_pending_travel_state()
	## Same real bug fix as _offer_travel() above — see its own comment.
	## Genuinely blocking every World Map step while Overloaded left no
	## way to recover; the real enforcement point is
	## _offer_return_to_world_map() (leaving a local map), not here.
	var days: int = _compute_travel_days(player.grid_pos, tile)
	_pending_travel_tile = tile
	_pending_travel_days = days
	_start_confirm_prompt("Travel here? %d day(s) travel." % days, "Confirm", "Cancel")
	encounter_label.visible = true
	awaiting_travel_confirm = true
	while awaiting_travel_confirm:
		await get_tree().process_frame
	encounter_label.visible = false

## Per the request: standing on a city's own tile on the World Map
## offers to enter its local map — a separate, 0-day choice from
## _offer_travel() above (which is for getting there in the first
## place). If the city doesn't have a real local map built yet, says
## so plainly rather than pretending to enter.
func _offer_enter_location(loc: LocationDefinition) -> void:
	_reset_pending_travel_state()
	_start_confirm_prompt("Enter %s?" % loc.location_name, "Enter", "Stay outside")
	encounter_label.visible = true
	awaiting_travel_confirm = true
	_pending_enter_location = loc
	while awaiting_travel_confirm:
		await get_tree().process_frame
	encounter_label.visible = false
	if _entered_confirmed:
		_entered_confirmed = false
		if loc.city_screen_scene_path != "":
			## New City Screen feature: checked FIRST, ahead of the
			## ordinary tile-grid local_map_path below — a city with
			## its own image-map screen (Ubersreik, so far) never
			## falls through to the tile-grid path at all, but any
			## location that ISN'T set up this way is completely
			## unaffected (city_screen_scene_path stays "" for every
			## other LocationDefinition).
			GameState.world_map_player_position = loc.world_tile
			GameState.pending_city_id = loc.city_id
			GameState.autosave()
			get_tree().change_scene_to_file(loc.city_screen_scene_path)
		elif loc.local_map_path == "":
			encounter_label_text.text = "%s isn't ready to explore yet — this part of the Empire is still a work in progress." % loc.location_name
			encounter_label.visible = true
			await get_tree().create_timer(2.5).timeout
			encounter_label.visible = false
		else:
			GameState.world_map_player_position = loc.world_tile
			GameState.pending_map_path = loc.local_map_path
			## Per the request: zoning in uses the same tile as zoning
			## out — entering a local map lands the player at its own
			## exit tile (the road they'd leave by), not always the
			## map's default spawn, so the two feel like the same real
			## crossing point rather than two unrelated teleports. Reads
			## the target map's own data directly since it hasn't
			## loaded yet at this point.
			var target_def: LocalMapDefinition = load(loc.local_map_path)
			GameState.pending_map_spawn_tile = target_def.world_map_exit_tile
			GameState.autosave()
			get_tree().change_scene_to_file("res://scenes/Overworld.tscn")
	_pending_enter_location = null

## Per the Goblin Fort rework request ("Stepping in to the Gate to
## access the new Goblin fort Dungeon"): same confirm-then-go shape as
## _offer_enter_location above, called from _check_standing_trigger()
## when the player steps onto the fort's own gate tile ("j") on
## Giessingen. Hands off to FieldEncounter.tscn's own exploration mode
## exactly the way the Rat Catcher's Guild sends the party into the
## sewer dungeon (see rat_catcher_guild_screen.gd's _on_quest_pressed()).
##
## Per the follow-up request ("the greenskin dungeon map should not
## remember its state if the player leaves, it should reset every time
## the player enters"): unlike the Sewer/Cave (which still prefer
## resuming an in-progress dungeon_state, see that comment on
## _offer_enter_cave_dungeon()/rat_catcher_guild_screen.gd), the Goblin
## Fort now ALWAYS discards any leftover dungeon_state and starts a
## completely fresh fort (new ambush roll, chest re-locked, entry_ambush_
## fired reset) every single time — whether the party left cleanly via
## Exit, retreated mid-fight, or simply abandoned an unfinished visit
## without ever reaching the entrance again. Declining the prompt below
## ("Stay outside") never touches dungeon_state/pending_dungeon_theme_id
## at all, so the gate remains freely re-triggerable later, same as
## before — nothing about this change blocks a later attempt.
func _offer_enter_goblin_fort_dungeon() -> void:
	_reset_pending_travel_state()
	_start_confirm_prompt("Enter the Goblin Fort?", "Enter", "Stay outside")
	encounter_label.visible = true
	awaiting_travel_confirm = true
	_pending_enter_goblin_fort = true
	while awaiting_travel_confirm:
		await get_tree().process_frame
	encounter_label.visible = false
	if _entered_confirmed:
		_entered_confirmed = false
		## Same "remember where to pop back out" convention every other
		## encounter/dungeon entry point uses (_trigger_idol_ambush(),
		## the corridor-ambush triggers, etc.) — lands the party back on
		## the gate tile itself once they leave the dungeon, rather than
		## the map's own unrelated default spawn.
		GameState.return_position = player.grid_pos
		## Always fresh — see this function's own header comment. Also
		## correctly discards a stale, unrelated OTHER dungeon's leftover
		## state (e.g. an abandoned Cave visit) that would otherwise have
		## silently blocked _load_or_generate_dungeon() from ever
		## generating the fort at all, since it only ever checks "is
		## dungeon_state non-empty," not which theme it belongs to.
		GameState.dungeon_state = {}
		## Same "discard the stale OTHER dungeon" reset as dungeon_state
		## just above -- an abandoned Cave visit's cached floors (see
		## GameState.dungeon_floor_states' own comment) don't belong to
		## the Goblin Fort delve about to start either.
		GameState.dungeon_floor_states = {}
		GameState.pending_dungeon_theme_id = "goblin_fort"
		## Real bug fix ("all outdoor field combat encounters jump to the
		## Goblin Fort dungeon"): this is one of the only real dungeon-
		## entry points in the game — see GameState.dungeon_entry_
		## requested's own header comment for the full explanation of why
		## this flag (not raw dungeon_state presence) has to be what
		## decides whether the FieldEncounter.tscn load below resumes
		## exploration.
		GameState.dungeon_entry_requested = true
		GameState.autosave()
		get_tree().change_scene_to_file("res://scenes/FieldEncounter.tscn")
	_pending_enter_goblin_fort = false

## Per the NE Cave rework request ("Stepping in to the Cave entrance to
## access the new Cave Dungeon"): same confirm-then-go shape as
## _offer_enter_goblin_fort_dungeon() above, called from
## _check_standing_trigger() when the player steps onto the new cave
## entrance tile ("y") on Giessingen. "Similar to Sewer dungeon" per the
## request — this dungeon uses the normal procedural
## DungeonGenerator.generate() (see field_encounter_screen.gd's
## _load_or_generate_dungeon(), which only special-cases "goblin_fort"),
## not the Goblin Fort's fixed single-room layout.
func _offer_enter_cave_dungeon() -> void:
	_reset_pending_travel_state()
	_start_confirm_prompt("Enter the Cave?", "Enter", "Stay outside")
	encounter_label.visible = true
	awaiting_travel_confirm = true
	_pending_enter_cave_dungeon = true
	while awaiting_travel_confirm:
		await get_tree().process_frame
	encounter_label.visible = false
	if _entered_confirmed:
		_entered_confirmed = false
		## Same "remember where to pop back out" convention as the
		## Goblin Fort gate above.
		GameState.return_position = player.grid_pos
		if GameState.dungeon_state.is_empty():
			GameState.pending_dungeon_theme_id = "cave"
		## Same real bug fix as _offer_enter_goblin_fort_dungeon() above —
		## see GameState.dungeon_entry_requested's own header comment.
		GameState.dungeon_entry_requested = true
		GameState.autosave()
		get_tree().change_scene_to_file("res://scenes/FieldEncounter.tscn")
	_pending_enter_cave_dungeon = false

## Per Phase 2 of the world-map plan: the reverse trip — leaving an
## ordinary local map (Giessingen, for now) back to the World Map,
## landing at wherever the player's own World Map position last was
## (or that map's own default spawn if they've genuinely never been
## there, e.g. the very first time leaving Giessingen).
func _offer_return_to_world_map() -> void:
	_reset_pending_travel_state()
	## Per the request ("let's do the block only when leaving the
	## village (and other places)"): this is the one real place an
	## Overloaded party actually needs stopping — heading out onto the
	## open road while carrying more than 3x capacity (p.293, "you're
	## not moving"). Unlike _offer_travel/_offer_travel_to_tile above,
	## refusing this specific exit never soft-locks anything: the player
	## is still standing inside a real settlement, free to visit its Shop
	## and drop/sell gear, then try leaving again.
	var blocked_reason := _travel_blocked_reason()
	if not blocked_reason.is_empty():
		await _show_wilderness_text(blocked_reason)
		return
	_start_confirm_prompt("Leave for the open road?", "Confirm", "Cancel")
	encounter_label.visible = true
	awaiting_travel_confirm = true
	while awaiting_travel_confirm:
		await get_tree().process_frame
	encounter_label.visible = false

## Per Phase 2 of the world-map plan: called once the player confirms
## a journey — advances the calendar by the real computed travel time,
## then either arrives at the destination's own local map (if one
## exists yet) or shows a plain "not yet explorable" notice and stays
## on the World Map, per the request's own phased-rollout approach
## (only Giessingen has a real local map so far). A null
## _pending_travel_location means "return to the World Map" instead —
## the reverse trip, with no travel-day cost of its own here (the
## outbound trip already charged for the whole round journey).
func _confirm_travel() -> void:
	## Per the request: this path (leaving a local map for the World
	## Map) shows no Wilderness Event and needs no timing fix at all —
	## kept fully synchronous and first, before anything below that
	## does, so it can never be affected by timing changes made for
	## the wilderness-event race fix further down.
	if _pending_travel_tile == Vector2i(-1, -1) and _pending_travel_location == null:
		GameState.pending_map_path = "res://data/maps/empire_world_map.tres"
		## Per the request: completely redone — no dynamic adjacent-
		## tile search, no session-state lookup, no reverse-searching
		## the World Map's own location list. The currently loaded
		## local map's own world_map_return_tile field (set directly
		## on its own map data — Vector2i(15, 30) for Giessingen) is
		## used exactly as-is, with nothing else able to interfere.
		if current_map_def != null and current_map_def.world_map_return_tile != Vector2i(-1, -1):
			GameState.pending_map_spawn_tile = current_map_def.world_map_return_tile
		GameState.autosave()
		get_tree().change_scene_to_file("res://scenes/Overworld.tscn")
		return
	## Real bug fix: the offer function that led here (_offer_travel,
	## _offer_travel_to_tile, etc.) is still mid-coroutine at this
	## point, waiting to wake up on its own next frame and
	## unconditionally hide encounter_label as its own cleanup. If a
	## Wilderness Event tries to show something on THIS same frame,
	## that stale cleanup would immediately hide it right after,
	## leaving nothing visible while the game is actually still
	## waiting on a Space/Y/N press the player has no way to see —
	## exactly the reported "sometimes doesn't move, and Wilderness
	## Events never visibly trigger." Yielding one frame first lets
	## that old coroutine's cleanup finish before anything new starts.
	await get_tree().process_frame
	if _pending_travel_tile != Vector2i(-1, -1):
		var tile := _pending_travel_tile
		var days2 := _pending_travel_days
		_pending_travel_tile = Vector2i(-1, -1)
		var route2: Array = astar_grid.get_id_path(player.grid_pos, tile)
		var cancelled2 := await _run_travel_day_loop(route2, days2, "your destination")
		if cancelled2:
			return
		GameState.world_map_player_position = tile
		encounter_label_text.text = "You arrive, %d day(s) later." % days2
		encounter_label.visible = true
		await get_tree().create_timer(1.5).timeout
		encounter_label.visible = false
		player.grid_pos = tile
		player.position = Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)
		_check_standing_trigger(tile)
		return
	var loc := _pending_travel_location
	var days := _pending_travel_days
	var route: Array = astar_grid.get_id_path(player.grid_pos, loc.world_tile)
	## Per the request: a real Wilderness Travel Event roll each Stage
	## (1 Stage = 1 day here), matching the source material's own
	## structure. A combat result genuinely interrupts the journey —
	## the scene transitions to FieldEncounter, and the remaining
	## distance is simply not yet covered; the player can choose to
	## resume travelling once the fight is over, same as any other
	## fresh journey.
	var cancelled := await _run_travel_day_loop(route, days, loc.location_name)
	if cancelled:
		return
	GameState.world_map_player_position = loc.world_tile
	encounter_label_text.text = "You arrive at %s, %d day(s) later." % [loc.location_name, days]
	encounter_label.visible = true
	await get_tree().create_timer(1.5).timeout
	encounter_label.visible = false
	player.grid_pos = loc.world_tile
	player.position = Vector2(loc.world_tile.x * TILE_SIZE, loc.world_tile.y * TILE_SIZE)
	## warp_to() doesn't emit the player's own "moved" signal, so the
	## standing-trigger check (which offers to enter the city) needs
	## an explicit call here rather than relying on that signal.
	_check_standing_trigger(loc.world_tile)

## Shared by both city travel and plain-tile travel — walks the route
## day by day (one day = one real Stage = 8 hours, per the source
## material), rolling for real Wilderness Events, forcing a real
## camp-or-continue choice after every single Stage, and watching for
## a real Esc/Space cancellation at any point. Returns true if the
## journey was interrupted (combat, or the player genuinely chose to
## stop) — the caller should not treat this as having arrived.
func _run_travel_day_loop(route: Array, days: int, destination_name: String) -> bool:
	## Real bug fix — the actual cause of the reported "game freezes
	## during World Map travel (near Giessingen), only sometimes":
	## nothing ever guarded against a SECOND call to this function
	## starting while a first one was still active on this same
	## Overworld instance. Two concurrent calls both read/write the
	## SAME shared state (_travel_in_progress, _awaiting_stage_choice,
	## encounter_label/encounter_label_text) — reproduced directly by
	## simulating real input events against the real code: whichever
	## loop's own "await _awaiting_stage_choice" resolves first can
	## silently steal or clobber the other's own prompt, leaving one
	## loop's while-loop spinning forever on a flag nothing will ever
	## flip again, with no visible prompt on screen for the player to
	## respond to — indistinguishable from a total freeze even though
	## the engine itself is still running fine underneath. A second
	## call is refused outright rather than risk that race.
	if _travel_in_progress:
		push_warning("Reikland Chronicles: _run_travel_day_loop() called while a journey was already in progress on this Overworld — ignored to avoid a UI race that looks like a freeze.")
		return true
	_travel_in_progress = true
	_show_travel_progress(0, days)
	var route_idx := 0
	for day_index in range(days):
		GameState.advance_days(1)
		var target_idx: int = clampi(int(float(day_index + 1) / float(days) * (route.size() - 1)), 0, route.size() - 1)
		await _animate_travel_along_route(route, route_idx, target_idx)
		route_idx = target_idx
		_show_travel_progress(day_index + 1, days)

		## Per the request: the player can stop travelling at any point
		## via Esc or Space, checked right after each Stage's own
		## movement completes.
		if _travel_cancel_requested:
			await _handle_travel_cancel(route[route_idx], destination_name)
			return true

		## Encumbrance (p.293): "Fatigued Conditions are accrued at the
		## end of a day's travel" — each completed Stage above IS one
		## day's travel per this loop's own comment, so this is exactly
		## that boundary. Scoped to the player_character only, matching
		## this project's existing single-character Fatigue-tracking
		## precedent (the over-8-hours-without-rest Fatigue in
		## _advance_world_map_step_time() and the Fatigue-easing in
		## _camp_in_place()/camp_screen.gd's _on_sleep() both do the
		## same) — not tracked per party member.
		if GameState.player_character != null:
			var enc := GameState.player_character.get_encumbrance_penalty()
			if int(enc["travel_fatigue"]) > 0:
				GameState.player_character.add_condition("Fatigued", int(enc["travel_fatigue"]))

		if randi_range(1, 10) >= 8:
			var sample_tile: Vector2i = _sample_route_tile(route, day_index, days)
			var wtable := _wilderness_table_category(tile_chars.get(sample_tile, "."))
			var event: Dictionary = WildernessEvents.roll_event(wtable)
			## Per the request: a Wilderness Event used to permanently
			## cancel the whole journey — the remaining route/days only
			## ever lived in this function's own local variables, which
			## are destroyed the instant the scene changes for the
			## event itself. Persisted here, before that can happen, so
			## Overworld can pick the journey back up automatically
			## afterward instead of losing it.
			var days_remaining: int = days - (day_index + 1)
			if days_remaining > 0:
				GameState.pending_resume_travel_route = route.slice(route_idx)
				GameState.pending_resume_travel_days_remaining = days_remaining
				GameState.pending_resume_travel_destination_name = destination_name
			var interrupted: bool = await _resolve_wilderness_event(event)
			if interrupted:
				_travel_in_progress = false
				_hide_travel_progress()
				return true

		## Per the request: a full 8-hour Stage of marching is now
		## complete — force a real choice before any further travel,
		## rather than silently continuing or silently applying
		## Fatigue as before. Skipped on the very last Stage, since
		## the journey is already over at that point.
		if day_index < days - 1:
			var keep_going := await _offer_stage_choice(destination_name)
			if _travel_cancel_requested:
				await _handle_travel_cancel(route[route_idx], destination_name)
				return true
			if not keep_going:
				await _camp_in_place()
	_travel_in_progress = false
	_hide_travel_progress()
	GameState.pending_resume_travel_route = []
	return false

## Per the request: a real progress bar, lower-center of the screen,
## tracking the actual day/Stage of the journey — visible only while
## a journey is genuinely in progress.
func _show_travel_progress(current_stage: int, total_stages: int) -> void:
	var panel: VBoxContainer = %TravelProgressPanel
	panel.visible = true
	%TravelStageLabel.text = "Travelling — Stage %d of %d" % [current_stage, total_stages]
	var bar: ProgressBar = %TravelProgressBar
	bar.max_value = total_stages
	bar.value = current_stage

func _hide_travel_progress() -> void:
	%TravelProgressPanel.visible = false

## Shared cancel-landing logic — the player is left exactly where they
## currently are on the route, told plainly that they've stopped, and
## the usual standing-trigger check runs in case they happen to have
## stopped right on a city tile.
func _handle_travel_cancel(current_tile: Vector2i, destination_name: String) -> void:
	_travel_cancel_requested = false
	_travel_in_progress = false
	_hide_travel_progress()
	GameState.pending_resume_travel_route = []
	GameState.world_map_player_position = current_tile
	encounter_label_text.text = "You have stopped travelling towards %s." % destination_name
	encounter_label.visible = true
	await get_tree().create_timer(1.5).timeout
	encounter_label.visible = false
	player.grid_pos = current_tile
	player.position = Vector2(current_tile.x * TILE_SIZE, current_tile.y * TILE_SIZE)
	_check_standing_trigger(current_tile)

## Per the request: a genuine, forced choice after every completed
## Stage (8 hours of marching) — camp for the night, or push on and
## risk Fatigue. Returns true if the player chose to keep moving.
func _offer_stage_choice(destination_name: String) -> bool:
	## Per the request ("swap this prompt around, Yes to make Camp, No
	## to Push on. Default on Yes"): [Y]/default is now "Make camp for
	## the night", [N] is "Push on" — see _confirm_prompt_press_yes/no's
	## own comments for the matching _stage_choice_continue swap.
	_start_confirm_prompt("You've marched a full Stage (8 hours) toward %s." % destination_name, "Make camp for the night", "Push on")
	encounter_label.visible = true
	_awaiting_stage_choice = true
	_stage_choice_continue = false
	while _awaiting_stage_choice:
		await get_tree().process_frame
	encounter_label.visible = false
	return _stage_choice_continue

## Per the request: camping right where the party is mid-journey —
## the same real rest effects Camp's own Sleep action already applies
## (full Wounds/Fortune, a Critical Wound day tick, 1 Fatigue stack
## eased, and the World Map's own travel-hour tracking reset), without
## a full scene transition that would lose the in-progress journey.
func _camp_in_place() -> void:
	GameState.advance_minutes(8 * 60)
	var c: Character = GameState.player_character
	c.wounds_current = c.wounds_max
	## Luck (p.??): "your maximum Fortune Points now equal your current
	## Fate points plus the number of times you've taken Luck" — not a
	## separate mechanic, just a bigger cap on the same refresh every
	## character already gets here (see Character.get_max_fortune_points).
	c.fortune_points = c.get_max_fortune_points()
	## See camp_screen.gd's own _on_sleep() comment: same rest-based
	## approximation of p.171's Resolve regen.
	c.resolve = c.resilience
	c.tick_critical_wound_days(1)
	var fatigue_before: int = int(c.conditions.get("Fatigued", 0))
	if fatigue_before > 0:
		if fatigue_before <= 1:
			c.conditions.erase("Fatigued")
		else:
			c.conditions["Fatigued"] = fatigue_before - 1
	## Rattled (per the request "losing a social encounter needs to carry
	## some consequence" — a lingering -10 Test penalty applied to
	## whoever came off worst in a lost Social Combat, see
	## social_encounter_screen.gd's own _resolve_social_combat_loss_
	## consequences()): clears on a proper rest, same lifecycle as
	## Fatigued above, just not stack-counted (see Character.
	## get_condition_test_penalty_breakdown()'s own comment).
	c.conditions.erase("Rattled")
	GameState.world_map_hours_since_rest = 0.0
	GameState.world_map_fatigue_warned_today = false
	GameState.world_map_fatigue_applied_today = false
	GameState.autosave()
	var fatigue_note := " Fatigue eased (%d → %d)." % [fatigue_before, max(0, fatigue_before - 1)] if fatigue_before > 0 else ""
	encounter_label_text.text = "You make camp for the night. Fully rested — Wounds and Fortune Points restored.%s" % fatigue_note
	encounter_label.visible = true
	await get_tree().create_timer(1.8).timeout
	encounter_label.visible = false

## Per the request: finds a real walkable tile adjacent to the given
## center (checking the 8 surrounding tiles), reading directly from a
## LocalMapDefinition's own raw map_rows — used for spawning the
## player next to a city marker rather than directly on top of it,
## on a map that may not even be the one currently loaded. Falls back
## to the center tile itself only if every neighbour is genuinely
## blocked (shouldn't happen given every city marker is generated
## with real cleared ground around it, but a safe fallback regardless).
func _find_adjacent_walkable_tile(map_def: LocalMapDefinition, center: Vector2i) -> Vector2i:
	var neighbors: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
	for offset in neighbors:
		var t := center + offset
		if t.y < 0 or t.y >= map_def.map_rows.size():
			continue
		var row: String = map_def.map_rows[t.y]
		if t.x < 0 or t.x >= row.length():
			continue
		var ch: String = row[t.x]
		if not BLOCKED.has(ch):
			return t
	return center

## Per the request: makes World Map travel genuinely progressive —
## moves the player tile by tile along the actual computed route
## toward that day's stopping point, rather than jumping straight
## there. Deliberately bypasses player._move_to()/the "moved" signal
## chain (which would double up on time/Fatigue, already handled
## per-day by the travel loop itself) — this is visual-only, a fast
## tween per tile.
func _animate_travel_step(target_tile: Vector2i) -> void:
	if player.grid_pos == target_tile:
		return
	var target_pixel := Vector2(target_tile.x * TILE_SIZE, target_tile.y * TILE_SIZE)
	var tween := create_tween()
	tween.tween_property(player, "position", target_pixel, 0.12)
	await tween.finished
	player.grid_pos = target_tile
	%CoordsLabel.text = "(%d, %d)" % [target_tile.x, target_tile.y]
	## Per the request: kept in sync every Stage, not just at journey's
	## end, so a mid-journey autosave (the periodic timer, or camping
	## in place) genuinely captures wherever the player actually is
	## right now rather than stale data from before the trip started.
	if current_map_def != null and current_map_def.is_world_map:
		GameState.world_map_player_position = target_tile

## Walks the player progressively along a real pathfound route toward
## a day's own stopping point, tile by tile, rather than one single
## jump — used by both city travel and plain-tile travel so the whole
## journey genuinely looks like travelling, not teleporting.
func _animate_travel_along_route(route: Array, from_index: int, to_index: int) -> void:
	var start := maxi(from_index, 0)
	var end := mini(to_index, route.size() - 1)
	for i in range(start, end + 1):
		await _animate_travel_step(route[i])

## Picks a tile from the actual pathfound route proportional to how
## far into the journey a given day represents, so the terrain rolled
## for a Wilderness Event genuinely reflects where along the route the
## party actually is that day, not always the start or destination.
func _sample_route_tile(route: Array, day_index: int, total_days: int) -> Vector2i:
	if route.is_empty():
		return player.grid_pos
	var frac: float = float(day_index + 1) / float(max(total_days, 1))
	var idx: int = clampi(int(frac * (route.size() - 1)), 0, route.size() - 1)
	return route[idx]

## Runs one real Wilderness Travel Event, per the request — resolves
## it using whichever of this project's own existing systems actually
## matches the event's own type (a real skill/characteristic Test via
## TestResolver, a real Condition via Character.add_condition, a real
## fight via FieldEncounter, or a real choice via SocialEncounter).
## Returns true if the journey was interrupted (a combat transition
## actually happened, so the caller should stop the day-loop).
func _resolve_wilderness_event(event: Dictionary) -> bool:
	## Per the request: Wilderness Events are now resolved on their
	## own real screen (a full scene transition, matching Social and
	## Field encounters), with genuinely interactive Skill Test
	## buttons rather than an automatic roll — so every event type now
	## interrupts the journey the same way combat already did, since
	## every one of them now involves leaving the World Map scene.
	## Remembers exactly where the player was standing so they land
	## back in the same spot once the encounter resolves.
	GameState.return_position = player.grid_pos
	GameState.pending_wilderness_event = event
	GameState.autosave()
	get_tree().change_scene_to_file("res://scenes/WildernessEncounter.tscn")
	return true

## Resolves either a real Skill Test (if skill_name matches a known
## skill) or a real raw Characteristic Test (if it matches a
## characteristic name instead, e.g. "Strength" for a Quick Mud
## crossing) — the source material mixes both kinds of Test freely.
func _resolve_char_or_skill_test(c: Character, skill_name: String, specialisation: String, difficulty: int) -> bool:
	var char_keys := ["weapon_skill", "ballistic_skill", "strength", "toughness", "initiative", "agility", "dexterity", "intelligence", "willpower", "fellowship"]
	var lname := skill_name.to_lower()
	for key in char_keys:
		if key == lname or key.replace("_", " ") == lname:
			return _tr_char(c, key, difficulty).success
	var skill_def: SkillDefinition = GameData.skill_db.find_by_name(skill_name)
	if skill_def == null:
		return true   ## no matching skill/characteristic found — don't block the player on a data gap
	var result := _tr_skill(c, skill_def, specialisation, difficulty)
	return result.success

## Per the follow-up request: the full Ancient Tomb, Monolith, and
## Ruin tables, built out properly. Barrow rolls directly on the
## Ancient Tomb Table, matching the source's own "See the Ancient
## Tomb Table" instruction; Monolith and Ruin each roll their own
## table first, which can in turn lead into the Ancient Tomb Table.
func _resolve_wilderness_sub_table(event: Dictionary) -> void:
	var sub_type: String = event.get("sub_type", "")
	var text: String = event["text"]
	match sub_type:
		"barrow":
			await _show_wilderness_text(text)
			await _resolve_ancient_tomb()
		"monolith":
			await _show_wilderness_text(text)
			await _resolve_monolith_table()
		"ruin":
			await _show_wilderness_text(text)
			await _resolve_ruin_table()

## The Monolith Table (1d10) — Grave Marker (9) redirects into the
## Ancient Tomb Table; the Orc Totem (10) is a real hostile encounter.
func _resolve_monolith_table() -> void:
	var roll := randi_range(1, 10)
	var entry: Dictionary = {}
	for e in WildernessEvents.MONOLITH_TABLE:
		if roll <= int(e["roll_max"]):
			entry = e
			break
	if entry.get("text", "") == "GRAVE_MARKER":
		await _show_wilderness_text("A nearby, half-hidden entrance suggests this stone marks somebody's grave — and a real tomb besides.")
		await _resolve_ancient_tomb()
		return
	await _show_wilderness_text(str(entry.get("text", "")))
	if entry.get("hostile", false):
		var pool: Array = entry.get("monster_pool", [])
		var monster_names: Array[String] = []
		for m in pool:
			monster_names.append(str(m))
		GameState.pending_encounter_monster_names = monster_names
		GameState.pending_encounter_is_player_ambush = true
		GameState.autosave()
		_capture_battle_terrain_snapshot()
		get_tree().change_scene_to_file("res://scenes/FieldEncounter.tscn")

## The Ruin Table (2d10) — Bandit Camp and Trolls results reference
## the Ancient Tomb Table's own loot column specifically; represented
## here by rolling the full table and using only its loot fields.
func _resolve_ruin_table() -> void:
	var roll := randi_range(1, 10) + randi_range(1, 10)
	var entry: Dictionary = {}
	for e in WildernessEvents.RUIN_TABLE:
		if roll <= int(e["roll_max"]):
			entry = e
			break
	if entry.is_empty():
		entry = WildernessEvents.RUIN_TABLE[-1]
	var text: String = str(entry.get("text", ""))
	if entry.has("loot_gc"):
		var lo: int = entry["loot_gc"][0]
		var hi: int = entry["loot_gc"][1]
		var gc := randi_range(lo, hi)
		GameState.player_character.gold_crowns += gc
		text += "\n\nYou find %d GC worth of coin and trinkets among the debris." % gc
	if entry.get("hostile", false) or (entry.has("hostile_chance") and randf() < float(entry["hostile_chance"])):
		await _show_wilderness_text(text)
		var pool: Array = entry.get("monster_pool", [])
		var monster_names: Array[String] = []
		for m in pool:
			monster_names.append(str(m))
		GameState.pending_encounter_monster_names = monster_names
		GameState.pending_encounter_is_player_ambush = true
		GameState.autosave()
		_capture_battle_terrain_snapshot()
		get_tree().change_scene_to_file("res://scenes/FieldEncounter.tscn")
		return
	if entry.get("social", false):
		var approach := await _show_wilderness_choice(text, "Investigate", "Move on")
		if approach:
			GameState.pending_social_encounter_name = ""
			GameState.pending_social_npc_name = ""
			GameState.pending_social_npc_gender = ""
			GameState.pending_social_situation_index = -1
			GameState.pending_social_opening_flavor_index = -1
			GameState.autosave()
			get_tree().change_scene_to_file("res://scenes/SocialEncounter.tscn")
		return
	await _show_wilderness_text(text)

## The full Ancient Tomb Table (1d10) — finding a buried entrance,
## getting past a locked or barred door, whatever waits inside, real
## loot, and the tomb's own special feature/hazard. "Extended Test"
## mechanics from the source are resolved as a single, appropriately
## harder Test here — see the data file's own note on this.
func _resolve_ancient_tomb(forced_index: int = -1) -> void:
	var c: Character = GameState.player_character
	var roll := forced_index if forced_index >= 0 else randi_range(0, 9)
	var tomb: Dictionary = WildernessEvents.ANCIENT_TOMB_TABLE[roll]
	var text := str(tomb.get("entrance", ""))

	if tomb.has("find_difficulty"):
		var perception_def: SkillDefinition = GameData.skill_db.find_by_name("Perception")
		var found := perception_def != null and _tr_skill(c, perception_def, "", int(tomb["find_difficulty"])).success
		if not found:
			text += "\n\nYou search, but can't turn up the way in."
			await _show_wilderness_text(text)
			return

	var lock_sl: int = int(tomb.get("lock_sl", -1))
	var break_target: int = int(tomb.get("break_target", -1))
	if lock_sl >= 0 or (break_target != -1 and break_target >= -30):
		var got_in := false
		var pick_lock_def: SkillDefinition = GameData.skill_db.find_by_name("Pick Lock")
		if lock_sl >= 0 and pick_lock_def != null and c.has_skill(pick_lock_def):
			got_in = _tr_skill(c, pick_lock_def, "", lock_sl * -2).success
			text += "\n\n" + ("The lock gives way." if got_in else "The lock holds firm.")
		if not got_in and break_target != -1 and break_target >= -30:
			var str_target := c.get_effective_characteristic_value("strength") + break_target
			var break_result := TestResolver.resolve(str_target)
			_log_auto_roll(c, "Strength (Force Door)", break_result)
			got_in = break_result.success
			text += "\n\n" + ("You force your way through." if got_in else "You can't force it open.")
			if not got_in:
				c.add_condition("Fatigued", 1)
		if not got_in:
			await _show_wilderness_text(text + "\n\nWhatever this place holds, it's not giving it up today.")
			return

	var inhabitants: Array = tomb.get("inhabitants", [])
	if not inhabitants.is_empty():
		text += "\n\nSomething's already inside."
		await _show_wilderness_text(text)
		var monster_names: Array[String] = []
		for m in inhabitants:
			monster_names.append(str(m))
		GameState.pending_encounter_monster_names = monster_names
		GameState.pending_encounter_is_player_ambush = true
		GameState.autosave()
		_capture_battle_terrain_snapshot()
		get_tree().change_scene_to_file("res://scenes/FieldEncounter.tscn")
		return

	## Only reached once the tomb is genuinely clear — loot and its
	## own feature/hazard.
	var loot_gc = tomb.get("loot_gc", 0)
	if loot_gc is Array:
		var gc := randi_range(loot_gc[0], loot_gc[1])
		c.gold_crowns += gc
		text += "\n\nInside: %s, worth %d GC." % [str(tomb.get("loot_text", "loot")), gc]
	elif int(loot_gc) > 0:
		c.gold_crowns += int(loot_gc)
		text += "\n\nInside: %s, worth %d GC." % [str(tomb.get("loot_text", "loot")), int(loot_gc)]
	elif str(tomb.get("loot_text", "")) != "":
		text += "\n\nInside: %s." % str(tomb["loot_text"])

	match str(tomb.get("feature", "")):
		"submerged":
			var swim_def: SkillDefinition = GameData.skill_db.find_by_name("Swim") if GameData.skill_db.find_by_name("Swim") != null else null
			var swim_ok := true
			if swim_def != null:
				swim_ok = _tr_skill(c, swim_def, "", -20).success
			if not swim_ok:
				text += "\n\n" + str(tomb.get("feature_text", "")) + " You come up empty-handed and half-drowned."
				c.add_condition("Fatigued", 1)
			else:
				text += "\n\n" + str(tomb.get("feature_text", ""))
		"trap":
			var perc_def: SkillDefinition = GameData.skill_db.find_by_name("Perception")
			var avoided := perc_def != null and _tr_skill(c, perc_def).success
			if not avoided:
				var dmg := Dice.roll_dice_string("1d10")
				c.wounds_current = max(0, c.wounds_current - dmg)
				text += "\n\n" + str(tomb.get("feature_text", "")) + " You're not fast enough (%d Wound(s))." % dmg
			else:
				text += "\n\n" + str(tomb.get("feature_text", "")) + " You spot it in time."
		"mould":
			var lore_def: SkillDefinition = GameData.skill_db.find_by_name("Lore")
			var spotted := lore_def != null and _tr_skill(c, lore_def, "Herbs", 0).success
			if spotted:
				text += "\n\n" + str(tomb.get("feature_text", "")) + " You spot it and steer well clear."
			else:
				var end_def: SkillDefinition = GameData.skill_db.find_by_name("Endurance")
				var resisted := end_def != null and _tr_skill(c, end_def).success
				if not resisted:
					c.add_condition("Blinded", 1)
					var dmg2 := Dice.roll_dice_string("1d5")
					c.wounds_current = max(0, c.wounds_current - dmg2)
					text += "\n\n" + str(tomb.get("feature_text", "")) + " The spores catch you off guard (Blinded, %d Wound(s))." % dmg2
				else:
					text += "\n\n" + str(tomb.get("feature_text", "")) + " You hold your breath and push through unharmed."
		"maze":
			var nav_def: SkillDefinition = GameData.skill_db.find_by_name("Navigation") if GameData.skill_db.find_by_name("Navigation") != null else GameData.skill_db.find_by_name("Outdoor Survival")
			var navigated := nav_def != null and _tr_skill(c, nav_def).success
			if navigated:
				text += "\n\n" + str(tomb.get("feature_text", "")) + " You find your way through without much trouble."
			else:
				c.add_condition("Fatigued", 1)
				text += "\n\n" + str(tomb.get("feature_text", "")) + " You backtrack more than once before finally finding the way."
		"cold":
			var end_def2: SkillDefinition = GameData.skill_db.find_by_name("Endurance")
			var resisted2 := end_def2 != null and _tr_skill(c, end_def2).success
			if not resisted2:
				c.add_condition("Fatigued", 1)
				text += "\n\n" + str(tomb.get("feature_text", "")) + " The cold gets to you before you can leave."
			else:
				text += "\n\n" + str(tomb.get("feature_text", ""))
		"vermin":
			text += "\n\n" + str(tomb.get("feature_text", ""))
			await _show_wilderness_text(text)
			var vermin_names: Array[String] = []
			for m in tomb.get("feature_monsters", []):
				vermin_names.append(str(m))
			GameState.pending_encounter_monster_names = vermin_names
			GameState.pending_encounter_is_player_ambush = true
			GameState.autosave()
			_capture_battle_terrain_snapshot()
			get_tree().change_scene_to_file("res://scenes/FieldEncounter.tscn")
			return
		_:
			if str(tomb.get("feature", "")) != "":
				text += "\n\n" + str(tomb.get("feature_text", ""))

	await _show_wilderness_text(text)


## Shows one Wilderness Event's own text in the same encounter-box UI
## already used for combat/social narrator lines, with a single
## Continue prompt.
func _show_wilderness_text(text: String) -> void:
	encounter_label_text.text = text + "\n\n[Space] Continue"
	encounter_label.visible = true
	_awaiting_wilderness_continue = true
	while _awaiting_wilderness_continue:
		await get_tree().process_frame
	encounter_label.visible = false

## Shows a real Y/N choice for the one Wilderness Event that offers
## one (Fellow Travellers — approach or avoid).
var _awaiting_wilderness_continue: bool = false
var _awaiting_wilderness_choice: bool = false
var _wilderness_choice_result: bool = false
## Per the follow-up ambush-rework request — see _show_ambush_choice()
## and _on_ambush_marker_clicked() above.
var _awaiting_ambush_choice: bool = false
var _ambush_choice_result: bool = false
func _show_wilderness_choice(text: String, yes_label: String, no_label: String) -> bool:
	_start_confirm_prompt(text + "\n", yes_label, no_label)
	encounter_label.visible = true
	_awaiting_wilderness_choice = true
	while _awaiting_wilderness_choice:
		await get_tree().process_frame
	encounter_label.visible = false
	return _wilderness_choice_result

## Per the request: 3 grass atlas variants, alternated across "."
## tiles by position (see _grass_variant_atlas below) so open ground
## doesn't read as one flat repeating texture. Plus 4 shore transition
## tiles (water-on-N/S/E/W-side, grass on the other) — swapped in for
## a "." tile that's orthogonally adjacent to "~" water, so the
## grass/water boundary gets a real rounded, blended edge instead of
## a hard square one.
const GRASS_VARIANT_ATLAS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(34, 0), Vector2i(35, 0), Vector2i(42, 0), Vector2i(43, 0), Vector2i(44, 0)]
## Per the follow-up request ("add variation to the water and mud
## tiles, these should apply to battlemap and overworld tiles"): the
## outdoor mud path ("G") previously always drew the single fixed
## TILE_ATLAS["G"] tile (18, 0) with zero variation, unlike grass's own
## GRASS_VARIANT_ATLAS above. Columns 166/167 are new worn-dirt art
## (footprint/track variants generated to match the existing style —
## see claude/tile_variation_water_mud_v0.3.106.md), picked alongside
## the original the same way GRASS_VARIANT_ATLAS includes its own base
## tile as one of the choices. Deliberately NOT added: the same
## generation batch's wheel-rut variants — a repeat-tile check showed
## obvious vertical banding, so those never made it into tileset.png.
const MUD_VARIANT_ATLAS: Array[Vector2i] = [Vector2i(18, 0), Vector2i(166, 0), Vector2i(167, 0)]
const SHORE_NORTH_ATLAS := Vector2i(36, 0)   ## water above, grass below
const SHORE_SOUTH_ATLAS := Vector2i(37, 0)   ## water below, grass above
const SHORE_EAST_ATLAS := Vector2i(38, 0)    ## water to the right, grass to the left
const SHORE_WEST_ATLAS := Vector2i(39, 0)    ## water to the left, grass to the right
## Per the request ("make the grass to water transition less straight,
## add some variance... but make sure they match up"): a long straight
## shoreline repeats the SAME single tile over and over, so however
## wavy that one tile's own edge is, the shore as a whole still reads
## as a perfectly periodic — and therefore visually "straight" —
## repeating pattern. Fixed with 2 extra wavy variants per direction
## (picked at random per-tile below), each generated with the shore
## boundary perturbed by a sine wave that's windowed to exactly zero
## right at the tile's own edges (see water_shore_rework_v2.py-style
## generation notes) — so column 0/63 (for N/S) or row 0/63 (for E/W)
## always lands on the same unperturbed boundary depth every variant
## shares, which is also exactly what the corner/three/isolated
## pieces below use unperturbed. That's what guarantees any mix of
## variants tiles seamlessly with itself, with each other, and with
## every other shore piece, while the tile's own interior is free to
## bulge differently — confirmed with a direct seam-check render
## before shipping.
## Per the follow-up request: hand-crafted variants generated with
## Claude in Chrome + Gemini (not the procedural band/blur pipeline) —
## real painted detail (rocks/reeds/a sandy shoal) sitting right at the
## waterline. Composited so the tile's own outer edges exactly match
## the plain SHORE_*_ATLAS baseline (guaranteeing seamless tiling with
## the baseline, with the procedural wavy variants, and with a copy of
## themselves) and fade into the real grass/water textures at the two
## non-tiling edges — only the interior band shows the hand-painted art.
const SHORE_NORTH_ATLAS_VARIANTS: Array[Vector2i] = [SHORE_NORTH_ATLAS, Vector2i(121, 0), Vector2i(125, 0), Vector2i(129, 0), Vector2i(130, 0), Vector2i(131, 0)]
const SHORE_SOUTH_ATLAS_VARIANTS: Array[Vector2i] = [SHORE_SOUTH_ATLAS, Vector2i(122, 0), Vector2i(126, 0), Vector2i(132, 0)]
const SHORE_EAST_ATLAS_VARIANTS: Array[Vector2i] = [SHORE_EAST_ATLAS, Vector2i(123, 0), Vector2i(127, 0), Vector2i(133, 0)]
const SHORE_WEST_ATLAS_VARIANTS: Array[Vector2i] = [SHORE_WEST_ATLAS, Vector2i(124, 0), Vector2i(128, 0), Vector2i(134, 0)]
## Per the request: real corner pieces for where the coastline turns
## a corner (water on two adjacent sides at once) — the previous
## straight-edge-only system left one of the two water-facing sides
## with no transition at all, which is the "missing edging" the
## request described.
const SHORE_CORNER_NE_ATLAS := Vector2i(49, 0)   ## water above AND to the right
const SHORE_CORNER_NW_ATLAS := Vector2i(50, 0)   ## water above AND to the left
const SHORE_CORNER_SE_ATLAS := Vector2i(51, 0)   ## water below AND to the right
const SHORE_CORNER_SW_ATLAS := Vector2i(52, 0)   ## water below AND to the left
## Per the request: a real, rounded transition where grass meets the
## mud path ("G"), the same idea as the water shore edges above but
## for mud instead of water.
const MUD_SHORE_NORTH_ATLAS := Vector2i(45, 0)   ## mud above, grass below
const MUD_SHORE_SOUTH_ATLAS := Vector2i(46, 0)   ## mud below, grass above
const MUD_SHORE_EAST_ATLAS := Vector2i(47, 0)    ## mud to the right, grass to the left
const MUD_SHORE_WEST_ATLAS := Vector2i(48, 0)    ## mud to the left, grass to the right
## Hand-painted mud-shore variants (Claude in Chrome + Gemini, same
## edge-pinning composite technique as the water shore variants above):
## two additional grass-tuft/wildflower variations per direction,
## derived from two Gemini-generated north-edge tiles by rotating the
## source art 90/180/270 degrees (the boundary art has no directional
## bias, so rotation carries the detail cleanly to every edge) and then
## re-compositing each rotation against that direction's own baseline
## tile so every edge still tiles seamlessly.
const MUD_SHORE_NORTH_ATLAS_VARIANTS: Array[Vector2i] = [MUD_SHORE_NORTH_ATLAS, Vector2i(135, 0), Vector2i(139, 0)]
const MUD_SHORE_SOUTH_ATLAS_VARIANTS: Array[Vector2i] = [MUD_SHORE_SOUTH_ATLAS, Vector2i(136, 0), Vector2i(140, 0)]
const MUD_SHORE_EAST_ATLAS_VARIANTS: Array[Vector2i] = [MUD_SHORE_EAST_ATLAS, Vector2i(137, 0), Vector2i(141, 0)]
const MUD_SHORE_WEST_ATLAS_VARIANTS: Array[Vector2i] = [MUD_SHORE_WEST_ATLAS, Vector2i(138, 0), Vector2i(142, 0)]
## Per the request: mud gets the same corner treatment water already
## has — both the two-orthogonal-sides case and the diagonal-only
## case, since the mud path turning a corner with no rounding at all
## was the reported "hacked off" look.
const MUD_SHORE_CORNER_NE_ATLAS := Vector2i(53, 0)
const MUD_SHORE_CORNER_NW_ATLAS := Vector2i(54, 0)
const MUD_SHORE_CORNER_SE_ATLAS := Vector2i(55, 0)
const MUD_SHORE_CORNER_SW_ATLAS := Vector2i(56, 0)
## Per the request: a full rework of shore transitions. The previous
## system only properly handled 0, 1, or 2-adjacent water/mud
## neighbors — a cell with water on 3 sides, or on 2 OPPOSITE sides
## (a narrow isthmus), or fully isolated (water on all 4 sides), fell
## through to whichever 2-sided corner check happened to match first,
## which looked wrong (too much grass showing) exactly where a
## winding diagonal coastline packs these configurations together.
const WATER_THREE_N_ATLAS := Vector2i(58, 0)   ## water on S,E,W — only the north side remains grass
const WATER_THREE_S_ATLAS := Vector2i(59, 0)
const WATER_THREE_E_ATLAS := Vector2i(60, 0)
const WATER_THREE_W_ATLAS := Vector2i(61, 0)
const WATER_ISOLATED_ATLAS := Vector2i(62, 0)     ## water on all 4 orthogonal sides
const WATER_ISTHMUS_NS_ATLAS := Vector2i(63, 0)   ## water N and S — grass strip runs east-west
const WATER_ISTHMUS_EW_ATLAS := Vector2i(64, 0)   ## water E and W — grass strip runs north-south
const MUD_THREE_N_ATLAS := Vector2i(65, 0)
const MUD_THREE_S_ATLAS := Vector2i(66, 0)
const MUD_THREE_E_ATLAS := Vector2i(67, 0)
const MUD_THREE_W_ATLAS := Vector2i(68, 0)
const MUD_ISOLATED_ATLAS := Vector2i(69, 0)
const MUD_ISTHMUS_NS_ATLAS := Vector2i(70, 0)
const MUD_ISTHMUS_EW_ATLAS := Vector2i(71, 0)
## Per the request: the diagonal-only case (water/mud touching a
## grass cell at just one corner point, no orthogonal contact at all)
## was reusing the same large-notch corner art built for the full
## 2-adjacent-orthogonal-side case — visually too aggressive for a
## genuinely subtler situation, producing an oversized, blocky
## "overspill" bulge exactly where the request pointed it out. These
## are dedicated, much smaller notch pieces for that specific case.
const WATER_DIAG_NE_ATLAS := Vector2i(72, 0)
const WATER_DIAG_NW_ATLAS := Vector2i(73, 0)
const WATER_DIAG_SE_ATLAS := Vector2i(74, 0)
const WATER_DIAG_SW_ATLAS := Vector2i(75, 0)
const MUD_DIAG_NE_ATLAS := Vector2i(76, 0)
const MUD_DIAG_NW_ATLAS := Vector2i(77, 0)
const MUD_DIAG_SE_ATLAS := Vector2i(78, 0)
const MUD_DIAG_SW_ATLAS := Vector2i(79, 0)
## Per the request: water darkens the further it is from any shore.
## A hard 2-tier (shallow/deep) system produced visible rectangular
## "blocks" with an abrupt edge between them — smoothed into a 3-tier
## gradient instead: shallow (touches shore directly), medium (one
## ring further out), deep (two or more rings from any shore).
const DEEP_WATER_ATLAS := Vector2i(41, 0)
const MEDIUM_WATER_ATLAS := Vector2i(57, 0)
## Per the follow-up request ("add variation to the water and mud
## tiles"): shallow water (the ring directly touching shore) previously
## always drew the single fixed TILE_ATLAS["~"] tile (2, 0). Columns
## 163-165 are new calm-water art matching the existing painterly blue-
## teal style — see claude/tile_variation_water_mud_v0.3.106.md — picked
## alongside the original tile the same way MUD_VARIANT_ATLAS above
## does. Medium/deep water stay single fixed tiles (their darker,
## flatter colour reads fine without variation, and they're usually far
## enough from the camera/small enough on-screen that it wouldn't be
## noticed anyway). A generated circular swirl/whirlpool variant was
## deliberately left out of the atlas — tiled across open water it reads
## as an obviously repeating spiral, per the same repeat-tile check that
## dropped the mud rut variants.
const SHALLOW_WATER_VARIANT_ATLAS: Array[Vector2i] = [Vector2i(2, 0), Vector2i(163, 0), Vector2i(164, 0), Vector2i(165, 0)]

## Per the report: a "T" tree cell sitting next to a "G" mud path cell
## rendered as a hard rectangular seam, since _resolve_tile_atlas()
## returned TILE_ATLAS["T"] unconditionally for any non-grass ch,
## skipping the whole shore/mud-edge system entirely (that system only
## ever ran for plain "." / "," grass cells). These 8 tiles are the
## tree cell's own grass background blended into the mud path texture
## right at whichever edge(s) genuinely border a "G" cell — same thin,
## edge-anchored band technique as the water/grass shore rework, just
## 2-way (tree tile -> mud) instead of 3-way, and deliberately only
## the single-edge + adjacent-corner cases (a tree bordered by mud on
## 3+ sides, or diagonally only, is rare enough in practice that it
## just falls back to the plain tree tile below rather than needing
## its own dedicated art).
##
## Per the follow-up report ("tree tops overlapping mud tiles should
## display the mud behind them and not extend the grass tile"): once
## the canopy started spilling into neighboring tiles (see
## TREE_OVERLAY_ANCHOR_PX below), these 8 ground tiles no longer
## composite any tree cutout at all — they're pixel-identical to the
## corresponding plain-grass MUD_SHORE_*/MUD_SHORE_CORNER_* blend
## tiles. Baking a small in-tile tree into the ground here (sized and
## anchored independently from the overlay sprite) was exactly the
## kind of ground/overlay mismatch v0.2.574 already fixed once for
## shadows — the overlay is now the sole source of visible tree art
## everywhere, ground tiles included, so it can never drift out of
## sync with itself again. TILE_ATLAS["T"] (col 3) is likewise now
## just plain grass, identical to TILE_ATLAS["."].
const TREE_MUD_NORTH_ATLAS := Vector2i(113, 0)
const TREE_MUD_SOUTH_ATLAS := Vector2i(114, 0)
const TREE_MUD_EAST_ATLAS := Vector2i(115, 0)
const TREE_MUD_WEST_ATLAS := Vector2i(116, 0)
const TREE_MUD_CORNER_NE_ATLAS := Vector2i(117, 0)
const TREE_MUD_CORNER_NW_ATLAS := Vector2i(118, 0)
const TREE_MUD_CORNER_SE_ATLAS := Vector2i(119, 0)
const TREE_MUD_CORNER_SW_ATLAS := Vector2i(120, 0)

const TILE_ATLAS := {
	".": Vector2i(0, 0), "P": Vector2i(1, 0), "~": Vector2i(2, 0),
	"T": Vector2i(3, 0), "#": Vector2i(4, 0), ",": Vector2i(5, 0),
	"M": Vector2i(6, 0),
	## Per the request: a warm, timber-framed house wall — visually
	## distinct from the cold grey mountain/fort wall tile ("#") — and
	## a small stone well, for the village's own new central square.
	"B": Vector2i(7, 0), "W": Vector2i(8, 0),
	## Per the follow-up request: a richer interior tileset — three
	## new floor types, a real stone wall distinct from "B"'s timber
	## frame, a plain wooden interior wall, and basic furniture
	## (table, chair, bed, cupboard) for building actual room interiors.
	"F": Vector2i(9, 0),    ## paved floor (stone flags)
	"D": Vector2i(10, 0),   ## bordered floor (ornamental trim)
	"U": Vector2i(11, 0),   ## mud floor
	"K": Vector2i(12, 0),   ## stone wall
	"O": Vector2i(13, 0),   ## wooden wall
	"C": Vector2i(14, 0),   ## table
	"R": Vector2i(15, 0),   ## chair
	"E": Vector2i(16, 0),   ## bed
	"V": Vector2i(17, 0),   ## cupboard
	## Per the second follow-up request: an outdoor mud path, tilled
	## farmland, a rail fence, a plain gate, a matching fence gate, and
	## a wider, worn road — all distinct from the existing indoor floor
	## tiles and the plain dirt path.
	"G": Vector2i(18, 0),   ## mud path (outdoor)
	"A": Vector2i(19, 0),   ## farmer's field
	## Per the "fences running north to south need to be turned so they
	## connect correctly" request: this is the DEFAULT/horizontal-run
	## orientation only — an isolated or east/west-adjacent fence tile.
	## A north/south run, or a corner where a run bends 90 degrees,
	## resolves to one of the FENCE_*_ATLAS constants below instead —
	## see _resolve_fence_atlas(), called from _build_map() in place of
	## this raw TILE_ATLAS entry for every "I" cell.
	"I": Vector2i(20, 0),   ## fence (horizontal run / isolated / fallback)
	"J": Vector2i(21, 0),   ## gate
	"L": Vector2i(22, 0),   ## fence gate
	"Q": Vector2i(23, 0),   ## road
	"X": Vector2i(144, 0),   ## wooden bridge fallback (see _resolve_bridge_atlas() for the real per-cell piece)
	"Z": Vector2i(25, 0),   ## village location marker (World Map only)
	## Per the follow-up request: a snowy northeast region trailing
	## toward Kislev, on the World Map only. Lowercase since every
	## uppercase letter is already spoken for.
	"s": Vector2i(26, 0),   ## snow-covered ground
	"f": Vector2i(27, 0),   ## frosted/snowy evergreen tree
	## Per the request: building front facades (a door + small window),
	## for the front-facing wall of a building rather than a plain,
	## featureless wall tile there. Lowercase since every uppercase
	## letter is already spoken for.
	"w": Vector2i(29, 0),   ## wood/timber building front
	"r": Vector2i(30, 0),   ## stone building front
	## Per the request: a distinct marker for major cities — a
	## fortified wall with a gate and battlements, a central
	## watchtower, and multiple rooftops behind the wall, rather than
	## the plain village marker's own small, unwalled house cluster.
	"c": Vector2i(31, 0),   ## major city location marker (World Map only)
	## Per the request: a real, distinct standing-stone tile for the
	## Red Ogham stone circle east of Gotheim, per the source material
	## — a short, squat monolith with carved notches, rather than the
	## generic dirt-patch tile it stood in for previously.
	"o": Vector2i(32, 0),   ## Red Ogham standing stone
	## Per the request: the flood that follows the levee breaking —
	## deliberately walkable, unlike the game's own normal deep-water
	## tile, since the party still needs to move through the
	## devastated, flooded village.
	"v": Vector2i(33, 0),   ## floodwater (walkable)
	## Per the follow-up request: a province border marker — a dashed
	## line drawn over plain grass, purely visual (walkable, same as
	## any road/path — a real border never blocks travel).
	"b": Vector2i(28, 0),
	## Per the request: an actual door tile for the gap already left in
	## a building's front wall row (previously just plain ground, no
	## door art at all) — a wood-framed dark opening, "usually open"
	## per the request, so it's deliberately walkable like any ordinary
	## floor tile rather than a closed obstacle. Newly-painted tiles
	## appended to the end of the tileset image, since every existing
	## atlas slot was already spoken for.
	"d": Vector2i(89, 0),   ## door (open)
	## Per the request: real growing-crop art for the village's farm
	## fields — visually distinct from "A"'s plain tilled dirt (which
	## has no plants on it at all) — a corn field (green stalks, golden
	## ears) and a barley field (dense golden stalks). Lowercase, same
	## reason as every other tile added since the original 26-letter
	## alphabet filled up. Newly-painted tiles appended to the end of
	## the tileset image, same pattern as the door/roof tiles.
	"z": Vector2i(92, 0),   ## corn field (growing crop)
	"k": Vector2i(93, 0),   ## barley field (growing crop)
	## Per the Gotheim rework request: a distinct chapel/church facade
	## (stone front with a pointed-arch window and a small cross above
	## it) — used to flank a church building's own door, in place of
	## the plain stone building front ("r"), so a church actually reads
	## as a church rather than just a bigger generic stone building.
	## Structurally treated exactly like "r" (see BUILDING_CHARS/
	## WALL_MATERIAL_CHARS/SHADOW_CASTING_CHARS/BLOCKED below) — this is
	## purely a different facade texture on the same kind of wall tile.
	"h": Vector2i(94, 0),   ## chapel front (church facade)
	## Per the same request: aftermath-of-attack set dressing — broken
	## planks/rubble scattered on the ground, and a large monster's
	## clawed tracks — both purely decorative ground tiles (walkable,
	## not shadow-casting, not building material), same category as
	## "," or the crop tiles above.
	"e": Vector2i(95, 0),   ## debris / rubble
	"g": Vector2i(96, 0),   ## large monster claw tracks
	## Per the request: a real outdoor cobblestone path connecting the
	## village's houses to each other — irregular worn stone blocks
	## with grass tufts at the edges, deliberately distinct from "F"'s
	## clean, evenly-gridded INDOOR paved floor. Purely decorative
	## ground dressing (walkable, not shadow-casting, not building
	## material), same category as "," or the crop tiles above.
	"p": Vector2i(98, 0),   ## outdoor cobblestone path
	## Per the request ("all house interiors tiles should have matching
	## crafted floor ie wood/stone"): a real wood-plank interior floor,
	## laid per-building (see _paint_building_interiors() in
	## _build_map()) for every wood-walled building — stone-walled
	## buildings (church, smithy) reuse the existing "F" paved floor
	## instead, rather than needing a second new stone tile.
	## Per the later "rework floor tiles" building request: this atlas
	## slot's own pixel content was replaced (same column, col105) with
	## a clean, hand-painted (Gemini) horizontal-plank floor — the
	## original placeholder here was a busy, dark, wall-like texture
	## that barely read as a floor at all, and was never actually
	## reworked in the first building-rework pass despite that pass's
	## own new wall tiles (WALL_WOOD_*_ATLAS above) being built to
	## blend into it. Same swap for "F" below (col9, paved stone floor).
	"n": Vector2i(105, 0),   ## wood-plank interior floor
	## Per the request ("make the shop and smithy buildings more
	## distinct from the outside"): dedicated facades — a hanging shop
	## sign + barrel over the general store's own timber front, and a
	## glowing forge window + anvil silhouette over the smithy's own
	## stone front — replacing the plain "w"/"r" facade tiles that
	## flanked each one's door before. Structurally identical to "h"
	## (the chapel front) everywhere else (BUILDING_CHARS/
	## WALL_MATERIAL_CHARS/SHADOW_CASTING_CHARS/BLOCKED) — purely a
	## different facade texture on the same kind of wall tile.
	"m": Vector2i(106, 0),   ## shop front (general store facade)
	"u": Vector2i(107, 0),   ## smithy front (forge facade)
	## Per the "add 2 static lamps in the village" request: a standalone
	## street lamp post, structurally the same kind of small solid
	## decorative object as "W" (the well) — always drawn (day and
	## night), with the actual "turns on at night" behaviour handled by
	## a separate glow overlay sprite (see LAMP_GLOW_TEXTURE /
	## static_lamp_coords / _rebuild_shadows()) rather than a second
	## atlas variant, and its own secondary-shadow casting handled by
	## _apply_static_lamp_secondary_shadows() rather than the primary
	## sun/moon system (see STATIC_LAMP_CHAR's own comment for why it's
	## deliberately left out of SHADOW_CASTING_CHARS, same as "W").
	## Lowercase "l" — uppercase "L" was already taken (the fence gate).
	"l": Vector2i(157, 0),
	## Per the Giessingen Goblin Fort rework request: close the fort's old
	## plain stone-wall block off into a real palisade perimeter (new
	## tiles, no auto-roof), add a front gate that leads into a new
	## Goblin Fort Dungeon instead of the old in-place chest tile, and a
	## few greenskin tents inside. New chars since every letter A-Z is
	## already spoken for (uppercase) or taken (most of lowercase) —
	## "a"/"j"/"t" were the first free lowercase letters left.
	## Deliberately excluded from WALL_MATERIAL_CHARS (see that constant's
	## own comment) so the fort's closed ring never flood-fills into
	## _compute_buildings() and grows an auto-roof over its own interior
	## — same reasoning as the village's "I" fence. Still fully solid:
	## see BLOCKED/LIGHT_BLOCKING_WALL_CHARS/SHADOW_CASTING_CHARS below.
	"a": Vector2i(158, 0),   ## palisade wall (Goblin Fort perimeter)
	## Fort gate — a walkable trigger tile (see _check_standing_trigger())
	## that offers to enter the Goblin Fort Dungeon, same pattern as the
	## Rat Catcher's Guild sewer entrance. Not in BLOCKED (it's the one
	## opening in the wall), not a shadow-caster (an opening, not a
	## silhouette — same reasoning as the "d" door).
	"j": Vector2i(159, 0),   ## Goblin Fort gate (dungeon entrance)
	## Greenskin tent — a small solid decorative object inside the fort,
	## structurally like "W" (the well) or "l" (the lamp): blocks
	## movement and casts a shadow, but isn't wall material/doesn't
	## contribute to any building footprint.
	"t": Vector2i(160, 0),   ## greenskin tent
	## Per the Giessingen NE Cave rework request: the old furnished
	## "cave" house is replaced with a real extension of the mountain
	## range — a rocky cliff-face texture (distinct from "M"'s
	## grassy/treed mountain-top look) that reads as the foot of the
	## mountain rather than its silhouette from above. Deliberately
	## given the exact same terrain role as "M" (BLOCKED only — not a
	## building wall, not a light-blocker, not a shadow-caster) rather
	## than treated like "w"/"r" building fronts, since it's dressing
	## on impassable mountain terrain, not a structure. Lowercase "i" —
	## the next free letter (every uppercase already spoken for).
	"i": Vector2i(161, 0),   ## rock face (NE Cave mountain extension)
	## Cave entrance — a walkable trigger tile (see
	## _check_standing_trigger()) that offers to enter the new Cave
	## Dungeon, same pattern as the Goblin Fort gate ("j") and the Rat
	## Catcher's Guild sewer entrance. Not in BLOCKED (it's the one
	## opening in the rock face), not a shadow-caster (an opening, not
	## a silhouette — same reasoning as "j"/"d").
	"y": Vector2i(162, 0),   ## Cave Dungeon entrance
	"@": Vector2i(1, 0), "N": Vector2i(1, 0), "H": Vector2i(1, 0), "S": Vector2i(1, 0), "Y": Vector2i(1, 0),
}
## Per the "remove the flat bridge, make it look like a real wooden
## bridge" request: replaces the old single flat repeating-plank tile
## (which had no rails or structure) with a proper multi-piece bridge —
## hand-painted via Claude in Chrome + Gemini, generated as one
## continuous strip (landing, deck, landing) so the pieces are
## guaranteed to line up, then sliced and edge-blended (see the
## v0.2.585 compose script): the middle deck tile was made to tile
## seamlessly with itself, and each landing's outer edge blends into
## the real grass tile while its inner edge is pinned to match the
## middle tile's own edge exactly.
## Only a horizontal bridge exists on the current map, but
## _resolve_bridge_atlas() below supports either orientation — the
## vertical pieces are just the horizontal art rotated 90 degrees
## (a plank deck with post-and-rail sides has no directional bias),
## so a future north/south bridge needs no new art.
const BRIDGE_H_MIDDLE_ATLAS := Vector2i(144, 0)   ## deck over water, tiles left/right
const BRIDGE_H_WEST_END_ATLAS := Vector2i(143, 0)  ## deck meets grass to the west
const BRIDGE_H_EAST_END_ATLAS := Vector2i(145, 0)  ## deck meets grass to the east
const BRIDGE_V_MIDDLE_ATLAS := Vector2i(147, 0)   ## deck over water, tiles up/down
const BRIDGE_V_NORTH_END_ATLAS := Vector2i(146, 0) ## deck meets grass to the north
const BRIDGE_V_SOUTH_END_ATLAS := Vector2i(148, 0) ## deck meets grass to the south
## Per the "fences running north to south need to be turned so they
## connect correctly, with corner tiles to change the angle" request:
## the fence's own art (rail + posts) reads correctly only for a run
## going east/west — the original "I" atlas tile above — so a run going
## north/south, or a 90-degree bend between the two, needs genuinely
## different art rather than reusing the same tile at an odd angle.
## FENCE_VERTICAL_ATLAS is bespoke art, NOT the horizontal tile rotated
## 90 degrees (an earlier version of this comment claimed it was — that
## was checked directly against the real pixels during the fence-shadow
## work and found false; see the handoff doc's fence-shadow section for
## how that was confirmed): a thin single rail spanning the tile's full
## height, rather than a mirror of the horizontal tile's two-rail
## cross-section. Its thick post-cap accent originally sat at BOTH the
## top and bottom of the tile, symmetric — per the direct "change the
## vertical fences to match the north leaning style like everything
## else" request, it's now asymmetric like every other tall element in
## this game (a roof's ridge/peak sits at the tile's north edge with the
## low eave at the south edge; the straight horizontal fence's own posts
## plant their foot at the south edge and taper to nothing at the north
## edge): the accent now only sits at the SOUTH (bottom) edge — the
## post's foot — while the north (top) edge is just the plain thin rail,
## tapering away the same way everything else's "far" edge does.
## The four corner tiles originally shipped with only ONE of the two
## lateral rail bands drawn (a simpler single-band "L" with a solid post
## at the bend) — per the direct "the lower lateral bar is missing, same
## in all corners" report, all four now carry BOTH bands, at the exact
## same row position the straight horizontal tile uses (rows 4-6 and
## 10-12), so a corner tile lines up seamlessly with a straight tile
## placed next to it and reads as the same fence structure continuing
## through the bend rather than thinning out at the joint. A follow-up
## request ("add a post in each corner") also added a proper post marker
## (matching the straight tile's own post color and edge spacing,
## cols 1-2/13-14) to the OUTER edge of each corner's horizontal arm —
## previously that arm was a plain uninterrupted rail with no post where
## it meets the next straight tile, unlike every straight-to-straight
## tile boundary elsewhere along a fence run.
const FENCE_VERTICAL_ATLAS := Vector2i(108, 0)
const FENCE_CORNER_NE_ATLAS := Vector2i(109, 0)   ## connects a run to the north and one to the east
const FENCE_CORNER_NW_ATLAS := Vector2i(110, 0)   ## connects a run to the north and one to the west
const FENCE_CORNER_SE_ATLAS := Vector2i(111, 0)   ## connects a run to the south and one to the east
const FENCE_CORNER_SW_ATLAS := Vector2i(112, 0)   ## connects a run to the south and one to the west
## Per the follow-up request: real top-down pixel art reads as facing
## a fixed direction (north, away from the viewer) rather than a flat
## texture shot from directly overhead — a roof is the clearest place
## that matters, since a uniform tile in every row just looks like a
## textured floor from above, not a sloped roof. Three variants instead
## of one: the NORTH edge of a building's footprint (the back, however
## far from the camera/door that ends up being) gets the lighter ridge
## cap, the SOUTH edge (nearest the wall/door row the player actually
## walks up to) gets the darker eave with its own overhang trim line,
## and everything between gets the plain shingled body. See
## roof_layer/_roof_atlas_for_row() and _compute_buildings() below —
## none of this is a map_rows character, since which tiles need a roof
## (and which row of it they are) is entirely derived from where the
## walls already are, rather than needing every map hand-annotated.
const ROOF_RIDGE_ATLAS := Vector2i(90, 0)   ## north edge — the roof's peak
const ROOF_BODY_ATLAS := Vector2i(88, 0)    ## the sloped surface between
const ROOF_EAVE_ATLAS := Vector2i(91, 0)    ## south edge — overhangs the wall
## Per the request ("all builds should have slight variations"): two
## more (ridge, body, eave) sets, palette-shifted from the original
## terracotta-clay roof — a desaturated blue-grey slate, and a warmer
## brown wood-shingle — so not every roof on the map reads as the same
## building repeated. Picked per building (see _roof_variant_for()) by
## a fixed, deterministic index rather than true randomness, so the
## same map always looks the same way twice. Index 0 is always the
## original atlas above; 1 and 2 are these.
const ROOF_RIDGE_VARIANTS := [Vector2i(90, 0), Vector2i(99, 0), Vector2i(102, 0)]
const ROOF_BODY_VARIANTS := [Vector2i(88, 0), Vector2i(100, 0), Vector2i(103, 0)]
const ROOF_EAVE_VARIANTS := [Vector2i(91, 0), Vector2i(101, 0), Vector2i(104, 0)]
## Per the request ("new front wall tiles (wood/stone)... rework floor
## tiles and make sure floor stretches to the wall edges inside the
## house"), refined by two direct follow-up corrections after the first
## pass looked wrong in-game:
##  - First pass gave every orientation a ~50/50 wall/floor split using
##    bespoke Gemini-painted "floor," which didn't match the real "n"/"F"
##    floor tiles at all (those still used old placeholder art at the
##    time — see the floor-tile-replacement note on TILE_ATLAS["n"]/
##    ["F"] below).
##  - Per "side wall should only show a very thin line of wall along the
##    outer edge and the rest should be floor boards, match the rest
##    floorboard tiles too": WEST/EAST are now built procedurally —
##    the real floor tile ("n"/"F", now itself reworked, see above) as
##    the base, with a genuinely thin strip (7 of 64px) of the real wall
##    texture ("B"/"K", unchanged) composited at the tile's own true
##    outer edge (left for WEST, right for EAST) and lightly feathered
##    in — so the floor portion is pixel-identical to the real interior
##    floor, and the wall is just a thin edge accent, not a redesigned
##    texture.
##  - Per "front and back walls should not include the floor boards,
##    only wall": NORTH/FRONT are plain, full-tile copies of the real
##    wall texture ("B"/"K") — no floor blend at all. Front and back
##    walls need to read as a genuinely solid, unbroken wall face
##    (that's also the edge is_walkable() actually blocks on — see the
##    is_walkable() comment below), so unlike the side walls they get
##    no floor accent.
## _resolve_wall_atlas() (below) picks the right one per cell purely
## from its position in _compute_buildings()'s own bounding rect — same
## as before, only the art at these 8 atlas columns changed.
## Deliberately does NOT touch "O" (interior partition wall, only when
## it's not sitting on the building's own outer rect edge — see
## _resolve_wall_atlas()'s own fallback), "#" (falls back to the same
## fallback when it's not part of a real building footprint at all —
## e.g. a standalone fort/mountain wall segment on the World Map), or
## the chapel/shop/smithy unique fronts ("h"/"m"/"u") — those three keep
## their own bespoke facade art unconditionally, no floor-bleed variant.
const WALL_WOOD_NORTH_ATLAS := Vector2i(149, 0)
const WALL_WOOD_FRONT_ATLAS := Vector2i(150, 0)
const WALL_WOOD_WEST_ATLAS := Vector2i(151, 0)
const WALL_WOOD_EAST_ATLAS := Vector2i(152, 0)
const WALL_STONE_NORTH_ATLAS := Vector2i(153, 0)
const WALL_STONE_FRONT_ATLAS := Vector2i(154, 0)
const WALL_STONE_WEST_ATLAS := Vector2i(155, 0)
const WALL_STONE_EAST_ATLAS := Vector2i(156, 0)
## Which map characters get the new floor-bleed wall art at all — every
## OTHER WALL_MATERIAL_CHARS entry ("h"/"m"/"u") keeps its own unique
## facade texture untouched. Wood family: "B" (timber exterior wall),
## "w" (timber front facade), "O" (interior wooden partition). Stone
## family: "K" (stone exterior wall), "r" (stone front facade), "#"
## (the older grey fort/mountain wall material, wherever it happens to
## be part of a real building footprint).
const WALL_RESOLVED_WOOD_CHARS: Array[String] = ["B", "w", "O"]
const WALL_RESOLVED_STONE_CHARS: Array[String] = ["K", "r", "#"]
## Per the Gotheim rework request ("make the houses look like what they
## are, ie church etc."): a small bell-tower silhouette baked into a
## ridge-cap-sized tile, painted over the single center-most cell of a
## church's own ridge row (see building_is_chapel/_build_map() below) —
## the one row-tall cell budget this rectangular roof system has to
## spend on "this building is special," reusing the same ridge-row
## atlas mechanism every other building's roof already uses.
const STEEPLE_ROOF_ATLAS := Vector2i(97, 0)
## Trees ("T") are deliberately NOT blocked anymore — they're walkable
## at a movement penalty instead (see Player._move_to and is_tree()
## below). Mountains ("M") take over as the map's impassable border.
## Per the follow-up request: the new stone/wooden walls and every
## piece of furniture (table, chair, bed, cupboard) block movement,
## same as any other solid wall or obstacle — the new floor types
## (paved/bordered/mud) are plain walkable ground, same as grass/path.
## Per the second follow-up request: the fence blocks movement, same
## as any solid boundary — both gate types are real, deliberate
## openings and stay walkable, same as the mud path, field, and road.
## Per the door/roof request: "d" (the new door tile) is deliberately
## left OUT of this list — an open door is exactly as walkable as the
## plain-ground gap it replaced.
## Per the Goblin Fort rework: "a" (palisade wall) and "t" (greenskin
## tent) both block movement — the palisade closes the fort's perimeter,
## the tent is a solid camp object. "j" (the fort gate) is deliberately
## absent — it's the one walkable opening in the wall.
## Per the NE Cave rework: "i" (rock face) blocks movement exactly like
## "M" (mountain) — it's mountain terrain dressing, not a building. "y"
## (the cave entrance) is deliberately absent, same reasoning as "j".
const BLOCKED := ["M", "#", "~", "B", "W", "K", "O", "C", "R", "E", "V", "I", "w", "r", "o", "h", "m", "u", "l", "a", "t", "i"]
## Per the "add 2 static lamps" request: the character a static lamp
## post is painted with in map_rows — a single, shared constant instead
## of a bare "l" literal scattered across every list it needs to join,
## since a lamp genuinely participates in several unrelated systems
## (blocks movement, receives shadows from other lights, casts its own
## secondary shadows once lit). Lowercase "l" — uppercase "L" was
## already taken (the fence gate). Deliberately left OUT of
## SHADOW_CASTING_CHARS — same as "W" (the well) — a small standalone
## object like this was never given a primary sun/moon shadow; adding
## one now would be a bigger, unrelated visual change nobody asked for.
const STATIC_LAMP_CHAR := "l"
const ENCOUNTER_TILES := ["."]
const ENCOUNTER_CHANCE := 0.12

## Per the request: which map layer each character's tile is written
## to in _build_map() — see water_layer/building_layer above. Anything
## not listed in either falls through to the ground layer (the
## default/largest group: grass, paths, floors, furniture, fences,
## the well, trees, etc.). Deliberately narrow on purpose:
## - WATER_CHARS is just "~" (the river) — floodwater ("v") is a
##   distinct, simpler hazard tile that never goes through the "~"
##   shore-blending logic in _resolve_tile_atlas, so it stays on the
##   ground layer rather than being folded in here.
## - BUILDING_CHARS is walls + building front facades, PLUS the new
##   door tile ("d") — matches the tiles that already cast shadows
##   (walls/fronts only — see SHADOW_CASTING_CHARS, which deliberately
##   does NOT include "d": an open doorway is a gap, not a silhouette)
##   plus the obvious building-face tiles — furniture, fences/gates,
##   and the well stay on the ground layer for now.
## - "I" (fence) is a special case handled inline in _build_map()'s own
##   tile loop, NOT via this constant — its art is mostly transparent
##   (just posts + a rail), so it needs a real grass tile painted onto
##   the ground layer underneath it (same deterministic variant an
##   ordinary "." cell there would get) before its own art is drawn on
##   the building layer on top, or its transparent gaps show the raw
##   viewport clear color instead of blending with the grass around it.
##   Every other BUILDING_CHARS tile is fully opaque, so it never needed
##   this — see the "Per the 'blend better...' request" comment there.
const WATER_CHARS: Array[String] = ["~"]
## NPC spawn-trigger letters (see _spawn_npc/_spawn_shopkeeper/
## _spawn_priest, called from _build_map()'s first pass) that overload
## the map's own character grid purely as a spawn signal — TILE_ATLAS
## still had to map each one to *something* (Vector2i(1,0), the plain
## bare-path tile), so before this fix every one of these spawn points
## rendered as an isolated, mismatched patch of bare path/dirt no
## matter what actually surrounded it (grass outdoors, a room's own
## crafted wood/stone floor indoors). See
## _natural_ground_char_for_npc_marker() and its use in _build_map()'s
## own ground-painting pass.
##
## RECURRENCE NOTE: this exact fix first shipped as v0.3.45 (that
## version's own doc has the full writeup), but was lost at some point
## afterward — this function/constant were simply absent from the live
## file when the "NPCs in houses are still standing on mud tiles"
## follow-up report came in, meaning the ground-painting pass had
## silently fallen back to painting these markers with the raw
## TILE_ATLAS lookup again. Restored here verbatim, this time with "@"
## (the player's own start tile — the identical Vector2i(1,0) mapping,
## previously left out of scope on the reasoning that nobody had
## reported it) folded into the same fix, closing that known loose end
## too rather than leaving a second latent copy of the same bug.
const NPC_MARKER_CHARS: Array[String] = ["@", "N", "H", "S", "Y"]
## Per the Gotheim rework request: "h" (chapel front) joins "w"/"r" as
## just another building-facade texture — same layer, same shadow, same
## flood-fill treatment as an ordinary stone building front.
## Per the Goblin Fort rework: "a" (palisade wall) and "j" (its gate)
## join the layer, same as any other opaque wall/door pair — both tiles
## are fully opaque, same as every other entry here, so neither needs
## the fence's own transparent-underlay special case. "t" (tent) is
## deliberately NOT here — it's a small freestanding solid object,
## treated like "W" (the well): painted on the ground layer instead.
const BUILDING_CHARS: Array[String] = ["B", "K", "O", "#", "w", "r", "d", "h", "m", "u", "a", "j"]
## Per the request: which wall/front characters actually count as solid
## "wall material" when grouping a map's buildings into footprint rects
## for the roof layer (see _compute_buildings()) — every BUILDING_CHARS
## entry EXCEPT the door, since a door tile is an opening in the wall,
## not part of it, and including it would let two separate buildings
## that happen to share a door-adjacent tile falsely merge into one.
## Deliberately does NOT include "I" (fence) — per the Gotheim rework
## request, the village's perimeter is a fence, not a building, so it
## must never flood-fill into the buildings array (that's exactly what
## caused the old "one giant roof over the entire village" bug: the
## village's outer wall used to be built from "#", which IS wall
## material, and its own unbroken ring was one single connected
## component whose bounding box covered nearly the whole village).
## Per the Goblin Fort rework, "a" (palisade) is the exact same case as
## "I" above — its own closed ring must never flood-fill into
## _compute_buildings() and grow an auto-roof over the fort's interior,
## which is precisely the "no roof" the request asked for. "j" (its
## gate) stays out for the same reason "d" (door) does.
const WALL_MATERIAL_CHARS: Array[String] = ["B", "K", "O", "#", "w", "r", "h", "m", "u"]
## Per the "also treat walls with doors like normal walls for the
## purpose of shadows" follow-up: == WALL_MATERIAL_CHARS + "d". The
## PRIMARY sun/moon shadow silhouette already treats a door exactly like
## the wall around it (SHADOW_CASTING_CHARS includes "d", and its own
## wall-run merge at line ~5319 keys off that same list) — but the
## SECONDARY torch/lamp system's own line-of-sight check
## (_has_line_of_sight()) and its two wall-run merge collectors
## (_apply_light_source_secondary_shadows()/_apply_static_lamp_secondary_
## shadows(), both gated on "ch in WALL_MATERIAL_CHARS") still keyed off
## plain WALL_MATERIAL_CHARS, which deliberately EXCLUDES "d" (see its
## own comment — an open doorway shouldn't fracture a building's
## footprint into two). That exclusion is exactly right for footprint/
## roof detection, but it meant a torch or lamp could see clean THROUGH
## a closed door as if it were a window, and a door tile drew its own
## little standalone blob shadow instead of merging into the wall run's
## solid silhouette either side of it. This constant exists so shadow/
## LOS call sites can opt into "door counts as solid" without touching
## WALL_MATERIAL_CHARS itself (which every footprint/walkability call
## site still needs unchanged).
## Per the Goblin Fort rework: "a" (palisade) joins the plain wall
## chars here (it's excluded from WALL_MATERIAL_CHARS only to dodge
## roof flood-fill — see that constant's comment — it's still meant to
## be a real, LOS-blocking wall). "j" (its gate) joins for the same
## reason "d" (door) does: a torch/lamp shouldn't see straight through
## the one gap in the wall into the fort's interior.
const LIGHT_BLOCKING_WALL_CHARS: Array[String] = ["B", "K", "O", "#", "w", "r", "h", "m", "u", "d", "a", "j"]

## Combat Encounter rework (per the request): snapshots passability for
## the 3x3 field tiles centered on the player's own current position
## into GameState.pending_battle_terrain, right before FieldEncounter.
## tscn's own scene change destroys this Overworld instance — see that
## field's own comment in game_state.gd for the exact 9-entry layout.
## Reads from `tile_chars` (the actually-displayed character per tile,
## including runtime overrides like the Gotheim flood's "v" tiles) via
## _build_map()'s own populated dictionary, rather than re-deriving from
## current_map_def.map_rows directly, so a flooded/otherwise-modified
## map hands the battle grid the terrain the player can actually see,
## not the map's original static data. A tile with no entry in
## tile_chars at all (off the edge of the map) is treated as impassable
## — there's no ground there to stand a square on.
##
## Combat Encounter rework, Phase 2: also captures a parallel cover
## snapshot into GameState.pending_battle_cover, true wherever the tile
## is forest ("T"/"f") — the same tile chars Overworld already treats
## as forest for travel purposes (see _terrain_category), reused here
## purely for the woodland cover they'd obviously provide against
## ranged attacks. Per the request, cover-vs-ranged only for this
## phase — no difficult-ground movement cost, no elevation.
func _capture_battle_terrain_snapshot() -> void:
	var snapshot: Array = []
	var cover_snapshot: Array = []
	## Per the follow-up request ("fill this in with the same tiles as
	## overworld water rather then Grey tiles"): a third snapshot, true
	## only for the WATER subset of `snapshot`'s own impassable tiles (see
	## its own declaration comment in game_state.gd) — BattleGrid needs to
	## tell a water block apart from a building block to know which one
	## gets real water art instead of the old plain wall colour.
	var water_snapshot: Array = []
	snapshot.resize(9)
	cover_snapshot.resize(9)
	water_snapshot.resize(9)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var tile: Vector2i = player.grid_pos + Vector2i(dx, dy)
			var idx: int = (dy + 1) * 3 + (dx + 1)
			if not tile_chars.has(tile):
				snapshot[idx] = true
				cover_snapshot[idx] = false
				water_snapshot[idx] = false
				continue
			var ch: String = tile_chars[tile]
			snapshot[idx] = (ch in WATER_CHARS) or (ch in BUILDING_CHARS)
			cover_snapshot[idx] = ch in ["T", "f"]
			water_snapshot[idx] = ch in WATER_CHARS
	GameState.pending_battle_terrain = snapshot
	GameState.pending_battle_cover = cover_snapshot
	GameState.pending_battle_water = water_snapshot
	## Per the day/night & light-source-in-combat request: captured here,
	## the single shared hand-off point every field-encounter trigger in
	## this file already routes through right before change_scene_to_file
	## — see GameState.pending_battle_is_dark's own comment for why this
	## can't just be read directly from FieldEncounter.tscn.
	GameState.pending_battle_is_dark = GameState.get_night_darkness() > 0.0 or (current_map_def != null and current_map_def.is_dark_location)
	GameState.pending_battle_is_pitch_black = current_map_def != null and current_map_def.is_dark_location

const NPC_SCENE_TEXTURE := preload("res://assets/sprites/npc.png")
## The Goblin Fort's lootable chest used to be a hand-placed overworld
## tile here (GOBLIN_FORT_CHEST_TILE) — per the Goblin Fort Dungeon
## rework, it now lives inside the fort's own Dungeon Map instead (see
## field_encounter_screen.gd's chest functions), reached through the
## gate tile ("j") rather than clicked directly on the world map.
var _radial_menu_target_lore_tile: Vector2i = Vector2i(-1, -1)
const CHARACTER_MENU_SCENE := preload("res://scenes/CharacterMenu.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/PauseMenu.tscn")
const SWITCH_CHARACTER_TAB_INDEX := 7   ## Stats, Equipment, Inventory, Spellbook, Career, Group, Journal, Switch Character

## Per the request ("use the new portraits in all Icon, in and out of
## combat"): the old class-specific, wound-tier PORTRAIT_SETS table that
## used to live here is gone — every portrait on this screen now comes
## from CareerPortraits (scripts/core/career_portraits.gd), keyed by the
## Character's specific Career rather than career_class, with no
## wound-based swap since there's one image per Career. See
## _refresh_party_panel() below.

## Per the request: real map layers instead of every tile sharing one
## TileMapLayer. Water sits BEHIND the ground (z_index -1); buildings/
## walls sit IN FRONT of it. The ground itself is no longer a single
## fixed layer — per the follow-up request, it's a DYNAMIC array of
## TileMapLayers, one per distinct elevation actually used on the
## current map (see LocalMapDefinition.elevation_overrides and
## ground_layers below), instantiated fresh each time _build_map()
## runs rather than fixed scene nodes. This is prep for a future
## stairs mechanic (a raised platform/terrace can already sit above
## the base ground level; a bridge tile on the ground layer over a
## water-layer tile at the same coords works the same way). z_index
## values are computed, not hardcoded: ground layer i = z_index i,
## shadows/tree-canopy sit just above the TOPMOST ground layer
## (whatever that turns out to be for this map), and buildings sit one
## higher still — see _build_map()'s call to _rebuild_ground_layers().
## water_layer and building_layer stay real fixed scene nodes (their
## z_index is still assigned dynamically in code, just not their
## existence) — only the ground tier itself needed to become dynamic.
@onready var water_layer: TileMapLayer = $WaterLayer
@onready var building_layer: TileMapLayer = $BuildingLayer
## Per the door/roof request: a real roof layer, one z_index above
## building_layer — every building's own footprint (walls + interior,
## see _compute_buildings()) gets covered in roof tiles so you can no
## longer see straight down into a house's furniture from outside.
## Fixed scene node, same pattern as water_layer/building_layer — only
## its z_index is assigned dynamically (see _rebuild_ground_layers()).
@onready var roof_layer: TileMapLayer = $RoofLayer
## Per the "still bleeding through at the edges" thread's real root
## cause (see _build_map()'s own roof-painting comment): ROOF_RIDGE's
## own atlas art is deliberately taller than one tile cell (so the
## ridge reads as rising above the flat 2D grid), and that overflow
## quietly paints into the row(s) of ground just past a building's own
## back wall — invisible under ordinary night darkness, but exposed the
## instant a nearby light's reveal thins that darkness right there.
## v0.2.608 through v0.2.610 all tried to patch this by forcing the
## LIGHTING system to redarken that spot back to true ambient — first
## with a hand-picked rectangle (straight edges fighting the light's own
## circular falloff), then with a circular scan around every light
## (which instead drew a visible ring at the "genuinely lit" cutoff
## radius, since that band is SUPPOSED to still show the shader's own
## smooth partial reveal, not get force-flattened to full black). Both
## were solving the wrong layer of the problem: the actual bug is
## purely visual (roof art bleeding where it shouldn't), so the actual
## fix is purely visual too — repaint the real ground/canopy tile that
## belongs in the overflow band on TOP of the roof layer, plain ordinary
## world content just like roof_layer itself, so the EXISTING lighting
## pipeline (already correct everywhere else) just does its normal job
## on it with no special-casing needed at all. Same scene-node pattern
## as roof_layer; only its z_index is assigned dynamically (see
## _rebuild_ground_layers()), one above roof_layer's own so it draws on
## top and actually masks the bleed.
@onready var roof_overflow_mask_layer: TileMapLayer = $RoofOverflowMaskLayer
## The ground layer, one TileMapLayer per elevation actually present
## on the current map (index 0 = base ground level). Built fresh by
## _rebuild_ground_layers() every time _build_map() runs. `tile_map`
## is kept as an alias for ground_layers[0] — the base ground layer —
## since the rest of this file only ever uses it for coordinate math
## (map_to_local, tile_set.tile_size) that's identical across every
## ground layer regardless of elevation, never for anything
## elevation-specific.
var ground_layers: Array[TileMapLayer] = []
var tile_map: TileMapLayer = null
## Per the request: real map layers now compute their own z_index
## based on however many ground elevation layers a given map actually
## needs, rather than a fixed number — this is the shared "definitely
## above every ground layer and every shadow, safe for anything that
## should always render on top" z_index, recomputed by
## _rebuild_ground_layers() each time the map (re)builds. Used for the
## Player and every NPC/marker sprite spawned directly onto the map —
## deliberately kept above roof_layer too, so the player's own sprite
## always pokes out above a roof rather than disappearing under it.
var above_buildings_z: int = 6
## Per the door/roof request: every building on the current map, as a
## tile-grid Rect2i covering its full wall+interior footprint — see
## _compute_buildings(), called fresh each time _build_map() runs.
## Index into this array is what player_inside_building (below) tracks.
var buildings: Array[Rect2i] = []
## Which entry in `buildings` the player is currently standing inside,
## or -1 when outside every building. Drives _update_roof_visibility()
## — the specific building the player just entered/left is the only
## one whose roof cells actually get touched, not a full roof rebuild.
var player_inside_building: int = -1
## Per the "add 2 static lamps in the village" request: every STATIC_LAMP_CHAR
## ("l") tile on the current map, populated fresh in _build_map()'s own
## first tile_chars pass (same spot "@"/"N"/"H"/"S"/"Y" are picked out of
## that same loop) — the fixed, always-on-the-map counterpart to
## `player.grid_pos` that _apply_static_lamp_secondary_shadows() sweeps
## shadows from, and that _rebuild_shadows()/_update_shadow_angles() use
## to place and fade each lamp's own glow sprite.
var static_lamp_coords: Array[Vector2i] = []
## Per the request: "inside houses it should always be shady" — one
## dim overlay Polygon2D per building, index-aligned with `buildings`
## above, covering exactly the same roofed-rows footprint the roof
## itself uses (see _roof_row_count()). Hidden by default (every
## building starts with its roof shown, nobody indoors yet) and
## toggled together with the roof in _set_building_roof_visible() —
## visible exactly when that building's roof is hidden, i.e. exactly
## while the player is the one standing inside it. Deliberately NOT
## tied to time-of-day/`shadow_container.visible` the way the outdoor
## wall shadows are — indoors should read as dim at every hour, not
## just while the sun's out casting shadows outside.
var indoor_shade_polygons: Array[Polygon2D] = []
## Per the Gotheim rework request ("make the houses look like what they
## are, ie church etc."): index-aligned with `buildings`, true for the
## one building whose own footprint contains a chapel-front ("h") tile
## — computed once in _build_map() (see _building_contains_char()) and
## read both there (to paint the steeple's roof-cap override) and in
## _set_building_roof_visible() (so the steeple survives every later
## enter/exit roof repaint, not just the first one).
var building_is_chapel: Array[bool] = []
## Per the request ("all builds should have slight variations"):
## index-aligned with `buildings`, the roof-palette variant (0/1/2 —
## see ROOF_BODY_VARIANTS/_roof_variant_for()) this building was
## assigned when the map was built. Computed once in _build_map() and
## read both there and in _set_building_roof_visible(), same pattern
## as building_is_chapel — a repaint on enter/exit must reuse the same
## variant, not re-roll it, or a building's roof colour would visibly
## flicker between materials every time the player walked in and out.
var building_roof_variant: Array[int] = []
const MAP_TILESET := preload("res://resources/tileset.tres")
## Per the request: a second, transparent layer for extra diagonal
## shore/mud notches a cell's own base tile can't show by itself —
## see _resolve_shore_overlay_atlas() and the scene's own comment.
## Only ever decorates GROUND cells ("." / ","), never water/building
## ones (see _resolve_shore_overlay_atlas), so it stays paired with
## the base ground layer's own z_index.
@onready var shore_overlay_layer: TileMapLayer = $ShoreOverlayLayer
## Per the request: a gfx shadow system for tall objects — trees and
## walls — that visibly change angle across the day. Each qualifying
## map cell gets one Sprite2D child here, repositioned/rotated as
## time passes rather than pre-rendered per-tile art, since the
## shadow's own angle needs to sweep smoothly, not jump between a
## handful of fixed positions.
@onready var shadow_container: Node2D = $ShadowContainer
## Per the request: no tree's shadow — its own or a neighbour's —
## should ever visually cover a real tree's canopy. The per-shadow
## clip shader only ever knew about its OWN tree's canopy position;
## it had no way to know where every OTHER tree on the map was. This
## overlay solves it generally instead: redraws every tree's own real
## canopy pixels on a layer above ALL shadows, so whichever shadow
## happens to reach into that space, the actual canopy always paints
## back over it.
@onready var tree_canopy_overlay: Node2D = $TreeCanopyOverlay
const TREE_CANOPY_OVERLAY_TEXTURE := preload("res://assets/fx/tree_canopy_overlay.png")
## Per the request: the shadow's own shape now matches the object
## casting it — a real tree silhouette (canopy + trunk/roots, derived
## from the actual tree sprite's own alpha channel) for trees, and a
## rectangular block for walls, rather than one generic blob for
## everything.
const SHADOW_TEXTURE_TREE := preload("res://assets/fx/shadow_tree.png")
const SHADOW_CLIP_SHADER := preload("res://assets/fx/shadow_clip.gdshader")
## Per the request: an animated, patchy cloud-shadow overlay drifting
## across the whole map, adapted from a GodotShaders.com reference (see
## the shader file's own header comment for the link/attribution) —
## applied full-screen via CloudShadowOverlay ($UI/CloudShadowOverlay),
## the same "ColorRect in the UI CanvasLayer" pattern NightOverlay
## already uses, just with a noise-masked alpha instead of a flat one.
const CLOUD_SHADOW_SHADER := preload("res://assets/fx/cloud_shadow_overlay.gdshader")
## Per the follow-up request's light-source system: punches a soft
## radial "hole" through NightOverlay's own darkness tint, centered on
## the player, sized to their equipped light source's radius — see the
## shader file's own header comment. Attached to $UI/NightOverlay
## lazily, the first time _apply_light_source_overlay() runs (same
## lazy-attach convention _maybe_reseed_cloud_shadow_overlay() already
## uses for CLOUD_SHADOW_SHADER above).
const NIGHT_OVERLAY_LIGHT_SHADER := preload("res://assets/fx/night_overlay_light.gdshader")
## Per the request: measured and visually verified directly against
## the actual tree/shadow art — the trunk's visual MIDDLE, not its
## bottom tip (which the previous build used and still read as
## slightly misaligned).
## Per the TILE_SIZE 16->64 upscale: this and every other _PX / row-band
## constant below it in this file were measured against the old
## 16px-native fx art (shadow_tree.png, shadow_person.png,
## shadow_wall.png, fence_shadow_source.png, tree_canopy_overlay.png).
## Those fx images were 4x-nearest-neighbour-upscaled alongside
## tileset.png so the pixels they measure are unchanged, just bigger —
## so each constant is simply scaled by FX_SCALE here rather than
## re-measured.
const FX_SCALE := 4.0
## Per "leave NPCs for now": every Player/NPC body sprite (16x16 native,
## same as the old tile size) stays unregenerated art, scaled up on the
## node itself to match the new bigger tile grid — a shared constant
## since every NPC sprite is the same native size.
const NPC_SPRITE_SCALE := FX_SCALE
## Per the follow-up request: "the shadows are a bit too big for the
## size of the tree, and there's a silhouette of the old tree sprite
## remaining which is never touched by the shadow." SHADOW_TEXTURE_TREE
## used to be its own independent, generic "rounded blob with a stem"
## silhouette, authored once, long before any of the tree repaints —
## every later tree-art change (v0.2.570 new tree, v0.2.572/573 size
## passes) left it untouched, so it drifted further from the actual
## tree's own real silhouette each time, to the point that its edges
## visibly no longer matched the lobed canopy shape at all (reading as
## a leftover ghost of some earlier tree). Fixed the way this project's
## fence shadows already do it (see FENCE_TILESET_TEXTURE's own
## comment: "the shadow is always the literal same pixels as the real
## fence tile it's shadowing") — shadow_tree.png is a direct recolor of
## the tree's own real alpha matte (tree_canopy_overlay.png), not a
## separate hand-authored shape, so it can never again drift out of
## sync with whatever the tree currently looks like. Baked to
## WALL_SHADOW_COLOR's own dark tone (matching every other shadow in
## the game) at alpha 150.
##
## Per the further follow-up ("let the canopy visually spread into
## neighboring tiles"): a single 64x64 TileMapLayer cell is a hard
## physical ceiling on how big any ground-tile-baked tree art could
## ever look, but the canopy OVERLAY is just a Sprite2D, not a tile —
## nothing stops it from being bigger than 64x64 and overlapping
## neighboring cells, the same way this overlay already sits happily
## on top of THIS tile's own shadows and ground art regardless of tile
## boundaries. tree_canopy_overlay.png and shadow_tree.png are now
## both a 2x-scaled (relative to the same 64px-tile reference frame
## every other tree measurement in this file uses), 128x128 render of
## the tree's own cutout, scaled outward from its own trunk-base
## anchor point — since there's no 64x64 box to stay inside anymore,
## the canopy is simply free to grow upward and sideways past the
## tile's own edges. TREE_OVERLAY_ANCHOR_PX is that trunk-base point's
## own pixel position within the new bigger canvas (used as both the
## overlay sprite's and the shadow's offset, since they're the same
## image); TREE_SHADOW_PIVOT_PX is kept as its own separate constant
## (rather than reusing TREE_OVERLAY_ANCHOR_PX by name) only so every
## other shadow-specific call site here keeps reading the same way it
## always has.
##
## Per the report right after this shipped ("tree tops overlapping mud
## tiles should display the mud behind them and not extend the grass
## tile"): the ground tile (TILE_ATLAS["T"], col 3) used to bake its
## OWN small in-tile tree cutout, sized/anchored independently from
## this overlay (anchored near the canopy's own top, to dodge the
## v0.2.573 clipping bug, rather than at the trunk base like the
## overlay above) — so once the overlay grew past the ground tile's
## own bounds, the two tree shapes no longer lined up, leaving slivers
## of the ground's own smaller tree (and the grass/mud blend it sat
## on) exposed around the bigger overlay. Fixed by never baking a tree
## into the ground tile at all: TILE_ATLAS["T"] is now pixel-identical
## to TILE_ATLAS["."] (plain grass), and the TREE_MUD_* tiles below are
## pixel-identical to the corresponding plain-grass MUD_SHORE_* blend
## tiles — the overlay sprite is the only place a tree is ever drawn,
## so ground and overlay can't drift apart again.
## Per the report ("remove the grass completely, like this [reference
## image]"): the painterly hand-cutout tree (circles fitted over the
## original grass+tree composite art) kept reading as mottled/grassy no
## matter how the alpha edge was cleaned up, because the contamination
## was in the opaque interior, not just the edge. Replaced with a
## proper cutout of the tree artwork the user provided directly —
## keyed off its flat grey checkerboard "transparent" background
## (every background/soft-shadow pixel there is neutral grey, R≈G≈B;
## every real tree pixel — green foliage, brown trunk/roots — is not,
## so a simple per-pixel channel-spread threshold separates them
## cleanly), resized to match this shipped canopy's own previous
## width, and re-anchored at its own trunk-base point.
## Per the follow-up request (10% smaller, and remove the stray white
## "sparkle" pixels the reference art had scattered right at the
## canopy's sunlit rim — visible as isolated white flecks against the
## transparent background instead of blending into the foliage):
## the sparkle pixels were re-keyed out of the source cutout (found
## via the same near-grayscale/high-brightness test used to key the
## original background, restricted to within ~18px of the tree's own
## edge — that's where all of them turned out to sit — then in-painted
## from their nearest non-sparkle foliage neighbor) and the whole
## cutout was re-fit to the canvas at 90% of the previous width.
## Per the further follow-up (another 10% smaller, and more white
## pixels still visible): the edge-only sparkle pass above wasn't
## enough — some flecks sat further into the canopy than 18px, and a
## few pure-white ones apparently needed a bigger local-median window
## to register as outliers than the first pass used. Replaced with a
## proper local-contrast detector (an opaque pixel whose brightness
## sits well above its own 9x9-median-filtered neighborhood, with low
## color saturation, is a sparkle regardless of where in the canopy it
## sits) unioned with a flat "near-pure-white" absolute check, then a
## second identical pass run on the final placed/resized canvas itself
## (resampling can reintroduce a few bright edge pixels even from
## already-cleaned source art) — confirmed zero pixels matching either
## test anywhere in the shipped texture. Re-measured directly from
## this new art's own alpha mask, same as every previous resize.
const TREE_OVERLAY_ANCHOR_PX := Vector2(64.0, 121.0)
const TREE_SHADOW_PIVOT_PX := TREE_OVERLAY_ANCHOR_PX
const TREE_CANOPY_CLIP_PX := 10.5
## Per the request: the actual trunk's visual middle within the
## 16x16 tree tile itself, measured and visually verified directly.
## Re-measured for the reworked tree art (v0.2.571/572, tree_canopy_
## overlay.png replaced and then enlarged) — re-derived from the
## current tile's own brown trunk pixels each time rather than left
## pointing at a previous build's trunk position. Still describes the
## GROUND TILE's own (64x64-constrained) art specifically — the bigger
## canopy overlay above uses its own TREE_OVERLAY_ANCHOR_PX instead,
## since it's a separately-scaled asset — but both are meant to mark
## the same real-world "trunk planted here" point, so the overlay
## sprite is positioned using this same constant (see its own creation
## code) to keep the two lined up.
const TREE_TILE_BASE_PX := Vector2(8.0, 12.3) * FX_SCALE
const SHADOW_TEXTURE_WALL := preload("res://assets/fx/shadow_wall.png")
## Fence shadows, attempt #7 — re-added per direct request, after six
## earlier designs (independent per-tile sprites, merged wall-run-style
## flat fills, hand-picked rail/post rects, a whole-tile shader shear,
## a translate+hull+clip sweep, a per-rect translation, and finally a
## per-rect shear) were all tried and abandoned/reverted across two
## prior sessions — see the "WFRP 8bit" project's own
## `reikland_chronicles_handoff.md` for the full history, and the
## fence_shadow_silhouette.gdshader file's own comment for why this
## attempt is deliberately the simplest of the lot: a pixel-exact
## silhouette (real texture alpha as a mask, so picket gaps stay gaps)
## that only ever TRANSLATES as a whole shape — no shear, no per-vertex
## anchoring, no rect decomposition. The fence's own art changed
## completely since the last attempt too (the picket-lattice style from
## v0.2.242/243, not the old log-rail tiles every earlier design was
## built against), so there's no salvageable geometry from before
## regardless. FENCE_TILESET_TEXTURE is the same tileset.png the
## TileMapLayer atlas itself draws from, loaded here as a plain
## Texture2D so a Sprite2D can crop out exactly the same 16x16 region
## _resolve_fence_atlas() picked for the real tile, via region_rect —
## the shadow is always the literal same pixels as the real fence tile
## it's shadowing, just recolored.
const FENCE_TILESET_TEXTURE := preload("res://assets/tiles/tileset.png")
const FENCE_SHADOW_SHADER := preload("res://assets/fx/fence_shadow_silhouette.gdshader")
## v0.2.248 fix, per direct request with a reference photo: "the shadow
## needs to emanate from the bottom row of the fence tile, not pivot
## around a single point." v0.2.245-247 all rotated the WHOLE fence
## tile rigidly around one fixed pivot pixel — correct for a single
## POINT object (why it worked fine for a lone vertical post) but wrong
## for anything with width, since rotating a rigid shape around one
## point swings every OTHER point along an arc rather than sliding it
## straight out along the ground. That's what made the straight-run
## tiles look like they were "pivoting" instead of genuinely emanating
## from their own base row.
##
## The physically correct fix — never move the base row, shift every
## row above it sideways-and-down proportional to its own height above
## that row — is mathematically just a SHEAR. A first attempt at this
## did it as a custom per-pixel-row resample in
## fence_shadow_silhouette.gdshader's fragment function (which needed a
## deliberately padded source texture, since a sheared shape needs room
## to spill outside the tile's own 16x16 box, unlike a rotated one) —
## that hit an unresolved Godot rendering bug in the region_rect/scale
## pipeline itself (reproduced even with the custom shader stripped
## down to plain sampling), so it was abandoned. A shear, unlike a
## per-pixel-row resample, is a plain LINEAR transform — it doesn't need
## a fragment shader at all. It's now done as a Transform2D set directly
## on each shadow's Sprite2D node in _update_shadow_angles(), the exact
## same mechanism (a node transform) that already drives every other
## shadow's rotation/scale in this file. FENCE_SHADOW_SOURCE_TEXTURE is
## back to its real, unpadded 16x16-per-cell size — a node-transform
## shear moves the whole drawn quad, so there's nothing to clip against
## and no padding is needed.
##
## v0.2.249 fix, per direct request: "the lateral beams are missing in
## the shadow of the horizontal fence tiles." fence_shadow_source.png's
## straight-run and 4 corner cells (everything except the single-post
## vertical cell) had been hand-trimmed at some point in this asset's
## history to drop the horizontal rail pixels that touch each cell's
## left/right edge — keeping only the short connector notches between
## a cell's own posts. That's invisible on a single isolated tile, but
## once adjacent fence tiles' shadows sit side by side it means the
## rail shadow breaks at every tile seam instead of reading as one
## continuous band, same as the real fence's rails do. Confirmed via a
## pixel-mask diff against the real tile art: the straight-run cell was
## missing 40 opaque pixels and each corner cell 20, all of them right
## at the cell edges; the vertical cell (no edge-touching rails to
## begin with) matched exactly. Fixed by regenerating all 6 cells
## directly from FENCE_TILESET_TEXTURE's own real fence pixels (the
## same tileset.png region _resolve_fence_atlas() picks for the actual
## tile) instead of the old hand-trimmed source — which is what this
## texture's own pixel-exact-silhouette design already intended (see
## fence_shadow_silhouette.gdshader's comment), so this is a return to
## that intent rather than a new design.
const FENCE_SHADOW_SOURCE_TEXTURE := preload("res://assets/fx/fence_shadow_source.png")
## Real, unpadded per-cell size in FENCE_SHADOW_SOURCE_TEXTURE — matches
## the real fence tile's own 16x16 footprint exactly.
const FENCE_SHADOW_CELL_SIZE_PX := Vector2(16.0, 16.0) * FX_SCALE
## The fence tile's own ground-contact point, in a single cell's local
## pixel space (shared by both the real tileset.png tile and this
## shadow-only texture's own cells, which are cropped from the same
## rail-free art at the same size) — used both to compute where in
## WORLD space each shadow sprite's node origin sits
## (fence_tile_topleft_px + this) and, via shadow.offset, to make that
## exact pixel always render at the node's own local origin. Since the
## node's local origin is also the shear transform's own fixed point
## (see _update_shadow_angles()), this is the one pixel that's
## guaranteed to never move no matter what the sun is doing — the
## fence's own real base.
const FENCE_SHADOW_WORLD_ANCHOR_PX := Vector2(8.0, 16.0) * FX_SCALE
## v0.2.251: row bands (inclusive, [start, end]) for the vertical-run
## atlas's 3 post "knots" — matches the row ranges the v0.2.250 art fix
## drew them at in both tileset.png and FENCE_SHADOW_SOURCE_TEXTURE's
## own vertical cell. Used to split that one atlas cell's shadow into 3
## independently-anchored Sprite2D pieces in _rebuild_shadows() (see the
## v0.2.251 comment there) instead of shearing the whole 16-row cell as
## one rigid block.
const FENCE_VERTICAL_POST_ROW_BANDS: Array[Vector2i] = [Vector2i(0, 2) * 4, Vector2i(6, 8) * 4, Vector2i(12, 14) * 4]
## v0.2.252 fix, per direct request: "make the vertical fence post
## shadows a bit thinner." Each post piece's own shadow silhouette is
## as wide as the real post knot's own art (4px, cols 6-9 within its
## crop) — sheared per-row but never narrowed, so the diagonal band
## reads as fairly thick/solid. Scaling the per-piece transform's own
## x_axis by this factor (applied only to vertical-run post pieces —
## see the `shear_height_px` meta check in _update_shadow_angles())
## narrows the drawn quad horizontally around its own local origin
## (which sits at the post's own horizontal center, matching where the
## real post's own art is centered), without touching region_rect,
## offset, or the shear itself.
const FENCE_VERTICAL_POST_SHADOW_WIDTH_SCALE := 0.6
## RECONSTRUCTED after a session filesystem reversion wiped the working
## tree back to its v0.2.252 state — restored from this Project's own
## `claude/reikland_chronicles_v256_v257_addendum.md` doc (the
## established "Project doc is the reliable source of truth" recovery
## workflow, used repeatedly earlier in this same saga). v0.2.256
## through v0.2.258's own intermediate architecture (per-tile shared
## shear anchor for rail-gap-row pieces) was fully superseded by
## v0.2.259's translation-based rail — reconstructing straight to the
## v0.2.265 end state rather than replaying now-dead intermediate code.
##
## v0.2.259: the vertical-run atlas's own rail column (cols 7-8, the
## thin line connecting each post knot) needs a constant TRANSLATION,
## not a per-row/per-tile SHEAR, to stay continuous across tile
## boundaries — a shear's displacement depends on row position, and
## every tile's own row-to-world mapping differs the moment tiles
## stack top-to-bottom, so adjacent tiles' shears disagree right at
## the shared boundary. A translation has no such boundary to disagree
## at. v0.2.260 split the single rail line into two (matching the
## horizontal atlas's own double rail-band look); v0.2.261 tuned line
## A's ratio down so it aligns better where a straight tile meets a
## corner.
const FENCE_VERTICAL_RAIL_COLUMN_START_PX := 7.0 * FX_SCALE
const FENCE_VERTICAL_RAIL_COLUMN_WIDTH_PX := 2.0 * FX_SCALE
const FENCE_VERTICAL_RAIL_LINE_WIDTH_PX := FENCE_VERTICAL_RAIL_COLUMN_WIDTH_PX / 2.0
const FENCE_VERTICAL_RAIL_SHADOW_RATIO_A := 0.2
const FENCE_VERTICAL_RAIL_SHADOW_RATIO_B := 0.85
## Fallback default only — every real rail piece always sets its own
## `fence_rail_ratio` meta (see the rail-piece creation loop below), so
## this should never actually be read in practice.
const FENCE_VERTICAL_RAIL_SHADOW_RATIO := 0.6
## v0.2.263: NE/NW corner tiles (the enclosure's bottom two corners,
## where a vertical run terminates) get the SAME translated-rail-line
## treatment applied to their own rail column, via 2 extra Sprite2D
## pieces cropped from the corner's own shadow-atlas cell — the
## corner's whole-tile SHEAR (used for its horizontal-arm pickets and
## cross-rails) was never going to make its rail column "continue the
## same pattern" as the straight tiles' translated rail lines above
## it. v0.2.265 widened this piece's own row range from just the
## bottom 4 rows (12-15) to the corner's FULL rail column (0-15) —
## the bottom-only crop fixed continuity at the corner's own ground,
## but left a second, separate discontinuity at the corner's own TOP
## edge (bordering the straight tile above) wherever the v0.2.264
## fake-post pieces don't already paint over it (row 3's gap, rows
## 6-11) — real pixel data already covers all 16 rows, so this only
## ever needed a wider crop, not new art.
const FENCE_CORNER_RAIL_TAIL_ATLAS_CELLS := [Vector2i(2, 0), Vector2i(3, 0)]   ## NE, NW shadow-atlas cells only
const FENCE_CORNER_RAIL_TAIL_ROW_START := 0.0 * FX_SCALE
const FENCE_CORNER_RAIL_TAIL_ROW_COUNT := 16.0 * FX_SCALE
## v0.2.264: NE/NW corners' own rows 0-5 have no real knot-bulge art at
## all (that space is occupied by the corner's horizontal-arm detail
## instead), so the established post-knot "tick" rhythm from the
## straight run above stopped short of the corner. Filled with 2 extra
## "fake post" pieces per corner, cropped from the STRAIGHT vertical
## atlas's own shadow cell (index 1 — the corner's own cell has no
## knot pixel data in that space to crop) — a deliberate shadow-only
## continuation of the rhythm, not a claim the real corner art secretly
## has knots there. Row 3 is left bare between the two bands, matching
## the established knot-to-knot gap rhythm.
## v0.2.266 follow-up ("now extend the corner post like this. on both
## bottom corners of the fence", on a screenshot of this same NE-type
## corner with red marks on the real post caps and a red dot at the
## corner's own pivot): a close crop of the pivot itself (where the
## vertical arm's shaft bends into the horizontal rail) showed a bare
## patch of grass immediately around the bend — no shadow there at
## all, real "post"-style tick or otherwise. Every other joint along
## this corner's own rhythm already casts a wedge: the straight tile
## above has 3 real knots (rows 0-2/6-8/12-14 of ITS OWN tile), the
## corner's own rows 0-2 and 4-5 get the v0.2.264 fake-post treatment
## — but the corner's own PIVOT (local rows ~12-14, where the vertical
## shaft actually turns) never got one, because that's real corner art
## (the turn itself), not empty space the way rows 0-5 were. A third
## band, `Vector2i(12, 14)`, closes that gap — deliberately matching
## FENCE_VERTICAL_POST_ROW_BANDS's own third band exactly (the
## straight vertical atlas's natural bottom-knot position), so the
## corner's own pivot reads as one more knot in the same established
## rhythm rather than a bespoke shape. Same fake-post mechanism as the
## other two bands (cropped from the straight vertical atlas's own
## shadow cell, own local shear anchor) — it composites OVER the
## corner's real turn art at those rows, which is fine: a real post's
## own knot shadow is expected to be the most visually prominent thing
## at a joint, same as everywhere else along the fence.
const FENCE_CORNER_FAKE_POST_ROW_BANDS := [Vector2i(0, 2) * 4, Vector2i(4, 5) * 4, Vector2i(12, 14) * 4]
## v0.2.246 fix, per direct request: "the fence shadows need to merge
## with adjacent ones, like walls but with holes basically." Each fence
## tile's shadow still transforms independently, anchored to ITS OWN
## real base (that per-tile independence is exactly what keeps every
## tile's shadow attached to that tile's own real base — a single
## shared transform for a whole multi-tile run would only keep ONE
## point on the run anchored and let every other tile drift away from
## its own base the farther it sits from that point, reintroducing the
## v0.2.244 bug for anything longer than a couple of tiles). What
## changes here is only how the already-correct per-tile pieces are
## COMPOSITED: they're now children of a shared CanvasGroup
## (`_fence_shadow_group`, set up in _rebuild_shadows()) instead of
## being added to shadow_container directly. A CanvasGroup renders its
## children into one shared offscreen buffer before compositing that
## buffer as a whole onto the scene — so where two fence shadow sprites
## overlap (most likely right at a corner), the overlap just shows
## whichever child is on top, instead of two separate translucent draws
## stacking into a visibly darker double-shadow patch. The per-tile
## silhouette shader outputs a fully OPAQUE shape (see
## fence_shadow_silhouette.gdshader's own comment) and the group's own
## `self_modulate.a` supplies the actual translucency exactly once for
## the flattened result — so individual pickets/posts still read as
## real transparent holes, and non-overlapping fence shadows look
## pixel-identical to before this fix.
var _fence_shadow_group: CanvasGroup = null
## Which map characters cast a shadow — genuinely tall objects a
## real light source would silhouette, not flat ground decoration.
## Per the request: "w"/"r" (wooden and stone house fronts) now cast
## shadows too, exactly like every other wall/building tile — they
## were previously omitted here even though they're already part of
## BUILDING_CHARS for layering purposes.
## Per the follow-up request: "d" (the door) now casts a shadow too,
## same as the wall tiles flanking it — previously deliberately
## excluded on the theory that an open doorway is a gap rather than a
## silhouette, but the request is explicit that doors should shadow
## exactly like walls do, so that reasoning no longer applies. Doors
## still stay OUT of WALL_MATERIAL_CHARS (see its own comment) — this
## only affects shadow casting, not building-footprint/roof detection.
## "I" (fence) stays OUT of SHADOW_CASTING_CHARS — it casts a shadow
## again as of this build (see the comment above FENCE_TILESET_TEXTURE),
## but via its own dedicated branch in _rebuild_shadows()/
## _update_shadow_angles(), NOT the wall-run rect-merge path this list
## feeds. Adding "I" here would merge fence tiles into
## _find_wall_shadow_rects()' solid-rectangle logic, which is exactly
## the "loses the gaps, becomes a solid block" failure mode every fence
## shadow design that reused the wall/rect approach ran into. As
## before, "I" is also out of WALL_MATERIAL_CHARS (see its own
## comment): neither list affects the other, and this has no effect on
## building-footprint/roof detection.
## Per the Goblin Fort rework: "a" (palisade) and "j" (its gate) join
## every other wall/door char here — same reasoning as "d" above, a
## solid silhouette either way. "t" (tent) is deliberately left out,
## same as "W" (well) / the static lamp — a small freestanding object
## outside the primary sun/moon shadow system, not a wall run.
const SHADOW_CASTING_CHARS: Array[String] = ["T", "B", "K", "O", "#", "w", "r", "d", "h", "m", "u", "a", "j"]
## Per the request: walls/buildings that sit next to each other should
## have their shadows join up into one seamless shape instead of each
## tile fanning out its own separate shadow from its own pivot (which
## visibly gapped at non-midday sun angles — see
## _find_wall_shadow_rects()). Measured directly from shadow_wall.png's
## own (essentially flat) pixel colour, so the merged flat-fill shape
## reads as the same shadow, just without the seams.
const WALL_SHADOW_COLOR := Color(8.0 / 255.0, 14.0 / 255.0, 8.0 / 255.0, 140.0 / 255.0)
## Per the request ("subtle moon glow+shadows during the night"): the
## multiplier every shadow (trees/walls/fences via shadow_container's
## own `modulate`, which cascades to every child including the fence
## CanvasGroup; Player/NPC shadows directly, since those sprites live
## outside shadow_container — see _update_person_shadow()) is tinted
## toward at full night, faded in/out via GameState.get_night_darkness()
## so it eases in exact lockstep with the night overlay itself rather
## than a separately-tuned timeline. A cool pale blue-silver, and a
## reduced alpha multiplier (0.6) so moonlit shadows genuinely read as
## fainter than daylight ones, not just differently coloured.
const MOON_SHADOW_TINT := Color(0.55, 0.65, 0.95, 0.6)
## Per the request: the Player and every friendly NPC now cast a
## shadow too, exactly like trees and walls already do — same
## sundial-style sweep (see _update_shadow_angles()), just anchored
## to a moving/standing character instead of a fixed tile. Unlike
## tree shadows, no clip shader is needed here: the character sprite
## isn't baked into the ground tile the way a tree's canopy is, so a
## plain z-index below the character (see _make_person_shadow())
## already keeps the shadow from ever drawing over its own owner.
const SHADOW_TEXTURE_PERSON := preload("res://assets/fx/shadow_person.png")
## Measured directly from shadow_person.png's own opaque pixels — the
## narrow point at the very bottom is the shadow's own anchor (a
## character's feet), matching the tree-shadow convention of pivoting
## around a fixed point while the rest of the shape swings around it.
## Per the TILE_SIZE 16->64 upscale: deliberately left UNSCALED, unlike
## every other _PX constant above. shadow_person.png itself is NOT
## being 4x-upscaled (per "leave NPCs for now" — Player/NPC art,
## including their shadow, stays native-res); instead the Player/NPC
## Sprite2D itself gets an explicit `scale = Vector2(4,4)` (see
## player_controller.gd and the NPC spawn functions below), and
## _make_person_shadow()'s Shadow node is a CHILD of that sprite, so it
## inherits the 4x visual boost for free — these constants stay in
## native, pre-scale local space to match. The one place that draws
## SHADOW_TEXTURE_PERSON WITHOUT that parent scale (the secondary
## light-source shadow branch below) multiplies by FX_SCALE explicitly
## at its own call site instead.
const PERSON_SHADOW_PIVOT_PX := Vector2(6.0, 17.0)
## Where a character's own feet sit within their 16x16 sprite (every
## Player/NPC sprite is non-centered, origin at its own top-left
## corner) — this is the shadow node's local position within its
## parent, i.e. the point the shadow actually pivots around. See the
## PERSON_SHADOW_PIVOT_PX comment above re: staying unscaled.
const PERSON_SHADOW_ANCHOR_PX := Vector2(8.0, 15.0)

## Per the follow-up request ("add secondary shadows for light
## sources. objects with no line of sight or that cast shadows already
## should all be included"): the carried light source (Lantern/
## Candle) now throws its own short, radial shadows off nearby solid
## objects, layered on top of the long, slow sun/moon sweep above.
## Eligible objects are the union of SHADOW_CASTING_CHARS (everything
## that already casts a primary sun/moon shadow) and BLOCKED
## (everything solid enough to stop movement — the overworld has no
## separate dedicated line-of-sight concept of its own; that's the
## battle grid's, see CombatEncounter/BattleGrid, deliberately not
## reused here), minus WATER_CHARS — a flat river surface has no real
## height to throw a shadow from, and a shadow-shaped patch sweeping
## across it would just read as a rendering glitch. Computed by hand
## as a literal (GDScript const arrays can't be built from a runtime
## union expression over other consts).
const SECONDARY_LIGHT_SHADOW_CHARS: Array[String] = [
	"T", "B", "K", "O", "#", "w", "r", "d", "h", "m", "u",   ## == SHADOW_CASTING_CHARS
	"I",                                                      ## fence — its own primary-shadow branch exists, simple radial treatment here
	"M", "W", "C", "R", "E", "V", "o", "l",                  ## == BLOCKED, minus WATER_CHARS, not already listed above (l added for the static lamp post)
]
## The light-shadow's own scale range, blended by how close the object
## sits to the light (see _apply_light_source_secondary_shadows()) —
## used for the per-tile tree/person blob SHADOW SPRITES specifically
## (see the two sprite.scale assignments below). Deliberately a plain
## scale multiplier, same style as the sun/moon sweep's own `0.75 +
## length_factor * 0.35`, not a literal target pixel length. Left
## unchanged by the wall-shadow length fix just below — a tree or
## person's own little cast-shadow blob stretching several tiles long
## would look absurd; the actual reported gap is specifically about
## wall shadows, not these.
const SECONDARY_LIGHT_SHADOW_MIN_SCALE := 0.35
const SECONDARY_LIGHT_SHADOW_MAX_SCALE := 1.3
## Per the "you just made shadows black without fixing the light bleed
## at the edges of the light circle" report: v0.2.613 tried raising the
## alpha every occluded surface compensates against instead (a
## since-reverted OCCLUDED_TARGET_ALPHA — see _compensate_alpha_for_
## reveal()'s call sites) to stop a bright barley field from showing
## through its own correct wall-shadow. That made shadowed ground read
## as flat black without touching the actual complaint — the visible
## reach of a wall's own cast-shadow SHAPE stopping well short of where
## a light's own circle actually fades into ambient darkness, leaving a
## gap of "technically redarkened but visually bare" ground in between.
## Reverted the alpha change; THIS range is the real fix instead — used
## only for the merged wall-shadow POLYGON's own extension length (see
## the two `extension := dir_vec * tile_size.y * length_scale` call
## sites), not the blob-sprite scale above. Bumped from a short
## 0.35-1.3 tiles up to 1.2-3.5 tiles — every wall's own cast shadow now
## reaches several tiles out, all the way into (or past) the zone where
## the light's own falloff was already fading to black, so there's no
## gap left between "end of visible shadow" and "start of ambient dark"
## for the light's own edge to bleed through.
const SECONDARY_LIGHT_WALL_SHADOW_MIN_SCALE := 1.2
const SECONDARY_LIGHT_WALL_SHADOW_MAX_SCALE := 3.5
## Per the follow-up report ("the light radius is a round circle which
## ignores the tiles while the wall shadows are tile based, where they
## meet, there is gaps of light"): v0.2.615 tried making each wall run's
## shadow FAN OUT from its own light (a new _swept_clip_piece_radial(),
## projecting each footprint corner along its own ray from the light
## instead of by one shared vector) instead of staying a constant-width
## parallelogram. Verified in isolation (an A/B screenshot diff of the
## real village map showed exactly two clean fan-shaped wedges closing
## the gap beside each building's shadow, nothing else in frame changed)
## but reverted at the user's request right after shipping — back to
## the plain `extension := dir_vec * tile_size.y * length_scale` +
## _swept_clip_piece(footprint, extension) translation-sweep below, same
## as v0.2.614. Left this note so a future attempt at the same report
## doesn't have to rediscover the radial-sweep idea from scratch, or
## repeat it without knowing it was already tried and pulled back.
## Per the follow-up request ("secondary shadows should be the same
## darkness as the current normal night darkness outside the light,
## and merge cleanly with the darkness outside the ring of light"):
## superseded the old fixed alpha pair this comment used to document
## (a flat 0.85 near / 0.4 far, deliberately darker than WALL_SHADOW_
## COLOR's own ambient tone) — a secondary shadow's own color/alpha is
## now read fresh from `night_overlay.color` every frame instead (see
## _apply_light_source_secondary_shadows()/_apply_static_lamp_secondary_
## shadows() below), so it always matches whatever the CURRENT ambient
## night tint and darkness level actually are (time of day, moon-glow
## pulse, weather, all of it) rather than a separately-tuned fixed
## value. A static lamp's own STATIC_LAMP_SHADOW_RANGE_TILES exactly
## equals its STATIC_LAMP_LIGHT_RADIUS_TILES, so a shadow at the very
## edge of its range sits right at the true boundary of the lamp's own
## light circle — matching the live ambient color there, rather than
## fading to some fixed lighter tone, is what keeps that boundary from
## reading as a visible seam against the real night just beyond it.
## A Lantern's own real light_radius_tiles is 20 (Storm Lantern more)
## — practically "reveal the whole nearby area," not "cast a sharp
## shadow of one specific object." Genuine point-light shadows only
## read correctly, and stay cheap to compute every frame, over a much
## SHORTER close-range reach than the light's own full reveal radius
## — capped here regardless of how far the light actually illuminates.
## Per the "secondary shadows seem to only go 10 yards even in full
## light...2nd light should dispel shadows beyond 10 yards if it
## reaches that far" follow-up: this cap ONLY governs how far an
## individual shadow-casting BLOB sprite (tree/person silhouette) or
## merged wall-shadow polygon is drawn (blob_shadow_range_tiles in
## _apply_light_source_secondary_shadows()) — it deliberately does NOT
## limit the LOS-occlusion sweep, the redarkening-exemption tracking
## (_player_secondary_lit_tiles), or cross-light suppression
## (_player_secondary_shadow_range_tiles) any more, all of which now use
## the light's own TRUE radius_tiles instead, so a wall's redarkened
## "shadow" correctly extends all the way out to wherever the light
## itself actually stops reaching (merging cleanly with the ambient
## dark beyond) and a strong Lantern can dispel another light's shadow
## anywhere its own true glow reaches, not just within this short cap.
const SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES := 8
## Per the "there is always light bleeding through the edges (top row
## of cells)... extend secondary shadow beyond the circle of the light"
## follow-up: a tile sitting right at the OUTER rim of a light's own
## true reach only ever gets a PARTIAL reveal from the shader — the
## last ~1-1.5 tiles are its softness band, fading from that light's
## own brightness down to exactly 0 right at the true edge (see
## night_overlay_light.gdshader's own smoothstep). But
## _tile_lit_by_any_secondary_light()'s membership test (is this tile
## in _player_secondary_lit_tiles / _lamp_secondary_lit_tiles) is a
## hard yes/no — a tile barely inside that fading rim counted as
## exactly as "lit" as one deep in the light's core, which was enough
## to fully exempt it from redarkening, or to let it cross-suppress a
## DIFFERENT light's shadow there. Since the shader itself was already
## fading that same spot toward black, the result was a thin band where
## nothing painted proper matching darkness even though the light
## barely reached it any more — the reported seam. Tiles that count as
## "lit" for exemption/cross-suppression purposes now have to be
## solidly inside a light's core (its true radius minus this margin),
## not just barely grazed by its fading rim — so a shadow now correctly
## wins in that outer band instead. Deliberately does NOT shrink the
## occlusion-sweep bound itself (see occlusion_range_tiles in
## _apply_light_source_secondary_shadows()) — a wall right at the true
## edge still needs to be found and fully redarkened; only the
## "does some light's reach cancel that out" test gets the margin.
const SECONDARY_SHADOW_EDGE_MARGIN_TILES := 2
## Rebuilt fresh alongside the rest of shadow_container's children in
## _rebuild_shadows() — added there LAST, after every tree/wall/fence
## shadow, so within shadow_container's own z tier it draws on top of
## them (a torch a step away from a tree should read as the more
## prominent, sharper shadow).
var light_shadow_container: Node2D = null
## One pooled Sprite2D per currently-in-range tile, keyed by its own
## tile coords — reused/hidden rather than destroyed+recreated every
## frame (this runs from _process(), the same cadence as
## _apply_light_source_overlay()), and reset alongside
## light_shadow_container itself on every map (re)build.
var _light_shadow_sprites: Dictionary = {}
## Per the request ("the primary and secondary shadow buildings cast
## should come from the wall edges and be merged into one solid
## shadow"): wall/building tiles caught by the light-source shadow
## sweep above get pulled OUT of the plain per-tile person-blob loop
## (a rectangular wall casting a little person-shaped shadow blob was
## always wrong) and drawn here instead — one merged flat-fill polygon
## per contiguous wall run in range, same "swept + clipped + unioned"
## technique _update_shadow_angles() already uses for the sun/moon
## shadow (see _find_wall_shadow_rects()/_swept_clip_piece()/
## _union_polygon_into(), all reused as-is), just extruded away from
## the PLAYER's own position instead of a fixed sun/moon direction,
## since a torch's shadow direction is different for every wall tile
## around it. A small pooled Array (not a Dictionary keyed by coords,
## since a merged run's own shape is recomputed from scratch every
## frame as the player moves) — grown as needed, extra nodes from a
## previous frame just get an empty polygon rather than being freed,
## same pattern _update_shadow_angles()'s own wall_nodes loop uses.
var _light_wall_shadow_nodes: Array = []
## Per the "should only light up things with LOS" request: every tile
## within the player's own light range that _has_line_of_sight() ruled
## out this frame — refreshed at the top of _apply_light_source_
## secondary_shadows() each call, consumed by _refresh_light_occlusion()
## right after (see that function's own comment for the full picture).
var _player_light_blocked_tiles: Array = []
## Per the "secondary lights should remove both primary and secondary
## shadows within their light LOS" request: every tile the player's own
## carried light can currently see (LOS-checked, within its own capped
## secondary-shadow range) — recomputed once per frame by
## _recompute_secondary_light_lit_tiles(), BEFORE either _apply_light_
## source_secondary_shadows() or _apply_static_lamp_secondary_shadows()
## run, so each of those can check "is this tile ALSO reachable by a
## DIFFERENT active light" and suppress its own shadow there (a second
## light's illumination fills in what would otherwise be a shadow from
## the first). Keyed the same way _light_visible_tiles() already returns
## (Dictionary, coords -> true), so checking membership is a plain O(1)
## `.has()`.
var _player_secondary_lit_tiles: Dictionary = {}
## Same idea, one Dictionary per lamp, keyed by lamp index.
var _lamp_secondary_lit_tiles: Dictionary = {}
## The player's own light's TRUE reach this frame in tiles (0 when no
## effective light) — cached alongside _player_secondary_lit_tiles so
## the wall-shadow disc-clip below doesn't need to re-derive it from
## _party_light_bearer()/get_active_light_radius_tiles() a second time.
## Per the "2nd light should dispel shadows... if it reaches that far"
## follow-up: this is the light's own UNCAPPED radius_tiles, not the
## shorter SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES cap that separately
## limits how far individual shadow-blob sprites are drawn.
var _player_secondary_shadow_range_tiles: int = 0
## Per the same request: the pooled screen-space quads _refresh_light_
## occlusion() draws to re-darken every currently-blocked tile (player's
## own + every lamp's) — see that function's own long comment.
## Lazily created on first use (as a child of cloud_shadow_overlay) and
## kept for the life of the scene, same as every other UI node here.
var _light_occlusion_container: Node2D = null
var _light_occlusion_quads: Array = []
## Per the "the re-darkening behind walls is done in tile-sized chunks
## (64px)... lets make them smooth" follow-up, this USED to cache each
## tile-grid corner's own redarkening weight so a redarkening quad could
## fade its alpha down toward a neighbouring lit tile across roughly one
## tile's width instead of cutting off in one hard step (see the deleted
## _occlusion_corner_weight()). Per the later "wall shadows leave gaps of
## light when they meet the edge of lantern/lamp light circle" report —
## reproduced and confirmed: that corner grading unconditionally diluted
## a genuinely-blocked tile's own alpha by up to 75% wherever it happened
## to share a grid corner with a brightly-lit neighbour, regardless of
## how bright that neighbour actually was, which is exactly a "should be
## fully dark but isn't" gap right where a wall's shadow meets a light's
## own reach. _refresh_light_occlusion() now fills each redarkened tile
## with its own flat, fully-compensated alpha again (see tile_alpha
## there) — every blocked tile is always exactly as dark as _local_
## light_reveal()/_compensate_alpha_for_reveal() says it should be, with
## no neighbour-dependent dilution, at the cost of the boundary itself
## going back to a hard tile-grid step rather than a smoothed fade.
## Per the "add 2 static lamps... these should come on at night time and
## cast secondary shadows around them" request: the warm halo texture
## drawn over each lamp post once it's "lit" — a plain soft radial
## gradient, not animated, kept as its own const the same way every
## other fx texture on this file is (SHADOW_TEXTURE_TREE etc.).
const LAMP_GLOW_TEXTURE := preload("res://assets/fx/lamp_glow.png")
## The lamp's own glow ramps up over a narrower band of night_amount
## than the ambient moon-shadow tint does (see MOON_SHADOW_TINT's own
## lerp against the full 0-1 night_amount in _update_shadow_angles()) —
## a real street lamp reads as "switched on" fairly promptly once dusk
## sets in, not a slow fade synced with the deepest part of the night.
const LAMP_GLOW_FADE_START := 0.12   ## night_amount at which the lamp starts visibly lighting
const LAMP_GLOW_FADE_END := 0.45     ## night_amount at which the lamp reaches full brightness
const LAMP_GLOW_MAX_ALPHA := 0.9
## Per the follow-up request ("these static lamp should cast 10yard
## shadow"): 10 yards, expressed directly as 10 tiles on the overworld
## grid — the same yards≈tiles convention Character.get_active_light_
## radius_tiles() already relies on here (its own doc comment: "returns
## YARDS despite its name", plugged straight into Overworld's own
## radius_tiles/SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES as a tile count
## with no further conversion — see _apply_light_source_overlay()'s
## radius_px line). Kept as its own separate constant from the carried-
## light system's SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES := 8, so a
## static lamp's own reach can be tuned independently of a carried
## Lantern's.
const STATIC_LAMP_SHADOW_RANGE_TILES := 10
## Per the "light bleeding through the edges... extend secondary shadow
## beyond the circle of the light" follow-up (see SECONDARY_SHADOW_EDGE_
## MARGIN_TILES's own comment for the full mechanism): the static
## lamps' own "counts as genuinely lit" radius, margin already
## subtracted — used wherever a lamp's own _lamp_secondary_lit_tiles
## set (or another light's disc clipping this lamp's own wall shadow)
## needs to know how far THIS lamp's light genuinely counts as reaching
## for exemption/cross-suppression purposes. STATIC_LAMP_SHADOW_RANGE_
## TILES itself is untouched and still governs the lamp's own occlusion
## sweep and blob/wall-shadow rendering distance, both left at the full
## 10 tiles.
const LAMP_SECONDARY_LIT_RANGE_TILES := STATIC_LAMP_SHADOW_RANGE_TILES - SECONDARY_SHADOW_EDGE_MARGIN_TILES
## Per the same request: a lamp must also punch its own hole through
## NightOverlay's darkness (and CloudShadowOverlay's drifting patches),
## the same way the player's own carried Lantern does via
## night_overlay_light.gdshader's `lamp_*` uniform array — otherwise
## the glow Sprite2D above would just get crushed back to near-black by
## that full-screen overlay drawn on top of it.
## Per the follow-up request ("these static lamp should cast 10yard
## shadow"): matches STATIC_LAMP_SHADOW_RANGE_TILES's own 10-yard/10-
## tile reach, so the lamp's visible glow/reveal radius and the range
## it actually casts shadows across line up. Brightness stays dimmer
## than a carried Lantern (LIGHT_BRIGHTNESS_ON := 0.72) — a fixed
## street lamp lighting a wider pool of ground at lower intensity, not
## a torch held right up close.
const STATIC_LAMP_LIGHT_RADIUS_TILES := 10
const STATIC_LAMP_LIGHT_BRIGHTNESS := 0.55
## A lamp's own secondary shadows only start being worth drawing once
## it's actually lit — reusing LAMP_GLOW_FADE_START as that same cutoff
## (rather than a separate constant) keeps "the glow is visible" and
## "the lamp casts light-shadows" perfectly in sync, the same way the
## carried-light system's _light_source_effective() gates both its own
## overlay and its own secondary shadows on one shared condition.
## Rebuilt fresh alongside light_shadow_container in _rebuild_shadows()
## (same reset reasoning — the previous map's pooled nodes are freed
## with the rest of shadow_container's children) — one Node2D holding
## every lamp's own glow Sprite2D, kept OUTSIDE shadow_container/
## light_shadow_container on purpose: those two get shadow_container's
## own modulate cascade (the day/night MOON_SHADOW_TINT cool-blue tint
## plus its counter-multiplied alpha, see _update_shadow_angles()'s own
## comment on light_shadow_container.modulate), which would wrongly tint
## and fade a lamp's own warm glow along with the shadows it's meant to
## be independent of. Added directly under the Overworld node itself,
## with its own z_index (see _rebuild_shadows()) instead.
var _static_lamp_glow_container: Node2D = null
## One pooled Sprite2D per lamp in static_lamp_coords, keyed by that
## lamp's own tile coords — same pooling convention as
## _light_shadow_sprites above, just never hidden/shown per-frame (only
## its alpha fades, driven by night_amount in _update_shadow_angles()).
var _static_lamp_glow_sprites: Dictionary = {}
## 0 (fully off) .. 1 (fully lit) — recomputed each time _update_shadow_
## angles() runs (see its own comment on this same line), read every
## frame by _apply_static_lamp_overlay() below to scale the night-
## overlay/cloud-shadow reveal without that per-frame function needing
## to recompute night_amount itself.
var _lamp_night_factor: float = 0.0
## Per the same request: each lit static lamp needs its own independent
## "cast secondary shadows around it" pass, structurally identical to
## _apply_light_source_secondary_shadows()'s own per-tile-blob +
## merged-wall-run pipeline, just sourced from a fixed lamp position
## instead of the player's carried light. Kept as entirely SEPARATE
## pooled structures — never merged into _light_shadow_sprites/
## _light_wall_shadow_nodes above — so building_secondary_shadow_merge_
## test.gd and secondary_light_shadow_test.gd's own direct, bare-
## Vector2i-keyed lookups into those two stay exactly as they were
## before this feature existed. Both keyed by lamp index (its position
## in static_lamp_coords) rather than lamp coords, since a Dictionary
## key needs to be hashable/stable and an int index is simplest; each
## value is itself the same shape _light_shadow_sprites/_light_wall_
## shadow_nodes already use (a coords-keyed Dictionary of Sprite2D, and
## a plain Array of pooled Polygon2D) for exactly one lamp.
var _static_lamp_tile_shadow_sprites: Dictionary = {}
var _static_lamp_wall_shadow_nodes: Dictionary = {}
## The actual shadow sprites/polygons _apply_static_lamp_secondary_
## shadows() draws — kept INSIDE shadow_container (unlike
## _static_lamp_glow_container above), a sibling of light_shadow_
## container, so a lamp's cast shadows tint/dim with the day-night cycle
## exactly like every other shadow on the map (the glow itself is the
## one part of this feature that must NOT do that — see that
## container's own comment).
var _static_lamp_shadow_container: Node2D = null
## Per the "should only light up things with LOS" request: mirrors
## _player_light_blocked_tiles, one Array per lamp, keyed by lamp index
## — refreshed each call to _apply_static_lamp_secondary_shadows(),
## consumed by _refresh_light_occlusion().
var _static_lamp_blocked_tiles: Dictionary = {}
@onready var player: Node2D = $Player
@onready var dialogue_label: Label = $UI/DialogueLabel
@onready var encounter_label: PanelContainer = $UI/EncounterBox
@onready var encounter_label_text: Label = $UI/EncounterBox/EncounterMargin/EncounterLabel
@onready var hud_label: Label = $UI/HudLabel
@onready var night_overlay: ColorRect = $UI/NightOverlay
@onready var cloud_shadow_overlay: ColorRect = $UI/CloudShadowOverlay
@onready var party_panel_row: HBoxContainer = %PartyPanelRow
@onready var xp_label: Label = %XPLabel
@onready var gold_label: Label = %GoldLabel
@onready var time_label: Label = %TimeLabel
@onready var date_label: Label = %DateLabel
@onready var quest_tracker_title: Label = %QuestTrackerTitle
@onready var quest_tracker_detail: Label = %QuestTrackerDetail

## Per the request ("randomize it subtly day to day"): the calendar
## day-key (see _maybe_reseed_cloud_shadow_overlay()) the cloud shadow
## shader's uniforms were last seeded for — -1 so the very first
## _update_hud() call always reseeds, regardless of what day the game
## actually starts on.
var _cloud_shadow_seed_day: int = -1
## Per the follow-up request ("add the cloud overlay to the overworld
## map... considering the high up view"): the World Map now uses a
## different, finer-grained tuning of the same shader (see
## _maybe_reseed_cloud_shadow_overlay()) — tracked alongside the day key
## so switching between a local map and the World Map on the same
## in-game day always re-tunes for whichever one is actually current,
## instead of the reseed short-circuit skipping it because the day
## itself hasn't changed.
var _cloud_shadow_seed_is_world: bool = false
## Base alpha _update_night_overlay() last computed from
## GameState.get_time_of_day_color(), before _process()'s own subtle
## moon-glow pulse (see below) nudges it up and down each frame — kept
## separate so the pulse never has to be "undone," and so
## _update_night_overlay() (event-driven, not per-frame) stays the
## single source of truth for the real underlying time-of-day value.
var _night_overlay_base_color: Color = Color(0, 0, 0, 0)

## --- Automatic Roll Log overlay (bottom-right) -------------------------
## Per the request ("add a transparent overlay in the bottom right of the
## overworld screen which will show all automatic rolls which are
## happening while walking around... keep it simple... fade out line by
## line after about 10 seconds, mousing over the bottom right of the
## screen will show the history"): every hidden TestResolver roll this
## screen already makes on the party's behalf (ambush/social Perception,
## Charm small talk, Ancient Tomb/Ruin/Monolith checks, mud-crossing
## Tests, and so on) used to be completely invisible — the player only
## ever saw the prose OUTCOME ("You spot it in time"), never the roll
## that produced it. _log_auto_roll() below is the one funnel every one
## of those call sites now routes through via the _tr_skill()/_tr_char()/
## _tr_party() wrappers (see their own comments), so surfacing a new kind
## of automatic roll later only ever means routing it through the same
## wrapper, not touching this overlay again.
##
## Two halves, built entirely in code in _build_roll_log_overlay() (same
## "no .tscn editing" approach BattleGridView's own hover tooltip already
## uses) rather than a scene-file addition:
## - `_roll_log_feed`: the transient live feed — each new roll appends a
##   Label, which fades itself out ROLL_LOG_FADE_AFTER_SEC seconds after
##   it was added and frees itself once fully transparent.
## - `_roll_log_history_panel`: the FULL session history (capped at
##   ROLL_LOG_MAX_HISTORY), hidden until the mouse enters the corner
##   hover zone and hidden again the moment it leaves — the "mousing
##   over... will show the history" half of the request.
var _roll_log_history: Array[String] = []
const ROLL_LOG_MAX_HISTORY := 200
const ROLL_LOG_FADE_AFTER_SEC := 10.0
const ROLL_LOG_FADE_DURATION_SEC := 1.5
const ROLL_LOG_MAX_VISIBLE_LINES := 8
## Real bug fix, caught by in-engine screenshot verification: a Label
## with no wrapping reports its own NATURAL (unwrapped) text width as
## its minimum size, and a plain Control parent (unlike a Container)
## never clamps a child below its own minimum size — so a longer roll
## line (e.g. "Aldric - Language (Magick) Roll vs 105 (SL +12)", ~490px
## at this font size) was silently inflating _roll_log_feed/_roll_log_
## history_list past this box's intended width, pushing the overflow
## off the right edge of the screen entirely rather than staying inside
## the corner. Fixed two ways together: `clip_text = true` on every
## label below (its minimum size no longer depends on text length once
## that's set, so the box can no longer be blown out) with an ellipsis
## as a fallback for a genuinely long line, AND this widened from the
## original 340 to comfortably fit a realistic line without ellipsis-
## trimming in the common case.
##
## Per the follow-up request ("half the width of the roll log and
## history boxes"): halved again from 580 to 290. The clip_text +
## OVERRUN_TRIM_ELLIPSIS fix above means a line too long for this
## narrower box just gets an ellipsis rather than overflowing the
## screen edge, same safety net as before.
const ROLL_LOG_WIDTH := 290.0

var _roll_log_container: Control = null
var _roll_log_feed: VBoxContainer = null
var _roll_log_history_panel: PanelContainer = null
var _roll_log_history_list: VBoxContainer = null
var _roll_log_history_scroll: ScrollContainer = null

## Per the follow-up request ("make the text 3x smaller"): was a flat
## 13 (hardcoded separately in both _roll_log_push_feed_line() and
## _roll_log_refresh_history_panel()) — now one shared constant, cut to
## roughly a third.
##
## Per a further follow-up ("push it back to font size 6"): bumped back
## up from 4 to 6 — still noticeably smaller than the original 13, but
## more readable than 4.
const ROLL_LOG_FONT_SIZE := 6

var tile_chars: Dictionary = {}          ## Vector2i -> single-char String
var npc_dialogue: Dictionary = {}        ## Vector2i -> String
var petty_magic_trainer_coords: Array[Vector2i] = []   ## the Hermit Wizard(s) — special interaction, not just dialogue
var shopkeeper_coords: Array[Vector2i] = []
var priest_coords: Array[Vector2i] = []   ## the Shallyan Priest healer — cures Critical Wound effects for coin
## Per the request: what actually connects a specific map tile to a
## real quest NPC/monster encounter — built once from the map's own
## quest_npc_markers/quest_monster_markers when it loads.
var quest_npc_marker_tiles: Dictionary = {}      ## Vector2i -> QuestNPCMapMarker
var quest_monster_marker_tiles: Dictionary = {}  ## Vector2i -> QuestMonsterMapMarker
## Per the request: "hide NPCs that are inside houses from the
## outside" — every NPC/marker sprite spawned directly onto the map
## (shopkeeper, priest, traveller/trainer, elder, quest NPCs, the
## companion maker) registers itself here so its visibility can be
## tied to the same roof-visibility state as the building it's
## standing in — see _set_building_roof_visible() and
## _roofed_building_index_at(). Before this, every NPC sprite used a
## flat above_buildings_z (deliberately, so buildings never occluded
## them) which meant an indoor NPC rendered ON TOP of its own roof,
## visibly floating there from outside instead of reading as
## "sheltered inside." Vector2i -> Sprite2D.
var npc_sprites_by_tile: Dictionary = {}
var dialogue_timer: SceneTreeTimer = null
var character_menu: CanvasLayer
var pause_menu: CanvasLayer
var radial_menu: CanvasLayer
const RADIAL_MENU_SCENE := preload("res://scenes/RadialMenu.tscn")

## Enemy/Monster Difficulty Tier (0-5), per the request: "This will
## apply by Area (entire map or sub areas on the same map)."
## default_difficulty_tier covers the whole map unless the player's
## current tile falls inside one of difficulty_areas, which are
## checked in order (first match wins) and override the default within
## their own bounds. This map ships with the default at Tier 0 and no
## sub-areas defined, per the request to keep every enemy on the
## current map at Tier 0 for now — this is the template future
## maps/areas will build on as the world expands.
@export var default_difficulty_tier: int = 0
@export var difficulty_areas: Array[DifficultyAreaDefinition] = []

## Grid-based pathfinding for click-to-move — built once from the same
## walkability rules is_walkable() already uses, so a clicked spot only
## ever plots a path the player could also have walked manually.
var astar_grid: AStarGrid2D
var current_path: Array[Vector2i] = []   ## remaining tiles to walk, consumed one at a time as each step completes

## Per the request: true while the mandatory origin-story popup (or
## any other blocking story popup) is on screen — checked by
## is_menu_open() so PlayerController._process() won't move the
## player until it's dismissed.
var story_popup_active: bool = false
## Per the request: set by _build_map() when it's already deliberately
## placed the player this load (arriving via travel), so
## _restore_return_position() knows to skip its own fallback logic —
## see the real bug this fixes, documented at _build_map()'s own use
## of it.
var _used_deliberate_spawn_tile: bool = false

## Ambush-detection encounter system, per the request: a successful
## hidden Perception-vs-Stealth roll spawns a clickable "!" marker
## within 3 tiles of the player instead of starting combat instantly.
## Clicking it used to ambush the enemy group unconditionally
## (Surprised for Round 1); ignoring it and walking more than 6 tiles
## away makes it disappear with no fight at all — the player
## successfully avoided the encounter entirely, not just delayed it.
##
## Per the follow-up request ("instead of always surprising them after
## detecting them... they need to pass a second perception test on the
## target first, then give them the option to surprise the monsters or
## leave without the monster noticing"): clicking the marker no longer
## guarantees a surprise round. It now rolls a second, separate
## Perception Test (ambush_sneak_test_used/_success below) — success
## offers a real Surprise-or-Leave choice (see _show_ambush_choice()),
## while failure means the group has noticed something and there's no
## more sneaking to be had: a further click just wades in fighting
## normally, per the explicit follow-up ("if they fail the second test
## and attack the monster manually, the battle should start without
## the monsters being surprised").
var ambush_marker: Control = null
var ambush_marker_tile: Vector2i = Vector2i(-1, -1)
var ambush_group_names: Array[String] = []
var ambush_sneak_test_used: bool = false
var ambush_sneak_test_success: bool = false
const AMBUSH_MARKER_MAX_DISTANCE_FROM_PLAYER := 3
const AMBUSH_MARKER_FORGET_DISTANCE := 6

## Social encounter marker, per the request: unlike the ambush "!"
## marker above, this one has no hidden detection roll at all — it
## simply appears, a white "?" the player can choose to approach or
## ignore. Otherwise mechanically identical: spawns within 3 tiles,
## disappears once the player is more than 6 tiles away without
## clicking it.
var social_marker: Control = null
var social_marker_tile: Vector2i = Vector2i(-1, -1)

## Per the request: a right-click on either marker offers a one-time
## Perception check (+0) that, on success, reveals what's actually
## waiting there. social_marker_encounter is the encounter picked the
## moment the marker spawns — so a successful check can name it
## specifically, and the actual encounter (if the marker is later
## clicked) is guaranteed to be the same one, not a fresh roll.
var social_marker_encounter: SocialEncounterDefinition = null
## Per the follow-up request: the NPC's name/gender and which
## situation/opening-flavor variant this playthrough uses are chosen
## once, right when the marker spawns — same reason
## social_marker_encounter itself is pre-selected: a Perception reveal
## must match what actually happens later.
var social_marker_name_info: NPCNameGenerator.NameInfo = null
var social_marker_situation_index: int = -1
var social_marker_opening_flavor_index: int = -1
var ambush_perception_used: bool = false
var social_perception_used: bool = false
## Which marker (if any) the radial menu is currently open against —
## read back when "Perception" is actually chosen, since the menu
## itself doesn't know about markers.
var _radial_menu_target_marker: String = ""   ## "ambush", "social", or ""
## Which NPC tile (if any) the radial menu is currently open against,
## per the request — read back when Perception or Gossip is chosen.
var _radial_menu_target_npc: Vector2i = Vector2i(-1, -1)
## Which quest-monster (enemy) tile, if any, the radial menu is
## currently open against — per the Radial Menu rework request, Attack
## only shows for a target that "is an enemy and can be fought", i.e.
## a live (not yet defeated) quest monster marker.
var _radial_menu_target_enemy: Vector2i = Vector2i(-1, -1)
## The plain tile (if any) the radial menu is open against when it's
## none of the above (marker/chest/npc/enemy) — read back so Perception
## can still describe an ordinary tile, per the request that Perception
## ("info about the selected Tile") is always available.
var _radial_menu_target_tile: Vector2i = Vector2i(-1, -1)
var _last_left_click_time: int = 0
var _last_left_click_tile: Vector2i = Vector2i(-9999, -9999)
const DOUBLE_CLICK_MS := 400

## Configures this map's Difficulty Areas, per the request: the whole
## area east of the river (the bridge at row 19 crosses into it) is a
## Tier 1 zone. Within it, two themed sub-areas restrict which
## monsters actually spawn there — the goblin fort's forest territory
## in the south, and the bear cave's territory in the north — checked
## before the broad catch-all so a walk through either zone genuinely
## encounters what its theming promises, not just the map's generic
## random pool. All three share Tier 1; only the monster pool differs.
func _setup_pathfinding() -> void:
	var map_width: int = map_rows[0].length()
	var map_height: int = map_rows.size()
	astar_grid = AStarGrid2D.new()
	astar_grid.region = Rect2i(0, 0, map_width, map_height)
	astar_grid.cell_size = Vector2(TILE_SIZE, TILE_SIZE)
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER   ## matches this project's 4-directional movement everywhere else
	astar_grid.update()
	for y in range(map_height):
		for x in range(map_width):
			var coords := Vector2i(x, y)
			if not is_walkable(coords):
				astar_grid.set_point_solid(coords, true)

## Per the request: a gauntleted-hand mouse cursor — default, a red
## hue when hovering an ambush marker, and a small speech bubble added
## when hovering a social marker. Hotspot near the thumb spike (the
## part of the silhouette that actually points toward what's under
## it), scaled down from the 128x128 draw space to the real 32x32
## final cursor size.
const CURSOR_DEFAULT := preload("res://assets/sprites/cursor_gauntlet.png")
const CURSOR_AMBUSH := preload("res://assets/sprites/cursor_gauntlet_ambush.png")
const CURSOR_SOCIAL := preload("res://assets/sprites/cursor_gauntlet_social.png")
const CURSOR_HOTSPOT := Vector2(17, 8)
var _current_cursor_state: String = "default"   ## "default" | "ambush" | "social"

## Per a real leak caught during testing: Input.set_custom_mouse_cursor()
## holds its own reference to the cursor texture independent of this
## scene's own lifetime, and Godot reports (correctly) a leaked GL
## texture if that reference is never cleared before shutdown. Reset
## to the engine's own default arrow here, whenever this scene itself
## goes away (leaving the Overworld, not just switching menus within
## it) — the next scene that wants a custom cursor sets its own.
func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null)

func _process(_delta: float) -> void:
	_update_cursor_for_hover()
	_apply_moon_glow_pulse()
	_apply_light_source_overlay()
	_apply_building_interior_overlay()
	_apply_static_lamp_overlay()
	_apply_light_source_secondary_shadows()
	_apply_static_lamp_secondary_shadows()
	_refresh_light_occlusion()

## Per the request ("a subtle moon glow... during the night"): a very
## gentle breathing brighten/dim on top of NightOverlay's own base
## color (see _update_night_overlay(), which is event-driven — tile
## steps, waiting, etc. — and sets _night_overlay_base_color) so the
## night tint doesn't just sit static once dusk finishes settling in.
## Only runs while there's genuine night darkness to modulate (the
## World Map's own exemption already zeroes that out via
## _night_overlay_base_color.a == 0, so this naturally no-ops there
## too, without needing its own separate check) — and stays small
## (±0.035 alpha) and slow (an 8-second full cycle) specifically to
## read as "subtle," per the request, not a strobing effect.
##
## Per the follow-up request ("gets a bit too bright at its
## brightest... limit to be half as bright at its brightest, but
## don't make it darker at the lower end"): the pulse dipped the
## overlay's alpha DOWN by up to 0.035 at its brightest point (lower
## alpha = less dark tint blended over the scene = brighter) and
## pushed it UP by up to 0.035 at its darkest/dimmest point. That
## brightening half is now halved (max -0.0175 instead of -0.035),
## while the darkening half is left at its original full amplitude
## (still up to +0.035) — so the dim/low end of the breathing cycle
## reads exactly as before, only the bright peak is toned down.
func _apply_moon_glow_pulse() -> void:
	if not is_instance_valid(night_overlay):
		return
	if _night_overlay_base_color.a <= 0.01:
		night_overlay.color = _night_overlay_base_color
		return
	var raw_pulse: float = sin(Time.get_ticks_msec() / 1000.0 * (TAU / 8.0))
	var pulse: float = raw_pulse * 0.035 * (0.5 if raw_pulse < 0.0 else 1.0)
	var c := _night_overlay_base_color
	c.a = clamp(c.a + pulse, 0.0, 1.0)
	night_overlay.color = c

## Per the follow-up request ("show the player character light nimbus
## no matter which character is selected... if multiple character have
## light equipped use only one at a time in character order... and
## switch to the backup automatically"): each party member tracks their
## own light_mode/light_fuel_minutes independently (see
## Character.has_active_light_source()), and Q/E can freely change
## which one is GameState.player_character (the currently CONTROLLED
## member) without that having anything to do with whose lantern is
## actually lit. The party's one shared light — the nimbus, and the
## fuel that burns for it — is always whichever party member is FIRST
## in party order (GameState.party's own index order) with a genuinely
## active light source right now, regardless of who's currently
## selected/displayed. Because this is re-resolved fresh every call
## rather than cached, a bearer running out of fuel (has_active_light_
## source() flips to false the instant tick_light_fuel() sets
## light_mode = "off") is automatically superseded by the next
## eligible member in order on the very next check — no explicit
## "switch to backup" bookkeeping needed. If a second member also has
## their own light switched "on" behind the first, it simply never
## gets its turn (and never burns fuel) while the first is still lit,
## exactly like a real backup lantern staying unlit in a pack.
func _party_light_bearer() -> Character:
	for c in GameState.party:
		if c != null and c.has_active_light_source():
			return c
	return null

## Per the light-source request: mechanically active only at night or on
## a dark_location map (a future cave/ruin) — carrying a lit lantern at
## high noon outdoors has no effect, matching "should only be active at
## night time and in dark locations." The toggle itself (light_mode) is
## always available regardless — see _toggle_light_source() — this is
## purely "does it currently DO anything."
func _light_source_effective() -> bool:
	if _party_light_bearer() == null:
		return false
	if current_map_def != null and current_map_def.is_dark_location:
		return true
	return GameState.get_night_darkness() > 0.0

## Per the follow-up request ("the lantern light is not centered on the
## player... a bit less bright, and half again as bright in low light
## mode... turn off cloud shadows inside the lantern/light source
## nimbus"): a bit less bright at full ("on") strength than before, and
## low mode is now genuinely dimmer too (half of "on"'s brightness), not
## just a smaller radius at the same full strength. The reveal is also
## now punched through CloudShadowOverlay (not just NightOverlay) so
## drifting cloud-shadow patches don't visibly darken the ground right
## where the player is standing in their own lantern-light.
const LIGHT_BRIGHTNESS_ON := 0.72
const LIGHT_BRIGHTNESS_LOW := LIGHT_BRIGHTNESS_ON * 0.5

## Real bug fix, surfaced while wiring up the overworld Light spell
## (see _toggle_light_spell()): every brightness lookup below used to
## read `pc.light_mode` alone ("low" -> LIGHT_BRIGHTNESS_LOW, anything
## else -> full ON) — correct for an item-based source, but `pc` here is
## _party_light_bearer(), whoever has_active_light_source() picks out,
## which (per Character.has_active_light_source()) can now be a bearer
## whose light comes ENTIRELY from an active Light spell with light_mode
## left at its untouched default "off". Reading that default straight
## through the old "else -> full ON" branch meant a spell cast in "dim"
## mode with no item equipped always rendered full-brightness on the
## overworld regardless. This picks brightness from whichever of the two
## independent sources (item vs spell) is actually the one supplying
## get_active_light_radius_tiles()'s own winning radius, mirroring that
## function's own "spell wins a tie" precedence exactly.
func _active_light_brightness(pc: Character) -> float:
	if pc == null:
		return LIGHT_BRIGHTNESS_ON
	var spell_active: bool = pc.light_spell_rounds_remaining > 0 and pc.light_spell_mode != "out"
	var spell_radius: int = 0
	if spell_active:
		spell_radius = Character.LIGHT_SPELL_RADIUS_TILES_LOW if pc.light_spell_mode == "dim" else Character.LIGHT_SPELL_RADIUS_TILES
	var item_radius := 0
	if pc.light_mode != "off":
		var item := pc.get_equipped_light_item()
		if item != null and item.light_radius_tiles > 0 and not (item.light_requires_oil and pc.light_fuel_minutes <= 0.0):
			item_radius = item.light_radius_tiles_low if (pc.light_mode == "low" and item.light_radius_tiles_low > 0) else item.light_radius_tiles
	if spell_active and spell_radius >= item_radius:
		return LIGHT_BRIGHTNESS_LOW if pc.light_spell_mode == "dim" else LIGHT_BRIGHTNESS_ON
	return LIGHT_BRIGHTNESS_LOW if pc.light_mode == "low" else LIGHT_BRIGHTNESS_ON

## Draws (or clears) the light-radius reveal on top of NightOverlay's
## own darkness tint every frame. Per the bug report, the player is NOT
## always at the exact viewport center — Camera2D.limit_left/right/
## top/bottom (see _apply_camera_limits()) clamp the camera to the
## map's own bounds, so near any edge camera.get_screen_center_position()
## stops matching the player's real position, and World Map drag-pan
## (_reset_world_map_camera_pan()) can move the camera away from the
## player entirely. This now computes the player's REAL on-screen pixel
## position by inverting _screen_to_tile()'s own screen->world formula
## (screen_pos = viewport_center + (world_pos - camera_center) * zoom),
## using the sprite's actual visual center (Player's Sprite2D is
## `centered = false` with a 16x16 region, and Camera2D itself sits at
## local (8,8) to align with it — see Player.tscn) rather than the
## Player node's raw (0,0) origin corner.
func _apply_light_source_overlay() -> void:
	if not is_instance_valid(night_overlay):
		return
	if not (night_overlay.material is ShaderMaterial):
		var mat := ShaderMaterial.new()
		mat.shader = NIGHT_OVERLAY_LIGHT_SHADER
		night_overlay.material = mat
	var mat: ShaderMaterial = night_overlay.material
	var cloud_mat: ShaderMaterial = cloud_shadow_overlay.material if (is_instance_valid(cloud_shadow_overlay) and cloud_shadow_overlay.material is ShaderMaterial) else null
	## The party's shared light-bearer (see _party_light_bearer()'s own
	## comment) — NOT necessarily GameState.player_character/whoever is
	## currently selected. The nimbus is still drawn centered on the
	## single on-screen `player` sprite either way (there's only ever
	## one visible party sprite on the map), it just now reflects
	## whichever party member is genuinely carrying the lit source.
	var pc := _party_light_bearer()
	if not _light_source_effective():
		mat.set_shader_parameter("light_radius_px", 0.0)
		if cloud_mat != null:
			cloud_mat.set_shader_parameter("light_radius_px", 0.0)
		return
	var radius_tiles: int = pc.get_active_light_radius_tiles()
	if radius_tiles <= 0 or not is_instance_valid(player):
		mat.set_shader_parameter("light_radius_px", 0.0)
		if cloud_mat != null:
			cloud_mat.set_shader_parameter("light_radius_px", 0.0)
		return
	var camera: Camera2D = player.get_node("Camera2D")
	var zoom: Vector2 = camera.zoom if camera != null else Vector2.ONE
	var viewport_size := get_viewport_rect().size
	var viewport_center := viewport_size / 2.0
	## The sprite's own visual center in world space — matches
	## Camera2D's local (8,8) offset in Player.tscn, i.e. exactly where
	## the camera centers when NOT clamped away from the player.
	var player_world_center: Vector2 = player.global_position + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	var screen_pos: Vector2 = viewport_center + (player_world_center - camera.get_screen_center_position()) * zoom
	var radius_px: float = float(radius_tiles) * TILE_SIZE * zoom.x
	var softness_px: float = TILE_SIZE * zoom.x * 1.5
	var brightness: float = _active_light_brightness(pc)
	mat.set_shader_parameter("light_center_px", screen_pos)
	mat.set_shader_parameter("light_radius_px", radius_px)
	mat.set_shader_parameter("light_softness_px", softness_px)
	mat.set_shader_parameter("light_brightness", brightness)
	## Real bug fix ("player light source is still not centred on the
	## player character"): get_viewport_rect().size (viewport_size,
	## used to build screen_pos above) is this project's fixed
	## 1920x1080 DESIGN resolution — window/stretch/mode="canvas_items"
	## in project.godot lets the real OS window be any other size, and
	## the two only coincide when it happens to actually BE 1920x1080.
	## The shader used to compare against FRAGCOORD (the real, physical
	## framebuffer pixel), which drifted from this design-space
	## screen_pos on any other window size — confirmed by force-
	## resizing the window in a repro and watching the reveal circle
	## land nowhere near the player while this same screen_pos still
	## matched their true on-screen position exactly. Both shaders now
	## reconstruct a design-space fragment position from their own
	## resolution-independent UV instead (UV * screen_size), so this
	## viewport_size is sent alongside light_center_px as the scale to
	## multiply UV back out by.
	mat.set_shader_parameter("screen_size", viewport_size)
	if cloud_mat != null:
		cloud_mat.set_shader_parameter("light_center_px", screen_pos)
		cloud_mat.set_shader_parameter("light_radius_px", radius_px)
		cloud_mat.set_shader_parameter("light_softness_px", softness_px)
		cloud_mat.set_shader_parameter("screen_size", viewport_size)

## Per the "always light up the inside of building with no shadows"
## request: punches an unconditional, rectangular hole through both
## NightOverlay and CloudShadowOverlay over whichever ONE building the
## player currently has the roof hidden for (player_inside_building —
## _update_roof_visibility()'s own tracking; there's only ever one,
## since a building's interior floor is only actually rendered/visible
## while its own roof is off). Deliberately independent of whether the
## player has any light source at all — a real building has its own
## ambient light (windows, a hearth), so its interior shouldn't go dark
## just because a torch isn't lit. Runs every frame right after
## _apply_light_source_overlay() (same cadence, and reuses the same
## screen-space conversion math), rather than being folded into that
## function directly, since _apply_light_source_overlay() early-returns
## in several no-light-source cases that must NOT also skip this.
func _apply_building_interior_overlay() -> void:
	if not is_instance_valid(night_overlay) or not (night_overlay.material is ShaderMaterial):
		return
	var mat: ShaderMaterial = night_overlay.material
	var cloud_mat: ShaderMaterial = cloud_shadow_overlay.material if (is_instance_valid(cloud_shadow_overlay) and cloud_shadow_overlay.material is ShaderMaterial) else null
	var camera: Camera2D = player.get_node("Camera2D") if is_instance_valid(player) else null
	if player_inside_building < 0 or player_inside_building >= buildings.size() or camera == null:
		mat.set_shader_parameter("interior_active", 0.0)
		if cloud_mat != null:
			cloud_mat.set_shader_parameter("interior_active", 0.0)
		return
	var zoom: Vector2 = camera.zoom
	var viewport_size := get_viewport_rect().size
	var viewport_center := viewport_size / 2.0
	var tile_size: Vector2 = Vector2(tile_map.tile_set.tile_size)
	var rect: Rect2i = buildings[player_inside_building]
	var top_left_center: Vector2 = tile_map.map_to_local(rect.position)
	var bottom_right_center: Vector2 = tile_map.map_to_local(rect.position + rect.size - Vector2i(1, 1))
	var world_min: Vector2 = top_left_center - tile_size / 2.0
	var world_max: Vector2 = bottom_right_center + tile_size / 2.0
	var screen_min: Vector2 = viewport_center + (world_min - camera.get_screen_center_position()) * zoom
	var screen_max: Vector2 = viewport_center + (world_max - camera.get_screen_center_position()) * zoom
	mat.set_shader_parameter("interior_rect_min_px", screen_min)
	mat.set_shader_parameter("interior_rect_max_px", screen_max)
	mat.set_shader_parameter("interior_active", 1.0)
	mat.set_shader_parameter("screen_size", viewport_size)
	if cloud_mat != null:
		cloud_mat.set_shader_parameter("interior_rect_min_px", screen_min)
		cloud_mat.set_shader_parameter("interior_rect_max_px", screen_max)
		cloud_mat.set_shader_parameter("interior_active", 1.0)
		cloud_mat.set_shader_parameter("screen_size", viewport_size)

## Per the "add 2 static lamps... come on at night time" request: the
## lamps' own per-frame counterpart to _apply_light_source_overlay()
## just above — sends every lamp's own current on-screen position (the
## camera can pan/zoom independently of any lamp, which never moves in
## world space, unlike the player) plus the shared _lamp_night_factor
## into the same night_overlay_light.gdshader/cloud_shadow_overlay.gdshader
## `lamp_*` uniform array those shaders now carry (see their own
## comments), so a lit lamp punches its own hole in the darkness
## exactly like a carried Lantern does. Runs every frame (the camera
## itself moves continuously with the player, even though the lamps
## don't), same cadence as _apply_light_source_overlay().
func _apply_static_lamp_overlay() -> void:
	if not is_instance_valid(night_overlay):
		return
	if not (night_overlay.material is ShaderMaterial):
		var mat := ShaderMaterial.new()
		mat.shader = NIGHT_OVERLAY_LIGHT_SHADER
		night_overlay.material = mat
	var mat: ShaderMaterial = night_overlay.material
	var cloud_mat: ShaderMaterial = cloud_shadow_overlay.material if (is_instance_valid(cloud_shadow_overlay) and cloud_shadow_overlay.material is ShaderMaterial) else null
	if static_lamp_coords.is_empty() or _lamp_night_factor <= 0.0 or not is_instance_valid(player):
		mat.set_shader_parameter("lamp_count", 0)
		mat.set_shader_parameter("lamp_radius_px", 0.0)
		if cloud_mat != null:
			cloud_mat.set_shader_parameter("lamp_count", 0)
			cloud_mat.set_shader_parameter("lamp_radius_px", 0.0)
		return
	var camera: Camera2D = player.get_node("Camera2D")
	var zoom: Vector2 = camera.zoom if camera != null else Vector2.ONE
	var viewport_size := get_viewport_rect().size
	var viewport_center := viewport_size / 2.0
	## Only the shader's own fixed 4-slot array size limits how many
	## lamps a single map could ever show at once — comfortably above
	## this map's 2.
	var centers: PackedVector2Array = PackedVector2Array()
	for lamp_coords in static_lamp_coords:
		if centers.size() >= 4:
			break
		var lamp_world_center: Vector2 = tile_map.map_to_local(lamp_coords)
		var lamp_screen_pos: Vector2 = viewport_center + (lamp_world_center - camera.get_screen_center_position()) * zoom
		centers.append(lamp_screen_pos)
	var radius_px: float = float(STATIC_LAMP_LIGHT_RADIUS_TILES) * TILE_SIZE * zoom.x
	var softness_px: float = TILE_SIZE * zoom.x * 1.0
	var brightness: float = STATIC_LAMP_LIGHT_BRIGHTNESS * _lamp_night_factor
	mat.set_shader_parameter("lamp_centers_px", centers)
	mat.set_shader_parameter("lamp_count", centers.size())
	mat.set_shader_parameter("lamp_radius_px", radius_px)
	mat.set_shader_parameter("lamp_softness_px", softness_px)
	mat.set_shader_parameter("lamp_brightness", brightness)
	mat.set_shader_parameter("screen_size", viewport_size)
	if cloud_mat != null:
		cloud_mat.set_shader_parameter("lamp_centers_px", centers)
		cloud_mat.set_shader_parameter("lamp_count", centers.size())
		cloud_mat.set_shader_parameter("lamp_radius_px", radius_px)
		cloud_mat.set_shader_parameter("lamp_softness_px", softness_px)
		cloud_mat.set_shader_parameter("screen_size", viewport_size)

## Per the "secondary lights should remove both primary and secondary
## shadows within their light LOS" request: called fresh from the very
## top of BOTH _apply_light_source_secondary_shadows() and _apply_
## static_lamp_secondary_shadows() below (rather than once from
## _process()) so either one is self-sufficient and always sees an
## up-to-date snapshot no matter which order they run in, or whether
## they're invoked directly (as the test suites do) instead of through
## the normal per-frame flow — recomputing this is cheap (bounded
## tile-radius loops, same cost _light_visible_tiles() already is
## elsewhere) so doing it twice a frame is a non-issue. Lets each
## function cross-check every OTHER active light's own LOS-visible tile
## set and suppress its own secondary shadow wherever a different light
## also reaches that tile — the real-world approximation of "a second
## light source fills in what would otherwise be a shadow cast by the
## first." A light never suppresses its OWN shadow this way (that would
## erase every secondary shadow outright) — only a genuinely different
## light's reach cancels it. Deliberately its own separate pass rather
## than reusing _update_shadow_angles()'s own `lit_tiles` (event-driven,
## primary-shadow-only, and merged into one combined set rather than
## kept per-light) — this needs its own per-light breakdown.
func _recompute_secondary_light_lit_tiles() -> void:
	_player_secondary_lit_tiles = {}
	_lamp_secondary_lit_tiles = {}
	_player_secondary_shadow_range_tiles = 0
	if _light_source_effective() and is_instance_valid(player):
		var pc := _party_light_bearer()
		var radius_tiles: int = pc.get_active_light_radius_tiles() if pc != null else 0
		## Per the "secondary shadows seem to only go 10 yards even in
		## full light...2nd light should dispel shadows beyond 10 yards
		## if it reaches that far" follow-up: this tracks how far the
		## player's own light GENUINELY reaches for "is this tile lit by
		## some light" purposes — redarkening exemption (_tile_needs_
		## redarkening()) AND letting this light cross-suppress another
		## light's shadow/wall-polygon/primary-shadow at range (see the
		## _player_secondary_shadow_range_tiles usage below and in
		## _update_shadow_angles()). Deliberately the light's own TRUE
		## radius_tiles now, not the much shorter SECONDARY_LIGHT_SHADOW_
		## MAX_RANGE_TILES cap — that cap only ever existed to keep
		## individual shadow-casting BLOB sprites (tree/person
		## silhouettes, wall polygons) to a believable close range (see
		## its own comment); reusing it here meant a strong Lantern's own
		## true 20-tile reveal circle had NO occlusion/cross-suppression
		## logic at all past 8 tiles — a wall's redarkened "shadow" just
		## stopped dead at that radius instead of continuing out to
		## wherever the light itself stops actually reaching, and a
		## bright lantern couldn't dispel another light's shadow beyond
		## that same short cap even where its own true glow reached.
		if radius_tiles > 0:
			## Per the "light bleeding through the edges... extend
			## secondary shadow beyond the circle of the light" follow-up:
			## shrunk by SECONDARY_SHADOW_EDGE_MARGIN_TILES so a tile only
			## counts as genuinely "lit by this light" (exempt from its
			## own redarkening, or able to cross-suppress a DIFFERENT
			## light's shadow) once it's solidly inside this light's core
			## — not just barely grazed by the last ~1.5 tiles of its own
			## soft fade-out, where the shader itself is already most of
			## the way back to black. See that constant's own comment.
			var lit_radius_tiles: int = max(radius_tiles - SECONDARY_SHADOW_EDGE_MARGIN_TILES, 0)
			_player_secondary_lit_tiles = _light_visible_tiles(player.grid_pos, lit_radius_tiles)
			_player_secondary_shadow_range_tiles = lit_radius_tiles
	## Mirrors _apply_static_lamp_secondary_shadows()'s own "only once
	## actually lit" gate (LAMP_GLOW_FADE_START) so an unlit-by-day lamp
	## never suppresses anything.
	var night_amount: float = GameState.get_night_darkness() / GameState.NIGHT_DARKNESS_MAX
	var lamp_lit: bool = night_amount > LAMP_GLOW_FADE_START
	if lamp_lit:
		for lamp_index in range(static_lamp_coords.size()):
			_lamp_secondary_lit_tiles[lamp_index] = _light_visible_tiles(static_lamp_coords[lamp_index], LAMP_SECONDARY_LIT_RANGE_TILES)

## Per the follow-up request ("add secondary shadows for light
## sources. objects with no line of sight or that cast shadows already
## should all be included"): a SECOND, independent shadow layer for
## the party's carried light source (see _party_light_bearer()), on
## top of the sun/moon sweep _update_shadow_angles() already handles.
## Unlike that system (event-driven — tile-step, waiting, etc.), this
## runs every frame from _process(), the same cadence as
## _apply_light_source_overlay() itself right above, since the light
## genuinely moves continuously with the player rather than sweeping
## on the slow game-clock scale the sun/moon do.
##
## Deliberately much simpler than the primary system's per-type
## handling (tree canopy-clip shaders, fence shear pieces, wall
## polygon extrusion+union): every eligible object
## (SECONDARY_LIGHT_SHADOW_CHARS) gets one plain rotated/scaled
## Sprite2D — SHADOW_TEXTURE_TREE for an actual tree, and
## SHADOW_TEXTURE_PERSON (already a soft, rotation-friendly blob)
## standing in for every other solid object, since shadow_wall.png's
## own shape is purpose-built for the polygon-extrusion approach and
## reads oddly at an arbitrary rotation. Direction radiates OUTWARD
## from the light for each object individually (unlike the sun/moon's
## single shared `dir` for the whole map), which is exactly what makes
## this read as a genuine point-light shadow rather than another
## ambient sweep. Scoped to a small tile-radius box around the player
## (the light's own radius_tiles) so this never has to scan the whole
## map's tile_chars dictionary every frame — on a typical local map
## that's a handful to a couple dozen objects, not the map's full
## few-hundred-tile shadow-casting roster.
func _apply_light_source_secondary_shadows() -> void:
	if not is_instance_valid(light_shadow_container):
		return
	## Per the "same darkness as normal night darkness outside the light"
	## and "stop stacking shadows" requests: light_shadow_container is a
	## CanvasGroup (see _rebuild_shadows()'s own comment) whose
	## self_modulate supplies the group's ENTIRE translucency exactly
	## once for its whole flattened contents — set fresh every frame so
	## it always tracks the current ambient tint/darkness, same as every
	## other per-frame read of night_overlay.color in this file.
	## Per the later "darker than normal night darkness" report: this
	## group sits ON TOP of NightOverlay's own reveal shader, which is
	## already showing some residual brightness right where these
	## shadows land (they're always within the player's OWN light,
	## after all) — using the flat ambient alpha here on top of that
	## would stack past it (see _compensate_alpha_for_reveal()'s own
	## comment). Compensated using this light's own brightness constant
	## as the reveal estimate, since a blob/wall shadow always sits well
	## inside its own casting light's core, not out at its fading rim.
	if is_instance_valid(night_overlay):
		var own_brightness: float = 0.0
		if _light_source_effective():
			var bearer := _party_light_bearer()
			if bearer != null:
				own_brightness = _active_light_brightness(bearer)
		var compensated_alpha: float = _compensate_alpha_for_reveal(own_brightness, night_overlay.color.a)
		light_shadow_container.self_modulate = Color(night_overlay.color.r, night_overlay.color.g, night_overlay.color.b, compensated_alpha)
	_recompute_secondary_light_lit_tiles()
	var used_this_frame: Dictionary = {}
	## Per the request ("the primary and secondary shadow buildings cast
	## should come from the wall edges and be merged into one solid
	## shadow"): every LIGHT_BLOCKING_WALL_CHARS tile (walls + doors —
	## see that constant's own comment) caught by the loop below is
	## diverted in here instead of getting its own little person-blob
	## sprite — see the merged-polygon pass right after the loop.
	var wall_coords_in_range: Dictionary = {}
	var light_world_pos_for_walls: Vector2 = Vector2.ZERO
	## Per the "should only light up things with LOS, everything out of
	## LOS should remain normal night darkness" request: every tile in
	## range that fails _has_line_of_sight() from the light's own tile —
	## refreshed fresh each call, read back by _refresh_light_occlusion()
	## (called once per frame from _process(), after this and the static
	## lamps' own equivalent below have both run) to re-cover exactly
	## those tiles' own on-screen area with NightOverlay's current
	## darkness, undoing the reveal shader's blind, wall-unaware circular
	## falloff there.
	_player_light_blocked_tiles.clear()
	if _light_source_effective() and is_instance_valid(player):
		var pc := _party_light_bearer()
		var radius_tiles: int = pc.get_active_light_radius_tiles() if pc != null else 0
		## Per the "secondary shadows seem to only go 10 yards even in
		## full light...should continue to the edge of the map and merge
		## cleanly with the dark outside the light circle" follow-up: the
		## OCCLUSION sweep (which tiles get LOS-checked and, if blocked,
		## redarkened via _player_light_blocked_tiles) now covers the
		## light's own TRUE reveal radius, not the much shorter
		## SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES cap — that cap only
		## ever existed to keep individual shadow-casting BLOB sprites
		## (tree/person silhouettes, wall polygons) to a believable
		## close range (see its own comment); reusing it for occlusion
		## meant a strong Lantern's own true 20-tile reveal circle had NO
		## wall-blocking logic at all past 8 tiles, so a wall's "shadow"
		## just stopped dead at that radius instead of continuing out to
		## wherever the light itself stops actually reaching — a visible
		## seam, not a clean merge into the ambient dark beyond.
		## blob_shadow_range_tiles below keeps the ORIGINAL short cap for
		## the actual shadow-sprite-casting decision a few lines down —
		## LOS beyond it is still checked (for occlusion), just no blob/
		## wall-shadow polygon gets drawn that far out.
		var occlusion_range_tiles: int = radius_tiles
		var blob_shadow_range_tiles: int = min(radius_tiles, SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES)
		if occlusion_range_tiles > 0:
			## Deliberately player.grid_pos + tile_map.map_to_local()
			## throughout, NOT player.global_position — every shadow
			## sprite here is a child of shadow_container/
			## light_shadow_container, which already share tile_map's own
			## local coordinate space (see how tree/wall shadows above
			## position themselves via plain tile_map.map_to_local()
			## results, no camera/viewport conversion at all) — unlike
			## _apply_light_source_overlay() right above, which genuinely
			## needs the screen-space conversion since it's driving a
			## full-screen shader uniform instead of a Node2D transform.
			var light_world_pos: Vector2 = tile_map.map_to_local(player.grid_pos)
			light_world_pos_for_walls = light_world_pos
			var tile_size: Vector2 = Vector2(tile_map.tile_set.tile_size)
			for dy in range(-occlusion_range_tiles, occlusion_range_tiles + 1):
				for dx in range(-occlusion_range_tiles, occlusion_range_tiles + 1):
					var coords: Vector2i = player.grid_pos + Vector2i(dx, dy)
					if coords == player.grid_pos:
						continue
					var tile_center: Vector2 = tile_map.map_to_local(coords)
					var offset_vec: Vector2 = tile_center - light_world_pos
					var dist_tiles: float = offset_vec.length() / max(tile_size.x, 1.0)
					if dist_tiles > float(occlusion_range_tiles):
						continue
					## Per the LOS request: a tile the light can't actually
					## see past a wall to reach neither receives a light-
					## shadow of its own here NOR counts as "lit" for the
					## overlay reveal — tracked in _player_light_blocked_
					## tiles regardless of this tile's own character (a
					## plain patch of grass behind a wall needs re-
					## darkening exactly as much as an object would).
					if not _has_line_of_sight(player.grid_pos, coords):
						_player_light_blocked_tiles.append(coords)
						continue
					## Per the same follow-up: LOS is genuinely clear all
					## the way out to occlusion_range_tiles now, but an
					## actual shadow-casting BLOB/wall-shadow-polygon still
					## only draws within the shorter blob_shadow_range_
					## tiles — see this function's own top-of-body comment.
					if dist_tiles > float(blob_shadow_range_tiles):
						continue
					var ch: String = tile_chars.get(coords, "")
					if ch == "" or not SECONDARY_LIGHT_SHADOW_CHARS.has(ch):
						continue
					if ch in LIGHT_BLOCKING_WALL_CHARS:
						## Per the "secondary lights should remove both
						## primary and secondary shadows within their light
						## LOS" request: wall tiles are always collected
						## here regardless of any other light's own reach —
						## suppressing the wall's own SOURCE tile wouldn't
						## touch the shadow it casts anyway, since that
						## shadow lands on GROUND tiles away from the wall,
						## not on the wall's own tile. The actual suppression
						## for wall shadows happens further down, where the
						## merged wall-shadow POLYGON itself gets clipped
						## against every other active light's own disc (see
						## the comment just above that clip call).
						wall_coords_in_range[coords] = ch
						continue
					## Per the same request: a tile the player's own light
					## would otherwise shadow here is left alone if some
					## OTHER active light (any lit static lamp) also has LOS
					## on it — that lamp's own light fills in what would
					## otherwise be a shadow cast by the player's torch,
					## exactly like the sun/moon's primary shadow already
					## gets suppressed under a light.
					var lit_by_another_light := false
					for lamp_index in _lamp_secondary_lit_tiles:
						if _lamp_secondary_lit_tiles[lamp_index].has(coords):
							lit_by_another_light = true
							break
					if lit_by_another_light:
						continue
					var sprite: Sprite2D = _light_shadow_sprites.get(coords)
					if sprite == null:
						sprite = Sprite2D.new()
						sprite.centered = false
						sprite.name = "LightShadow_%d_%d" % [coords.x, coords.y]
						light_shadow_container.add_child(sprite)
						_light_shadow_sprites[coords] = sprite
					var is_tree: bool = ch == "T"
					sprite.texture = SHADOW_TEXTURE_TREE if is_tree else SHADOW_TEXTURE_PERSON
					## Per the TILE_SIZE 16->64 upscale: TREE_SHADOW_PIVOT_PX/
					## TREE_TILE_BASE_PX are already in final scale (shadow_tree.png
					## is the tree's own real silhouette, recolored, on the same
					## bigger-than-one-tile canvas as the canopy overlay — see
					## TREE_OVERLAY_ANCHOR_PX's own comment). PERSON_SHADOW_PIVOT_PX/ANCHOR_PX
					## deliberately stayed native (see their own comments) since
					## _make_person_shadow()'s primary shadow inherits its 4x
					## boost from its scaled NPC/player parent — but THIS sprite
					## has no such parent (it's a direct child of
					## light_shadow_container), so the person case needs FX_SCALE
					## applied explicitly, right here, instead.
					var pivot_px: Vector2 = TREE_SHADOW_PIVOT_PX if is_tree else PERSON_SHADOW_PIVOT_PX * FX_SCALE
					sprite.offset = -pivot_px
					var base_px: Vector2 = TREE_TILE_BASE_PX if is_tree else PERSON_SHADOW_ANCHOR_PX * FX_SCALE
					sprite.position = tile_center + (base_px - tile_size / 2.0)
					## Guards the (extremely unlikely, since coords ==
					## player.grid_pos is already skipped above) exact-
					## overlap case where offset_vec would otherwise
					## normalize to a NaN/zero vector.
					var dir_vec: Vector2 = offset_vec if offset_vec.length() > 0.5 else Vector2(0.0, 1.0)
					dir_vec = dir_vec.normalized()
					## Same "-90°/-PI/2 natural up" correction the sun/moon
					## sweep already uses (see _update_shadow_angles()'s
					## own comment) — every shadow texture here draws
					## pointing "up," away from its own base pivot, before
					## rotation.
					sprite.rotation = dir_vec.angle() + PI / 2.0
					## Closer to the light = longer, sharper shadow;
					## fading out toward the light's own outer radius,
					## where it's about to go dark anyway regardless of
					## this shadow.
					var closeness: float = clamp(1.0 - dist_tiles / float(blob_shadow_range_tiles), 0.0, 1.0)
					var length_scale: float = lerp(SECONDARY_LIGHT_SHADOW_MIN_SCALE, SECONDARY_LIGHT_SHADOW_MAX_SCALE, closeness)
					## Tree branch matches shadow_tree.png's own pixels 1:1 (no
					## extra multiplier needed — shadow_tree.png is now the
					## tree's own real silhouette on the same 64x64 canvas as
					## the tree art itself, so this scale is calibrated fresh
					## against the current tree size, not carried over from
					## an old, differently-sized shadow texture). Person
					## branch has no scaled parent here (see the pivot_px/
					## base_px comment just above) so FX_SCALE is applied to
					## both axes directly instead.
					sprite.scale = Vector2(0.7, length_scale) if is_tree else Vector2(1.3 * FX_SCALE, length_scale * FX_SCALE)
					## Per the "stop stacking shadows (making them darker)"
					## request: drawn fully OPAQUE here — light_shadow_
					## container is now a CanvasGroup (see its own comment
					## in _rebuild_shadows()) whose self_modulate (set to
					## night_overlay.color a few lines below) supplies the
					## actual ambient-matching darkness exactly once for
					## the whole flattened group, so overlapping shadows no
					## longer stack into a darker double-shadow patch.
					sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
					sprite.visible = true
					used_this_frame[coords] = true
	for coords in _light_shadow_sprites:
		if not used_this_frame.has(coords):
			_light_shadow_sprites[coords].visible = false

	## Per the request ("the primary and secondary shadow buildings cast
	## should come from the wall edges and be merged into one solid
	## shadow"): every wall/building run caught above is drawn as ONE
	## flat-fill polygon per contiguous run, extruded away from the
	## player's own position — reusing the exact same
	## sweep+clip+union pipeline _update_shadow_angles() already built
	## for the sun/moon wall shadow (_find_wall_shadow_rects(),
	## _swept_clip_piece(), _union_polygon_into()), just with a
	## per-run direction (away from the torch) instead of one shared
	## sun/moon direction, and a per-run length that shrinks with
	## distance from the light the same way the tree/person blob
	## shadows above already fade with distance. Deliberately a single
	## flat fill (color read fresh from night_overlay.color, same as the
	## tree/person blobs — see the comment above SECONDARY_LIGHT_SHADOW_
	## MIN_SCALE) with no per-run alpha fade — these can merge together
	## at a corner and a Polygon2D can only carry one uniform color
	## anyway.
	var wall_raw_pieces: Array = []
	if not wall_coords_in_range.is_empty():
		var tile_size2: Vector2 = Vector2(tile_map.tile_set.tile_size)
		## Per the "remove shadows inside buildings" request: a torch
		## carried inside a building can throw a nearby wall's shadow
		## onto that same building's own interior floor exactly the way
		## the sun/moon can (see the comment above _update_shadow_angles()'s
		## own building_polys) — clipped out below for the same reason.
		var building_polys2: Array = _building_world_polys(tile_size2)
		## Per the "secondary lights should remove both primary and
		## secondary shadows within their light LOS" request: unlike the
		## per-tile tree/person blobs above (suppressed by checking their
		## own tile's LOS membership directly), a WALL shadow is a single
		## merged polygon whose landing footprint can sit well away from
		## the wall tile that sourced it — so excluding wall tiles from
		## wall_coords_in_range wouldn't actually clip where the shadow
		## falls. Instead, mirroring exactly how _update_shadow_angles()
		## already clips the PRIMARY wall shadow against every active
		## light's own disc, the piece built below gets clipped against
		## every OTHER lit lamp's own disc (never the player's own — this
		## is the player's torch shadow) right where the primary system
		## does its own clip.
		var other_light_discs: Array = []
		for lamp_index in _lamp_secondary_lit_tiles:
			var lamp_world_pos2: Vector2 = tile_map.map_to_local(static_lamp_coords[lamp_index])
			other_light_discs.append({"pos": lamp_world_pos2, "radius": float(LAMP_SECONDARY_LIT_RANGE_TILES) * tile_size2.x})
		for rect in _find_wall_shadow_rects(wall_coords_in_range):
			var top_left_center: Vector2 = tile_map.map_to_local(rect.position)
			var bottom_right_center: Vector2 = tile_map.map_to_local(rect.position + rect.size - Vector2i(1, 1))
			var x_left: float = top_left_center.x - tile_size2.x / 2.0
			var y_top: float = top_left_center.y - tile_size2.y / 2.0
			var x_right: float = bottom_right_center.x + tile_size2.x / 2.0
			var y_bottom: float = bottom_right_center.y + tile_size2.y / 2.0
			## Per the "make secondary shadows act in a similar way from
			## any side of the buildings" request: a carried light can
			## sit anywhere, so a torch's shadow of a back (north) wall
			## can sweep in any direction — not just the sun/moon's
			## fixed southward bias — but the SAME visual mismatch
			## applies whenever it sweeps sideways: the tall roof sprite
			## extends further north than the wall's own grid row, so a
			## full-rectangle sweep can still drag along that row's own
			## top edge, up near the roofline, exactly like the primary
			## sun/moon shadow did before its own fix. Reusing the exact
			## same _is_building_north_wall_run() scoping keeps the two
			## shadow systems' back-wall behaviour identical, while every
			## other side (front/west/east) stays on the full rectangle
			## in both systems, same as before.
			var footprint: PackedVector2Array
			if rect.size.y == 1 and _is_building_north_wall_run(rect):
				footprint = PackedVector2Array([
					Vector2(x_left, y_bottom),
					Vector2(x_right, y_bottom),
					Vector2(x_right, y_bottom),
					Vector2(x_left, y_bottom),
				])
			else:
				footprint = PackedVector2Array([
					Vector2(x_left, y_top),
					Vector2(x_right, y_top),
					Vector2(x_right, y_bottom),
					Vector2(x_left, y_bottom),
				])
			var rect_center: Vector2 = (top_left_center + bottom_right_center) / 2.0
			var offset_vec: Vector2 = rect_center - light_world_pos_for_walls
			var dist_tiles: float = offset_vec.length() / max(tile_size2.x, 1.0)
			var dir_vec: Vector2 = offset_vec.normalized() if offset_vec.length() > 0.5 else Vector2(0.0, 1.0)
			var closeness: float = clamp(1.0 - dist_tiles / float(SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES), 0.0, 1.0)
			var length_scale: float = lerp(SECONDARY_LIGHT_WALL_SHADOW_MIN_SCALE, SECONDARY_LIGHT_WALL_SHADOW_MAX_SCALE, closeness)
			var extension: Vector2 = dir_vec * tile_size2.y * length_scale
			var piece: PackedVector2Array = _swept_clip_piece(footprint, extension)
			for surviving_piece in _clip_piece_against_buildings(piece, building_polys2):
				for final_piece in _clip_piece_against_light_discs(surviving_piece, other_light_discs):
					wall_raw_pieces.append(final_piece)
	var merged_wall_pieces: Array = []
	for piece in wall_raw_pieces:
		merged_wall_pieces = _union_polygon_into(merged_wall_pieces, piece)
	while _light_wall_shadow_nodes.size() < merged_wall_pieces.size():
		var wall_node := Polygon2D.new()
		wall_node.name = "LightWallShadow_%d" % _light_wall_shadow_nodes.size()
		light_shadow_container.add_child(wall_node)
		_light_wall_shadow_nodes.append(wall_node)
	for i in range(_light_wall_shadow_nodes.size()):
		if i < merged_wall_pieces.size():
			## Per the "stop stacking shadows" request: opaque, same
			## reasoning as the tree/person blob sprites above — light_
			## shadow_container's own self_modulate (a CanvasGroup) is
			## what actually supplies the ambient-matching darkness now.
			_light_wall_shadow_nodes[i].color = Color(1.0, 1.0, 1.0, 1.0)
			_light_wall_shadow_nodes[i].polygon = merged_wall_pieces[i]
		else:
			_light_wall_shadow_nodes[i].polygon = PackedVector2Array()

## Per the "add 2 static lamps in the village... these should come on at
## night time and cast secondary shadows around them" request: one
## independent pass per lamp in static_lamp_coords, structurally the
## same per-tile-blob + merged-wall-run pipeline
## _apply_light_source_secondary_shadows() just built above (same
## SECONDARY_LIGHT_SHADOW_CHARS eligibility, same _find_wall_shadow_
## rects()/_swept_clip_piece()/_clip_piece_against_buildings()/
## _union_polygon_into() pipeline, same _is_building_north_wall_run()
## footprint scoping) — just sourced from a fixed lamp position instead
## of the player's own carried light, and using this feature's own
## separate pooled structures (_static_lamp_tile_shadow_sprites/
## _static_lamp_wall_shadow_nodes, keyed by lamp index) so the existing
## player-only _light_shadow_sprites/_light_wall_shadow_nodes — and the
## tests that key into them directly — are left completely untouched.
func _apply_static_lamp_secondary_shadows() -> void:
	if not is_instance_valid(_static_lamp_shadow_container) or static_lamp_coords.is_empty():
		return
	## Per the "same darkness as normal night darkness outside the light"
	## and "stop stacking shadows" requests — see the identical comment
	## in _apply_light_source_secondary_shadows() above. Per the later
	## "darker than normal night darkness" report, compensated against
	## a lamp's own brightness constant the same way — see that
	## function's own comment for the full reasoning.
	## A lamp only throws shadows once it's actually lit — reusing
	## LAMP_GLOW_FADE_START as that same cutoff (see its own comment).
	var night_amount: float = GameState.get_night_darkness() / GameState.NIGHT_DARKNESS_MAX
	var lamp_lit: bool = night_amount > LAMP_GLOW_FADE_START
	if is_instance_valid(night_overlay):
		var lamp_reveal: float = STATIC_LAMP_LIGHT_BRIGHTNESS * _lamp_night_factor if lamp_lit else 0.0
		var compensated_alpha2: float = _compensate_alpha_for_reveal(lamp_reveal, night_overlay.color.a)
		_static_lamp_shadow_container.self_modulate = Color(night_overlay.color.r, night_overlay.color.g, night_overlay.color.b, compensated_alpha2)
	_recompute_secondary_light_lit_tiles()
	var tile_size: Vector2 = Vector2(tile_map.tile_set.tile_size)
	var building_polys: Array = _building_world_polys(tile_size)
	for lamp_index in range(static_lamp_coords.size()):
		var lamp_coords: Vector2i = static_lamp_coords[lamp_index]
		var tile_sprites: Dictionary = _static_lamp_tile_shadow_sprites.get(lamp_index, {})
		var used_this_frame: Dictionary = {}
		var wall_coords_in_range: Dictionary = {}
		var light_world_pos: Vector2 = tile_map.map_to_local(lamp_coords)
		## Per the "should only light up things with LOS" request — see
		## _player_light_blocked_tiles' own comment for the full picture;
		## this is that same bookkeeping, per-lamp, keyed by lamp index so
		## _refresh_light_occlusion() can re-darken each lamp's own
		## blocked tiles independently.
		var blocked_tiles: Array = []
		if lamp_lit:
			for dy in range(-STATIC_LAMP_SHADOW_RANGE_TILES, STATIC_LAMP_SHADOW_RANGE_TILES + 1):
				for dx in range(-STATIC_LAMP_SHADOW_RANGE_TILES, STATIC_LAMP_SHADOW_RANGE_TILES + 1):
					var coords: Vector2i = lamp_coords + Vector2i(dx, dy)
					if coords == lamp_coords:
						continue
					var tile_center: Vector2 = tile_map.map_to_local(coords)
					var offset_vec: Vector2 = tile_center - light_world_pos
					var dist_tiles: float = offset_vec.length() / max(tile_size.x, 1.0)
					if dist_tiles > float(STATIC_LAMP_SHADOW_RANGE_TILES):
						continue
					if not _has_line_of_sight(lamp_coords, coords):
						blocked_tiles.append(coords)
						continue
					var ch: String = tile_chars.get(coords, "")
					if ch == "" or not SECONDARY_LIGHT_SHADOW_CHARS.has(ch):
						continue
					if ch in LIGHT_BLOCKING_WALL_CHARS:
						## Per the "secondary lights should remove both
						## primary and secondary shadows within their light
						## LOS" request: wall tiles are always collected
						## here — suppressing the wall's own SOURCE tile
						## wouldn't touch the shadow it casts, since that
						## shadow lands on GROUND tiles away from the wall.
						## The actual suppression for wall shadows happens
						## further down, where this lamp's own merged
						## wall-shadow polygon gets clipped against every
						## OTHER active light's own disc (see the comment
						## just above that clip call).
						wall_coords_in_range[coords] = ch
						continue
					## Per the same request: this lamp's own shadow
					## contribution here is suppressed if the player's own
					## carried light OR any OTHER lit lamp (never this same
					## lamp — that would erase every shadow this lamp ever
					## casts) also has LOS on this tile — that other light's
					## own illumination fills in what would otherwise be a
					## shadow cast by this lamp.
					var lit_by_another_light: bool = _player_secondary_lit_tiles.has(coords)
					if not lit_by_another_light:
						for other_index in _lamp_secondary_lit_tiles:
							if other_index == lamp_index:
								continue
							if _lamp_secondary_lit_tiles[other_index].has(coords):
								lit_by_another_light = true
								break
					if lit_by_another_light:
						continue
					var sprite: Sprite2D = tile_sprites.get(coords)
					if sprite == null:
						sprite = Sprite2D.new()
						sprite.centered = false
						sprite.name = "StaticLampShadow_%d_%d_%d" % [lamp_index, coords.x, coords.y]
						_static_lamp_shadow_container.add_child(sprite)
						tile_sprites[coords] = sprite
					var is_tree: bool = ch == "T"
					sprite.texture = SHADOW_TEXTURE_TREE if is_tree else SHADOW_TEXTURE_PERSON
					var pivot_px: Vector2 = TREE_SHADOW_PIVOT_PX if is_tree else PERSON_SHADOW_PIVOT_PX * FX_SCALE
					sprite.offset = -pivot_px
					var base_px: Vector2 = TREE_TILE_BASE_PX if is_tree else PERSON_SHADOW_ANCHOR_PX * FX_SCALE
					sprite.position = tile_center + (base_px - tile_size / 2.0)
					var dir_vec: Vector2 = offset_vec if offset_vec.length() > 0.5 else Vector2(0.0, 1.0)
					dir_vec = dir_vec.normalized()
					sprite.rotation = dir_vec.angle() + PI / 2.0
					var closeness: float = clamp(1.0 - dist_tiles / float(STATIC_LAMP_SHADOW_RANGE_TILES), 0.0, 1.0)
					var length_scale: float = lerp(SECONDARY_LIGHT_SHADOW_MIN_SCALE, SECONDARY_LIGHT_SHADOW_MAX_SCALE, closeness)
					sprite.scale = Vector2(0.7, length_scale) if is_tree else Vector2(1.3 * FX_SCALE, length_scale * FX_SCALE)
					## Per the "stop stacking shadows" request — see the
					## identical comment in _apply_light_source_secondary_
					## shadows() above.
					sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
					sprite.visible = true
					used_this_frame[coords] = true
		for coords in tile_sprites:
			if not used_this_frame.has(coords):
				tile_sprites[coords].visible = false
		_static_lamp_tile_shadow_sprites[lamp_index] = tile_sprites

		var wall_raw_pieces: Array = []
		if not wall_coords_in_range.is_empty():
			## Per the "secondary lights should remove both primary and
			## secondary shadows within their light LOS" request: this
			## lamp's own merged wall-shadow polygon gets clipped against
			## every OTHER active light's own disc (the player's carried
			## light, if effective, plus every OTHER lit lamp — never this
			## same lamp) — see the identical comment in
			## _apply_light_source_secondary_shadows() for why this has to
			## happen against the final polygon rather than by excluding
			## wall SOURCE tiles.
			var other_light_discs: Array = []
			if _player_secondary_shadow_range_tiles > 0 and is_instance_valid(player):
				other_light_discs.append({"pos": tile_map.map_to_local(player.grid_pos), "radius": float(_player_secondary_shadow_range_tiles) * tile_size.x})
			for other_index in _lamp_secondary_lit_tiles:
				if other_index == lamp_index:
					continue
				other_light_discs.append({"pos": tile_map.map_to_local(static_lamp_coords[other_index]), "radius": float(LAMP_SECONDARY_LIT_RANGE_TILES) * tile_size.x})
			for rect in _find_wall_shadow_rects(wall_coords_in_range):
				var top_left_center: Vector2 = tile_map.map_to_local(rect.position)
				var bottom_right_center: Vector2 = tile_map.map_to_local(rect.position + rect.size - Vector2i(1, 1))
				var x_left: float = top_left_center.x - tile_size.x / 2.0
				var y_top: float = top_left_center.y - tile_size.y / 2.0
				var x_right: float = bottom_right_center.x + tile_size.x / 2.0
				var y_bottom: float = bottom_right_center.y + tile_size.y / 2.0
				var footprint: PackedVector2Array
				if rect.size.y == 1 and _is_building_north_wall_run(rect):
					footprint = PackedVector2Array([
						Vector2(x_left, y_bottom),
						Vector2(x_right, y_bottom),
						Vector2(x_right, y_bottom),
						Vector2(x_left, y_bottom),
					])
				else:
					footprint = PackedVector2Array([
						Vector2(x_left, y_top),
						Vector2(x_right, y_top),
						Vector2(x_right, y_bottom),
						Vector2(x_left, y_bottom),
					])
				var rect_center: Vector2 = (top_left_center + bottom_right_center) / 2.0
				var offset_vec: Vector2 = rect_center - light_world_pos
				var dist_tiles: float = offset_vec.length() / max(tile_size.x, 1.0)
				var dir_vec: Vector2 = offset_vec.normalized() if offset_vec.length() > 0.5 else Vector2(0.0, 1.0)
				var closeness: float = clamp(1.0 - dist_tiles / float(STATIC_LAMP_SHADOW_RANGE_TILES), 0.0, 1.0)
				var length_scale: float = lerp(SECONDARY_LIGHT_WALL_SHADOW_MIN_SCALE, SECONDARY_LIGHT_WALL_SHADOW_MAX_SCALE, closeness)
				var extension: Vector2 = dir_vec * tile_size.y * length_scale
				var piece: PackedVector2Array = _swept_clip_piece(footprint, extension)
				for surviving_piece in _clip_piece_against_buildings(piece, building_polys):
					for final_piece in _clip_piece_against_light_discs(surviving_piece, other_light_discs):
						wall_raw_pieces.append(final_piece)
		var merged_wall_pieces: Array = []
		for piece in wall_raw_pieces:
			merged_wall_pieces = _union_polygon_into(merged_wall_pieces, piece)
		var wall_nodes: Array = _static_lamp_wall_shadow_nodes.get(lamp_index, [])
		while wall_nodes.size() < merged_wall_pieces.size():
			var wall_node := Polygon2D.new()
			wall_node.name = "StaticLampWallShadow_%d_%d" % [lamp_index, wall_nodes.size()]
			_static_lamp_shadow_container.add_child(wall_node)
			wall_nodes.append(wall_node)
		for i in range(wall_nodes.size()):
			if i < merged_wall_pieces.size():
				## Per the "stop stacking shadows" request — see the
				## identical comment in _apply_light_source_secondary_
				## shadows() above.
				wall_nodes[i].color = Color(1.0, 1.0, 1.0, 1.0)
				wall_nodes[i].polygon = merged_wall_pieces[i]
			else:
				wall_nodes[i].polygon = PackedVector2Array()
		_static_lamp_wall_shadow_nodes[lamp_index] = wall_nodes
		_static_lamp_blocked_tiles[lamp_index] = blocked_tiles

## Per the "should only light up things with LOS, everything out of LOS
## should remain normal night darkness" request: night_overlay_light.
## gdshader's own reveal (see _apply_light_source_overlay()/_apply_
## static_lamp_overlay()) is a blind circular falloff with no concept of
## walls — on its own it would happily brighten ground on the far side
## of a wall a lamp/lantern is standing right next to. This redraws
## NightOverlay's own CURRENT colour (pulse and all, since it just reads
## `night_overlay.color` fresh every call) as a plain screen-space quad
## over every tile _apply_light_source_secondary_shadows()/_apply_
## static_lamp_secondary_shadows() just marked blocked this frame,
## painting the darkness back on top of the shader's own reveal exactly
## where line-of-sight says it shouldn't have reached in the first
## place. Parented under cloud_shadow_overlay (added once, lazily) so it
## draws after BOTH dark overlays (see Overworld.tscn's own NightOverlay
## → CloudShadowOverlay sibling order) but still before every real HUD
## element declared later under UI (InfoBar, HudLabel, DialogueLabel,
## etc.) — a child always draws immediately after its own parent and
## before that parent's later siblings, so this stays safely under the
## HUD regardless of exactly how many quads it needs this frame. Pooled/
## reused the same way every other per-frame sprite set in this file is
## (_light_shadow_sprites and friends) rather than freed and recreated.
## True when SOME active secondary light — the player's own carried
## light, or any lit static lamp — genuinely has LOS on `coords` within
## its own reach. Reuses the exact same per-light LOS dictionaries
## _recompute_secondary_light_lit_tiles() refreshes each frame (already
## relied on to cross-suppress one light's secondary shadow with
## another's own reach) so "is this tile lit by ANY light" always means
## the same thing everywhere it's asked, including inside
## _refresh_light_occlusion() right below.
func _tile_lit_by_any_secondary_light(coords: Vector2i) -> bool:
	if _player_secondary_lit_tiles.has(coords):
		return true
	for lamp_index in _lamp_secondary_lit_tiles:
		if _lamp_secondary_lit_tiles[lamp_index].has(coords):
			return true
	return false

## True when `coords` genuinely deserves a redarkening quad — i.e. no
## active light reaches it AND it's not inside whichever ONE building
## currently has its roof hidden (player_inside_building). Per the
## "always light up the inside of building with no shadows" request:
## _apply_building_interior_overlay() already keeps that building's own
## NightOverlay/CloudShadowOverlay hole open unconditionally (a real
## building has its own ambient light, independent of any carried
## torch), so a redarkening quad on top of that hole would otherwise
## still paint darkness right back over it whenever some light's own
## LOS genuinely fails to reach a corner of it.
func _tile_needs_redarkening(coords: Vector2i) -> bool:
	if player_inside_building >= 0 and player_inside_building < buildings.size():
		if buildings[player_inside_building].has_point(coords):
			return false
	return not _tile_lit_by_any_secondary_light(coords)

## Called once per frame from _process(), after both secondary-shadow
## passes above have refreshed their own blocked-tile lists for this
## frame.
## Per the "secondary shadow still looks darker the normal night
## darkness, and does not blend perfectly" report: NightOverlay/
## CloudShadowOverlay's own reveal shader is purely DISTANCE-based —
## it has no idea a wall is blocking LOS, so it still shows SOME
## partial brightness (reveal = a light's own brightness constant,
## capped below 1.0 — see LIGHT_BRIGHTNESS_ON/STATIC_LAMP_LIGHT_
## BRIGHTNESS — even at the very center of its circle, fading further
## in the softness band) at a spot the game logic has correctly
## decided needs full redarkening. The redarkening quad/shadow group
## was then drawn ON TOP of that already-partially-lit base using
## plain alpha-over compositing with the SAME RGB as the base tint,
## which doesn't replace it, it STACKS with it — two semi-transparent
## layers of the same colour composite to MORE opaque than either one
## alone (1-(1-a)(1-b) > max(a,b) whenever both are > 0), so a
## redarkened tile could read measurably darker than the true ambient
## night tint just outside any light's reach altogether. Returns how
## much residual "reveal" (0..1, matching night_overlay_light.gdshader's
## own per-light falloff formula exactly) the base overlay shader is
## already showing at `world_pos`, from every currently active light —
## the player's own carried source plus every lit static lamp — so a
## caller can work out exactly how much of its own alpha to draw to
## land on the target ambient alpha exactly once, not twice.
func _local_light_reveal(world_pos: Vector2) -> float:
	var reveal: float = 0.0
	if _light_source_effective() and is_instance_valid(player):
		var pc := _party_light_bearer()
		var radius_tiles: int = pc.get_active_light_radius_tiles() if pc != null else 0
		if radius_tiles > 0:
			var light_pos: Vector2 = tile_map.map_to_local(player.grid_pos)
			var radius_px: float = float(radius_tiles) * TILE_SIZE
			var softness_px: float = TILE_SIZE * 1.5
			var brightness: float = _active_light_brightness(pc)
			var dist: float = world_pos.distance_to(light_pos)
			reveal = max(reveal, (1.0 - smoothstep(max(radius_px - softness_px, 0.0), radius_px, dist)) * brightness)
	if not static_lamp_coords.is_empty():
		var night_amount: float = GameState.get_night_darkness() / GameState.NIGHT_DARKNESS_MAX
		if night_amount > LAMP_GLOW_FADE_START:
			var lamp_radius_px: float = float(STATIC_LAMP_LIGHT_RADIUS_TILES) * TILE_SIZE
			var lamp_softness_px: float = TILE_SIZE * 1.0
			var lamp_brightness: float = STATIC_LAMP_LIGHT_BRIGHTNESS * _lamp_night_factor
			for lamp_coords in static_lamp_coords:
				var lamp_pos: Vector2 = tile_map.map_to_local(lamp_coords)
				var dist2: float = world_pos.distance_to(lamp_pos)
				reveal = max(reveal, (1.0 - smoothstep(max(lamp_radius_px - lamp_softness_px, 0.0), lamp_radius_px, dist2)) * lamp_brightness)
	return reveal

## Given how much the base overlay shader has already revealed
## (un-darkened) a spot (`reveal`, see _local_light_reveal() above),
## returns the alpha a SECOND, plain-alpha-over layer of the exact same
## colour needs to draw at in order for the TOTAL composited alpha to
## land on `target_alpha` exactly — not stack past it. Standard "over"
## compositing of two same-colour layers gives combined = a + b(1-a),
## so solving for the second layer's own alpha b, given the first
## layer's own alpha a = target_alpha * (1 - reveal): b = (target -
## a) / (1 - a).
func _compensate_alpha_for_reveal(reveal: float, target_alpha: float) -> float:
	if reveal <= 0.0:
		return target_alpha
	var base_a: float = target_alpha * (1.0 - reveal)
	var denom: float = max(1.0 - base_a, 0.0001)
	return clamp((target_alpha - base_a) / denom, 0.0, 1.0)

func _refresh_light_occlusion() -> void:
	if not is_instance_valid(night_overlay) or not is_instance_valid(cloud_shadow_overlay):
		return
	## Per the "still bleeding through at the edges, fix it so it merges
	## with the outside darkness with no gaps" thread: the first two
	## attempts at this (v0.2.608/609, a hand-picked rectangular band of
	## rows north of every building) and the third (v0.2.610, a scan of
	## every active light's own circular reach) both tried to solve the
	## ROOF_RIDGE-art-taller-than-one-tile overflow (see ROOF_RIDGE_ATLAS/
	## _roof_atlas_for_row()) by forcing an artificial ambient-darkness
	## OVERRIDE onto some subset of tiles via this function's own reveal-
	## compensation machinery. Each attempt traded one visible seam for a
	## different one: the rectangle disagreed with the light's own round
	## falloff along its own straight edge (the "uneven merging... two
	## rectangular boxes of darkness" report); the circular scan then
	## forced the shader's own intentionally-smooth SECONDARY_SHADOW_EDGE_
	## MARGIN_TILES band (see that constant's own comment) to full ambient
	## black, creating a sudden brightness cliff right at the margin's own
	## boundary — visible as a ring "all around the circle" of every
	## light, confirmed as a regression.
	##
	## Both attempts were the wrong tool: the actual bug is a purely
	## VISUAL one (roof art painting past its own tile cell), so it's now
	## fixed at the visual layer instead — RoofOverflowMaskLayer (see its
	## own @onready comment) repaints correct ground/canopy art directly
	## over the overflow at build time, one z_index above roof_layer. That
	## is ordinary world content, so the existing night_overlay/cloud_
	## shadow_overlay shader darkens and reveals it exactly like any other
	## tile, with zero special-casing here — eliminating this entire class
	## of "compensate the ambient fill for some subset of tiles" bug, and
	## every seam/ring artifact the last three attempts introduced trying
	## to solve it through the lighting system instead. This function is
	## back to its original v0.2.607 job: closing the genuine LOS-blocked
	## (wall-shadowed) gap, nothing more.
	var raw_blocked: Array = []
	raw_blocked.append_array(_player_light_blocked_tiles)
	for lamp_index in _static_lamp_blocked_tiles:
		raw_blocked.append_array(_static_lamp_blocked_tiles[lamp_index])
	## Per the "lamps stand either side of the southern house, and are
	## casting shadow on each other, that should NOT be happening" report:
	## each light's OWN blocked-tile list only knows about that single
	## light's own LOS — a tile squarely behind a wall from lamp A's own
	## position lands in lamp A's blocked_tiles even when lamp B, standing
	## on the OTHER side of that same wall, has perfectly clear LOS to it
	## and is actively lighting it. The old code then unioned every
	## light's blocked list and redarkened all of it unconditionally,
	## painting solid night-darkness right back over ground a second
	## light was correctly revealing — exactly the large blocky dark
	## areas reported, distinct from (and in addition to) the wall-shadow
	## POLYGON cross-suppression this same request already fixed. A tile
	## only genuinely deserves redarkening when NO active light — not the
	## player's own torch, not any lamp — actually reaches it; the
	## per-light LOS dictionaries _recompute_secondary_light_lit_tiles()
	## already refreshes this same frame (used to suppress secondary
	## shadows) are exactly that "does some light see this tile" answer,
	## so re-use them here rather than trusting each light's blocked list
	## in isolation.
	var all_blocked: Array = []
	var _blocked_seen: Dictionary = {}
	for coords in raw_blocked:
		if _blocked_seen.has(coords):
			continue
		_blocked_seen[coords] = true
		if _tile_needs_redarkening(coords):
			all_blocked.append(coords)
	if all_blocked.is_empty() or not is_instance_valid(player):
		for quad in _light_occlusion_quads:
			quad.visible = false
		return
	var camera: Camera2D = player.get_node("Camera2D")
	if camera == null:
		for quad in _light_occlusion_quads:
			quad.visible = false
		return
	if not is_instance_valid(_light_occlusion_container):
		_light_occlusion_container = Node2D.new()
		_light_occlusion_container.name = "LightOcclusionContainer"
		cloud_shadow_overlay.add_child(_light_occlusion_container)
	var zoom: Vector2 = camera.zoom
	var viewport_size := get_viewport_rect().size
	var viewport_center := viewport_size / 2.0
	var half_tile_px: Vector2 = Vector2(TILE_SIZE, TILE_SIZE) * zoom / 2.0
	## Matches whatever NightOverlay is showing THIS frame, moon-glow
	## pulse and all (see _apply_moon_glow_pulse()) — so a redarkened
	## tile always blends seamlessly with the ambient darkness around
	## it, day or night, rather than needing its own separately-tuned
	## color.
	var fill_color: Color = night_overlay.color
	var quad_index := 0
	for coords in all_blocked:
		var world_center: Vector2 = tile_map.map_to_local(coords)
		var screen_center: Vector2 = viewport_center + (world_center - camera.get_screen_center_position()) * zoom
		var quad: Polygon2D
		if quad_index < _light_occlusion_quads.size():
			quad = _light_occlusion_quads[quad_index]
		else:
			quad = Polygon2D.new()
			## vertex_colors (set below) fully replaces this flat color
			## with a per-corner one, so this is just Godot's own inert
			## default for a freshly-created Polygon2D.
			quad.color = Color(1.0, 1.0, 1.0, 1.0)
			_light_occlusion_container.add_child(quad)
			_light_occlusion_quads.append(quad)
		quad.polygon = PackedVector2Array([
			screen_center + Vector2(-half_tile_px.x, -half_tile_px.y),
			screen_center + Vector2(half_tile_px.x, -half_tile_px.y),
			screen_center + Vector2(half_tile_px.x, half_tile_px.y),
			screen_center + Vector2(-half_tile_px.x, half_tile_px.y),
		])
		## Per the "darker than normal night darkness" report: this
		## tile's own target alpha is compensated for whatever residual
		## reveal the base overlay shader is already showing here (see
		## _local_light_reveal()/_compensate_alpha_for_reveal() above),
		## so the two layers land on fill_color.a exactly once instead
		## of stacking past it.
		var tile_alpha: float = _compensate_alpha_for_reveal(_local_light_reveal(world_center), fill_color.a)
		## Per the "wall shadows leave gaps of light when they meet the
		## edge of lantern/lamp light circle" report: this used to grade
		## each corner's own alpha by how many of the (up to) 4 tiles
		## sharing that grid corner still needed redarkening, fading the
		## boundary against a lit neighbour out across roughly a tile's
		## width. That unconditionally diluted a genuinely-blocked tile's
		## own correct, fully-compensated darkness by up to 75% wherever
		## it shared a corner with a bright neighbour — a real "should be
		## fully dark but isn't" gap, not just a cosmetic soft edge. Every
		## corner now gets this tile's own flat tile_alpha, so a redarkened
		## tile is always exactly as dark as _local_light_reveal()/
		## _compensate_alpha_for_reveal() says it should be, full stop —
		## the boundary against a lit tile goes back to a hard tile-grid
		## step instead of a smoothed fade.
		quad.vertex_colors = PackedColorArray([
			Color(fill_color.r, fill_color.g, fill_color.b, tile_alpha),
			Color(fill_color.r, fill_color.g, fill_color.b, tile_alpha),
			Color(fill_color.r, fill_color.g, fill_color.b, tile_alpha),
			Color(fill_color.r, fill_color.g, fill_color.b, tile_alpha),
		])
		quad.visible = true
		quad_index += 1
	for i in range(quad_index, _light_occlusion_quads.size()):
		_light_occlusion_quads[i].visible = false

## Per the request: switches the cursor's hue/decoration based on
## which marker (if any) the mouse is currently over — markers are
## positioned in real tile coordinates (see _spawn_ambush_marker/
## _spawn_social_marker), so converting the mouse's own screen
## position to a tile via the same _screen_to_tile() every click
## already uses keeps this in perfect sync with where markers are
## actually clickable, not a separate, possibly-drifting pixel check.
func _update_cursor_for_hover() -> void:
	var hovered_tile := _screen_to_tile(get_viewport().get_mouse_position())
	var new_state := _cursor_state_for_tile(hovered_tile)
	if new_state == _current_cursor_state:
		return
	_current_cursor_state = new_state
	match new_state:
		"ambush":
			Input.set_custom_mouse_cursor(CURSOR_AMBUSH, Input.CURSOR_ARROW, CURSOR_HOTSPOT)
		"social":
			Input.set_custom_mouse_cursor(CURSOR_SOCIAL, Input.CURSOR_ARROW, CURSOR_HOTSPOT)
		_:
			Input.set_custom_mouse_cursor(CURSOR_DEFAULT, Input.CURSOR_ARROW, CURSOR_HOTSPOT)

## Split out from _update_cursor_for_hover() so the state-determination
## logic can be tested directly against a given tile, without needing
## to simulate real mouse motion in a headless test.
func _cursor_state_for_tile(tile: Vector2i) -> String:
	if ambush_marker != null and tile == ambush_marker_tile:
		return "ambush"
	if social_marker != null and tile == social_marker_tile:
		return "social"
	return "default"

func _ready() -> void:
	Input.set_custom_mouse_cursor(CURSOR_DEFAULT, Input.CURSOR_ARROW, CURSOR_HOTSPOT)
	_load_map_definition()
	GameState.ensure_player_character()
	## Per the request: entering a quest's own home map is itself the
	## trigger to start it — start_scripted_quest() is already a
	## no-op if the quest is already Active, so this is safe to run
	## on every single visit, not just the very first.
	if current_map_def != null and current_map_def.auto_start_quest_id != "":
		var qid: String = current_map_def.auto_start_quest_id
		var qdef: QuestDefinition = load("res://data/quests/%s.tres" % qid) as QuestDefinition
		if qdef != null:
			GameState.player_character.start_scripted_quest(qdef.quest_id, qdef.quest_title, qdef.quest_summary)
	_build_map()
	## Per the request: buildings/shadows now render above however many
	## ground elevation layers this specific map needed (computed fresh
	## by _rebuild_ground_layers() inside _build_map() above) — the
	## Player needs to stay above all of that too, same as every NPC/
	## marker sprite (see above_buildings_z).
	player.z_index = above_buildings_z
	## Per the request: the Player casts a shadow too, same as every
	## friendly NPC — see _make_person_shadow(). Per the TILE_SIZE
	## 16->64 upscale: now added to the Player's own Sprite2D child
	## (not the plain Node2D wrapper) so it inherits that sprite's
	## scale = Vector2(4,4) exactly the way every NPC's shadow already
	## does (NPC shadows are added via `sprite.add_child(...)`, where
	## `sprite` IS the scaled Sprite2D) — PERSON_SHADOW_PIVOT_PX/
	## PERSON_SHADOW_ANCHOR_PX are deliberately unscaled local-space
	## values that only read correctly under a 4x-scaled parent (see
	## their own comments). _update_person_shadow()'s lookup checks
	## both "Shadow" and "Sprite2D/Shadow" so this still works
	## regardless of which of the two node shapes it's given.
	player.get_node("Sprite2D").add_child(_make_person_shadow())
	_setup_pathfinding()
	_restore_return_position()
	## Per the door/roof request: _build_map() itself always starts with
	## every roof shown (player_inside_building = -1) since it can't yet
	## know where the player will really end up — _restore_return_position()
	## just above is what actually settles that (camp position, a fresh
	## spawn, a deliberate map-transition tile, etc.), so this is the
	## first point where checking "is the player indoors?" is meaningful.
	_update_roof_visibility(player.grid_pos)
	player.overworld = self
	player.moved.connect(_on_player_moved)
	_apply_camera_limits()
	_reset_world_map_camera_pan()

	## Real bug fix — the actual cause of the reported "game freezes
	## during World Map travel, only sometimes": character_menu/
	## pause_menu used to be created much further down this function
	## (see below), AFTER the Wilderness-Event resume block that
	## follows. _unhandled_input() unconditionally bails out on EVERY
	## keypress — not just Y/N, literally everything — whenever
	## character_menu or pause_menu is null (see its own guard). Since
	## the resume block below can itself `await` a full Stage-choice
	## prompt (if the resumed journey has more than one day left), and
	## that prompt can only ever be dismissed by a real keypress,
	## _ready() would deadlock: it can't reach the code that creates
	## character_menu/pause_menu until the resume block finishes, and
	## the resume block can't finish because _unhandled_input() is
	## refusing every keypress until character_menu/pause_menu exist.
	## Confirmed directly: simulating a real Gotheim->Altdorf journey
	## (repeatedly, seeded, through the real game code) reproduced
	## this exact hang whenever a Wilderness Event interrupted a
	## multi-day journey and the resumed leg needed its own Stage
	## choice — matching the user's own report of an intermittent,
	## totally unresponsive freeze on that exact route (which passes
	## directly through Giessingen, coincidentally near where the
	## first Wilderness Event roll tends to land, not because
	## Giessingen itself is special). Moved here, before the resume
	## block, so _unhandled_input() is fully functional the moment any
	## awaited travel prompt might need it. Both scenes are trivial,
	## self-contained (`_ready()` just wires up their own buttons and
	## sets `visible = false`) — moving them earlier has no other
	## dependency on anything later in this function.
	character_menu = CHARACTER_MENU_SCENE.instantiate()
	add_child(character_menu)
	character_menu.closed.connect(_on_character_menu_closed)

	pause_menu = PAUSE_MENU_SCENE.instantiate()
	add_child(pause_menu)
	pause_menu.switch_character_requested.connect(_on_switch_character_requested)

	## Per the request: a Wilderness Event interrupting a journey no
	## longer cancels it — if Overworld's own GameState carries a
	## real remaining journey (persisted right before the event that
	## interrupted it), pick it back up automatically here, the same
	## way it would have continued if nothing had interrupted it.
	if current_map_def != null and current_map_def.is_world_map and not GameState.pending_resume_travel_route.is_empty():
		var resume_route: Array = GameState.pending_resume_travel_route
		var resume_days: int = GameState.pending_resume_travel_days_remaining
		var resume_destination: String = GameState.pending_resume_travel_destination_name
		GameState.pending_resume_travel_route = []
		await _run_travel_day_loop(resume_route, resume_days, resume_destination)
	## Per the source material (p.4, "The Frenzied Mob"): before the
	## Characters can even reach Gotheim, they're attacked by a mob of
	## rampaging villagers turned berserk by the Jabberslythe's own
	## proximity — as many as there are party members, plus one extra.
	## Triggered once, the very first time the player arrives, not a
	## random encounter and not repeatable — tracked on the quest's
	## own real state, matching the same "only happens once" rule
	## already applied to the Jabberslythe itself.
	if current_map_def != null and current_map_def.auto_start_quest_id == "gotheim":
		var q_pre := GameState.player_character.find_quest("gotheim")
		var mob_already_encountered: bool = not q_pre.is_empty() and bool(q_pre.get("mob_encountered", false))
		_trigger_gotheim_mob_encounter()
		## Per the request: only shown on a genuine return visit — the
		## mob fight's own trigger sets mob_encountered synchronously
		## the instant it fires, well before the actual fight (and any
		## victory) has happened, so checking it only right here would
		## show the village narrative before the fight even started.
		if mob_already_encountered:
			_show_gotheim_entering_narrative()
	## Per the request: each map sets its own default zoom — the World
	## Map needs to show far more of its much larger grid than an
	## ordinary local map does.
	var cam: Camera2D = player.get_node("Camera2D")
	if cam != null and current_map_def != null:
		cam.zoom = Vector2(current_map_def.default_camera_zoom, current_map_def.default_camera_zoom)
	## Per the request: the InfoBar is a fixed-height, opaque overlay
	## pinned to the very top of the screen (see UI/InfoBar in
	## Overworld.tscn) — previously the camera centered the player (and
	## the map generally) across the WHOLE screen, including the strip
	## underneath the bar, so anything near the top edge rendered
	## invisibly behind it and was also unclickable (see the
	## %InfoBar.size.y guard already in _unhandled_input()). Shifting
	## the camera's own capture point up by half the bar's height
	## (converted from fixed screen pixels to world units via this
	## map's own zoom) re-centers the visible player/map within the
	## space BELOW the bar instead, without touching the bar itself or
	## the existing World Map drag-pan (which reads/writes
	## camera.position, a separate property from this).
	if cam != null:
		var bar_height: float = %InfoBar.size.y
		cam.offset = Vector2(0, -bar_height / 2.0 / cam.zoom.y)
	dialogue_label.visible = false
	encounter_label.visible = false
	_build_roll_log_overlay()
	_update_hud()

	## Per the Radial Menu rework request: the persistent Menu/Camp
	## buttons are gone entirely — both menus stay reachable exactly as
	## before via their own keyboard shortcuts (M / "open_menu" and C),
	## handled in _unhandled_input() below.
	radial_menu = RADIAL_MENU_SCENE.instantiate()
	add_child(radial_menu)
	radial_menu.menu_selected.connect(_on_radial_menu_selected)
	_spawn_elder()
	## Per the request: a handful of NPC shadows (quest NPCs, the
	## companion maker, the Elder) are spawned after _rebuild_shadows()
	## already ran its own _update_shadow_angles() pass above, so their
	## freshly-added Shadow children would otherwise sit un-rotated
	## until the next incidental HUD refresh. One more pass here — now
	## that every spawn call in _ready() has run — settles all of them
	## (Player included) to the correct angle before the first frame
	## ever draws.
	_update_shadow_angles()

	## Per the request: the game should genuinely save on any map and
	## location, not just wherever a movement-based or menu-close
	## autosave happens to trigger. This matters especially on the
	## World Map now that WASD movement is disabled there — the old
	## "autosaves every step" behavior no longer has any steps to fire
	## on, so a real periodic timer covers that gap (and every other
	## map besides) regardless of what the player is actually doing.
	## Per the "movement feels jerky" request: _on_player_moved() used
	## to ALSO call GameState.autosave() on every single tile step,
	## which meant a synchronous disk write during ordinary WASD
	## walking on every local map — that was the real source of the
	## jerkiness (see its own comment), and it's gone now. This timer
	## is therefore the only thing keeping an on-foot player's position
	## fresh on disk while they walk around without triggering any
	## other checkpoint (shop, camp, quest, menu, etc.) — shortened
	## from 20s to 6s to compensate for losing that per-step guarantee,
	## while still being far too infrequent to ever cause a hitch
	## anyone could actually notice.
	var autosave_timer := Timer.new()
	autosave_timer.wait_time = 6.0
	autosave_timer.autostart = true
	autosave_timer.timeout.connect(func(): GameState.autosave())
	add_child(autosave_timer)

	## Per the request: a class/career-themed origin story, shown once,
	## before the player can move for the first time — has_seen_origin_story
	## is per-Character (saved with them), so this only ever fires for a
	## genuinely new character, never again on a later load.
	if not GameState.player_character.has_seen_origin_story:
		_show_origin_story()

## If GameState remembers where the player was standing before their
## last field encounter (set by _trigger_encounter, left in place by a
## win, and cleared by a defeat — see FieldEncounter._end_battle), drop
## them back there instead of the map's default spawn point. Consumes
## the value either way so a stale position can't leak into a later,
## unrelated load of this scene.
## Restores wherever the player should actually spawn, in priority
## order: a post-battle return position (session-only, set by
## FieldEncounter on a win), then a persistent camp position (survives
## a save/reload, set whenever Camp is opened, cleared on death), then
## finally the map's own default spawn if neither applies.
func _restore_return_position() -> void:
	if _used_deliberate_spawn_tile:
		GameState.return_position = Vector2i(-1, -1)
		return
	var pos := GameState.return_position
	GameState.return_position = Vector2i(-1, -1)
	if pos == Vector2i(-1, -1):
		pos = GameState.player_character.camp_position
	if pos == Vector2i(-1, -1):
		return
	if is_walkable(pos):
		player.warp_to(pos)

## M (character menu), C (Camp), and Esc (pause menu, and closing
## whichever menu is currently open) are all handled in exactly one
## place, rather than having each menu independently listen for its own
## key — multiple nodes racing to consume the same keypress is fragile,
## especially since Esc means different things depending on what's
## currently open.
func _unhandled_input(event: InputEvent) -> void:
	## Real bug fix: character_menu/pause_menu are only assigned
	## partway through _ready() — if any input arrives before that
	## point finishes (this function reads their own .visible
	## unconditionally further down), this crashed. Guards the whole
	## handler rather than each access site individually.
	if character_menu == null or pause_menu == null:
		return
	## Per the request: Esc or Space stops an in-progress World Map
	## journey at any point — checked first, ahead of every other
	## binding, but only actually takes effect while a journey is
	## genuinely animating between Stages with nothing else showing
	## (is_menu_open() covers every active sub-prompt: a Wilderness
	## Event, the Stage choice itself, any menu), so this never steals
	## Esc/Space from something else that's using them at the time.
	if _travel_in_progress and not is_menu_open() and (event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_SPACE)):
		get_viewport().set_input_as_handled()
		_travel_cancel_requested = true
		return
	if event.is_action_pressed("open_menu"):
		if character_menu.visible:
			character_menu.close()
		elif not pause_menu.visible:
			character_menu.open()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_C:
		if not character_menu.visible and not pause_menu.visible:
			get_viewport().set_input_as_handled()
			_open_camp()
	## Per the light-source request: L toggles the active character's
	## equipped light source off -> on -> low (if it has a low mode) ->
	## off. Same guard as Camp/Q/E above — available any time neither
	## menu is open, and always works regardless of time of day/location
	## (see _toggle_light_source()'s own comment for why).
	elif event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_L:
		if not character_menu.visible and not pause_menu.visible:
			get_viewport().set_input_as_handled()
			_toggle_light_source()
	## Per the request: Q cycles the active party member left, E
	## cycles right — same guard as Camp above, since switching who
	## you're controlling mid-menu or mid-travel-animation would be
	## confusing at best.
	## Per the request: Q cycles the active party member left, E
	## cycles right on the map itself — same guard as Camp above,
	## since switching who you're controlling mid-travel-animation
	## would be confusing at best. When the Character Menu is open
	## instead, Q/E cycles which member's own stats/inventory/
	## equipment/spellbook/advancement it's showing — per the
	## request, accessible via the Menu itself.
	elif event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_Q:
		if character_menu.visible:
			get_viewport().set_input_as_handled()
			character_menu.cycle_displayed_character(-1)
		elif not pause_menu.visible and not _travel_in_progress:
			get_viewport().set_input_as_handled()
			GameState.cycle_active_party_member(-1)
			_apply_active_character_sprite()
			_update_hud()
	elif event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_E:
		if character_menu.visible:
			get_viewport().set_input_as_handled()
			character_menu.cycle_displayed_character(1)
		elif not pause_menu.visible and not _travel_in_progress:
			get_viewport().set_input_as_handled()
			GameState.cycle_active_party_member(1)
			_apply_active_character_sprite()
			_update_hud()
	## Per the request ("always allow WASD movement and hotkey space to
	## accept selected for these all these types of pop ups"): while
	## any real Y/N prompt is open, WASD's own Left/Up (A/W) and
	## Right/Down (D/S) move the selection highlight between [Y] and
	## [N], and Space accepts whichever is currently selected — via
	## the exact same _confirm_prompt_press_yes/no() code the direct
	## Y/N keys below call, so behaviour is always identical either
	## way. Checked ahead of the direct Y/N branches (and everything
	## else keyed off move_left/right/up/down or KEY_SPACE elsewhere)
	## since a real prompt being up should always win.
	elif _any_yn_prompt_awaiting() and (event.is_action_pressed("move_left") or event.is_action_pressed("move_up")):
		get_viewport().set_input_as_handled()
		_confirm_selected_yes = true
		_render_confirm_prompt()
	elif _any_yn_prompt_awaiting() and (event.is_action_pressed("move_right") or event.is_action_pressed("move_down")):
		get_viewport().set_input_as_handled()
		_confirm_selected_yes = false
		_render_confirm_prompt()
	elif _any_yn_prompt_awaiting() and event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		if _confirm_selected_yes:
			_confirm_prompt_press_yes()
		else:
			_confirm_prompt_press_no()
	## Per the request: a forced choice after every Stage of World Map
	## travel — Y pushes on, N makes camp for the night.
	elif _awaiting_stage_choice and event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_Y:
		get_viewport().set_input_as_handled()
		_confirm_prompt_press_yes()
	elif _awaiting_stage_choice and event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_N:
		get_viewport().set_input_as_handled()
		_confirm_prompt_press_no()
	## Per Phase 2 of the world-map plan: Y/N confirm or cancel a
	## pending travel offer — or, per the request, a pending "enter
	## this city's local map" offer, distinguished by
	## _pending_enter_location being set.
	elif awaiting_travel_confirm and event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_Y:
		get_viewport().set_input_as_handled()
		_confirm_prompt_press_yes()
	elif awaiting_travel_confirm and event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_N:
		get_viewport().set_input_as_handled()
		_confirm_prompt_press_no()
	## Per the request: Space continues a Wilderness Event's own text;
	## Y/N resolves the one Wilderness Event with a real choice
	## (Fellow Travellers — approach or avoid).
	elif _awaiting_wilderness_continue and event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		_awaiting_wilderness_continue = false
	elif _awaiting_wilderness_choice and event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_Y:
		get_viewport().set_input_as_handled()
		_confirm_prompt_press_yes()
	elif _awaiting_wilderness_choice and event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_N:
		get_viewport().set_input_as_handled()
		_confirm_prompt_press_no()
	## Per the follow-up ambush-rework request: Y/N (and Space, already
	## covered by the shared _any_yn_prompt_awaiting() branch above)
	## resolve the Surprise-or-Leave choice the same way every other
	## Y/N prompt in this screen does.
	elif _awaiting_ambush_choice and event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_Y:
		get_viewport().set_input_as_handled()
		_confirm_prompt_press_yes()
	elif _awaiting_ambush_choice and event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_N:
		get_viewport().set_input_as_handled()
		_confirm_prompt_press_no()
	elif event.is_action_pressed("ui_cancel"):
		if character_menu.visible:
			character_menu.close()
		elif pause_menu.visible:
			pause_menu.close()
		else:
			pause_menu.open()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		## Reaching _unhandled_input at all already means no Control
		## (the InfoBar, its buttons, any open menu) consumed this
		## click first — that's what _unhandled_input is for. The
		## explicit height check below is a second, defensive layer
		## specifically for the request's "including the buttons"
		## wording, in case a future UI change ever adds a
		## click-through gap in the bar.
		if event.position.y <= %InfoBar.size.y:
			return
		if is_menu_open():
			return
		if event.button_index == MOUSE_BUTTON_LEFT and is_world_map_active():
			## Per the request: don't fire the click immediately — a
			## left-press on the World Map might turn into a drag pan
			## instead of a genuine click, and that's only knowable once
			## the button is released (see the release branch below).
			_is_dragging_camera = true
			_drag_confirmed = false
			_drag_start_mouse_pos = event.position
			_drag_start_camera_offset = _world_map_camera_offset
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_on_map_left_click(event)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_on_map_right_click(event)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _is_dragging_camera:
		## A real drag actually happened (moved past the threshold) —
		## the camera pan itself is the whole interaction, so no click
		## fires. Otherwise this was genuinely just a click that
		## happened to start the same way, so it's handled normally now.
		_is_dragging_camera = false
		if not _drag_confirmed:
			_on_map_left_click(event)
		_drag_confirmed = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _is_dragging_camera:
		var delta: Vector2 = event.position - _drag_start_mouse_pos
		if not _drag_confirmed and delta.length() > CAMERA_DRAG_THRESHOLD:
			_drag_confirmed = true
		if _drag_confirmed:
			## Dragging right/down should feel like pulling the map
			## itself in that direction — i.e. the camera moves the
			## opposite way from the mouse.
			_world_map_camera_offset = _drag_start_camera_offset - delta
			var camera: Camera2D = player.get_node("Camera2D")
			camera.position = _world_map_camera_offset
		get_viewport().set_input_as_handled()

## Godot's own InputEventMouseButton.double_click is the authoritative
## double-click signal (proper OS-level timing/distance thresholds) —
## used directly rather than hand-rolling a second timer-based check.
func _on_map_left_click(event: InputEventMouseButton) -> void:
	var target_tile := _screen_to_tile(event.position)
	if target_tile == ambush_marker_tile:
		get_viewport().set_input_as_handled()
		_on_ambush_marker_clicked()
		return
	if target_tile == social_marker_tile:
		get_viewport().set_input_as_handled()
		_on_social_marker_clicked()
		return
	## Per the reported bug: quest monster markers (e.g. the
	## Jabberslythe's own lair) were never checked in any click
	## handler at all — matches the same real fix as quest NPCs
	## below, and the same established direct-trigger pattern the
	## ambush marker already uses.
	if quest_monster_marker_tiles.has(target_tile):
		get_viewport().set_input_as_handled()
		_on_quest_monster_marker_clicked(target_tile)
		return
	## Per Phase 2 of the world-map plan: clicking a city marker on the
	## World Map offers travel there — unless the player is already
	## standing on it, in which case clicking (or simply standing
	## there, per the request) offers to enter instead.
	if current_map_def != null and current_map_def.is_world_map:
		var loc := _get_location_at(target_tile)
		if loc != null:
			get_viewport().set_input_as_handled()
			if player.grid_pos == loc.world_tile:
				_offer_enter_location(loc)
			else:
				_offer_travel(loc)
			return
	## Per the request: no click-to-move pathing on the World Map either
	## — the same reasoning as disabling WASD there.
	if is_world_map_active():
		return
	if not event.double_click:
		return
	_start_path_to(target_tile)
	get_viewport().set_input_as_handled()

func _on_map_right_click(event: InputEventMouseButton) -> void:
	var target_tile := _screen_to_tile(event.position)
	_radial_menu_target_marker = ""
	_radial_menu_target_npc = Vector2i(-1, -1)
	_radial_menu_target_enemy = Vector2i(-1, -1)
	_radial_menu_target_tile = Vector2i(-1, -1)
	## Per the Radial Menu rework request: "default" replaces the old
	## "normal" (Menu/Camp) context — Perception is always shown, and
	## Gossip/Talk/Attack are conditionally shown on top of it depending
	## on what's actually under the cursor (see radial_menu.gd).
	var context := "default"
	## Per the request: the World Map's own right-click menu is just
	## the single Lore button, regardless of what's under the cursor —
	## a city marker or any ordinary province tile both have real lore
	## to show.
	if current_map_def != null and current_map_def.is_world_map:
		_radial_menu_target_lore_tile = target_tile
		radial_menu.open_at(event.position, "lore")
		get_viewport().set_input_as_handled()
		return
	if target_tile == ambush_marker_tile and not ambush_perception_used:
		_radial_menu_target_marker = "ambush"
		context = "marker"
	elif target_tile == social_marker_tile and not social_perception_used:
		_radial_menu_target_marker = "social"
		context = "marker"
	elif quest_monster_marker_tiles.has(target_tile) and not GameState.player_character.get_quest_monster_defeated(quest_monster_marker_tiles[target_tile].quest_id, quest_monster_marker_tiles[target_tile].monster_id):
		_radial_menu_target_enemy = target_tile
	elif _get_npc_role_at(target_tile) != "":
		_radial_menu_target_npc = target_tile
	else:
		_radial_menu_target_tile = target_tile
	radial_menu.open_at(event.position, context, {"can_talk": _radial_menu_target_npc != Vector2i(-1, -1), "can_attack": _radial_menu_target_enemy != Vector2i(-1, -1)})
	get_viewport().set_input_as_handled()

## Which kind of NPC (if any) occupies a tile — "" if none. Matches
## this project's existing role-specific coordinate lists (there's no
## unified NPC registry yet, just per-role tracking set up wherever
## each type is spawned).
func _get_npc_role_at(tile: Vector2i) -> String:
	if tile == elder_tile:
		return "elder"
	## Per the reported bug: quest NPC markers were never checked here
	## at all — only the generic shopkeeper/priest/traveller/trainer
	## types were, which is exactly why right-click interaction only
	## ever found the merchant in a map like Gotheim's, never any of
	## its own real quest NPCs. Checked ahead of the generic types,
	## since a quest marker is always the more specific match.
	if quest_npc_marker_tiles.has(tile):
		return "quest_npc"
	if current_map_def != null and current_map_def.companion_maker_tile != Vector2i(-1, -1) and tile == current_map_def.companion_maker_tile:
		return "companion_maker"
	if shopkeeper_coords.has(tile):
		return "shopkeeper"
	if priest_coords.has(tile):
		return "priest"
	if petty_magic_trainer_coords.has(tile):
		return "trainer"
	if npc_dialogue.has(tile):
		return "traveller"
	return ""

func _on_radial_menu_selected(option: String) -> void:
	if option == "perception":
		if _radial_menu_target_npc != Vector2i(-1, -1):
			_show_npc_description()
		elif _radial_menu_target_enemy != Vector2i(-1, -1):
			_show_enemy_description()
		elif _radial_menu_target_marker != "":
			_perform_marker_perception_check()
		else:
			_show_tile_description()
	elif option == "gossip":
		_show_npc_gossip()
	elif option == "talk":
		_talk_to_npc()
	elif option == "attack":
		_attack_target_enemy()
	elif option == "lore":
		_show_lore_box()
	elif option == "travel":
		var tile := _radial_menu_target_lore_tile
		var loc := _get_location_at(tile)
		if loc != null:
			if player.grid_pos == loc.world_tile:
				_offer_enter_location(loc)
			else:
				_offer_travel(loc)
		else:
			_offer_travel_to_tile(tile)

## Per the request: Perception on an NPC shows a description of them
## rather than the marker-detection roll — no Test involved, this one
## is always available (you can always just look at someone).
func _show_npc_description() -> void:
	var role := _get_npc_role_at(_radial_menu_target_npc)
	_radial_menu_target_npc = Vector2i(-1, -1)
	if role == "":
		return
	_show_info_popup("Perception", NPCFlavorText.get_description(role))

## Per the request: a random piece of local gossip, not tied to any
## specific NPC's own identity — this project's NPCs don't have real
## backstories to draw from yet, and gossip is naturally more "what's
## going on around here" than "tell me about yourself" anyway.
func _show_npc_gossip() -> void:
	_radial_menu_target_npc = Vector2i(-1, -1)
	_show_info_popup("Gossip", NPCFlavorText.get_gossip())

## Per the Radial Menu rework request: Perception on a live quest
## monster marker (the radial's "enemy" target) describes the creature
## itself — reusing the real MonsterDefinition.summary already written
## for that monster rather than inventing new flavor text, same as how
## _show_npc_description() reuses NPCFlavorText above.
func _show_enemy_description() -> void:
	var tile := _radial_menu_target_enemy
	_radial_menu_target_enemy = Vector2i(-1, -1)
	if not quest_monster_marker_tiles.has(tile):
		return
	var mmarker: QuestMonsterMapMarker = quest_monster_marker_tiles[tile]
	var qdef: QuestDefinition = load("res://data/quests/%s.tres" % mmarker.quest_id) as QuestDefinition
	var quest_mdef: QuestMonsterDefinition = qdef.find_monster(mmarker.monster_id) if qdef != null else null
	var mdef: MonsterDefinition = GameData.monster_db.find_by_name(quest_mdef.monster_name) if quest_mdef != null else null
	var desc: String = mdef.summary if mdef != null and mdef.summary != "" else "Something dangerous, and it's noticed you too."
	_show_info_popup("Perception", "%s It looks ready for a fight." % desc)

## Per the Radial Menu rework request: Attack, only ever shown for a
## live quest monster marker (an "enemy that can be fought" — see
## _on_map_right_click), launches the exact same encounter the
## existing left-click/walk-onto trigger already uses.
func _attack_target_enemy() -> void:
	var tile := _radial_menu_target_enemy
	_radial_menu_target_enemy = Vector2i(-1, -1)
	if tile == Vector2i(-1, -1):
		return
	_on_quest_monster_marker_clicked(tile)

## Per the Radial Menu rework request: Perception "allow[s] info about
## the selected Tile", always available — for an ordinary tile (not an
## NPC, live enemy, chest, or ambush/social marker) this reads the raw
## map character straight from map_rows and shows a short description
## of the terrain itself.
const TERRAIN_DESCRIPTIONS := {
	".": "Open grass — unremarkable, ordinary ground.",
	"T": "A tree, its branches offering a little cover if you needed it.",
	"~": "Cold, moving river water — not for wading into without good reason.",
	"v": "Floodwater, murky and knee-deep, swallowing whatever the levee break left behind.",
	"G": "A worn mud path, packed hard by years of footsteps.",
	"Q": "A proper road — the easiest going you'll find out here.",
	"A": "Tilled farmland, freshly turned and waiting on a season's work.",
	"z": "Corn, tall and green, close to ready.",
	"k": "Barley, dense and golden, swaying in the breeze.",
	"F": "Smooth flagstone flooring.",
	"D": "A neatly bordered floor — someone's taken real care over this room.",
	"U": "Packed mud flooring, cheap and practical.",
	"C": "A sturdy wooden table.",
	"R": "A plain wooden chair.",
	"E": "A modest bed, better than sleeping on the road.",
	"V": "A closed wooden cupboard.",
	"I": "A rough fence, marking out someone's land.",
	"J": "A wooden gate.",
	"L": "A fence gate, latched shut against wandering livestock.",
	"X": "A sturdy wooden bridge, its planks worn smooth by crossing feet and its rope-and-post railings holding steady over the water.",
	"W": "The village well — clean water, if you trust it.",
	"l": "A street lamp, its iron post cold and dark by day — lit against the dark once the sun goes down.",
	"o": "The Red Ogham standing stone, notched with carvings long since worn illegible.",
	",": "Patchy scrub and undergrowth.",
	"a": "A crude palisade of sharpened logs, lashed together — greenskin work, but it'll stop an arrow.",
	"j": "A gap in the palisade, flanked by two heavy gateposts — the way into the Goblin Fort.",
	"t": "A greenskin tent, hides patched and stitched over crooked poles. Best not to look inside.",
	"i": "Bare rock face, the mountain's foot rising sheer out of the ground.",
	"y": "A dark cave mouth opening into the mountainside — cold air drifts out of the black.",
}
func _show_tile_description() -> void:
	var tile := _radial_menu_target_tile
	_radial_menu_target_tile = Vector2i(-1, -1)
	if tile.y < 0 or tile.y >= map_rows.size() or tile.x < 0 or tile.x >= map_rows[tile.y].length():
		return
	var ch: String = map_rows[tile.y][tile.x]
	_show_info_popup("Perception", TERRAIN_DESCRIPTIONS.get(ch, "Nothing remarkable here — just ordinary ground."))

## Goblin Fort chest — moved to field_encounter_screen.gd's own
## exploration-mode chest functions, since the chest itself now
## lives inside the fort's Dungeon Map rather than as an overworld
## tile (see the Goblin Fort Dungeon rework's project doc).

## Per the request: a short narrative small-talk exchange that always
## has a Task attached — gated by a Charm Test that can simply be
## retried on a later Talk if it fails, per the request's own "can be
## tried again later if failed usually." Only one Task is ever active
## at a time (see Character.add_task), so talking to another NPC while
## one is already running is just small talk, nothing more offered.
func _talk_to_npc() -> void:
	var role := _get_npc_role_at(_radial_menu_target_npc)
	var npc_tile := _radial_menu_target_npc
	_radial_menu_target_npc = Vector2i(-1, -1)
	if role == "":
		return
	if role == "elder":
		_talk_to_elder()
		return
	## Per the reported bug: this is the actual real fix — a quest NPC
	## marker's own "Talk" option now genuinely opens their real
	## scripted encounter, instead of falling through to the generic
	## small-talk/random-task system every other NPC type uses.
	if role == "quest_npc" and quest_npc_marker_tiles.has(npc_tile):
		var marker: QuestNPCMapMarker = quest_npc_marker_tiles[npc_tile]
		GameState.pending_quest_id = marker.quest_id
		GameState.pending_quest_npc_id = marker.npc_id
		GameState.return_position = player.grid_pos
		get_tree().change_scene_to_file("res://scenes/ScriptedNPCEncounter.tscn")
		return
	## Per the request: the Party Companion Maker's own "Talk" option
	## opens the real Character Creator (in companion mode) directly,
	## the same way the quest NPC branch above bypasses the generic
	## small-talk system.
	if role == "companion_maker":
		_open_companion_maker()
		return
	var body := NPCFlavorText.get_small_talk(role)

	## Per the request: rolled by every present party member, not just
	## the active one — surfaced to the player as "so-and-so talks to
	## them," not an anonymous party result.
	var charm_def: SkillDefinition = GameData.skill_db.find_by_name("Charm")
	if charm_def == null:
		_show_info_popup("Talk", body)
		return
	var party_result := _tr_party(GameState.party, charm_def)
	var result: TestResolver.TestResult = party_result["result"]
	var roller: Character = party_result["roller"]

	if not roller.get_active_task().is_empty():
		body += "\n\n(%s already has something on the go for someone else — best finish that first.)" % roller.character_name
		_show_info_popup("Talk", body)
		return

	if result.success:
		var task: Dictionary = TaskGenerator.random_task(role)
		var added := roller.add_task(
			str(task["task_id"]), str(task["title"]), str(task["description"]),
			str(task["task_type"]), str(task["target_key"]), int(task["target_count"])
		)
		if added:
			body = "%s does the talking.\n\n" % roller.character_name + body
			body += "\n\nTASK: %s\n%s" % [task["title"], task["description"]]
			GameState.autosave()
	else:
		body += "\n\n\"...Actually, never mind. Maybe another time.\""
	_show_info_popup("Talk", body)

## Per the request: talking to the Village Elder always goes through
## SocialEncounterScreen's own dedicated story sequence rather than
## the generic small-talk/Task flow — which specific stage of the
## story gets shown is entirely SocialEncounterScreen's own call
## (reading the character's real quest state directly), this just
## makes the trip.
func _talk_to_elder() -> void:
	GameState.pending_elder_encounter = true
	get_tree().change_scene_to_file("res://scenes/SocialEncounter.tscn")

## Converts a screen-space click into the map tile under it — accounts
## for the camera's current scroll/zoom via the player's Camera2D
## rather than assuming the map is always at a fixed screen offset.
func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var camera: Camera2D = player.get_node("Camera2D")
	var viewport_center := get_viewport_rect().size / 2.0
	var world_pos := camera.get_screen_center_position() + (screen_pos - viewport_center) / camera.zoom
	return Vector2i(floor(world_pos.x / TILE_SIZE), floor(world_pos.y / TILE_SIZE))

## Plots a path with AStarGrid2D and starts the player walking it one
## tile at a time — an unreachable or non-walkable target just does
## nothing, the same as trying to walk into a wall manually would.
func _start_path_to(target_tile: Vector2i) -> void:
	if not astar_grid.region.has_point(target_tile) or not is_walkable(target_tile):
		return
	var path: Array[Vector2i] = astar_grid.get_id_path(player.grid_pos, target_tile)
	if path.size() <= 1:
		return
	current_path = path.slice(1)   ## drop the starting tile, already standing there
	_advance_path()

## Cancels any click-to-move journey in progress — called when the
## player takes manual keyboard control back, so the two movement
## methods never fight over the same tween.
func _cancel_path() -> void:
	current_path.clear()

func _advance_path() -> void:
	if current_path.is_empty() or player.is_moving or is_menu_open():
		return
	var next_tile: Vector2i = current_path[0]
	if not is_walkable(next_tile, player.grid_pos):
		current_path.clear()
		return
	current_path.remove_at(0)
	var delta: Vector2i = next_tile - player.grid_pos
	if delta == Vector2i(1, 0):
		player.facing = "right"
	elif delta == Vector2i(-1, 0):
		player.facing = "left"
	elif delta == Vector2i(0, 1):
		player.facing = "down"
	elif delta == Vector2i(0, -1):
		player.facing = "up"
	player._update_sprite_frame()
	player._move_to(next_tile)

## Shared by the Camp button and the C hotkey — saves the player's
## current position persistently (see Character.camp_position) before
## navigating, so returning from Camp — or reloading the game entirely
## — drops them back at the same spot.
## Per the request: the Party Companion Maker NPC — recruits a new
## party member via the same full Character Creator wizard used for
## the very first character, up to the real 4-member party cap. Per
## the follow-up request: if anyone was previously dismissed from the
## party (Character Menu's Group tab), this NPC also offers to
## re-recruit them directly, with everything they left with — skills,
## Talents, XP, inventory — still exactly as it was, rather than only
## ever offering to build someone brand new.
func _open_companion_maker() -> void:
	if GameState.party.size() >= GameState.MAX_PARTY_SIZE:
		_show_info_popup("Party Companion Maker", "\"Your party's already as large as I can help you manage — four's the most anyone can look after well on the road.\"")
		return
	if GameState.dismissed_companions.is_empty():
		_start_new_companion_creation()
		return
	_open_companion_choice_popup()

func _start_new_companion_creation() -> void:
	GameState.return_position = player.grid_pos
	GameState.pending_companion_creation = true
	GameState.autosave()
	get_tree().change_scene_to_file("res://scenes/CharacterCreation.tscn")

## Offers a choice between the usual brand-new-companion wizard and
## re-recruiting anyone currently sitting in GameState.dismissed_companions
## — built with the same CanvasLayer+backdrop+PanelContainer shape
## _show_info_popup uses, but sized to its content (a CenterContainer
## wrapping the panel, per the pattern OverwriteConfirmOverlay/
## PauseMenu already use for their own modals) since the companion
## list here can vary in length.
func _open_companion_choice_popup() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.5)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title_label := Label.new()
	title_label.text = "Party Companion Maker"
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	vbox.add_child(title_label)

	var body_label := Label.new()
	body_label.text = "\"Someone new to travel with, or an old face you'd like back?\""
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(body_label)

	vbox.add_child(HSeparator.new())

	for companion in GameState.dismissed_companions:
		var btn := Button.new()
		btn.text = "Re-recruit %s — %s %s, %s (Tier %d)" % [
			companion.character_name,
			companion.race.race_name if companion.race else "?",
			companion.career.career_name if companion.career else "?",
			companion.career.get_level(companion.current_tier).level_name if companion.career else "?",
			companion.current_tier,
		]
		btn.pressed.connect(func(): _on_re_recruit_pressed(companion, layer))
		vbox.add_child(btn)

	vbox.add_child(HSeparator.new())

	var new_btn := Button.new()
	new_btn.text = "Recruit a Brand New Companion"
	new_btn.pressed.connect(func():
		layer.queue_free()
		_start_new_companion_creation()
	)
	vbox.add_child(new_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Not Right Now"
	cancel_btn.pressed.connect(func(): layer.queue_free())
	vbox.add_child(cancel_btn)

	backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			layer.queue_free()
			get_viewport().set_input_as_handled()
	)

func _on_re_recruit_pressed(companion: Character, layer: CanvasLayer) -> void:
	layer.queue_free()
	if GameState.party.size() >= GameState.MAX_PARTY_SIZE:
		_show_info_popup("Party Companion Maker", "\"Your party's already as large as I can help you manage — four's the most anyone can look after well on the road.\"")
		return
	GameState.dismissed_companions.erase(companion)
	GameState.add_party_member(companion)
	GameState.autosave()
	_show_info_popup("Party Companion Maker", "\"Welcome back, %s!\"" % companion.character_name)

func _open_camp() -> void:
	GameState.player_character.camp_position = player.grid_pos
	## Camp rework, per the request: Hunting/Trap Endeavours are outdoors
	## only — is_safe_area_at() already answers "is this tile inside a
	## defined Safe Area" (e.g. a village) for exactly this kind of gate
	## (field-encounter spawning already uses it the same way), so it's
	## reused here rather than inventing a second, parallel notion of
	## "in a settlement."
	GameState.camp_is_outdoors = not is_safe_area_at(player.grid_pos)
	GameState.autosave()
	get_tree().change_scene_to_file("res://scenes/Camp.tscn")

func _on_switch_character_requested() -> void:
	pause_menu.close()
	character_menu.open(SWITCH_CHARACTER_TAB_INDEX)

## Autosaves whenever the character menu closes — covers XP spends,
## equipment changes, etc. made while it was open, which don't
## themselves involve a movement step (the other autosave trigger, in
## _on_player_moved below).
func _on_character_menu_closed() -> void:
	GameState.autosave()
	## Covers the Character Menu's own "Switch Character" tab — a second
	## way active_party_index can change besides Q/E and clicking a
	## party panel (both already call this directly; this is the
	## catch-all for whatever the menu itself did while it was open).
	_apply_active_character_sprite()
	_update_hud()

## The player controller checks this before processing movement/interact
## input, so a menu being open cleanly pauses exploration without
## pausing the whole SceneTree (which would also stop UI animations).
## Per the request: the encounter fade-in text counts as a "menu"
## here too — a real gap where the player could keep moving during the
## transition into combat, since encounter_label.visible was never
## checked before.
func is_menu_open() -> bool:
	if character_menu == null or pause_menu == null or encounter_label == null:
		return false
	return character_menu.visible or pause_menu.visible or (radial_menu != null and radial_menu.backdrop.visible) or story_popup_active or encounter_label.visible or awaiting_travel_confirm

## Per the request: whether the currently loaded map is the World Map
## — used to disable WASD free-roam and click-to-move pathing there,
## since every real journey on the World Map should go through the
## actual Travel system instead (right-click a destination), which is
## what genuinely costs time, rolls Wilderness Events, and enforces
## the 8-hour travel cap. Free movement bypassed all of that.
func is_world_map_active() -> bool:
	return current_map_def != null and current_map_def.is_world_map

## Clamps the player's Camera2D to the map's own bounds so it never shows
## empty space beyond the edge — the camera's visible area must be
## smaller than the map on both axes for this to fully eliminate borders
## (see Player.tscn's Camera2D zoom).
func _apply_camera_limits() -> void:
	var camera: Camera2D = player.get_node("Camera2D")
	var map_width: int = map_rows[0].length()
	var map_height: int = map_rows.size()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = map_width * TILE_SIZE
	camera.limit_bottom = map_height * TILE_SIZE

## Per the request: re-centers the World Map drag-pan on the player,
## for whenever their actual position changes — a fresh map load, or
## arriving somewhere via real Travel — so a pan from a previous spot
## never persists into a new one it doesn't make sense for.
func _reset_world_map_camera_pan() -> void:
	_world_map_camera_offset = Vector2.ZERO
	_is_dragging_camera = false
	_drag_confirmed = false
	if player != null:
		var camera: Camera2D = player.get_node("Camera2D")
		camera.position = Vector2.ZERO

## Per the request: clears any previous shadows (so switching maps or
## rebuilding doesn't leave stale ones behind) and spawns one Sprite2D
## shadow per tall-object tile (trees, walls). Positions and angles
## themselves are set immediately after by _update_shadow_angles(),
## since that same function also needs to run on its own whenever
## time passes, without a full map rebuild.
func _rebuild_shadows() -> void:
	for child in shadow_container.get_children():
		child.queue_free()

	## See the comment above _fence_shadow_group's own declaration for
	## the full "merge without double-darkening" reasoning. Created
	## unconditionally (even on a map with no fences at all) for the
	## same reason wall_coords is always declared below regardless of
	## whether any walls exist this map — a plain, cheap, empty
	## container costs nothing and keeps this function's structure
	## uniform.
	_fence_shadow_group = CanvasGroup.new()
	_fence_shadow_group.name = "FenceShadowGroup"
	_fence_shadow_group.self_modulate = Color(1.0, 1.0, 1.0, WALL_SHADOW_COLOR.a)
	shadow_container.add_child(_fence_shadow_group)

	## Trees: unchanged — one independent Sprite2D shadow per tile,
	## silhouette-shaped and clipped against that tree's own canopy.
	## Trees are spaced apart on the map (not a reported problem), so
	## they keep the per-tile sundial-style rotation approach.
	var wall_coords: Dictionary = {}
	for coords in tile_chars:
		var ch: String = tile_chars[coords]
		if ch == "T":
			var shadow := Sprite2D.new()
			shadow.texture = SHADOW_TEXTURE_TREE
			## Per the request: the shadow's real anchor point is the
			## trunk base, not the texture's own centre — offset the
			## drawn texture so its bottom-centre pixel sits at the
			## sprite's own (0,0) local origin, which is also this
			## node's rotation pivot. Rotating around that fixed point
			## is what makes the canopy swing like a real sundial
			## gnomon while the base itself never visibly moves.
			shadow.centered = false
			## Per the request: the pivot must sit exactly on the
			## trunk's own visual tip within the texture, not an
			## assumed bottom-centre — measured directly from the
			## shadow texture's own opaque pixels, since the tree
			## silhouette (derived from real sprite art) isn't
			## perfectly symmetric and its actual base sits a little
			## left of the texture's geometric centre.
			shadow.offset = -TREE_SHADOW_PIVOT_PX
			## Per the request: the shadow must render UNDER the tree's
			## own canopy, not over it — since the canopy is baked into
			## the same opaque tile as the ground, reordering layers
			## can't achieve this. This shader clips any shadow pixel
			## that would land above the real canopy/trunk boundary
			## instead — NOT the pivot itself, which sits at the
			## trunk's own middle; clipping there would wrongly discard
			## the trunk's own upper half along with the canopy, which
			## is exactly the "no trunk visible" bug this fixes.
			var mat := ShaderMaterial.new()
			mat.shader = SHADOW_CLIP_SHADER
			mat.set_shader_parameter("clip_threshold_px", TREE_CANOPY_CLIP_PX)
			shadow.material = mat
			shadow.name = "Shadow_%d_%d" % [coords.x, coords.y]
			shadow.set_meta("tile_coords", coords)
			shadow.set_meta("ch", ch)
			## Per-shadow tile-space base position, read back in
			## _update_shadow_angles() instead of a hardcoded constant —
			## kept generalized (rather than reverting to a bare
			## constant) in case a future tile type reuses this same
			## per-tile sundial-rotation path.
			shadow.set_meta("base_px", TREE_TILE_BASE_PX)
			shadow.modulate = Color(1, 1, 1, 1)
			shadow_container.add_child(shadow)
		elif ch == "I":
			## Fence shadow — see the comment above FENCE_SHADOW_SOURCE_TEXTURE
			## (the v0.2.248 shear fix) and fence_shadow_silhouette.gdshader's
			## own comment for the full reasoning. Normally one Sprite2D per
			## fence tile, cropped (via region_rect) to this tile's own
			## cell in FENCE_SHADOW_SOURCE_TEXTURE (see
			## _resolve_fence_shadow_atlas()) — a dedicated, rail-free
			## version of the real fence art, NOT the real tileset.png the
			## TileMapLayer itself draws from. The vertical-run atlas is
			## the one exception — see the v0.2.251 comment below.
			##
			## v0.2.250 fix (still applies to every piece below):
			## `region_rect.position` only selects which pixels get
			## SAMPLED from the source texture — it has no bearing on
			## where the cropped region is drawn in the node's own LOCAL
			## space. A `Sprite2D` with `centered = false` always draws
			## its (possibly-cropped) quad starting at local `offset`,
			## regardless of which cell/row-band of the atlas
			## `region_rect` happens to be reading from, so `offset` must
			## be set independently to place this piece's own
			## ground-contact pixel at the node's local origin (0,0) —
			## which is both where "fence_pivot_px" places it in WORLD
			## space AND the one fixed point the shear transform in
			## _update_shadow_angles() never moves. (The old formula —
			## `-(cell_origin_px + FENCE_SHADOW_WORLD_ANCHOR_PX)` — folded
			## the source-texture crop position into `offset` too, which
			## happened to be harmless for cell 0 (straight-run,
			## `cell_origin_px == (0,0)`) but silently shifted every
			## OTHER cell's drawn quad a full cell-width away from the
			## real tile.)
			var fence_shadow_atlas: Vector2i = _resolve_fence_shadow_atlas(coords)
			var cell_origin_px: Vector2 = Vector2(fence_shadow_atlas.x, fence_shadow_atlas.y) * FENCE_SHADOW_CELL_SIZE_PX
			var fence_tile_topleft_px: Vector2 = tile_map.map_to_local(coords) - Vector2(tile_map.tile_set.tile_size) / 2.0
			if fence_shadow_atlas == Vector2i(1, 0):
				## v0.2.251 fix, per direct request ("the vertical fence
				## shadow should connect between posts, like this [zigzag
				## reference sketch]"): the whole-tile SHEAR below treats
				## the entire 16-row cell as one rigid object whose row
				## position encodes "height above ONE shared ground row"
				## — correct for the straight-run atlas, whose real
				## pickets genuinely stand on the tile's own bottom edge,
				## but wrong for the vertical-run atlas, whose "posts"
				## (per the v0.2.250 art fix, just above) are really 3
				## small, independent knots at different rows WITHIN the
				## same tile, each already sitting at its own local
				## ground. Shearing them as one rigid block under a
				## single shared anchor gives each post a wildly
				## different, wrong displacement purely depending on how
				## far it happens to sit from the tile's own bottom edge.
				##
				## The fix: give the vertical-run atlas THREE separate
				## shadow Sprite2D pieces instead of one, one per
				## FENCE_VERTICAL_POST_ROW_BANDS entry, each cropped to
				## just that post's own row band and anchored at its OWN
				## foot (that band's own bottom row) rather than the
				## tile's. `shear_height_px` (read back in
				## _update_shadow_angles(), which generalizes the shear's
				## divisor to a per-piece meta instead of a hardcoded
				## whole-tile 16) means every post gets the exact same
				## `dir * fence_shadow_length` reach at its own top and
				## zero displacement at its own foot, regardless of the
				## post's own height or where it sits within its tile —
				## which is what makes each post's shadow visibly grow
				## out of, and connect toward, its neighbours'.
				for band in FENCE_VERTICAL_POST_ROW_BANDS:
					var row_start: int = band.x
					var row_end: int = band.y
					var band_height: float = float(row_end - row_start + 1)
					var piece := Sprite2D.new()
					piece.texture = FENCE_SHADOW_SOURCE_TEXTURE
					piece.region_enabled = true
					piece.region_rect = Rect2(cell_origin_px + Vector2(0.0, float(row_start)), Vector2(FENCE_SHADOW_CELL_SIZE_PX.x, band_height))
					piece.centered = false
					piece.offset = -Vector2(8.0 * FX_SCALE, band_height)
					var piece_mat := ShaderMaterial.new()
					piece_mat.shader = FENCE_SHADOW_SHADER
					piece.material = piece_mat
					piece.modulate = Color(1, 1, 1, 1)
					piece.name = "ShadowFence_%d_%d_post%d" % [coords.x, coords.y, row_start]
					var piece_pivot_px: Vector2 = fence_tile_topleft_px + Vector2(8.0 * FX_SCALE, float(row_end + 1))
					piece.position = piece_pivot_px
					piece.set_meta("fence_pivot_px", piece_pivot_px)
					piece.set_meta("shear_height_px", band_height)
					piece.set_meta("is_fence_post_piece", true)
					_fence_shadow_group.add_child(piece)
				## v0.2.259: the vertical-run atlas's own rail column needs
				## a constant TRANSLATION, not the per-band shear the post
				## pieces above use -- see FENCE_VERTICAL_RAIL_COLUMN_
				## START_PX's own long comment for why. v0.2.260 split it
				## into 2 half-width lines, each with its own ratio.
				for rail_line_index in range(2):
					var rail_line_start_px: float = FENCE_VERTICAL_RAIL_COLUMN_START_PX + float(rail_line_index) * FENCE_VERTICAL_RAIL_LINE_WIDTH_PX
					var rail_piece := Sprite2D.new()
					rail_piece.texture = FENCE_SHADOW_SOURCE_TEXTURE
					rail_piece.region_enabled = true
					rail_piece.region_rect = Rect2(cell_origin_px + Vector2(rail_line_start_px, 0.0), Vector2(FENCE_VERTICAL_RAIL_LINE_WIDTH_PX, FENCE_SHADOW_CELL_SIZE_PX.y))
					rail_piece.centered = false
					rail_piece.offset = Vector2.ZERO
					var rail_mat := ShaderMaterial.new()
					rail_mat.shader = FENCE_SHADOW_SHADER
					rail_piece.material = rail_mat
					rail_piece.modulate = Color(1, 1, 1, 1)
					rail_piece.name = "ShadowFence_%d_%d_rail%d" % [coords.x, coords.y, rail_line_index]
					var rail_base_px: Vector2 = fence_tile_topleft_px + Vector2(rail_line_start_px, 0.0)
					rail_piece.position = rail_base_px
					rail_piece.set_meta("fence_rail_base_px", rail_base_px)
					rail_piece.set_meta("fence_rail_ratio", FENCE_VERTICAL_RAIL_SHADOW_RATIO_A if rail_line_index == 0 else FENCE_VERTICAL_RAIL_SHADOW_RATIO_B)
					_fence_shadow_group.add_child(rail_piece)
			else:
				var shadow := Sprite2D.new()
				shadow.texture = FENCE_SHADOW_SOURCE_TEXTURE
				shadow.region_enabled = true
				shadow.region_rect = Rect2(cell_origin_px, FENCE_SHADOW_CELL_SIZE_PX)
				shadow.centered = false
				shadow.offset = -FENCE_SHADOW_WORLD_ANCHOR_PX
				var fence_mat := ShaderMaterial.new()
				fence_mat.shader = FENCE_SHADOW_SHADER
				shadow.material = fence_mat
				shadow.modulate = Color(1, 1, 1, 1)
				shadow.name = "ShadowFence_%d_%d" % [coords.x, coords.y]
				var fence_pivot_px: Vector2 = fence_tile_topleft_px + FENCE_SHADOW_WORLD_ANCHOR_PX
				shadow.position = fence_pivot_px
				shadow.set_meta("fence_pivot_px", fence_pivot_px)
				_fence_shadow_group.add_child(shadow)
				## v0.2.263/265: NE/NW corners get 2 extra translated
				## rail pieces covering their own FULL rail column --
				## see FENCE_CORNER_RAIL_TAIL_ATLAS_CELLS's own long
				## comment for the full reasoning.
				if fence_shadow_atlas in FENCE_CORNER_RAIL_TAIL_ATLAS_CELLS:
					for rail_line_index in range(2):
						var tail_line_start_px: float = FENCE_VERTICAL_RAIL_COLUMN_START_PX + float(rail_line_index) * FENCE_VERTICAL_RAIL_LINE_WIDTH_PX
						var tail_piece := Sprite2D.new()
						tail_piece.texture = FENCE_SHADOW_SOURCE_TEXTURE
						tail_piece.region_enabled = true
						tail_piece.region_rect = Rect2(cell_origin_px + Vector2(tail_line_start_px, FENCE_CORNER_RAIL_TAIL_ROW_START), Vector2(FENCE_VERTICAL_RAIL_LINE_WIDTH_PX, FENCE_CORNER_RAIL_TAIL_ROW_COUNT))
						tail_piece.centered = false
						tail_piece.offset = Vector2.ZERO
						var tail_mat := ShaderMaterial.new()
						tail_mat.shader = FENCE_SHADOW_SHADER
						tail_piece.material = tail_mat
						tail_piece.modulate = Color(1, 1, 1, 1)
						tail_piece.name = "ShadowFence_%d_%d_railtail%d" % [coords.x, coords.y, rail_line_index]
						var tail_base_px: Vector2 = fence_tile_topleft_px + Vector2(tail_line_start_px, FENCE_CORNER_RAIL_TAIL_ROW_START)
						tail_piece.position = tail_base_px
						tail_piece.set_meta("fence_rail_base_px", tail_base_px)
						tail_piece.set_meta("fence_rail_ratio", FENCE_VERTICAL_RAIL_SHADOW_RATIO_A if rail_line_index == 0 else FENCE_VERTICAL_RAIL_SHADOW_RATIO_B)
						_fence_shadow_group.add_child(tail_piece)
					## v0.2.264: fake post pieces filling the corner's
					## own bare row-band gap -- see FENCE_CORNER_FAKE_
					## POST_ROW_BANDS's own long comment.
					var vertical_atlas_cell_origin_px: Vector2 = Vector2(1.0, 0.0) * FENCE_SHADOW_CELL_SIZE_PX
					for band in FENCE_CORNER_FAKE_POST_ROW_BANDS:
						var fake_row_start: int = band.x
						var fake_row_end: int = band.y
						var fake_band_height: float = float(fake_row_end - fake_row_start + 1)
						var fake_piece := Sprite2D.new()
						fake_piece.texture = FENCE_SHADOW_SOURCE_TEXTURE
						fake_piece.region_enabled = true
						fake_piece.region_rect = Rect2(vertical_atlas_cell_origin_px + Vector2(0.0, float(fake_row_start)), Vector2(FENCE_SHADOW_CELL_SIZE_PX.x, fake_band_height))
						fake_piece.centered = false
						fake_piece.offset = -Vector2(8.0 * FX_SCALE, fake_band_height)
						var fake_mat := ShaderMaterial.new()
						fake_mat.shader = FENCE_SHADOW_SHADER
						fake_piece.material = fake_mat
						fake_piece.modulate = Color(1, 1, 1, 1)
						fake_piece.name = "ShadowFence_%d_%d_fakepost%d" % [coords.x, coords.y, fake_row_start]
						var fake_pivot_px: Vector2 = fence_tile_topleft_px + Vector2(8.0 * FX_SCALE, float(fake_row_end + 1))
						fake_piece.position = fake_pivot_px
						fake_piece.set_meta("fence_pivot_px", fake_pivot_px)
						fake_piece.set_meta("shear_height_px", fake_band_height)
						fake_piece.set_meta("is_fence_post_piece", true)
						_fence_shadow_group.add_child(fake_piece)
		elif ch in SHADOW_CASTING_CHARS:
			wall_coords[coords] = ch

	## Walls/buildings: merged per contiguous run — horizontal AND
	## vertical (see _find_wall_shadow_rects()) — instead of one
	## Sprite2D per tile, so adjacent wall tiles in the same row OR the
	## same column share one seamless flat-fill shadow shape instead of
	## each tile's shadow fanning out independently from its own pivot
	## and visibly separating from its neighbours' at non-midday sun
	## angles. Each run's polygon is built from the run's own full
	## footprint (all 4 corners of its tile-grid rectangle) extruded
	## along the sun direction, with the footprint itself then clipped
	## back out via Geometry2D.clip_polygons() — leaving only the swept
	## area beyond the tiles, never the tiles' own visible face. This
	## generalises cleanly to any run shape (1 wide, 1 tall, or a lone
	## tile) unlike the old bottom-edge-only trick, which only worked
	## for horizontal runs (a vertical run's tiles don't share one
	## colinear bottom edge). The polygon itself is recomputed every
	## time the sun moves, in _update_shadow_angles().
	##
	## Per the "move the outside shadow to the bottom of the back wall"
	## request: at a low sun angle `dir` sweeps mostly SIDEWAYS (see its
	## own comment in _update_shadow_angles()), so a HORIZONTAL run's
	## (front/back wall) full-rectangle footprint lets the swept sliver
	## drag along that row's own LEFT/RIGHT edge too, not just its
	## bottom — and since a back-wall row's own top edge sits at the
	## true exterior/roofline boundary of the building, the resulting
	## sideways wedge visibly hangs from up near the roof instead of
	## from the wall's own base, where a real cast shadow would
	## originate. Reintroducing the "old bottom-edge-only trick" the
	## comment above mentions — but scoped ONLY to a run that's genuinely
	## a building's own BACK (north) wall row (see
	## _is_building_north_wall_run()), never the front wall — the front
	## wall's own row already sits at the building's true south/exterior
	## edge, so its full rectangle was never visually wrong, and (per
	## the "side wall no longer merges with the front wall" regression
	## report) shrinking it to a floating bottom-edge line pulled its
	## swept piece away from the row13/14 boundary the west/east wall's
	## own full-rectangle piece touches there, breaking the corner merge
	## _union_polygon_into() relies on. Collapsing the footprint to a
	## zero-height line along the run's own bottom edge before extrusion
	## means the swept shadow can only ever hang off that bottom edge,
	## never the row's own top — but only for the one wall run that
	## actually had that problem.
	var tile_size: Vector2 = Vector2(tile_map.tile_set.tile_size)
	for rect in _find_wall_shadow_rects(wall_coords):
		var top_left_center: Vector2 = tile_map.map_to_local(rect.position)
		var bottom_right_center: Vector2 = tile_map.map_to_local(rect.position + rect.size - Vector2i(1, 1))
		var x_left: float = top_left_center.x - tile_size.x / 2.0
		var y_top: float = top_left_center.y - tile_size.y / 2.0
		var x_right: float = bottom_right_center.x + tile_size.x / 2.0
		var y_bottom: float = bottom_right_center.y + tile_size.y / 2.0
		var footprint: PackedVector2Array
		if rect.size.y == 1 and _is_building_north_wall_run(rect):
			footprint = PackedVector2Array([
				Vector2(x_left, y_bottom),
				Vector2(x_right, y_bottom),
				Vector2(x_right, y_bottom),
				Vector2(x_left, y_bottom),
			])
		else:
			footprint = PackedVector2Array([
				Vector2(x_left, y_top),
				Vector2(x_right, y_top),
				Vector2(x_right, y_bottom),
				Vector2(x_left, y_bottom),
			])
		var shadow := Polygon2D.new()
		shadow.color = WALL_SHADOW_COLOR
		shadow.name = "ShadowWall_%d_%d_%d_%d" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		shadow.set_meta("footprint_px", footprint)
		shadow_container.add_child(shadow)

	for child in tree_canopy_overlay.get_children():
		child.queue_free()
	for coords in tile_chars:
		if tile_chars[coords] == "T":
			var canopy := Sprite2D.new()
			canopy.texture = TREE_CANOPY_OVERLAY_TEXTURE
			canopy.centered = false
			## Per the "let the canopy spread into neighboring tiles"
			## request: this texture is now bigger than one tile (see
			## TREE_OVERLAY_ANCHOR_PX's own comment), so simply anchoring
			## it at the tile's own top-left corner (the old, tile-sized-
			## texture approach) would shift the WHOLE bigger canopy off
			## to one side instead of growing outward from the tree's own
			## trunk. offset shifts the sprite's local draw rect so the
			## anchor pixel sits at this node's own local origin, and
			## position places that origin at the exact same real-world
			## "trunk planted here" point every other tree measurement in
			## this file (TREE_TILE_BASE_PX) already uses — same pattern
			## the shadow sprites use for the same reason.
			canopy.offset = -TREE_OVERLAY_ANCHOR_PX
			canopy.position = tile_map.map_to_local(coords) + (TREE_TILE_BASE_PX - Vector2(tile_map.tile_set.tile_size) / 2.0)
			canopy.name = "Canopy_%d_%d" % [coords.x, coords.y]
			tree_canopy_overlay.add_child(canopy)

	## Per the follow-up request ("secondary shadows for light
	## sources"): rebuilt fresh here too, same as _fence_shadow_group
	## above — the pooled sprites from the PREVIOUS map (if any) were
	## children of the old light_shadow_container, already swept away
	## by the child.queue_free() loop at the very top of this function
	## alongside every other shadow_container child; without this reset,
	## _light_shadow_sprites would still be full of now-freed node
	## references. Added as the LAST child of shadow_container — after
	## every tree/wall/fence shadow above — so it draws on top of them.
	## Per the "stop stacking shadows (making them darker)" request: a
	## CanvasGroup instead of a plain Node2D — same fix, same reason, as
	## _fence_shadow_group's own CanvasGroup (see its comment for the
	## full explanation): renders every child (tree/person blob sprites,
	## merged wall-shadow polygons) into one shared offscreen buffer
	## before compositing that buffer as a whole onto the scene, so where
	## two secondary-shadow shapes overlap (two nearby trees under the
	## same torch, or a wall's own merged shadow crossing a tree's), the
	## overlap just shows whichever child is on top instead of two
	## separate translucent draws stacking into a visibly darker patch.
	## Children are drawn fully OPAQUE (see the modulate/color = Color(1,
	## 1,1,1) assignments in _apply_light_source_secondary_shadows()
	## below) precisely so this works — self_modulate (set every frame
	## to night_overlay.color, matching the "same darkness as normal
	## night darkness" request) supplies the actual translucency exactly
	## once for the flattened result.
	light_shadow_container = CanvasGroup.new()
	light_shadow_container.name = "LightShadowContainer"
	shadow_container.add_child(light_shadow_container)
	_light_shadow_sprites.clear()
	## Same reset, same reason, for the merged building-shadow polygons
	## — the previous map's pooled Polygon2D nodes were direct children
	## of light_shadow_container too, already swept away above.
	_light_wall_shadow_nodes.clear()

	## Per the "add 2 static lamps... come on at night time and cast
	## secondary shadows" request: one glow Sprite2D per lamp, plus this
	## map build's own fresh secondary-shadow pool for each lamp — see
	## _static_lamp_glow_container's own comment for why the glow lives
	## OUTSIDE shadow_container (it must not inherit the day/night
	## MOON_SHADOW_TINT cascade the way every real shadow here does).
	if is_instance_valid(_static_lamp_glow_container):
		_static_lamp_glow_container.queue_free()
	_static_lamp_glow_container = Node2D.new()
	_static_lamp_glow_container.name = "StaticLampGlowContainer"
	_static_lamp_glow_container.z_index = above_buildings_z - 1
	add_child(_static_lamp_glow_container)
	_static_lamp_glow_sprites.clear()
	## The lamps' own cast-shadow container: a sibling of
	## light_shadow_container, added last (after it) so a lamp's shadow
	## draws on top of every tree/wall/fence shadow the same way the
	## carried-light shadows already do — freed alongside every other
	## shadow_container child by the queue_free() loop at the top of
	## this function, so a fresh one is always created here.
	## Same CanvasGroup fix, same reason, as light_shadow_container just
	## above — see its own comment.
	_static_lamp_shadow_container = CanvasGroup.new()
	_static_lamp_shadow_container.name = "StaticLampShadowContainer"
	shadow_container.add_child(_static_lamp_shadow_container)
	_static_lamp_tile_shadow_sprites.clear()
	_static_lamp_wall_shadow_nodes.clear()
	_static_lamp_blocked_tiles.clear()
	var lamp_tile_size: Vector2 = Vector2(tile_map.tile_set.tile_size)
	for lamp_index in range(static_lamp_coords.size()):
		var lamp_coords: Vector2i = static_lamp_coords[lamp_index]
		var glow := Sprite2D.new()
		glow.texture = LAMP_GLOW_TEXTURE
		glow.name = "LampGlow_%d_%d" % [lamp_coords.x, lamp_coords.y]
		## Centred over the lamp head (roughly the upper-middle of the
		## 64x64 tile art — see make_lamp.py's own head_top/head_bot,
		## the post's foot sits down near the tile's bottom edge instead)
		## rather than the tile's own geometric centre.
		var lamp_tile_topleft: Vector2 = tile_map.map_to_local(lamp_coords) - lamp_tile_size / 2.0
		glow.position = lamp_tile_topleft + Vector2(32.0, 15.0)
		glow.modulate = Color(1.0, 0.85, 0.55, 0.0)   ## starts fully faded; alpha driven by night_amount in _update_shadow_angles()
		_static_lamp_glow_container.add_child(glow)
		_static_lamp_glow_sprites[lamp_coords] = glow
		## Per-lamp pooled shadow structures, same shape
		## _light_shadow_sprites/_light_wall_shadow_nodes use for the
		## player's own carried light, indexed by this lamp's own slot.
		_static_lamp_tile_shadow_sprites[lamp_index] = {}
		_static_lamp_wall_shadow_nodes[lamp_index] = []

	_update_shadow_angles()

## Per the "light sources... should only light up things with LOS,
## everything out of LOS should remain normal night darkness" request:
## a direct 8-directional line from `from` to `to`, same Bresenham
## algorithm as BattleGrid.direct_line() (ported rather than reused —
## the overworld's own tile grid is a separate, much larger space with
## its own blocking rules, not the battle grid's). Excludes `from`,
## includes `to`.
static func _direct_line(from: Vector2i, to: Vector2i) -> Array:
	var points: Array = []
	var x0 := from.x
	var y0 := from.y
	var x1 := to.x
	var y1 := to.y
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while x0 != x1 or y0 != y1:
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
		points.append(Vector2i(x0, y0))
	return points

## True when nothing in LIGHT_BLOCKING_WALL_CHARS lies strictly between
## `from` and `to` — same convention BattleGrid.has_line_of_sight()
## already uses (the destination tile itself never blocks its own
## visibility; you can always see the wall you're looking straight at,
## it's what's BEHIND it that's hidden). Every non-wall-material tile
## (fences, trees, furniture, the well, a lamp post) is deliberately NOT
## sight-blocking here. Per the "treat walls with doors like normal
## walls for the purpose of shadows" follow-up: doors ("d") now DO block
## LOS here, same as any other wall tile — a closed door reads as a
## solid wall to a torch/lamp, not a window, so LIGHT_BLOCKING_WALL_CHARS
## (WALL_MATERIAL_CHARS + "d") is used instead of the plain
## WALL_MATERIAL_CHARS this used to check (see that constant's own
## comment for why footprint/roof detection still needs "d" excluded
## while shadow/LOS logic needs it included).
func _has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var line: Array = _direct_line(from, to)
	for i in range(line.size() - 1):
		var ch: String = tile_chars.get(line[i], "")
		if ch in LIGHT_BLOCKING_WALL_CHARS:
			return false
	return true

## Every tile within `range_tiles` (Euclidean, matching the range checks
## the secondary-shadow systems already use) of `light_tile` that also
## has a clear _has_line_of_sight() to it — this light's own real
## "what does it actually illuminate" set. Always includes light_tile
## itself. Used by _update_shadow_angles() to decide exactly which
## primary tree/person shadow sprites a nearby light source should
## suppress (see its own comment) — deliberately NOT used for the
## per-frame secondary-shadow eligibility loops (those inline their own
## LOS check per tile instead, to avoid building a full Dictionary every
## single frame for what's already a single pass over the same tiles).
func _light_visible_tiles(light_tile: Vector2i, range_tiles: int) -> Dictionary:
	var visible: Dictionary = {light_tile: true}
	for dy in range(-range_tiles, range_tiles + 1):
		for dx in range(-range_tiles, range_tiles + 1):
			if dx == 0 and dy == 0:
				continue
			if Vector2(dx, dy).length() > float(range_tiles):
				continue
			var coords: Vector2i = light_tile + Vector2i(dx, dy)
			if _has_line_of_sight(light_tile, coords):
				visible[coords] = true
	return visible

## A plain N-gon approximating a light's own illuminated circle, used
## only to clip PRIMARY wall-shadow polygons away from an active light
## source (see the "remove primary shadows where their light falls"
## comment in _update_shadow_angles()) — deliberately a circle, not the
## exact LOS-shaped tile set _light_visible_tiles() computes, since
## unioning potentially hundreds of individual tile rects into one
## polygon on every call here would cost far more than this
## comparatively minor visual refinement is worth. A wall shadow clipped
## a little more generously than the true LOS boundary right next to a
## light is a small, forgivable imprecision; under-clipping the
## darkness-reveal itself (see _refresh_light_occlusion()) would not be.
func _light_disc_polygon(center: Vector2, radius: float, segments: int = 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return pts

## Small helper for _update_shadow_angles()'s wall-shadow branch, same
## shape as _clip_piece_against_buildings() — subtracts every active
## light's own _light_disc_polygon() from `piece` in turn.
func _clip_piece_against_light_discs(piece: PackedVector2Array, light_discs: Array) -> Array:
	if piece.size() == 0:
		return []
	var candidates: Array = [piece]
	for disc in light_discs:
		var disc_poly: PackedVector2Array = _light_disc_polygon(disc["pos"], disc["radius"])
		var next_candidates: Array = []
		for candidate in candidates:
			next_candidates.append_array(Geometry2D.clip_polygons(candidate, disc_poly))
		candidates = next_candidates
		if candidates.is_empty():
			break
	return candidates

## Per the "move the outside shadow to the bottom of the back wall"
## fix (see _rebuild_shadows()): true when `rect` is a horizontal wall
## run that sits exactly on some building's own NORTH (back) row — its
## `position.y` matches that building's own top row, and it falls
## within that building's own column span. Deliberately narrower than
## "any wide horizontal run," which would also catch a front (south)
## wall row and give it the same bottom-edge-only treatment that row
## never needed — see the regression this was scoped down from ("side
## wall no longer merges with the front wall").
func _is_building_north_wall_run(rect: Rect2i) -> bool:
	if rect.size.y != 1:
		return false
	for b in buildings:
		if b.position.y == rect.position.y and rect.position.x >= b.position.x and rect.position.x + rect.size.x <= b.position.x + b.size.x:
			return true
	return false

## Groups wall/building tiles into maximal runs — horizontal
## (contiguous columns within the same row) AND vertical (contiguous
## rows within the same column) — so _rebuild_shadows() can draw ONE
## merged shadow per run instead of one per tile. Returns tile-grid
## rects (Rect2i, in tile coordinates, not pixels). Horizontal runs are
## claimed first; a tile a horizontal run of length >= 2 already
## covers is never also considered for a vertical run, so a corner
## tile joins whichever run direction it was found in first rather
## than both — a small compromise at corners, but it keeps every rect
## exactly one-tile-thick in ONE dimension (never a full 2D block),
## which is what stops a hollow building outline (e.g. a "#####" /
## "#...#" / "#####" perimeter) from ever getting its interior wrongly
## filled in — only the wall tiles themselves ever contribute a rect.
## Any tile left over after both passes (no same-row AND no
## same-column wall neighbour) comes back as its own isolated 1x1
## rect, so every wall tile is covered by exactly one rect.
func _find_wall_shadow_rects(wall_coords: Dictionary) -> Array[Rect2i]:
	var covered: Dictionary = {}
	var rects: Array[Rect2i] = []

	var by_row: Dictionary = {}
	for coords in wall_coords:
		if not by_row.has(coords.y):
			by_row[coords.y] = []
		by_row[coords.y].append(coords.x)
	for y in by_row:
		var xs: Array = by_row[y]
		xs.sort()
		for run in _find_runs(xs):
			if run[1] > run[0]:
				rects.append(Rect2i(Vector2i(run[0], y), Vector2i(run[1] - run[0] + 1, 1)))
				for x in range(run[0], run[1] + 1):
					covered[Vector2i(x, y)] = true

	var by_col: Dictionary = {}
	for coords in wall_coords:
		if covered.has(coords):
			continue
		if not by_col.has(coords.x):
			by_col[coords.x] = []
		by_col[coords.x].append(coords.y)
	for x in by_col:
		var ys: Array = by_col[x]
		ys.sort()
		for run in _find_runs(ys):
			if run[1] > run[0]:
				rects.append(Rect2i(Vector2i(x, run[0]), Vector2i(1, run[1] - run[0] + 1)))
				for y in range(run[0], run[1] + 1):
					covered[Vector2i(x, y)] = true

	for coords in wall_coords:
		if not covered.has(coords):
			rects.append(Rect2i(coords, Vector2i(1, 1)))
			covered[coords] = true

	return rects

## Small helper: given a sorted Array of ints, returns its maximal
## consecutive runs as [start, end] pairs.
func _find_runs(sorted_vals: Array) -> Array:
	var runs: Array = []
	var start = sorted_vals[0]
	var prev = sorted_vals[0]
	for i in range(1, sorted_vals.size()):
		var v = sorted_vals[i]
		if v == prev + 1:
			prev = v
		else:
			runs.append([start, prev])
			start = v
			prev = v
	runs.append([start, prev])
	return runs

## Per the request: shadows sweep from pointing west (long, dawn)
## through pointing south (shortest, near midday) to pointing east
## (long, dusk), and disappear entirely outside that window since
## there's no sun to cast them. Called once right after
## _rebuild_shadows() spawns the sprites, and again from
## _update_hud() every time it refreshes (movement, waiting, etc.) so
## the angle keeps advancing with the clock without needing a full
## rebuild each time.
## Per the day/night rework request ("make sure shadows are shown
## during [the dawn/dusk transition]"): widened from the old
## 8am-8pm window to 7am-9pm, matching GameState's own dawn
## (07:00-08:00) and dusk (20:00-21:00) transition windows exactly —
## shadows now stay visible for the full time there's any sun in the
## sky at all, not just during the flat-daylight core.
const SUNRISE_MINUTES := 7 * 60
const SUNSET_MINUTES := 21 * 60
## Small helper for _update_shadow_angles()'s Player/NPC pass: looks up
## the "Shadow" child added by _make_person_shadow() and no-ops if it
## isn't there (defensive — every real spawn site adds one, but this
## keeps a future spawn site that forgets to from hard-erroring the
## whole HUD refresh). Shadows are visible around the clock now (day
## sun / night moon — see _update_shadow_angles()), so there's no
## longer a separate "hide it outright" helper to go with this one.
func _update_person_shadow(owner_node: Node, target_rotation: float, length_factor: float, tint: Color = Color(1, 1, 1, 1)) -> void:
	## NPCs pass their own (already-scaled) Sprite2D as owner_node, so
	## "Shadow" is a direct child of it (see the various _spawn_*
	## functions' `sprite.add_child(_make_person_shadow())`). The Player
	## passes its plain Node2D wrapper instead, with Shadow nested one
	## level deeper under its Sprite2D child (see _ready()'s
	## `player.get_node("Sprite2D").add_child(...)`) — checked as a
	## fallback so this one function still serves both shapes.
	var shadow: Node = owner_node.get_node_or_null("Shadow")
	if shadow == null:
		shadow = owner_node.get_node_or_null("Sprite2D/Shadow")
	if shadow is Sprite2D:
		var s: Sprite2D = shadow as Sprite2D
		s.visible = true
		s.rotation = target_rotation
		s.scale = Vector2(0.7, 0.75 + length_factor * 0.35)
		## Per the request ("subtle moon glow+shadows during the
		## night"): Player/NPC shadows live outside shadow_container
		## (each is a child of its own owner's sprite, not the shared
		## container — see _make_person_shadow()), so they need their
		## own tint applied directly rather than inheriting
		## shadow_container's modulate the way tree/wall/fence shadows
		## do below.
		s.modulate = tint

## How far into the night window (dusk's end through the next dawn's
## start, wrapping past midnight) the given minute-of-day sits, as
## 0.0-1.0 — the moon-shadow counterpart to the sun's own `progress`
## below. Picks up exactly at 0.0 where the sun's own sweep left off
## (SUNSET_MINUTES) and reaches 1.0 exactly where the sun's sweep
## resumes (SUNRISE_MINUTES the next morning), so the two windows tile
## the full 24 hours with no gap and no overlap.
func _night_shadow_progress(t: int) -> float:
	var elapsed: int = (t - SUNSET_MINUTES) if t >= SUNSET_MINUTES else (t + 1440 - SUNSET_MINUTES)
	var window_len: int = SUNRISE_MINUTES + 1440 - SUNSET_MINUTES
	return clamp(float(elapsed) / float(window_len), 0.0, 1.0)

func _update_shadow_angles() -> void:
	var t: int = GameState.time_minutes
	var is_daytime: bool = t >= SUNRISE_MINUTES and t <= SUNSET_MINUTES
	## Per the request ("subtle moon glow+shadows during the night"):
	## shadows used to switch off entirely outside the 7am-9pm sun-up
	## window. They now stay visible around the clock — dim and cool
	## blue at night ("moon shadows"), fading smoothly in and out with
	## GameState's own dusk/night/dawn darkness curve below, rather than
	## a hard on/off cut.
	shadow_container.visible = true
	var dir: Vector2
	var length_factor: float
	if is_daytime:
		var progress: float = float(t - SUNRISE_MINUTES) / float(SUNSET_MINUTES - SUNRISE_MINUTES)
		## Direction sweeps from west-ish (-1, small south bias) through
		## south (0, 1) to east-ish (1, small south bias) — a fixed
		## downward bias throughout, since a top-down game's shadows
		## conventionally fall "down and to the side," never straight up.
		dir = Vector2(lerp(-1.0, 1.0, progress), 0.35).normalized()
		## Longest at dawn/dusk (progress near 0 or 1), shortest near
		## midday (progress near 0.5) — never fully zero, real shadows
		## don't vanish outright even with the sun near its peak.
		length_factor = 0.35 + 0.65 * abs(progress - 0.5) * 2.0
	else:
		## Moon shadows: the same style of sweep, just over the night
		## window instead of the day one, and picking up exactly where
		## the sun's own sweep left off at dusk (east-ish, +1) so there's
		## no directional "pop" at the handoff — see
		## _night_shadow_progress()'s own comment.
		var night_progress: float = _night_shadow_progress(t)
		dir = Vector2(lerp(1.0, -1.0, night_progress), 0.35).normalized()
		length_factor = 0.35 + 0.65 * abs(night_progress - 0.5) * 2.0
	## The texture's own natural "up" direction (canopy, away from the
	## pivot at its base) is -90°/-PI/2 before any rotation — this is
	## the correction needed to point that same direction at `dir`
	## instead, so the canopy genuinely swings to match the sun (or, at
	## night, the moon).
	var target_rotation: float = dir.angle() + PI / 2.0
	## Per the request: shadows dim and cool toward blue as night
	## darkness deepens, reusing GameState's own existing dusk/night/
	## dawn darkness curve exactly — so the shadow tint eases in and out
	## in perfect lockstep with the night overlay itself, rather than
	## tracking a separately-tuned timeline. shadow_container's own
	## `modulate` (not self_modulate) cascades multiplicatively to every
	## child, including the fence CanvasGroup's own self_modulate, so
	## this one line tints every tree/wall/fence shadow on the map at
	## once without touching any of their own carefully-tuned colors.
	var night_amount: float = GameState.get_night_darkness() / GameState.NIGHT_DARKNESS_MAX
	var shadow_tint: Color = Color(1, 1, 1, 1).lerp(MOON_SHADOW_TINT, night_amount)
	shadow_container.modulate = shadow_tint
	## Per the follow-up request ("make the secondary shadows a lot
	## darker"): shadow_container.modulate above cascades down to
	## light_shadow_container too (it's a child, added in
	## _rebuild_shadows()), so MOON_SHADOW_TINT's own 0.6 alpha was
	## quietly capping the secondary shadows' own SECONDARY_LIGHT_
	## SHADOW_ALPHA_NEAR/FAR at a fraction of what they're tuned for —
	## bumping those constants alone couldn't fully compensate since
	## modulate alpha can't exceed 1.0. Counter-multiplying
	## light_shadow_container's own modulate alpha here cancels that
	## cascade out (while deliberately leaving the RGB tint alone, so
	## the torch-thrown shadows still cool toward blue at night same as
	## every other shadow on the map) — the secondary system's own
	## alpha constants are then the true, uncapped final result.
	if is_instance_valid(light_shadow_container):
		light_shadow_container.modulate = Color(1.0, 1.0, 1.0, 1.0 / max(shadow_tint.a, 0.05))
	## Same counter-multiply, same reason, for each static lamp's own
	## cast shadows.
	if is_instance_valid(_static_lamp_shadow_container):
		_static_lamp_shadow_container.modulate = Color(1.0, 1.0, 1.0, 1.0 / max(shadow_tint.a, 0.05))
	## Per the "add 2 static lamps... come on at night time" request:
	## each lamp's glow sprite fades in/out with night_amount, over the
	## narrower LAMP_GLOW_FADE_START..END band (see that const's own
	## comment) — deliberately NOT parented under shadow_container (see
	## _static_lamp_glow_container's own comment), so this is the one
	## place its own fade has to be driven explicitly rather than
	## inheriting shadow_container.modulate the way every real shadow
	## sprite above does.
	## 0..1 "how lit is a static lamp right now" ratio, shared by the
	## glow sprite's own alpha here AND the night-overlay/cloud-shadow
	## reveal punched through by _apply_static_lamp_overlay() every
	## frame — kept as a member so that per-frame function can read the
	## same value _update_shadow_angles() (event-driven, not per-frame)
	## last computed, rather than recomputing night_amount itself.
	_lamp_night_factor = clamp((night_amount - LAMP_GLOW_FADE_START) / (LAMP_GLOW_FADE_END - LAMP_GLOW_FADE_START), 0.0, 1.0)
	for lamp_coords in _static_lamp_glow_sprites:
		var glow_sprite: Sprite2D = _static_lamp_glow_sprites[lamp_coords]
		if is_instance_valid(glow_sprite):
			glow_sprite.modulate.a = LAMP_GLOW_MAX_ALPHA * _lamp_night_factor
	## Per the request: the Player and every friendly NPC swing their
	## own shadow through the exact same angle/length as trees and
	## walls right here, so the whole map's shadows always read as cast
	## by one consistent light source (the sun by day, the moon by
	## night).
	_update_person_shadow(player, target_rotation, length_factor, shadow_tint)
	for npc_sprite in npc_sprites_by_tile.values():
		_update_person_shadow(npc_sprite, target_rotation, length_factor, shadow_tint)
	## Wall/building run shadows are flat-fill polygons extruded along
	## the same `dir` used for trees (see _find_wall_shadow_rects()) —
	## a straight Minkowski-style extension of the run's own full
	## footprint, rather than a rotated sprite, so a merged run never
	## has an internal seam regardless of how long (or tall) it is.
	## The footprint itself is then clipped back out of the extruded
	## hull (Geometry2D.clip_polygons), so the result never covers any
	## part of the wall tiles' own visible face — only the swept area
	## beyond them. This works the same way for a horizontal run, a
	## vertical run, or a lone tile, since it only ever depends on the
	## run's own rectangle, never which direction it happens to run in.
	var wall_shadow_length: float = Vector2(tile_map.tile_set.tile_size).y * (0.65 + length_factor * 0.55)
	var wall_extension: Vector2 = dir * wall_shadow_length
	## Fence shadows: a SHEAR now (v0.2.248 — see the comment above
	## FENCE_SHADOW_SOURCE_TEXTURE), expressed as a plain Transform2D on
	## each shadow's own Sprite2D node rather than any per-pixel shader
	## resample. `fence_shadow_length` keeps the same 4-11px reach every
	## fence shadow build has used since v0.2.245 — only HOW that reach
	## is expressed changed. The per-shadow shear below is how many
	## pixels a point shifts per pixel of height above the base row —
	## dividing by that piece's own `shear_height_px` meta (its own crop
	## height; see the v0.2.251 comment in _rebuild_shadows(), defaults
	## to 16 — the whole tile's own full height — for straight-run/corner
	## pieces that never set it) means a point at the very top of THAT
	## piece (its own maximum possible height above its own base) shifts
	## by exactly `dir * fence_shadow_length` in total, the same "how far
	## the shadow reaches" quantity used everywhere else, while the base
	## row itself (height above base = 0) never shifts at all, no matter
	## what this value is — true for every piece regardless of its own
	## height, which is what gives short vertical-run post shadows and
	## tall straight-run picket shadows the same reach.
	##
	## The shear as a 2x2 matrix — and the one place this design's first
	## draft (see the fs6 screenshot debugging session, since reverted)
	## got the math wrong. The fence sprite's own real art occupies
	## LOCAL y in [-16, -1] — "north" of the base — since that's how a
	## standing object's height is drawn in this top-down game (the
	## sprite extends UP on screen from its ground-contact point; see
	## FENCE_SHADOW_WORLD_ANCHOR_PX's comment). A real shadow is a flat
	## shape lying ON THE GROUND, thrown out to the SOUTH side of the
	## base (the side away from the object's own drawn body) by an
	## amount proportional to each point's height. Naively shearing the
	## sprite's own (lx, ly) — i.e. literally sliding the existing
	## north-side pixels sideways — keeps the whole result on the SAME
	## north side the real object already occupies (just compressed
	## toward the base), so the "shadow" ends up overlapping the fence's
	## own footprint instead of falling away from it into the grass.
	## The fix is to throw away the source row's own y entirely and
	## rebuild the output position purely from the per-height offset:
	## a local point (lx, ly), with height above base h = -ly, maps to
	## (lx - shear.x*ly, -shear.y*ly) — note the second component has NO
	## "+ly" term, so the base row (h=0) still maps to the origin
	## untouched, but every row above it lands SOUTH of the base
	## (positive local y, since shear.y is always non-negative) instead
	## of staying north alongside the real fence art. That's a
	## Transform2D with x_axis (1,0) unchanged, y_axis
	## (-shear.x, -shear.y), origin at the fence's own fixed
	## ground-contact point.
	var fence_shadow_length: float = (4.0 + 7.0 * length_factor) * FX_SCALE
	## Per the reported "double shadow" bug: at a low sun angle, a
	## horizontal wall run's own shadow doesn't just fall straight
	## below it — it sweeps mostly SIDEWAYS, so it can reach into the
	## same ground area as a perpendicular run's shadow right next to
	## it (e.g. a building's top wall run and its own left-side wall
	## tile, at the corner where they meet). Each run's shadow used to
	## be computed and assigned to its OWN Polygon2D node completely
	## independently, so that shared corner area got drawn TWICE —
	## once by each node — and two overlapping semi-transparent shapes
	## stack into a visibly darker patch than either alone. Fixed by
	## computing every run's own raw clipped piece first (unchanged),
	## then unioning them ALL together (_union_polygon_into()) before
	## handing pieces back to nodes — the union guarantees no two
	## nodes' polygons ever cover the same ground twice, so there's
	## nothing left to double up regardless of how many separate wall
	## runs reach into the same corner.
	##
	## Per the "align the back wall's shadow" / "remove shadows inside
	## buildings" request: the sun/moon sweep direction (`dir`) always
	## carries a fixed southward bias (see its own comment above), so
	## a run's shadow always extends "further south" of its own tile —
	## which for a NORTH (back) wall row means straight onto that same
	## building's own interior floor. Invisible from outside (the roof
	## covers it), but a wrongly-placed dark smear once the player
	## steps inside and the roof itself hides. Every wall run's raw
	## piece below is now clipped against every building's own
	## world-space rectangle (see _clip_piece_against_buildings()) — no
	## wall's shadow can cover ANY building's interior or walls, not
	## just the one it belongs to, so a neighbour's shadow can't bleed
	## into a building either. Building interiors sit under a roof and
	## never receive sun/moon light in the first place, so removing the
	## overlap is the physically-correct fix, not just a visibility
	## patch — this is also why the back wall's own shadow, once
	## clipped, mostly just disappears rather than "moving" anywhere:
	## its natural sweep direction is into its own building, and once
	## that's excluded there's nowhere left outside for it to fall.
	var wall_shadow_tile_size: Vector2 = Vector2(tile_map.tile_set.tile_size)
	var building_polys: Array = _building_world_polys(wall_shadow_tile_size)
	## Per the "light source that cause secondary shadow should remove
	## primary shadows there their light falls" request: every currently
	## active light source (the player's own carried light, if effective,
	## plus every lit static lamp) gets paired with its own world-space
	## disc here (for clipping primary WALL shadow polygons just below)
	## and its own exact LOS-visible tile set merged into `lit_tiles`
	## (for hiding individual primary tree/person shadow SPRITES further
	## down) — a light source close enough to throw its OWN bright
	## secondary shadow across an area shouldn't leave a second, longer
	## ambient moon/sun shadow visibly poking through that same lit
	## ground. Recomputed fresh each call — event-driven (player
	## movement, waiting, etc. — see _update_hud()'s own comment), not
	## per-frame, same cadence every other primary-shadow calculation
	## here already runs at.
	var active_light_discs: Array = []
	var lit_tiles: Dictionary = {}
	if _light_source_effective() and is_instance_valid(player):
		var shadow_pc := _party_light_bearer()
		var shadow_radius_tiles: int = shadow_pc.get_active_light_radius_tiles() if shadow_pc != null else 0
		## Per the "2nd light should dispel shadows beyond 10 yards if it
		## reaches that far" follow-up: this suppresses PRIMARY sun/moon
		## shadows wherever the player's own light genuinely reaches, so
		## it uses the light's TRUE radius_tiles now rather than the
		## short SECONDARY_LIGHT_SHADOW_MAX_RANGE_TILES cap meant only to
		## limit how far individual secondary shadow-blob sprites are
		## drawn (see _apply_light_source_secondary_shadows()'s own
		## comment) — a strong Lantern should clear away an ambient
		## moon-shadow anywhere its own bright circle actually falls, not
		## just within the first 8 tiles of it.
		var suppress_range: int = shadow_radius_tiles
		if suppress_range > 0:
			var player_world_pos: Vector2 = tile_map.map_to_local(player.grid_pos)
			active_light_discs.append({"pos": player_world_pos, "radius": float(suppress_range) * wall_shadow_tile_size.x})
			for coords in _light_visible_tiles(player.grid_pos, suppress_range):
				lit_tiles[coords] = true
	if _lamp_night_factor > 0.0:
		for lamp_coords in static_lamp_coords:
			var lamp_world_pos: Vector2 = tile_map.map_to_local(lamp_coords)
			active_light_discs.append({"pos": lamp_world_pos, "radius": float(STATIC_LAMP_SHADOW_RANGE_TILES) * wall_shadow_tile_size.x})
			for coords in _light_visible_tiles(lamp_coords, STATIC_LAMP_SHADOW_RANGE_TILES):
				lit_tiles[coords] = true
	var wall_nodes: Array = []
	var wall_raw_pieces: Array = []
	## Fence shadow sprites now live one level deeper — as children of
	## _fence_shadow_group, itself a child of shadow_container (see the
	## comment above _fence_shadow_group's declaration) — so they need
	## to be folded into the same iteration explicitly. The group node
	## itself carries none of the metas this loop checks for, so it's
	## skipped outright rather than falling through to the tree/generic
	## branch at the bottom, which would otherwise error trying to read
	## a "tile_coords" meta key that was never set on it.
	var shadow_nodes: Array = shadow_container.get_children()
	if _fence_shadow_group != null:
		shadow_nodes.append_array(_fence_shadow_group.get_children())
	for shadow in shadow_nodes:
		if shadow == _fence_shadow_group:
			continue
		## Per the follow-up request ("secondary shadows for light
		## sources"): light_shadow_container is likewise a direct child
		## of shadow_container carrying none of the metas this loop
		## checks for — its own pooled sprites are repositioned every
		## frame by _apply_light_source_secondary_shadows() instead,
		## which runs independently of this (event-driven, sun/moon-only)
		## function. Skipped outright for the exact same reason
		## _fence_shadow_group is, right above.
		if shadow == light_shadow_container:
			continue
		## Per the "add 2 static lamps" request: _static_lamp_shadow_
		## container is likewise a direct child of shadow_container
		## (added in _rebuild_shadows(), right after light_shadow_
		## container) carrying none of the metas this loop checks for —
		## its own pooled sprites/polygons are rebuilt every frame by
		## _apply_static_lamp_secondary_shadows() instead. Skipped for
		## the exact same reason light_shadow_container is, right above.
		if shadow == _static_lamp_shadow_container:
			continue
		if shadow.has_meta("footprint_px"):
			var footprint: PackedVector2Array = shadow.get_meta("footprint_px")
			var piece: PackedVector2Array = _swept_clip_piece(footprint, wall_extension)
			wall_nodes.append(shadow)
			for surviving_piece in _clip_piece_against_buildings(piece, building_polys):
				for final_piece in _clip_piece_against_light_discs(surviving_piece, active_light_discs):
					wall_raw_pieces.append(final_piece)
			continue
		if shadow.has_meta("fence_rail_base_px"):
			## v0.2.259: the vertical-run rail column (and, since
			## v0.2.263/265, the NE/NW corner's own rail column too)
			## needs a constant TRANSLATION, not a shear — see
			## FENCE_VERTICAL_RAIL_COLUMN_START_PX's own long comment
			## for why a low, roughly-constant-height rail can't use
			## the same per-row/per-tile shear the post knots use.
			## Each piece carries its own `fence_rail_ratio` meta (set
			## per-piece at creation) so the two half-width lines land
			## at different, but each individually uniform, offsets.
			var rail_ratio: float = shadow.get_meta("fence_rail_ratio", FENCE_VERTICAL_RAIL_SHADOW_RATIO)
			var rail_translation: Vector2 = dir * fence_shadow_length * rail_ratio
			shadow.position = shadow.get_meta("fence_rail_base_px") + rail_translation
			continue
		if shadow.has_meta("fence_pivot_px"):
			## The fence's own base row is fixed at this exact world
			## point no matter what the sun is doing (see
			## FENCE_SHADOW_WORLD_ANCHOR_PX's comment) — setting the
			## whole node transform's origin here, in the same
			## assignment as the shear matrix itself, is what keeps that
			## true on every frame the sun moves. v0.2.251: the shear
			## basis is now computed per-shadow-piece, reading each
			## piece's own `shear_height_px` meta (defaulting to 16 for
			## whole-tile straight-run/corner pieces) instead of a single
			## divisor shared by every fence shadow.
			var piece_shear_height_px: float = shadow.get_meta("shear_height_px", 16.0)
			var piece_shear_per_height_px: Vector2 = (dir * fence_shadow_length) / piece_shear_height_px
			var piece_shear_basis_y: Vector2 = Vector2(-piece_shear_per_height_px.x, -piece_shear_per_height_px.y)
			## v0.2.252 fix, per direct request ("make the vertical fence
			## post shadows a bit thinner"): narrow only the vertical-run
			## post pieces (identified by `is_fence_post_piece` meta — set
			## v0.2.259, replacing the earlier, more fragile
			## `has_meta("shear_height_px")` check now that rail pieces
			## no longer set shear_height_px at all) by scaling the
			## transform's own x_axis around the node's local origin,
			## which sits at the post's own horizontal center — see
			## FENCE_VERTICAL_POST_SHADOW_WIDTH_SCALE's own comment.
			var piece_x_scale: float = FENCE_VERTICAL_POST_SHADOW_WIDTH_SCALE if shadow.get_meta("is_fence_post_piece", false) else 1.0
			shadow.transform = Transform2D(Vector2(piece_x_scale, 0.0), piece_shear_basis_y, shadow.get_meta("fence_pivot_px"))
			continue
		var coords: Vector2i = shadow.get_meta("tile_coords")
		## Per the same request: an individual tree/person primary shadow
		## sprite is suppressed outright wherever a nearby light source's
		## own exact LOS-visible area reaches it — precise (unlike the
		## wall-shadow disc clip above), since this is a cheap O(1)
		## Dictionary membership check per sprite rather than a polygon
		## boolean op.
		if lit_tiles.has(coords):
			shadow.visible = false
			continue
		shadow.visible = true
		var tile_center: Vector2 = tile_map.map_to_local(coords)
		var tile_size: Vector2 = Vector2(tile_map.tile_set.tile_size)
		## Anchored at the object's own real base — the tree trunk's
		## actual measured pixel — and never translated away from there
		## again. Only rotation and length change as the day passes,
		## exactly like a real shadow pivoting from a fixed point.
		var base_px: Vector2 = shadow.get_meta("base_px", TREE_TILE_BASE_PX)
		var base_delta: Vector2 = base_px - tile_size / 2.0
		shadow.position = tile_center + base_delta
		shadow.rotation = target_rotation
		shadow.scale = Vector2(0.7, 0.75 + length_factor * 0.35)
		## Keep the clip shader's own rotation uniform in sync, so the
		## "never render above the pivot" clip always matches the
		## shadow's actual current rotation.
		if shadow.material is ShaderMaterial:
			(shadow.material as ShaderMaterial).set_shader_parameter("shadow_rotation", target_rotation)

	## Union every wall run's raw shadow piece together (see the "double
	## shadow" comment above) into a set of mutually non-overlapping
	## polygons, then hand them back out to the existing per-run nodes
	## — reusing the same nodes rather than recreating them, since the
	## number of merged pieces is always <= the number of raw pieces
	## (union only ever combines, never splits) so there's always
	## enough nodes to go around; any leftover node just gets an empty
	## polygon (draws nothing) for this update.
	var merged_pieces: Array = []
	for piece in wall_raw_pieces:
		if piece.size() == 0:
			continue
		merged_pieces = _union_polygon_into(merged_pieces, piece)
	for i in range(wall_nodes.size()):
		if i < merged_pieces.size():
			wall_nodes[i].polygon = merged_pieces[i]
		else:
			wall_nodes[i].polygon = PackedVector2Array()

## Small helper for _update_shadow_angles()'s wall-shadow branch:
## translates `footprint` by `extension`, takes the convex hull of the
## original+translated points, and clips the original footprint back
## out — "sweep this shape toward the sun, keep only what it newly
## covers," which is what keeps a piece's shadow genuinely attached at
## that piece's own real position. Fences no longer use this — fence
## shadows were removed entirely (see the comment above
## SHADOW_TEXTURE_WALL). Returns an empty PackedVector2Array if there's
## nothing left after clipping.
func _swept_clip_piece(footprint: PackedVector2Array, extension: Vector2) -> PackedVector2Array:
	var extruded := PackedVector2Array()
	for p in footprint:
		extruded.append(p)
	for p in footprint:
		extruded.append(p + extension)
	var hull := Geometry2D.convex_hull(extruded)
	## Per the "move the outside shadow to the bottom of the back wall"
	## fix: a horizontal wall run's footprint is now deliberately a
	## zero-height line along its own bottom edge (see _rebuild_shadows(),
	## the "old bottom-edge-only trick" reintroduced) rather than a real
	## rectangle — there's no original area left to clip back out in
	## that case (clip_polygons() against a degenerate/zero-area
	## polygon isn't a case worth relying on), so the raw swept hull
	## itself IS the final piece.
	if _polygon_area(footprint) < 0.01:
		return hull
	var diff := Geometry2D.clip_polygons(hull, footprint)
	if diff.size() == 0:
		return PackedVector2Array()
	## clip_polygons can return more than one piece for an unusually-
	## shaped clip (not expected for this simple rectangle-vs-hull case,
	## but defensive nonetheless) — keep the largest by area so a stray
	## sliver never shows instead of the real shadow.
	var best: PackedVector2Array = diff[0]
	var best_area: float = _polygon_area(best)
	for i in range(1, diff.size()):
		var area: float = _polygon_area(diff[i])
		if area > best_area:
			best = diff[i]
			best_area = area
	return best

## Per the "shadows inside buildings" fix: one world-space rectangle
## (as a 4-point PackedVector2Array, same corner-extrusion convention
## _rebuild_shadows() already uses for each wall run's own footprint)
## per entry in `buildings`. Shared by both shadow systems that need to
## exclude building interiors — _update_shadow_angles() (sun/moon) and
## _apply_light_source_secondary_shadows() (carried light sources) —
## via _clip_piece_against_buildings(), since a torch carried inside a
## building can throw its own wall's shadow onto that same building's
## interior floor exactly the same way the sun/moon can.
func _building_world_polys(tile_size: Vector2) -> Array:
	var polys: Array = []
	for b in buildings:
		var top_left_center: Vector2 = tile_map.map_to_local(b.position)
		var bottom_right_center: Vector2 = tile_map.map_to_local(b.position + b.size - Vector2i(1, 1))
		var x_left: float = top_left_center.x - tile_size.x / 2.0
		var y_top: float = top_left_center.y - tile_size.y / 2.0
		var x_right: float = bottom_right_center.x + tile_size.x / 2.0
		var y_bottom: float = bottom_right_center.y + tile_size.y / 2.0
		polys.append(PackedVector2Array([
			Vector2(x_left, y_top),
			Vector2(x_right, y_top),
			Vector2(x_right, y_bottom),
			Vector2(x_left, y_bottom),
		]))
	return polys

## Per the "shadows inside buildings" fix: subtracts every building's
## own world-space rectangle (`building_polys`, precomputed once per
## _update_shadow_angles() call) from `piece` in turn, so a wall run's
## shadow can never visibly cover any building's interior floor or
## walls. Returns an Array of PackedVector2Array rather than a single
## piece because a clip can legitimately split one shadow into several
## disjoint remainders (e.g. a long wall run's shadow straddling the
## gap between two nearby buildings) — every surviving fragment is real
## shadow area, so all of them are kept rather than just the largest.
## Returns an empty Array if nothing survives (the common case for a
## wall whose entire swept shadow lands inside its own building, such
## as a north/back wall's shadow sweeping onto its own interior floor).
func _clip_piece_against_buildings(piece: PackedVector2Array, building_polys: Array) -> Array:
	if piece.size() == 0:
		return []
	var candidates: Array = [piece]
	for building_poly in building_polys:
		var next_candidates: Array = []
		for candidate in candidates:
			next_candidates.append_array(Geometry2D.clip_polygons(candidate, building_poly))
		candidates = next_candidates
		if candidates.is_empty():
			break
	return candidates

## Small helper for _update_shadow_angles()'s wall-shadow branch:
## shoelace-formula polygon area, used only to pick the largest piece
## if Geometry2D.clip_polygons() ever returns more than one.
func _polygon_area(poly: PackedVector2Array) -> float:
	var area := 0.0
	var n := poly.size()
	for i in range(n):
		var p1: Vector2 = poly[i]
		var p2: Vector2 = poly[(i + 1) % n]
		area += p1.x * p2.y - p2.x * p1.y
	return abs(area) * 0.5

## Per the "double shadow" bug fix: merges `poly` into `pieces` (an
## already mutually-non-overlapping set of polygons), returning the
## updated set. If `poly` overlaps or touches an existing piece,
## Geometry2D.merge_polygons() combines them into one (its own return
## size is 1 in that case); if they're disjoint, merge_polygons() hands
## both back out unmerged (return size > 1), so that existing piece
## stays separate and `poly` keeps looking for other overlaps. Because
## the loop keeps folding `poly` (well, `current`, which grows as it
## absorbs overlapping pieces) against every existing piece in a single
## pass, a piece that only overlaps `poly` indirectly through a second
## piece still gets picked up correctly within this one call — and
## since `pieces` is always non-overlapping on the way in (by the same
## invariant, maintained by every previous call), the result is too.
func _union_polygon_into(pieces: Array, poly: PackedVector2Array) -> Array:
	var current: PackedVector2Array = poly
	var remaining: Array = []
	for piece in pieces:
		var merged: Array = Geometry2D.merge_polygons(current, piece)
		if merged.size() == 1:
			current = merged[0]
		else:
			remaining.append(piece)
	remaining.append(current)
	return remaining

## Per the follow-up request: makes the ground tier dynamic instead of
## a single fixed layer — creates one real TileMapLayer per distinct
## elevation actually used by `map_def.elevation_overrides` (always at
## least 1, so a map with no elevation data at all behaves exactly as
## before). Frees any ground layers left over from a previous call
## (defensive — _build_map() currently only runs once per scene
## instance, but this keeps a future map switch from leaking nodes or
## leaving stale cells behind). Also (re)computes the z_index every
## other map-adjacent node needs to stay correctly ordered relative to
## however many ground layers this particular map turned out to need:
## shadows/tree-canopy sit just above the TOPMOST ground layer,
## buildings sit one higher than that, the roof layer one higher still,
## and above_buildings_z (used by the Player and every NPC/marker
## sprite) one higher again. Must run before anything in _build_map()
## that spawns a sprite or writes a ground cell.
func _rebuild_ground_layers(map_def: LocalMapDefinition) -> void:
	for layer in ground_layers:
		layer.queue_free()
	ground_layers.clear()

	var max_elevation := 0
	if map_def != null:
		for v in map_def.elevation_overrides.values():
			max_elevation = maxi(max_elevation, int(v))
	var layer_count: int = max_elevation + 1

	for i in range(layer_count):
		var layer := TileMapLayer.new()
		layer.name = "GroundLayer%d" % i
		layer.tile_set = MAP_TILESET
		layer.z_index = i
		add_child(layer)
		ground_layers.append(layer)
	tile_map = ground_layers[0]

	shadow_container.z_index = layer_count
	tree_canopy_overlay.z_index = layer_count
	building_layer.z_index = layer_count + 1
	roof_layer.z_index = layer_count + 2
	## One above roof_layer's own so its repainted ground/canopy tiles
	## actually draw on top of (and mask) the roof's own bleed — see
	## roof_overflow_mask_layer's own comment.
	roof_overflow_mask_layer.z_index = layer_count + 3
	above_buildings_z = layer_count + 4

func _build_map() -> void:
	_rebuild_ground_layers(current_map_def)
	## Per the request: once Gotheim's own levee has broken, most of
	## the village is genuinely flooded — applied here as a runtime
	## override on top of the map's own real static data, not a
	## permanent edit, since whether this has happened varies by
	## playthrough. The northern forest/lake/Cool House area (where
	## the Jabberslythe's own lair still needs to stay reachable) is
	## deliberately left untouched — the flood comes from the levee
	## and destroys the village downstream of it, not the woods
	## upstream. Border mountains and the map's own edges are never
	## overridden either.
	var gotheim_flooded := false
	if current_map_def != null and current_map_def.map_name == "Gotheim" and GameState.player_character != null:
		var q := GameState.player_character.find_quest("gotheim")
		gotheim_flooded = not q.is_empty() and bool(q.get("flood_triggered", false))

	## Defensive, matches the other fixed-layer .clear() calls below —
	## _build_map() currently only runs once per scene, but every NPC
	## sprite spawned during the loop just below registers itself here
	## fresh, so any stale entry from a previous build must not survive.
	npc_sprites_by_tile.clear()
	## Per the "add 2 static lamps" request: rebuilt fresh here, same
	## reasoning as npc_sprites_by_tile just above — _build_map() only
	## ever runs once per scene in practice, but a stale entry from a
	## previous build would otherwise silently survive.
	static_lamp_coords.clear()
	for y in range(map_rows.size()):
		var row: String = map_rows[y]
		for x in range(row.length()):
			var ch: String = row[x]
			var coords := Vector2i(x, y)
			if gotheim_flooded and y >= 23 and ch != "M" and ch != "@" and not (y == map_rows.size() - 1) and x > 0 and x < row.length() - 1:
				ch = "v"
			tile_chars[coords] = ch
			if ch == "@":
				player.warp_to(coords)
			elif ch == STATIC_LAMP_CHAR:
				static_lamp_coords.append(coords)
			elif ch == "N":
				_spawn_npc(coords, "A weary traveller nods to you. \"Safe roads to you, friend — stick to the path if you can. The grass this time of year draws vermin.\"")
			elif ch == "H":
				_spawn_npc(coords, "", true)
			elif ch == "S":
				_spawn_shopkeeper(coords)
			elif ch == "Y":
				_spawn_priest(coords)
	## Per the "new front wall tiles... floor stretches to the wall
	## edges" request: _resolve_wall_atlas() (used in the painting loop
	## just below) needs every building's bounding rect already known so
	## it can tell which edge of its own building a given wall cell sits
	## on — moved up from after the painting loop (where it used to run,
	## purely for the roof layer) to before it. _compute_buildings() only
	## ever reads tile_chars, which the first pass above just finished
	## fully populating, so this is safe to do this early.
	buildings = _compute_buildings()
	## Per the request: a real second pass over the now-fully-built
	## tile_chars grid, so grass variation and shore-edge detection can
	## safely look at ANY neighbor (including ones below/to the right,
	## which a single row-major pass wouldn't have reached yet).
	## Ground layers are always fresh (just created by
	## _rebuild_ground_layers() above) — only the fixed water/building/
	## overlay layers need clearing defensively before writing.
	water_layer.clear()
	building_layer.clear()
	shore_overlay_layer.clear()
	for coords in tile_chars:
		var ch: String = tile_chars[coords]
		var atlas: Vector2i = _resolve_tile_atlas(coords, ch)
		## Per the request: real map layers — ground (elevation-aware,
		## see below), water ("~", BEHIND every ground layer), and
		## buildings/walls (BUILDING_CHARS, IN FRONT of every ground
		## layer) — see WATER_CHARS/BUILDING_CHARS above. A ground tile
		## goes on the layer matching its own elevation
		## (LocalMapDefinition.elevation_overrides, default 0 — the
		## base level, same as before this feature existed). Clamped
		## defensively even though _rebuild_ground_layers() already
		## sized ground_layers to fit every elevation actually present.
		## Per the "blend better with neighboring tiles" request: the
		## fence ("I") art is mostly transparent (just posts + a rail),
		## and — unlike every other BUILDING_CHARS tile, which is fully
		## opaque and covers its cell completely — that transparency
		## used to show straight through to the raw viewport clear
		## color (a flat grey) instead of any real ground texture,
		## since a fence tile skipped the ground layer entirely (same
		## as a wall). Fixed by treating "I" as its own case: paint the
		## SAME deterministic grass variant an ordinary "." cell here
		## would get onto the ground layer first (so it blends exactly
		## like its neighbors, not a fixed/flat color), THEN draw the
		## fence's own (still transparent) art on the building layer on
		## top of it — every gap in the fence post/rail art now shows
		## real grass texture underneath instead of void.
		if ch in NPC_MARKER_CHARS:
			## See NPC_MARKER_CHARS's own comment: these letters are pure
			## spawn triggers, never real ground — resolve and paint the
			## actual terrain/floor that belongs here instead, and write
			## it back into tile_chars so every other system reading this
			## cell afterward (interior floor painting, shore/mud edge
			## blending on neighbouring cells, the overlay lookup just
			## below) sees the real terrain rather than a leftover spawn
			## letter.
			var natural_ch: String = _natural_ground_char_for_npc_marker(coords)
			tile_chars[coords] = natural_ch
			ch = natural_ch
			var npc_ground_atlas: Vector2i = _resolve_tile_atlas(coords, natural_ch)
			var npc_elevation := 0
			if current_map_def != null:
				npc_elevation = int(current_map_def.elevation_overrides.get(coords, 0))
			npc_elevation = clampi(npc_elevation, 0, ground_layers.size() - 1)
			ground_layers[npc_elevation].set_cell(coords, 0, npc_ground_atlas)
		elif ch == "I":
			var fence_elevation := 0
			if current_map_def != null:
				fence_elevation = int(current_map_def.elevation_overrides.get(coords, 0))
			fence_elevation = clampi(fence_elevation, 0, ground_layers.size() - 1)
			var fence_ground_atlas: Vector2i = _resolve_tile_atlas(coords, ".")
			ground_layers[fence_elevation].set_cell(coords, 0, fence_ground_atlas)
			## Per the "fences running north to south need to be turned"
			## request: `atlas` here is always the plain horizontal tile
			## (that's all TILE_ATLAS["I"] can ever return) — swap in the
			## orientation-aware pick instead, based on which of this
			## tile's own orthogonal neighbors are also fence.
			building_layer.set_cell(coords, 0, _resolve_fence_atlas(coords))
		elif ch == STATIC_LAMP_CHAR:
			## Per the "make the background of the new lamp transparent"
			## request: the lamp post art (like the fence's own art just
			## above) is mostly transparent — just the post/head/cap
			## silhouette, not a full opaque tile — so it hit the exact
			## same bug the fence did before its own "I" branch above was
			## added: painted straight onto the ground layer as though it
			## were a normal opaque ground tile, its transparent margin
			## showed the raw viewport clear colour (a flat grey box)
			## instead of the real grass/path underneath. Same fix: paint
			## the SAME deterministic ground variant an ordinary "." cell
			## here would get onto the ground layer first, THEN draw the
			## lamp's own (still transparent) art on the building layer on
			## top of it.
			var lamp_elevation := 0
			if current_map_def != null:
				lamp_elevation = int(current_map_def.elevation_overrides.get(coords, 0))
			lamp_elevation = clampi(lamp_elevation, 0, ground_layers.size() - 1)
			var lamp_ground_atlas: Vector2i = _resolve_tile_atlas(coords, ".")
			ground_layers[lamp_elevation].set_cell(coords, 0, lamp_ground_atlas)
			building_layer.set_cell(coords, 0, atlas)
		elif ch in BUILDING_CHARS:
			## Per the "new front wall tiles... floor stretches to the
			## wall edges" request: `atlas` here is always the old plain
			## wall texture (that's all TILE_ATLAS[ch] can ever return)
			## — swap in the orientation/material-aware, floor-bleeding
			## pick instead for the wall chars that have one.
			building_layer.set_cell(coords, 0, _resolve_wall_atlas(coords, ch))
		elif ch in WATER_CHARS:
			water_layer.set_cell(coords, 0, atlas)
		else:
			var elevation := 0
			if current_map_def != null:
				elevation = int(current_map_def.elevation_overrides.get(coords, 0))
			elevation = clampi(elevation, 0, ground_layers.size() - 1)
			ground_layers[elevation].set_cell(coords, 0, atlas)
		var overlay_atlas: Vector2i = _resolve_shore_overlay_atlas(coords, ch)
		if overlay_atlas != Vector2i(-1, -1):
			shore_overlay_layer.set_cell(coords, 0, overlay_atlas)
	## Per the door/roof request: cover every building's footprint (its
	## bounding rect was already computed above, before the painting
	## loop — see the "moved up" comment there) in roof tiles.
	## player_inside_building resets to -1 (every roof shown) since the
	## old index no longer means anything against a freshly rebuilt
	## `buildings` array; the real starting tile isn't settled until
	## _restore_return_position() runs later in _ready(), which is what
	## actually calls _update_roof_visibility() to correct this if the
	## player's real spawn tile turns out to be indoors.
	building_is_chapel.clear()
	building_roof_variant.clear()
	for i in range(buildings.size()):
		var rect: Rect2i = buildings[i]
		building_is_chapel.append(_building_contains_char(rect, "h"))
		building_roof_variant.append(_roof_variant_for(i))
	player_inside_building = -1
	roof_layer.clear()
	for i in range(buildings.size()):
		var rect: Rect2i = buildings[i]
		var variant: int = building_roof_variant[i]
		for y in range(rect.position.y, rect.position.y + _roof_row_count(rect)):
			var row_atlas: Vector2i = _roof_atlas_for_row(rect, y, variant)
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				roof_layer.set_cell(Vector2i(x, y), 0, row_atlas)
		## Per the request: give the church a small steeple silhouette —
		## the one cell of budget this rectangular-roof system has for
		## "this building is special" — dead center of its own ridge row,
		## overwriting the plain ridge cap painted there just above.
		if building_is_chapel[i]:
			var steeple_x := rect.position.x + rect.size.x / 2
			roof_layer.set_cell(Vector2i(steeple_x, rect.position.y), 0, STEEPLE_ROOF_ATLAS)
	## Per the "still bleeding through at the edges" thread's real fix
	## (see roof_overflow_mask_layer's own comment for the full "roof art
	## taller than one tile cell" story): repaint the two rows of ground
	## immediately north of every building's own ridge row — using
	## whichever plain ground atlas already belongs at that real map
	## coordinate, exactly the way a lamp/fence tile's own background is
	## repainted elsewhere in this function — on a layer that sits one
	## z_index above roof_layer, so it draws right over the ridge tile's
	## own overflow instead of trying to fight the lighting system about
	## it. Two rows (not one) for the same "measured a bit more than one
	## tile tall in practice" margin the earlier lighting-based attempts
	## used, just applied to the ACTUAL bleeding pixels instead.
	roof_overflow_mask_layer.clear()
	for i in range(buildings.size()):
		var rect: Rect2i = buildings[i]
		for y in range(rect.position.y - 2, rect.position.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				var mask_coords := Vector2i(x, y)
				var mask_ch: String = tile_chars.get(mask_coords, ".")
				roof_overflow_mask_layer.set_cell(mask_coords, 0, _resolve_tile_atlas(mask_coords, mask_ch))
	## Per the request ("all house interiors tiles should have matching
	## crafted floor ie wood/stone"): every building's own interior gets
	## a real crafted floor instead of plain grass — see
	## _paint_building_interiors().
	_paint_building_interiors()
	## Per the request: "inside houses it should always be shady" — one
	## dim overlay per building, covering the exact same roofed-rows
	## footprint as the roof itself (walls included, so the whole
	## indoor "shell" reads dim, not just the floor), hidden by default
	## and toggled together with the roof in _set_building_roof_visible().
	## Drawn just below the player/NPC layer so nobody standing inside
	## gets dimmed themselves, but above building_layer so the walls do.
	for old_shade in indoor_shade_polygons:
		if is_instance_valid(old_shade):
			old_shade.queue_free()
	indoor_shade_polygons.clear()
	for rect in buildings:
		var roofed_rows: int = _roof_row_count(rect)
		var top_left: Vector2 = tile_map.map_to_local(rect.position) - Vector2(tile_map.tile_set.tile_size) / 2.0
		var bottom_right: Vector2 = tile_map.map_to_local(Vector2i(rect.position.x + rect.size.x - 1, rect.position.y + roofed_rows - 1)) + Vector2(tile_map.tile_set.tile_size) / 2.0
		var shade := Polygon2D.new()
		shade.color = WALL_SHADOW_COLOR
		shade.polygon = PackedVector2Array([
			Vector2(top_left.x, top_left.y),
			Vector2(bottom_right.x, top_left.y),
			Vector2(bottom_right.x, bottom_right.y),
			Vector2(top_left.x, bottom_right.y),
		])
		shade.z_index = above_buildings_z - 1
		shade.visible = false
		shade.name = "IndoorShade_%d_%d" % [rect.position.x, rect.position.y]
		add_child(shade)
		indoor_shade_polygons.append(shade)
	## Per the request: any NPC already registered in npc_sprites_by_tile
	## (shopkeeper/priest/traveller/trainer — spawned during the loop
	## above, before buildings/roof existed to check against) needs its
	## real starting visibility set now that both exist. player_inside_
	## building is still -1 here (every roof freshly shown), so this
	## simply hides anyone standing under a just-painted roof — correct
	## as a starting state; _update_roof_visibility()'s own call further
	## down in _ready() corrects it again if the player's real spawn
	## tile turns out to be indoors.
	for tile in npc_sprites_by_tile:
		npc_sprites_by_tile[tile].visible = _roofed_building_index_at(tile) == -1
	_rebuild_shadows()
	## Per the request: builds the real lookup used by try_interact()
	## below, and spawns a real, visible sprite at each marker tile —
	## a distinct one per named NPC where dedicated art exists (see
	## QUEST_NPC_TEXTURES), falling back to the generic traveller
	## sprite for any quest NPC that doesn't have its own art yet.
	quest_npc_marker_tiles.clear()
	if current_map_def != null:
		for marker in current_map_def.quest_npc_markers:
			## Per the request: the timeline's own events change who
			## remains visible and accessible as time passes — a
			## removed NPC (dead, fled, or lost to a flood) gets no
			## marker and no sprite at all, not just a "can't talk to
			## them" interaction block.
			if GameState.player_character.is_quest_npc_removed(marker.quest_id, marker.npc_id):
				continue
			quest_npc_marker_tiles[marker.tile] = marker
			var sprite := Sprite2D.new()
			var texture_key: String = "%s_%s" % [marker.quest_id, marker.npc_id]
			sprite.texture = QUEST_NPC_TEXTURES.get(texture_key, NPC_TRAVELLER_TEXTURE)
			sprite.centered = false
			sprite.scale = Vector2(NPC_SPRITE_SCALE, NPC_SPRITE_SCALE)
			sprite.position = Vector2(marker.tile.x * TILE_SIZE, marker.tile.y * TILE_SIZE)
			## Per the request: buildings render on their own layer in
			## front of the ground — NPCs need an explicit z_index above
			## that (and above however many ground/shadow tiers this
			## particular map needed) so one standing on/near a building
			## tile (e.g. inside a shop) doesn't visually disappear
			## behind the wall. See above_buildings_z / _rebuild_ground_layers().
			sprite.z_index = above_buildings_z
			add_child(sprite)
			sprite.add_child(_make_person_shadow())
			## Per the request: a quest NPC standing inside a building
			## (e.g. a shop) should be hidden from outside exactly like
			## any other indoor NPC — register + apply the same starting
			## visibility check as the shopkeeper/priest/traveller pass
			## above (player_inside_building is still -1 at this point in
			## _build_map(), same reasoning).
			npc_sprites_by_tile[marker.tile] = sprite
			sprite.visible = _roofed_building_index_at(marker.tile) == -1
	quest_monster_marker_tiles.clear()
	if current_map_def != null:
		for mmarker in current_map_def.quest_monster_markers:
			quest_monster_marker_tiles[mmarker.tile] = mmarker
	## Per the request: the Party Companion Maker NPC — spawned
	## directly from the map's own data, not tied to any quest, so it
	## persists across the whole game rather than being a one-off.
	if current_map_def != null and current_map_def.companion_maker_tile != Vector2i(-1, -1):
		var companion_sprite := Sprite2D.new()
		companion_sprite.texture = NPC_TRAINER_TEXTURE
		companion_sprite.centered = false
		companion_sprite.scale = Vector2(NPC_SPRITE_SCALE, NPC_SPRITE_SCALE)
		companion_sprite.position = Vector2(current_map_def.companion_maker_tile.x * TILE_SIZE, current_map_def.companion_maker_tile.y * TILE_SIZE)
		companion_sprite.z_index = above_buildings_z
		add_child(companion_sprite)
		companion_sprite.add_child(_make_person_shadow())
		npc_sprites_by_tile[current_map_def.companion_maker_tile] = companion_sprite
		companion_sprite.visible = _roofed_building_index_at(current_map_def.companion_maker_tile) == -1
	## Per the request: fixes a real bug — arriving via a deliberate
	## map spawn (leaving a local map back to the World Map, or
	## arriving at a local map via travel) was correctly warped here,
	## then immediately overwritten by _restore_return_position()'s
	## own fallback to the character's own camp_position — their last
	## position on the PREVIOUS map, reinterpreted as coordinates on
	## this new one, landing them somewhere unrelated rather than
	## next to the place they'd actually just left. Tracked here so
	## _restore_return_position() knows to skip its own fallback
	## entirely when this already happened.
	_used_deliberate_spawn_tile = false
	if GameState.pending_map_spawn_tile != Vector2i(-1, -1):
		player.warp_to(GameState.pending_map_spawn_tile)
		GameState.pending_map_spawn_tile = Vector2i(-1, -1)
		_used_deliberate_spawn_tile = true
	elif current_map_def != null and current_map_def.is_world_map and GameState.world_map_player_position != Vector2i(-1, -1):
		## Per the request: a genuine save/load on the World Map now
		## restores the player's own exact saved position there,
		## rather than always the map's default spawn tile — this is
		## specifically what makes Continue/Load land back where the
		## player actually was, not just correctly re-open the World
		## Map itself (which already worked).
		##
		## Real bug fix — the actual cause of the reported "I keep
		## being reset to location 25,45 on the overworld map, and
		## travel is interrupted after a wilderness encounter": this
		## branch used to NOT set _used_deliberate_spawn_tile, so the
		## correct warp above was immediately overwritten a few lines
		## later in _ready() by _restore_return_position()'s own
		## camp_position fallback — which fires on basically EVERY
		## ordinary World Map load, since GameState.return_position is
		## -1,-1 the vast majority of the time (it's only ever set
		## momentarily, around a specific field/wilderness encounter).
		## camp_position is wherever the player last pressed Camp on
		## ANY map, local or World — for most players that's somewhere
		## in Gotheim (the starting village), e.g. its own south-gate
		## exit tile at local Vector2i(25, 45), which coincidentally is
		## also a walkable World Map tile, so is_walkable(pos) let it
		## through silently. The result: the player's real, correct
		## World Map position (restored just above) was clobbered by a
		## Gotheim-local coordinate reinterpreted as a World Map one,
		## every single time — matching the "keeps resetting to 25,45"
		## report exactly, and also explaining "travel interrupted,
		## back where I started": any Overworld reload mid-journey
		## (e.g. after a Wilderness Event's own scene round-trip, if
		## return_position wasn't the one thing keeping this branch
		## from being clobbered) landed back at that same stale spot
		## instead of continuing forward. Marked deliberate here, same
		## as the pending_map_spawn_tile branch above, so
		## _restore_return_position() skips its own fallback entirely
		## — this restored position is already correct and shouldn't
		## be second-guessed.
		player.warp_to(GameState.world_map_player_position)
		_used_deliberate_spawn_tile = true
	elif current_map_def != null and current_map_def.default_spawn_tile != Vector2i(-1, -1):
		player.warp_to(current_map_def.default_spawn_tile)
	## Per the request: keeps world_map_player_position genuinely in
	## sync with wherever the player actually ends up on the World
	## Map, regardless of which branch above spawned them there — the
	## existing travel code already updates this correctly once a
	## journey completes, but the very first arrival (leaving a local
	## map for the first time, or the map's own default '@' spawn on a
	## brand new character) never did, which would have made an
	## immediate save right after arriving capture a stale or unset
	## position instead of where the player genuinely just landed.
	if current_map_def != null and current_map_def.is_world_map:
		GameState.world_map_player_position = player.grid_pos
	## Per the request: real city/town names shown on the World Map,
	## next to each location's own marker — only meaningful there, so
	## skipped entirely for an ordinary local map.
	if current_map_def != null and current_map_def.is_world_map:
		_spawn_location_labels()
		_spawn_province_labels()

## Per the door/roof request: groups every WALL_MATERIAL_CHARS tile
## into buildings via simple 4-directional flood fill, then returns
## each building's own bounding Rect2i (tile coordinates, covering the
## full footprint — walls AND whatever interior floor/furniture sits
## inside them). A single flood-fill component correctly covers an
## entire building even though its front wall has a door-sized gap in
## it (see WALL_MATERIAL_CHARS's own comment) — the gap only breaks
## the front row's own connectivity, not the building's, since the
## other three walls (or, for a fully hollow perimeter, just enough of
## the loop) still connect every wall tile into one component.
## Deliberately excludes any component whose bounding box is only 1
## tile wide or tall (a lone fence post, a standalone wall segment with
## no real interior) — a real building always encloses at least a
## little floor space, so a degenerate sliver never gets a roof.
func _compute_buildings() -> Array[Rect2i]:
	var visited: Dictionary = {}
	var rects: Array[Rect2i] = []
	var directions := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for start_coords in tile_chars:
		if visited.has(start_coords):
			continue
		if not (tile_chars[start_coords] in WALL_MATERIAL_CHARS):
			continue
		visited[start_coords] = true
		var stack: Array = [start_coords]
		var min_x: int = start_coords.x
		var max_x: int = start_coords.x
		var min_y: int = start_coords.y
		var max_y: int = start_coords.y
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			min_x = mini(min_x, cur.x)
			max_x = maxi(max_x, cur.x)
			min_y = mini(min_y, cur.y)
			max_y = maxi(max_y, cur.y)
			for dir in directions:
				var neighbor: Vector2i = cur + dir
				if visited.has(neighbor):
					continue
				if not (tile_chars.get(neighbor, "") in WALL_MATERIAL_CHARS):
					continue
				visited[neighbor] = true
				stack.append(neighbor)
		var width: int = max_x - min_x + 1
		var height: int = max_y - min_y + 1
		if width >= 2 and height >= 2:
			rects.append(Rect2i(Vector2i(min_x, min_y), Vector2i(width, height)))
	return rects

## Per the Gotheim rework request: does any tile within this building's
## own footprint use the given map character? Used to tag a building as
## a chapel (contains an "h" chapel-front tile) without needing a
## separate per-building "kind" field threaded through _compute_buildings()
## — the character already placed in map_rows for the door-flanking
## facade IS the tag.
## Per the wall-walkability request: which building's bounding rect (if
## any) a tile falls inside — used by is_walkable() to decide "is this
## wall tile being approached from inside its own building." Same
## linear-scan-over-`buildings` approach _update_roof_visibility()
## already uses; building counts per map are small (a handful), so this
## is cheap enough to call per movement step.
func _building_index_at(coords: Vector2i) -> int:
	for i in range(buildings.size()):
		if buildings[i].has_point(coords):
			return i
	return -1

## Per the "new front wall tiles... floor stretches to the wall edges"
## request: picks the correct floor-bleed wall tile for a
## WALL_RESOLVED_WOOD_CHARS/WALL_RESOLVED_STONE_CHARS cell, based purely
## on where it sits within its own building's bounding rect (from
## _compute_buildings()) — same "derive it from the rect, don't hand-
## annotate the map" approach _roof_atlas_for_row() already uses.
## A building's rect always has its back wall as the very first row and
## its front/door wall as the very last row (see _compute_buildings()'s
## own doc comment on the map's row layout), with side walls only ever
## occupying the rows strictly between them — so a cell can never match
## more than one of the four checks below.
## Falls back to the plain old TILE_ATLAS entry for anything that isn't
## one of the two resolved material families, or that IS one of those
## chars but isn't actually part of a real building footprint (no
## _building_index_at() match — e.g. a standalone "#" wall segment), or
## that's an "O" interior partition sitting somewhere other than the
## building's own outer edge (an inner room divider, not an outer wall)
## — all of which keep the original plain wall texture, unchanged.
func _resolve_wall_atlas(coords: Vector2i, ch: String) -> Vector2i:
	var is_wood: bool = ch in WALL_RESOLVED_WOOD_CHARS
	var is_stone: bool = ch in WALL_RESOLVED_STONE_CHARS
	if not (is_wood or is_stone):
		return TILE_ATLAS.get(ch, Vector2i.ZERO)
	var building_idx: int = _building_index_at(coords)
	if building_idx == -1:
		return TILE_ATLAS.get(ch, Vector2i.ZERO)
	var rect: Rect2i = buildings[building_idx]
	var north_row: int = rect.position.y
	var front_row: int = rect.position.y + rect.size.y - 1
	var west_col: int = rect.position.x
	var east_col: int = rect.position.x + rect.size.x - 1
	if coords.y == north_row:
		return WALL_WOOD_NORTH_ATLAS if is_wood else WALL_STONE_NORTH_ATLAS
	if coords.y == front_row:
		return WALL_WOOD_FRONT_ATLAS if is_wood else WALL_STONE_FRONT_ATLAS
	if coords.x == west_col:
		return WALL_WOOD_WEST_ATLAS if is_wood else WALL_STONE_WEST_ATLAS
	if coords.x == east_col:
		return WALL_WOOD_EAST_ATLAS if is_wood else WALL_STONE_EAST_ATLAS
	return TILE_ATLAS.get(ch, Vector2i.ZERO)

func _building_contains_char(rect: Rect2i, target_char: String) -> bool:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if tile_chars.get(Vector2i(x, y), "") == target_char:
				return true
	return false

## See NPC_MARKER_CHARS's own comment. Indoors (the marker's tile falls
## within a real building footprint), returns that building's own real
## floor material — "F" (paved stone) if the building contains a stone
## "K" wall tile, otherwise "n" (wood-plank floor) — the exact same
## rule _paint_building_interiors() already applies to every ordinary
## interior cell, so an NPC marker's tile ends up floored identically
## to the room around it. Outdoors, looks at the tile's four orthogonal
## neighbours and returns whichever real, paintable ground character is
## most common among them — ignoring other markers (which don't
## describe real ground either), building/wall tiles, water, the fence
## ("I"), and the static lamp, none of which a marker tile could
## sensibly inherit as "its own ground" — falling back to plain grass
## "." only if no neighbour qualifies (e.g. a marker boxed in on every
## side by exactly those excluded tile types).
func _natural_ground_char_for_npc_marker(coords: Vector2i) -> String:
	var building_idx: int = _building_index_at(coords)
	if building_idx != -1:
		var rect: Rect2i = buildings[building_idx]
		var stone: bool = _building_contains_char(rect, "K")
		return "F" if stone else "n"
	var neighbor_offsets := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	var counts: Dictionary = {}
	for offset in neighbor_offsets:
		var n_ch: String = tile_chars.get(coords + offset, "")
		if n_ch == "" or n_ch in NPC_MARKER_CHARS or n_ch in BUILDING_CHARS or n_ch in WATER_CHARS or n_ch == "I" or n_ch == STATIC_LAMP_CHAR:
			continue
		counts[n_ch] = counts.get(n_ch, 0) + 1
	var best_ch := "."
	var best_count := 0
	for ch in counts:
		if counts[ch] > best_count:
			best_count = counts[ch]
			best_ch = ch
	return best_ch

## Per the request ("all house interiors tiles should have matching
## crafted floor ie wood/stone"): every building's true interior cells
## (excluding its own wall ring on 3 sides AND its front/door row —
## see _roof_row_count()'s own "the front row is never roofed" logic,
## the same boundary applies here: that row is a wall/door row, not
## interior floor) get a real crafted floor instead of plain grass.
## Material follows the building's own walls: any building containing
## a stone "K" wall tile (the church, the smithy) gets the existing
## "F" paved-stone floor; everything else (every "B" timber-framed
## building) gets the new "n" wood-plank floor. Only ever overwrites a
## cell that's still plain "." ground — a hand-placed furniture tile
## (table/chair/bed/cupboard) or a deliberately different floor a
## future map author places on purpose is left alone, same
## "don't clobber anything meaningful" rule the cobblestone path BFS
## follows. Called once per _build_map(), right after `buildings` and
## its roof are painted, so this naturally applies to every map with
## real buildings (Giessingen, Gotheim, any future one) without needing
## per-map special-casing.
func _paint_building_interiors() -> void:
	for rect in buildings:
		if rect.size.x < 3 or rect.size.y < 3:
			continue   ## no real interior cell — just walls/door, nothing to floor
		var stone: bool = _building_contains_char(rect, "K")
		var floor_char: String = "F" if stone else "n"
		var floor_atlas: Vector2i = TILE_ATLAS[floor_char]
		for y in range(rect.position.y + 1, rect.position.y + rect.size.y - 1):
			for x in range(rect.position.x + 1, rect.position.x + rect.size.x - 1):
				var coords := Vector2i(x, y)
				if tile_chars.get(coords, "") != ".":
					continue
				tile_chars[coords] = floor_char
				var elevation := 0
				if current_map_def != null:
					elevation = int(current_map_def.elevation_overrides.get(coords, 0))
				elevation = clampi(elevation, 0, ground_layers.size() - 1)
				ground_layers[elevation].set_cell(coords, 0, floor_atlas)

## Per the door/roof request: "when entering a house via a door... the
## roof should go see through" — called from _on_player_moved() every
## time the player's tile changes, plus once from _ready() right after
## _restore_return_position() settles the real starting tile. Only
## touches the ONE building being entered and/or the ONE being left
## (tracked via player_inside_building), never a full roof rebuild.
func _update_roof_visibility(tile: Vector2i) -> void:
	var new_index := -1
	for i in range(buildings.size()):
		if buildings[i].has_point(tile):
			new_index = i
			break
	if new_index == player_inside_building:
		return
	if player_inside_building != -1:
		_set_building_roof_visible(player_inside_building, true)
	if new_index != -1:
		_set_building_roof_visible(new_index, false)
	player_inside_building = new_index

## Small helper for _update_roof_visibility(): shows or hides every
## roof cell belonging to one specific building. "Hidden" means the
## cell is genuinely erased from roof_layer (source_id -1), not just
## made transparent — simplest way to guarantee nothing about the roof
## can ever visually block the floor/furniture/player underneath it
## while the player's standing inside.
## Per the request ("hide NPCs that are inside houses from the
## outside"): any tracked NPC sprite (see npc_sprites_by_tile) standing
## on one of this building's own roofed cells is toggled in the exact
## same pass — visible only while the roof over their own tile is
## hidden (i.e. only while the player is the one standing inside this
## building with them). Before this, every NPC used a flat
## above_buildings_z so an indoor NPC rendered on top of its own roof
## from outside — this is what actually fixes that.
func _set_building_roof_visible(building_index: int, roof_visible: bool) -> void:
	var rect: Rect2i = buildings[building_index]
	var variant: int = building_roof_variant[building_index] if building_index < building_roof_variant.size() else 0
	for y in range(rect.position.y, rect.position.y + _roof_row_count(rect)):
		var row_atlas: Vector2i = _roof_atlas_for_row(rect, y, variant)
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var coords := Vector2i(x, y)
			if roof_visible:
				roof_layer.set_cell(coords, 0, row_atlas)
			else:
				roof_layer.set_cell(coords, -1)
			if npc_sprites_by_tile.has(coords):
				npc_sprites_by_tile[coords].visible = not roof_visible
	## Per the Gotheim rework request: re-apply the steeple override
	## every time the roof comes back — the loop above just repainted
	## this building's whole ridge row with the plain ridge atlas, which
	## would otherwise silently erase the steeple after the player's
	## first visit indoors.
	if roof_visible and building_index < building_is_chapel.size() and building_is_chapel[building_index]:
		var steeple_x := rect.position.x + rect.size.x / 2
		roof_layer.set_cell(Vector2i(steeple_x, rect.position.y), 0, STEEPLE_ROOF_ATLAS)
	## Per the request ("inside houses it should always be shady"): the
	## dim overlay toggles in lockstep with the roof too — visible
	## exactly while the roof is hidden, same as the NPCs above.
	if building_index < indoor_shade_polygons.size():
		indoor_shade_polygons[building_index].visible = not roof_visible

## Per the request: which building (if any) has a roof cell over this
## exact tile right now — i.e. the tile is within a building's own
## ROOFED rows (see _roof_row_count(); the building's front wall/door
## row is never roofed, so an NPC standing there — none currently do —
## would correctly report -1 and always stay visible, same as being
## outside entirely). Returns -1 if no building roofs this tile. Used
## both to set an NPC sprite's correct starting visibility right after
## it spawns, and by _set_building_roof_visible() implicitly via
## npc_sprites_by_tile's own tile keys.
func _roofed_building_index_at(tile: Vector2i) -> int:
	for i in range(buildings.size()):
		var rect: Rect2i = buildings[i]
		if tile.x >= rect.position.x and tile.x < rect.position.x + rect.size.x \
				and tile.y >= rect.position.y and tile.y < rect.position.y + _roof_row_count(rect):
			return i
	return -1

## Per the second follow-up request: "the player should see the south
## facing wall" — the roof was covering a building's OWN front wall
## row (and its door, if it has one), which is wrong for this game's
## flat, single-tile-per-cell rendering: there's no fake-height trick
## making the roof read as sitting "above and behind" a visible wall
## below it, so a roof tile drawn on that row just replaced the wall/
## door art outright, hiding it (and the door specifically) until the
## player had already found their own way in. Every building on every
## current map has its actual front wall/door on its own southernmost
## row (the row nearest the camera/the player's approach — see
## _compute_buildings() and where "d" doors get placed), so the roof
## now deliberately stops one row short of the bottom: it covers rows
## [top, bottom - 1] only. The true bottom row is never given a
## roof_layer cell at all — its wall/door tiles on building_layer stay
## fully visible, always, exactly like they did before roofs existed.
func _roof_row_count(rect: Rect2i) -> int:
	return rect.size.y - 1

## Per the follow-up request: picks which of the three roof tiles a
## given (already-roofed — see _roof_row_count()) row of a building's
## own footprint should use — the ridge cap on its northernmost row
## (min y — the smallest y is the row drawn FARTHEST from the camera
## in this top-down view, i.e. the building's own "back"), the eave/
## overhang on the LAST roofed row (nearest the camera, directly above
## the building's own visible front wall), and the plain shingled body
## on anything between. A building whose roofed range is only 1 row
## (a building exactly 2 rows tall, `_compute_buildings()`'s minimum —
## one wall row, one front-wall row, no separate roofed interior) gets
## ridge only, which still reads fine with no eave row to spare.
## `variant` selects which of the 3 (ridge, body, eave) palette sets to
## use — see ROOF_RIDGE_VARIANTS/ROOF_BODY_VARIANTS/ROOF_EAVE_VARIANTS
## and _roof_variant_for(). Defaults to 0 (the original terracotta) so
## every OTHER call site that doesn't care about variation (there are
## none left, but keeps this safe to call generically) still works.
func _roof_atlas_for_row(rect: Rect2i, y: int, variant: int = 0) -> Vector2i:
	if y == rect.position.y:
		return ROOF_RIDGE_VARIANTS[variant]
	if y == rect.position.y + _roof_row_count(rect) - 1:
		return ROOF_EAVE_VARIANTS[variant]
	return ROOF_BODY_VARIANTS[variant]

## Per the request ("all builds should have slight variations"): a
## fixed, deterministic 0/1/2 pick per building index — not true
## randomness, so re-loading the same map always looks identical to
## itself. Plain modulo is enough: buildings are computed in a stable
## order (see _compute_buildings()'s own row-major tile_chars scan),
## so adjacent buildings in that order naturally land on different
## variants most of the time without needing anything fancier.
func _roof_variant_for(building_index: int) -> int:
	return building_index % ROOF_BODY_VARIANTS.size()

## Per the request: picks the actual atlas tile for one map cell,
## given its own character and (for grass) its neighbors — grass
## alternates between 3 real variants so open ground doesn't read as
## one flat repeating texture, and any grass cell touching water gets
## a real rounded shore edge instead of a hard square boundary.
## Deliberately called from a second pass, after tile_chars is fully
## built, so it can safely check ANY neighbor.
## Per the request: a full rework, covering every possible
## orthogonal/diagonal neighbor configuration a grass cell can have
## against one other terrain (water or mud), not just the 0/1/2-
## adjacent cases the previous system handled. Returns Vector2i(-1,-1)
## if `target_char` doesn't border this cell at all (caller moves on
## to check something else, or falls back to plain grass).
## Deterministic per-position pick among a straight shore edge's
## variants — same integer-mixing hash as the plain grass variant
## picker further down (so the same map cell always renders the same
## way), but salted per direction so the four edges don't end up
## picking correlated variants for the same tile.
func _shore_variant_index(coords: Vector2i, count: int, salt: int) -> int:
	var h: int = (coords.x + salt) * 374761393 + (coords.y + salt) * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return int(abs(h)) % count

## Picks the right hand-painted bridge piece for a given "X" cell.
## Orientation comes from which of this cell's own orthogonal
## neighbors are also bridge ("X"): bridge neighbors to the east/west
## means a horizontal span, to the north/south means vertical. Within
## that orientation, a cell is the over-water MIDDLE piece if its
## perpendicular neighbors are actual river ("~") — i.e. it's really
## spanning the water — and an END/landing piece otherwise (it's
## sitting on the bank, where the deck meets dry land). A single
## isolated "X" (no bridge neighbors either way — shouldn't happen on
## a real map, but keeps this total) just falls back to the middle
## deck piece.
func _resolve_bridge_atlas(coords: Vector2i) -> Vector2i:
	var w_bridge: bool = tile_chars.get(coords + Vector2i(-1, 0), "") == "X"
	var e_bridge: bool = tile_chars.get(coords + Vector2i(1, 0), "") == "X"
	var n_bridge: bool = tile_chars.get(coords + Vector2i(0, -1), "") == "X"
	var s_bridge: bool = tile_chars.get(coords + Vector2i(0, 1), "") == "X"
	var horizontal: bool = w_bridge or e_bridge
	var vertical: bool = n_bridge or s_bridge
	if horizontal and not vertical:
		var n_water: bool = tile_chars.get(coords + Vector2i(0, -1), "") == "~"
		var s_water: bool = tile_chars.get(coords + Vector2i(0, 1), "") == "~"
		if n_water or s_water:
			return BRIDGE_H_MIDDLE_ATLAS
		if not w_bridge:
			return BRIDGE_H_WEST_END_ATLAS
		if not e_bridge:
			return BRIDGE_H_EAST_END_ATLAS
		return BRIDGE_H_MIDDLE_ATLAS
	if vertical and not horizontal:
		var e_water: bool = tile_chars.get(coords + Vector2i(1, 0), "") == "~"
		var w_water: bool = tile_chars.get(coords + Vector2i(-1, 0), "") == "~"
		if e_water or w_water:
			return BRIDGE_V_MIDDLE_ATLAS
		if not n_bridge:
			return BRIDGE_V_NORTH_END_ATLAS
		if not s_bridge:
			return BRIDGE_V_SOUTH_END_ATLAS
		return BRIDGE_V_MIDDLE_ATLAS
	return BRIDGE_H_MIDDLE_ATLAS

func _resolve_shore_atlas(coords: Vector2i, target_char: String, atlas: Dictionary) -> Vector2i:
	var n: bool = tile_chars.get(coords + Vector2i(0, -1), "") == target_char
	var s: bool = tile_chars.get(coords + Vector2i(0, 1), "") == target_char
	var e: bool = tile_chars.get(coords + Vector2i(1, 0), "") == target_char
	var w: bool = tile_chars.get(coords + Vector2i(-1, 0), "") == target_char
	var orth_count: int = int(n) + int(s) + int(e) + int(w)
	if orth_count == 4:
		return atlas["ISOLATED"]
	if orth_count == 3:
		if not n:
			return atlas["THREE_N"]   ## the ONE non-target side is north -> grass remains on the north
		if not s:
			return atlas["THREE_S"]
		if not e:
			return atlas["THREE_E"]
		return atlas["THREE_W"]
	if orth_count == 2:
		if n and s:
			return atlas["ISTHMUS_NS"]
		if e and w:
			return atlas["ISTHMUS_EW"]
		if n and e:
			return atlas["NE"]
		if n and w:
			return atlas["NW"]
		if s and e:
			return atlas["SE"]
		return atlas["SW"]   ## s and w
	if orth_count == 1:
		if n:
			return atlas["N"]
		if s:
			return atlas["S"]
		if e:
			return atlas["E"]
		return atlas["W"]
	## No orthogonal contact — check for a single diagonal-only touch
	## (e.g. a "stairstep" coastline corner). Uses dedicated, smaller
	## notch pieces (DIAG_*), not the full corner pieces above — this
	## situation is genuinely subtler and looked like an oversized
	## "overspill" bulge when it borrowed the bigger art.
	if tile_chars.get(coords + Vector2i(1, -1), "") == target_char:
		return atlas["DIAG_NE"]
	if tile_chars.get(coords + Vector2i(-1, -1), "") == target_char:
		return atlas["DIAG_NW"]
	if tile_chars.get(coords + Vector2i(1, 1), "") == target_char:
		return atlas["DIAG_SE"]
	if tile_chars.get(coords + Vector2i(-1, 1), "") == target_char:
		return atlas["DIAG_SW"]
	return Vector2i(-1, -1)

## Per the request: a grass cell's own base tile only ever shows a
## notch matching its OWN orthogonal neighbor pattern (a straight
## edge, an adjacent-side corner, etc.) — it has no way to also show
## an water/mud touch at a diagonal that pattern doesn't already
## imply (e.g. a cell with water at N and E already shows a NE
## notch, but if water ALSO happens to touch at SE — completely
## independent information — the base tile can't show that too).
## Returns the atlas coordinate for a small extra notch to draw on
## the transparent overlay layer, or Vector2i(-1,-1) if none needed.
## Checks water first (matching the base-tile priority), then mud.
func _resolve_shore_overlay_atlas(coords: Vector2i, ch: String) -> Vector2i:
	if ch != "." and ch != ",":
		return Vector2i(-1, -1)
	var water_overlay := _find_uncovered_diagonal_notch(coords, "~", {
		"NE": Vector2i(80, 0), "NW": Vector2i(81, 0), "SE": Vector2i(82, 0), "SW": Vector2i(83, 0),
	})
	if water_overlay != Vector2i(-1, -1):
		return water_overlay
	return _find_uncovered_diagonal_notch(coords, "G", {
		"NE": Vector2i(84, 0), "NW": Vector2i(85, 0), "SE": Vector2i(86, 0), "SW": Vector2i(87, 0),
	})

func _find_uncovered_diagonal_notch(coords: Vector2i, target_char: String, notch_atlas: Dictionary) -> Vector2i:
	var n: bool = tile_chars.get(coords + Vector2i(0, -1), "") == target_char
	var s: bool = tile_chars.get(coords + Vector2i(0, 1), "") == target_char
	var e: bool = tile_chars.get(coords + Vector2i(1, 0), "") == target_char
	var w: bool = tile_chars.get(coords + Vector2i(-1, 0), "") == target_char
	var orth_count: int = int(n) + int(s) + int(e) + int(w)
	## 3+ orthogonal sides or fully isolated: the base tile is already
	## mostly/fully target_char-colored, no extra notch needed anywhere.
	if orth_count >= 3:
		return Vector2i(-1, -1)
	var diag_ne: bool = tile_chars.get(coords + Vector2i(1, -1), "") == target_char
	var diag_nw: bool = tile_chars.get(coords + Vector2i(-1, -1), "") == target_char
	var diag_se: bool = tile_chars.get(coords + Vector2i(1, 1), "") == target_char
	var diag_sw: bool = tile_chars.get(coords + Vector2i(-1, 1), "") == target_char
	## A diagonal is already "covered" by the base tile's own shape
	## only when BOTH its component orthogonal sides are also
	## target_char (that's exactly the adjacent-corner case, which
	## already draws its own notch there).
	if diag_ne and not (n and e):
		return notch_atlas["NE"]
	if diag_nw and not (n and w):
		return notch_atlas["NW"]
	if diag_se and not (s and e):
		return notch_atlas["SE"]
	if diag_sw and not (s and w):
		return notch_atlas["SW"]
	return Vector2i(-1, -1)

## Per the "fences running north to south need to be turned so they
## connect correctly, with corner tiles to change the angle" request:
## picks which fence atlas tile a given "I" cell needs, based on which
## of its own 4 orthogonal neighbors are ALSO fence — a self-adjacency
## check, deliberately simpler than _resolve_shore_atlas()'s generic
## neighbor-vs-other-terrain version above (that one handles diagonals,
## 3-neighbor, and 4-neighbor "isolated" cases a shore transition can
## produce; a fence is authored as a simple perimeter loop, so only the
## straight/corner/dead-end cases below are ever expected in practice).
## A dead end (exactly one neighbor) reads as the run continuing in
## that direction — an isolated single post, or a genuine 3-or-4-way
## junction (neither of which the game's current maps ever produce),
## falls back to the plain horizontal tile rather than guessing at a
## shape nobody has actually authored art for.
func _resolve_fence_atlas(coords: Vector2i) -> Vector2i:
	var n: bool = tile_chars.get(coords + Vector2i(0, -1), "") == "I"
	var s: bool = tile_chars.get(coords + Vector2i(0, 1), "") == "I"
	var e: bool = tile_chars.get(coords + Vector2i(1, 0), "") == "I"
	var w: bool = tile_chars.get(coords + Vector2i(-1, 0), "") == "I"
	if n and e and not s and not w:
		return FENCE_CORNER_NE_ATLAS
	if n and w and not s and not e:
		return FENCE_CORNER_NW_ATLAS
	if s and e and not n and not w:
		return FENCE_CORNER_SE_ATLAS
	if s and w and not n and not e:
		return FENCE_CORNER_SW_ATLAS
	if n or s:
		return FENCE_VERTICAL_ATLAS
	return TILE_ATLAS["I"]

## Maps a real fence atlas coordinate (as returned by _resolve_fence_atlas()
## above — always exactly one of TILE_ATLAS["I"] / FENCE_VERTICAL_ATLAS /
## one of the 4 FENCE_CORNER_*_ATLAS constants) to the matching cell in
## FENCE_SHADOW_SOURCE_TEXTURE's own small 6-cell layout — see the
## comment above that texture's own preload for why the shadow draws
## from a separate, rail-free source image rather than the real
## tileset.png. Column order here matches the order the source PNG was
## generated in: straight run, vertical run, then the 4 corners.
func _resolve_fence_shadow_atlas(coords: Vector2i) -> Vector2i:
	var real_atlas: Vector2i = _resolve_fence_atlas(coords)
	if real_atlas == FENCE_VERTICAL_ATLAS:
		return Vector2i(1, 0)
	if real_atlas == FENCE_CORNER_NE_ATLAS:
		return Vector2i(2, 0)
	if real_atlas == FENCE_CORNER_NW_ATLAS:
		return Vector2i(3, 0)
	if real_atlas == FENCE_CORNER_SE_ATLAS:
		return Vector2i(4, 0)
	if real_atlas == FENCE_CORNER_SW_ATLAS:
		return Vector2i(5, 0)
	return Vector2i(0, 0)   ## straight run / fallback

## A bridge ("X") is a structure OVER the water, not a bank — it
## shouldn't make the river read as shallower right where it crosses.
## Water-depth neighbor checks below treat "X" the same as "~" so
## deep water keeps running under a bridge instead of the crossing
## carving a medium/shallow gap into the middle of the river.
func _is_water_like(coords: Vector2i) -> bool:
	var c: String = tile_chars.get(coords, "~")
	return c == "~" or c == "X"

func _resolve_tile_atlas(coords: Vector2i, ch: String) -> Vector2i:
	if ch == "~":
		for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(1,0), Vector2i(-1,0)]:
			if not _is_water_like(coords + d):
				return SHALLOW_WATER_VARIANT_ATLAS[_shore_variant_index(coords, SHALLOW_WATER_VARIANT_ATLAS.size(), 1009)]
		## Not shallow (no orthogonal non-water neighbor) — check the
		## rest of the 5x5 block (everything except the center cell
		## itself) for medium. This deliberately re-checks the 4
		## diagonal distance-1 cells too, since the shallow check above
		## only looked at orthogonal neighbors — a diagonal-only
		## non-water touch at distance 1 should still read as medium,
		## not jump straight to deep.
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				if dx == 0 and dy == 0:
					continue
				if not _is_water_like(coords + Vector2i(dx, dy)):
					return MEDIUM_WATER_ATLAS
		return DEEP_WATER_ATLAS
	## Per the report: a tree standing next to a mud path showed a hard
	## rectangular seam, since every OTHER terrain type fell straight
	## into the line below, never reaching the shore/mud-edge system
	## just past it. Reuses that same generic neighbor-scanning
	## resolver against the tree's own mud-blend art — the rarer 3+-
	## side/diagonal-only cases fall back to the plain tree tile
	## (Vector2i(-1,-1) below coerces to it via the final `return
	## TILE_ATLAS.get(...)`), since a tree genuinely hemmed in by mud
	## on that many sides is rare enough not to need its own art.
	if ch == "T":
		var tree_mud_atlas := _resolve_shore_atlas(coords, "G", {
			"N": TREE_MUD_NORTH_ATLAS, "S": TREE_MUD_SOUTH_ATLAS, "E": TREE_MUD_EAST_ATLAS, "W": TREE_MUD_WEST_ATLAS,
			"NE": TREE_MUD_CORNER_NE_ATLAS, "NW": TREE_MUD_CORNER_NW_ATLAS, "SE": TREE_MUD_CORNER_SE_ATLAS, "SW": TREE_MUD_CORNER_SW_ATLAS,
			"THREE_N": TILE_ATLAS["T"], "THREE_S": TILE_ATLAS["T"], "THREE_E": TILE_ATLAS["T"], "THREE_W": TILE_ATLAS["T"],
			"ISOLATED": TILE_ATLAS["T"], "ISTHMUS_NS": TILE_ATLAS["T"], "ISTHMUS_EW": TILE_ATLAS["T"],
			"DIAG_NE": TILE_ATLAS["T"], "DIAG_NW": TILE_ATLAS["T"], "DIAG_SE": TILE_ATLAS["T"], "DIAG_SW": TILE_ATLAS["T"],
		})
		if tree_mud_atlas != Vector2i(-1, -1):
			return tree_mud_atlas
		return TILE_ATLAS["T"]
	if ch == "X":
		return _resolve_bridge_atlas(coords)
	if ch == "G":
		return MUD_VARIANT_ATLAS[_shore_variant_index(coords, MUD_VARIANT_ATLAS.size(), 1103)]
	if ch != "." and ch != ",":
		return TILE_ATLAS.get(ch, Vector2i(0, 0))
	## Shore edges (water first, mud second — water wins if a cell
	## somehow borders both) take priority over plain grass variation.
	## Per the request for shore variance: pick one of each straight
	## edge's variants deterministically per-tile (same hash pattern as
	## the plain grass variants below, with a salt so the two don't end
	## up visibly correlated) — only the single-edge N/S/E/W case gets
	## varied; corners/three/isolated/isthmus/diag stay on their one
	## piece each, since they already only ever appear as one-offs at
	## the ends of a shore run, not as a long repeating stretch.
	var water_atlas := _resolve_shore_atlas(coords, "~", {
		"N": SHORE_NORTH_ATLAS_VARIANTS[_shore_variant_index(coords, SHORE_NORTH_ATLAS_VARIANTS.size(), 101)],
		"S": SHORE_SOUTH_ATLAS_VARIANTS[_shore_variant_index(coords, SHORE_SOUTH_ATLAS_VARIANTS.size(), 211)],
		"E": SHORE_EAST_ATLAS_VARIANTS[_shore_variant_index(coords, SHORE_EAST_ATLAS_VARIANTS.size(), 307)],
		"W": SHORE_WEST_ATLAS_VARIANTS[_shore_variant_index(coords, SHORE_WEST_ATLAS_VARIANTS.size(), 401)],
		"NE": SHORE_CORNER_NE_ATLAS, "NW": SHORE_CORNER_NW_ATLAS, "SE": SHORE_CORNER_SE_ATLAS, "SW": SHORE_CORNER_SW_ATLAS,
		"THREE_N": WATER_THREE_N_ATLAS, "THREE_S": WATER_THREE_S_ATLAS, "THREE_E": WATER_THREE_E_ATLAS, "THREE_W": WATER_THREE_W_ATLAS,
		"ISOLATED": WATER_ISOLATED_ATLAS, "ISTHMUS_NS": WATER_ISTHMUS_NS_ATLAS, "ISTHMUS_EW": WATER_ISTHMUS_EW_ATLAS,
		"DIAG_NE": WATER_DIAG_NE_ATLAS, "DIAG_NW": WATER_DIAG_NW_ATLAS, "DIAG_SE": WATER_DIAG_SE_ATLAS, "DIAG_SW": WATER_DIAG_SW_ATLAS,
	})
	if water_atlas != Vector2i(-1, -1):
		return water_atlas
	var mud_atlas := _resolve_shore_atlas(coords, "G", {
		"N": MUD_SHORE_NORTH_ATLAS_VARIANTS[_shore_variant_index(coords, MUD_SHORE_NORTH_ATLAS_VARIANTS.size(), 613)],
		"S": MUD_SHORE_SOUTH_ATLAS_VARIANTS[_shore_variant_index(coords, MUD_SHORE_SOUTH_ATLAS_VARIANTS.size(), 701)],
		"E": MUD_SHORE_EAST_ATLAS_VARIANTS[_shore_variant_index(coords, MUD_SHORE_EAST_ATLAS_VARIANTS.size(), 809)],
		"W": MUD_SHORE_WEST_ATLAS_VARIANTS[_shore_variant_index(coords, MUD_SHORE_WEST_ATLAS_VARIANTS.size(), 907)],
		"NE": MUD_SHORE_CORNER_NE_ATLAS, "NW": MUD_SHORE_CORNER_NW_ATLAS, "SE": MUD_SHORE_CORNER_SE_ATLAS, "SW": MUD_SHORE_CORNER_SW_ATLAS,
		"THREE_N": MUD_THREE_N_ATLAS, "THREE_S": MUD_THREE_S_ATLAS, "THREE_E": MUD_THREE_E_ATLAS, "THREE_W": MUD_THREE_W_ATLAS,
		"ISOLATED": MUD_ISOLATED_ATLAS, "ISTHMUS_NS": MUD_ISTHMUS_NS_ATLAS, "ISTHMUS_EW": MUD_ISTHMUS_EW_ATLAS,
		"DIAG_NE": MUD_DIAG_NE_ATLAS, "DIAG_NW": MUD_DIAG_NW_ATLAS, "DIAG_SE": MUD_DIAG_SE_ATLAS, "DIAG_SW": MUD_DIAG_SW_ATLAS,
	})
	if mud_atlas != Vector2i(-1, -1):
		return mud_atlas
	## Deterministic per-position hash — the same map cell always
	## picks the same grass variant on every load, rather than
	## flickering between runs. A proper integer-mixing hash (not a
	## simple linear x*7+y*13), per the request — a linear function
	## mod a small variant count produces visible diagonal striping
	## across the map; this scrambles the bits first so neighboring
	## cells don't fall into an obvious repeating pattern.
	var h: int = coords.x * 374761393 + coords.y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	## "," keeps its own distinct decorative look when no shore/mud
	## transition applies — the extension above is only to catch it
	## when it genuinely borders water or mud, not to fold it into
	## ordinary "." grass variation the rest of the time.
	if ch == ",":
		return TILE_ATLAS[","]
	var variant_index: int = int(abs(h)) % GRASS_VARIANT_ATLAS.size()
	return GRASS_VARIANT_ATLAS[variant_index]

## Per the follow-up request: one large, muted text label per
## province, centered over its own broad region — visually distinct
## from the smaller, brighter city name labels (see
## _spawn_location_labels above them).
func _spawn_province_labels() -> void:
	## Per the TILE_SIZE 16->64 upscale: font_size/outline_size/label
	## box/offsets are all scaled by FX_SCALE so this label still reads
	## at the same ON-SCREEN size as before — the camera's own zoom was
	## divided by FX_SCALE to keep showing the same number of tiles, so
	## anything measured in fixed pixels (Label text, unlike tile art)
	## would otherwise shrink to a quarter of its old apparent size.
	for prov in current_map_def.provinces:
		var label := Label.new()
		label.text = prov.province_name
		label.add_theme_font_size_override("font_size", 15 * FX_SCALE)
		label.add_theme_color_override("font_color", Color(0.72, 0.6, 0.35, 0.75))
		label.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.04, 0.6))
		label.add_theme_constant_override("outline_size", int(2 * FX_SCALE))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(prov.label_tile.x * TILE_SIZE - 60 * FX_SCALE, prov.label_tile.y * TILE_SIZE - 6 * FX_SCALE)
		label.custom_minimum_size = Vector2(120, 16) * FX_SCALE
		label.size = Vector2(120, 16) * FX_SCALE
		label.z_index = 5
		add_child(label)

## Per the request: one small text label per World Map location,
## positioned just below its own 'Z' marker tile — reuses the same
## world-space Label pattern the ambush/social markers already use
## (position set directly in tile*TILE_SIZE coordinates, added as a
## direct child so the camera handles it like any other map object).
func _spawn_location_labels() -> void:
	## See _spawn_province_labels()'s comment re: FX_SCALE — same reason.
	for loc in current_map_def.locations:
		var label := Label.new()
		label.text = loc.location_name
		label.add_theme_font_size_override("font_size", 11 * FX_SCALE)
		label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
		label.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05))
		label.add_theme_constant_override("outline_size", int(3 * FX_SCALE))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(loc.world_tile.x * TILE_SIZE - 40 * FX_SCALE, loc.world_tile.y * TILE_SIZE + TILE_SIZE + 1 * FX_SCALE)
		label.custom_minimum_size = Vector2(96, 12) * FX_SCALE
		label.size = Vector2(96, 12) * FX_SCALE
		label.z_index = 9
		add_child(label)

## Per the request: role-specific NPC sprites — a shopkeeper genuinely
## looks like a shopkeeper, a priest like a priest, and so on — rather
## than one generic sprite recoloured per role. Each is already
## pre-downsampled to the real 16x16 final size (see gen_npc_sprites.py),
## so no scale correction is needed the way the old shared npc.png
## required.
const NPC_SHOPKEEPER_TEXTURE := preload("res://assets/sprites/npc_shopkeeper.png")
const NPC_PRIEST_TEXTURE := preload("res://assets/sprites/npc_priest.png")
const NPC_TRAINER_TEXTURE := preload("res://assets/sprites/npc_trainer.png")
const NPC_TRAVELLER_TEXTURE := preload("res://assets/sprites/npc_traveller.png")
## Per the request: distinct sprite art for each of Gotheim's 9 real
## NPCs — keyed by "<quest_id>_<npc_id>" so future adventures can add
## their own entries without any collision risk. Any quest NPC not
## listed here falls back to NPC_TRAVELLER_TEXTURE automatically (see
## the lookup in _build_map()), so this dictionary only ever needs
## entries for NPCs that actually have dedicated art.
const QUEST_NPC_TEXTURES := {
	"gotheim_wilhelm": preload("res://assets/sprites/npc_gotheim_wilhelm.png"),
	"gotheim_smith": preload("res://assets/sprites/npc_gotheim_hugo.png"),
	"gotheim_emil": preload("res://assets/sprites/npc_gotheim_emil.png"),
	"gotheim_kai": preload("res://assets/sprites/npc_gotheim_kai.png"),
	"gotheim_bruno": preload("res://assets/sprites/npc_gotheim_bruno.png"),
	"gotheim_martha": preload("res://assets/sprites/npc_gotheim_martha.png"),
	"gotheim_children": preload("res://assets/sprites/npc_gotheim_children.png"),
	"gotheim_gerd": preload("res://assets/sprites/npc_gotheim_gerd.png"),
	"gotheim_maria": preload("res://assets/sprites/npc_gotheim_maria.png"),
}
const NPC_ELDER_TEXTURE := preload("res://assets/sprites/npc_elder.png")

## Per the request: shared by every Player/NPC spawn site — builds one
## shadow Sprite2D, already anchored at the character's own feet
## (PERSON_SHADOW_ANCHOR_PX) with its rotation pivot on the shadow
## texture's own anchor point (PERSON_SHADOW_PIVOT_PX), and pinned to
## the same flat z-tier tree/wall shadows already render on
## (shadow_container.z_index, absolute rather than relative — see the
## const's own comment) so a character's shadow always falls under
## their own building/roof layer exactly like every other ground
## shadow, never merely "one below whatever z their owner happens to
## have." Callers just add_child() the result onto the character's
## own sprite/node — position, rotation and visibility are all then
## kept current by _update_shadow_angles(), same as tree/wall shadows.
func _make_person_shadow() -> Sprite2D:
	var shadow := Sprite2D.new()
	shadow.name = "Shadow"
	shadow.texture = SHADOW_TEXTURE_PERSON
	shadow.centered = false
	shadow.offset = -PERSON_SHADOW_PIVOT_PX
	shadow.position = PERSON_SHADOW_ANCHOR_PX
	shadow.z_as_relative = false
	shadow.z_index = shadow_container.z_index
	shadow.modulate = Color(1, 1, 1, 1)
	return shadow

func _spawn_shopkeeper(coords: Vector2i) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = NPC_SHOPKEEPER_TEXTURE
	sprite.centered = false
	sprite.scale = Vector2(NPC_SPRITE_SCALE, NPC_SPRITE_SCALE)
	sprite.position = Vector2(coords.x * TILE_SIZE, coords.y * TILE_SIZE)
	sprite.z_index = above_buildings_z   ## stays above ground/shadows/buildings, however many ground layers this map needs
	add_child(sprite)
	sprite.add_child(_make_person_shadow())
	shopkeeper_coords.append(coords)
	npc_sprites_by_tile[coords] = sprite   ## per the request: hides the trader from outside their own house — see _set_building_roof_visible()

func _spawn_priest(coords: Vector2i) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = NPC_PRIEST_TEXTURE
	sprite.centered = false
	sprite.scale = Vector2(NPC_SPRITE_SCALE, NPC_SPRITE_SCALE)
	sprite.position = Vector2(coords.x * TILE_SIZE, coords.y * TILE_SIZE)
	sprite.z_index = above_buildings_z   ## stays above ground/shadows/buildings, however many ground layers this map needs
	add_child(sprite)
	sprite.add_child(_make_person_shadow())
	priest_coords.append(coords)
	npc_sprites_by_tile[coords] = sprite   ## per the request: hides indoor NPCs from outside their own house — see _set_building_roof_visible()

## Per the request: the Village Elder, a new quest-giver NPC — a
## distinct warm amber/brown tint, an old, settled colour befitting
## someone who's spent a whole life in this one village.
func _spawn_elder() -> void:
	var sprite := Sprite2D.new()
	sprite.texture = NPC_ELDER_TEXTURE
	sprite.centered = false
	sprite.scale = Vector2(NPC_SPRITE_SCALE, NPC_SPRITE_SCALE)
	sprite.position = Vector2(elder_tile.x * TILE_SIZE, elder_tile.y * TILE_SIZE)
	sprite.z_index = above_buildings_z   ## stays above ground/shadows/buildings, however many ground layers this map needs
	add_child(sprite)
	sprite.add_child(_make_person_shadow())
	## Per the request: hides the Elder if their tile is ever placed
	## inside a building on some future map — spawns after
	## _update_roof_visibility() has already settled the player's real
	## starting building (see _ready()'s call order), so
	## player_inside_building here is the real value, not the -1
	## placeholder _build_map() uses for its own earlier spawns.
	npc_sprites_by_tile[elder_tile] = sprite
	var elder_building := _roofed_building_index_at(elder_tile)
	sprite.visible = elder_building == -1 or elder_building == player_inside_building

func _spawn_npc(coords: Vector2i, dialogue: String, is_trainer: bool = false) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = NPC_TRAINER_TEXTURE if is_trainer else NPC_TRAVELLER_TEXTURE
	sprite.centered = false
	sprite.scale = Vector2(NPC_SPRITE_SCALE, NPC_SPRITE_SCALE)
	sprite.position = Vector2(coords.x * TILE_SIZE, coords.y * TILE_SIZE)
	sprite.z_index = above_buildings_z   ## stays above ground/shadows/buildings, however many ground layers this map needs
	add_child(sprite)
	sprite.add_child(_make_person_shadow())
	if is_trainer:
		petty_magic_trainer_coords.append(coords)
	else:
		npc_dialogue[coords] = dialogue
	npc_sprites_by_tile[coords] = sprite   ## per the request: hides indoor NPCs from outside their own house — see _set_building_roof_visible()

## Places the "!" marker on a real walkable tile within
## AMBUSH_MARKER_MAX_DISTANCE_FROM_PLAYER of the player — never on an
## NPC's own tile (those already block movement) and never underneath
## the player themselves. Falls back to doing nothing (no marker, no
## fight — the safer failure) if no such tile exists nearby, rather
## than forcing one somewhere that breaks the "within 3 tiles" promise.
func _spawn_ambush_marker(monster_names: Array[String]) -> void:
	var candidates: Array[Vector2i] = []
	for dx in range(-AMBUSH_MARKER_MAX_DISTANCE_FROM_PLAYER, AMBUSH_MARKER_MAX_DISTANCE_FROM_PLAYER + 1):
		for dy in range(-AMBUSH_MARKER_MAX_DISTANCE_FROM_PLAYER, AMBUSH_MARKER_MAX_DISTANCE_FROM_PLAYER + 1):
			if dx == 0 and dy == 0:
				continue
			var tile: Vector2i = player.grid_pos + Vector2i(dx, dy)
			if abs(dx) + abs(dy) > AMBUSH_MARKER_MAX_DISTANCE_FROM_PLAYER:
				continue   ## Manhattan distance, matching how tile-step distance is measured everywhere else in this project
			if is_walkable(tile):
				candidates.append(tile)
	if candidates.is_empty():
		return

	_clear_ambush_marker()
	ambush_marker_tile = candidates[randi() % candidates.size()]
	ambush_group_names = monster_names
	ambush_perception_used = false
	ambush_sneak_test_used = false
	ambush_sneak_test_success = false

	## Per the request: a gold marker instead of white while a gather
	## task is active AND at least one monster in this group would
	## actually drop the item that task is asking for — a real,
	## reachable signal, not just a random recolour.
	var marker_color := Color.WHITE
	var active_task: Dictionary = GameState.player_character.get_active_task()
	if active_task.get("task_type", "") == "gather":
		var target_item: String = str(active_task.get("target_key", ""))
		for n in monster_names:
			var mdef: MonsterDefinition = GameData.monster_db.find_by_name(n)
			if mdef != null and TrophyLookup.pick_trophy_for_monster(mdef) == target_item:
				marker_color = Color(1.0, 0.84, 0.0)   ## gold
				break

	var marker := Label.new()
	marker.text = "!"
	## FX_SCALE'd for the same reason as _spawn_province_labels()'s font.
	marker.add_theme_font_size_override("font_size", 14 * FX_SCALE)
	marker.add_theme_color_override("font_color", marker_color)
	marker.add_theme_color_override("font_outline_color", Color.BLACK)
	marker.add_theme_constant_override("outline_size", int(4 * FX_SCALE))
	marker.position = Vector2(ambush_marker_tile.x * TILE_SIZE, ambush_marker_tile.y * TILE_SIZE - 10 * FX_SCALE)
	marker.z_index = above_buildings_z + 4
	add_child(marker)
	ambush_marker = marker

func _clear_ambush_marker() -> void:
	if is_instance_valid(ambush_marker):
		ambush_marker.queue_free()
	ambush_marker = null
	ambush_marker_tile = Vector2i(-1, -1)
	ambush_group_names = []

## Checked every step, per the request: once the player has walked
## more than AMBUSH_MARKER_FORGET_DISTANCE tiles from a marker they
## never clicked, it disappears — the encounter was successfully
## avoided entirely, not merely postponed.
func _check_ambush_marker_distance() -> void:
	if ambush_marker_tile == Vector2i(-1, -1):
		return
	var dist: int = abs(player.grid_pos.x - ambush_marker_tile.x) + abs(player.grid_pos.y - ambush_marker_tile.y)
	if dist > AMBUSH_MARKER_FORGET_DISTANCE:
		_clear_ambush_marker()

## Triggered by a real single left-click landing on the marker's own
## tile. Per the follow-up request, this is no longer a guaranteed
## ambush — the first click on a given marker spends a one-time
## Perception Test attempting to close in unseen:
##   - Success: offers a real choice (see _show_ambush_choice) between
##     surprising the group (Surprised for Round 1, the old behaviour)
##     or slipping away without them ever noticing (no fight at all).
##     Clicking the marker again afterward just re-offers the same
##     choice — no reason to force an immediate decision.
##   - Failure: the group's been alerted, so there's no more sneaking
##     to be had. A further click on the marker is a deliberate manual
##     attack, and starts the fight with nobody Surprised.
func _on_ambush_marker_clicked() -> void:
	if not ambush_sneak_test_used:
		ambush_sneak_test_used = true
		var perception_def: SkillDefinition = GameData.skill_db.find_by_name("Perception")
		var success := false
		var roller: Character = null
		if perception_def != null:
			var party_result := _tr_party(GameState.party, perception_def)
			var result: TestResolver.TestResult = party_result["result"]
			roller = party_result["roller"]
			success = result.success
		ambush_sneak_test_success = success
		if not success:
			var who: String = roller.character_name if roller != null else "Someone"
			_show_info_popup("Perception — Spotted", "%s tries to close in unseen, but gives the game away. There's no sneaking up on them now — attacking from here means fighting them at full readiness." % who)
			return
	if ambush_sneak_test_success:
		var surprise: bool = await _show_ambush_choice("You've closed in unseen. Surprise the group, or slip away before they notice you?")
		if surprise:
			await _start_ambush_field_encounter(true)
		return
	## The sneak attempt already failed once — this click is a
	## deliberate manual attack, so the fight starts with nobody
	## Surprised.
	await _start_ambush_field_encounter(false)

## Actually leaves for FieldEncounter.tscn with the ambush group —
## split out from _on_ambush_marker_clicked() so both the
## Surprise-chosen path and the failed-sneak-then-attack-anyway path
## can share it, differing only in whether Surprise actually applies.
func _start_ambush_field_encounter(is_ambush: bool) -> void:
	GameState.return_position = player.grid_pos
	GameState.pending_encounter_monster_names = ambush_group_names
	GameState.pending_encounter_is_player_ambush = is_ambush
	_clear_ambush_marker()
	current_path.clear()
	encounter_label_text.text = EncounterNarrator.random_line()
	encounter_label.visible = true
	await get_tree().create_timer(1.4).timeout
	_capture_battle_terrain_snapshot()
	get_tree().change_scene_to_file("res://scenes/FieldEncounter.tscn")

## Real Surprise-or-Leave choice offered after a successful sneak-in
## attempt — same shared Y/N confirm-prompt idiom as
## _show_wilderness_choice() (Space accepts the highlighted default,
## Y/N pick directly). Returns true for Surprise, false for Leave.
func _show_ambush_choice(text: String) -> bool:
	_start_confirm_prompt(text + "\n", "Surprise", "Leave")
	encounter_label.visible = true
	_awaiting_ambush_choice = true
	while _awaiting_ambush_choice:
		await get_tree().process_frame
	encounter_label.visible = false
	return _ambush_choice_result

## Per the reported bug: the actual click-trigger fix for a quest
## monster's own lair — reuses the already-proven
## setup_quest_monster_encounter() from earlier work, which reads the
## monster's own genuinely-current (possibly already-healed) state.
func _on_quest_monster_marker_clicked(tile: Vector2i) -> void:
	var mmarker: QuestMonsterMapMarker = quest_monster_marker_tiles[tile]
	## Per the request: the quest only happens once — a monster
	## already defeated for this quest no longer triggers a fight.
	if GameState.player_character.get_quest_monster_defeated(mmarker.quest_id, mmarker.monster_id):
		return
	var qdef: QuestDefinition = load("res://data/quests/%s.tres" % mmarker.quest_id) as QuestDefinition
	var mdef: QuestMonsterDefinition = qdef.find_monster(mmarker.monster_id) if qdef != null else null
	if mdef == null:
		return
	GameState.player_character.setup_quest_monster_encounter(mdef, mmarker.quest_id)
	GameState.return_position = player.grid_pos
	current_path.clear()
	## Per the request: more narrative fade-in text as the quest
	## progresses — the source's own text as the Jabberslythe is
	## actually encountered, in place of the generic encounter line
	## for this specific fight.
	if mmarker.quest_id == "gotheim" and mmarker.monster_id == "beast":
		encounter_label_text.text = "The strange burbling noise stops. From the wide mouth of the cave, something enormous shifts in the dark — wounded, cornered, and utterly furious."
	else:
		encounter_label_text.text = EncounterNarrator.random_line()
	encounter_label.visible = true
	await get_tree().create_timer(1.4).timeout
	_capture_battle_terrain_snapshot()
	get_tree().change_scene_to_file("res://scenes/FieldEncounter.tscn")

## No detection roll, per the request — this spawns unconditionally
## whenever a social encounter is rolled, on any real walkable tile
## within AMBUSH_MARKER_MAX_DISTANCE_FROM_PLAYER (the same 3-tile
## radius the ambush marker uses, for a consistent feel between the
## two marker types).
func _spawn_social_marker() -> void:
	var candidates: Array[Vector2i] = []
	for dx in range(-AMBUSH_MARKER_MAX_DISTANCE_FROM_PLAYER, AMBUSH_MARKER_MAX_DISTANCE_FROM_PLAYER + 1):
		for dy in range(-AMBUSH_MARKER_MAX_DISTANCE_FROM_PLAYER, AMBUSH_MARKER_MAX_DISTANCE_FROM_PLAYER + 1):
			if dx == 0 and dy == 0:
				continue
			var tile: Vector2i = player.grid_pos + Vector2i(dx, dy)
			if abs(dx) + abs(dy) > AMBUSH_MARKER_MAX_DISTANCE_FROM_PLAYER:
				continue
			if is_walkable(tile):
				candidates.append(tile)
	if candidates.is_empty():
		return

	_clear_social_marker()
	social_marker_tile = candidates[randi() % candidates.size()]
	social_marker_encounter = GameData.social_encounter_db.random_encounter()
	social_perception_used = false
	if social_marker_encounter != null:
		social_marker_name_info = NPCNameGenerator.random_name()
		if not social_marker_encounter.situations.is_empty():
			social_marker_situation_index = randi() % social_marker_encounter.situations.size()
		if not social_marker_encounter.opening_flavors.is_empty():
			social_marker_opening_flavor_index = randi() % social_marker_encounter.opening_flavors.size()

	## Per the request: a gold marker instead of white while a
	## find-encounter task is active AND this is genuinely the specific
	## encounter it's looking for.
	var marker_color := Color.WHITE
	var active_task: Dictionary = GameState.player_character.get_active_task()
	if active_task.get("task_type", "") == "find_encounter" and social_marker_encounter != null:
		if str(active_task.get("target_key", "")) == social_marker_encounter.encounter_name:
			marker_color = Color(1.0, 0.84, 0.0)   ## gold

	var marker := Label.new()
	marker.text = "?"
	## FX_SCALE'd for the same reason as _spawn_province_labels()'s font.
	marker.add_theme_font_size_override("font_size", 14 * FX_SCALE)
	marker.add_theme_color_override("font_color", marker_color)
	marker.add_theme_color_override("font_outline_color", Color.BLACK)
	marker.add_theme_constant_override("outline_size", int(4 * FX_SCALE))
	marker.position = Vector2(social_marker_tile.x * TILE_SIZE, social_marker_tile.y * TILE_SIZE - 10 * FX_SCALE)
	marker.z_index = above_buildings_z + 4
	add_child(marker)
	social_marker = marker

func _clear_social_marker() -> void:
	if is_instance_valid(social_marker):
		social_marker.queue_free()
	social_marker = null
	social_marker_tile = Vector2i(-1, -1)
	social_marker_encounter = null
	social_marker_name_info = null
	social_marker_situation_index = -1
	social_marker_opening_flavor_index = -1

## Cleared the same way the ambush marker is — "like combat
## encounters," per the request — once the player has walked more than
## AMBUSH_MARKER_FORGET_DISTANCE tiles away without clicking it.
func _check_social_marker_distance() -> void:
	if social_marker_tile == Vector2i(-1, -1):
		return
	var dist: int = abs(player.grid_pos.x - social_marker_tile.x) + abs(player.grid_pos.y - social_marker_tile.y)
	if dist > AMBUSH_MARKER_FORGET_DISTANCE:
		_clear_social_marker()

## Triggered by a real single left-click landing on the marker's own
## tile — SocialEncounter.tscn picks its own random encounter, so
## there's no group/state to hand off here beyond the return position.
func _on_social_marker_clicked() -> void:
	GameState.return_position = player.grid_pos
	## Per the request ("we have difficulty level in combat, let's add
	## it to social encounters too... all encounters should have the
	## same modifiers"): same map-based tier field encounters already
	## use (get_difficulty_tier_at()), computed from where the marker
	## actually is rather than the player's current tile — the marker
	## can sit unclicked for a while and the player may have moved on
	## by now. Read once, by SocialEncounterScreen._build_npc_roster(),
	## via DifficultyTiers.apply_social_npc_tier_bonus().
	## Per the follow-up request ("let social encounter difficulty tier
	## minimum be 1, ie. never 0... but let that rule affect nothing
	## else"): floored at 1 here, ONLY here — get_difficulty_tier_at()
	## itself, current_field_difficulty_tier, and every real Tier-0 area
	## on the map (including the deliberate "beginner area, no monster
	## over 12 HP" design — see DifficultyTiers.BEGINNER_AREA_MAX_
	## WOUNDS) are all completely untouched by this; a social encounter
	## rolled inside a genuine Tier 0 combat area simply gets treated as
	## Tier 1 for its own NPCs, nothing more.
	GameState.current_social_difficulty_tier = maxi(1, get_difficulty_tier_at(social_marker_tile))
	if social_marker_encounter != null:
		GameState.pending_social_encounter_name = social_marker_encounter.encounter_name
		if social_marker_name_info != null:
			GameState.pending_social_npc_name = social_marker_name_info.full_name
			GameState.pending_social_npc_gender = social_marker_name_info.gender
		GameState.pending_social_situation_index = social_marker_situation_index
		GameState.pending_social_opening_flavor_index = social_marker_opening_flavor_index
	_clear_social_marker()
	current_path.clear()
	encounter_label_text.text = EncounterNarrator.random_line()
	encounter_label.visible = true
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/SocialEncounter.tscn")

## Per the request: a right-clicked marker offers a one-time +0
## Perception Test. On success, a popup reveals what's actually
## waiting there — the specific monster group for an ambush marker, or
## the specific NPC/encounter for a social marker (the exact same one
## pre-selected when the marker spawned, not a fresh roll). On
## failure, or after the check has already been used once, nothing
## further happens — the marker itself is untouched either way, so
## the player can still choose to approach or ignore it normally.
func _perform_marker_perception_check() -> void:
	var target := _radial_menu_target_marker
	_radial_menu_target_marker = ""
	if target == "":
		return
	if target == "ambush" and ambush_perception_used:
		return
	if target == "social" and social_perception_used:
		return

	var perception_def: SkillDefinition = GameData.skill_db.find_by_name("Perception")
	if perception_def == null:
		return
	var party_result := _tr_party(GameState.party, perception_def)
	var result: TestResolver.TestResult = party_result["result"]
	var roller: Character = party_result["roller"]

	if target == "ambush":
		ambush_perception_used = true
		if not result.success:
			_show_info_popup("Perception", "You strain your senses, but come away none the wiser about what's ahead.")
			return
		var counts: Dictionary = {}
		var order: Array[String] = []
		for n in ambush_group_names:
			if not counts.has(n):
				order.append(n)
			counts[n] = counts.get(n, 0) + 1
		var parts: Array[String] = []
		for n in order:
			parts.append(("%d %s" % [counts[n], n]) if counts[n] > 1 else n)
		_show_info_popup("Perception — Something's Waiting", "%s catches sight of what's lurking ahead: %s." % [roller.character_name, ", ".join(parts)])
	elif target == "social":
		social_perception_used = true
		if not result.success:
			_show_info_popup("Perception", "You strain your senses, but come away none the wiser about who's ahead.")
			return
		if social_marker_encounter != null and social_marker_name_info != null:
			_show_info_popup("Perception — Someone's Waiting", "%s gets a look at who's ahead: %s (%s)." % [roller.character_name, social_marker_name_info.full_name, social_marker_encounter.encounter_name])
		else:
			_show_info_popup("Perception", "You sense someone waiting nearby, though you can't quite make them out.")

## A simple, dark-themed info popup matching this project's own visual
## style rather than Godot's built-in AcceptDialog (which wouldn't
## automatically pick up the custom theme's look) — a centered panel
## with a title, body text, and a single dismiss button.
## Per the request: shown once, at the very start of a character's
## life — a class/career-themed origin story that must be read before
## the player can move. Unlike _show_info_popup, this one has no
## backdrop-click-to-dismiss (it's meant to actually be read, not
## clicked past by accident) and records itself as the character's
## first Journal entry the moment it's dismissed.
func _show_origin_story() -> void:
	story_popup_active = true
	var c: Character = GameState.player_character
	var story_text: String = OriginStories.get_story(c.character_name, c.career.career_class if c.career != null else "Warrior", c.career.career_name if c.career != null else "Wanderer")

	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.7)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(backdrop)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -280
	panel.offset_right = 280
	panel.offset_top = -220
	panel.offset_bottom = 220
	backdrop.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title_label := Label.new()
	title_label.text = "%s's Story Begins..." % c.character_name
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(title_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var body_label := Label.new()
	body_label.text = story_text
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	body_label.custom_minimum_size = Vector2(520, 0)
	scroll.add_child(body_label)

	var begin_btn := Button.new()
	begin_btn.text = "Begin  [Space]"
	begin_btn.pressed.connect(func():
		layer.queue_free()
		story_popup_active = false
		c.has_seen_origin_story = true
		c.add_journal_entry("Origin", "The Story Begins", story_text)
		GameState.autosave()
	)
	vbox.add_child(begin_btn)
	begin_btn.grab_focus()

func _show_info_popup(popup_title: String, body: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.5)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(backdrop)

	## Real bug fix: this used to ALSO set panel.position on top of
	## anchors_preset(PRESET_CENTER) — the anchor already re-origins
	## position to the parent's center, so adding another half-viewport
	## offset on top of that pushed the whole panel off-screen to the
	## bottom-right, cutting it off and making its own OK button
	## unreachable (the real cause of "won't close", not a separate
	## bug). Fixed by using anchor OFFSETS instead of a raw position —
	## the correct way to size/center a Control relative to an anchor.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -180
	panel.offset_right = 180
	panel.offset_top = -70
	panel.offset_bottom = 70
	backdrop.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title_label := Label.new()
	title_label.text = popup_title
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(title_label)

	var body_label := Label.new()
	body_label.text = body
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(body_label)

	var ok_btn := Button.new()
	ok_btn.text = "OK"
	ok_btn.pressed.connect(func(): layer.queue_free())
	vbox.add_child(ok_btn)

	## Robust fallbacks so a mispositioned or off-screen popup (from
	## any future layout issue) can never trap the player again —
	## clicking anywhere on the backdrop, or pressing Escape/Space,
	## also closes it.
	backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			layer.queue_free()
			get_viewport().set_input_as_handled()
	)

## Per the request: "towns and cities they visited (once)" — this
## project's current map doesn't yet have real towns beyond the
## starting village, so the closest honest equivalent is its named,
## story-worthy zones (not the generic "East of the River" catch-all,
## which isn't really a place). A real hook for a future map with
## actual settlements to extend, not the final word on what counts.
const LOCATION_JOURNAL_FLAVOR := {
	"Dark Forest (Goblin Fort)": "The trees close in fast out here, and something with a truly appalling sense of hygiene has clearly been marking territory. Somewhere ahead, muffled through the underbrush, comes the unmistakable sound of goblins arguing about something — possibly dinner, possibly you.",
	"Northern Cave (Bears)": "The air turns cold and starts smelling like wet fur and old bones the moment you step past the treeline. Whatever's denning up in that cave clearly doesn't get many visitors, and clearly prefers it that way.",
}

func _check_location_journal(new_tile: Vector2i) -> void:
	var area_name := get_difficulty_tier_area_name_at(new_tile)
	if area_name == "" or not LOCATION_JOURNAL_FLAVOR.has(area_name):
		return
	GameState.player_character.add_journal_entry(
		"Location", "Arrived: %s" % area_name, LOCATION_JOURNAL_FLAVOR[area_name],
		"location:%s" % area_name
	)

## Per the request: standing on a local map's own exit tile offers to
## leave for the World Map, and standing on a World Map city tile
## offers to enter its local map — both triggered simply by arriving
## on the tile (walking there, or being warped there after travel),
## not by clicking. Re-checked only when the player genuinely lands
## on a NEW tile (not every frame while standing still), and only
## re-offered if they actually leave and come back, so declining
## once doesn't nag them on every subsequent step.
func _check_standing_trigger(new_tile: Vector2i) -> void:
	## Real bug fix, companion to the reentrancy guard in
	## _run_travel_day_loop(): this only ever checked
	## awaiting_travel_confirm before offering to enter a city — not
	## _travel_in_progress/_awaiting_stage_choice, so if the player
	## ever lands on a location tile (e.g. Giessingen, directly on the
	## Gotheim->Altdorf route) while a Stage-choice prompt or an
	## active journey is already using encounter_label, this would
	## fire a SECOND competing prompt on the same shared UI state,
	## silently hanging one of them forever with nothing visible on
	## screen to respond to.
	if current_map_def == null or awaiting_travel_confirm or _travel_in_progress or _awaiting_stage_choice or _awaiting_wilderness_continue or _awaiting_wilderness_choice or _awaiting_ambush_choice:
		return
	## Per the request: the Jabberslythe's own fight starts
	## automatically the moment the player gets near its cave mouth —
	## matching the source's own "anyone approaching the cave... or
	## who causes a disturbance near the cave mouth" — rather than
	## needing an explicit click into the tile itself.
	if not current_map_def.is_world_map and not quest_monster_marker_tiles.is_empty():
		for marker_tile in quest_monster_marker_tiles.keys():
			var mmarker: QuestMonsterMapMarker = quest_monster_marker_tiles[marker_tile]
			if abs(new_tile.x - marker_tile.x) + abs(new_tile.y - marker_tile.y) <= 1:
				if not GameState.player_character.get_quest_monster_defeated(mmarker.quest_id, mmarker.monster_id):
					_on_quest_monster_marker_clicked(marker_tile)
					return
	if new_tile == _last_standing_prompt_tile:
		return
	## Per the Goblin Fort rework request ("Stepping in to the Gate to
	## access the new Goblin fort Dungeon"): the fort's gate tile ("j")
	## only ever appears on Giessingen's own map, so no extra bounds
	## check is needed beyond the map name itself.
	if not current_map_def.is_world_map and current_map_def.map_name == "Giessingen" and tile_chars.get(new_tile, "") == "j":
		_last_standing_prompt_tile = new_tile
		_offer_enter_goblin_fort_dungeon()
		return
	## Per the NE Cave rework request ("Stepping in to the Cave entrance
	## to access the new Cave Dungeon"): same pattern as the Goblin Fort
	## gate above, for the new cave entrance tile ("y").
	if not current_map_def.is_world_map and current_map_def.map_name == "Giessingen" and tile_chars.get(new_tile, "") == "y":
		_last_standing_prompt_tile = new_tile
		_offer_enter_cave_dungeon()
		return
	if not current_map_def.is_world_map and world_map_exit_tile != Vector2i(-1, -1) and new_tile == world_map_exit_tile:
		_last_standing_prompt_tile = new_tile
		_offer_return_to_world_map()
		return
	if current_map_def.is_world_map:
		var loc := _get_location_at(new_tile)
		if loc != null:
			_last_standing_prompt_tile = new_tile
			_offer_enter_location(loc)
			return

## Per the request ("change how the sides and back walls work and make
## it so you can walk on them from the inside, and only block movement
## on their outer edges... allow walking behind the front and back
## walls too"): `from` is the tile the player is actually stepping FROM
## — optional (defaults to NO_FROM, meaning "no directional context"),
## since most callers (pathfinding's solid-grid setup, ambush/social
## marker placement, the camp-position warp check) just want the old
## "is this tile walkable at all, from any direction" answer, and for
## those every wall/front tile stays fully solid exactly as before.
## Only the two real step-by-step movement call sites (the WASD press
## in player_controller.gd and _advance_path()'s click-to-move stepper)
## pass a real `from`, which is what actually turns this on.
##
## The rule, once `from` is known: a WALL_MATERIAL_CHARS tile (every
## wall/front-facade character — sides, back, AND front, per the
## request) is walkable if `from` falls anywhere inside the SAME
## building's own bounding rect (that rect covers the whole footprint,
## walls included — see _compute_buildings()) — i.e. you're already
## inside, walking along the inside face of a wall, whichever wall it
## is. Symmetrically, stepping OFF a wall tile to somewhere outside
## that same building's rect is refused — that's the "outer edge" —
## regardless of what the destination tile itself is (even if it's
## perfectly ordinary walkable grass), since otherwise the first rule
## would let you walk in one side of a wall and straight out the other.
## A door tile is untouched by any of this (it was never in
## WALL_MATERIAL_CHARS to begin with) so entering/leaving through the
## real doorway keeps working exactly as it always has.
##
## Per the direct follow-up ("make the southern edge of the northern
## walls impassable, just like the south wall, and allow player to walk
## behind it on the outside"): the NORTH (back) wall row is a deliberate
## exception to the rule above — it's walkable the OTHER way around.
## A north-row cell (coords.y == its building's own rect.position.y) is
## walkable when `from` is anywhere that ISN'T strictly inside the
## building (the true exterior behind the building, or another cell
## along this same back-wall row), and blocked when `from` is a genuine
## interior cell (inside the rect, with a strictly greater y than the
## back row) — i.e. you can walk along the outside of the back wall, but
## can no longer reach it by walking through the building's own
## interior. Every other wall (front/west/east) keeps the original
## walkable-from-inside rule above, unchanged.
const NO_FROM := Vector2i(-999999, -999999)

func is_walkable(coords: Vector2i, from: Vector2i = NO_FROM) -> bool:
	## Falls back to "M" (blocked) for any coordinate outside the
	## authored map, not "T" — Trees don't block movement anymore, so
	## defaulting to them here would make anywhere off the map's edge
	## walkable by accident.
	var ch: String = tile_chars.get(coords, "M")
	if from != NO_FROM:
		var from_ch: String = tile_chars.get(from, "")
		if from_ch in WALL_MATERIAL_CHARS:
			var from_building: int = _building_index_at(from)
			if from_building != -1:
				var from_rect: Rect2i = buildings[from_building]
				if from.y == from_rect.position.y:
					## Stepping off a NORTH (back) wall tile: blocked only
					## toward the building's own interior (a rect cell
					## strictly south of the back row) — stepping further
					## north (behind the building) or sideways along this
					## same row is allowed. See the is_walkable() doc
					## comment above for the full north-wall exception.
					if from_rect.has_point(coords) and coords.y > from_rect.position.y:
						return false
				elif not from_rect.has_point(coords):
					return false   ## stepping off any other wall tile, out past the building's own footprint — blocked
	if BLOCKED.has(ch):
		if ch in WALL_MATERIAL_CHARS and from != NO_FROM:
			var building_idx: int = _building_index_at(coords)
			if building_idx == -1:
				return false
			var rect: Rect2i = buildings[building_idx]
			if coords.y == rect.position.y:
				## Entering a NORTH (back) wall tile: walkable unless
				## `from` is a genuine interior cell (inside the rect,
				## strictly south of this back row) — i.e. from the
				## exterior behind the building, or along this same row,
				## it's allowed; from inside the building it's blocked.
				if rect.has_point(from) and from.y > rect.position.y:
					return false
			elif not rect.has_point(from):
				return false
		else:
			return false
	if npc_dialogue.has(coords) or petty_magic_trainer_coords.has(coords) or shopkeeper_coords.has(coords) or priest_coords.has(coords):
		return false   ## NPCs also block movement
	if quest_npc_marker_tiles.has(coords):
		return false   ## quest NPCs (e.g. Gotheim's own) block movement too, same as any other NPC — real bug fix, this was never checked before
	if coords == elder_tile:
		return false   ## the Elder blocks movement too
	if current_map_def != null and current_map_def.companion_maker_tile != Vector2i(-1, -1) and coords == current_map_def.companion_maker_tile:
		return false   ## the Party Companion Maker blocks movement too, same as any other NPC
	return true

## Whether this tile is a Tree — walkable, but Player._move_to applies
## a movement-speed penalty when moving into one, per the request.
func is_tree(coords: Vector2i) -> bool:
	return tile_chars.get(coords, "") == "T"

## The Enemy/Monster Difficulty Tier that applies at a given tile —
## checks difficulty_areas first (first bounds match wins), falling
## back to default_difficulty_tier if the tile isn't inside any of
## them.
func get_difficulty_tier_at(tile: Vector2i) -> int:
	for area in difficulty_areas:
		if area.contains_tile(tile):
			return area.tier
	return default_difficulty_tier

## Per the follow-up request: which kind of terrain a tile counts as,
## for the new faction-by-location spawn rules (see TileTypeRules) —
## "countryside" for anywhere outside every defined area, matching
## DifficultyAreaDefinition's own default.
func get_tile_type_at(tile: Vector2i) -> String:
	for area in difficulty_areas:
		if area.contains_tile(tile):
			return area.tile_type
	return "countryside"

## Per the follow-up request: true if this tile falls inside a Safe
## Area — field-encounter spawning is disabled entirely there,
## independent of tier/faction rules.
func is_safe_area_at(tile: Vector2i) -> bool:
	for area in difficulty_areas:
		if area.contains_tile(tile) and area.is_safe_area:
			return true
	return false

## Which named area (if any) a tile falls inside — "" if it's outside
## every defined area. Used for location-based Journal entries; not
## every area necessarily has journal flavor text defined for it (see
## LOCATION_JOURNAL_FLAVOR), so callers should check for that too.
func get_difficulty_tier_area_name_at(tile: Vector2i) -> String:
	for area in difficulty_areas:
		if area.contains_tile(tile):
			return area.area_name
	return ""

## Which monster names a field encounter at this tile should be
## restricted to — the first area (in order) whose bounds contain the
## tile AND which actually defines a monster_pool. Empty means "no
## restriction, use the map's full random pool" — the correct result
## both when the tile isn't inside any themed area, and when it's
## inside a difficulty-only area (like the broad East-of-River
## catch-all) that never restricts monsters at all.
func get_monster_pool_at(tile: Vector2i) -> Array[String]:
	for area in difficulty_areas:
		if area.contains_tile(tile) and not area.monster_pool.is_empty():
			return area.monster_pool
	return []

## Which habitat tag applies at this tile, for location-appropriate
## spawning — the first area (in order) whose bounds contain the tile
## AND which actually defines a habitat. Empty means "no habitat
## preference."
func get_habitat_at(tile: Vector2i) -> String:
	for area in difficulty_areas:
		if area.contains_tile(tile) and area.habitat != "":
			return area.habitat
	return ""

func try_interact(target: Vector2i) -> void:
	## Per the request: what actually connects a specific map tile to
	## a real quest encounter — checked first, ahead of the ordinary
	## generic NPC types, since a quest marker is always the more
	## specific interaction when both could somehow apply to the same
	## tile.
	if quest_npc_marker_tiles.has(target):
		var marker: QuestNPCMapMarker = quest_npc_marker_tiles[target]
		GameState.pending_quest_id = marker.quest_id
		GameState.pending_quest_npc_id = marker.npc_id
		GameState.return_position = player.grid_pos
		get_tree().change_scene_to_file("res://scenes/ScriptedNPCEncounter.tscn")
	elif quest_monster_marker_tiles.has(target):
		var mmarker: QuestMonsterMapMarker = quest_monster_marker_tiles[target]
		## Per the request: once this quest's own monster has already
		## been defeated, the marker no longer triggers a fight at
		## all — the quest only happens once.
		if GameState.player_character.get_quest_monster_defeated(mmarker.quest_id, mmarker.monster_id):
			return
		var qdef: QuestDefinition = load("res://data/quests/%s.tres" % mmarker.quest_id) as QuestDefinition
		var mdef: QuestMonsterDefinition = qdef.find_monster(mmarker.monster_id) if qdef != null else null
		if mdef != null:
			GameState.player_character.setup_quest_monster_encounter(mdef, mmarker.quest_id)
			GameState.return_position = player.grid_pos
			_capture_battle_terrain_snapshot()
			get_tree().change_scene_to_file("res://scenes/FieldEncounter.tscn")
	elif npc_dialogue.has(target):
		_show_dialogue(npc_dialogue[target])
	elif current_map_def != null and current_map_def.companion_maker_tile != Vector2i(-1, -1) and target == current_map_def.companion_maker_tile:
		_open_companion_maker()
	elif petty_magic_trainer_coords.has(target):
		GameState.return_position = player.grid_pos
		get_tree().change_scene_to_file("res://scenes/Hermit.tscn")
	elif shopkeeper_coords.has(target):
		GameState.return_position = player.grid_pos
		get_tree().change_scene_to_file("res://scenes/Shop.tscn")
	elif priest_coords.has(target):
		GameState.return_position = player.grid_pos
		get_tree().change_scene_to_file("res://scenes/Healer.tscn")

func _show_dialogue(text: String) -> void:
	dialogue_label.text = text
	dialogue_label.visible = true
	dialogue_timer = get_tree().create_timer(3.5)
	dialogue_timer.timeout.connect(func() -> void:
		dialogue_label.visible = false
	)

## Builds the bottom-right automatic-roll-log overlay — see
## _roll_log_history's own declaration comment for the full design.
## Built entirely in code (same approach BattleGridView._build_hover_
## tooltip() already uses) and called once from _ready(), after `%UI`
## itself is guaranteed to exist.
func _build_roll_log_overlay() -> void:
	_roll_log_container = Control.new()
	_roll_log_container.name = "RollLogOverlay"
	_roll_log_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_roll_log_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_roll_log_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_roll_log_container.offset_left = -ROLL_LOG_WIDTH
	_roll_log_container.offset_top = -260
	_roll_log_container.offset_right = -12
	_roll_log_container.offset_bottom = -12
	## PASS (not the default STOP) so this corner box never eats a real
	## game click aimed at a tile/marker underneath it — it only needs
	## to see the mouse pass through to show/hide the history panel.
	_roll_log_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_roll_log_container.mouse_entered.connect(func():
		if is_instance_valid(_roll_log_history_panel):
			_roll_log_history_panel.visible = true
	)
	_roll_log_container.mouse_exited.connect(func():
		if is_instance_valid(_roll_log_history_panel):
			_roll_log_history_panel.visible = false
	)
	$UI.add_child(_roll_log_container)

	## The live feed: transient, auto-fading lines, newest at the bottom
	## (a small running log, not a stack of toasts).
	_roll_log_feed = VBoxContainer.new()
	_roll_log_feed.name = "RollLogFeed"
	_roll_log_feed.set_anchors_preset(Control.PRESET_FULL_RECT)
	_roll_log_feed.alignment = BoxContainer.ALIGNMENT_END
	_roll_log_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roll_log_container.add_child(_roll_log_feed)

	## The full history — hidden until the corner is hovered (see the
	## mouse_entered/exited wiring above). A real ScrollContainer since a
	## long session's worth of rolls won't all fit in 260px.
	_roll_log_history_panel = PanelContainer.new()
	_roll_log_history_panel.name = "RollLogHistoryPanel"
	_roll_log_history_panel.visible = false
	_roll_log_history_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roll_log_history_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.82)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.55, 0.5, 0.4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_roll_log_history_panel.add_theme_stylebox_override("panel", style)
	_roll_log_history_scroll = ScrollContainer.new()
	_roll_log_history_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_roll_log_history_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_roll_log_history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_roll_log_history_panel.add_child(_roll_log_history_scroll)
	_roll_log_history_list = VBoxContainer.new()
	_roll_log_history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roll_log_history_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	## Per the request ("have the history log align to the bottom of the
	## window"): when there are fewer entries than fit the panel, they
	## should sit flush with the bottom (right where the live feed and
	## the newest roll are) rather than stranded at the top with empty
	## space below. ScrollContainer stretches its child to fill its own
	## size whenever the content is shorter than the panel (see
	## fit_child_in_rect in Godot's ScrollContainer), so this VBox is
	## already given the full panel height to work with -- ALIGNMENT_END
	## then bottom-anchors its rows within that space. Once there are
	## enough rows to overflow, this has no visible effect and normal
	## scrolling takes over.
	_roll_log_history_list.alignment = BoxContainer.ALIGNMENT_END
	_roll_log_history_scroll.add_child(_roll_log_history_list)
	_roll_log_container.add_child(_roll_log_history_panel)

## The one funnel every automatic Test on this screen logs through (see
## _tr_skill()/_tr_char()/_tr_party() below) — appends to the permanent
## history and pushes one fading line onto the live feed. `character`/
## `result` both being non-null is the only requirement, so this reads
## fine for a monster's own roll (e.g. the hidden ambush-detection
## Stealth Test) just as well as a party member's.
##
## `name_override`: per the request ("hide monster names with ??? in
## the roll log"), _roll_ambush_detection() passes "???" here for an
## unidentified monster's own Stealth roll instead of its real
## character_name -- everything else leaves this blank and gets the
## normal character.character_name.
##
## Per the follow-up request ("why is the last entry SL wrong, 16 vs 80
## is SL +7" -- it wasn't wrong, Elrohir just had a Talent adding +2 SL
## that the line never showed): when result.success_levels includes a
## Talent bonus on top of the roll's own raw SL (base_success_levels !=
## success_levels -- see TestResult's own comment), show both parts
## instead of just the opaque total, e.g. "(SL +7+2)" rather than the
## same math silently landing on "(SL +9)" with nothing to explain it.
func _log_auto_roll(character: Character, skill_name: String, result: TestResolver.TestResult, name_override: String = "") -> void:
	if character == null or result == null:
		return
	var display_name := name_override if name_override != "" else character.character_name
	var sl_bonus := result.success_levels - result.base_success_levels
	var sl_text := ("%+d%+d" % [result.base_success_levels, sl_bonus]) if sl_bonus != 0 else ("%+d" % result.success_levels)
	var line := "%s - %s %d vs %d (SL %s)" % [display_name, skill_name, result.roll, result.target, sl_text]
	_roll_log_history.append(line)
	if _roll_log_history.size() > ROLL_LOG_MAX_HISTORY:
		_roll_log_history.pop_front()
	_roll_log_push_feed_line(line, result.success)
	_roll_log_refresh_history_panel()

## Adds one line to the live feed and schedules its own fade-and-free —
## per the request, each line fades out independently ROLL_LOG_FADE_
## AFTER_SEC after IT was added, not on a shared/reset timer for the
## whole feed.
func _roll_log_push_feed_line(text: String, success: bool) -> void:
	if not is_instance_valid(_roll_log_feed):
		return
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.55, 0.92, 0.55) if success else Color(0.92, 0.5, 0.45))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_font_size_override("font_size", ROLL_LOG_FONT_SIZE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	## See ROLL_LOG_WIDTH's own comment — without this, a long line's
	## full unwrapped width becomes this Label's (and its VBoxContainer
	## parent's) minimum size, silently pushing the whole overlay wider
	## than intended and off the right edge of the screen.
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roll_log_feed.add_child(label)
	while _roll_log_feed.get_child_count() > ROLL_LOG_MAX_VISIBLE_LINES:
		_roll_log_feed.get_child(0).queue_free()
	var fade_timer := get_tree().create_timer(ROLL_LOG_FADE_AFTER_SEC)
	fade_timer.timeout.connect(func():
		if not is_instance_valid(label):
			return
		var tw := create_tween()
		tw.tween_property(label, "modulate:a", 0.0, ROLL_LOG_FADE_DURATION_SEC)
		tw.finished.connect(func():
			if is_instance_valid(label):
				label.queue_free()
		)
	)

## Rebuilds the hover history panel from _roll_log_history. Per the
## follow-up request ("invert the history log so its oriented the same
## as the actual logs are bottom up"): oldest entry at the top, newest
## at the bottom — same chronological order the live feed itself
## already reads in (a new roll's Label is add_child()'d, i.e. appended
## at the bottom, in _roll_log_push_feed_line()) — this used to build
## newest-first (top), which read backwards compared to the feed right
## above it. Scrolled to the bottom afterward so the newest entry (the
## one that just triggered this rebuild) is what's actually in view
## without the viewer having to scroll down themselves.
func _roll_log_refresh_history_panel() -> void:
	if not is_instance_valid(_roll_log_history_list):
		return
	## Freed immediately (not queue_free()) so the list's own child count
	## is always exactly right the instant this returns — this can fire
	## more than once in the very same frame (e.g. an ambush check logs
	## both a Perception AND a Stealth roll from one function), and a
	## deferred free would otherwise let old and new rows briefly coexist.
	for child in _roll_log_history_list.get_children():
		_roll_log_history_list.remove_child(child)
		child.free()
	for line in _roll_log_history:
		var lbl := Label.new()
		lbl.text = line
		lbl.add_theme_font_size_override("font_size", ROLL_LOG_FONT_SIZE)
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		## See ROLL_LOG_WIDTH's own comment on _roll_log_push_feed_line()'s
		## matching fix — same overflow risk here, inside the scrollable
		## history list.
		lbl.clip_text = true
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_roll_log_history_list.add_child(lbl)
	if is_instance_valid(_roll_log_history_scroll):
		## The new rows' real size isn't known until layout runs on the
		## next frame — set_deferred so this applies AFTER that layout
		## pass settles the scrollable range, not the stale one from
		## before this rebuild. ScrollContainer clamps scroll_vertical to
		## its own real max automatically, so an oversized value here
		## just always lands exactly at the bottom.
		_roll_log_history_scroll.set_deferred("scroll_vertical", 999999)

## --- Thin logging wrappers around TestResolver ------------------------
## Per the request ("show all automatic rolls which are happening while
## walking around"): every direct TestResolver.resolve_skill_test()/
## resolve_characteristic_test()/resolve_party_skill_test() call in this
## file is routed through one of these three instead, so the roll log
## overlay stays a single addition here rather than something every
## individual call site has to remember to also do. Field_encounter_
## screen.gd's own combat rolls deliberately do NOT go through these —
## combat already shows every roll as a real dice card, and this overlay
## is specifically the "while walking around" one the request asked for.
func _tr_skill(c: Character, skill_def: SkillDefinition, specialisation: String = "", modifier: int = 0,
		modifier_breakdown: Array = [], forced_roll: int = -1, extra_sl_breakdown: Array = [], extra_scopes: Array = []) -> TestResolver.TestResult:
	var result := TestResolver.resolve_skill_test(c, skill_def, specialisation, modifier, modifier_breakdown, forced_roll, extra_sl_breakdown, extra_scopes)
	_log_auto_roll(c, skill_def.display_name(specialisation), result)
	return result

func _tr_char(c: Character, characteristic_key: String, modifier: int = 0, extra_scopes: Array = [], modifier_breakdown: Array = []) -> TestResolver.TestResult:
	var result := TestResolver.resolve_characteristic_test(c, characteristic_key, modifier, extra_scopes, modifier_breakdown)
	_log_auto_roll(c, characteristic_key.capitalize(), result)
	return result

## resolve_party_skill_test() already rolls once per party member
## internally and returns only the best — logging that one winning
## roll (rather than reaching into TestResolver to log every member's
## own attempt individually) keeps a party-wide check to a single log
## line, matching "keep it simple."
func _tr_party(party: Array[Character], skill_def: SkillDefinition, specialisation: String = "", modifier: int = 0) -> Dictionary:
	var r := TestResolver.resolve_party_skill_test(party, skill_def, specialisation, modifier)
	if r.get("result") != null and r.get("roller") != null:
		_log_auto_roll(r["roller"], skill_def.display_name(specialisation), r["result"])
	return r

## Per the request: cycles off -> on -> low -> off (skipping "low" for
## a source with no dedicated low-flame radius, e.g. Candle/Davrich
## Lamp) — always available regardless of time of day or location, per
## the request's own "player should be able to turn it on/off... if
## they want to." Whether the toggle actually shows anything on screen
## is a completely separate question, decided every frame by
## _light_source_effective() — so lighting a lantern at high noon
## outdoors is allowed (and remembered) but simply has no visible
## effect (or fuel cost) until it's actually dark enough to matter.
func _toggle_light_source() -> void:
	var pc: Character = GameState.player_character
	if pc == null:
		return
	var item := pc.get_equipped_light_item()
	if item == null:
		## Per the request ("allow the light spell to be used on the
		## overworld map the same way that lamp is used with the L
		## button"): with no light ITEM equipped at all, L falls
		## through to the Light petty spell instead, for a caster who
		## knows it — see _toggle_light_spell()'s own comment for the
		## bright/dim/off cycle this drives.
		if pc.known_spells.has("Light"):
			_toggle_light_spell(pc)
		else:
			_show_dialogue("You aren't carrying a light source.")
		return
	if pc.light_mode == "off":
		if item.light_requires_oil and pc.light_fuel_minutes <= 0.0:
			if pc.inventory.has("Lamp Oil"):
				pc.inventory.erase("Lamp Oil")
				pc.light_fuel_minutes = Character.LAMP_OIL_MINUTES
			else:
				_show_dialogue("No lamp oil left to light the %s." % item.item_name)
				return
		## Per the request ("candles too but without the Oil/fuel
		## component, candles last 4hrs each"): a self-fuel source has
		## no separate fuel item to check — it's the equipped unit
		## itself that runs out (see Character.tick_light_fuel()) — so
		## the only thing to verify here is that there's still at least
		## one actual unit in inventory to light in the first place.
		elif item.light_self_fuel_minutes > 0.0 and pc.light_fuel_minutes <= 0.0:
			if pc.inventory.has(item.item_name):
				pc.light_fuel_minutes = item.light_self_fuel_minutes
			else:
				_show_dialogue("You don't have any %s left." % item.item_name)
				return
		pc.light_mode = "on"
		_show_dialogue("%s lit." % item.item_name)
	elif pc.light_mode == "on":
		if item.light_radius_tiles_low > 0:
			pc.light_mode = "low"
			_show_dialogue("%s turned down to a low flame." % item.item_name)
		else:
			pc.light_mode = "off"
			_show_dialogue("%s extinguished." % item.item_name)
	else:   ## "low"
		pc.light_mode = "off"
		_show_dialogue("%s extinguished." % item.item_name)
	_apply_light_source_overlay()

## Per the request ("allow the light spell to be used on the overworld
## map the same way that lamp is used with the L button... use spell
## duration as normal and recast automatically if duration expires, it
## will just work forever"): mirrors _toggle_light_source()'s own
## off -> on -> low -> off item cycle one step for one step, just for a
## caster with the Light petty spell known and no light item equipped
## (see the call site in _toggle_light_source() above):
##   - not currently active (a fresh caster, or a previous cast that was
##     manually let expire below) -> casts it fresh: full Willpower-
##     minutes duration, always starts "bright" — same "recasting always
##     refreshes rather than stacks" rule field_encounter_screen.gd's
##     own combat cast already follows.
##   - "bright" -> "dim", mirroring on -> low.
##   - "dim" -> ends it outright (duration cleared to 0), mirroring
##     low -> off. Deliberately NOT the combat-only "out" state (which
##     keeps secretly ticking while hooded, see light_spell_mode's own
##     comment) — there's no reason for that subtlety out here, and a
##     flat "off" keeps this exactly as simple as the lamp toggle it's
##     mirroring.
## Duration is then spent by tick_light_spell_duration(), called from
## _on_player_moved() below for every party member regardless of who's
## currently controlled — the spell belongs to whichever character it
## was cast on, not to whoever Q/E happens to have selected afterward.
## If a fight starts while this is active (bright or dim), Character.
## light_spell_rounds_remaining/light_spell_mode carry straight into
## FieldEncounter untouched (nothing in _start_encounter() resets
## them) — so combat simply picks up with whatever real time was left,
## per the explicit request.
func _toggle_light_spell(pc: Character) -> void:
	if pc.light_spell_rounds_remaining <= 0:
		pc.light_spell_rounds_remaining = max(pc.get_effective_characteristic_value("willpower"), 1)
		pc.light_spell_mode = "bright"
		pc.light_spell_minutes_accum = 0.0
		_show_dialogue("%s casts Light." % pc.character_name)
	elif pc.light_spell_mode == "bright":
		pc.light_spell_mode = "dim"
		_show_dialogue("Light dimmed.")
	else:
		pc.light_spell_rounds_remaining = 0
		pc.light_spell_mode = "bright"
		pc.light_spell_minutes_accum = 0.0
		_show_dialogue("The Light spell fades out.")
	_apply_light_source_overlay()

## Per the request: fuel only burns while the light is actually doing
## something (_light_source_effective() — dark out, or a dark_location
## map), never while switched "on" in broad daylight with no visible
## effect. Local-map tile-stepping only (see _on_player_moved()) —
## deliberately NOT World Map travel or Camp/Sleep resting, same scope
## as the rest of this system, which is about carrying a light while
## exploring a local map.
##
## Per the follow-up request ("if multiple character have light
## equipped use only one at a time in character order... don't consume
## the other one, and switch to the backup automatically"): burns fuel
## for the party's one shared light-bearer (_party_light_bearer() —
## first party-order member with a genuinely active light), never for
## GameState.player_character specifically. A second member with their
## own light left "on" behind the bearer simply never gets ticked while
## the bearer is still lit — its fuel stays exactly where it was. Once
## the bearer's own tick_light_fuel() call above extinguishes them
## (out of fuel/stock), _party_light_bearer() on the very next tile
## step naturally resolves to that next member instead — no separate
## "switch to backup" step needed here.
func _tick_light_source_fuel() -> void:
	if not _light_source_effective():
		return
	var pc: Character = _party_light_bearer()
	if pc == null:
		return
	## Captured before tick_light_fuel() runs: a self-fuel source with
	## nothing left in stock clears equipped_weapon/equipped_offhand as
	## part of that same call (see Character.tick_light_fuel()), so
	## get_equipped_light_item() would no longer find it afterward.
	var pre_item := pc.get_equipped_light_item()
	var requires_oil: bool = pre_item != null and pre_item.light_requires_oil
	if pc.tick_light_fuel(GameState.minutes_per_tile_fraction()):
		var item_name: String = pre_item.item_name if pre_item != null else "light source"
		var bearer_name: String = pc.character_name
		if requires_oil:
			_show_dialogue("%s's %s has run out of oil!" % [bearer_name, item_name])
		else:
			_show_dialogue("%s's %s has burned out!" % [bearer_name, item_name])

## Per the request ("use spell duration as normal and recast
## automatically if duration expires, it will just work forever"):
## unlike _tick_light_source_fuel() above, this deliberately ticks
## EVERY party member's own Light spell (not just whoever the current
## _party_light_bearer() resolves to, and not gated on
## _light_source_effective()) — the spell's Willpower-minutes duration
## is a real Test-book Duration, not a conserved fuel resource, so it
## keeps genuinely elapsing in broad daylight exactly like it would
## underground, and it belongs to whichever character actually cast it
## regardless of who Q/E currently has selected. Character.tick_light_
## spell_duration() is itself a no-op for anyone with no active cast,
## so this is cheap to just run down the whole party every step.
func _tick_light_spell_duration() -> void:
	var minutes := GameState.minutes_per_tile_fraction()
	for c in GameState.party:
		if c != null:
			c.tick_light_spell_duration(minutes)

func _on_player_moved(new_tile: Vector2i) -> void:
	if current_map_def != null and current_map_def.is_world_map:
		_advance_world_map_step_time(new_tile)
	else:
		GameState.advance_time_one_step()
		_tick_light_source_fuel()
		_tick_light_spell_duration()
	_check_ambush_marker_distance()
	_check_social_marker_distance()
	_check_location_journal(new_tile)
	_check_standing_trigger(new_tile)
	_update_roof_visibility(new_tile)
	## Keep the persistent fallback position current on every single
	## step, not just when the player explicitly opens Camp. Real bug
	## this fixes: camp_position previously only updated inside
	## _open_camp(), so a player who quit, switched characters, or
	## otherwise left the game without ever explicitly camping had a
	## stale (or default, Vector2i(-1,-1)) camp_position saved —
	## _restore_return_position()'s fallback then dropped them back at
	## that old spot (or the map's default spawn) instead of wherever
	## they'd actually last been standing, since return_position itself
	## is session-only and never survives a real app relaunch.
	## Per the "movement feels jerky" request: updating this in-memory
	## field is free, but it used to be followed by a full
	## GameState.autosave() — a synchronous JSON-serialize-the-whole-
	## party-and-write-to-disk call — on THIS EXACT tile, every single
	## tile, for the entire time the player is walking. That's a disk
	## write roughly every MOVE_DURATION (0.14s, see
	## player_controller.gd) for as long as a direction key stays held,
	## landing right in the Tween's own completion callback — precisely
	## the moment the game would otherwise start the next tile's tween
	## — so any I/O latency spike (a slow disk, an antivirus scan, a
	## networked/cloud-synced save folder, even routine OS scheduling
	## jitter) reads as a visible stutter in the middle of normal
	## walking. Root-caused by checking what actually runs inside this
	## callback rather than assuming the movement/tween code itself was
	## at fault. The disk write is no longer here — see the
	## `autosave_timer` in _ready() (now on a much shorter interval, see
	## its own comment) plus the many explicit GameState.autosave()
	## calls already scattered across every real checkpoint (shop
	## purchases, camp, healer, quest/encounter triggers, menu close,
	## switching characters, quitting) for what keeps a save genuinely
	## current without hitching every step.
	GameState.player_character.camp_position = new_tile
	_update_hud()
	var ch: String = tile_chars.get(new_tile, ".")
	GameState.tiles_since_last_encounter += 1
	if ENCOUNTER_TILES.has(ch) and GameState.tiles_since_last_encounter >= GameState.ENCOUNTER_COOLDOWN_TILES and randf() < ENCOUNTER_CHANCE:
		current_path.clear()   ## a fight interrupts any click-to-move journey in progress
		GameState.tiles_since_last_encounter = 0
		_trigger_encounter()
		return
	_advance_path()

## Per the request: a genuine chance this "encounter" isn't a fight at
## all — a narrative, social exchange instead. Per the follow-up
## correction, this no longer launches SocialEncounter.tscn directly:
## it spawns a visible "?" marker (no detection roll at all, unlike
## the ambush "!" marker below) that the player can choose to approach
## or ignore. Checked first, before any of the combat/ambush-detection
## machinery further down even runs, since a social encounter never
## goes through Tier/habitat-based monster selection at all.
const SOCIAL_ENCOUNTER_CHANCE := 0.3

## Per the source material (p.4): "The Frenzied Mob" — as many
## villagers as there are party members, plus one extra. Only ever
## fires once per real playthrough (tracked directly on the quest's
## own state, the same "only happens once" rule already applied to
## the Jabberslythe), and only if the quest is genuinely still Active
## — a player who somehow re-enters after the quest already concluded
## shouldn't be ambushed by a mob that's already been dealt with.
## Per the request: more narrative fade-in text as the quest
## progresses — this is the "after the maddened villagers" moment,
## the source's own full read-aloud passage as the Characters
## actually enter the devastated village, shown once, right after the
## mob fight outside has already been dealt with (or if it never
## triggered at all, e.g. an existing save mid-quest).
func _show_gotheim_entering_narrative() -> void:
	var q := GameState.player_character.find_quest("gotheim")
	if q.is_empty() or bool(q.get("entering_narrative_shown", false)):
		return
	if not bool(q.get("mob_encountered", false)):
		return
	q["entering_narrative_shown"] = true
	_show_info_popup("Entering Gotheim", "Through the shattered gates is a scene of shocking devastation. The village has been subjected to an attack of sudden, intense violence. Many of the small cottages that stood here have been pulled apart, reduced to piles of wood and reed. Tongues of flame rise from some of these piles. The palisade that rings the village has been torn apart in places, the heavy stakes reduced to matchwood. Corpses are strewn about like wheatsheafs after harvest, and the heavy impressions of huge, four-toed feet lead a winding path through the carnage. To your left a tall coaching inn still stands undamaged. Raised voices echo from within. To your right smoke rises from the interior of a small village forge, and the tall brass dome of a temple of Sigmar proudly dominates the skyline before you.")

func _trigger_gotheim_mob_encounter() -> void:
	var q := GameState.player_character.find_quest("gotheim")
	if q.is_empty() or q.get("status", "Active") != "Active" or q.get("mob_encountered", false):
		return
	q["mob_encountered"] = true
	var mob_size: int = GameState.party.size() + 1
	var names: Array[String] = []
	for i in range(mob_size):
		names.append("Maddened Villager")
	GameState.return_position = player.grid_pos
	GameState.pending_encounter_monster_names = names
	GameState.pending_encounter_is_player_ambush = false
	current_path.clear()
	encounter_label_text.text = "Before you even reach the village, you hear it: something crashing through the trees to the west of the road, whooping and screaming threats. The frenzied mob bursts from the treeline!"
	encounter_label.visible = true
	await get_tree().create_timer(1.8).timeout
	_capture_battle_terrain_snapshot()
	get_tree().change_scene_to_file("res://scenes/FieldEncounter.tscn")

func _trigger_encounter() -> void:
	## Per the request: a map can disable random encounters entirely —
	## Gotheim, specifically, where every fight is meant to be a
	## deliberate quest beat rather than a random roll. Checked first,
	## same priority as the existing Safe Area guard below.
	if current_map_def != null and not current_map_def.allow_random_encounters:
		return

	## Per the follow-up request: a Safe Area disables field-encounter
	## spawning entirely, independent of everything else below —
	## checked before even the social-encounter roll, since "safe"
	## means safe, not just "less likely to run into something."
	if is_safe_area_at(player.grid_pos):
		return

	if GameData.social_encounter_db != null and not GameData.social_encounter_db.encounters.is_empty() and randf() < SOCIAL_ENCOUNTER_CHANCE:
		_spawn_social_marker()
		return

	GameState.current_field_difficulty_tier = get_difficulty_tier_at(player.grid_pos)
	GameState.current_field_monster_pool = get_monster_pool_at(player.grid_pos)
	GameState.current_field_habitat = get_habitat_at(player.grid_pos)
	var tile_type := get_tile_type_at(player.grid_pos)

	## The group is selected ONCE, here — both the detection roll and
	## (whichever way it goes) the eventual fight itself use this exact
	## same group, never a freshly-rolled one.
	var group: Array[MonsterDefinition] = EncounterGroupBuilder.select_group(GameState.current_field_monster_pool, GameState.current_field_difficulty_tier, GameState.current_field_habitat, tile_type)
	if group.is_empty():
		return
	var names: Array[String] = []
	for mdef in group:
		names.append(mdef.monster_name)

	if _roll_ambush_detection(group):
		_spawn_ambush_marker(names)
		return

	GameState.return_position = player.grid_pos
	GameState.pending_encounter_monster_names = names
	GameState.pending_encounter_is_player_ambush = false
	encounter_label_text.text = EncounterNarrator.random_line()
	encounter_label.visible = true
	await get_tree().create_timer(1.4).timeout
	_capture_battle_terrain_snapshot()
	get_tree().change_scene_to_file("res://scenes/FieldEncounter.tscn")

## Hidden Perception (player) vs Stealth (Rural) (the lead monster in
## the group) opposed Test, per the request — never shown to the
## player either way, since the whole point is that they don't
## necessarily know an encounter was even possible. Built from the
## group's own first monster (with the same Tier bonus a real fight
## against it would apply, so the roll reflects the actual difficulty
## rather than a flat, un-scaled baseline) rather than every monster
## in the group — one representative Stealth check for "did the group
## keep hidden," not a separate roll per creature.
func _roll_ambush_detection(group: Array[MonsterDefinition]) -> bool:
	var lead_def: MonsterDefinition = group[0]
	var lead: Character
	if lead_def.uses_career_template:
		lead = BanditGenerator.build_bandit(lead_def.monster_name, GameState.current_field_difficulty_tier)
	else:
		lead = lead_def.to_character()
		DifficultyTiers.apply_tier_bonus(lead, GameState.current_field_difficulty_tier)

	var perception_def: SkillDefinition = GameData.skill_db.find_by_name("Perception")
	var stealth_def: SkillDefinition = GameData.skill_db.find_by_name("Stealth")
	if perception_def == null or stealth_def == null:
		return false

	## Per the follow-up request: Large+ creatures (Dire Wolf, Troll,
	## Ogre, Giant, Rat Ogre) are easier to spot on the overworld —
	## +20 to the player's own Perception roll here — matching that
	## something genuinely that big shouldn't sneak up as easily as a
	## Giant Rat would. Checked against the whole group, not just the
	## lead, since a Large+ creature grouped alongside something else
	## should still be this much easier to notice.
	var perception_bonus := 0
	for m in group:
		if not m.default_spawn_eligible:
			perception_bonus = 20
			break

	var player_test := _tr_skill(GameState.player_character, perception_def, "", perception_bonus)
	## Per the request ("hide monster names with ??? in the roll log"):
	## an unidentified monster's Stealth roll can't be logged under its
	## real name yet -- whether the party has actually identified it
	## depends on the outcome of THIS check, which isn't known until
	## after everyone's Perception is rolled below. So resolve it
	## directly (bypassing the _tr_skill wrapper, which would log it
	## immediately) and log it manually once the outcome is in.
	var monster_name := lead.character_name
	var already_identified: bool = GameState.identified_monster_names.has(monster_name)
	var enemy_test: TestResolver.TestResult
	if already_identified:
		enemy_test = _tr_skill(lead, stealth_def, "Rural")
	else:
		enemy_test = TestResolver.resolve_skill_test(lead, stealth_def, "Rural")
	## Per the request: automatic Tests against the whole party are
	## genuinely carried out by every present member, not just
	## whoever's currently active — a party of 4 pairs of eyes is
	## more likely to spot danger than 1. Everyone present rolls their
	## own real Perception; the party succeeds if ANY of them beats
	## the enemy's own shared Stealth roll (rolled once — the enemy's
	## concealment effort doesn't change per who's looking for it).
	var best_sl: int = player_test.success_levels
	for member in GameState.party:
		if member == GameState.player_character:
			continue   ## already rolled above; avoid rolling the same member twice
		var member_test := _tr_skill(member, perception_def, "", perception_bonus)
		if member_test.success_levels > best_sl:
			best_sl = member_test.success_levels
	## Opposed Test convention: compare Success Levels; the defender
	## (the enemy trying to stay hidden) wins ties, since a failure to
	## clearly beat a hidden opponent's own Stealth isn't a detection.
	var spotted := best_sl > enemy_test.success_levels
	if not already_identified:
		## Spotting it IS identifying it — once the party has actually
		## seen the thing, later encounters with the same monster type
		## log its real name from then on. Stayed hidden this time?
		## Still logged (per "show all automatic rolls"), just under
		## "???" since the party never got a look at it.
		if spotted:
			GameState.identified_monster_names[monster_name] = true
		_log_auto_roll(lead, stealth_def.display_name("Rural"), enemy_test, "" if spotted else "???")
	return spotted

## Per the request ("when switching character switch the actively
## displayed character on screen to the one that is selected"): the
## on-map `player` Node2D's own sprite already has a real per-class
## texture swap (player_controller.gd's _apply_class_sprite(), keyed
## off GameState.player_character.career.career_class) — it just only
## ever ran once, at _ready(), since nothing switched the active party
## member yet when it was written. Every place that changes
## active_party_index (Q/E cycling, clicking a party panel) now calls
## this right alongside it, so the token walking around the map
## visually becomes whichever character is now actually being
## controlled, not just the HUD's own name/HP highlight.
func _apply_active_character_sprite() -> void:
	if player != null and player.has_method("_apply_class_sprite"):
		player._apply_class_sprite()

func _update_hud() -> void:
	var c := GameState.player_character
	if c:
		## Per the request: a hint on the World Map specifically —
		## normal walking hints don't apply there anymore (WASD/click-
		## to-move are both disabled), and Esc/Space stopping a journey
		## in progress is a genuinely new thing worth calling out.
		var party_hint := "  [Q/E: switch character]" if GameState.party.size() > 1 else ""
		if is_world_map_active():
			hud_label.text = "%s — Right-click a destination to Travel.%s" % [c.character_name, party_hint]
		else:
			hud_label.text = "%s — WASD to move, double-click to move there, right-click to interact%s" % [c.character_name, party_hint]
	_update_info_bar()
	_update_night_overlay()
	_update_shadow_angles()
	## Per the request: the active map's own coordinates, always
	## visible bottom-left while on any map.
	%CoordsLabel.text = "(%d, %d)" % [player.grid_pos.x, player.grid_pos.y]

## Populates the top info bar: HP text/bar (colour-coded), a portrait
## that swaps at each 25% Wounds threshold, XP, coin, and the clock.
func _update_info_bar() -> void:
	var c := GameState.player_character
	if c == null:
		return

	_update_party_panels()

	xp_label.text = "XP: %d" % c.experience_total
	gold_label.text = "%d GC %d SS %d BP" % [c.gold_crowns, c.silver_shillings, c.brass_pennies]

	var suffix := " 🌙" if GameState.get_night_darkness() > 0.05 else ""
	time_label.text = GameState.get_time_string() + suffix
	date_label.text = GameState.get_date_string()
	_update_quest_tracker(c)

## Per the request: portrait + HP split into up to 4 party panels, one
## per real party member — rebuilt only when the party's own size
## actually changes (adding/removing a member, or loading a save),
## otherwise just refreshed in place, since this runs on every single
## HUD update. The currently active member (whichever Q/E cycling
## last landed on) gets a real visible highlight so it's always clear
## who's actually being controlled.
func _update_party_panels() -> void:
	if party_panel_row.get_child_count() != GameState.party.size():
		## Real bug fix: queue_free() alone is deferred — the old
		## children were still counted (and still occupying their old
		## indices) immediately afterward, since removal doesn't
		## actually happen until the next idle frame. remove_child()
		## takes effect synchronously, so the child list is genuinely
		## accurate right away for the add_child() calls below.
		for child in party_panel_row.get_children():
			party_panel_row.remove_child(child)
			child.queue_free()
		for i in range(GameState.party.size()):
			party_panel_row.add_child(_build_party_panel(i))
	for i in range(GameState.party.size()):
		_refresh_party_panel(party_panel_row.get_child(i), GameState.party[i], i == GameState.active_party_index)

## One party member's own mini panel: a small portrait, HP text, and
## an HP bar, wrapped in a PanelContainer so the active-member
## highlight (a real visible border) has something to draw onto.
## Clicking a panel switches to that member directly, alongside the
## real Q/E cycling — a natural, low-risk extra rather than the only
## way to switch.
## Per the follow-up request ("Make the char icon box about 50% longer"):
## 96x44 -> 144x44 (width x1.5, height unchanged). The HP column (name
## label + HP bar) gets essentially the whole extra width — 96, the
## full space actually left over after the portrait/separation/panel
## margins at 144 wide — rather than a smaller number that still left
## most short/medium names shrinking below their natural size for no
## reason (a fixed 1.5x-of-the-old-56 figure undershot the real
## available room once PressStart2P's per-character width was
## accounted for).
const PARTY_PANEL_SIZE := Vector2(144, 44)
const PARTY_PANEL_HP_COLUMN_WIDTH := 96
## Per the follow-up request ("try dynamically resize the char name to
## fit (but not make it too small)"): the font-size range
## _fit_party_name_label() searches — 10 is the box's original size
## (used whenever a name already fits at full size), 7 is the floor
## it won't shrink past even if the name still doesn't quite fit at
## that size (accepting a little clipping there — see panel's own
## clip_contents — rather than shrinking to the point of being
## unreadable).
const PARTY_NAME_MAX_FONT_SIZE := 10
const PARTY_NAME_MIN_FONT_SIZE := 7

func _build_party_panel(index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "PartyPanel%d" % index
	panel.custom_minimum_size = PARTY_PANEL_SIZE
	## Per the earlier follow-up request ("keep the World map character
	## icon boxes a uniform size, ie dont let them grow"):
	## custom_minimum_size alone is only a FLOOR — a long character name
	## could still push this panel wider than intended, since Godot
	## containers happily grow a child past its stated minimum to fit
	## that child's own content. clip_contents makes this size a genuine
	## ceiling too: anything that would overflow it (in practice, only
	## ever an extreme name at the font-size floor — see
	## _fit_party_name_label()) gets visually clipped instead of growing
	## the panel.
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			GameState.active_party_index = index
			_apply_active_character_sprite()
			_update_party_panels()
	)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	## Per the follow-up request ("place the fuel bar on the character
	## icon holding it"): the portrait now sits inside a small fixed-
	## size wrapper so a LanternFuelIcon can be layered on top of it as
	## a corner overlay, rather than living beside it in the row.
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
	## Per the request ("use the new portraits in all Icon"): the old
	## 40x40 wound-tier art was square, so plain STRETCH_SCALE never
	## distorted it. The new Career portraits aren't square (each keeps
	## its own source aspect ratio), so this box now crops-to-fill
	## (KEEP_ASPECT_COVERED) instead of stretching, same treatment as
	## the portrait columns in camp_screen.gd/tavern_screen.gd/
	## field_encounter_screen.gd.
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_stack.add_child(portrait)

	## Bottom-right corner overlay — small enough to stay out of the
	## way of the portrait art itself, big enough to actually read as a
	## lantern. Hidden by default; _refresh_party_panel() below only
	## shows it for a member who actually has an oil-requiring light
	## source (Lantern, Storm Lantern) equipped.
	var lantern_icon := LanternFuelIcon.new()
	lantern_icon.name = "LanternFuelIcon"
	lantern_icon.size = Vector2(13, 16)
	lantern_icon.position = Vector2(32 - 13, 32 - 16)
	lantern_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lantern_icon.visible = false
	portrait_stack.add_child(lantern_icon)

	var hp_box := VBoxContainer.new()
	hp_box.name = "HPBox"
	hp_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_box.add_theme_constant_override("separation", 2)
	row.add_child(hp_box)

	## Per the follow-up request: this holds ONLY the character's name —
	## the HP figure moved onto the bar itself below (see wound_lbl) to
	## save space. Per the latest follow-up ("try dynamically resize the
	## char name to fit"), a long name now shrinks its OWN font size to
	## fit PARTY_PANEL_HP_COLUMN_WIDTH instead of clipping/ellipsis-
	## truncating — see _fit_party_name_label(), called from
	## _refresh_party_panel() every time the name might have changed.
	var hp_label_node := Label.new()
	hp_label_node.name = "HPLabel"
	hp_label_node.add_theme_font_size_override("font_size", PARTY_NAME_MAX_FONT_SIZE)
	hp_label_node.custom_minimum_size = Vector2(PARTY_PANEL_HP_COLUMN_WIDTH, 0)
	hp_label_node.clip_text = true   ## safety net only — _fit_party_name_label() is what actually keeps text from needing this in practice
	hp_label_node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hp_box.add_child(hp_label_node)

	var hp_bar_node := ProgressBar.new()
	hp_bar_node.name = "HPBar"
	hp_bar_node.custom_minimum_size = Vector2(PARTY_PANEL_HP_COLUMN_WIDTH, 10)
	hp_bar_node.show_percentage = false
	hp_box.add_child(hp_bar_node)

	## Per the follow-up request ("move the HP values inside the HP bar
	## itself to save space"): same "text layered directly on the bar"
	## pattern the combat screen's own Attacker/Defender HP bars already
	## use (see field_encounter_screen.gd's wound_lbl) — added as the
	## ProgressBar's own child rather than a sibling, so it sits
	## centered right on top of the fill with no extra layout node
	## needed. Outline keeps it legible over both the green and red
	## fill colours.
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

## Per the request ("try dynamically resize the char name to fit (but
## not make it too small)"): picks the largest font size in
## [PARTY_NAME_MIN_FONT_SIZE, PARTY_NAME_MAX_FONT_SIZE] whose rendered
## width still fits inside `max_width`, rather than always using the
## max size and clipping/ellipsis-truncating whatever doesn't fit
## (label.clip_text/text_overrun_behavior stay set as a pure safety
## net for the rare name that still doesn't fit even at the size
## floor). Measures with the label's own actual theme font, so this
## stays correct if the theme's font ever changes.
func _fit_party_name_label(label: Label, text: String, max_width: float) -> void:
	label.text = text
	var font: Font = label.get_theme_font("font")
	if font == null:
		label.add_theme_font_size_override("font_size", PARTY_NAME_MAX_FONT_SIZE)
		return
	var chosen_size := PARTY_NAME_MIN_FONT_SIZE
	for size in range(PARTY_NAME_MAX_FONT_SIZE, PARTY_NAME_MIN_FONT_SIZE - 1, -1):
		var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if text_width <= max_width:
			chosen_size = size
			break
	label.add_theme_font_size_override("font_size", chosen_size)

func _refresh_party_panel(panel: Node, c: Character, is_active: bool) -> void:
	var row: HBoxContainer = panel.get_node("Row")
	var portrait: TextureRect = row.get_node("PortraitStack/Portrait")
	var lantern_icon: LanternFuelIcon = row.get_node("PortraitStack/LanternFuelIcon")
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
	## generic career_class/wound-tier art (see PORTRAIT_SETS's removal
	## note near the top of this file).
	portrait.texture = CareerPortraits.get_portrait_for_character(c)
	## Per the follow-up request ("add a red tint at low health"): the
	## old wound-tier art baked its damage cue into the swapped image
	## itself — with one portrait per Career now, the same cue is a
	## colour tint instead.
	portrait.modulate = CareerPortraits.wound_modulate_for_character(c)

	## Per the follow-up request: the lantern-drain overlay lives on
	## THIS character's own portrait — each party member tracks their
	## own equipped light source/fuel independently (Character fields,
	## not shared), so a member not currently holding an oil-requiring
	## source simply shows no icon at all rather than an empty one.
	var light_item := c.get_equipped_light_item()
	if light_item != null and light_item.light_requires_oil:
		lantern_icon.visible = true
		lantern_icon.set_fuel(clamp(c.light_fuel_minutes / Character.LAMP_OIL_MINUTES, 0.0, 1.0), c.light_mode != "off")
	elif light_item != null and light_item.light_self_fuel_minutes > 0.0:
		## Per the request ("candles last 4hrs each"): the same drain
		## icon, now normalized against this item's own per-unit burn
		## time instead of a Lamp Oil flask's — Candle gets a visible
		## countdown on its current unit exactly like an oil lantern
		## does, just fed from a different denominator.
		lantern_icon.visible = true
		lantern_icon.set_fuel(clamp(c.light_fuel_minutes / light_item.light_self_fuel_minutes, 0.0, 1.0), c.light_mode != "off")
	else:
		lantern_icon.visible = false

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.14, 0.14, 0.12, 0.9)
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	panel_style.content_margin_left = 4
	panel_style.content_margin_right = 4
	panel_style.content_margin_top = 3
	panel_style.content_margin_bottom = 3
	if is_active:
		panel_style.border_width_left = 2
		panel_style.border_width_top = 2
		panel_style.border_width_right = 2
		panel_style.border_width_bottom = 2
		panel_style.border_color = Color(0.85, 0.7, 0.25)
	panel.add_theme_stylebox_override("panel", panel_style)

## Per the request: the currently active Task/Quest (see
## Character.get_active_task()), shown on the right side of the
## Overworld's own info bar so the player can see it at a glance
## without opening the Character menu's Quests sub-tab. Shows nothing
## at all when there's no active task, rather than an empty "no
## quest" placeholder cluttering the bar.
func _update_quest_tracker(c: Character) -> void:
	var task: Dictionary = c.get_active_task()
	if task.is_empty():
		quest_tracker_title.text = ""
		quest_tracker_detail.text = ""
		return
	quest_tracker_title.text = str(task.get("title", ""))
	var task_type: String = str(task.get("task_type", ""))
	if task_type == "gather":
		quest_tracker_detail.text = "%d / %d %s" % [int(task.get("progress", 0)), int(task.get("target_count", 1)), str(task.get("target_key", ""))]
	elif task_type == "find_encounter":
		quest_tracker_detail.text = "Looking for: %s" % str(task.get("target_key", ""))
	else:
		quest_tracker_detail.text = ""

func _update_night_overlay() -> void:
	## Per the request: no day/night cycle on the World Map — travel
	## there is measured in days and Stages, not a single continuous
	## day/night visual that doesn't mean much at that scale.
	if current_map_def != null and current_map_def.is_world_map:
		_night_overlay_base_color = Color(0, 0, 0, 0)
		night_overlay.color = _night_overlay_base_color
		## Real bug fix ("stuck on a black screen when leaving Giessingen
		## ... ok, it's just very dark ... on the overworld map, even
		## tho its 08:50am"): this early-return used to skip
		## _update_cloud_shadow_overlay() entirely, so CloudShadowOverlay
		## itself was never told anything on the World Map — only the
		## dark_location and ordinary-daytime branches below ever called
		## it. Every fresh arrival on the World Map (change_scene_to_file
		## always rebuilds Overworld.tscn from scratch) left that
		## ColorRect sitting at its raw scene-file default — visible=true
		## with an OPAQUE near-black color = Color(0.05, 0.07, 0.1, 1) —
		## covering the whole screen with no shader/opacity animation
		## ever applied to soften it. Confirmed directly via a headless
		## repro (fresh Overworld instance, World Map, 08:50 game time):
		## current_map_def.is_world_map was true and get_night_darkness()
		## was correctly 0.0, yet CloudShadowOverlay.visible read true
		## with alpha 1.0 regardless — exactly matching the report
		## (screen reads "very dark," not literally frozen, HUD/clock
		## still readable underneath since it's a separate always-on-top
		## UI layer). Per the follow-up request ("do add the cloud
		## overlay to the overworld map... considering the high up
		## view"), the World Map is no longer exempt from cloud shadows
		## at all — it gets its own finer-grained shader tuning instead
		## (see _maybe_reseed_cloud_shadow_overlay()'s is_world_map
		## branch) — so this now calls the same real update function the
		## other two branches already do, instead of just force-hiding.
		_update_cloud_shadow_overlay()
		return
	## Per the light-source follow-up request: a dark_location map (a
	## cave, a ruin interior) is always dark regardless of the clock —
	## checked here, ahead of the ordinary time-of-day tint below, so
	## the base ambient darkness itself (not just whether a carried
	## light source is "effective," see _light_source_effective())
	## reflects it. Without this, a cave visited at noon would render
	## with the same near-zero-alpha daylight overlay as being outside,
	## since get_time_of_day_color() has no idea it's underground.
	if current_map_def != null and current_map_def.is_dark_location:
		_night_overlay_base_color = GameState.get_dark_location_color()
		night_overlay.color = _night_overlay_base_color
		_update_cloud_shadow_overlay()
		return
	## Per the request: real dawn/morning/noon/afternoon/evening/dusk
	## light-COLOR changes, not just a darkness alpha — GameState's own
	## get_time_of_day_color() carries both (see its own comment for the
	## full keyframe table, based directly on the reference chart the
	## user provided). _apply_moon_glow_pulse() (in _process()) reads
	## _night_overlay_base_color and nudges the alpha slightly on top of
	## it every frame — this function stays the single source of truth
	## for the real, event-driven time-of-day value.
	_night_overlay_base_color = GameState.get_time_of_day_color()
	night_overlay.color = _night_overlay_base_color
	_update_cloud_shadow_overlay()

## Per the request: an animated, patchy cloud-shadow overlay drifting
## across the map (see cloud_shadow_overlay.gdshader's own header for
## the technique/attribution). Per the follow-up request ("do add the
## cloud overlay to the overworld map... considering the high up
## view"), the World Map now shows this too — it used to be exempt
## entirely (a continuous ground-level visual "didn't mean much" at
## World Map's own day-and-Stage travel scale), but the World Map is
## really just a much-further-zoomed-out view of the same land, so
## drifting cloud shadows read fine there too as long as the shader's
## own tuning accounts for that zoomed-out scale (see
## _maybe_reseed_cloud_shadow_overlay()'s is_world_map branch — much
## smaller pixels, smaller/denser patches, matching a genuine high-up
## view rather than the close-up local-map look).
func _update_cloud_shadow_overlay() -> void:
	if not is_instance_valid(cloud_shadow_overlay):
		return
	## Per the light-source follow-up request: no drifting cloud shadows
	## underground/indoors — a cave/ruin interior has no open sky for
	## clouds to shadow in the first place. The only remaining exemption.
	cloud_shadow_overlay.visible = current_map_def == null or not current_map_def.is_dark_location
	if cloud_shadow_overlay.visible:
		_maybe_reseed_cloud_shadow_overlay()

## Per the request ("randomize it subtly day to day"): reseeds the
## cloud shadow shader's wind/patch/threshold/opacity uniforms once per
## in-game calendar day — deterministic (same seed always produces the
## same day's pattern, so reloading mid-day doesn't visibly "jump") but
## different from the day before and the day after. Ranges are kept
## tight around the shader's own tuned defaults specifically so each
## day's cloud cover reads as a subtly different variation, not a
## wildly different effect.
func _maybe_reseed_cloud_shadow_overlay() -> void:
	var day_key: int = GameState.imperial_year * 1000 + GameState.day_of_year
	var is_world: bool = current_map_def != null and current_map_def.is_world_map
	if day_key == _cloud_shadow_seed_day and is_world == _cloud_shadow_seed_is_world:
		return
	_cloud_shadow_seed_day = day_key
	_cloud_shadow_seed_is_world = is_world
	if not (cloud_shadow_overlay.material is ShaderMaterial):
		var mat := ShaderMaterial.new()
		mat.shader = CLOUD_SHADOW_SHADER
		cloud_shadow_overlay.material = mat
	var mat: ShaderMaterial = cloud_shadow_overlay.material
	var rng := RandomNumberGenerator.new()
	## Per the follow-up request: salted differently from the local-map
	## seed below so the World Map's own cloud pattern doesn't just
	## mirror whatever the local-map roll for the same calendar day
	## happened to be — a real, independently-varying look from one day
	## to the next.
	rng.seed = day_key * 2 + (1 if is_world else 0)
	mat.set_shader_parameter("wind_dir_angle", rng.randf_range(-40.0, 40.0))
	mat.set_shader_parameter("wind_speed", rng.randf_range(14.0, 32.0))
	mat.set_shader_parameter("use_wind_gusts", true)
	if is_world:
		## Per the follow-up request ("much smaller pixels and more
		## detail considering the high up view"): the World Map shows
		## far more ground per screen pixel than a local map's close-up
		## view — the same patch/pixel sizes tuned for standing at
		## ground level would read as a few giant, blocky shadow bands
		## up here instead of a natural dappled cloud pattern. Smaller
		## pixel_size_px keeps the pixelation fine-grained rather than
		## chunky, and smaller patch_width/height raises the pattern's
		## frequency so many smaller shadow patches show across the much
		## larger visible area, reading as genuine detail from height
		## rather than a few oversized blobs.
		mat.set_shader_parameter("patch_width_px", rng.randf_range(60.0, 130.0))
		mat.set_shader_parameter("patch_height_px", rng.randf_range(25.0, 55.0))
		mat.set_shader_parameter("pixel_size_px", rng.randf_range(1.0, 2.0))
	else:
		mat.set_shader_parameter("patch_width_px", rng.randf_range(220.0, 420.0))
		mat.set_shader_parameter("patch_height_px", rng.randf_range(70.0, 140.0))
		mat.set_shader_parameter("pixel_size_px", rng.randf_range(2.0, 6.0))
	mat.set_shader_parameter("rotation_degrees", rng.randf_range(-20.0, 20.0))
	mat.set_shader_parameter("threshold", rng.randf_range(0.56, 0.68))
	mat.set_shader_parameter("opacity", rng.randf_range(0.08, 0.16))
