extends Control
class_name BattleGridView
## Combat Encounter rework: renders the real BattleGrid (walkable vs
## impassable squares) plus every living combatant's own token, and
## reports clicks back to FieldEncounterScreen via the square_clicked
## signal — used for Move/Run destination picking. Deliberately dumb:
## this node owns no combat state of its own, just draws whatever
## grid/positions/highlight set is handed to it and reports raw clicks;
## FieldEncounterScreen decides what a click means.

signal square_clicked(square: Vector2i)
## Per the request: right-click sets (or, on a highlighted square that's
## already the current waypoint anchor, effectively re-confirms) a
## waypoint mid-move — a corner the path is locked to go through — without
## committing the move itself, which only ever happens on a real left
## click (see square_clicked). Same Vector2i(-1, -1)-means-"outside the
## grid" convention as square_clicked; FieldEncounterScreen ignores that.
signal square_right_clicked(square: Vector2i)
## Per the request: a live arrow/path preview while choosing a Move
## destination needs to know which square the mouse is currently over —
## emitted on every MouseMotion inside the grid, and with
## Vector2i(-1, -1) when the mouse is outside the grid bounds or leaves
## this control entirely (see mouse_exited in _ready()), so
## FieldEncounterScreen can clear the preview rather than leaving it
## stuck on the last real square.
signal square_hovered(square: Vector2i)

## Combat Encounter rework, Phase 2: "zoom the battle map so it fills
## the entire central window" — the grid used to render at a fixed
## SQUARE_PX=20 (600x360px) inside a ScrollContainer, so on any wider
## screen it sat in a small box with wasted space around it. Now the
## square size is computed fresh every draw from this control's actual
## current `size` (min of width/DEFAULT_VIEW_COLS and
## height/DEFAULT_VIEW_ROWS, so squares stay square), and
## FieldEncounter.tscn no longer wraps this in a ScrollContainer — it
## just fills CenterCol directly (size_flags horizontal/vertical = 3).
## A small minimum size keeps the very first layout pass (before the
## container has assigned real space) from drawing at 0px.
const MIN_SIZE := Vector2(300, 180)

## Per the follow-up request ("make the Battle around 50% larger
## vertically and horizontally, but keep the default zoom level to the
## current 30x18 cells so Player has to zoom out to see the whole map by
## default"): _square_px() below fits THIS reference window — the
## original 30x18 dimensions — into the control's own rect at
## zoom_level 1.0, independent of the real (now larger, see
## BattleGrid.COLS/ROWS) battlefield size. So the default view still
## shows squares at the same on-screen size as before the enlargement,
## and the actual map simply spills past the viewport edges at zoom 1.0
## until the player zooms out (ZOOM_LEVELS' own 0.6667 entry exactly
## fits the whole enlarged map, the same way 1.0 used to) or pans around.
const DEFAULT_VIEW_COLS := 30
const DEFAULT_VIEW_ROWS := 18

## Per the request ("allow SHIFT+mouse wheel to zoom the battle map by
## x2/4/8, SHIFT+left mouse button drag moves it around while zoomed"):
## the whole grid+token+FX drawing is rendered into an unscaled "content
## space" of size `size` (this control's own current rect, same as
## every function above already assumes), then uniformly scaled by
## `zoom_level` and shifted by `pan_offset` at render time — via
## draw_set_transform() for this Control's own _draw() calls, and via
## fx_layer's own `scale`/`position` (a plain Node2D, so those actually
## do something, unlike a Control whose container would otherwise fight
## over `position`) for the attack-FX children. Every function that
## converts between screen pixels and grid squares (_square_at, and
## anything reading raw event.position) has to invert this same
## transform — see _square_at().
## The leading 0.6667 entry is new (per the follow-up request above) —
## exactly DEFAULT_VIEW_COLS / BattleGrid.COLS (30/45), so it fits the
## whole now-larger map into the viewport in one step, the same "whole
## map visible" feel 1.0 used to give before the enlargement.
## Per the request ("lets let camera zoom on all screens which have it
## have smoother and finer zoom scaling"): the old ZOOM_LEVELS table
## only offered 5 discrete stops (2x jumps between most of them —
## 1.0 -> 2.0 -> 4.0 -> 8.0), so anything in between (e.g. 1.3x) was
## simply unreachable. Replaced with continuous exponential zoom — same
## MIN_ZOOM/MAX_ZOOM endpoints the old table had (0.6667/8.0), so
## nothing that depended on those specific bounds changes behavior, but
## every float in between is now reachable via a dozen or so small
## ticks instead of one or two big jumps. See _handle_zoom_wheel() below.
const MIN_ZOOM := 0.6667
const MAX_ZOOM := 8.0
const ZOOM_STEP_FACTOR := 1.06   ## ~6% per wheel tick
var zoom_level: float = 1.0
var pan_offset: Vector2 = Vector2.ZERO
## Per the request ("follow it if its a Enemy and its moving, slow down
## the visible moving a bit"): the one live tween driving an eased camera
## pan (see center_on_animated below). Kept as a single tracked instance
## so a new follow request started before the previous one finishes
## (a fast monster taking several moves in a row) cleanly replaces it
## instead of two tweens fighting over pan_offset at once.
var _camera_follow_tween: Tween = null
## True from a SHIFT+left-button press until that same button releases —
## while true, mouse motion pans instead of doing anything else, and the
## eventual release is consumed rather than read as a square click (see
## _gui_input). Not gated on zoom_level at press time so a drag that
## starts somewhere panning would currently be a no-op (see _clamp_pan —
## whichever axis the content doesn't overflow on) doesn't suddenly
## start "clicking through" if the player zooms in/out mid-drag.
var _is_panning: bool = false

## Follow-up request ("allow zoomable maps to be dragged with left
## click... or in move mode" — move mode is the one named exception,
## since every click there needs to land precisely and immediately on
## the intended square rather than risk being eaten by a drag-to-pan
## threshold): outside that mode, a plain left-press no longer commits
## a square click right away — same deferred click/pan pattern as
## CityMapView's own _gui_input (see that file for the fuller
## rationale). FieldEncounterScreen sets this Callable once, right
## after instancing this view, to `Callable(self, "_is_move_mode_active")`
## (or equivalent) — a live poll rather than a pushed flag, so this
## view doesn't depend on every one of the screen's several
## `move_mode_active = false` reset sites (turn-start resets, etc.)
## remembering to also notify it.
var suppress_left_click_pan: Callable = Callable()
var _click_pending: bool = false
var _click_candidate_square: Vector2i = Vector2i(-1, -1)
var _press_pos: Vector2 = Vector2.ZERO
const DRAG_CLICK_THRESHOLD := 6.0

func _left_click_pan_suppressed() -> bool:
	return suppress_left_click_pan.is_valid() and suppress_left_click_pan.call()

var grid: BattleGrid = null
var positions: Dictionary = {}   ## Character -> Vector2i
var current_turn_character: Character = null
var highlighted: Dictionary = {}   ## Vector2i -> true, valid Move/Run destinations
var selected_target: Character = null
## Per the request: each token now shows a real icon (monster art or
## the player's own current wound-tier portrait) with a health bar
## above it and a name tag below — both built fresh by
## FieldEncounterScreen every render (see _render_turn_order_panel)
## and hint no combat state of their own here, same as everything else
## this view draws.
var icons: Dictionary = {}   ## Character -> Texture2D
var icon_modulates: Dictionary = {}   ## Character -> Color, optional per-token tint (see set_state)
var names: Dictionary = {}   ## Character -> String (full character_name, including any disambiguation number)
## Day/night & light-source-in-combat request: whether the battle map
## should paint its own darkness tint at all, and the {"pos", "radius"}
## light sources punching lit holes through it — see set_state()'s own
## comment. Both pushed fresh every render, same as everything else here.
var battle_dark_active: bool = false
var dark_light_sources: Array = []
## A dark, slightly-blue-black semi-transparent wash painted over any
## square not within reach of a light source — deliberately translucent
## rather than solid black so terrain/obstacles/cover underneath still
## read through it, just dimmed, the same "you can still make out
## shapes in the dark" feel Overworld's own NightOverlay goes for.
const DARKNESS_TINT_COLOR := Color(0.02, 0.02, 0.06, 0.8)
## Per the request: the single Move action now previews an arrow from
## the mover's current square to wherever the mouse is pointing, capped
## at however far they can actually go — FieldEncounterScreen truncates
## the path to the remaining movement budget before handing it here, so
## this just draws whatever it's given, same "dumb renderer" convention
## as `highlighted` above. Vector2i entries, in order from (but not
## including) the mover's own square.
var preview_path: Array = []
## Per the request ("highlight the targeted square clearly while
## choosing a destination"): the single square the arrow currently ends
## on — drawn with its own distinct marker on top of the plain
## reachable-squares tint, so the exact destination a click would commit
## to doesn't get lost among every other highlighted square. Green when
## `hover_target_valid` (a real click here would commit), red when not
## (e.g. out of remaining movement) — Vector2i(-1, -1) draws nothing.
var hover_target: Vector2i = Vector2i(-1, -1)
var hover_target_valid: bool = false

## Per the request ("show a secondary arrow when character moves within
## charge range of any enemy target"): every enemy square that would
## become chargeable from the current Move-preview hover square — set
## every hover via set_charge_preview(), same "dumb renderer" convention
## as `preview_path`/`hover_target` above. Drawn as its own distinct red
## arrow from `charge_preview_origin` (the hover square, not the mover's
## real current square — see FieldEncounterScreen._charge_range_targets_from)
## to each listed enemy square, so it reads as "moving here sets up a
## Charge on that target" rather than competing with the yellow Move
## arrow that already runs from the mover's real square.
var charge_preview_targets: Array = []
var charge_preview_origin: Vector2i = Vector2i(-1, -1)

## Per the follow-up request ("if the active character is within charge
## range of the selected target draw a Red arrow line from that
## character to the target"): the currently selected target's own
## square, or Vector2i(-1, -1) when no Charge is currently available —
## set every time FieldEncounterScreen recomputes its own can_charge
## (see set_charge_ready below), same "dumb renderer" convention as
## everything else in this file. Unlike charge_preview_targets above
## (which previews charging from a hypothetical Move destination), this
## draws from the mover's real, current square — "you could Charge
## right now, without moving at all."
var charge_ready_target: Vector2i = Vector2i(-1, -1)

## Free-target AoE spell/prayer targeting (Blast, Twin-tailed Comet):
## every square the effect would hit if confirmed at the current hover
## square — set every hover via set_aoe_preview(), same "dumb renderer"
## convention as `highlighted`/`preview_path`. Drawn in its own distinct
## color so it doesn't get confused with Move's reachable-squares tint
## (the two never overlap in practice, but the color still needs to
## read as "a different kind of highlight" at a glance).
var aoe_preview: Dictionary = {}   ## Vector2i -> true

## Ground Fire visual — every square any currently-active
## persistent_aoe_hazard covers (Great Fires of U'Zhul, Firewall),
## unioned across all of them. Same "dumb renderer" convention as
## aoe_preview above: FieldEncounterScreen recomputes the union and
## passes it to set_state() every time battle state changes; this view
## just draws whatever it was handed, with no knowledge of hazards,
## damage, or Rounds-remaining. Also drives _process()'s own continuous
## queue_redraw() below, since the flame needs to keep animating between
## real state changes, not just redraw once per action.
var ground_fire_squares: Array = []

## Smoke Breath visual — every square any currently-active
## FieldEncounterScreen.active_smoke_clouds entry covers, unioned across
## all of them. Same "dumb renderer" convention as ground_fire_squares
## just above: this view has no idea what a smoke cloud even is, it just
## draws whatever squares it's handed. Also drives _process()'s own
## continuous queue_redraw(), alongside ground_fire_squares, so the
## smoke's own drift animation keeps playing between real state changes.
var smoke_squares: Array = []

## Ranged Attack / single-target Magic-Prayer targeting (per the
## request): once the player's clicked Attack/Cast/Pray for a ranged
## effect (not self, not AoE, not a "Special"-targeting spell), an
## arrow is drawn from them to EVERY currently valid (in-range) target
## at once — set by set_target_arrows(), same "dumb renderer"
## convention as the fields above. Any of the arrowed targets is
## directly clickable regardless of focus below.
var target_arrows: Array = []   ## Vector2i squares of currently valid targets

## Per the follow-up request ("do not lock in the pre-selected target
## right away, instead allow user to target freely, like when
## moving"): which one of `target_arrows` is currently under the
## cursor — set live on every hover via set_target_focus(), same idea
## as Move's own hover_target preview. Vector2i(-1, -1) means nothing's
## focused yet (nothing hovered since targeting mode opened). Drawn
## with its own crosshair reticle and a floating "distance — range
## band [+ modifiers]" readout instead of the plain outline every other
## valid target still gets, so the player can freely look around the
## full option set before ever committing to one with a real click.
## Per the follow-up request ("add cover -xx (in red) after the range
## +/-xx modifier label... and any other known test modifiers too"):
## an Array of {"text": String, "color": Color (optional)} segments
## (see FieldEncounterScreen._ranged_target_readout) instead of a plain
## String, so the base range readout and each modifier can be drawn in
## their own color rather than one flat line — see _draw()'s own
## target_focus_square block for how these are laid out.
var target_focus_square: Vector2i = Vector2i(-1, -1)
var target_focus_segments: Array = []

## Per the request ("add battle map animated attack gfx to Melee/
## Ranged and Magic/Pray rolls"): a dedicated Node2D child, always the
## LAST child added, so every transient attack effect (slash, block
## spark, projectile, explosion, floating damage number) renders on
## top of the plain grid/token drawing above — Godot draws a
## CanvasItem's children after its own _draw() commands, in sibling
## order, so nothing extra is needed to keep FX above the grid besides
## adding this after everything else. Positions passed to the public
## play_*_fx() functions below are grid squares; _square_center_px()
## converts them into this same local-pixel space _draw() already uses
## for token centers, so FX lines up with wherever a token actually is
## drawn regardless of the current zoom-to-fit square size.
var fx_layer: Node2D

## Per the request ("hovering over any character or monster on the
## battle map should bring up a small tooltip box with their vital
## stats"): a real Control, not a _draw()-time overlay like the ranged-
## target readout above — a background box is much simpler to get right
## as an actual PanelContainer than by hand-drawing a rect behind
## draw_string calls. Added as this control's own child (after
## fx_layer, so it paints on top of both the canvas-drawn grid and the
## FX layer) rather than routed through FieldEncounterScreen's node
## tree — this control already owns all the screen-space math
## (_last_hover_mouse_pos below is in the exact same local coordinate
## space _gui_input's MouseMotion events already arrive in, untouched
## by the zoom/pan transform that only affects _draw()/fx_layer), so
## there's nothing to convert.
var _hover_tooltip: PanelContainer
var _hover_tooltip_vbox: VBoxContainer
var _last_hover_mouse_pos: Vector2 = Vector2.ZERO

## Preloaded once — every attack this whole encounter plays reuses the
## same six AudioStream resources rather than loading from disk each
## time. The WAV files under assets/audio/sfx/ are procedurally
## synthesized 8-bit-style SFX (short square-wave/noise bursts with a
## simple envelope) rather than fetched art/audio, matching this
## project's "no external assets beyond what's already here" convention
## for its battle map.
const SFX_SLASH := preload("res://assets/audio/sfx/sfx_slash.wav")
const SFX_BLOCK := preload("res://assets/audio/sfx/sfx_block.wav")
const SFX_RANGED_HIT := preload("res://assets/audio/sfx/sfx_ranged_hit.wav")
const SFX_RANGED_MISS := preload("res://assets/audio/sfx/sfx_ranged_miss.wav")
const SFX_MAGIC_MISSILE := preload("res://assets/audio/sfx/sfx_magic_missile.wav")
const SFX_EXPLOSION := preload("res://assets/audio/sfx/sfx_explosion.wav")
## The Goblin Fort Dungeon's own chest marker — same art the original
## overworld chest tile used (see grid.chest_marker_pos's own comment).
const CHEST_TEXTURE := preload("res://assets/sprites/monster_chest.png")

## Room Furniture ("Sewer/Cave Dungeons update") — same generated-art
## convention as CHEST_TEXTURE above, one sprite per furniture_markers
## "type" string (see grid.furniture_markers' own declaration comment).
const FURNITURE_TEXTURES := {
	"weapon_rack": preload("res://assets/sprites/furniture_weapon_rack.png"),
	"cupboard": preload("res://assets/sprites/furniture_cupboard.png"),
	"alchemy_table": preload("res://assets/sprites/furniture_alchemy_table.png"),
	"torture_rack": preload("res://assets/sprites/furniture_torture_rack.png"),
}

## Ground Fire visual (persistent_aoe_hazards — Great Fires of U'Zhul,
## Firewall; see FieldEncounterScreen.persistent_aoe_hazards' own
## declaration comment): real generated flame art (produced with an
## image tool, not hand-drawn vector shapes — an earlier hand-coded
## polygon version couldn't match a real reference no matter how much
## it was tuned), chroma-keyed to a transparent background and
## normalized to a shared bottom-anchored canvas so the 6 frames don't
## jump around when flipped between. Drawn at REAL_FLAME_OPACITY so the
## scorched ground tint/border underneath (see the "real_art" style's
## _draw_region_overlay call, mirrored below for the real hazard) still
## reads through the flame, and scaled down to REAL_FLAME_SCALE tile-
## widths per two follow-up size tweaks. See assets/fx/flame_ground/.
const REAL_FLAME_FRAMES: Array[Texture2D] = [
	preload("res://assets/fx/flame_ground/ground_fire_frame_1.png"),
	preload("res://assets/fx/flame_ground/ground_fire_frame_2.png"),
	preload("res://assets/fx/flame_ground/ground_fire_frame_3.png"),
	preload("res://assets/fx/flame_ground/ground_fire_frame_4.png"),
	preload("res://assets/fx/flame_ground/ground_fire_frame_5.png"),
	preload("res://assets/fx/flame_ground/ground_fire_frame_6.png"),
]
const REAL_FLAME_FPS := 9.0
const REAL_FLAME_OPACITY := 0.6
const REAL_FLAME_SCALE := 1.215

## Smoke Breath visual (FieldEncounterScreen.active_smoke_clouds — the
## "Breath" spell's Shadow Lore type; see that var's own declaration
## comment): same real-generated-art pipeline as REAL_FLAME_FRAMES above
## (Gemini, chroma-keyed transparent), but the source art is already
## achromatic (grey/white smoke has no real hue of its own), so instead
## of trying to perfectly un-blend a magenta-spill fringe at the edges,
## every pixel was simply desaturated to its own luminance during
## chroma-keying — any leftover background contamination on a semi-
## transparent edge pixel becomes a slightly off grey instead of a
## visible magenta/purple ring. Normalized to a shared CENTER-anchored
## canvas (not bottom-anchored like the flame) since a lingering smoke
## cloud floats over the whole tile rather than standing on the ground
## from one base point. See assets/fx/smoke_ground/.
const REAL_SMOKE_FRAMES: Array[Texture2D] = [
	preload("res://assets/fx/smoke_ground/smoke_ground_frame_1.png"),
	preload("res://assets/fx/smoke_ground/smoke_ground_frame_2.png"),
	preload("res://assets/fx/smoke_ground/smoke_ground_frame_3.png"),
	preload("res://assets/fx/smoke_ground/smoke_ground_frame_4.png"),
	preload("res://assets/fx/smoke_ground/smoke_ground_frame_5.png"),
	preload("res://assets/fx/smoke_ground/smoke_ground_frame_6.png"),
	preload("res://assets/fx/smoke_ground/smoke_ground_frame_7.png"),
	preload("res://assets/fx/smoke_ground/smoke_ground_frame_8.png"),
]
const REAL_SMOKE_FPS := 4.0   ## slower than fire's flicker -- smoke drifts, it doesn't flare
const REAL_SMOKE_OPACITY := 0.7
const REAL_SMOKE_SCALE := 1.55   ## bigger than the flame -- a smoke cloud should overhang its own tile a little, reading as one continuous haze once several tiles are covered

