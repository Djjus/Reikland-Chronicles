extends Control
class_name CityMapView
## New City Screen feature: renders the city's background map image
## with clickable location markers and the party's own group token,
## zoomable/pannable — the map-image equivalent of BattleGridView (see
## that file's own header comment for the general approach this
## mirrors). Deliberately dumb, same convention as BattleGridView:
## this control owns no game state of its own, just draws whatever
## CityScreen hands it via set_state()/set_locations() and reports raw
## clicks back through signals; CityScreen decides what a click means.

## Emitted with the CityLocationDefinition a marker was clicked on.
## Follow-up request ("left clicking a visible POI should not trigger
## travel... select it, and show a radial menu"): CityScreen now
## interprets this as "select this location" rather than "offer travel
## to it directly" — the meaning of the click itself (you clicked this
## marker) hasn't changed, only what CityScreen does about it.
signal location_clicked(loc: CityLocationDefinition)
## Raw content-space (unscaled, pre zoom/pan) click position, for a
## click that didn't land on any marker. Per the same follow-up
## request ("left or right click anywhere else on the map will
## deselect current POI"), this is now actually used — CityScreen
## deselects whatever's currently selected on a background click.
signal background_clicked(content_pos: Vector2)
## Emitted when one of the radial-menu buttons (drawn around either the
## home or target marker — see home_location/target_location below) is
## clicked. `loc` is whichever of the two that button actually belongs
## to (NOT always target_location — a home-radial button emits
## home_location). `action` is one of the "key" values CityScreen
## handed in via home_actions/target_actions — "lore" plus either
## "travel" (target_location — anywhere the party hasn't walked to yet)
## or "stay"/"enter_shop"/"leave_city" (home_location — the single
## location the party's own token is currently standing on); CityScreen
## owns what each one does.
signal radial_action(loc: CityLocationDefinition, action: String)
## Emitted on any right-click anywhere on the map. This view has no
## other use for the right mouse button, so per the follow-up request
## ("right click anywhere else on the map will deselect current POI")
## CityScreen just always deselects on this, regardless of what (if
## anything) was under the click.
signal right_clicked()

const MIN_SIZE := Vector2(400, 300)

## Per the same "SHIFT+wheel zoom toward cursor, SHIFT+drag pan" input
## pattern as BattleGridView — a plain image map has no natural "default
## fits exactly" zoom the way a fixed grid does, so the endpoints here
## are just even bounds rather than mirroring that file's own fitted
## 0.6667 leading entry.
## Per the request ("lets let camera zoom on all screens which have it
## have smoother and finer zoom scaling"): same continuous-zoom
## rewrite as BattleGridView.MIN_ZOOM/MAX_ZOOM/ZOOM_STEP_FACTOR — the
## old ZOOM_LEVELS table only offered 7 discrete stops, so most values
## (e.g. 0.9x) were simply unreachable. Same endpoints the old table
## had (0.35/3.0), so nothing that depended on those specific bounds
## changes behavior.
const MIN_ZOOM := 0.35
const MAX_ZOOM := 3.0
const ZOOM_STEP_FACTOR := 1.06   ## ~6% per wheel tick
var zoom_level: float = 0.5
var pan_offset: Vector2 = Vector2.ZERO
var _is_panning: bool = false

## Follow-up request ("allow zoomable maps to be dragged with left
## click... when not clicking on a marker"): a plain left-press no
## longer commits its click right away — it waits to see whether the
## player drags (pan) or releases roughly in place (a real click,
## either on a marker or the background). SHIFT+drag still starts
## panning immediately on press, unchanged, for muscle memory carried
## over from before this click/pan was ever a distinction.
var _click_pending: bool = false
var _click_candidate_location: CityLocationDefinition = null
## Follow-up request (radial POI menu): a press that lands on one of
## the radial buttons is deferred exactly the same way a marker press
## is — "" means the press didn't land on a radial button.
## Follow-up request ("always show Leave City/Stay/Enter... trigger it
## after travel finishes... show click focused options Lore/Travel at
## the same time"): now that there can be TWO radial menus open at
## once (home_location's and target_location's — see their own
## declarations below), the loc a hit radial button belongs to is no
## longer always target_location, so it's captured alongside the
## action key here.
var _click_candidate_radial_action: String = ""
var _click_candidate_radial_loc: CityLocationDefinition = null
var _press_pos: Vector2 = Vector2.ZERO
const DRAG_CLICK_THRESHOLD := 6.0

var background: Texture2D = null

## New follow-up request ("phase the ubersreik background map by time
## of day... start phasing in gradually 2 hrs before the time of the
## image"): an optional second background layer drawn on top of
## `background`, alpha-blended in via `background_blend` (0 = only
## `background` visible, 1 = `background_next` fully replaces it).
## CityScreen owns the actual time-of-day math and just updates these
## two fields + queue_redraw() whenever the game clock moves; this
## control stays "dumb" per its own header comment.
var background_next: Texture2D = null
var background_blend: float = 0.0

## Content-space size is pinned to whichever keyframe image CityScreen
## first hands in (see set_background_reference_size()) rather than
## read off `background.get_size()` directly — the four time-of-day
## keyframes aren't guaranteed to all be the exact same source pixel
## size (they're stretched to fit regardless), and letting content
## size follow whichever texture happens to be "current" would make
## marker radii/zoom jitter every time the day crosses a keyframe.
var _content_size_override: Vector2 = Vector2.ZERO

