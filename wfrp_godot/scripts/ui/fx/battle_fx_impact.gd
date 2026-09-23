extends Node2D
class_name BattleFxImpact
## A quick expanding-then-fading flash — the "something just landed"
## beat shared by a ranged hit and a magic missile's own impact (see
## battle_grid_view.gd's play_ranged_fx/play_magic_missile_fx). Smaller
## and faster than BattleFxExplosion, which is reserved for AoE spells/
## prayers per the request's own "Area explosion for AoE attack."

const DURATION := 0.22

var radius: float = 16.0
var color: Color = Color(1, 0.9, 0.5)
var _elapsed := 0.0

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= DURATION:
		queue_free()

func _draw() -> void:
	var t: float = clampf(_elapsed / DURATION, 0.0, 1.0)
	var r: float = radius * ease(t, 0.4)
	var fade: float = clampf(1.0 - t, 0.0, 1.0)
	draw_circle(Vector2.ZERO, r, Color(color.r, color.g, color.b, fade * 0.55))
	draw_arc(Vector2.ZERO, r, 0, TAU, 20, Color(1, 1, 1, fade), 2.5)