## Battlefield obstacle art (per the request: "update the battle map
## (non dungeon) tile art... create new ones for the obstacles like
## wagon, house, high grass etc") — same Gemini-generated, chroma-keyed
## real-art pipeline as the flame/smoke effects above, but static (no
## animation frames — these are terrain features, not VFX) and, unlike
## the effects' painterly/photographic style, drawn in this project's
## own flat cel-shaded icon style (the same style already established
## for UI/furniture icons — see FURNITURE_TEXTURES) since that's what
## actually suits a discrete battlefield prop. Per the explicit
## follow-up request ("make the structure wooden"), Structure's own
## art is a timber-framed wooden building, not stone/brick. Tree/Bush/
## HighGrass/Fence/Pond are drawn once per occupied square (see
## _draw_obstacle_detail(), same call site the old hand-drawn shapes
## used — Pond moved here per a later follow-up, and later still moved
## again onto the same tileset.png art OverworldMap's own lakes use, see
## _resolve_water_shore_atlas()'s own comment); Boulder/BrokenCart/
## Structure are drawn once per whole instance, stretched across its
## full footprint (see _draw_obstacle_detail_stretched()) — same two-
## tier split the old vector version already used, just real art
## instead of shapes now.
const OBSTACLE_TREE_TEX: Texture2D = preload("res://assets/fx/obstacles/tree.png")
const OBSTACLE_BUSH_TEX: Texture2D = preload("res://assets/fx/obstacles/bush.png")
const OBSTACLE_HIGHGRASS_TEX: Texture2D = preload("res://assets/fx/obstacles/high_grass.png")
const OBSTACLE_BOULDER_TEX: Texture2D = preload("res://assets/fx/obstacles/boulder.png")
## Pond's own art lives with the ground-tile system further below (see
## WATER_SHALLOW_ATLAS and _resolve_water_shore_atlas()) rather than
## here as a preloaded sprite — per the follow-up request "can we use
## the overworld water instead and use all the edging already built for
## those", it's drawn straight from tileset.png, the same atlas the
## ground tiles above already sample.
const OBSTACLE_BROKEN_CART_TEX: Texture2D = preload("res://assets/fx/obstacles/broken_cart.png")
const OBSTACLE_STRUCTURE_TEX: Texture2D = preload("res://assets/fx/obstacles/structure.png")
## A single post-to-post repeat unit — cropped from the middle of a
## wider generated strip that had several posts across it, at exactly
## the pitch between two post centers, so tiling it edge-to-edge (see
## _draw_fence_detail()'s per-square draw) lines every post up evenly
## with no visible seam. Authored for an EAST-WEST run only (see
## OBSTACLE_FENCE_VERTICAL_TEX for the north-south counterpart).
const OBSTACLE_FENCE_TEX: Texture2D = preload("res://assets/fx/obstacles/fence.png")
## Per the follow-up request ("the vertical fence have be more of a top
## down look and fit together nicely with the horizontal one"): a
## dedicated north-south art asset, NOT the east-west tile above simply
## rotated 90 degrees — rotating it produced a "ladder lying on its
## side" look (two rails + repeated crossbar-like posts), since
## OBSTACLE_FENCE_TEX was authored front-on for a run that crosses the
## screen, and that same front-on framing reads as broken once turned
## sideways. This is its own top-down-along-the-run art (mostly rail
## tops + post tops, foreshortened along its length, mostly generated
## in the same Gemini chat/style as the rest of assets/fx/obstacles/ —
## see the project doc for this version), post-to-post repeat unit
## already cropped/chroma-keyed the same way as the tile above, and
## its post style/wood tone was iterated against the east-west tile
## specifically so a corner square (drawing both, see
## _draw_fence_detail()) reads as one continuous fence rather than two
## mismatched pieces.
const OBSTACLE_FENCE_VERTICAL_TEX: Texture2D = preload("res://assets/fx/obstacles/fence_vertical.png")
## Per the follow-up request ("vertical and horizontal fences need to
## connect cleanly post to post, lets rework those"): a dedicated corner
## piece for the single square where a Fence run bends a right angle (see
## BattleGrid's own Fence shape comment — a Fence is always straight or
## bent exactly once, so this ONE asset plus flipping covers every corner,
## no T-junction/crossing art is ever needed). Drawing the two straight
## tiles above on top of each other at a bend square (the old approach)
## put a half-post at that square's own EDGE for each axis independently
## — the horizontal tile's post sitting at the square's left/right edge,
## the vertical tile's post sitting at its top/bottom edge — two different
## (x, y) positions, so the bend showed two disconnected post shapes
## instead of one shared post. This asset instead has a single full post
## anchored at the square's OWN CENTER (the one spot common to both a
## still-mid-rail east/west slice and a still-mid-rail north/south slice),
## with a rail stub reaching from that center post out to the east edge
## (a straight crop of OBSTACLE_FENCE_TEX's own right half, so it hands
## off to an actual east-neighbour tile's own left half-post with zero
## seam) and another stub reaching out to the south edge (same idea, a
## crop of OBSTACLE_FENCE_VERTICAL_TEX's own bottom half). Authored for
## the SE case (run continues east and south of the bend). The other
## three bend orientations are each their OWN pre-flipped file (_sw/_ne/
## _nw below) rather than one asset mirrored at draw time — a negative-
## size dest Rect2 (the same trick _draw_icon_centered()'s flip_h already
## uses for HighGrass) was tried first for both axes here and verified
## broken via a standalone probe scene: at this asset's actual on-grid
## draw size, draw_texture_rect rendered almost nothing (just a sliver at
## the rect's own anchor edge) for ANY negative-size dest Rect2, not only
## the vertical axis — so rather than depend on that engine quirk, every
## bend orientation just gets its own plain, never-flipped file.
const OBSTACLE_FENCE_CORNER_SE_TEX: Texture2D = preload("res://assets/fx/obstacles/fence_corner_se.png")
const OBSTACLE_FENCE_CORNER_SW_TEX: Texture2D = preload("res://assets/fx/obstacles/fence_corner_sw.png")
const OBSTACLE_FENCE_CORNER_NE_TEX: Texture2D = preload("res://assets/fx/obstacles/fence_corner_ne.png")
const OBSTACLE_FENCE_CORNER_NW_TEX: Texture2D = preload("res://assets/fx/obstacles/fence_corner_nw.png")

## Per the request ("add visual markers for conditions on each
## combatant"): a small icon glyph + tint per named Condition, drawn in
## a row above each token's own HP bar — see the per-token draw loop
## below for how this is actually used. Same "plain Unicode glyph drawn
## via draw_string, no bespoke art asset" convention this project
## already relies on elsewhere (the Light spell's own turn-order row
## uses "💡", the ally/adversary side markers use "🛡"/"☠", Victory
## notices use "★" — all rendered the exact same way, through this
## project's own shared default font's fallback glyphs). Deliberately
## covers only the 10 Conditions actually named in the request; any
## other Condition this project tracks (Unconscious, In-Fighting, ...)
## already has its own dedicated treatment elsewhere (Unconscious's own
## red X across the whole token, just below) or has no live visual
## trigger to hook into, so it's left out of this row rather than
## guessed at.
## Real fix, found via an actual in-game screenshot taken to verify this
## feature (see condition_markers_advantage_reset_v0.3.74.md): three of
## the original glyph picks didn't survive contact with this project's
## real font — "👁" and "🏳" drew as plain missing-glyph tofu boxes (no
## fallback glyph for either codepoint at all), and "💧" turned out to be
## a full-color bitmap glyph that silently ignores draw_string's own
## color argument, so Bleeding rendered as a blue droplet instead of red
## and read as "water," not blood. All three replaced with glyphs
## confirmed (by the same screenshot technique) to actually render, and
## to still read clearly at the small size these draw at on a token:
## "🙈" (a monkey literally covering its own eyes) for Blinded, "😱" (the
## classic fear-stricken face) for Broken — WFRP's own Broken Condition
## means fleeing in terror, which this reads as directly — and a plain
## "🔴" for Bleeding, which is inherently red regardless of whatever
## draw_string's color argument does or doesn't do to it.
const CONDITION_ICONS := {
	"Ablaze": {"glyph": "🔥", "color": Color(1.0, 0.45, 0.15)},
	"Bleeding": {"glyph": "🔴", "color": Color(0.85, 0.1, 0.1)},
	"Stunned": {"glyph": "💫", "color": Color(0.95, 0.9, 0.5)},
	"Prone": {"glyph": "⬇", "color": Color(0.75, 0.6, 0.4)},
	"Broken": {"glyph": "😱", "color": Color(0.9, 0.9, 0.9)},
	"Blinded": {"glyph": "🙈", "color": Color(0.5, 0.5, 0.55)},
	"Fatigued": {"glyph": "💤", "color": Color(0.55, 0.65, 0.85)},
	"Poisoned": {"glyph": "☣", "color": Color(0.45, 0.85, 0.25)},
	"Surprised": {"glyph": "❗", "color": Color(0.95, 0.85, 0.2)},
	"Deafened": {"glyph": "👂", "color": Color(0.6, 0.6, 0.6)},
}
## Fixed draw order, independent of Dictionary iteration order (which
## GDScript doesn't guarantee stays stable across engine versions) — so
## a combatant suffering several Conditions at once always shows them in
## the same left-to-right order every time, rather than shuffling frame
## to frame or build to build.
const CONDITION_ICON_ORDER: Array[String] = [
	"Ablaze", "Bleeding", "Poisoned", "Stunned", "Prone", "Broken",
	"Blinded", "Deafened", "Fatigued", "Surprised",
]

## Builds the ordered list of {"text": String, "color": Color} markers to
## draw for `c` right now — split out from the per-token _draw() loop so
## it's a plain, testable function with no dependency on this being an
## actual live CanvasItem. One entry per Condition in CONDITION_ICON_ORDER
## that `c` currently has: just the bare glyph for a Condition at 0 or 1
## stack (e.g. Surprised, which is never stacked), or the glyph plus its
## own stack count (e.g. "🔥2") once it's genuinely stacked — matching how
## the reference markers showed a numbered badge per icon. Empty for a
## combatant suffering none of these ten Conditions right now.
func _condition_markers_for(c: Character) -> Array:
	var markers: Array = []
	for cond_name in CONDITION_ICON_ORDER:
		if not c.conditions.has(cond_name):
			continue
		var stacks: int = int(c.conditions.get(cond_name, 0))
		var icon_def: Dictionary = CONDITION_ICONS[cond_name]
		var text: String = ("%s%d" % [icon_def["glyph"], stacks]) if stacks > 1 else icon_def["glyph"]
		markers.append({"text": text, "color": icon_def["color"]})
	return markers

func _ready() -> void:
	custom_minimum_size = MIN_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	## Container layout can resize this control at any time (window
	## resize, side panels changing width) — redraw whenever that
	## happens so the grid always fills the current space, not just
	## whatever size it happened to be at _ready(). Also re-clamps
	## pan_offset (see _clamp_pan) since it's derived from `size`, and
	## keeps fx_layer's transform in sync with it.
	resized.connect(_on_resized)
	## The mouse can leave this control's rect between two MouseMotion
	## events with nothing else firing in between — without this, the
	## last real square_hovered square (and thus the arrow preview)
	## would stick around after the cursor's actually left the map.
	mouse_exited.connect(func(): square_hovered.emit(Vector2i(-1, -1)))
	fx_layer = Node2D.new()
	fx_layer.name = "FxLayer"
	add_child(fx_layer)
	_build_hover_tooltip()

## Keeps redrawing every frame ONLY while a real ground fire hazard is
## on screen, so _draw_ground_fire_tile()'s own frame-flipping animation
## actually animates — nothing else in this file needs a continuous
## per-frame redraw (every other overlay only changes on a real state
## change and calls queue_redraw() itself right then).
func _process(_delta: float) -> void:
	if not ground_fire_squares.is_empty() or not smoke_squares.is_empty():
		queue_redraw()

## Built once — see _hover_tooltip's own declaration for why this is a
## real Control rather than a _draw()-time overlay.
func _build_hover_tooltip() -> void:
	_hover_tooltip = PanelContainer.new()
	_hover_tooltip.visible = false
	## Never eats the mouse itself — it floats right next to the cursor,
	## which is still hovering the grid square underneath it; without
	## this, the tooltip would flicker on/off as it repeatedly steals
	## its own MouseMotion events out from under the grid.
	_hover_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.95)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.6, 0.55, 0.4)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	_hover_tooltip.add_theme_stylebox_override("panel", style)
	_hover_tooltip_vbox = VBoxContainer.new()
	_hover_tooltip_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_tooltip_vbox.add_theme_constant_override("separation", 2)
	_hover_tooltip.add_child(_hover_tooltip_vbox)
	## Added last (after fx_layer) so it paints on top of both the
	## canvas-drawn grid/tokens and any in-flight attack FX.
	add_child(_hover_tooltip)

## The current per-square pixel size, fit to whichever of this control's
## own width/DEFAULT_VIEW_COLS or height/DEFAULT_VIEW_ROWS is smaller —
## keeps squares square. Deliberately fit against the fixed
## DEFAULT_VIEW_COLS/ROWS "reference window" rather than the real (and
## now larger, see BattleGrid.COLS/ROWS) battlefield size — see
## DEFAULT_VIEW_COLS's own comment above for why: the default zoomed-out
## view should still show squares at their original size, with the
## actual bigger map spilling past this control's edges until the player
## zooms out or pans (see _clamp_pan below, which now allows that).
func _square_px() -> float:
	if size.x <= 0.0 or size.y <= 0.0:
		return 0.0
	return min(size.x / float(DEFAULT_VIEW_COLS), size.y / float(DEFAULT_VIEW_ROWS))

## Top-left pixel offset that centers the (square_px * COLS x
## square_px * ROWS) grid within this control's own current rect —
## whichever axis has leftover space (or, now that square_px is fit
## against the smaller DEFAULT_VIEW_COLS/ROWS reference window instead of
## the real grid size, whichever axis OVERFLOWS) gets it split evenly on
## both sides rather than the grid sitting flush in a corner — so at the
## default zoom the visible window centers on the middle of the map
## rather than its top-left corner.
func _grid_origin(square_px: float) -> Vector2:
	var g_cols: int = grid.cols if grid != null else BattleGrid.COLS
	var g_rows: int = grid.rows if grid != null else BattleGrid.ROWS
	var grid_size := Vector2(square_px * g_cols, square_px * g_rows)
	return (size - grid_size) / 2.0

func _gui_input(event: InputEvent) -> void:
	## Per the request: SHIFT+wheel zooms — handled first and consumed
	## outright, before anything below can read the same event as a
	## click/hover.
	if event is InputEventMouseButton and event.pressed and event.shift_pressed \
			and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		_handle_zoom_wheel(event.button_index == MOUSE_BUTTON_WHEEL_UP, event.position)
		return
	## SHIFT+left-button press starts a pan drag instead of a square
	## click; the matching release just ends the drag. Both consumed
	## here so the click-handling block further down never sees them.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.shift_pressed:
				_is_panning = true
				_click_pending = false
				return
			if _left_click_pan_suppressed():
				## Move mode (or any other mode the screen flags via
				## suppress_left_click_pan) — keep the old immediate,
				## no-drag-consideration click behavior exactly as before
				## this feature existed.
				var square := _square_at(event.position)
				if square != Vector2i(-1, -1):
					square_clicked.emit(square)
				return
			## Plain left-press outside a suppressed mode: defer the
			## click — see suppress_left_click_pan's own declaration
			## comment above for the full rationale. Resolved on release
			## (a real click) or converted to a pan by the MouseMotion
			## branch below if the player drags past the threshold.
			_press_pos = event.position
			_click_candidate_square = _square_at(event.position)
			_click_pending = true
			return
		else:
			if _is_panning:
				_is_panning = false
				return
			if _click_pending:
				_click_pending = false
				if _click_candidate_square != Vector2i(-1, -1):
					square_clicked.emit(_click_candidate_square)
				return
	if event is InputEventMouseMotion:
		if _is_panning:
			pan_offset += event.relative
			_clamp_pan()
			_sync_fx_layer_transform()
			queue_redraw()
			return
		if _click_pending:
			if event.position.distance_to(_press_pos) > DRAG_CLICK_THRESHOLD:
				_click_pending = false
				_is_panning = true
				pan_offset += event.relative
				_clamp_pan()
				_sync_fx_layer_transform()
				queue_redraw()
			return
		## Raw, untransformed local position — same space set_hover_tooltip()
		## positions the tooltip in, so no zoom/pan conversion is needed
		## there (see _hover_tooltip's own declaration).
		_last_hover_mouse_pos = event.position
		var square := _square_at(event.position)
		square_hovered.emit(square)   ## Vector2i(-1, -1) from _square_at() when out of bounds — see square_hovered's own comment
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_RIGHT:
		return
	var square := _square_at(event.position)
	if square == Vector2i(-1, -1):
		return
	square_right_clicked.emit(square)

## Steps zoom_level continuously (ZOOM_STEP_FACTOR per wheel tick,
## clamped to [MIN_ZOOM, MAX_ZOOM]), keeping whatever content point was
## under the cursor at the moment of the scroll fixed on screen — the
## same "zoom toward the cursor" feel any map/image viewer gives, rather
## than always zooming around the grid's top-left corner. `mouse_pos` is
## the raw (pre-transform) event.position from the wheel event.
func _handle_zoom_wheel(zoom_in: bool, mouse_pos: Vector2) -> void:
	var old_zoom := zoom_level
	var new_zoom: float = clampf(zoom_level * (ZOOM_STEP_FACTOR if zoom_in else 1.0 / ZOOM_STEP_FACTOR), MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, old_zoom):
		return
	pan_offset = mouse_pos - (mouse_pos - pan_offset) * (new_zoom / old_zoom)
	zoom_level = new_zoom
	_clamp_pan()
	_sync_fx_layer_transform()
	queue_redraw()

## Per the request ("make zooming out easier, right now it gets stuck on
## the edges and its difficult to pan around, have the map float in the
## middle and allow it to go over the edge of the map when panning/
## zoom"): this used to be a hard "no blank space, ever" clamp — a
## content point `p` (already including _grid_origin's own centering
## offset) maps to screen point `pan_offset + zoom_level * p`, and the
## old clamp forced pan_offset to keep the rendered content fully
## covering this control's own `size` on any axis the content
## overflowed, with panning locked to exactly 0 (dead center, no
## movement at all) on any axis the content didn't overflow. That's
## what read as "stuck on the edges": the instant a drag reached the
## tight boundary — which, at any zoom level close to fitting the
## viewport, is only a few pixels of travel — panning simply stopped
## dead, and at zoom levels where the map fit entirely (e.g. the
## default 0.6667) panning was disabled outright.
##
## Now each axis gets a generous overscroll allowance (half this
## control's own current size) added on both ends of that same
## "fully covers" range, so the map can always be dragged some real
## distance — floating freely around its centered default rather than
## snapping to a wall — and can be pushed far enough to show blank
## space past its own edges on any axis, at any zoom level, instead of
## being pinned. BattleGridView's own clip_contents (see FieldEncounter.
## tscn) keeps that blank overscroll region from ever painting over the
## neighboring Combat Log/Turn Order panels. Still bounded (not
## infinite), so a wild drag/zoom can't lose the map off in space
## forever — see OVERSCROLL_FACTOR below to retune how far.
const OVERSCROLL_FACTOR := 0.5
func _clamp_pan() -> void:
	var square_px := _square_px()
	if square_px <= 0.0:
		pan_offset = Vector2.ZERO
		return
	var grid_origin := _grid_origin(square_px)
	var g_cols: int = grid.cols if grid != null else BattleGrid.COLS
	var g_rows: int = grid.rows if grid != null else BattleGrid.ROWS
	var content_size := Vector2(square_px * g_cols, square_px * g_rows) * zoom_level
	var overscroll := size * OVERSCROLL_FACTOR
	var bound_a := Vector2(size.x - content_size.x - zoom_level * grid_origin.x, size.y - content_size.y - zoom_level * grid_origin.y)
	var bound_b := Vector2(-zoom_level * grid_origin.x, -zoom_level * grid_origin.y)
	pan_offset.x = clamp(pan_offset.x, min(bound_a.x, bound_b.x) - overscroll.x, max(bound_a.x, bound_b.x) + overscroll.x)
	pan_offset.y = clamp(pan_offset.y, min(bound_a.y, bound_b.y) - overscroll.y, max(bound_a.y, bound_b.y) + overscroll.y)