func set_background_reference_size(sz: Vector2) -> void:
	_content_size_override = sz

## Follow-up request ("give the Ubersreik 8pm map a slight animated
## twinkle on the small doted lights around the map"): CityScreen hands
## in the 8pm keyframe texture and a fixed list of normalized light-dot
## positions (detected offline from that image itself — see
## UbersreikNightLights). Whenever that texture is wholly or partially
## the visible background (current OR fading in as background_next — see
## _night_lights_opacity()), a small twinkling glow is drawn on top of
## it at each position. Purely decorative; CityScreen owns which
## texture "is" the night-lights one, this view just draws whatever
## it's handed, same "dumb view" convention as the rest of this file.
var night_lights_texture: Texture2D = null
var night_lights_positions: Array = []   ## Array[Vector2], normalized 0..1

## Follow-up tuning request ("too extreme, turn it way down only a 2-3
## should twinkle at once then alternate randomly, they should also be
## at least 50% fainter"): the first version pulsed every one of the
## ~195 detected light points continuously and independently, which
## read as the whole map shimmering rather than a subtle effect. Now
## only TWINKLE_ACTIVE_COUNT points are ever animated at once — each
## tracked by a "slot" that fades one light in and back out over a
## short randomized duration, then picks a new random light and
## repeats. Every other light just shows whatever's already baked into
## the base map art (no overlay at all), so the effect reads as a
## handful of lights catching the eye now and then rather than a
## constant glimmer.
const TWINKLE_ACTIVE_COUNT := 3
const TWINKLE_MIN_DURATION := 1.1
const TWINKLE_MAX_DURATION := 2.4
var _twinkle_slots: Array = []   ## each: {"index": int, "elapsed": float, "duration": float}

func _ensure_twinkle_slots() -> void:
	if not _twinkle_slots.is_empty() or night_lights_positions.is_empty():
		return
	for i in range(TWINKLE_ACTIVE_COUNT):
		var slot := _new_twinkle_slot()
		## Stagger initial phase so all slots don't fade in together the
		## first time the 8pm keyframe becomes visible.
		slot["elapsed"] = randf() * slot["duration"]
		_twinkle_slots.append(slot)

func _new_twinkle_slot() -> Dictionary:
	var idx: int = randi() % night_lights_positions.size()
	## A handful of retries so a slot rarely picks a light another slot
	## is already twinkling — not load-bearing (a rare double-up is
	## harmless), just keeps the "2-3 distinct lights" reading honest.
	var attempts := 0
	while attempts < 5 and _is_index_active(idx):
		idx = randi() % night_lights_positions.size()
		attempts += 1
	return {"index": idx, "elapsed": 0.0, "duration": randf_range(TWINKLE_MIN_DURATION, TWINKLE_MAX_DURATION)}

func _is_index_active(idx: int) -> bool:
	for slot in _twinkle_slots:
		if slot["index"] == idx:
			return true
	return false

## Only ticks/redraws while the night-lights texture actually has some
## visible opacity — no wasted per-frame work the rest of the day.
func _process(delta: float) -> void:
	if _night_lights_opacity() <= 0.0:
		return
	_ensure_twinkle_slots()
	for slot in _twinkle_slots:
		slot["elapsed"] += delta
		if slot["elapsed"] >= slot["duration"]:
			var fresh := _new_twinkle_slot()
			slot["index"] = fresh["index"]
			slot["elapsed"] = 0.0
			slot["duration"] = fresh["duration"]
	queue_redraw()

## How visible the 8pm keyframe currently is (0..1) — full opacity
## while it's the settled `background` with nothing blending over it,
## fading down as background_next blends in over it, or fading up if
## it's itself the incoming background_next. Mirrors the same "current
## fades out, next fades in via background_blend" math CityScreen's
## own _update_time_of_day_background() drives.
func _night_lights_opacity() -> float:
	if night_lights_texture == null:
		return 0.0
	if background == night_lights_texture:
		return (1.0 - background_blend) if background_next != null else 1.0
	if background_next == night_lights_texture and background_blend > 0.0:
		return background_blend
	return 0.0

var locations: Array = []   ## Array[CityLocationDefinition], UNLOCKED ONLY — CityScreen filters before handing these in
var party_token_pos: Vector2 = Vector2(0.5, 0.5)   ## normalized 0..1
var party_token_texture: Texture2D = null
## Per the follow-up request ("add a red tint at low health"): tints the
## party token the same way a portrait TextureRect's own `modulate`
## would — see CareerPortraits.wound_modulate_for_character(). Set
## alongside party_token_texture by whoever assigns it (city_screen.gd).
var party_token_modulate: Color = Color(1, 1, 1)
var hovered_location: CityLocationDefinition = null

