extends Node2D
class_name BattleFxExplosion
## Per the request ("a Area explosion for AoE attack... if its a AoE
## attack hitting multiple show it on all targets that it hit"): one
## instance of this is spawned per affected square by
## battle_grid_view.gd's play_aoe_explosion_fx — a bigger, longer-lived
## burst than BattleFxImpact (the single-target ranged/magic-missile
## flash), reading as a real blast rather than a small hit spark.

const DURATION := 0.5

var radius: float = 34.0
var color: Color = Color(0.95, 0.55, 0.2)
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
	## Fast expand, slower fade — a blast that visibly punches outward
	## before it dissipates, rather than a uniform balloon.
	var r: float = radius * ease(clampf(t / 0.5, 0.0, 1.0), 0.25)
	var fade: float = clampf(1.0 - (t - 0.15) / 0.85, 0.0, 1.0) if t > 0.15 else 1.0
	draw_circle(Vector2.ZERO, r, Color(color.r, color.g, color.b, fade * 0.5))
	draw_arc(Vector2.ZERO, r, 0, TAU, 24, Color(1, 0.85, 0.5, fade), 3.5)
	draw_circle(Vector2.ZERO, r * 0.4, Color(1, 1, 0.8, fade * 0.7))
