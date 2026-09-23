extends Node2D
class_name BattleFxSlash
## The melee "hit landed" animation (see battle_grid_view.gd's
## play_melee_fx) — a single sweeping arc. Per the request ("the sweep
## happens on the attacker... at the point of the icon ring closest to
## the defender"): this now sits on the attacker's own token ring
## facing the defender, rather than centered on the defender's token —
## so, unlike before, its orientation actually matters and can't just
## default to a fixed rightward-ish sweep. Purely procedural
## (draw_arc), matching this project's existing "no external art, draw
## it" convention for the battle map itself (BattleGridView._draw()
## already does the same for the whole grid).

const DURATION := 0.32

var radius: float = 26.0
## Per the request: the attacker->defender angle in degrees, set by
## play_melee_fx before this node enters the tree — the arc sweeps
## outward around this direction instead of a fixed one. Left at 0.0
## (sweeping along +X, this class's original default) for any other
## caller that doesn't set it.
var facing_degrees: float = 0.0
var _elapsed := 0.0
var _start_deg: float = -50.0
var _end_deg: float = 50.0

func _ready() -> void:
	set_process(true)
	rotation_degrees = facing_degrees + randf_range(-15.0, 15.0)   ## a little variety between hits

func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= DURATION:
		queue_free()

func _draw() -> void:
	var t: float = clampf(_elapsed / DURATION, 0.0, 1.0)
	## The sweep itself draws fast (first ~55% of the duration), then
	## the whole arc holds and fades out — reads as a quick slash
	## rather than a slow-motion wipe.
	var sweep_t: float = clampf(t / 0.55, 0.0, 1.0)
	var fade: float = 1.0 if t < 0.55 else clampf(1.0 - (t - 0.55) / 0.45, 0.0, 1.0)
	var cur_end_deg: float = lerpf(_start_deg, _end_deg, sweep_t)
	var color := Color(0.95, 0.95, 1.0, fade)
	var width: float = radius * 0.22
	draw_arc(Vector2.ZERO, radius, deg_to_rad(_start_deg), deg_to_rad(cur_end_deg), 16, color, width, true)
	## A thinner, brighter core line on top reads as "steel" better than
	## one flat-colored arc alone.
	draw_arc(Vector2.ZERO, radius, deg_to_rad(_start_deg), deg_to_rad(cur_end_deg), 16, Color(1, 1, 1, fade * 0.85), width * 0.35, true)