## Follow-up request ("always show the Leave City, Stay and Enter
## radial options when the party is at a location and they are
## available, trigger it after travel finishes... only remove it when
## travel starts again... show click focused options Lore/Travel at
## the same time"): the radial menu is no longer a single "whatever's
## currently selected" slot — there are now up to TWO independent
## radial menus drawn/clickable at once:
##
## - home_location/home_actions: the location the party's own token is
##   CURRENTLY standing on. Set by CityScreen right after arriving
##   somewhere (or on first load) and cleared right as a real walk
##   actually begins — see CityScreen._refresh_home_radial()/
##   _run_travel(). Always [Lore, Stay|Enter|Leave City] (whichever
##   applies), never Travel — walking to where you already are was
##   always a no-op. Persists through clicking other markers, opening
##   Lore, or even a different location's own travel confirm — it's
##   only ever cleared by a real walk actually starting.
## - target_location/target_actions/target_radial_open: the OTHER
##   location the player just clicked, if any — always exactly
##   [Lore, Travel] (a target, by construction, is never the location
##   the party is already standing on — see CityScreen._select_location).
##   Cleared on a background/right click, or once its own Travel button
##   is actually clicked (see CityScreen._on_radial_action's own
##   "travel" branch).
##
## Both CityScreen-owned, same "CityScreen sets it, this view just
## draws/reports" convention as the rest of this file — this view never
## flips either on its own.
## Follow-up request ("have the shops... close at 8pm and open at 8am,
## gray out the Enter option and change it to Closed, show tooltip"):
## an action dict may now also carry `"disabled": true` and a
## `"tooltip": String` — CityScreen decides WHY (shop hours, here) and
## hands the finished dict in; this view just draws a disabled entry
## greyed out and inert to clicks, and shows its tooltip on hover. Both
## keys are optional — every action dict without them behaves exactly
## as before.
var home_location: CityLocationDefinition = null
var home_actions: Array = []   ## Array[{"key": String, "label": String, "disabled": bool, "tooltip": String}]
var target_location: CityLocationDefinition = null
var target_radial_open: bool = false
var target_actions: Array = []   ## Array[{"key": String, "label": String, "disabled": bool, "tooltip": String}]
## Screen-space (post-transform) rects last drawn for each radial menu's
## own buttons, keyed by action string — same convention as
## _marker_screen_rects. Two separate dicts (rather than one shared by
## key) since both radials can be open at once and could otherwise both
## have a "lore" entry colliding on the same key.
var _home_radial_rects: Dictionary = {}   ## String -> Rect2
var _target_radial_rects: Dictionary = {}   ## String -> Rect2
## The full action dict last drawn for each button, keyed the same way
## as the rects above — lets both hit-testing (is this key disabled?)
## and hover (does this key have a tooltip?) read back "disabled"/
## "tooltip" without CityScreen needing to hand them in twice.
var _home_radial_meta: Dictionary = {}   ## String -> Dictionary (the action dict)
var _target_radial_meta: Dictionary = {}   ## String -> Dictionary (the action dict)
## Follow-up request (shop hours tooltip): whatever disabled button's
## tooltip text is currently under the mouse, and where to draw it —
## "" means nothing is being hovered. Updated in _gui_input's own
## MouseMotion handling, alongside the existing marker-hover check.
var _hovered_radial_tooltip: String = ""
var _hovered_radial_mouse_pos: Vector2 = Vector2.ZERO

## Follow-up request (legend click should reveal an off-screen POI so
## its radial menu is actually visible/clickable): centers the view on
## a normalized content-space position, same zoom level, then clamps.
func center_on_content_pos(content_pos_norm: Vector2) -> void:
	var content := _content_size()
	if content.x <= 0.0 or content.y <= 0.0:
		return
	var target_px: Vector2 = Vector2(content_pos_norm.x * content.x, content_pos_norm.y * content.y)
	pan_offset = size / 2.0 - target_px * zoom_level
	_clamp_pan()
	queue_redraw()

## Marker colour per CityLocationDefinition.category — purely cosmetic
## grouping so the map/legend read at a glance without needing real
## icon art per location.
const CATEGORY_COLORS := {
	"gate": Color(0.55, 0.55, 0.6),
	"tavern": Color(0.85, 0.6, 0.2),
	"guild": Color(0.4, 0.55, 0.8),
	"shop": Color(0.55, 0.75, 0.4),
	"temple": Color(0.9, 0.85, 0.4),
	"landmark": Color(0.75, 0.4, 0.75),
	"watch": Color(0.8, 0.3, 0.3),
	"residence": Color(0.6, 0.5, 0.4),
	"castle": Color(0.7, 0.7, 0.75),
}
const DEFAULT_MARKER_COLOR := Color(0.8, 0.8, 0.75)

## New follow-up request ("vector some rough walking paths... so that
## travel across the map looks more realistic"): the current route's
## own polyline (normalized positions, set by CityScreen while a walk
## is being offered/animated) — drawn as a dashed road-like line under
## the party token so the player can see the actual route a walk will
## take, not just a straight line to the destination. Empty when no
## route is currently being offered/walked.
var travel_path: Array = []

## Screen-space (post-transform) rect last drawn for each marker,
## rebuilt every _draw() — used by _gui_input's own hit-testing so
## clicks don't need to duplicate _draw()'s own transform math.
var _marker_screen_rects: Dictionary = {}   ## CityLocationDefinition -> Rect2

func _ready() -> void:
	custom_minimum_size = MIN_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(func(): _clamp_pan(); queue_redraw())
	mouse_exited.connect(func():
		if hovered_location != null:
			hovered_location = null
			queue_redraw()
		if _hovered_radial_tooltip != "":
			_hovered_radial_tooltip = ""
			queue_redraw()
	)

## Content-space size — the background image's own real pixel size,
## the same "unscaled space everything draws in before the one
## draw_set_transform() call" convention BattleGridView uses (there,
## square_px * COLS/ROWS; here, just the texture's own size).
func _content_size() -> Vector2:
	if _content_size_override.x > 0.0 and _content_size_override.y > 0.0:
		return _content_size_override
	if background == null:
		return Vector2.ONE
	return background.get_size()