## fx_layer is a plain Node2D (not a Control), so unlike this control's
## own `position` — which a parent Container would just overwrite every
## layout pass — its `scale`/`position` actually stick, and compose
## with everything drawn under it exactly the same way draw_set_transform
## does for this control's own _draw() calls. Called after every zoom/
## pan change and on resize so attack FX (spawned in content-space
## coordinates via square_center_px()) always line up with the grid
## under the current zoom/pan.
func _sync_fx_layer_transform() -> void:
	if fx_layer == null:
		return
	fx_layer.scale = Vector2(zoom_level, zoom_level)
	fx_layer.position = pan_offset

func _on_resized() -> void:
	_clamp_pan()
	_sync_fx_layer_transform()
	queue_redraw()

## Shared pixel -> grid-square conversion for both the click handler and
## the hover-preview handler above (previously duplicated inline just
## for clicks) — returns Vector2i(-1, -1) for anything outside the
## drawn grid (including while the control hasn't been laid out yet).
## `local_pos` is raw (pre-transform) event.position; converted back
## into the same unscaled content space _draw() lays the grid out in
## before applying pan_offset/zoom_level — the inverse of _draw()'s own
## draw_set_transform() call.
func _square_at(local_pos: Vector2) -> Vector2i:
	var square_px := _square_px()
	if square_px <= 0.0:
		return Vector2i(-1, -1)
	var content_pos: Vector2 = (local_pos - pan_offset) / zoom_level
	var local: Vector2 = content_pos - _grid_origin(square_px)
	if local.x < 0.0 or local.y < 0.0:
		return Vector2i(-1, -1)
	var square := Vector2i(int(local.x / square_px), int(local.y / square_px))
	var g_cols: int = grid.cols if grid != null else BattleGrid.COLS
	var g_rows: int = grid.rows if grid != null else BattleGrid.ROWS
	if not (square.x >= 0 and square.x < g_cols and square.y >= 0 and square.y < g_rows):
		return Vector2i(-1, -1)
	return square

## Exploration mode: draws one dungeon-sourced square from its own tile
## art + fog-of-war state, entirely separate from the normal battlefield
## rendering above (obstacles/cover/mud/darkness never apply to a
## dungeon grid — its own walls/doors/light already cover the same
## ground, see grid.generate_from_dungeon_grid()'s own comment). vis 0 =
## never seen (solid black, nothing else drawn at all — an unseen wall
## Real bug fix, per the follow-up request ("hide all furniture and
## walls inside rooms until they are opened — Stairs... visible before
## opening the door right now"): the exact same "force this cell to
## read as unexplored, regardless of what fog_of_war itself says"
## override _draw_dungeon_square() already applies to the floor tile
## texture below — factored out here so every OTHER marker drawn on top
## of the floor (furniture, both chest systems, the entrance marker, and
## especially the stairs marker) can apply the identical rule. Without
## this, a marker sitting on a room's own near-face row (the door's own
## threshold row, forced black so the room can't be peeked through
## before its door opens) still drew its highlight/sprite on top of that
## forced-black floor, because each marker's own gate only ever checked
## raw fog_of_war — and a Quest room's stairs_pos (the rect corner
## farthest from its chest) can genuinely land ON that same near-face
## row whenever the door happens to sit on that same edge, which is
## exactly what let a stairs marker (and, by the same bug, potentially a
## chest/furniture piece landing in the same spot) show through a still-
## closed door. The door/wall boundary LINE itself is deliberately
## exempted from this — see _door_edge_visible()/_wall_edge_visible(),
## which intentionally keep reading raw fog_of_war so the player can
## still see there's a door there before opening it, per that earlier
## request's own explicit "still show doors and walls."
func _marker_fog(sq: Vector2i) -> int:
	if grid.closed_door_near_face_cells.has(sq):
		return 0
	return int(grid.fog_of_war.get(sq, 0))

## reads as pure void); vis 1 = explored but not currently lit (tile art
## drawn, then a dark translucent wash — the "remembered but dim" read
## fog-of-war conventionally uses); vis 2 = currently visible (tile art
## at full brightness).
func _draw_dungeon_square(rect: Rect2, sq: Vector2i) -> void:
	## Per the request ("the player can still see the first row of floor
	## tiles behind closed doors... we need to hide those until the door
	## is opened, but still show doors and walls" + its own follow-up,
	## "the floor tiles next to the grey wall lines are still visible
	## too"): a still-closed room's own whole near-face row is forced to
	## render as solid unexplored black here, WITHOUT touching
	## grid.fog_of_war itself — the door/wall threshold-line overlay
	## (_door_edge_visible() et al) reads that same fog_of_war entry to
	## decide whether to draw the door/wall line at all, so erasing it
	## there would make the door disappear too, which the request
	## explicitly says not to do. The moment the door opens,
	## closed_door_near_face_cells no longer includes its cells (rebuilt
	## by BattleGrid on the same door-open-triggered grid rebuild that
	## already existed) and the floor renders normally again.
	var vis: int = _marker_fog(sq)
	if vis <= 0:
		## Per the request ("remove the grid from the black cells round
		## the Dungeon tiles" and its own follow-up "remove the remaining
		## cell borders... bordering the dungeon tiles"): _draw() now
		## paints one single opaque backdrop across the whole dungeon
		## grid's extent before this per-square loop even starts (see its
		## own comment) — there's nothing left to draw or seam against
		## here, at any zoom level, so this is now a pure no-op.
		return
	var tex: Texture2D = grid.cell_texture.get(sq)
	if tex != null:
		draw_texture_rect(tex, rect, false)
	else:
		draw_rect(rect, Color(0, 0, 0, 1))
	if vis == 1:
		draw_rect(rect, Color(0, 0, 0, 0.55))

## Exploration mode: re-centers pan_offset so `square`'s own pixel center
## lands in the middle of this control's current rect, at the current
## zoom level — the "camera follows the party" behavior the cropped
## exploration viewport uses (see field_encounter_screen.gd's own
## _center_camera_on_party()), called every time the party moves.
## Nothing else in this file has ever needed a programmatic re-center
## before this — normal combat's own camera is purely mouse-drag panned
## (see pan_offset's own declaration) — so this is a new, additive
## capability, not a change to how panning already works.
func center_on(square: Vector2i) -> void:
	var square_px := _square_px()
	if square_px <= 0.0:
		return
	## A pending animated follow (see center_on_animated below) shouldn't
	## keep fighting an instant, deliberate re-center like this one (a
	## fresh Turn beginning, per field_encounter_screen.gd's own call
	## site) — kill it first so this snap actually sticks.
	if _camera_follow_tween != null and _camera_follow_tween.is_valid():
		_camera_follow_tween.kill()
		_camera_follow_tween = null
	var origin := _grid_origin(square_px)
	var content_point := Vector2(origin.x + (square.x + 0.5) * square_px, origin.y + (square.y + 0.5) * square_px)
	pan_offset = size / 2.0 - content_point * zoom_level
	_clamp_pan()
	_sync_fx_layer_transform()
	queue_redraw()

## Per the request ("follow it if its a Enemy and its moving, slow down
## the visible moving a bit"): same destination math as center_on above,
## but eases pan_offset there over `duration` seconds via a real Tween
## instead of snapping instantly — this deliberately unhurried pace IS
## the "slow down" the request asked for, since nothing else in this
## project animates a mover's own glide across the grid (a monster's
## move just relocates its battle_positions entry outright; see
## FieldEncounterScreen._follow_camera_on_enemy_move's own comment for
## why). Any camera-follow tween already in flight is replaced rather
## than left to finish, so a monster that moves more than once in a row
## (closing distance, then repositioning for cover) always eases toward
## its own latest square instead of finishing a stale earlier destination
## first.
func center_on_animated(square: Vector2i, duration: float = 0.9) -> void:
	var square_px := _square_px()
	if square_px <= 0.0:
		return
	var origin := _grid_origin(square_px)
	var content_point := Vector2(origin.x + (square.x + 0.5) * square_px, origin.y + (square.y + 0.5) * square_px)
	var target_offset: Vector2 = size / 2.0 - content_point * zoom_level
	if _camera_follow_tween != null and _camera_follow_tween.is_valid():
		_camera_follow_tween.kill()
	_camera_follow_tween = create_tween()
	_camera_follow_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_camera_follow_tween.tween_method(_apply_animated_pan, pan_offset, target_offset, duration)

## Per-frame callback for center_on_animated's own tween — applies one
## intermediate (or final) pan_offset value exactly the way every other
## pan_offset write in this file already does (clamp, sync the fx layer,
## redraw), so an in-flight camera-follow pan still respects the same
## bounds a manual mouse-drag pan would.
func _apply_animated_pan(p: Vector2) -> void:
	pan_offset = p
	_clamp_pan()
	_sync_fx_layer_transform()
	queue_redraw()

## True if a `footprint_size`x`footprint_size` combatant anchored at
## `pos` is within 1 square (footprint-aware, so a Large/Enormous/
## Monstrous ally's whole body counts, not just its anchor cell) of any
## currently living ally in `positions` — see the request quoted at
## the _draw() call site. A downed (0 Wounds, or Unconscious) ally
## isn't perceiving anything, so doesn't count. Standalone and static
## (reads only its own parameters, nothing from the live scene) so a
## regression test can call it directly without needing a real _draw()
## pass.
static func is_adjacent_to_living_ally(pos: Vector2i, footprint_size: int, positions: Dictionary) -> bool:
	for c in positions:
		if c.allegiance != "ally":
			continue
		if c.wounds_current <= 0 or c.conditions.has("Unconscious"):
			continue
		for ally_sq in BattleGrid.footprint_cells(positions[c], c.get_footprint_size()):
			for sq in BattleGrid.footprint_cells(pos, footprint_size):
				if BattleGrid.distance_squares(sq, ally_sq) <= 1:
					return true
	return false

