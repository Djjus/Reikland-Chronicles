extends Node2D
class_name BattleFxProjectile
## A small glowing bolt that travels in a straight line — used for both
## a ranged weapon's arrow/bolt and a magic missile (same shape,
## different color; see battle_grid_view.gd's play_ranged_fx/
## play_magic_missile_fx). Per the request ("show a projectile either
## hit the target or nothing"): on a miss, it simply keeps going past
## the target square and fades out rather than stopping/impacting —
## the impact flash + floating damage number are spawned separately by
## the caller once travel_time has elapsed (see battle_grid_view.gd),
## so this node's own job is only ever "fly in a straight line, then
## disappear."

const TRAVEL_TIME := 0.28
const MISS_OVERSHOOT := 60.0
const FADE_TIME := 0.15

var start: Vector2 = Vector2.ZERO
var end: Vector2 = Vector2.ZERO
var hit: bool = true
var color: Color = Color(1, 1, 0.6)

var _elapsed := 0.0
var _actual_end: Vector2
var _dir: Vector2
var _fading := false
var _fade_elapsed := 0.0

func _ready() -> void:
	_dir = (end - start).normalized() if end != start else Vector2.RIGHT
	_actual_end = end if hit else end + _dir * MISS_OVERSHOOT
	position = start
	set_process(true)

func _process(delta: float) -> void:
	if _fading:
		_fade_elapsed += delta
		modulate.a = clampf(1.0 - _fade_elapsed / FADE_TIME, 0.0, 1.0)
		if _fade_elapsed >= FADE_TIME:
			queue_free()
		return
	_elapsed += delta
	var t: float = clampf(_elapsed / TRAVEL_TIME, 0.0, 1.0)
	position = start.lerp(_actual_end, t)
	queue_redraw()
	if t >= 1.0:
		_fading = true

func _draw() -> void:
	draw_circle(Vector2.ZERO, 4.5, color)
	draw_circle(Vector2.ZERO, 2.0, Color(1, 1, 1, 0.9))
	## A short trail back toward where it came from — constant
	## direction the whole flight, since it's a straight line.
	draw_line(Vector2.ZERO, -_dir * 16.0, Color(color.r, color.g, color.b, 0.35), 3.0)