## Fits the whole background image into this control's own current
## rect (same idea as BattleGridView's leading 0.6667 zoom level) —
## used once, the first time a real background/size are both available,
## to pick a sane starting zoom rather than always opening at 0.5.
func fit_to_view() -> void:
	var content := _content_size()
	if content.x <= 0.0 or content.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return
	var fit: float = min(size.x / content.x, size.y / content.y)
	## Per the continuous-zoom rewrite: no more table to snap to — the
	## exact fit ratio (clamped to the same range wheel-zooming honors)
	## is used directly.
	zoom_level = clampf(fit, MIN_ZOOM, MAX_ZOOM)
	pan_offset = (size - content * zoom_level) / 2.0
	_clamp_pan()
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.shift_pressed \
			and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		_handle_zoom_wheel(event.button_index == MOUSE_BUTTON_WHEEL_UP, event.position)
		return
	## Per the request ("allow zooming in and out"): plain wheel (no
	## SHIFT needed) also zooms — unlike the battle grid, this screen
	## has no other use for a bare mouse wheel, so it's free to be the
	## primary zoom gesture; SHIFT+wheel still works too for muscle
	## memory carried over from the battle map.
	if event is InputEventMouseButton and event.pressed \
			and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		_handle_zoom_wheel(event.button_index == MOUSE_BUTTON_WHEEL_UP, event.position)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		## No other use for right-click on this view — always a plain
		## deselect signal, position irrelevant. Also drop any left-click/
		## pan already in flight so a right-click mid-drag doesn't leave
		## either dangling.
		_click_pending = false
		_is_panning = false
		right_clicked.emit()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.shift_pressed:
				_is_panning = true
				_click_pending = false
				return
			## Plain left-press (no SHIFT): don't commit to a click yet —
			## see _click_pending's own declaration comment above. Whether
			## it lands on a radial button, a marker, or bare background,
			## the actual radial_action/location_clicked/background_clicked
			## emission is deferred to MOUSE_BUTTON_LEFT release below,
			## unless a drag past DRAG_CLICK_THRESHOLD converts it into a
			## pan first (handled in the MouseMotion branch). Radial
			## buttons (home's or target's — see _radial_hit_at) are
			## checked first since they sit on top of/near their own marker.
			_press_pos = event.position
			var hit: Dictionary = _radial_hit_at(event.position)
			_click_candidate_radial_loc = hit.get("loc", null)
			_click_candidate_radial_action = hit.get("action", "")
			_click_candidate_location = null if _click_candidate_radial_action != "" else _location_at(event.position)
			_click_pending = true
			return
		else:
			if _is_panning:
				_is_panning = false
				return
			if _click_pending:
				_click_pending = false
				if _click_candidate_radial_action != "":
					radial_action.emit(_click_candidate_radial_loc, _click_candidate_radial_action)
				elif _click_candidate_location != null:
					location_clicked.emit(_click_candidate_location)
				else:
					var content_pos: Vector2 = (event.position - pan_offset) / zoom_level
					background_clicked.emit(content_pos)
				return
	if event is InputEventMouseMotion:
		if _is_panning:
			pan_offset += event.relative
			_clamp_pan()
			queue_redraw()
			return
		if _click_pending:
			if event.position.distance_to(_press_pos) > DRAG_CLICK_THRESHOLD:
				## Dragged far enough to no longer be "just a click" —
				## convert to a pan starting from here, rather than
				## snapping the click through or losing the motion.
				_click_pending = false
				_is_panning = true
				pan_offset += event.relative
				_clamp_pan()
				queue_redraw()
			return
		var hit := _location_at(event.position)
		if hit != hovered_location:
			hovered_location = hit
			queue_redraw()
		## Follow-up request (shop hours tooltip): tracked independently
		## of the marker hover above — a radial button sits well outside
		## its own marker's hit rect, so this needs its own check rather
		## than piggybacking on `hit`.
		var tooltip := _radial_tooltip_at(event.position)
		if tooltip != _hovered_radial_tooltip:
			_hovered_radial_tooltip = tooltip
			queue_redraw()
		_hovered_radial_mouse_pos = event.position
		return

func _handle_zoom_wheel(zoom_in: bool, mouse_pos: Vector2) -> void:
	var old_zoom := zoom_level
	var new_zoom: float = clampf(zoom_level * (ZOOM_STEP_FACTOR if zoom_in else 1.0 / ZOOM_STEP_FACTOR), MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, old_zoom):
		return
	pan_offset = mouse_pos - (mouse_pos - pan_offset) * (new_zoom / old_zoom)
	zoom_level = new_zoom
	_clamp_pan()
	queue_redraw()

const OVERSCROLL_FACTOR := 0.5
func _clamp_pan() -> void:
	var content := _content_size()
	if content.x <= 0.0 or content.y <= 0.0:
		pan_offset = Vector2.ZERO
		return
	var content_size := content * zoom_level
	var overscroll := size * OVERSCROLL_FACTOR
	var bound_a := Vector2(size.x - content_size.x, size.y - content_size.y)
	var bound_b := Vector2.ZERO
	pan_offset.x = clamp(pan_offset.x, min(bound_a.x, bound_b.x) - overscroll.x, max(bound_a.x, bound_b.x) + overscroll.x)
	pan_offset.y = clamp(pan_offset.y, min(bound_a.y, bound_b.y) - overscroll.y, max(bound_a.y, bound_b.y) + overscroll.y)