func _draw() -> void:
	if grid == null:
		return
	var square_px := _square_px()
	if square_px <= 0.0:
		return
	## Per the request: everything below draws in the same unscaled
	## content space as always — this single transform is what actually
	## applies the current zoom/pan to all of it at once, rather than
	## every draw_*() call below needing its own zoom/pan math. See
	## _square_at() for the matching inverse used on input, and
	## _sync_fx_layer_transform() for how the attack-FX layer (a
	## separate node, unaffected by this) keeps up.
	draw_set_transform(pan_offset, 0.0, Vector2(zoom_level, zoom_level))
	var origin := _grid_origin(square_px)
	## Per the request ("remove the remaining cell borders on the cells
	## bordering the dungeon tiles"): a dungeon-sourced grid's own
	## unexplored (black) cells used to each draw their own individually-
	## grown rect (see _draw_dungeon_square()'s old comment, now a no-op
	## below) — seamless between two unexplored cells in raster order,
	## but leaving a 1px gap wherever an EXPLORED cell (deliberately
	## drawn 1px undersized, for its own intentional grid-line look) sat
	## next to an unexplored one, since the explored cell's own shrink
	## isn't compensated for by the unexplored neighbour's one-directional
	## growth — made worse by v0.2.539's continuous zoom, since two
	## separately-drawn rects only exactly adjacent in unscaled integer
	## math can pick up sub-pixel rounding gaps once scaled by an
	## arbitrary fractional zoom level. Fixed architecturally: paint one
	## single opaque backdrop across the whole dungeon grid's extent here,
	## once, before the per-square loop — there's nothing left for an
	## unexplored cell to seam against at any zoom level. Explored cells
	## still draw their own intentionally-undersized rect on top
	## (unchanged), so the deliberate grid line between two explored
	## floor tiles is untouched. A no-op for a normal (non-dungeon)
	## battlefield, same as _draw_dungeon_square() itself.
	if not grid.cell_texture.is_empty():
		draw_rect(Rect2(origin, Vector2(grid.cols, grid.rows) * square_px), Color(0, 0, 0, 1))
	for y in range(grid.rows):
		for x in range(grid.cols):
			var sq := Vector2i(x, y)
			var rect := Rect2(origin.x + x * square_px, origin.y + y * square_px, square_px - 1, square_px - 1)
			## Exploration mode: a dungeon-sourced grid supplies its own
			## per-square tile art (grid.cell_texture) and fog-of-war
			## state (grid.fog_of_war) — both empty/unused for a normal
			## battlefield, so this branch is a no-op there and every
			## line below it (obstacles/cover/mud/darkness) runs
			## completely unchanged for normal combat.
			if not grid.cell_texture.is_empty():
				_draw_dungeon_square(rect, sq)
				continue
			var color: Color
			var is_cover: bool = grid.is_covered(sq)
			var obstacle_here: String = grid.obstacle_type.get(sq, "")
			var solid_obstacle: bool = OBSTACLE_FILL_COLOR.has(obstacle_here)
			## Per the request ("use the updated [tile art] from the world
			## map"): plain open ground (not an obstacle, not impassable
			## terrain, not cover) now draws a real painterly tile sampled
			## from the World Map's own tileset.png — see
			## _draw_world_ground_tile() — instead of a flat colour fill.
			## Every other case (solid obstacle mass, plain impassable
			## terrain, cover) is untouched and still gets its own flat
			## colour exactly as before.
			var is_plain_ground: bool = false
			## Per the follow-up request ("when the battlemap includes a
			## large section of greyed out cells due to overworld map
			## water, fill this in with the same tiles as overworld water
			## rather then Grey tiles"): a plain impassable square (no
			## obstacle) that's ALSO one of BattleGrid's own `water`
			## squares draws real water art instead of the flat brown
			## wall/water-block colour below — see the is_water_block
			## branch further down and _is_water_square()'s own comment
			## for how this also merges visually with real Pond obstacles.
			var is_water_block: bool = false
			## Per the request ("battle map forest sections... should
			## change to be clumps of trees rather then the big square
			## with green dot tiles... lets create a new forest floor
			## tile"): a `cover` square now draws real forest-floor tile
			## art (see _draw_forest_floor_tile()'s own comment) instead
			## of the old flat colour fill below — this flag routes it
			## there the same way is_water_block routes to _draw_water_tile().
			var is_forest_floor: bool = false
			if solid_obstacle:
				## Per the follow-up request ("make detailed Tiles"): a
				## Boulder/Pond/Broken Cart/Structure fills its own whole
				## footprint with one solid base colour (see
				## OBSTACLE_FILL_COLOR) rather than showing bare ground
				## underneath — reads as one coherent mass rather than a
				## cluster of separate tiles, especially once the seamless
				## border pass below removes the grid lines between its
				## own squares.
				color = OBSTACLE_FILL_COLOR[obstacle_here]
			elif grid.impassable.has(sq) and obstacle_here == "":
				if grid.water.has(sq):
					is_water_block = true
				else:
					color = Color(0.32, 0.24, 0.16)   ## plain terrain wall block (from the encounter's own snapshot, not an obstacle)
			elif is_cover:
				## Per the request ("clumps of tree's rather then the big
				## square with green dot tiles... make forest floor to
				## mud/grass/water edging too"): the old flat
				## Color(0.10, 0.30, 0.11) fill (plus a small dot marker,
				## also removed below) is replaced by real forest-floor
				## tile art — see is_forest_floor's own comment above and
				## _draw_forest_floor_tile() below.
				is_forest_floor = true
			else:
				is_plain_ground = true
			if is_plain_ground:
				## A plain ground square bordering a Pond draws that
				## border's own shore/corner/notch art (see
				## _resolve_water_shore_atlas()'s own comment) instead of
				## the ordinary grass/mud tile.
				var shore_atlas: Vector2i = _resolve_water_shore_atlas(sq)
				var is_mud_sq: bool = grid.mud.has(sq)
				if shore_atlas != Vector2i(-1, -1):
					draw_texture_rect_region(WORLD_TILESET, rect, Rect2(shore_atlas.x * WORLD_TILE_PX, 0, WORLD_TILE_PX, WORLD_TILE_PX))
				elif not is_mud_sq:
					## Per the follow-up request ("lets work on the grass to
					## mud edging transition"): water shore wins if a square
					## somehow borders both (matches OverworldMap's own
					## water-first priority) — otherwise a grass square
					## bordering `grid.mud` draws the ported shore art from
					## _resolve_mud_shore_atlas() instead of a flat grass
					## tile. Mud squares themselves are unaffected (a mud
					## square never draws shore art against its own kind —
					## only the grass side blends, same convention as water).
					var mud_shore_atlas: Vector2i = _resolve_mud_shore_atlas(sq)
					if mud_shore_atlas != Vector2i(-1, -1):
						draw_texture_rect_region(WORLD_TILESET, rect, Rect2(mud_shore_atlas.x * WORLD_TILE_PX, 0, WORLD_TILE_PX, WORLD_TILE_PX))
					else:
						_draw_world_ground_tile(rect, sq, false)
				else:
					_draw_world_ground_tile(rect, sq, true)
			elif is_water_block:
				## The square itself is entirely water (not just
				## bordering it) — same flat WATER_SHALLOW_ATLAS tile
				## _draw_pond_tile() uses for a Pond obstacle's own
				## squares, so a terrain-water block and an adjacent Pond
				## read as one continuous body of water.
				_draw_water_tile(rect, sq)
			elif is_forest_floor:
				_draw_forest_floor_tile(rect, sq)
			else:
				draw_rect(rect, color)
			## Darkness (per the request: "Darken the battle maps when
			## its night time... light source will cancel the darkness
			## effect within their area") — painted right over the base
			## tile colour, before any of the ground-texture/obstacle
			## detail below, so terrain still reads through it dimmed
			## rather than being fully hidden.
			if battle_dark_active and not _square_lit(sq):
				draw_rect(rect, DARKNESS_TINT_COLOR)

			## Combat Encounter rework, Phase 4 (per the follow-up
			## request: "make detailed Tiles of these... let these offer
			## varying degrees of cover"): a per-square detail drawn on
			## top of the base fill above — see _draw_obstacle_detail()
			## and BattleGrid.OBSTACLE_TYPES for what each type actually
			## does mechanically (impassable/cover tier/blocks line of
			## sight). Boulder/BrokenCart/Structure are deliberately
			## skipped here — per the follow-up request ("stretch
			## obstacle icon images rather than tiling them in their
			## assigned area's"), those are drawn once per whole instance
			## further below instead of once per occupied square. Tree/
			## Bush (always exactly 1 square), HighGrass/Fence (naturally
			## per-square texture/topology), and Pond (see
			## _resolve_water_shore_atlas()'s own comment) all stay
			## per-square.
			if obstacle_here != "" and (not OBSTACLE_FILL_COLOR.has(obstacle_here) or obstacle_here == "Pond"):
				_draw_obstacle_detail(rect, obstacle_here, sq)

			## Per the follow-up request ("show a darker cell border if
			## they can not be passed — thicker black line"): every
			## impassable square gets a thick dark outline — but only on
			## edges where the neighbour ISN'T part of the very same
			## obstacle (or, for two plain terrain-impassable squares
			## with no obstacle at all, the same "no obstacle" case), so
			## a multi-square Boulder/Structure/Fence reads as one
			## continuous shape instead of a grid of separately-outlined
			## tiles.
			##
			## Per the follow-up request ("remove the black outline from
			## ponds"): Pond is explicitly excluded here — its own water/
			## shore art (see _resolve_water_shore_atlas()'s own comment)
			## already reads as a clean, self-contained shape against the
			## grass around it, so the added black line was redundant/
			## unwanted specifically for water. Every other impassable
			## type keeps the outline unchanged.
			##
			## Per the follow-up request ("allow this water to merge with
			## ponds too"): `grid.water` squares are excluded the same
			## way, for the same reason — real water art already reads as
			## a clean shape, and this is also what lets a water block sit
			## flush against a Pond with no seam line between them.
			if grid.impassable.has(sq) and obstacle_here != "Pond" and not grid.water.has(sq):
				var border_w: float = max(2.0, square_px * 0.09)
				var border_col := Color(0, 0, 0, 0.85)
				if _impassable_border(sq, sq + Vector2i(0, -1)):
					draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), border_col, border_w)
				if _impassable_border(sq, sq + Vector2i(0, 1)):
					draw_line(rect.position + Vector2(0, rect.size.y), rect.position + rect.size, border_col, border_w)
				if _impassable_border(sq, sq + Vector2i(-1, 0)):
					draw_line(rect.position, rect.position + Vector2(0, rect.size.y), border_col, border_w)
				if _impassable_border(sq, sq + Vector2i(1, 0)):
					draw_line(rect.position + Vector2(rect.size.x, 0), rect.position + rect.size, border_col, border_w)

	## Exploration mode: door threshold lines (per the request "change
	## Doors to a thick brown line running along the Tile edges they sit
	## on"). Drawn after every square's own tile art/border pass, once
	## per grid.door_edges entry, only when at least one cell of that
	## door's own span (see door_edges' own declaration comment — a room's
	## own near-face cells, no separate tile of its own) is within the
	## party's fog-of-war ("should be visible for the player when close
	## enough" — explored/dim (vis 1) or currently lit (vis 2) both count,
	## matching how the rest of the dungeon itself is revealed). Same
	## line regardless of open/closed state — nothing in the request
	## distinguishes the two.
	if not grid.cell_texture.is_empty() and not grid.door_edges.is_empty():
		var door_col := Color(0.36, 0.22, 0.09, 0.95)
		var door_w: float = max(3.0, square_px * 0.16)
		for edge in grid.door_edges:
			if not _door_edge_visible(edge):
				continue
			var span_start: int = edge["span_start"]
			var span_end: int = edge["span_end"]
			var line_pos: int = edge["line_pos"]
			var p1: Vector2
			var p2: Vector2
			if edge["orientation"] == "vertical":
				p1 = origin + Vector2(line_pos * square_px, span_start * square_px)
				p2 = origin + Vector2(line_pos * square_px, span_end * square_px)
			else:
				p1 = origin + Vector2(span_start * square_px, line_pos * square_px)
				p2 = origin + Vector2(span_end * square_px, line_pos * square_px)
			draw_line(p1, p2, door_col, door_w)

	## Per the request ("places where passage walls touch rooms and
	## there is no door... should be impassable and player should [not]
	## be able to see through them"): a plain dark stone-grey line —
	## deliberately NOT the door's brown, so the two read as visually
	## distinct ("a real doorway" vs "just wall") — drawn on top of every
	## sealed grid.wall_edge_lines boundary once either of its own two
	## cells has been explored (same fog-of-war threshold every other
	## piece of dungeon art already uses).
	if not grid.cell_texture.is_empty() and not grid.wall_edge_lines.is_empty():
		var wall_col := Color(0.12, 0.12, 0.14, 0.95)
		var wall_w: float = max(3.0, square_px * 0.16)
		for edge in grid.wall_edge_lines:
			if not _wall_edge_visible(edge):
				continue
			var w_span_start: int = edge["span_start"]
			var w_span_end: int = edge["span_end"]
			var w_line_pos: int = edge["line_pos"]
			var wp1: Vector2
			var wp2: Vector2
			if edge["orientation"] == "vertical":
				wp1 = origin + Vector2(w_line_pos * square_px, w_span_start * square_px)
				wp2 = origin + Vector2(w_line_pos * square_px, w_span_end * square_px)
			else:
				wp1 = origin + Vector2(w_span_start * square_px, w_line_pos * square_px)
				wp2 = origin + Vector2(w_span_end * square_px, w_line_pos * square_px)
			draw_line(wp1, wp2, wall_col, wall_w)

	## Dungeon hazard tiles (Chasm/Spike trap, Hazard Table D3): a Chasm
	## is a visible physical gap (drawn regardless of resolved state,
	## same vision-gating threshold as everything else — explored or
	## lit); a Spike trap is a HIDDEN trap per genre convention, so it
	## only ever draws once `resolved` is true (i.e. after a character
	## has already sprung or spotted it) — see grid.hazard_markers' own
	## declaration comment.
	##
	## Per the request ("Chasm's should span the width... of rooms they
	## are in"): a chasm is no longer one small circle at the room's
	## center — marker["cells"] (see BattleGrid._build_hazard_markers())
	## is the full line of cells the gap actually spans, each drawn as a
	## solid dark square covering the whole tile (a real floor-to-wall
	## gap, not a token marker) with its own soft rim, each cell gated on
	## its OWN fog-of-war state so a partially-explored chasm reveals
	## square by square like the rest of the map, not all at once.
	if not grid.cell_texture.is_empty() and not grid.hazard_markers.is_empty():
		for marker in grid.hazard_markers:
			var mtype: String = marker["type"]
			if mtype == "chasm":
				var mcells: Array = marker.get("cells", [marker["pos"]])
				for c in mcells:
					if _marker_fog(c) < 1:
						continue
					var crect := Rect2(origin + Vector2(c) * square_px, Vector2(square_px, square_px))
					draw_rect(crect, Color(0.03, 0.03, 0.05, 0.92))
					var ccenter: Vector2 = crect.position + crect.size * 0.5
					draw_arc(ccenter, square_px * 0.47, 0, TAU, 16, Color(0.15, 0.13, 0.1, 0.6), max(1.0, square_px * 0.04))
			else:   ## spike_trap — stays a single hidden point
				var mpos: Vector2i = marker["pos"]
				if _marker_fog(mpos) < 1:
					continue
				if not marker["resolved"]:
					continue   ## still hidden -- nothing to draw yet
				var mcenter: Vector2 = origin + (Vector2(mpos) + Vector2(0.5, 0.5)) * square_px
				var spike_col := Color(0.55, 0.1, 0.1, 0.9)
				var half: float = square_px * 0.22
				draw_line(mcenter + Vector2(-half, -half), mcenter + Vector2(half, half), spike_col, max(1.5, square_px * 0.06))
				draw_line(mcenter + Vector2(-half, half), mcenter + Vector2(half, -half), spike_col, max(1.5, square_px * 0.06))

	## Room Furniture ("Sewer/Cave Dungeons update", Room Furniture Table
	## D12) — one real sprite per piece (see FURNITURE_TEXTURES above),
	## drawn ONCE stretched across its whole footprint's bounding Rect2
	## (grid.furniture_markers' own "anchor"/"size", both in cells) rather
	## than once per occupied cell — same "stretch across the instance's
	## full bounding rect" approach _draw_obstacle_detail_stretched()
	## already uses for multi-square battlefield obstacles, since a
	## single texture drawn once per cell would just tile/repeat instead
	## of reading as one object. Gated on every one of its cells being at
	## least explored/lit, not just its anchor cell, so a 2-cell piece
	## doesn't pop into view before the party can actually see all of it.
	if not grid.furniture_markers.is_empty():
		for fmarker in grid.furniture_markers:
			var fcells: Array = fmarker.get("cells", [])
			var all_lit := not fcells.is_empty()
			for fc in fcells:
				if _marker_fog(fc) < 1:
					all_lit = false
					break
			if not all_lit:
				continue
			var ftype: String = fmarker.get("type", "")
			var ftex: Texture2D = FURNITURE_TEXTURES.get(ftype)
			if ftex == null:
				continue
			var fanchor: Vector2i = fmarker.get("anchor", fcells[0])
			var fsize: Vector2i = fmarker.get("size", Vector2i(1, 1))
			var frect := Rect2(origin + Vector2(fanchor) * square_px, Vector2(fsize) * square_px)
			## Per the request ("furniture items should be placed along
			## the walls looking away from the wall"): the sprite itself
			## is authored facing "south" (wall at the top of the image,
			## open side at the bottom) at its natural, un-rotated
			## footprint aspect — DungeonGenerator.FURNITURE_FOOTPRINT,
			## the SAME base size _place_footprint() rotated/swapped away
			## from when this piece ended up against an east/west wall
			## instead of a north/south one (see that function's own
			## comment). Rotating the natural-aspect rect here, rather
			## than drawing pre-rotated art, is what makes a single
			## sprite per type look right against any of a room's four
			## walls: a rotated (2,1)-shaped rect visually fills exactly
			## the same space an actual (1,2) footprint would.
			var fcenter: Vector2 = frect.position + frect.size * 0.5
			var fnatural: Vector2i = DungeonGenerator.FURNITURE_FOOTPRINT.get(ftype, fsize)
			var fnatural_px: Vector2 = Vector2(fnatural) * square_px
			var fangle: float = _furniture_rotation(fmarker.get("facing", Vector2i.ZERO))
			draw_set_transform(pan_offset + fcenter * zoom_level, fangle, Vector2(zoom_level, zoom_level))
			draw_texture_rect(ftex, Rect2(-fnatural_px * 0.5, fnatural_px), false)
			draw_set_transform(pan_offset, 0.0, Vector2(zoom_level, zoom_level))

	## The Goblin Fort Dungeon's chest — drawn once its own square is at
	## least explored/lit, same fog-of-war gate as everything else on
	## this grid. Always the same closed-chest art regardless of locked/
	## looted state, matching the original overworld tile's own look.
	if grid.chest_marker_pos != Vector2i(-1, -1) and _marker_fog(grid.chest_marker_pos) >= 1:
		var chest_rect := Rect2(origin + Vector2(grid.chest_marker_pos) * square_px, Vector2(square_px, square_px))
		draw_texture_rect(CHEST_TEXTURE, chest_rect, false)

	## The procedural Quest room's own Treasure Chest ("Sewer/Cave
	## Dungeons update") — same monster_chest.png art as the Goblin
	## Fort's own chest above (same real-world object, just a different
	## per-room system — see grid.room_chest_markers' own declaration
	## comment for why these two chest systems stay separate), same
	## fog-of-war gate.
	if not grid.room_chest_markers.is_empty():
		for cmarker in grid.room_chest_markers:
			var cpos: Vector2i = cmarker.get("pos", Vector2i(-1, -1))
			if cpos == Vector2i(-1, -1) or _marker_fog(cpos) < 1:
				continue
			var rchest_rect := Rect2(origin + Vector2(cpos) * square_px, Vector2(square_px, square_px))
			draw_texture_rect(CHEST_TEXTURE, rchest_rect, false)

	## The dungeon's own entrance/exit tile — per the request ("show the
	## location of the entrance/exit of the Greenskin fort, right now
	## there is no indication where it is"). No dedicated gate/door
	## sprite exists for this yet, so it's a plain gold highlight rect
	## with an outlined "EXIT" label, same fog-of-war gate as the chest
	## marker above. grid.entrance_marker_pos is set for every dungeon
	## theme (see battle_grid.gd's own comment on the field), not just
	## the Goblin Fort.
	if grid.entrance_marker_pos != Vector2i(-1, -1) and _marker_fog(grid.entrance_marker_pos) >= 1:
		var entrance_rect := Rect2(origin + Vector2(grid.entrance_marker_pos) * square_px, Vector2(square_px, square_px))
		var entrance_col := Color(0.85, 0.7, 0.25, 0.35)
		draw_rect(entrance_rect, entrance_col)
		draw_rect(entrance_rect, Color(0.85, 0.7, 0.25, 0.85), false, max(1.5, square_px * 0.05))
		var exit_font := get_theme_default_font()
		var exit_font_size: int = int(clampf(square_px * 0.24, 6.0, 11.0))
		var exit_label := "EXIT"
		var exit_center: Vector2 = entrance_rect.position + entrance_rect.size / 2.0
		var exit_text_width: float = square_px * 1.4
		var exit_text_pos := Vector2(exit_center.x - exit_text_width / 2.0, exit_center.y + exit_font_size * 0.35)
		draw_string_outline(exit_font, exit_text_pos, exit_label, HORIZONTAL_ALIGNMENT_CENTER, exit_text_width, exit_font_size, 3, Color(0, 0, 0, 0.9))
		draw_string(exit_font, exit_text_pos, exit_label, HORIZONTAL_ALIGNMENT_CENTER, exit_text_width, exit_font_size, Color(1.0, 0.92, 0.6))

	## The procedural Quest room's own stairs down to the next dungeon
	## floor ("Sewer/Cave Dungeons update 2" request) -- same plain-
	## highlight-rect-plus-outlined-label treatment as the EXIT marker
	## just above (no dedicated stairs sprite exists yet either), just a
	## teal/blue color instead of gold so the two are never confused at a
	## glance, same fog-of-war gate. grid.room_stairs_markers is simply
	## empty on a dungeon's deepest floor (see DungeonGenerator.
	## MAX_DUNGEON_FLOOR) or on any theme that never populates `rooms`
	## at all (the Goblin Fort's fixed-room layout), so this safely no-
	## ops there.
	if not grid.room_stairs_markers.is_empty():
		for smarker in grid.room_stairs_markers:
			var spos: Vector2i = smarker.get("pos", Vector2i(-1, -1))
			if spos == Vector2i(-1, -1) or _marker_fog(spos) < 1:
				continue
			var stairs_rect := Rect2(origin + Vector2(spos) * square_px, Vector2(square_px, square_px))
			var stairs_col := Color(0.25, 0.55, 0.75, 0.35)
			draw_rect(stairs_rect, stairs_col)
			draw_rect(stairs_rect, Color(0.25, 0.55, 0.75, 0.85), false, max(1.5, square_px * 0.05))
			var stairs_font := get_theme_default_font()
			var stairs_font_size: int = int(clampf(square_px * 0.22, 6.0, 10.0))
			var stairs_label := "STAIRS"
			var stairs_center: Vector2 = stairs_rect.position + stairs_rect.size / 2.0
			var stairs_text_width: float = square_px * 1.6
			var stairs_text_pos := Vector2(stairs_center.x - stairs_text_width / 2.0, stairs_center.y + stairs_font_size * 0.35)
			draw_string_outline(stairs_font, stairs_text_pos, stairs_label, HORIZONTAL_ALIGNMENT_CENTER, stairs_text_width, stairs_font_size, 3, Color(0, 0, 0, 0.9))
			draw_string(stairs_font, stairs_text_pos, stairs_label, HORIZONTAL_ALIGNMENT_CENTER, stairs_text_width, stairs_font_size, Color(0.75, 0.92, 1.0))

	## Per the follow-up request ("stretch obstacle icon images rather
	## than tiling them in their assigned area's"): the "solid mass"
	## obstacle types (Boulder/Pond/BrokenCart/Structure — the same set
	## OBSTACLE_FILL_COLOR already gives one continuous base fill, per
	## the per-square loop above) get their hand-drawn detail rendered
	## ONCE per obstacle INSTANCE, scaled to fill that instance's whole
	## footprint bounding rect — rather than the per-square loop above
	## calling _draw_obstacle_detail once per occupied square, which for
	## a multi-square instance drew the same small motif over and over,
	## reading as a repeating/tiled pattern instead of one coherent
	## picture. grid.obstacles holds each instance's own full "squares"
	## footprint (independent of obstacle_type's flattened per-square
	## lookup), so the bounding rect here always matches the real shape
	## even for a non-rectangular Huge blob. Drawn after every square's
	## own border pass above, so a big stretched image sits on top of the
	## borders rather than under them.
	for inst in grid.obstacles:
		var inst_type: String = inst.get("type", "")
		## Pond stays in OBSTACLE_FILL_COLOR (for its own base fill/
		## border/darkness handling in the per-square loop above) but is
		## drawn per-square via _draw_obstacle_detail(), not stretched
		## here — see that call site's own comment.
		if not OBSTACLE_FILL_COLOR.has(inst_type) or inst_type == "Pond":
			continue
		var inst_squares: Array = inst.get("squares", [])
		if inst_squares.is_empty():
			continue
		var min_x: int = inst_squares[0].x
		var max_x: int = inst_squares[0].x
		var min_y: int = inst_squares[0].y
		var max_y: int = inst_squares[0].y
		for sq2 in inst_squares:
			min_x = mini(min_x, sq2.x)
			max_x = maxi(max_x, sq2.x)
			min_y = mini(min_y, sq2.y)
			max_y = maxi(max_y, sq2.y)
		var bound_rect := Rect2(
			origin.x + min_x * square_px,
			origin.y + min_y * square_px,
			float(max_x - min_x + 1) * square_px - 1.0,
			float(max_y - min_y + 1) * square_px - 1.0
		)
		_draw_obstacle_detail_stretched(bound_rect, inst_type, inst_squares[0])

	## Per the follow-up request ("change the yellow overlay when
	## selecting and give it 85% opacity, then give it a stylized edge
	## with no opacity [interior fill]... do the same for other similar
	## overlays on the battle map too"): Move's reachable-squares
	## highlight and AoE's preview both used to be a single flat, fully
	## opaque color that REPLACED the square's normal terrain fill
	## entirely (see the per-square loop above), with every square in the
	## set outlined individually — grid lines cut straight through the
	## middle of one contiguous highlighted zone. Now drawn here instead,
	## on top of the completely normal terrain (texture and all): a
	## near-transparent tint wash plus one continuous, rounded-corner
	## border running only along the OUTER boundary of the whole region
	## (see _draw_region_overlay) at 85% opacity — reads as one soft glow
	## around a zone rather than a grid of separately outlined tiles.
	if not highlighted.is_empty():
		_draw_region_overlay(highlighted, origin, square_px, Color(0.85, 0.8, 0.35, 0.14), Color(0.95, 0.88, 0.4, 0.85))
	if not aoe_preview.is_empty():
		_draw_region_overlay(aoe_preview, origin, square_px, Color(0.85, 0.35, 0.15, 0.16), Color(0.95, 0.45, 0.15, 0.85))
		## The exact square the AoE preview is currently centered/hovered
		## on keeps its own brighter accent on top of the shared region
		## tint, same distinction the old flat-color version drew (a
		## brighter orange right at the hover square).
		if aoe_preview.has(hover_target):
			var aoe_ht_rect := Rect2(origin.x + hover_target.x * square_px, origin.y + hover_target.y * square_px, square_px - 1, square_px - 1)
			draw_rect(aoe_ht_rect, Color(0.95, 0.5, 0.15, 0.22))

	## Per the request: the exact square the Move arrow currently ends on
	## gets its own clearly distinct marker on top of the reachable-
	## squares tint above — rather than leaving the player to trace the
	## thin arrowhead to figure out precisely where a click would land
	## them. Green/valid when a click here would actually commit (see
	## hover_target_valid); red/invalid when it wouldn't (out of
	## remaining movement, etc.), so the player also gets a clear "not
	## there" signal while aiming. Restyled to match _draw_region_overlay
	## above: a light tint (not a solid fill) plus an 85%-opacity rounded-
	## corner border, same "stylized edge, no opacity in the middle" look,
	## applied to a single-square region here.
	if hover_target != Vector2i(-1, -1):
		var ht_set := {hover_target: true}
		var ht_fill: Color = Color(0.4, 0.9, 0.35, 0.18) if hover_target_valid else Color(0.9, 0.25, 0.25, 0.16)
		var ht_border: Color = Color(0.55, 1.0, 0.5, 0.85) if hover_target_valid else Color(1.0, 0.35, 0.35, 0.85)
		_draw_region_overlay(ht_set, origin, square_px, ht_fill, ht_border)

	## Ground Fire visual (Great Fires of U'Zhul, Firewall — see
	## ground_fire_squares' own declaration comment): a scorched-ground
	## tint/border under the whole hazard region, same _draw_region_
	## overlay treatment Move/AoE highlights use above, then the real
	## flame art itself on top of each individual square.
	if not ground_fire_squares.is_empty():
		var gf_set: Dictionary = {}
		for s in ground_fire_squares:
			gf_set[s] = true
		_draw_region_overlay(gf_set, origin, square_px, Color(0.32, 0.08, 0.03, 0.35), Color(0.7, 0.25, 0.08, 0.6))
		for s in ground_fire_squares:
			_draw_ground_fire_tile(origin, square_px, s)

	## Smoke Breath visual (see smoke_squares' own declaration comment): a
	## hazy grey tint/border under the whole cloud region, same treatment
	## the ground fire hazard gets above, then the real smoke art on top
	## of each individual square.
	if not smoke_squares.is_empty():
		var smoke_set: Dictionary = {}
		for s in smoke_squares:
			smoke_set[s] = true
		_draw_region_overlay(smoke_set, origin, square_px, Color(0.5, 0.5, 0.55, 0.22), Color(0.75, 0.75, 0.8, 0.45))
		for s in smoke_squares:
			_draw_smoke_tile(origin, square_px, s)

	var font := get_theme_default_font()
	for c in positions:
		var pos: Vector2i = positions[c]
		## Exploration mode: a combatant standing somewhere the party
		## can't currently see (fog-of-war vis < 2 — unexplored, or
		## explored-but-dim "remembered" terrain) doesn't get a token
		## drawn at all, same as they'd genuinely be hidden in the dark.
		## No-op for a normal battlefield (grid.fog_of_war empty there).
		## Per the request ("when in combat with no light, Creatures
		## should become visible to the player once if they are standing
		## next to them (i.e. adjacent cells)"): is_adjacent_to_living_ally
		## overrides this for anyone right next to a living ally, even
		## somewhere the party's own light doesn't reach.
		if not grid.fog_of_war.is_empty() and int(grid.fog_of_war.get(pos, 0)) < 2:
			if not is_adjacent_to_living_ally(pos, c.get_footprint_size(), positions):
				continue
		## Per the multi-square creature footprint feature (Large=2x2,
		## Enormous=3x3, Monstrous=4x4, via Character.get_footprint_size()):
		## the token is centered on and sized to the WHOLE footprint's
		## bounding box, not just the single anchor cell — mirrors the
		## pre-existing multi-square OBSTACLE rendering pattern (a bounding
		## rect spanning every occupied cell). Reduces exactly to the
		## original single-cell math when footprint_size is 1 (every
		## Average-or-below combatant, the overwhelming majority).
		var footprint_size: int = c.get_footprint_size()
		var center := origin + Vector2((pos.x + footprint_size * 0.5) * square_px, (pos.y + footprint_size * 0.5) * square_px)
		var is_ally: bool = c.allegiance == "ally"
		var accent: Color = Color(0.3, 0.55, 0.95) if is_ally else Color(0.85, 0.25, 0.25)
		var icon_size: float = square_px * float(footprint_size) * 0.85
		var half := icon_size / 2.0

		## Per the request: cross out a dead or unconscious combatant's
		## own token right on the map. Mirrors
		## CombatEncounter.is_defeated()'s own wounds_current <= 0 check
		## (duplicated here rather than requiring a CombatEncounter
		## reference just for this one-line check), plus the Unconscious
		## Condition, which can apply while still above 0 Wounds. Also
		## dims the whole token, the same "greyed out" treatment the
		## top-strip panels already give a defeated combatant.
		var is_down: bool = c.wounds_current <= 0 or c.conditions.has("Unconscious")
		var token_modulate: Color = Color(0.55, 0.55, 0.55, 1.0) if is_down else Color(1, 1, 1, 1)

		## Per the follow-up request ("make ally tokens have a blue ring
		## around them by default, while enemy tokens will have red
		## rings. And the token background for both of them to black"):
		## the backdrop disc is now always black (was the solid accent
		## colour) — the ally(blue)/adversary(red) distinction instead
		## draws as a ring outline around that backdrop, right below.
		draw_circle(center, half + 2.0, Color(0, 0, 0, 1))
		var icon: Texture2D = icons.get(c)
		if icon != null:
			## Per the request ("use the new portraits in all Icon"): the
			## old wound-tier/monster sprites were square, so a plain
			## draw_texture_rect never distorted them. Ally Career
			## portraits keep their own source aspect ratio, so this crops
			## to a centered square region first instead of squashing a
			## tall/wide portrait to fit the round token (monster icons
			## are still square, so this is a no-op for them).
			var icon_size_px: Vector2 = icon.get_size()
			var icon_side: float = min(icon_size_px.x, icon_size_px.y)
			var icon_src := Rect2((icon_size_px.x - icon_side) * 0.5, (icon_size_px.y - icon_side) * 0.5, icon_side, icon_side)
			## Per the follow-up request ("add a red tint at low health"):
			## icon_modulates carries an optional per-Character wound tint
			## (ally tokens only — see field_encounter_screen.gd's own
			## _render_turn_order_panel), multiplied on top of the existing
			## is_down grey-out rather than replacing it.
			var wound_tint: Color = icon_modulates.get(c, Color(1, 1, 1, 1))
			draw_texture_rect_region(icon, Rect2(center - Vector2(half, half), Vector2(icon_size, icon_size)), icon_src, token_modulate * wound_tint)
		else:
			draw_circle(center, half, accent.lightened(0.15) * token_modulate)
		draw_arc(center, half + 2.0, 0, TAU, 24, accent * token_modulate, max(2.0, square_px * 0.08))

		if is_down:
			var inset := half * 0.15
			draw_line(center + Vector2(-half + inset, -half + inset), center + Vector2(half - inset, half - inset), Color(0.9, 0.15, 0.15, 0.9), max(2.0, square_px * 0.06))
			draw_line(center + Vector2(-half + inset, half - inset), center + Vector2(half - inset, -half + inset), Color(0.9, 0.15, 0.15, 0.9), max(2.0, square_px * 0.06))

		if c == current_turn_character:
			draw_arc(center, half + 4.0, 0, TAU, 20, Color(1, 1, 1), 2.0)
		if c == selected_target:
			draw_arc(center, half + 7.0, 0, TAU, 20, Color(0.95, 0.85, 0.3), 2.0)

		## Health bar above the icon — same green/yellow/red tiers as
		## the top-strip HP bars elsewhere in this screen.
		var bar_w: float = icon_size
		var bar_h: float = max(3.0, square_px * 0.12)
		var bar_rect := Rect2(center.x - bar_w / 2.0, center.y - half - bar_h - 4.0, bar_w, bar_h)
		draw_rect(bar_rect, Color(0.08, 0.07, 0.06, 0.85))
		var pct: float = clampf(float(c.wounds_current) / float(max(c.wounds_max, 1)), 0.0, 1.0)
		var fill_color: Color = Color(0.2, 0.75, 0.25) if pct > 0.5 else (Color(0.85, 0.65, 0.15) if pct > 0.25 else Color(0.75, 0.15, 0.15))
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * pct, bar_rect.size.y)), fill_color)
		draw_rect(bar_rect, Color(0, 0, 0, 0.6), false, 1.0)

		## Condition markers — per the request ("add visual markers for
		## conditions on each combatant"): one small glyph per active
		## Condition this project has a named icon for, drawn in a row
		## just above the HP bar. See _condition_markers_for()'s own
		## comment for what actually gets shown and why.
		var cond_markers: Array = _condition_markers_for(c)
		if not cond_markers.is_empty():
			var cond_font_size: int = int(clampf(square_px * 0.32, 6.0, 12.0))
			var cond_gap: float = cond_font_size * 0.35
			var cond_widths: Array[float] = []
			var cond_total_w: float = 0.0
			for i in range(cond_markers.size()):
				var w: float = font.get_string_size(cond_markers[i]["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, cond_font_size).x
				cond_widths.append(w)
				cond_total_w += w
				if i > 0:
					cond_total_w += cond_gap
			var cond_y: float = bar_rect.position.y - cond_gap
			var cond_x: float = center.x - cond_total_w / 2.0
			for i in range(cond_markers.size()):
				var cond_pos := Vector2(cond_x, cond_y)
				var cond_text: String = cond_markers[i]["text"]
				var cond_color: Color = cond_markers[i]["color"]
				draw_string_outline(font, cond_pos, cond_text, HORIZONTAL_ALIGNMENT_LEFT, -1, cond_font_size, 2, Color(0, 0, 0, 0.9))
				draw_string(font, cond_pos, cond_text, HORIZONTAL_ALIGNMENT_LEFT, -1, cond_font_size, cond_color)
				cond_x += cond_widths[i] + cond_gap

		## Name tag below the icon — `names` holds the full
		## character_name (including its own disambiguation number when
		## there's more than one of a species, e.g. "Wolf 2"), same as
		## every other name display in this screen, falling back to the
		## raw character_name if this combatant's tag wasn't supplied.
		## Per the follow-up request ("display the full names on all
		## icons, just make the text smaller"): rather than picking one
		## font size from square_px and then truncating whatever doesn't
		## fit (which is how "Giant Spider"/"Vulchling"/"Wolf" were
		## shortening down to "Gia"/"Vul"/"Wol"), this now shrinks the
		## font size itself, one point at a time, down to a small floor,
		## until the FULL label fits the budget. Only a name so long it
		## still doesn't fit even at the floor size falls back to the old
		## ellipsis-truncation as a last resort.
		var label: String = names.get(c, c.character_name)
		var max_font_size: int = int(clampf(square_px * 0.28, 5.0, 10.0))
		var min_font_size := 3
		## Real bug fix ("two adjacent same-named tokens' labels merge
		## into garbled text"): a label can only safely claim up to this
		## token's own share of the grid pitch (a small gutter subtracted
		## so two full-width neighbouring labels never touch edge-to-edge)
		## — see _fit_label_to_width's own comment for the full story.
		## Previously this was icon_size + 30.0, which could exceed the
		## actual center-to-center spacing between adjacent same-size
		## tokens and had no truncation at all, so overflow was guaranteed
		## for anything longer than a short name at a cramped zoom level.
		var label_budget: float = max(square_px * float(footprint_size) - 6.0, max_font_size * 3.0)
		var font_size: int = max_font_size
		while font_size > min_font_size and font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label_budget:
			font_size -= 1
		var fitted_label: String = label
		if font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label_budget:
			fitted_label = _fit_label_to_width(font, label, font_size, label_budget)
		var text_width: float = label_budget
		var text_pos := Vector2(center.x - text_width / 2.0, center.y + half + font_size + 3.0)
		draw_string_outline(font, text_pos, fitted_label, HORIZONTAL_ALIGNMENT_CENTER, text_width, font_size, 3, Color(0, 0, 0, 0.9))
		draw_string(font, text_pos, fitted_label, HORIZONTAL_ALIGNMENT_CENTER, text_width, font_size, Color(1, 1, 1))

	## Per the request: the Move arrow — a poly-line from wherever
	## `current_turn_character` (the mover) currently stands, through
	## each square of `preview_path`, with a small arrowhead at the tip.
	## `preview_path` is already truncated to whatever movement is
	## actually left by the caller, so drawing the whole thing as given
	## is exactly "up to the distance they can actually [move]" — nothing
	## further to cap here.
	## Per the follow-up request ("Straight path show with red lines"):
	## was a yellow-gold arrow — now a deep, saturated red, kept a
	## slightly different shade from the Charge arrows' red-orange
	## (Color(0.9, 0.25, 0.2, ...) below) so the two stay visually
	## distinct when both are on screen at once.
	if not preview_path.is_empty() and positions.has(current_turn_character):
		var arrow_color := Color(0.85, 0.1, 0.1, 0.9)
		var start_sq: Vector2i = positions[current_turn_character]
		var points: Array[Vector2] = [origin + (Vector2(start_sq) + Vector2(0.5, 0.5)) * square_px]
		for sq in preview_path:
			points.append(origin + (Vector2(sq) + Vector2(0.5, 0.5)) * square_px)
		for i in range(points.size() - 1):
			draw_line(points[i], points[i + 1], arrow_color, max(2.0, square_px * 0.1))
		if points.size() >= 2:
			var tip: Vector2 = points[points.size() - 1]
			var dir: Vector2 = (tip - points[points.size() - 2]).normalized()
			var perp := Vector2(-dir.y, dir.x)
			var head_len: float = square_px * 0.35
			var head_w: float = square_px * 0.22
			var back: Vector2 = tip - dir * head_len
			draw_line(tip, back + perp * head_w, arrow_color, max(2.0, square_px * 0.1))
			draw_line(tip, back - perp * head_w, arrow_color, max(2.0, square_px * 0.1))

	## Charge-ready arrow (per the request: "if the active character is
	## within charge range of the selected target draw a Red arrow line
	## from that character to the target"): a static red arrow from the
	## mover's REAL current square (unlike charge_preview_targets below,
	## which draws from a hypothetical Move-hover square) straight to
	## the currently selected target, shown whenever FieldEncounterScreen
	## reports a Charge is actually available right now (see
	## set_charge_ready — it mirrors the exact same _target_in_charge_range
	## check that gates the Charge button itself). Same red as the
	## Charge-range preview arrow below, with a "Charge" label along its
	## side per the request so its meaning reads at a glance.
	if charge_ready_target != Vector2i(-1, -1) and positions.has(current_turn_character):
		var cr_color := Color(0.9, 0.25, 0.2, 0.9)
		var cr_start: Vector2 = origin + (Vector2(positions[current_turn_character]) + Vector2(0.5, 0.5)) * square_px
		var cr_end: Vector2 = origin + (Vector2(charge_ready_target) + Vector2(0.5, 0.5)) * square_px
		var cr_line_w: float = max(2.0, square_px * 0.08)
		draw_line(cr_start, cr_end, cr_color, cr_line_w)
		var cr_dir: Vector2 = (cr_end - cr_start).normalized()
		var cr_perp := Vector2(-cr_dir.y, cr_dir.x)
		var cr_head_len: float = square_px * 0.35
		var cr_head_w: float = square_px * 0.22
		var cr_back: Vector2 = cr_end - cr_dir * cr_head_len
		draw_line(cr_end, cr_back + cr_perp * cr_head_w, cr_color, cr_line_w)
		draw_line(cr_end, cr_back - cr_perp * cr_head_w, cr_color, cr_line_w)
		_draw_arrow_label(font, cr_start, cr_end, "Charge", cr_color, square_px)

	## Charge-range preview arrow (per the request: "show a secondary
	## arrow when character moves within charge range of any enemy
	## target") — a thin red arrow from wherever the Move preview is
	## currently hovering (charge_preview_origin, NOT the mover's real
	## square — this is a "what if I end my Move here" preview) straight
	## to each enemy square that would become chargeable from there. Kept
	## visually distinct from the (also red, but deeper/thicker) Move
	## arrow above and the cyan ranged-target arrows (different color
	## entirely) so all three read as separate pieces of information even
	## when shown at once.
	## Per the follow-up request ("do the same on the red charge arrow
	## line that is created when selecting move position"): each of
	## these also gets its own "Charge" label, same helper and placement
	## convention as the static charge-ready arrow just above.
	if not charge_preview_targets.is_empty() and charge_preview_origin != Vector2i(-1, -1):
		var cp_color := Color(0.9, 0.25, 0.2, 0.85)
		var cp_start: Vector2 = origin + (Vector2(charge_preview_origin) + Vector2(0.5, 0.5)) * square_px
		var cp_line_w: float = max(1.5, square_px * 0.06)
		for sq in charge_preview_targets:
			var cp_end: Vector2 = origin + (Vector2(sq) + Vector2(0.5, 0.5)) * square_px
			draw_line(cp_start, cp_end, cp_color, cp_line_w)
			var cp_dir: Vector2 = (cp_end - cp_start).normalized()
			var cp_perp := Vector2(-cp_dir.y, cp_dir.x)
			var cp_head_len: float = square_px * 0.3
			var cp_head_w: float = square_px * 0.18
			var cp_back: Vector2 = cp_end - cp_dir * cp_head_len
			draw_line(cp_end, cp_back + cp_perp * cp_head_w, cp_color, cp_line_w)
			draw_line(cp_end, cp_back - cp_perp * cp_head_w, cp_color, cp_line_w)
			_draw_arrow_label(font, cp_start, cp_end, "Charge", cp_color, square_px)

	## Ranged Attack / Magic-Prayer targeting arrows (per the request:
	## "show a arrow from the attacking player to the valid targets"):
	## one straight-line arrow per currently valid target, all shown
	## simultaneously so the full option set stays visible. Per the
	## follow-up request ("do not lock in the pre-selected target right
	## away... allow user to target freely, like when moving"):
	## whichever target is currently FOCUSED (hover-tracked, see
	## target_focus_square) gets a brighter/thicker arrow; every other
	## valid target gets a dimmer arrow + faint outline so it still
	## reads as clickable without competing for attention. A cyan tone
	## keeps this visually distinct from Move's yellow arrow and AoE's
	## orange preview.
	if not target_arrows.is_empty() and positions.has(current_turn_character):
		var t_start_sq: Vector2i = positions[current_turn_character]
		var t_start: Vector2 = origin + (Vector2(t_start_sq) + Vector2(0.5, 0.5)) * square_px
		var target_color := Color(0.35, 0.8, 0.95, 0.9)
		var dim_color := Color(0.35, 0.8, 0.95, 0.32)
		for sq in target_arrows:
			var is_focus: bool = sq == target_focus_square
			var col: Color = target_color if is_focus else dim_color
			var line_w: float = max(2.0, square_px * (0.09 if is_focus else 0.05))
			var t_end: Vector2 = origin + (Vector2(sq) + Vector2(0.5, 0.5)) * square_px
			draw_line(t_start, t_end, col, line_w)
			var t_dir: Vector2 = (t_end - t_start).normalized()
			var t_perp := Vector2(-t_dir.y, t_dir.x)
			var t_head_len: float = square_px * 0.35
			var t_head_w: float = square_px * 0.22
			var t_back: Vector2 = t_end - t_dir * t_head_len
			draw_line(t_end, t_back + t_perp * t_head_w, col, line_w)
			draw_line(t_end, t_back - t_perp * t_head_w, col, line_w)
			if not is_focus:
				var t_rect := Rect2(origin.x + sq.x * square_px, origin.y + sq.y * square_px, square_px - 1, square_px - 1)
				draw_rect(t_rect, col, false, max(1.5, square_px * 0.06))

		## The focused target's own crosshair reticle, drawn last so it
		## sits on top of everything else — replaces the plain outline
		## every other valid target still gets, per "make the target a
		## crosshair" — plus a floating "distance — range band" readout
		## just above its square (see FieldEncounterScreen's
		## _ranged_target_readout for what populates the text).
		if target_focus_square != Vector2i(-1, -1) and target_arrows.has(target_focus_square):
			var xc: Vector2 = origin + (Vector2(target_focus_square) + Vector2(0.5, 0.5)) * square_px
			var reach: float = square_px * 0.42
			var gap: float = square_px * 0.15
			var xhair_color := Color(1.0, 0.95, 0.4, 0.95)
			var xhair_w: float = max(2.0, square_px * 0.065)
			draw_line(xc - Vector2(reach, 0), xc - Vector2(gap, 0), xhair_color, xhair_w)
			draw_line(xc + Vector2(gap, 0), xc + Vector2(reach, 0), xhair_color, xhair_w)
			draw_line(xc - Vector2(0, reach), xc - Vector2(0, gap), xhair_color, xhair_w)
			draw_line(xc + Vector2(0, gap), xc + Vector2(0, reach), xhair_color, xhair_w)
			draw_arc(xc, reach * 0.72, 0, TAU, 24, xhair_color, max(1.5, square_px * 0.045))
			if not target_focus_segments.is_empty():
				## Per the follow-up request ("add cover -xx (in red)
				## after the range +/-xx modifier label... and any other
				## known test modifiers too"): each segment is drawn
				## left-to-right in its own color (see
				## FieldEncounterScreen._ranged_target_readout — a
				## segment with no "color" key falls back to the plain
				## xhair_color the whole readout used to be, so the base
				## "12 yd — Short +20" text looks exactly as before), with
				## the whole run centered above the crosshair the same
				## way the old single draw_string call was.
				var rf_size: int = int(clampf(square_px * 0.26, 9.0, 14.0))
				var seg_widths: Array = []
				var total_w := 0.0
				for seg in target_focus_segments:
					var w: float = font.get_string_size(String(seg.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, rf_size).x
					seg_widths.append(w)
					total_w += w
				var rf_y: float = xc.y - reach - rf_size - 4.0
				var cur_x: float = xc.x - total_w / 2.0
				for i in range(target_focus_segments.size()):
					var seg = target_focus_segments[i]
					var seg_text: String = String(seg.get("text", ""))
					var seg_color: Color = seg.get("color", xhair_color)
					var seg_pos := Vector2(cur_x, rf_y)
					draw_string_outline(font, seg_pos, seg_text, HORIZONTAL_ALIGNMENT_LEFT, -1, rf_size, 3, Color(0, 0, 0, 0.9))
					draw_string(font, seg_pos, seg_text, HORIZONTAL_ALIGNMENT_LEFT, -1, rf_size, seg_color)
					cur_x += seg_widths[i]

## Draws `text` beside an arrow's line (per the request: "'Charge'
## along the side of the red line"), centred on the line's own midpoint
## and offset perpendicular to it so the label reads next to the arrow
## rather than sitting on top of and obscuring it. Used by both the
## static Charge-ready arrow and the hover-based Charge-range preview
## arrows above — kept as one shared helper since both want the exact
## same "label floats beside the middle of the line" treatment. Text
## stays upright (not rotated to match the line's own angle) — same
## "always axis-aligned" convention every other label in this file
## already uses (name tags, the ranged-target range readout, etc.).
## Real bug fix, per the user's own screenshot: two same-named
## creatures in adjacent grid cells (e.g. two "Wild Cat"s) had their
## token name-tag labels visibly merge into unreadable garbled text
## ("WildWild C"). Root cause: the label was always drawn at its full
## natural width regardless of how much horizontal room the cell
## spacing actually allows — draw_string doesn't clip to the width
## it's given, so a "Wild Cat"-at-font-size-10 or a much longer name
## like "Bloodletter of Khorne" would simply overflow into whatever's
## next door, without narrowing the font could even hide inside its own
## cell to begin with, unrelated to which creature portrait is shown.
## Truncates with a trailing ellipsis (…) so every label fits within
## its own token's fair share of the grid, one character shorter at a
## time, stopping at a 3-character floor so even a very tight budget
## still shows *something* recognisable rather than just "…".
static func _fit_label_to_width(font: Font, text: String, font_size: int, max_width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return text
	var lo := 1
	var hi := text.length()
	## Binary search for the longest prefix (plus "…") that still fits,
	## since get_string_size is the only expensive part here and this
	## keeps it to O(log n) calls instead of trimming one character at a
	## time from the full length down.
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		var candidate: String = text.substr(0, mid).strip_edges() + "…"
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
			lo = mid
		else:
			hi = mid - 1
	var fitted: String = text.substr(0, max(lo, 3 if text.length() >= 3 else text.length())).strip_edges() + "…"
	return fitted

func _draw_arrow_label(font: Font, from: Vector2, to: Vector2, text: String, color: Color, square_px: float) -> void:
	var mid: Vector2 = (from + to) / 2.0
	var dir: Vector2 = (to - from).normalized()
	if dir == Vector2.ZERO:
		return
	var perp := Vector2(-dir.y, dir.x)
	## Offset to whichever side of the line keeps the label further from
	## the top of the view, purely so it doesn't habitually collide with
	## whatever's drawn above the line (turn-order panel, etc.) — a
	## fixed offset direction would just as often put it exactly there.
	if perp.y < 0:
		perp = -perp
	var font_size: int = int(clampf(square_px * 0.24, 8.0, 13.0))
	var offset: float = square_px * 0.28
	var label_pos: Vector2 = mid + perp * offset
	var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	label_pos -= Vector2(text_width / 2.0, -font_size / 4.0)
	draw_string_outline(font, label_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0, 0, 0, 0.9))
	draw_string(font, label_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## Base fill colour for the obstacle types big/solid enough to read as
## one continuous mass spanning their whole footprint (see _draw()'s own
## `solid_obstacle` branch) — Tree/Bush/High Grass/Fence are deliberately
## absent here: they stay "icon over bare ground" instead (a lone tree or
## a fence post shouldn't paint over the grass it's standing on).
const OBSTACLE_FILL_COLOR := {
	"Boulder": Color(0.38, 0.36, 0.34),
	"Pond": Color(0.14, 0.28, 0.46),
	"BrokenCart": Color(0.3, 0.21, 0.12),
	"Structure": Color(0.34, 0.32, 0.3),
}

## Deterministic pseudo-random in [0, 1) from a square (plus an optional
## salt to get several independent values per square) — used for ground
## texture/decoration so it stays fixed across redraws instead of
## flickering (a real randf() call inside _draw() would re-roll on every
## single repaint, which happens constantly during animations/hover).
static func _hash01(x: int, y: int, salt: int = 0) -> float:
	var n := sin(float(x) * 12.9898 + float(y) * 78.233 + float(salt) * 37.719) * 43758.5453
	return n - floor(n)

## Ground Fire visual — draws one REAL_FLAME_FRAMES frame on `sq`, real
## generated flame art rather than a hand-drawn shape (see
## REAL_FLAME_FRAMES' own declaration comment for why). Each tile gets
## its own looping phase offset from _hash01(sq.x, sq.y, 500) — scaled
## by the frame count and floor()'d to a starting frame index rather
## than a time offset, so tiles are simply out of step with each other
## in the same 6-frame loop (there's no continuous parameter to offset
## since these are discrete frames). Drawn bottom-anchored and centered
## on the tile at REAL_FLAME_OPACITY (per the follow-up request "make
## the flame a bit see through" → 80% → "60%") and REAL_FLAME_SCALE
## tile-widths (per the follow-up "make the flame about 10% smaller",
## 1.35 → 1.215) — the normalized source canvas has generous side
## padding around the actual flame silhouette, so the flame itself
## reads at roughly one tile wide even at that scale.
func _draw_ground_fire_tile(origin: Vector2, square_px: float, sq: Vector2i) -> void:
	var frame_count := REAL_FLAME_FRAMES.size()
	if frame_count == 0:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var phase_offset: float = _hash01(sq.x, sq.y, 500) * frame_count
	var frame_idx: int = int(floor(t * REAL_FLAME_FPS + phase_offset)) % frame_count
	var tex: Texture2D = REAL_FLAME_FRAMES[frame_idx]
	var tex_size: Vector2 = tex.get_size()
	var draw_w: float = square_px * REAL_FLAME_SCALE
	var scale: float = draw_w / tex_size.x
	var draw_h: float = tex_size.y * scale
	var base_x: float = origin.x + sq.x * square_px + square_px * 0.5
	var base_y: float = origin.y + sq.y * square_px + square_px * 0.9
	var rect := Rect2(base_x - draw_w * 0.5, base_y - draw_h, draw_w, draw_h)
	draw_texture_rect(tex, rect, false, Color(1, 1, 1, REAL_FLAME_OPACITY))

## Smoke Breath visual — draws one REAL_SMOKE_FRAMES frame on `sq`, same
## "real generated art, not a hand-drawn shape" approach as
## _draw_ground_fire_tile() just above, and the same per-square looping
## phase offset trick (a different salt, so a tile that happens to be on
## fire AND smoked doesn't flicker both effects in lockstep). Drawn
## CENTERED on the tile — unlike the flame's bottom-anchored "standing on
## the ground" placement, a lingering cloud has no single base point, it
## just hangs over the whole square — at REAL_SMOKE_OPACITY and
## REAL_SMOKE_SCALE tile-widths (bigger than the flame, so adjacent
## smoked tiles read as one continuous haze rather than a grid of
## separate puffs).
func _draw_smoke_tile(origin: Vector2, square_px: float, sq: Vector2i) -> void:
	var frame_count := REAL_SMOKE_FRAMES.size()
	if frame_count == 0:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var phase_offset: float = _hash01(sq.x, sq.y, 900) * frame_count
	var frame_idx: int = int(floor(t * REAL_SMOKE_FPS + phase_offset)) % frame_count
	var tex: Texture2D = REAL_SMOKE_FRAMES[frame_idx]
	var tex_size: Vector2 = tex.get_size()
	var draw_w: float = square_px * REAL_SMOKE_SCALE
	var scale: float = draw_w / tex_size.x
	var draw_h: float = tex_size.y * scale
	var center_x: float = origin.x + sq.x * square_px + square_px * 0.5
	var center_y: float = origin.y + sq.y * square_px + square_px * 0.5
	var rect := Rect2(center_x - draw_w * 0.5, center_y - draw_h * 0.5, draw_w, draw_h)
	draw_texture_rect(tex, rect, false, Color(1, 1, 1, REAL_SMOKE_OPACITY))

## Shared square-region highlight renderer (Move's reachable-squares
## tint, AoE's preview, the hover-target marker) — see the call sites in
## _draw() for the full "why" comment. Two passes: a flat near-
## transparent `fill_color` under every square in `sq_set` (drawn UNDER
## nothing else — the caller already drew normal terrain there first),
## then a border drawn only on edges where the neighbouring square is
## NOT also in `sq_set` (an "outer boundary only" pass, same shape as
## _impassable_border's own multi-square-instance seamless-outline
## trick), with a small filled circle at every corner touched by at
## least one boundary edge to round off what would otherwise be sharp
## grid-aligned 90-degree joints.
func _draw_region_overlay(sq_set: Dictionary, origin: Vector2, square_px: float, fill_color: Color, border_color: Color) -> void:
	var border_w: float = max(2.0, square_px * 0.07)
	for sq in sq_set.keys():
		var rect := Rect2(origin.x + sq.x * square_px, origin.y + sq.y * square_px, square_px - 1, square_px - 1)
		draw_rect(rect, fill_color)
	for sq in sq_set.keys():
		var rect := Rect2(origin.x + sq.x * square_px, origin.y + sq.y * square_px, square_px - 1, square_px - 1)
		var has_n: bool = sq_set.has(sq + Vector2i(0, -1))
		var has_s: bool = sq_set.has(sq + Vector2i(0, 1))
		var has_w: bool = sq_set.has(sq + Vector2i(-1, 0))
		var has_e: bool = sq_set.has(sq + Vector2i(1, 0))
		if not has_n:
			draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), border_color, border_w)
		if not has_s:
			draw_line(rect.position + Vector2(0, rect.size.y), rect.position + rect.size, border_color, border_w)
		if not has_w:
			draw_line(rect.position, rect.position + Vector2(0, rect.size.y), border_color, border_w)
		if not has_e:
			draw_line(rect.position + Vector2(rect.size.x, 0), rect.position + rect.size, border_color, border_w)
		var r: float = border_w * 0.5
		if not has_n or not has_w:
			draw_circle(rect.position, r, border_color)
		if not has_n or not has_e:
			draw_circle(rect.position + Vector2(rect.size.x, 0), r, border_color)
		if not has_s or not has_w:
			draw_circle(rect.position + Vector2(0, rect.size.y), r, border_color)
		if not has_s or not has_e:
			draw_circle(rect.position + rect.size, r, border_color)

## True if the edge between `sq` and `neighbor` should get a border line
## drawn on it — off-grid, or the neighbour isn't impassable at all, or
## it's impassable but a DIFFERENT obstacle (or one belongs to an
## obstacle and the other doesn't) — see _draw()'s own call site.
func _impassable_border(sq: Vector2i, neighbor: Vector2i) -> bool:
	if not grid.is_in_bounds(neighbor):
		return true
	if not grid.impassable.has(neighbor):
		return true
	return grid.obstacle_group.get(sq, -1) != grid.obstacle_group.get(neighbor, -1)

## True if at least one cell of `edge`'s own door span (the room's own
## near-face cells the door sits on — see door_edges' own declaration
## comment; a door is no longer a tile of its own) has been explored
## (fog_of_war >= 1, dim or bright both count) — see the door_edges
## drawing pass in _draw() above for why: "should be visible for the
## player when close enough", same explored-or-lit threshold the rest
## of the dungeon's own art already uses. Walked out from `door_anchor`
## along whichever axis is perpendicular to the line itself (vertical
## line -> span runs along y, horizontal line -> span runs along x),
## matching DungeonGenerator's own CORRIDOR_SCALE-long door span.
func _door_edge_visible(edge: Dictionary) -> bool:
	var anchor: Vector2i = edge["door_anchor"]
	var perp: Vector2i = Vector2i(0, 1) if edge["orientation"] == "vertical" else Vector2i(1, 0)
	var span_len: int = edge["span_end"] - edge["span_start"]
	for i in range(span_len):
		var cell := anchor + perp * i
		if int(grid.fog_of_war.get(cell, 0)) >= 1:
			return true
	return false

## Same "should be visible for the player when close enough" rule
## _door_edge_visible() above uses, but simpler — grid.wall_edge_lines
## entries already carry their own exact 2-cell ["cells"] pair (see
## BattleGrid._build_room_wall_edges()), so there's no anchor/perp span
## to walk; either of the boundary's two cells being explored is enough.
##
## REAL BUG FIX ("the indicated wall sections inside of closer rooms
## should not be visible until doors are opened"): this used to check
## raw grid.fog_of_war directly, the same leak _marker_fog() was already
## introduced to patch for markers (v0.3.61) -- a still-closed room's own
## near-face row genuinely reads fog_of_war >= 1 (that's the mechanism
## _door_edge_visible() above deliberately relies on to keep showing the
## DOOR boundary line itself once nearby), but every OTHER wall segment
## touching that same near-face row -- the room's own side/corner walls,
## and the "solid wall, no door" segments _build_room_wall_edges() adds
## along the rest of the face -- rode along on that same leaked fog value
## and rendered too, visibly jutting out from the corridor's own boundary
## line into what should still be pure unexplored black. Routed through
## _marker_fog() (0 on a closed room's own near-face cell, regardless of
## its raw fog_of_war) so those interior/corner wall segments correctly
## stay hidden until the room's door actually opens, while
## _door_edge_visible() is deliberately left untouched above -- the door
## boundary itself showing "there's a door here" is still wanted.
##
## SECOND REAL BUG FIX (fresh report, screenshot showing a long wall
## segment still leaking well past the v0.3.63 fix above, deep along a
## closed room's own SIDE wall — nowhere near its door or near-face
## row): _build_outer_wall_edge_lines() also produces entries whose
## SECOND cell is a genuine wall/void tile (never in grid.cell_texture,
## by that function's own construction) rather than a second real floor
## cell like every _build_room_wall_edges() entry has. That wall/void
## cell can still pick up its own fog_of_war >= 1 the moment ANY
## adjacent explored floor cell — on the far side of that same 1-tile-
## thick wall, e.g. a completely unrelated corridor legitimately running
## alongside the room's outer wall without ever entering it — reveals it
## as a light_bfs() "boundary" surface (see _commit_visibility_from_
## centers()'s dim_boundary/bright_boundary handling). Checking "either
## cell" then let a still-closed room's own ROOM-FACING copy of that
## same wall tile's edge ride along on fog picked up from the totally
## unrelated OTHER face of the same physical wall — a leak this fix's
## own near-face routing above was never scoped to catch, since it isn't
## a near-face cell at all. Only a cell that's a genuine floor tile
## (grid.cell_texture.has(cell)) has a fog_of_war value that actually
## means "this specific side has been seen" — a wall/void cell's own
## entry is incidental to whichever side reached it first and says
## nothing about the OTHER side, so it's skipped here entirely rather
## than trusted. A _build_room_wall_edges() entry (room near-face cell +
## corridor cell) has two real floor cells either way, so this doesn't
## change that case's already-correct behaviour at all.
func _wall_edge_visible(edge: Dictionary) -> bool:
	for cell in edge.get("cells", []):
		if not grid.cell_texture.has(cell):
			continue
		if _marker_fog(cell) >= 1:
			return true
	return false

## Real World Map ground art (per the request: "update the battle map
## (non dungeon) tile art, use the updated ones from the world map") —
## replaces the old hand-drawn speckle/tuft-mark ground texture
## (_draw_grass_texture/_draw_mud_texture, now superseded) with actual
## painterly tiles sampled straight out of the same assets/tiles/
## tileset.png the Overworld map itself uses (see overworld.gd's own
## GRASS_VARIANT_ATLAS/TILE_ATLAS — this reuses those exact atlas
## columns for visual consistency between the two maps). A single-row
## strip of WORLD_TILE_PX-wide cells, so picking a variant is just an
## x-offset into the shared texture — no separate resource/import per
## tile needed.
const WORLD_TILESET: Texture2D = preload("res://assets/tiles/tileset.png")
const WORLD_TILE_PX := 64
## Same six grass columns overworld.gd's own GRASS_VARIANT_ATLAS picks
## from (0, 34, 35, 42, 43, 44) — deliberately the identical set, not
## just "similar", so a village's field-encounter battle map reads as
## the same ground the player was just walking on in Overworld.
const GRASS_TILE_VARIANTS: Array[int] = [0, 34, 35, 42, 43, 44]
## The World Map only has two plain, un-blended dirt/mud columns of its
## own (outdoor mud path "G" at 18, tilled farmland "A" at 19) — no
## equivalent multi-variant list exists there to mirror, so this is the
## full set rather than a curated subset.
## Per the follow-up request ("add variation to the water and mud
## tiles"): two new worn-dirt columns (166, 167 — footprint/track
## variants generated to match the existing 18/19 soft mud style, see
## claude/tile_variation_water_mud_v0.3.106.md) alongside the original
## pair. Deliberately left OUT: the same generation batch's wheel-rut
## variants — a 3x3 repeat-tile check showed strong visible vertical
## banding (ruts read as a mechanical repeating stripe rather than
## organic wear), so those weren't added to the atlas at all.
const MUD_TILE_VARIANTS: Array[int] = [18, 19, 166, 167]

## Per the follow-up request ("can we use the overworld water instead
## and use all the edging already built for those"): Pond's own shore
## art (v0.3.101's generated pond_water.png/pond_edge.png) is replaced
## by the exact same water/shore atlas columns OverworldMap's own lakes
## use in this same tileset.png — see OverworldMap._resolve_shore_atlas()
## / _resolve_tile_atlas() in scripts/game/overworld.gd, which this is
## a direct port of. Two things carry over unchanged from that system:
## (1) the shore/corner/three-sided/isthmus/diagonal tiles are all
## authored GRASS-side (mostly grass/land colour, with water notching
## in from whichever edge) — there's no water-side "grass notch" tile —
## so exactly like overworld, these get drawn on the plain GROUND square
## bordering a Pond, not on the Pond square itself (see
## _resolve_water_shore_atlas(), called from the main per-square loop's
## plain-ground branch); (2) which single tile applies is decided purely
## by a same-priority cascade over the 4 orthogonal Pond/non-Pond
## neighbours (isolated -> three-sided -> isthmus/corner -> single edge
## -> diagonal-only), reusing BattleGrid.obstacle_type as the "is this
## neighbour Pond" test in place of overworld's tile_chars.
const WATER_SHALLOW_ATLAS := Vector2i(2, 0)
## Per the follow-up request ("add variation to the water and mud
## tiles... apply to battlemap and overworld"): open water (a Pond
## square, or a terrain-water block) previously always drew the exact
## same WATER_SHALLOW_ATLAS tile with zero variation. These three new
## columns (163-165, generated to match the existing calm blue-teal
## painterly water style — see claude/tile_variation_water_mud_v0.3.106.md)
## are picked per-square alongside the original, the same way
## GRASS_TILE_VARIANTS/MUD_TILE_VARIANTS include their own base tile as
## one of the choices. A fourth generated variant (a tight circular
## swirl/whirlpool) was deliberately left OUT of the atlas — tiled
## across a whole pond it reads as an obviously repeating spiral rather
## than open water, per the same repeat-tile check used to drop the mud
## rut tiles above.
const WATER_SHALLOW_VARIANTS: Array[int] = [2, 163, 164, 165]
const WATER_SHORE_N_VARIANTS: Array[Vector2i] = [Vector2i(36, 0), Vector2i(121, 0), Vector2i(125, 0), Vector2i(129, 0), Vector2i(130, 0), Vector2i(131, 0)]
const WATER_SHORE_S_VARIANTS: Array[Vector2i] = [Vector2i(37, 0), Vector2i(122, 0), Vector2i(126, 0), Vector2i(132, 0)]
const WATER_SHORE_E_VARIANTS: Array[Vector2i] = [Vector2i(38, 0), Vector2i(123, 0), Vector2i(127, 0), Vector2i(133, 0)]
const WATER_SHORE_W_VARIANTS: Array[Vector2i] = [Vector2i(39, 0), Vector2i(124, 0), Vector2i(128, 0), Vector2i(134, 0)]
const WATER_CORNER_NE_ATLAS := Vector2i(49, 0)
const WATER_CORNER_NW_ATLAS := Vector2i(50, 0)
const WATER_CORNER_SE_ATLAS := Vector2i(51, 0)
const WATER_CORNER_SW_ATLAS := Vector2i(52, 0)
const WATER_THREE_N_ATLAS := Vector2i(58, 0)
const WATER_THREE_S_ATLAS := Vector2i(59, 0)
const WATER_THREE_E_ATLAS := Vector2i(60, 0)
const WATER_THREE_W_ATLAS := Vector2i(61, 0)
const WATER_ISOLATED_ATLAS := Vector2i(62, 0)
const WATER_ISTHMUS_NS_ATLAS := Vector2i(63, 0)
const WATER_ISTHMUS_EW_ATLAS := Vector2i(64, 0)
const WATER_DIAG_NE_ATLAS := Vector2i(72, 0)
const WATER_DIAG_NW_ATLAS := Vector2i(73, 0)
const WATER_DIAG_SE_ATLAS := Vector2i(74, 0)
const WATER_DIAG_SW_ATLAS := Vector2i(75, 0)

## Per the follow-up request ("lets work on the grass to mud edging
## transition"): a plain grass square bordering `grid.mud` used to just
## draw a flat GRASS_TILE_VARIANTS tile right up against a flat
## MUD_TILE_VARIANTS one — a hard, unblended seam, exactly the gap the
## Overworld map itself never had (OverworldMap._resolve_shore_atlas()
## already handles this there). This is a direct port of that same
## already-painted grass<->mud shore art (same shared tileset.png, same
## atlas columns — no new art needed) via the same
## "N/S/E/W straight edge (with hand-painted variants) + corner +
## three-sided + isolated + isthmus + diagonal-only notch" cascade
## _resolve_water_shore_atlas() above already ports for water.
## v0.3.108: straight-edge + corner mud shore art replaced with new,
## smoother Gemini-generated tiles (gentle undulating curve, soft blend)
## at cols 182-189, superseding the reused-overworld art at 45-56/135-142.
## Three-sided/isolated/isthmus/diagonal cases still use the old art below.
const MUD_SHORE_N_VARIANTS: Array[Vector2i] = [Vector2i(182, 0)]
const MUD_SHORE_S_VARIANTS: Array[Vector2i] = [Vector2i(183, 0)]
const MUD_SHORE_E_VARIANTS: Array[Vector2i] = [Vector2i(184, 0)]
const MUD_SHORE_W_VARIANTS: Array[Vector2i] = [Vector2i(185, 0)]
const MUD_CORNER_NE_ATLAS := Vector2i(186, 0)
const MUD_CORNER_NW_ATLAS := Vector2i(187, 0)
const MUD_CORNER_SE_ATLAS := Vector2i(188, 0)
const MUD_CORNER_SW_ATLAS := Vector2i(189, 0)
const MUD_THREE_N_ATLAS := Vector2i(65, 0)
const MUD_THREE_S_ATLAS := Vector2i(66, 0)
const MUD_THREE_E_ATLAS := Vector2i(67, 0)
const MUD_THREE_W_ATLAS := Vector2i(68, 0)
const MUD_ISOLATED_ATLAS := Vector2i(69, 0)
const MUD_ISTHMUS_NS_ATLAS := Vector2i(70, 0)
const MUD_ISTHMUS_EW_ATLAS := Vector2i(71, 0)
const MUD_DIAG_NE_ATLAS := Vector2i(76, 0)
const MUD_DIAG_NW_ATLAS := Vector2i(77, 0)
const MUD_DIAG_SE_ATLAS := Vector2i(78, 0)
const MUD_DIAG_SW_ATLAS := Vector2i(79, 0)

## Deterministic per-square, per-direction variant pick among a
## SHORE_*_VARIANTS array (same _hash01 salting convention
## _world_tile_variant() above uses) — mirrors OverworldMap's own
## _shore_variant_index(), just built on this file's existing hash
## helper instead of duplicating its FNV-style mixing (the two hashes
## don't need to match bit-for-bit; only their own determinism matters).
func _water_shore_variant_index(sq: Vector2i, count: int, salt: int) -> int:
	var h: float = _hash01(sq.x, sq.y, salt)
	return clampi(int(h * count), 0, count - 1)

## Per the follow-up request ("fill this in with the same tiles as
## overworld water rather then Grey tiles. allow this water to merge
## with ponds too"): "is this neighbour water" now covers TWO sources —
## a real Pond obstacle square, or one of BattleGrid's own `water`
## squares (the terrain-snapshot squares sourced from overworld water,
## see game_state.gd's pending_battle_water). Treating both the same
## way here is exactly what makes a Pond and an adjacent water block
## merge seamlessly — the shore/corner cascade below can't tell (and
## doesn't need to tell) which kind of water it's bordering.
func _is_water_square(sq: Vector2i) -> bool:
	return grid.obstacle_type.get(sq, "") == "Pond" or grid.water.has(sq)

## Returns the tileset.png atlas coord to draw on `sq` — a plain ground
## square, never a water square itself — if it borders water (Pond or
## overworld-sourced terrain water, see _is_water_square above), or
## Vector2i(-1, -1) if it doesn't border any water at all (the caller
## then falls back to the plain grass/mud tile). See this section's own
## opening comment for the full "why" and the priority cascade.
func _resolve_water_shore_atlas(sq: Vector2i) -> Vector2i:
	var n: bool = _is_water_square(sq + Vector2i(0, -1))
	var s: bool = _is_water_square(sq + Vector2i(0, 1))
	var e: bool = _is_water_square(sq + Vector2i(1, 0))
	var w: bool = _is_water_square(sq + Vector2i(-1, 0))
	var orth_count: int = int(n) + int(s) + int(e) + int(w)
	if orth_count == 4:
		return WATER_ISOLATED_ATLAS
	if orth_count == 3:
		if not n:
			return WATER_THREE_N_ATLAS
		if not s:
			return WATER_THREE_S_ATLAS
		if not e:
			return WATER_THREE_E_ATLAS
		return WATER_THREE_W_ATLAS
	if orth_count == 2:
		if n and s:
			return WATER_ISTHMUS_NS_ATLAS
		if e and w:
			return WATER_ISTHMUS_EW_ATLAS
		if n and e:
			return WATER_CORNER_NE_ATLAS
		if n and w:
			return WATER_CORNER_NW_ATLAS
		if s and e:
			return WATER_CORNER_SE_ATLAS
		return WATER_CORNER_SW_ATLAS
	if orth_count == 1:
		if n:
			return WATER_SHORE_N_VARIANTS[_water_shore_variant_index(sq, WATER_SHORE_N_VARIANTS.size(), 101)]
		if s:
			return WATER_SHORE_S_VARIANTS[_water_shore_variant_index(sq, WATER_SHORE_S_VARIANTS.size(), 211)]
		if e:
			return WATER_SHORE_E_VARIANTS[_water_shore_variant_index(sq, WATER_SHORE_E_VARIANTS.size(), 307)]
		return WATER_SHORE_W_VARIANTS[_water_shore_variant_index(sq, WATER_SHORE_W_VARIANTS.size(), 401)]
	## No orthogonal contact at all -- a single diagonal-only touch (a
	## "stairstep" pond corner) still gets a small notch instead of
	## reading as plain, disconnected ground right next to the water.
	if _is_water_square(sq + Vector2i(1, -1)):
		return WATER_DIAG_NE_ATLAS
	if _is_water_square(sq + Vector2i(-1, -1)):
		return WATER_DIAG_NW_ATLAS
	if _is_water_square(sq + Vector2i(1, 1)):
		return WATER_DIAG_SE_ATLAS
	if _is_water_square(sq + Vector2i(-1, 1)):
		return WATER_DIAG_SW_ATLAS
	return Vector2i(-1, -1)

## Returns the tileset.png atlas coord to draw on `sq` — a plain GRASS
## ground square (never called for a mud square itself, which always
## just draws its own flat MUD_TILE_VARIANTS tile — same "shore art
## lives on the grass side" convention OverworldMap and
## _resolve_water_shore_atlas() above both already use) — if it borders
## `grid.mud`, or Vector2i(-1, -1) if it doesn't border any mud at all
## (the caller then falls back to the plain grass tile). Structurally
## identical to _resolve_water_shore_atlas() above, just against
## grid.mud instead of _is_water_square().
func _resolve_mud_shore_atlas(sq: Vector2i) -> Vector2i:
	var n: bool = grid.mud.has(sq + Vector2i(0, -1))
	var s: bool = grid.mud.has(sq + Vector2i(0, 1))
	var e: bool = grid.mud.has(sq + Vector2i(1, 0))
	var w: bool = grid.mud.has(sq + Vector2i(-1, 0))
	var orth_count: int = int(n) + int(s) + int(e) + int(w)
	if orth_count == 4:
		return MUD_ISOLATED_ATLAS
	if orth_count == 3:
		if not n:
			return MUD_THREE_N_ATLAS
		if not s:
			return MUD_THREE_S_ATLAS
		if not e:
			return MUD_THREE_E_ATLAS
		return MUD_THREE_W_ATLAS
	if orth_count == 2:
		if n and s:
			return MUD_ISTHMUS_NS_ATLAS
		if e and w:
			return MUD_ISTHMUS_EW_ATLAS
		if n and e:
			return MUD_CORNER_NE_ATLAS
		if n and w:
			return MUD_CORNER_NW_ATLAS
		if s and e:
			return MUD_CORNER_SE_ATLAS
		return MUD_CORNER_SW_ATLAS
	if orth_count == 1:
		if n:
			return MUD_SHORE_N_VARIANTS[_water_shore_variant_index(sq, MUD_SHORE_N_VARIANTS.size(), 613)]
		if s:
			return MUD_SHORE_S_VARIANTS[_water_shore_variant_index(sq, MUD_SHORE_S_VARIANTS.size(), 701)]
		if e:
			return MUD_SHORE_E_VARIANTS[_water_shore_variant_index(sq, MUD_SHORE_E_VARIANTS.size(), 809)]
		return MUD_SHORE_W_VARIANTS[_water_shore_variant_index(sq, MUD_SHORE_W_VARIANTS.size(), 907)]
	## No orthogonal contact at all -- a single diagonal-only touch still
	## gets a small notch instead of reading as plain, disconnected
	## grass right next to the mud.
	if grid.mud.has(sq + Vector2i(1, -1)):
		return MUD_DIAG_NE_ATLAS
	if grid.mud.has(sq + Vector2i(-1, -1)):
		return MUD_DIAG_NW_ATLAS
	if grid.mud.has(sq + Vector2i(1, 1)):
		return MUD_DIAG_SE_ATLAS
	if grid.mud.has(sq + Vector2i(-1, 1)):
		return MUD_DIAG_SW_ATLAS
	return Vector2i(-1, -1)

## Picks one of `variants` for `sq`, deterministic (via _hash01, same
## reasoning as the old speckle marks — a real randf() would re-roll
## every redraw) so a given square always shows the same tile variant
## instead of flickering between them.
func _world_tile_variant(sq: Vector2i, variants: Array, salt: int) -> int:
	var h: float = _hash01(sq.x, sq.y, salt)
	var idx: int = int(h * variants.size())
	return variants[clampi(idx, 0, variants.size() - 1)]

## Draws `sq`'s plain-ground base fill as a real tileset.png tile region
## (grass or mud/dirt, whichever `is_mud` selects) stretched across the
## square's own on-screen rect — replaces the old flat-colour fill plus
## hand-drawn speckle overlay entirely; the real art already carries its
## own texture, no separate decoration pass needed on top.
func _draw_world_ground_tile(rect: Rect2, sq: Vector2i, is_mud: bool) -> void:
	var variants: Array = MUD_TILE_VARIANTS if is_mud else GRASS_TILE_VARIANTS
	var idx: int = _world_tile_variant(sq, variants, 1300 if is_mud else 1200)
	var src_rect := Rect2(idx * WORLD_TILE_PX, 0, WORLD_TILE_PX, WORLD_TILE_PX)
	draw_texture_rect_region(WORLD_TILESET, rect, src_rect)

## Draws a plain open-water square (a Pond obstacle square, or a
## terrain-water block) with one of WATER_SHALLOW_VARIANTS instead of
## always the same flat WATER_SHALLOW_ATLAS tile — see that const's own
## comment. Salt 1400 is new (doesn't collide with 500/900/1100/1200/
## 1300 or the 101/211/307/401 shore salts already in use in this file).
## Per the request ("battle map forest sections... should change to be
## clumps of trees rather then the big square with green dot tiles...
## lets create a new forest floor tile, sort of a mix between the grass
## and mud tiles we have now. make forest floor to mud/grass/water
## edging too. The new tiles should be under and surround all tree
## tiles in that area"): every `is_cover` square (still terrain-sourced,
## see BattleGrid.cover's own comment — unchanged mechanically, still
## drives the ranged cover bonus) now draws real tileset.png art instead
## of the old flat Color(0.10, 0.30, 0.11) fill plus dot marker. Two
## plain base variants (168/169 — a mossy leaf-litter mix, generated to
## sit visually between the existing grass and mud tiles) are picked
## per-square exactly like GRASS_TILE_VARIANTS/MUD_TILE_VARIANTS/
## WATER_SHALLOW_VARIANTS above (salt 1500, new/unused). Tree obstacles
## themselves (see BattleGrid._scatter_forest_trees()) are scattered
## densely-but-passably across these same `cover` squares, so this ground
## art sits under and around every tree exactly as requested.
const FOREST_FLOOR_VARIANTS: Array[int] = [168, 169]
## Single-edge blend tiles (170-181), one set per neighbour kind
## (grass/mud/water), authored facing North (neighbour-material on the
## tile's own top edge, forest floor on the bottom) and derived for the
## other 3 directions via plain 90-degree rotation — same "author one
## real edge, reuse via rotation" shortcut as everywhere else in this
## project that doesn't need the full shore corner/isthmus cascade
## (this is deliberately simpler than _resolve_water_shore_atlas() below
## — the request only asked for straight edging, not corners).
const FOREST_EDGE_ATLAS: Dictionary = {
	"grass": {"N": 170, "S": 171, "E": 172, "W": 173},
	"mud": {"N": 174, "S": 175, "E": 176, "W": 177},
	"water": {"N": 178, "S": 179, "E": 180, "W": 181},
}
## Corner blend tiles (190-193) for the case _draw_forest_floor_tile()
## used to fall back to plain floor on: two ADJACENT non-forest sides
## (e.g. N+E) that are both "grass". Per the request ("corner tiles of
## the forest are missing the edging effect, lets fix that so it
## matches the rest" -> follow-up "maybe it should just be grass"):
## scoped to the grass case only -- mud/water corners, opposite-side
## (N+S or E+W) pairs, and 3+-sided squares all still fall back to the
## plain FOREST_FLOOR_VARIANTS base tile exactly as before. Built by
## compositing the existing FOREST_EDGE_ATLAS["grass"] N/S/E/W tiles'
## own pure-grass texture with the plain floor tile (168), rounded with
## a small corner-radius blend so the two straight edges meet in a soft
## curve instead of a hard square notch -- not a fresh Gemini
## generation, since those two edge tiles are already the approved art
## for exactly these two materials.
const FOREST_CORNER_GRASS_ATLAS: Dictionary = {
	"NE": 190, "NW": 191, "SE": 192, "SW": 193,
}

## Classifies `sq` for forest-floor edge-blend purposes: "forest" (also
## cover -- no edge needed against it), "water" (real Pond/terrain-water,
## reusing _is_water_square()'s own two-source check), "mud"
## (grid.mud), or "grass" (anything else plain — the default/fallback
## kind, matching how _draw_world_ground_tile() itself treats "not mud"
## as grass).
func _forest_neighbor_kind(sq: Vector2i) -> String:
	if grid.is_covered(sq):
		return "forest"
	if _is_water_square(sq) or grid.water.has(sq):
		return "water"
	if grid.mud.has(sq):
		return "mud"
	return "grass"

## Draws `sq`'s forest-floor ground art — see FOREST_FLOOR_VARIANTS/
## FOREST_EDGE_ATLAS/FOREST_CORNER_GRASS_ATLAS's own comments above. A
## single, unambiguous non-forest neighbour (exactly one of N/S/E/W)
## gets an edge blend; two ADJACENT non-forest sides that are both
## "grass" get a rounded corner blend; anything else (zero non-forest
## sides, an opposite N+S/E+W pair, 3+ sides, or a 2-sided corner
## touching a non-grass kind) falls back to the plain base tile rather
## than picking an arbitrary side.
func _draw_forest_floor_tile(rect: Rect2, sq: Vector2i) -> void:
	var kinds: Dictionary = {
		"N": _forest_neighbor_kind(sq + Vector2i(0, -1)),
		"S": _forest_neighbor_kind(sq + Vector2i(0, 1)),
		"E": _forest_neighbor_kind(sq + Vector2i(1, 0)),
		"W": _forest_neighbor_kind(sq + Vector2i(-1, 0)),
	}
	var edge_dir: String = ""
	var edge_kind: String = ""
	var non_forest_count: int = 0
	for dir in kinds:
		var kind: String = kinds[dir]
		if kind != "forest":
			non_forest_count += 1
			edge_dir = dir
			edge_kind = kind
	var idx: int
	if non_forest_count == 1 and FOREST_EDGE_ATLAS.has(edge_kind):
		idx = FOREST_EDGE_ATLAS[edge_kind][edge_dir]
	elif non_forest_count == 2 and kinds["N"] == "grass" and kinds["E"] == "grass":
		idx = FOREST_CORNER_GRASS_ATLAS["NE"]
	elif non_forest_count == 2 and kinds["N"] == "grass" and kinds["W"] == "grass":
		idx = FOREST_CORNER_GRASS_ATLAS["NW"]
	elif non_forest_count == 2 and kinds["S"] == "grass" and kinds["E"] == "grass":
		idx = FOREST_CORNER_GRASS_ATLAS["SE"]
	elif non_forest_count == 2 and kinds["S"] == "grass" and kinds["W"] == "grass":
		idx = FOREST_CORNER_GRASS_ATLAS["SW"]
	else:
		idx = _world_tile_variant(sq, FOREST_FLOOR_VARIANTS, 1500)
	draw_texture_rect_region(WORLD_TILESET, rect, Rect2(idx * WORLD_TILE_PX, 0, WORLD_TILE_PX, WORLD_TILE_PX))

func _draw_water_tile(rect: Rect2, sq: Vector2i) -> void:
	var idx: int = _world_tile_variant(sq, WATER_SHALLOW_VARIANTS, 1400)
	draw_texture_rect_region(WORLD_TILESET, rect, Rect2(idx * WORLD_TILE_PX, 0, WORLD_TILE_PX, WORLD_TILE_PX))

## Hand-drawn per-square detail for every obstacle type (per the
## follow-up request: "let's review those obstacles... make detailed
## Tiles of these") — same "no external art assets, everything
## procedurally drawn" convention the rest of this file already follows.
## `rect` is the square's own drawn rect (already zoom/pan-transformed by
## the caller's draw_set_transform in _draw()); `s` is its width, the one
## shared scale every shape below is sized off of. HighGrass uses `sq`
## (via _hash01) to vary each square's own detail a little, so a
## multi-square clump doesn't look like the same tile stamped over and
## over. Only ever called for Tree/Bush (always exactly 1 square, so
## there's no multi-square footprint to stretch across) and
## HighGrass/Fence (naturally per-square texture/topology — grass
## blades, fence posts+rails) — see _draw_obstacle_detail_stretched()
## below for the "solid mass" types (Boulder/Pond/BrokenCart/Structure)
## that DO span multiple squares.
func _draw_obstacle_detail(rect: Rect2, type_name: String, sq: Vector2i) -> void:
	match type_name:
		"Tree":
			## Slightly bigger than the square (1.15x) so the canopy
			## overlaps its own tile edges a little, same "reads as a
			## real object standing on the ground" overscan the old
			## hand-drawn canopy circles had.
			_draw_icon_centered(OBSTACLE_TREE_TEX, rect, 1.15)
		"Bush":
			_draw_icon_centered(OBSTACLE_BUSH_TEX, rect, 1.05)
		"HighGrass":
			## A HighGrass instance is a multi-square "clump" (see
			## BattleGrid._shape_clump) — mirroring the same tuft image
			## horizontally on roughly half of its squares (deterministic
			## per-square via _hash01, not re-rolled every redraw) keeps a
			## several-square clump from reading as one icon visibly
			## stamped over and over.
			var flip: bool = _hash01(sq.x, sq.y, 1100) < 0.5
			_draw_icon_centered(OBSTACLE_HIGHGRASS_TEX, rect, 1.1, flip)
		"Fence":
			_draw_fence_detail(rect, sq)
		"Pond":
			_draw_pond_tile(rect, sq)

## Draws `tex` centered on `rect`, uniformly scaled (preserving its own
## aspect ratio) so its larger dimension fits `rect.size.x * scale_mult`
## — used for the obstacle types drawn once per occupied square (Tree/
## Bush/HighGrass) rather than stretched across a multi-square instance.
## `flip_h` mirrors it horizontally (via a negative-width dest rect, no
## transform needed) for the HighGrass per-square variation above.
func _draw_icon_centered(tex: Texture2D, rect: Rect2, scale_mult: float = 1.0, flip_h: bool = false) -> void:
	var tex_size: Vector2 = tex.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var target: float = rect.size.x * scale_mult
	var fit_scale: float = min(target / tex_size.x, target / tex_size.y)
	var draw_w: float = tex_size.x * fit_scale
	var draw_h: float = tex_size.y * fit_scale
	var c := rect.get_center()
	var draw_rect := Rect2(c.x - draw_w * 0.5, c.y - draw_h * 0.5, draw_w, draw_h)
	if flip_h:
		draw_rect = Rect2(draw_rect.position + Vector2(draw_rect.size.x, 0.0), Vector2(-draw_rect.size.x, draw_rect.size.y))
	draw_texture_rect(tex, draw_rect, false)

## Per the follow-up request ("stretch obstacle icon images rather than
## tiling them in their assigned area's"): the "solid mass" obstacle
## types' own hand-drawn detail, called ONCE per obstacle instance (see
## _draw()'s own instance loop) with `rect` set to that instance's FULL
## footprint bounding box — not one square. Uses `rect`'s real width
## (sx) and height (sy) separately rather than a single shared `s`, so
## the artwork actually fills/stretches across the whole assigned area
## instead of staying pinned to a single square's worth of space in one
## corner of it. Circular/radius-based features use `sr` (the SMALLER of
## sx/sy) as their shared scale instead of stretching into ellipses —
## reads as "one coherent cluster spread across the whole footprint"
## rather than a single circle warped out of shape on a strongly
## non-square (e.g. a wide-but-short Large) bounding box.
## Maps a Room Furniture piece's own `facing` (see BattleGrid.
## furniture_markers' own declaration comment — points away from the
## wall the piece is flush against, into the room) to the draw_set_
## transform() rotation angle that turns its south-facing base art
## (wall at the top of the image, open side at the bottom) to face that
## direction instead. South needs no rotation (0); the other three walls
## rotate the art a quarter-turn at a time.
func _furniture_rotation(facing: Vector2i) -> float:
	if facing == Vector2i(0, -1):
		return PI          ## north wall -> art rotated a half-turn to face north
	if facing == Vector2i(-1, 0):
		return PI / 2.0    ## east wall -> faces west
	if facing == Vector2i(1, 0):
		return -PI / 2.0   ## west wall -> faces east
	return 0.0              ## south (or unset/defensive default) -> art's own native facing

func _draw_obstacle_detail_stretched(rect: Rect2, type_name: String, sq: Vector2i) -> void:
	## Real generated art, stretched to fill the whole instance footprint
	## exactly like the old hand-drawn shapes already did (non-uniform
	## stretch — sx/sy independently — so e.g. a wide-but-short Large
	## instance still fills its own bounding box completely rather than
	## letterboxing). OBSTACLE_FILL_COLOR's own flat base fill (see
	## _draw()'s solid_obstacle branch) still paints first underneath, so
	## any transparent fringe on the art's own edge still reads as solid
	## ground/water colour rather than showing grid squares through it.
	match type_name:
		"Boulder":
			draw_texture_rect(OBSTACLE_BOULDER_TEX, rect, false)
		"BrokenCart":
			draw_texture_rect(OBSTACLE_BROKEN_CART_TEX, rect, false)
		"Structure":
			draw_texture_rect(OBSTACLE_STRUCTURE_TEX, rect, false)

## Fence/wall (per the follow-up request: "fences/walls (lines - in
## straight or L shape) - medium cover"): real generated art (a single
## post+rail segment authored to tile left-to-right — see
## OBSTACLE_FENCE_TEX's own declaration comment) drawn once per square
## for an east-west connection, and OBSTACLE_FENCE_VERTICAL_TEX's own
## dedicated north-south art (see its own declaration comment for why
## that's a separate asset now rather than the east-west tile rotated a
## quarter turn — per the follow-up request "the vertical fence have be
## more of a top down look and fit together nicely with the horizontal
## one") drawn plain (no rotation — it's already oriented correctly) for
## a north-south connection.
##
## Per the follow-up request ("vertical and horizontal fences need to
## connect cleanly post to post, lets rework those"): a bend square
## (connects both horizontally AND vertically) no longer draws both
## straight tiles overlapping — that put each tile's own half-post at a
## different edge of the square (see OBSTACLE_FENCE_CORNER_SE_TEX's own
## comment), reading as two disconnected posts. It now draws whichever of
## the four dedicated corner assets matches the two sides actually
## connected here (BattleGrid's Fence shape is always straight or bent
## exactly once — see _shape_line() — so a square is never connected on
## 3+ sides and exactly one of has_e/has_w and one of has_n/has_s is ever
## true here).
func _draw_fence_detail(rect: Rect2, sq: Vector2i) -> void:
	var gid = grid.obstacle_group.get(sq, -1)
	var has_e: bool = grid.obstacle_group.get(sq + Vector2i(1, 0), -2) == gid
	var has_w: bool = grid.obstacle_group.get(sq + Vector2i(-1, 0), -2) == gid
	var has_n: bool = grid.obstacle_group.get(sq + Vector2i(0, -1), -2) == gid
	var has_s: bool = grid.obstacle_group.get(sq + Vector2i(0, 1), -2) == gid
	var horizontal: bool = has_e or has_w
	var vertical: bool = has_n or has_s
	## An isolated fence square (no connected neighbour at all — a
	## single-square instance) still needs to draw SOMETHING; default to
	## the east-west art's own native orientation.
	if not horizontal and not vertical:
		horizontal = true
	if horizontal and vertical:
		## Four pre-flipped files, one per bend orientation (see the
		## OBSTACLE_FENCE_CORNER_*_TEX declarations' own comment for why
		## these aren't one asset mirrored at draw time) — pick the one
		## matching whichever two sides are actually connected here.
		var corner_tex: Texture2D
		if has_e and has_s:
			corner_tex = OBSTACLE_FENCE_CORNER_SE_TEX
		elif has_w and has_s:
			corner_tex = OBSTACLE_FENCE_CORNER_SW_TEX
		elif has_e and has_n:
			corner_tex = OBSTACLE_FENCE_CORNER_NE_TEX
		else:
			corner_tex = OBSTACLE_FENCE_CORNER_NW_TEX
		_draw_icon_centered(corner_tex, rect, 1.0)
	elif horizontal:
		_draw_icon_centered(OBSTACLE_FENCE_TEX, rect, 1.0)
	elif vertical:
		_draw_icon_centered(OBSTACLE_FENCE_VERTICAL_TEX, rect, 1.0)

## Water (per the follow-up request: "can we use the overworld water
## instead and use all the edging already built for those" — superseding
## v0.3.101's own generated pond_water.png/pond_edge.png): a Pond square
## itself just draws WATER_SHALLOW_ATLAS, the same plain-water tile
## OverworldMap's own lakes use — no per-square edge notch belongs HERE
## at all, since (per this system's own design, mirrored from
## OverworldMap) every shore notch is authored grass-side and drawn on
## the bordering GROUND square instead — see
## _resolve_water_shore_atlas()'s own comment for the full picture.
func _draw_pond_tile(rect: Rect2, sq: Vector2i) -> void:
	_draw_water_tile(rect, sq)

## `is_dark`/`light_sources`, per the day/night & light-source-in-combat
## request: whether this battle is genuinely dark right now
## (FieldEncounter's own battle_is_dark, captured once at the start of
## the fight) and every living combatant's own active light source, as
## {"pos": Vector2i, "radius": int} pairs — see FieldEncounter._gather_
## battle_light_sources(). Purely visual here; the actual Melee/Ranged
## Darkness penalty is computed independently in FieldEncounter's own
## _darkness_penalty(), which this just mirrors on-screen.
## Per the follow-up request ("add a red tint at low health"):
## new_icon_modulates optionally maps a Character -> Color to multiply
## its token icon by (see CareerPortraits.wound_modulate_for_character),
## on top of the existing is_down grey-out. Defaults to {} (no tint) so
## every other caller keeps working unchanged.
## `new_ground_fire_squares`, per the ground fire visual (see
## ground_fire_squares' own declaration comment): the union of every
## currently-active persistent_aoe_hazard's squares. Also defaults to
## [] so every other caller keeps working unchanged.
## `new_smoke_squares`, per the Smoke Breath visual (see smoke_squares'
## own declaration comment): the union of every currently-active
## active_smoke_cloud's squares. Also defaults to [] so every other
## caller keeps working unchanged.
func set_state(new_grid: BattleGrid, new_positions: Dictionary, current: Character, target: Character, new_icons: Dictionary = {}, new_names: Dictionary = {}, is_dark: bool = false, light_sources: Array = [], new_icon_modulates: Dictionary = {}, new_ground_fire_squares: Array = [], new_smoke_squares: Array = []) -> void:
	grid = new_grid
	positions = new_positions
	current_turn_character = current
	selected_target = target
	icons = new_icons
	icon_modulates = new_icon_modulates
	names = new_names
	battle_dark_active = is_dark
	dark_light_sources = light_sources
	ground_fire_squares = new_ground_fire_squares
	smoke_squares = new_smoke_squares
	queue_redraw()

## True once battle_dark_active whenever `sq` isn't within reach of any
## currently-active light source — see _draw()'s own darkness tint pass.
func _square_lit(sq: Vector2i) -> bool:
	for src in dark_light_sources:
		if BattleGrid.distance_squares(src["pos"], sq) <= int(src["radius"]):
			return true
	return false

## Per the request: move the yellow "focus" ring to the newly-selected
## target immediately, whether the click came from the grid itself or
## from the enemy list above it — rather than waiting for the next full
## _render_status()/set_state() pass (which only happens on the next
## turn/action and made the ring lag a beat behind the actual selection).
## A standalone setter rather than routing every _select_target() call
## through set_state() so this stays a cheap "just move the ring" update
## with no need to rebuild positions/icons/names along the way.
func set_selected_target(target: Character) -> void:
	selected_target = target
	queue_redraw()

func highlight_squares(squares: Array) -> void:
	highlighted.clear()
	for s in squares:
		highlighted[s] = true
	queue_redraw()

func clear_highlight() -> void:
	highlighted.clear()
	queue_redraw()

## AoE free-target spell/prayer preview (Blast, Twin-tailed Comet):
## replaces the whole preview set every call (same convention as
## highlight_squares) — FieldEncounterScreen recomputes it on every
## hover via BattleGrid.squares_within_radius(). An empty array clears
## the preview, same as clear_highlight() does for Move.
func set_aoe_preview(squares: Array) -> void:
	aoe_preview.clear()
	for s in squares:
		aoe_preview[s] = true
	queue_redraw()

func set_preview_path(path: Array) -> void:
	preview_path = path
	queue_redraw()

func set_hover_target(square: Vector2i, valid: bool) -> void:
	hover_target = square
	hover_target_valid = valid
	queue_redraw()

## `targets`: enemy squares to draw the secondary Charge-range arrow to;
## `origin`: the Move-preview hover square they're drawn from. An empty
## `targets` array (or origin == Vector2i(-1, -1)) draws nothing, same
## clear convention as set_preview_path([]).
func set_charge_preview(targets: Array, origin: Vector2i) -> void:
	charge_preview_targets = targets
	charge_preview_origin = origin
	queue_redraw()

## Per the follow-up request ("if the active character is within charge
## range of the selected target draw a Red arrow line from that
## character to the target"): `target_square` is the selected target's
## own square to draw the static Charge-ready arrow to, or
## Vector2i(-1, -1) to clear it (no Charge currently available). See
## charge_ready_target's own comment for how this differs from
## set_charge_preview above.
func set_charge_ready(target_square: Vector2i) -> void:
	charge_ready_target = target_square
	queue_redraw()

## Replaces the whole set of currently-valid target squares (see
## target_arrows above) — an empty array clears every arrow, same
## convention as clear_highlight()/set_aoe_preview([]).
func set_target_arrows(squares: Array) -> void:
	target_arrows = squares
	queue_redraw()

## Live hover-tracked focus target (see target_focus_square above) —
## called on every grid hover while ranged targeting mode is active.
## `readout` is whatever small "distance — range band" string should
## float above the crosshair; pass an empty string for no readout.
## Vector2i(-1, -1) clears the crosshair entirely (nothing currently
## hovered over a valid target).
func set_target_focus(square: Vector2i, readout: Array = []) -> void:
	target_focus_square = square
	target_focus_segments = readout
	queue_redraw()

## Per the request ("hovering over any character or monster on the
## battle map should bring up a small tooltip box with their vital
## stats"): `lines` is an Array of {"text": String, "color": Color,
## "bold": bool (optional)} dicts — see FieldEncounterScreen's own
## _hover_tooltip_lines() for what actually populates it. An empty
## array hides the tooltip, same "empty clears it" convention every
## other setter on this node already uses.
func set_hover_tooltip(lines: Array) -> void:
	if _hover_tooltip == null:
		return
	if lines.is_empty():
		_hover_tooltip.visible = false
		return
	for child in _hover_tooltip_vbox.get_children():
		child.queue_free()
	for entry in lines:
		var lbl := Label.new()
		lbl.text = String(entry.get("text", ""))
		lbl.add_theme_font_size_override("font_size", 12 if entry.get("bold", false) else 10)
		lbl.add_theme_color_override("font_color", entry.get("color", Color(0.9, 0.9, 0.85)))
		_hover_tooltip_vbox.add_child(lbl)
	_hover_tooltip.visible = true
	## Positioned near the last real hover position, clamped so it never
	## spills past this control's own right/bottom edge (e.g. hovering a
	## token right at the edge of the visible map). get_combined_min_size()
	## reads the freshly-set content's real size immediately, without
	## waiting a frame for layout to catch up.
	var tt_size: Vector2 = _hover_tooltip.get_combined_minimum_size()
	var pos: Vector2 = _last_hover_mouse_pos + Vector2(18, 18)
	pos.x = clampf(pos.x, 0.0, max(0.0, size.x - tt_size.x - 4.0))
	pos.y = clampf(pos.y, 0.0, max(0.0, size.y - tt_size.y - 4.0))
	_hover_tooltip.position = pos

## --- Attack FX (per the request: "add battle map animated attack gfx
## to Melee/Ranged and Magic/Pray rolls") ---------------------------------

## Grid-square -> local pixel center, same math _draw() already uses
## for token centers — public so field_encounter_screen.gd never needs
## to duplicate the origin/square_px calculation just to know where an
## FX should land.
func square_center_px(square: Vector2i) -> Vector2:
	var square_px := _square_px()
	if square_px <= 0.0:
		return Vector2.ZERO
	var origin := _grid_origin(square_px)
	return origin + Vector2((square.x + 0.5) * square_px, (square.y + 0.5) * square_px)

func _play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

## Per the request: every attack FX below spawns this whenever the hit
## actually dealt damage ("if the hit causes damage show a floating
## damage (after mitigation)") — `amount` is expected to already be the
## post-mitigation Wounds value, and this is a no-op for 0 (a hit that
## dealt no real damage after soak, or a miss/block passed in as 0 by
## the caller). `delay` lets the caller line this up with whatever
## impact beat (slash landing, projectile arriving) it should trail.
func _spawn_floating_damage(square: Vector2i, amount: int, color: Color, delay: float = 0.0) -> void:
	if amount <= 0:
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if not is_inside_tree():
			return
	var fx := BattleFxFloatingText.new()
	fx.position = square_center_px(square)
	fx_layer.add_child(fx)
	fx.setup(amount, color)

## Melee attack (per the request: "after the roll is complete for
## melee attack make a slashing weapons animation over the attacked
## enemy (if they defend a shield blocks it)"). `blocked` = the
## defender successfully Dodged/Parried (CombatResolver.AttackResult
## .hit == false, per field_encounter_screen.gd's own
## _play_combat_attack_fx) — shows a block spark instead of a landing
## slash, and never a damage number (a successful defense means there
## is none). `damage` is the post-mitigation Wounds actually dealt (0
## when blocked, or when a hit landed but dealt no Wounds after soak).
func play_melee_fx(attacker_square: Vector2i, defender_square: Vector2i, blocked: bool, damage: int) -> void:
	var target_pos := square_center_px(defender_square)
	if blocked:
		## Per the request ("keep the defended animation on the
		## defender"): a block is about the defender's own shield doing
		## the work, so the spark stays right where it always was.
		var fx := BattleFxBlock.new()
		fx.position = target_pos
		fx_layer.add_child(fx)
		_play_sfx(SFX_BLOCK)
	else:
		## Per the request ("the sweep happens on the attacker... at
		## the point of the icon ring closest to the defender"): the
		## slash now plays on the ATTACKER's own token, right at the
		## edge of their icon ring (the colored backdrop disc _draw()
		## gives every token — see _token_ring_radius()) facing the
		## defender, oriented to sweep outward toward them — reads as
		## the attacker swinging out at the target, rather than a slash
		## materializing on top of whoever got hit.
		var attacker_center := square_center_px(attacker_square)
		var dir: Vector2 = target_pos - attacker_center
		var fx := BattleFxSlash.new()
		if dir.length() > 0.001:
			fx.position = attacker_center + dir.normalized() * _token_ring_radius()
			fx.facing_degrees = rad_to_deg(dir.angle())
		else:
			fx.position = attacker_center   ## degenerate case: same square — shouldn't happen for a real melee attack
		fx_layer.add_child(fx)
		_play_sfx(SFX_SLASH)
		_spawn_floating_damage(defender_square, damage, Color(0.95, 0.35, 0.25), 0.12)

## The token backdrop disc's own on-screen radius, in the same
## unscaled content-space pixels _draw() itself uses for that disc
## (`half + 2.0`, where half is icon_size / 2 — see _draw()'s per-token
## rendering loop) — kept here as a small helper so play_melee_fx can
## place the slash exactly on that ring's edge instead of duplicating
## the math.
func _token_ring_radius() -> float:
	var square_px := _square_px()
	var icon_size: float = square_px * 0.85
	return icon_size / 2.0 + 2.0

## Ranged attack (per the request: "show a projectile either hit the
## target or nothing with a matching sound"). Always shows the
## projectile itself flying from attacker to defender; on a miss it
## flies past and fades rather than impacting — no impact flash, no
## damage number, and the softer "miss" sound instead of the "hit" one.
func play_ranged_fx(attacker_square: Vector2i, defender_square: Vector2i, hit: bool, damage: int) -> void:
	var proj := BattleFxProjectile.new()
	proj.start = square_center_px(attacker_square)
	proj.end = square_center_px(defender_square)
	proj.hit = hit
	proj.color = Color(0.85, 0.75, 0.4)
	fx_layer.add_child(proj)
	if hit:
		_play_sfx(SFX_RANGED_HIT)
		await get_tree().create_timer(BattleFxProjectile.TRAVEL_TIME).timeout
		if not is_inside_tree():
			return
		var impact := BattleFxImpact.new()
		impact.position = square_center_px(defender_square)
		impact.color = Color(0.9, 0.8, 0.5)
		fx_layer.add_child(impact)
		_spawn_floating_damage(defender_square, damage, Color(0.95, 0.35, 0.25))
	else:
		_play_sfx(SFX_RANGED_MISS, -4.0)

## Magic missile — a direct-target damage spell/prayer that succeeded
## (per the request: "if the succeed show a magical missile for direct
## attacks"). Same travelling-bolt shape as a ranged weapon, in a
## violet/arcane tint, always shown as a hit (this is only ever called
## once a spell/prayer has already been confirmed to have struck).
func play_magic_missile_fx(caster_square: Vector2i, target_square: Vector2i, damage: int) -> void:
	var proj := BattleFxProjectile.new()
	proj.start = square_center_px(caster_square)
	proj.end = square_center_px(target_square)
	proj.hit = true
	proj.color = Color(0.65, 0.45, 0.95)
	fx_layer.add_child(proj)
	_play_sfx(SFX_MAGIC_MISSILE)
	await get_tree().create_timer(BattleFxProjectile.TRAVEL_TIME).timeout
	if not is_inside_tree():
		return
	var impact := BattleFxImpact.new()
	impact.position = square_center_px(target_square)
	impact.color = Color(0.7, 0.5, 1.0)
	fx_layer.add_child(impact)
	_spawn_floating_damage(target_square, damage, Color(0.75, 0.55, 1.0))

## AoE spell/prayer that succeeded (per the request: "a Area explosion
## for AoE attack... if its a AoE attack hitting multiple show it on
## all targets that it hit"). `hits`: Array of {"square": Vector2i,
## "damage": int} — one explosion (plus, if it dealt damage, one
## floating number) per entry, all fired together rather than staggered,
## since a real Blast/Twin-tailed Comet lands on every target at once.
func play_aoe_explosion_fx(hits: Array) -> void:
	if hits.is_empty():
		return
	_play_sfx(SFX_EXPLOSION)
	for h in hits:
		var sq: Vector2i = h["square"]
		var explosion := BattleFxExplosion.new()
		explosion.position = square_center_px(sq)
		fx_layer.add_child(explosion)
		_spawn_floating_damage(sq, int(h.get("damage", 0)), Color(1.0, 0.65, 0.3), 0.15)
