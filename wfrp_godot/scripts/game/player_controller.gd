extends Node2D
## Grid-based (tile-snapped) player movement, JRPG-style: one tile per
## input, tweened for a smooth slide rather than an instant jump. The
## overworld script owns walkability/encounter logic — this just asks
## "can I move there?" and reports where it ends up.

signal moved(new_tile: Vector2i)

## Per the TILE_SIZE 16->64 upscale (overworld.gd): this is the world
## GRID pixel size used for movement/positioning, kept in lockstep with
## overworld.gd's own TILE_SIZE. It's deliberately NOT the same
## constant as SPRITE_FRAME_SIZE below — the player's sprite sheet
## itself stays native-resolution (16px-per-frame; "leave NPCs for now"
## covers the player too), scaled up visually via the Sprite2D's own
## `scale` (see Player.tscn and _apply_class_sprite()) rather than by
## changing what pixel region gets cropped out of the sheet.
const TILE_SIZE := 64
## The sprite sheet's own native per-frame size — unrelated to TILE_SIZE
## now that the two have diverged; used only by _update_sprite_frame()'s
## region_rect crop.
const SPRITE_FRAME_SIZE := 16
const MOVE_DURATION := 0.14
const FACING_OFFSETS := {
	"down": Vector2i(0, 1),
	"up": Vector2i(0, -1),
	"left": Vector2i(-1, 0),
	"right": Vector2i(1, 0),
}
const FACING_FRAMES := {"down": 0, "up": 1, "left": 2, "right": 3}
## Per the request: a distinct, more detailed sprite sheet per WFRP
## class — matches CareerDefinition.career_class exactly. Falls back
## to the plain "player.png" (the original generic sprite) for any
## class not in this map, or if no character/career is available yet.
const CLASS_SPRITE_PATHS := {
	"Warrior": "res://assets/sprites/player_warrior.png",
	"Ranger": "res://assets/sprites/player_ranger.png",
	"Rogue": "res://assets/sprites/player_rogue.png",
	"Academic": "res://assets/sprites/player_academic.png",
	"Burgher": "res://assets/sprites/player_burgher.png",
	"Courtier": "res://assets/sprites/player_courtier.png",
	"Peasant": "res://assets/sprites/player_peasant.png",
	"Riverfolk": "res://assets/sprites/player_riverfolk.png",
}
const DEFAULT_SPRITE_PATH := "res://assets/sprites/player.png"

@onready var sprite: Sprite2D = $Sprite2D

var overworld: Node = null   ## set by Overworld after instancing
var grid_pos: Vector2i = Vector2i.ZERO
var is_moving: bool = false
var facing: String = "down"
## The duration actually used for the most recent _move_to() call —
## exposed so tests can directly verify the Tree movement penalty is
## being applied, without relying on noisy wall-clock timing
## measurements (real-time measurement is subject to frame-pacing
## jitter, especially under a headless/virtualized test runner).
var last_move_duration: float = MOVE_DURATION

func _ready() -> void:
	_apply_class_sprite()
	_update_sprite_frame()

## Per the request: picks the sprite sheet matching the player's own
## career_class — called once at _ready(), and callable again any
## time the character's class might have genuinely changed (a future
## career-change system, once one exists).
func _apply_class_sprite() -> void:
	var path := DEFAULT_SPRITE_PATH
	if GameState.player_character != null and GameState.player_character.career != null:
		path = CLASS_SPRITE_PATHS.get(GameState.player_character.career.career_class, DEFAULT_SPRITE_PATH)
	sprite.texture = load(path)

func _process(_delta: float) -> void:
	if is_moving:
		return
	if overworld and overworld.has_method("is_menu_open") and overworld.is_menu_open():
		return

	if Input.is_action_just_pressed("ui_accept"):
		if overworld:
			overworld.try_interact(grid_pos + FACING_OFFSETS[facing])
		return

	## Per the request: no WASD free-roam on the World Map — every
	## journey there goes through the real Travel system (right-click
	## a destination), which is what actually costs real time, rolls
	## real Wilderness Events, and enforces the real 8-hour travel cap.
	## Free WASD movement bypassed all of that entirely.
	if overworld and overworld.has_method("is_world_map_active") and overworld.is_world_map_active():
		return

	var dir := Vector2i.ZERO
	var new_facing := facing
	if Input.is_action_pressed("move_right"):
		dir = Vector2i(1, 0); new_facing = "right"
	elif Input.is_action_pressed("move_left"):
		dir = Vector2i(-1, 0); new_facing = "left"
	elif Input.is_action_pressed("move_up"):
		dir = Vector2i(0, -1); new_facing = "up"
	elif Input.is_action_pressed("move_down"):
		dir = Vector2i(0, 1); new_facing = "down"

	if dir == Vector2i.ZERO:
		return

	if overworld and overworld.has_method("_cancel_path"):
		overworld._cancel_path()

	if new_facing != facing:
		facing = new_facing
		_update_sprite_frame()
		return   ## first press just turns to face that way, like classic JRPGs

	var target := grid_pos + dir
	if overworld and overworld.is_walkable(target, grid_pos):
		_move_to(target)

func _move_to(target: Vector2i) -> void:
	is_moving = true
	var target_pixel := Vector2(target.x * TILE_SIZE, target.y * TILE_SIZE)
	## Trees are walkable but slow the player down by 25% (a longer
	## tween across the same one tile, not a smaller step) — per the
	## request. overworld.is_tree() also covers the tile the player is
	## MOVING INTO, which is the one that matters here.
	var duration := MOVE_DURATION
	if overworld and overworld.has_method("is_tree") and overworld.is_tree(target):
		duration *= 1.25
	last_move_duration = duration
	var tween := create_tween()
	tween.tween_property(self, "position", target_pixel, duration)
	tween.tween_callback(func() -> void:
		grid_pos = target
		is_moving = false
		moved.emit(grid_pos)
	)

func warp_to(tile: Vector2i) -> void:
	grid_pos = tile
	position = Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)

func _update_sprite_frame() -> void:
	var frame: int = FACING_FRAMES.get(facing, 0)
	sprite.region_rect = Rect2(frame * SPRITE_FRAME_SIZE, 0, SPRITE_FRAME_SIZE, SPRITE_FRAME_SIZE)