## Marker radius in content-space (image pixels) — scales visually
## with zoom via the shared draw_set_transform(), same as everything
## else drawn in content space.
## Follow-up request ("reduce marker size by 40%"): POI markers only
## (16.0 -> 9.6) — the party's own group token (PARTY_TOKEN_RADIUS) is
## a different element entirely and wasn't part of that request.
const MARKER_RADIUS := 9.6
const PARTY_TOKEN_RADIUS := 20.0

func _location_at(local_pos: Vector2) -> CityLocationDefinition:
	for loc in _marker_screen_rects:
		if _marker_screen_rects[loc].has_point(local_pos):
			return loc
	return null

## Checks the home radial's own buttons first, then target's — returns
## {"loc": CityLocationDefinition, "action": String} for whichever one
## local_pos hits, or {} if neither. Both rect dicts are only populated
## by _draw() while their own radial is actually open (see
## _draw_radial_menu()), so a stale/hidden radial's buttons never
## register a hit here.
## Follow-up request (shop hours): a button marked "disabled" in its own
## meta dict (see home_actions/target_actions' own declaration comment)
## is inert to clicks — treated the same as a miss here, so pressing a
## greyed-out "Closed" button falls through to whatever's underneath
## (typically a background click) rather than firing its action.
func _radial_hit_at(local_pos: Vector2) -> Dictionary:
	for action in _home_radial_rects:
		if _home_radial_rects[action].has_point(local_pos):
			if _home_radial_meta.get(action, {}).get("disabled", false):
				return {}
			return {"loc": home_location, "action": action}
	for action in _target_radial_rects:
		if _target_radial_rects[action].has_point(local_pos):
			if _target_radial_meta.get(action, {}).get("disabled", false):
				return {}
			return {"loc": target_location, "action": action}
	return {}

## Follow-up request (shop hours tooltip): unlike _radial_hit_at, this
## checks EVERY button (disabled or not) purely to find hover tooltip
## text — a disabled button is still very much "hit" for the purposes
## of explaining to the player why it's greyed out, just not for
## firing its action. Returns "" if the position isn't over any button
## with tooltip text set.
func _radial_tooltip_at(local_pos: Vector2) -> String:
	for action in _home_radial_rects:
		if _home_radial_rects[action].has_point(local_pos):
			return _home_radial_meta.get(action, {}).get("tooltip", "")
	for action in _target_radial_rects:
		if _target_radial_rects[action].has_point(local_pos):
			return _target_radial_meta.get(action, {}).get("tooltip", "")
	return ""

