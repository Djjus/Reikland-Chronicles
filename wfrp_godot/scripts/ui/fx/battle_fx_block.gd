extends Node2D
class_name BattleFxBlock
## Per the request ("if they defend a shield blocks it"): a quick
## radiating spark burst over the defender's own token, shown INSTEAD
## of a landing slash whenever the defender's own Dodge/Parry actually
## won the opposed Test — see battle_grid_view.gd's play_melee_fx
## (blocked=true) and field_encounter_screen.gd's
## _play_combat_attack_fx (result.hit == false means "avoids the
## blow," matching CombatResolver.AttackResult's own doc comment).

const DURATION := 0.3
const SPOKE_COUNT := 6

var radius: float = 22.0
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
	var extend: float = ease(t, 0.3)   ## fast outward burst, matches a "clang" beat
	var fade: float = clampf(1.0 - t, 0.0, 1.0)
	var color := Color(0.85, 0.85, 0.95, fade)
	for i in range(SPOKE_COUNT):
		var ang: float = TAU * float(i) / float(SPOKE_COUNT)
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(dir * radius * 0.25, dir * radius * (0.4 + 0.9 * extend), color, 3.0)
	## A small bright flash disc at the center sells the "impact" beat
	## even before the spokes finish extending.
	draw_circle(Vector2.ZERO, radius * 0.3 * (1.0 - t), Color(1, 1, 0.85, fade * 0.8))