func _draw() -> void:
	var content := _content_size()
	if content.x <= 0.0 or content.y <= 0.0:
		return
	draw_set_transform(pan_offset, 0.0, Vector2(zoom_level, zoom_level))
	if background != null:
		draw_texture_rect(background, Rect2(Vector2.ZERO, content), false)
	## Next time-of-day keyframe crossfades in on top, alpha-modulated —
	## drawn stretched to the same fixed content rect as the base layer
	## regardless of its own native pixel size, so the two always align.
	if background_next != null and background_blend > 0.0:
		draw_texture_rect(background_next, Rect2(Vector2.ZERO, content), false, Color(1, 1, 1, background_blend))

	## Twinkling night-light dots — see night_lights_texture's own
	## declaration comment. Drawn right on top of the background layers
	## (before travel path/markers/token) so it reads as part of the
	## map's own lighting rather than sitting above the UI elements.
	var night_opacity: float = _night_lights_opacity()
	if night_opacity > 0.0 and not night_lights_positions.is_empty():
		## Only the handful of currently-active slots draw anything (see
		## _twinkle_slots' own declaration comment) — every other light
		## is left as whatever's already painted into the base map art.
		for slot in _twinkle_slots:
			var idx: int = slot["index"]
			if idx < 0 or idx >= night_lights_positions.size():
				continue
			var lp: Vector2 = night_lights_positions[idx]
			var lpos: Vector2 = Vector2(lp.x * content.x, lp.y * content.y)
			## A single fade-in/fade-out bump across the slot's own
			## lifetime (0 at both ends, 1 at the midpoint) rather than a
			## continuous oscillation — reads as one light catching for a
			## moment, not a strobe.
			var t: float = slot["elapsed"] / slot["duration"]
			var envelope: float = sin(PI * clampf(t, 0.0, 1.0))
			## Brightness history: original pass was outer 0.35 / inner 0.9
			## alpha caps; the "too extreme, turn it way down" follow-up cut
			## those to 0.15 / 0.4 (still well over 50% fainter than the
			## original once the envelope's own average is factored in — see
			## that request's own note above). A later direct "increase the
			## twinkle intensity by 20%, same rate" follow-up bumped
			## brightness back up in place from there, deliberately NOT
			## touching TWINKLE_ACTIVE_COUNT/MIN/MAX_DURATION (the "rate" —
			## how many lights are active at once and how long each one
			## takes): 0.15 -> 0.18, 0.4 -> 0.48.
			var a: float = night_opacity * envelope
			draw_circle(lpos, 4.0, Color(1.0, 0.85, 0.45, a * 0.18))
			draw_circle(lpos, 1.8, Color(1.0, 0.95, 0.75, a * 0.48))

	if travel_path.size() >= 2:
		var path_px: Array = []
		for p in travel_path:
			path_px.append(Vector2(p.x * content.x, p.y * content.y))
		## A dashed line reads as a "route" rather than a solid drawn-on
		## line — walked manually since Godot has no built-in dashed
		## polyline draw call, in short fixed-length content-space
		## segments so the dash length looks consistent at any zoom.
		##
		## Follow-up request ("change the travel path colour to
		## something that will be well visible at both night and day —
		## hard to see in the day right now"): the original warm gold
		## (1, 0.9, 0.5) sat far too close to the daytime map's own warm
		## tan/cream palette (and to the night map's warm twinkling
		## window-light dots just above this in _draw()) to read
		## clearly against either. Replaced with a saturated magenta/
		## pink — a hue that barely appears anywhere in either the day
		## keyframe (browns/tans/muted blues-greens) or the night ones
		## (desaturated dark blue-grey) — plus a solid black outline
		## drawn first UNDER each dash/dot, so the line stays crisp
		## against light AND dark backdrops alike rather than relying on
		## the fill colour's own contrast to do all the work.
		const DASH_LEN := 10.0
		const GAP_LEN := 7.0
		const PATH_COLOR := Color(1.0, 0.15, 0.75, 0.95)
		const PATH_OUTLINE_COLOR := Color(0, 0, 0, 0.75)
		for i in range(path_px.size() - 1):
			var a: Vector2 = path_px[i]
			var b: Vector2 = path_px[i + 1]
			var seg_vec: Vector2 = b - a
			var seg_len: float = seg_vec.length()
			if seg_len <= 0.0:
				continue
			var dir: Vector2 = seg_vec / seg_len
			var travelled := 0.0
			while travelled < seg_len:
				var dash_end: float = min(travelled + DASH_LEN, seg_len)
				var dash_a: Vector2 = a + dir * travelled
				var dash_b: Vector2 = a + dir * dash_end
				draw_line(dash_a, dash_b, PATH_OUTLINE_COLOR, 5.0)
				draw_line(dash_a, dash_b, PATH_COLOR, 3.0)
				travelled = dash_end + GAP_LEN
		for p in path_px:
			draw_circle(p, 4.5, PATH_OUTLINE_COLOR)
			draw_circle(p, 3.5, PATH_COLOR)

	_marker_screen_rects.clear()
	var font := get_theme_default_font()
	for loc in locations:
		var cpos: Vector2 = Vector2(loc.map_position.x * content.x, loc.map_position.y * content.y)
		var color: Color = CATEGORY_COLORS.get(loc.category, DEFAULT_MARKER_COLOR)
		var is_hovered: bool = loc == hovered_location
		## Follow-up request (dual home/target radial menus): a marker
		## reads as "selected" (brighter ring + name label) whenever
		## EITHER of the two possible radials is open on it — home_location
		## just as much as target_location, so the location the party is
		## actually standing at stays visually highlighted the whole time
		## its own radial is up, not just while it's freshly clicked.
		var is_selected: bool = loc == target_location or loc == home_location
		var r: float = MARKER_RADIUS * (1.15 if (is_hovered or is_selected) else 1.0)

		## Same "black backdrop disc + coloured ring" token language as
		## BattleGridView's own combatant tokens, per the request to
		## visually match the rest of the game rather than inventing a
		## new marker style from scratch.
		draw_circle(cpos, r + 2.0, Color(0, 0, 0, 0.9))
		draw_circle(cpos, r, color)
		draw_arc(cpos, r + 2.0, 0, TAU, 24, Color(1, 1, 1, 0.9) if is_selected else Color(0, 0, 0, 0.85), 2.5)
		## A simple pin dot instead of per-category icon art (not yet
		## made) — still reads clearly at a glance once zoomed in, and
		## the colour alone already distinguishes categories.
		draw_circle(cpos, r * 0.35, Color(0.08, 0.07, 0.06, 0.9))

		if is_hovered or is_selected:
			var label: String = loc.location_name
			var font_size := 13
			var text_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x + 16.0
			var text_pos := Vector2(cpos.x - text_width / 2.0, cpos.y - r - 10.0)
			draw_string_outline(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, text_width, font_size, 4, Color(0, 0, 0, 0.9))
			draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, text_width, font_size, Color(1, 0.95, 0.8))

		## Screen-space hit rect for _gui_input, converted the same way
		## _square_at()/_location_at() expect (raw event.position space
		## — i.e. WITH pan_offset/zoom_level applied, since draw_set_
		## transform() only affects drawing, not stored coordinates).
		var screen_center: Vector2 = pan_offset + cpos * zoom_level
		var screen_r: float = (r + 4.0) * zoom_level
		_marker_screen_rects[loc] = Rect2(screen_center - Vector2(screen_r, screen_r), Vector2(screen_r, screen_r) * 2.0)

	## Follow-up request ("left clicking a POI selects it and shows a
	## radial menu... Lore and Travel" + the later "always show...
	## home_location's own radial... show click focused options Lore/
	## Travel at the same time"): drawn on top of the markers so neither
	## is ever hidden behind one, after _marker_screen_rects is fully
	## rebuilt above (so a radial button can never accidentally register
	## as landing on a marker's own hit rect instead). Home drawn first,
	## target second — doesn't matter for hit-testing (_radial_hit_at
	## checks both dicts regardless of draw order), just keeps target's
	## buttons on top on the rare occasion the two markers sit close
	## enough to overlap.
	_home_radial_rects.clear()
	_home_radial_meta.clear()
	if home_location != null:
		var hpos: Vector2 = Vector2(home_location.map_position.x * content.x, home_location.map_position.y * content.y)
		_draw_radial_menu(hpos, font, home_actions, _home_radial_rects, _home_radial_meta)
	_target_radial_rects.clear()
	_target_radial_meta.clear()
	if target_radial_open and target_location != null:
		var tpos: Vector2 = Vector2(target_location.map_position.x * content.x, target_location.map_position.y * content.y)
		_draw_radial_menu(tpos, font, target_actions, _target_radial_rects, _target_radial_meta)

	## Party group token — drawn after every marker and both radial
	## menus, so it always renders on top of whichever marker it's
	## standing on and any radial buttons drawn around that marker (the
	## home radial's own buttons circle the exact spot the token sits —
	## see the follow-up request "the character marker on top of it").
	var token_pos: Vector2 = Vector2(party_token_pos.x * content.x, party_token_pos.y * content.y)
	draw_circle(token_pos, PARTY_TOKEN_RADIUS + 3.0, Color(0, 0, 0, 1))
	if party_token_texture != null:
		var half := PARTY_TOKEN_RADIUS
		## Per the request ("use the new portraits in all Icon"): the
		## token used to be a 40x40 square wound-tier icon, so a plain
		## draw_texture_rect never distorted it. The new Career portraits
		## keep their own source aspect ratio, so this now crops to a
		## centered square region first (draw_texture_rect_region) rather
		## than squashing a tall/wide portrait to fit the round token.
		var tex_size: Vector2 = party_token_texture.get_size()
		var side: float = min(tex_size.x, tex_size.y)
		var src_rect := Rect2((tex_size.x - side) * 0.5, (tex_size.y - side) * 0.5, side, side)
		draw_texture_rect_region(party_token_texture, Rect2(token_pos - Vector2(half, half), Vector2(half, half) * 2.0), src_rect, party_token_modulate)
	else:
		draw_circle(token_pos, PARTY_TOKEN_RADIUS, Color(0.3, 0.55, 0.95))
	draw_arc(token_pos, PARTY_TOKEN_RADIUS + 3.0, 0, TAU, 28, Color(0.3, 0.75, 0.95), 3.0)

	## Follow-up request (shop hours tooltip): the very last thing drawn,
	## on top of literally everything else (including the party token) —
	## a tooltip explaining a greyed-out button should never be hidden
	## behind anything. Drawn in raw screen-space (transform reset to
	## identity) since _hovered_radial_mouse_pos is already a screen-
	## space position, same as every other _gui_input coordinate this
	## file works with — unlike the rest of _draw(), which draws in
	## content-space under the earlier draw_set_transform() call.
	if _hovered_radial_tooltip != "":
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var tt_font_size := 13
		var tt_max_width := 220.0
		var tt_text_size: Vector2 = font.get_multiline_string_size(_hovered_radial_tooltip, HORIZONTAL_ALIGNMENT_LEFT, tt_max_width, tt_font_size)
		var tt_box_size: Vector2 = tt_text_size + Vector2(16.0, 12.0)
		var tt_pos: Vector2 = _hovered_radial_mouse_pos + Vector2(16.0, 16.0)
		## Clamp so the tooltip never runs off the right/bottom edge of
		## this control when hovering near them.
		tt_pos.x = min(tt_pos.x, size.x - tt_box_size.x - 4.0)
		tt_pos.y = min(tt_pos.y, size.y - tt_box_size.y - 4.0)
		var tt_rect := Rect2(tt_pos, tt_box_size)
		draw_rect(tt_rect, Color(0.05, 0.05, 0.05, 0.95))
		draw_rect(tt_rect, Color(0.7, 0.7, 0.65, 0.9), false, 1.5)
		draw_multiline_string(font, tt_pos + Vector2(8.0, tt_font_size + 2.0), _hovered_radial_tooltip, HORIZONTAL_ALIGNMENT_LEFT, tt_max_width, tt_font_size, -1, Color(0.95, 0.92, 0.85))

## Follow-up request ("left clicking a POI... show a radial menu around
## it, for now let put in 2 buttons: Lore... and Travel"): small
## pill-shaped buttons arranged in an arc above the given marker centre
## (`cpos`, content-space) — a genuinely radial layout even though each
## individual button is a rounded box rather than a circle, since short
## text labels don't read well packed into a circular badge.
## Follow-up request (dual home/target radial menus): now a generic
## helper — `actions` is whichever list (home_actions or
## target_actions) this particular call is drawing, and the resulting
## screen-space hit rects are written into `out_rects` (either
## _home_radial_rects or _target_radial_rects) rather than a single
## shared dict, so CityScreen decides what each key means per-radial via
## the `loc` _radial_hit_at() reports alongside it.
## Follow-up request ("move the POI buttons out from the marker, so
## they don't cover it or each other"): the buttons used to sit at
## 200/340 degrees — up and to either side of the marker — which put
## them right on top of both the marker itself and its hovered/selected
## name label (drawn just above the marker; see the label block in
## _draw()). Radius bumped up (46 -> 68) so the buttons never cover the
## marker or the label.
##
## Follow-up request ("position the POI options more cleanly around the
## markers... evenly spaced around the markers depending on the number
## of available options"): buttons are no longer confined to a fixed
## arc below the marker (which crowded 2+ buttons together right under
## it, close to the party's own token when that marker is the home
## radial's). They're now spread evenly around the FULL circle at
## RADIAL_RADIUS — see _draw_radial_menu()'s own comment for the exact
## "reserve the top slot for the label" scheme, which both keeps this a
## genuine radial layout and guarantees the top (where the name label
## draws) always stays clear regardless of how many buttons there are.
##
## (A later follow-up briefly changed this to measure spacing from each
## button's own closest edge instead of a fixed centre-radius, to
## account for varying label widths — reverted back to this simpler
## fixed-centre-radius scheme per direct request.)
const RADIAL_RADIUS := 68.0
const RADIAL_FONT_SIZE := 13
## Follow-up request ("always Auto focus (outline in red) and Space
## hotkey the travel option when its available"): target_actions is
## always exactly [Lore, Travel] by construction (see
## CityScreen._select_location — a target is by definition never the
## location the party is already standing on), so Travel is always the
## one thing worth drawing as visually pre-focused here — the usual
## gold outline becomes this thicker red one instead, matching the same
## "focused = distinct colour" language the travel/leave-city Y/N
## confirm's own buttons already use (see CityScreen.
## CONFIRM_FOCUSED_COLOR) — CityScreen's own Space handler is what
## actually activates it (see _unhandled_input's own "travel" branch).
const RADIAL_FOCUS_OUTLINE_COLOR := Color(0.95, 0.15, 0.15, 1.0)
const RADIAL_OUTLINE_COLOR := Color(0.9, 0.8, 0.4, 0.9)

## Follow-up request ("position the POI options more cleanly around the
## markers... evenly spaced around the markers depending on the number
## of available options in the dial"): divides the FULL circle around
## the marker into (count + 1) equal wedges rather than packing buttons
## into a fixed below-marker arc — one extra wedge, always the one
## centred straight up (-90 degrees, screen convention: 90 = straight
## down), is reserved and left permanently empty for the hovered/
## selected name label that draws just above the marker (see _draw()'s
## own label block), so buttons never collide with it no matter how
## many there are. The remaining `count` wedges are what actually get a
## button, walked clockwise starting just past the reserved one — for
## count == 1 that's still dead centre at the bottom (matches this
## project's previous single-button placement exactly); count == 2
## lands very close to the old fixed 25/155 pair (symmetric, just below
## the marker); count == 3+ genuinely wraps buttons around the sides
## and bottom of the marker instead of cramming them all underneath it.
## Follow-up request ("have the shops... close at 8pm and open at 8am,
## gray out the Enter option and change it to Closed"): `out_meta`
## receives the full action dict per key (alongside `out_rects`'
## screen-space rect) so _radial_hit_at/_radial_tooltip_at can read
## "disabled"/"tooltip" back later without CityScreen having to hand
## them in through some separate channel. A disabled entry (`a.get(
## "disabled", false)`) draws with the same muted-grey fill/outline/text
## used nowhere else in this file — deliberately NOT the focus red or
## the normal gold, so "inert" reads as visually distinct from either
## "normal" or "the one Space would activate".
const RADIAL_DISABLED_OUTLINE_COLOR := Color(0.45, 0.45, 0.42, 0.8)
const RADIAL_DISABLED_TEXT_COLOR := Color(0.6, 0.6, 0.58, 0.85)

func _draw_radial_menu(cpos: Vector2, font: Font, actions: Array, out_rects: Dictionary, out_meta: Dictionary) -> void:
	var count: int = actions.size()
	if count == 0:
		return
	var wedge_deg: float = 360.0 / float(count + 1)
	for i in range(count):
		var a: Dictionary = actions[i]
		var angle_deg: float = -90.0 + wedge_deg * float(i + 1)
		var rad: float = deg_to_rad(angle_deg)
		var offset: Vector2 = Vector2(cos(rad), sin(rad)) * RADIAL_RADIUS
		var center: Vector2 = cpos + offset
		var label: String = a["label"]
		var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, RADIAL_FONT_SIZE)
		var box_size: Vector2 = text_size + Vector2(24.0, 14.0)
		var box_rect := Rect2(center - box_size / 2.0, box_size)

		## Same dark-fill/light-outline language as the marker rings, so
		## these read as part of the same UI system rather than a
		## different widget style bolted on — except the auto-focused
		## Travel button (red outline) and a disabled button (muted grey
		## outline + text, see this function's own header comment).
		var is_focused: bool = a.get("key", "") == "travel"
		var is_disabled: bool = a.get("disabled", false)
		draw_rect(box_rect, Color(0.08, 0.07, 0.06, 0.92))
		var outline_color: Color = RADIAL_DISABLED_OUTLINE_COLOR if is_disabled else (RADIAL_FOCUS_OUTLINE_COLOR if is_focused else RADIAL_OUTLINE_COLOR)
		draw_rect(box_rect, outline_color, false, 3.0 if is_focused else 2.0)

		var text_color: Color = RADIAL_DISABLED_TEXT_COLOR if is_disabled else Color(1, 0.95, 0.85)
		var text_pos := Vector2(center.x - text_size.x / 2.0, center.y + text_size.y * 0.32)
		draw_string_outline(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, RADIAL_FONT_SIZE, 3, Color(0, 0, 0, 0.9))
		draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, RADIAL_FONT_SIZE, text_color)

		## Screen-space hit rect for _gui_input, same conversion as
		## _marker_screen_rects (draw_set_transform only affects drawing,
		## not our own bookkeeping — box_rect above is content-space).
		var screen_center: Vector2 = pan_offset + center * zoom_level
		var screen_size: Vector2 = box_size * zoom_level
		out_rects[a["key"]] = Rect2(screen_center - screen_size / 2.0, screen_size)
		out_meta[a["key"]] = a
